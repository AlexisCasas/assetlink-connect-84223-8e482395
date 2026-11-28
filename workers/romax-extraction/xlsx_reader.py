"""Restricted OOXML reader. Runs inside the isolated worker, never recalculates."""
import io
import json
import posixpath
import re
import unicodedata
import zipfile
import xml.etree.ElementTree as ET
from xml.parsers import expat

MAX_FILE=10*1024*1024
MAX_EXPANDED=40*1024*1024
MAX_PART=8*1024*1024
NS="http://schemas.openxmlformats.org/spreadsheetml/2006/main"
REL="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
PKG="http://schemas.openxmlformats.org/package/2006/relationships"
CT="http://schemas.openxmlformats.org/package/2006/content-types"
MIME="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
T=lambda name: "{"+NS+"}"+name
CELL=re.compile(r"([A-Z]{1,3})([1-9][0-9]{0,6})\Z")
DECIMAL=re.compile(r"[0-9]{1,12}(?:\.[0-9]{1,8})?\Z")
PART=re.compile(r"(?:\[Content_Types\]\.xml|_rels/\.rels|docProps/(?:core|app)\.xml|xl/(?:workbook|styles|sharedStrings)\.xml|xl/_rels/workbook\.xml\.rels|xl/theme/theme[1-9][0-9]*\.xml|xl/worksheets/sheet[1-9][0-9]*\.xml)\Z")
REL_TYPES={REL+"/"+k for k in ("officeDocument","worksheet","styles","sharedStrings","theme","extended-properties")} | {PKG+"/metadata/core-properties"}
class Reject(Exception):
    def __init__(self, reason):
        self.reason=reason
        super().__init__(reason)

def fail(reason="unsafe_structure"):
    raise Reject(reason)

def xml(data):
    # Expat rejects DTD/entity declarations in every encoding; no external resolver.
    depth=0
    count=0
    p=expat.ParserCreate()
    def start(*args):
        nonlocal depth,count
        depth+=1; count+=1
        if depth>64 or count>180000: fail("limit")
    def end(*args):
        nonlocal depth
        depth-=1
    p.StartElementHandler=start
    p.EndElementHandler=end
    p.StartDoctypeDeclHandler=lambda *args: fail()
    p.EntityDeclHandler=lambda *args: fail()
    p.ExternalEntityRefHandler=lambda *args: fail()
    try:
        p.Parse(data,True)
        return ET.fromstring(data)
    except (expat.ExpatError,ET.ParseError,ValueError,LookupError):
        fail()

def read_parts(data):
    if not isinstance(data,bytes) or len(data)>MAX_FILE: fail("limit")
    if not data.startswith(b"PK\x03\x04"): fail("unsupported_format")
    try:
        with zipfile.ZipFile(io.BytesIO(data)) as z:
            infos=z.infolist()
            if len(infos)>1000: fail("limit")
            seen=set(); total=0; parts={}
            for i in infos:
                name=i.filename
                if i.flag_bits&1: fail("encrypted")
                if name in seen or not PART.fullmatch(name) or i.is_dir() or i.orig_filename!=name:
                    fail()
                seen.add(name)
                if i.compress_type not in (zipfile.ZIP_STORED,zipfile.ZIP_DEFLATED) or (i.external_attr>>16)&0o170000==0o120000:
                    fail()
                if i.file_size>MAX_PART or i.file_size>100*max(1,i.compress_size) or total+i.file_size>MAX_EXPANDED:
                    fail("limit")
                buf=bytearray()
                with z.open(i) as f:
                    while True:
                        chunk=f.read(65536)
                        if not chunk: break
                        if len(buf)+len(chunk)>i.file_size or total+len(buf)+len(chunk)>MAX_EXPANDED: fail("limit")
                        buf.extend(chunk)
                if len(buf)!=i.file_size: fail()
                total+=len(buf)
                parts[name]=bytes(buf)
            return parts
    except (zipfile.BadZipFile,RuntimeError,NotImplementedError,OSError,EOFError):
        fail()

def coord(ref):
    m=CELL.fullmatch(ref or "")
    if not m: fail()
    n=0
    for c in m[1]: n=n*26+ord(c)-64
    r=int(m[2])
    if n>16384 or r>1048576: fail()
    return n,r

def range_coord(ref):
    bits=ref.split(":")
    if len(bits) not in (1,2): fail()
    a=coord(bits[0]); b=coord(bits[-1])
    if a[0]>b[0] or a[1]>b[1]: fail()
    return a,b

def resolve(base,target):
    if not target or any(c in target for c in "\\%?#:") or ".." in target.split("/"): fail()
    path=target[1:] if target.startswith("/") else posixpath.join(base,target)
    if not PART.fullmatch(path): fail()
    return path

def relationships(parts,name,base):
    node=xml(parts[name])
    if node.tag!="{"+PKG+"}Relationships": fail()
    out={}
    for r in node:
        if r.tag!="{"+PKG+"}Relationship" or r.get("TargetMode","Internal")!="Internal" or r.get("Type") not in REL_TYPES: fail()
        rid=r.get("Id"); path=resolve(base,r.get("Target"))
        if not rid or rid in out or path not in parts: fail()
        out[rid]=(r.get("Type"),path)
    return out

def rich(node):
    if node is None: return ""
    # Rich text runs preserve actual text, not phonetic annotations or XML markup.
    out=[]
    for t in node:
        if t.tag==T("t"): out.append(t.text or "")
        elif t.tag==T("r"):
            v=t.find(T("t"))
            if v is not None: out.append(v.text or "")
    return "".join(out)

def normalize(s):
    return " ".join("".join(c for c in unicodedata.normalize("NFKD",s.lower()) if not unicodedata.combining(c)).split())

HEADERS={
 "code":{"codigo","item","nro","n°","nº","partida","cod."},
 "description":{"descripcion","descripcion de partida","descripcion del trabajo","actividad","trabajo","servicio","concepto"},
 "quantity":{"cantidad","metrado","cant.","cant","qty"},
 "unit":{"unidad","und","u.m.","um","unid."},
 "spec":{"especificacion","especificaciones","detalle tecnico","observaciones tecnicas"},
}
def headers(cells):
    h={}
    for col,c in cells.items():
        if c["formula"] is not None: continue
        key=next((k for k,v in HEADERS.items() if normalize(c["value"]) in v),None)
        if key:
            if key in h: return None
            h[key]=col
    return h if "description" in h and ("quantity" in h or "unit" in h) else None

def extract(data):
    try:
        parts=read_parts(data)
        required={"[Content_Types].xml","_rels/.rels","xl/workbook.xml","xl/_rels/workbook.xml.rels"}
        if not required<=parts.keys(): fail("unsupported_format")
        # Validate every allowed XML part before using any data. No embedded binaries.
        for name,payload in parts.items():
            root=xml(payload)
            if name=="[Content_Types].xml":
                if root.tag!="{"+CT+"}Types": fail()
                overrides={}
                for x in root:
                    content=x.get("ContentType","")
                    if x.tag not in {"{"+CT+"}Override","{"+CT+"}Default"} or any(k in content.lower() for k in ("macroenabled","vba","activex","oleobject")): fail()
                    if x.tag=="{"+CT+"}Override":
                        part=x.get("PartName","").lstrip("/")
                        if part not in parts or part in overrides: fail()
                        overrides[part]=content
                if overrides.get("xl/workbook.xml")!="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml": fail("unsupported_format")
            if name.startswith("xl/worksheets/"):
                for e in root.iter():
                    if e.tag in {T(k) for k in ("hyperlinks","drawing","legacyDrawing","oleObjects","controls","extLst","externalReferences","tableParts","picture","conditionalFormatting","dataValidations")}:
                        fail()
        roots=relationships(parts,"_rels/.rels","")
        if [p for t,p in roots.values() if t==REL+"/officeDocument"]!=["xl/workbook.xml"]: fail()
        rels=relationships(parts,"xl/_rels/workbook.xml.rels","xl")
        wb=xml(parts["xl/workbook.xml"])
        if wb.tag!=T("workbook") or any(wb.find(T(x)) is not None for x in ("externalReferences","definedNames","extLst")): fail()
        sheets=wb.find(T("sheets"))
        if sheets is None or not len(sheets): fail("no_text")
        if len(sheets)>20: fail("limit")
        shared=[]
        if "xl/sharedStrings.xml" in parts:
            ss=xml(parts["xl/sharedStrings.xml"])
            if ss.tag!=T("sst") or len(ss)>50000: fail("limit")
            shared=[rich(x) for x in ss if x.tag==T("si")]
            if sum(len(x) for x in shared)>2000000: fail("limit")
        formats={0:"0"}
        xfs=[0]
        if "xl/styles.xml" in parts:
            styles=xml(parts["xl/styles.xml"])
            if styles.tag!=T("styleSheet"): fail()
            nf=styles.find(T("numFmts"))
            if nf is not None:
                for x in nf:
                    key=x.get("numFmtId","")
                    if not key.isdecimal(): fail()
                    formats[int(key)]=x.get("formatCode","")
            xf=styles.find(T("cellXfs"))
            if xf is not None:
                xfs=[]
                for x in xf:
                    key=x.get("numFmtId","0")
                    if not key.isdecimal(): fail()
                    xfs.append(int(key))
        evidence=[]; candidates=[]; partial=False; reason="unsupported_format"; chars=0; cells_count=0
        used=set(); names=set()
        def add(loc,excerpt):
            nonlocal chars,partial,reason
            if len(excerpt)>4000 or chars+len(excerpt)>200000 or len(evidence)>=1000:
                partial=True;reason="limit";return None
            evidence.append({"location":loc,"excerpt":excerpt});chars+=len(excerpt);return len(evidence)
        for ix,s in enumerate(sheets,1):
            name=s.get("name","")
            if not 1<=len(name)<=31 or name.casefold() in names or s.get("state","visible") not in ("visible","hidden","veryHidden"): fail()
            names.add(name.casefold())
            rid=s.get("{"+REL+"}id")
            if rid not in rels or rels[rid][0]!=REL+"/worksheet": fail()
            path=rels[rid][1]
            if path in used: fail()
            used.add(path)
            sheet=xml(parts[path])
            if sheet.tag!=T("worksheet"): fail()
            merged=[]
            merges=sheet.find(T("mergeCells"))
            if merges is not None:
                if len(merges)>1000: fail("limit")
                merged=[range_coord(x.get("ref","")) for x in merges]
            hidden_sheet=s.get("state","visible")!="visible"
            rows=sheet.find(T("sheetData"))
            if rows is None: fail()
            head=None; found_header=False; previous=0
            for row in rows:
                rn=row.get("r","")
                if row.tag!=T("row") or not rn.isdecimal() or len(rn)>7 or not previous<int(rn)<=1048576: fail()
                previous=int(rn); row_num=previous; cells={}; refs=set(); columns={}
                for c in row:
                    if c.tag!=T("c"): fail()
                    ref=c.get("r",""); col,rr=coord(ref)
                    if rr!=row_num or col in refs: fail()
                    refs.add(col)
                    typ=c.get("t","n"); v=c.find(T("v")); f=c.find(T("f"))
                    raw=v.text if v is not None and v.text is not None else ""
                    formula=None if f is None else (f.text or "")
                    style=c.get("s","0")
                    if not style.isdecimal() or len(style)>6 or int(style)>=len(xfs): fail()
                    fmt=xfs[int(style)]
                    if typ=="s":
                        if not raw.isdecimal() or len(raw)>6 or int(raw)>=len(shared): fail()
                        raw=shared[int(raw)]
                    elif typ=="inlineStr": raw=rich(c.find(T("is")))
                    elif typ not in ("n","str","b","e","d"): fail()
                    if not raw and formula is None: continue
                    cells_count+=1
                    if cells_count>50000: fail("limit")
                    cells[col]={"ref":ref,"value":raw,"formula":formula,"type":typ,"format":fmt}
                if not cells: continue
                cells=dict(sorted(cells.items()))
                loc={"sheet":name,"sheet_index":ix,"cells":next(iter(cells.values()))["ref"]+":"+list(cells.values())[-1]["ref"]}
                if len(cells)==1: loc["cells"]=next(iter(cells.values()))["ref"]
                # JSON string is literal evidence, not executable spreadsheet/HTML.
                excerpt=json.dumps([{"cell":x["ref"],"raw":x["value"],**({"formula":x["formula"],"cached":x["value"] or None} if x["formula"] is not None else {})} for x in cells.values()],ensure_ascii=False,separators=(",",":"))
                ordinal=add(loc,excerpt)
                if ordinal is None: continue
                new=headers(cells)
                if new is not None:
                    head=new;found_header=True;continue
                if not head: continue
                desc=cells.get(head["description"])
                if not desc or not desc["value"].strip():
                    partial=True;continue
                if len(candidates)>=500:
                    partial=True;reason="limit";continue
                if desc["formula"] is not None or len(desc["value"])>2000:
                    partial=True;continue
                get=lambda key: cells.get(head.get(key),{})
                code=get("code"); qty=get("quantity"); unit=get("unit"); spec=get("spec")
                flags=[]
                if hidden_sheet:
                    partial=True;continue  # preserve evidence; no hidden sheet candidates
                if row.get("hidden") in ("1","true"): flags.append("hidden_row")
                if any(a[1]<=row_num<=b[1] and any(a[0]<=c<=b[0] for c in head.values()) for a,b in merged): flags.append("merged_cell")
                label=normalize(desc["value"])
                if re.match(r"^(?:sub\s*total|total|igv|importe)(?:\b|$)",label):
                    flags.append("subtotal")
                raw=qty.get("value","")
                value=None
                if qty.get("formula") is not None:
                    flags.append("cached_formula" if raw else "missing_formula_cache")
                elif raw:
                    # Numeric XML is locale-independent, but text decimals are only accepted
                    # if unambiguous integer; decimal/group separators in text need review.
                    numeric=qty.get("type")=="n" and qty.get("format") in {0,1,2,3,4}
                    text_integer=qty.get("type") in {"s","str","inlineStr"} and re.fullmatch(r"[0-9]{1,12}",raw)
                    if DECIMAL.fullmatch(raw) and (numeric or text_integer): value=raw
                    else: flags.append("ambiguous_number")
                code_raw=code.get("value","")
                fmt=formats.get(code.get("format"),"")
                if code.get("type")=="n" and re.fullmatch(r"0{2,30}",fmt) and code_raw.isdecimal():
                    code_raw=code_raw.zfill(len(fmt))
                if re.fullmatch(r"\d+(?:\.\d+)+",code_raw): flags.append("hierarchy")
                if not unit.get("value"): flags.append("missing_unit")
                if "subtotal" in flags or "merged_cell" in flags: value=None
                if any(len(x)>100 for x in (raw,code_raw,unit.get("value",""))) or len(spec.get("value",""))>2000:
                    partial=True;reason="limit";continue
                if any(x.get("formula") is not None for x in (code,unit,spec)):
                    partial=True;continue
                proposal={"description":desc["value"],"quantity_raw":raw or None,"quantity":value,"unit_raw":unit.get("value") or None,"code_raw":code_raw or None,"specification":spec.get("value") or None,"flags":flags}
                candidates.append({"kind":"conflict" if "subtotal" in flags else "item","evidence_ordinal":ordinal,"proposal":proposal})
            if not found_header: partial=True
        if set(p for t,p in rels.values() if t==REL+"/worksheet")!=used or set(p for p in parts if p.startswith("xl/worksheets/"))!=used: fail()
        if not evidence: return result("unsupported","no_text")
        if not candidates: partial=True
        return result("partial" if partial else "succeeded",reason if partial else None,evidence,candidates)
    except Reject as e:
        return result("unsupported",e.reason)
    except (KeyError,ValueError,TypeError,OverflowError,RecursionError):
        return result("unsupported","unsafe_structure")

def result(status,reason,evidence=None,candidates=None):
    return {"status":status,"reason":reason,"evidence":evidence or [],"candidates":candidates or []}
