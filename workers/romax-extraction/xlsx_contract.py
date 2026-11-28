"""Independent broker-side validation of bounded XLSX result, no document parsing."""
import json
import re
from broker import Failure, MAX_OUTPUT

FLAGS={"ambiguous_number","cached_formula","missing_formula_cache","hidden_row","merged_cell","subtotal","header","hierarchy","uncertain_table","conflict","missing_unit","partial"}
REF=re.compile(r"([A-Z]{1,3})([1-9][0-9]{0,6})\Z")
NUM=re.compile(r"[0-9]{1,12}(?:\.[0-9]{1,8})?\Z")
def point(s):
    m=REF.fullmatch(s)
    if not m: raise ValueError()
    c=0
    for x in m[1]: c=c*26+ord(x)-64
    r=int(m[2])
    if c>16384 or r>1048576: raise ValueError()
    return c,r
def unique(pairs):
    d={}
    for k,v in pairs:
        if k in d: raise ValueError()
        d[k]=v
    return d
def checked(raw):
    try:
        if not isinstance(raw,bytes) or len(raw)>MAX_OUTPUT: raise ValueError()
        x=json.loads(raw.decode("utf-8"),object_pairs_hook=unique,parse_constant=lambda _: (_ for _ in ()).throw(ValueError()))
        if type(x)!=dict or set(x)!={"status","reason","evidence","candidates"}: raise ValueError()
        s,r,e,c=(x[k] for k in ("status","reason","evidence","candidates"))
        if type(e)!=list or type(c)!=list or len(e)>1000 or len(c)>500: raise ValueError()
        if s=="unsupported":
            if r not in ("limit","no_text","unsafe_structure","encrypted","unsupported_format") or e or c: raise ValueError()
        elif s=="succeeded":
            if r is not None or not e or not c: raise ValueError()
        elif s=="partial":
            if r not in ("limit","unsupported_format") or not e: raise ValueError()
        else: raise ValueError()
        total=0
        for b in e:
            if type(b)!=dict or set(b)!={"location","excerpt"}: raise ValueError()
            loc=b["location"]; text=b["excerpt"]
            if type(text)!=str or not 1<=len(text)<=4000: raise ValueError()
            total+=len(text)
            if type(loc)!=dict or set(loc)!={"sheet","sheet_index","cells"} or type(loc["sheet"])!=str or not 1<=len(loc["sheet"])<=31 or type(loc["sheet_index"])!=int or not 1<=loc["sheet_index"]<=20: raise ValueError()
            refs=loc["cells"].split(":")
            if len(refs) not in (1,2): raise ValueError()
            a,b=point(refs[0]),point(refs[-1])
            if a[0]>b[0] or a[1]!=b[1]: raise ValueError()
        if total>200000: raise ValueError()
        for a in c:
            if type(a)!=dict or set(a)!={"kind","evidence_ordinal","proposal"} or a["kind"] not in ("item","conflict") or type(a["evidence_ordinal"])!=int or not 1<=a["evidence_ordinal"]<=len(e): raise ValueError()
            q=a["proposal"]
            if type(q)!=dict or set(q)!={"description","quantity_raw","quantity","unit_raw","code_raw","specification","flags"} or type(q["description"])!=str or not 1<=len(q["description"].strip())<=2000: raise ValueError()
            for k in ("quantity_raw","unit_raw","code_raw","specification"):
                if q[k] is not None and (type(q[k])!=str or len(q[k])>(2000 if k=="specification" else 100)): raise ValueError()
            if q["quantity"] is not None and (type(q["quantity"])!=str or not NUM.fullmatch(q["quantity"])): raise ValueError()
            if type(q["flags"])!=list or len(q["flags"])>12 or any(type(f)!=str or f not in FLAGS for f in q["flags"]): raise ValueError()
            if set(q["flags"])&{"ambiguous_number","cached_formula","missing_formula_cache","subtotal","merged_cell"} and q["quantity"] is not None: raise ValueError()
            if a["kind"]=="conflict" and "subtotal" not in q["flags"]: raise ValueError()
        return x
    except (ValueError,TypeError,KeyError,AttributeError,RecursionError,UnicodeError):
        raise Failure("worker_error") from None
