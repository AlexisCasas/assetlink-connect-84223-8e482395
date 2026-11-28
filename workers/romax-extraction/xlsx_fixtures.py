"""Generate only synthetic OOXML workbooks; no external files or network."""
import io
import zipfile
from xml.sax.saxutils import escape,quoteattr
from xlsx_reader import NS,REL,PKG,CT

def cell(ref,value="",typ="inlineStr",style=None,formula=None):
    attrs=' r='+quoteattr(ref)+' t='+quoteattr(typ)
    if style is not None: attrs+=' s='+quoteattr(str(style))
    f="" if formula is None else "<f>"+escape(formula)+"</f>"
    v=("<is><t>"+escape(value)+"</t></is>") if typ=="inlineStr" else ("<v>"+escape(value)+"</v>" if value!="" else "")
    return "<c"+attrs+">"+f+v+"</c>"

def row(n,*cells,hidden=False):
    return '<row r="%s"%s>'%(n,' hidden="1"' if hidden else "")+"".join(cells)+"</row>"

def sheet(rows,extra=""):
    return '<worksheet xmlns="'+NS+'"><sheetData>'+''.join(rows)+'</sheetData>'+extra+'</worksheet>'

def head(n=1):
    return row(n,cell("A"+str(n),"Código"),cell("B"+str(n),"Descripción"),cell("C"+str(n),"Unidad"),cell("D"+str(n),"Metrado"),cell("E"+str(n),"Especificaciones"),cell("F"+str(n),"Precio"))

def workbook(sheets=None,mutate=None,compression=zipfile.ZIP_DEFLATED):
    if sheets is None:
        sheets=[("Metrados",sheet([
            head(),row(2,cell("A2","001"),cell("B2","Inspección ficticia"),cell("C2","und"),cell("D2","12.50","n"),cell("E2","Especificación ficticia"),cell("F2","9999","n")),
            row(3,cell("A3","01.02"),cell("B3","Informe ficticio"),cell("C3","glb"),cell("D3","1,250")),
            row(4,cell("A4","3","n",style=1),cell("B4","Fórmula con caché"),cell("C4","und"),cell("D4","4","n",formula="2+2")),
            row(5,cell("B5","Fórmula sin caché"),cell("C5","und"),cell("D5","","n",formula="SUM(D2:D4)")),
            row(6,cell("B6","Fila oculta"),cell("C6","m"),cell("D6","2","n"),hidden=True),
            row(7,cell("B7","Subtotal"),cell("D7","100","n")),
            row(8,cell("B8","Celda combinada"),cell("C8","und"),cell("D8","1","n")),
            row(9,cell("B9","Descripción compartida","s"),cell("C9","und"),cell("D9","3","n")),
        ],'<mergeCells count="1"><mergeCell ref="B8:C8"/></mergeCells>'),"visible"),
        ("Segunda",sheet([head(),row(2,cell("B2","Otro trabajo ficticio"),cell("C2","m2"),cell("D2","7","n"))]),"visible")]
    parts={
        "[Content_Types].xml":'<Types xmlns="'+CT+'"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/><Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/>'+''.join('<Override PartName="/xl/worksheets/sheet%d.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'%i for i in range(1,len(sheets)+1))+'</Types>',
        "_rels/.rels":'<Relationships xmlns="'+PKG+'"><Relationship Id="rId1" Type="'+REL+'/officeDocument" Target="xl/workbook.xml"/></Relationships>',
        "xl/workbook.xml":'<workbook xmlns="'+NS+'" xmlns:r="'+REL+'"><sheets>'+''.join('<sheet name='+quoteattr(name)+' sheetId="%d" r:id="rId%d" state="%s"/>'%(i,i,state) for i,(name,_,state) in enumerate(sheets,1))+'</sheets></workbook>',
        "xl/_rels/workbook.xml.rels":'<Relationships xmlns="'+PKG+'">'+''.join('<Relationship Id="rId%d" Type="%s/worksheet" Target="worksheets/sheet%d.xml"/>'%(i,REL,i) for i in range(1,len(sheets)+1))+'<Relationship Id="sty" Type="'+REL+'/styles" Target="styles.xml"/><Relationship Id="str" Type="'+REL+'/sharedStrings" Target="sharedStrings.xml"/></Relationships>',
        "xl/styles.xml":'<styleSheet xmlns="'+NS+'"><numFmts count="1"><numFmt numFmtId="164" formatCode="0000"/></numFmts><cellXfs count="2"><xf numFmtId="0"/><xf numFmtId="164"/></cellXfs></styleSheet>',
        "xl/sharedStrings.xml":'<sst xmlns="'+NS+'"><si><t>Texto compartido</t></si></sst>',
    }
    for i,(_,content,_) in enumerate(sheets,1): parts["xl/worksheets/sheet%d.xml"%i]=content
    # shared string cell holds index, not text
    for k in parts:
        if k.startswith("xl/worksheets/"): parts[k]=parts[k].replace("<v>Descripción compartida</v>","<v>0</v>")
    if mutate: mutate(parts)
    b=io.BytesIO()
    with zipfile.ZipFile(b,"w",compression=compression) as z:
        for name,content in parts.items():
            # deterministic fixtures and hashes
            info=zipfile.ZipInfo(name,date_time=(2026,1,1,0,0,0))
            info.compress_type=compression
            z.writestr(info,content)
    return b.getvalue()
