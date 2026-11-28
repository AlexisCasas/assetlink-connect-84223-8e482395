import hashlib
import json
import os
import subprocess
import unittest
import uuid
import zipfile
from broker import Failure, Scope, _run_container
from xlsx_broker import XlsxQABroker, PARSER, CONFIG, MIME
from xlsx_contract import checked
from xlsx_reader import extract, result
from xlsx_fixtures import workbook, sheet, row, cell, head

def encoded(x):
    return json.dumps(x,ensure_ascii=True).encode()

class ReaderTests(unittest.TestCase):
    def test_structured_metrados(self):
        r=extract(workbook())
        self.assertEqual(r["status"],"succeeded",r["reason"])
        p=[x["proposal"] for x in r["candidates"]]
        self.assertEqual(len(p),9)
        self.assertEqual(p[0]["code_raw"],"001")
        self.assertEqual(p[0]["quantity"],"12.50")
        self.assertEqual(p[0]["unit_raw"],"und")
        self.assertEqual(p[0]["specification"],"Especificación ficticia")
        self.assertNotIn("9999",json.dumps(p))
        self.assertEqual(p[1]["quantity_raw"],"1,250")
        self.assertIsNone(p[1]["quantity"])
        self.assertIn("ambiguous_number",p[1]["flags"])
        self.assertIn("hierarchy",p[1]["flags"])
        self.assertEqual(p[2]["code_raw"],"0003")
        self.assertIsNone(p[2]["quantity"])
        self.assertIn("cached_formula",p[2]["flags"])
        self.assertIn("missing_formula_cache",p[3]["flags"])
        self.assertIn("hidden_row",p[4]["flags"])
        self.assertIn("subtotal",p[5]["flags"])
        self.assertIsNone(p[5]["quantity"])
        self.assertEqual(r["candidates"][5]["kind"],"conflict")
        self.assertIn("merged_cell",p[6]["flags"])
        self.assertIsNone(p[6]["quantity"])
        self.assertEqual(p[7]["description"],"Texto compartido")
        self.assertEqual(p[8]["quantity"],"7")
        e=r["evidence"][r["candidates"][2]["evidence_ordinal"]-1]
        self.assertEqual(e["location"],{"sheet":"Metrados","sheet_index":1,"cells":"A4:D4"})
        self.assertIn('"formula":"2+2"',e["excerpt"])
        self.assertEqual(checked(encoded(r)),r)

    def test_deterministic(self):
        data=workbook()
        self.assertEqual(extract(data),extract(data))

    def test_no_header_partial(self):
        data=workbook([("Unknown",sheet([row(1,cell("A1","Unknown data"))]),"visible")])
        r=extract(data)
        self.assertEqual(r["status"],"partial")
        self.assertEqual(r["candidates"],[])
        self.assertEqual(len(r["evidence"]),1)

    def test_hidden_sheet_never_proposes(self):
        data=workbook([("Hidden",sheet([head(),row(2,cell("B2","Secret synthetic"),cell("D2","8","n"))]),"hidden")])
        r=extract(data)
        self.assertEqual(r["status"],"partial")
        self.assertEqual(r["candidates"],[])

    def test_header_ambiguity_stops_old_mapping(self):
        rows=[head(),row(2,cell("B2","First"),cell("C2","und"),cell("D2","2","n")),
              row(3,cell("B3","Descripción"),cell("C3","Cantidad"),cell("D3","Metrado")),
              row(4,cell("B4","Ambiguous"),cell("C4","20","n"),cell("D4","30","n"))]
        r=extract(workbook([("M",sheet(rows),"visible")]))
        self.assertEqual(r["status"],"partial")
        self.assertEqual(len(r["candidates"]),1)
        self.assertEqual(len(r["evidence"]),4)

    def test_literal_service_not_confused_with_header(self):
        r=extract(workbook([("M",sheet([head(),row(2,cell("B2","Servicio"),cell("C2","und"),cell("D2","3","n"))]),"visible")]))
        self.assertEqual(r["status"],"succeeded")
        self.assertEqual(r["candidates"][0]["proposal"]["quantity"],"3")

    def test_blank_quantity_not_invented(self):
        r=extract(workbook([("M",sheet([head(),row(2,cell("B2","Work"),cell("C2","und"))]),"visible")]))
        self.assertIsNone(r["candidates"][0]["proposal"]["quantity"])

    def test_path_and_active_parts_denied(self):
        for name in ("../evil.xml","xl/vbaProject.bin","xl/embeddings/oleObject1.bin","xl/externalLinks/externalLink1.xml","xl/worksheets/_rels/sheet1.xml.rels"):
            with self.subTest(name=name):
                self.assertEqual(extract(workbook(mutate=lambda p:p.update({name:"x"})))["reason"],"unsafe_structure")

    def test_external_relationship_denied(self):
        def mutate(p):
            p["xl/_rels/workbook.xml.rels"]=p["xl/_rels/workbook.xml.rels"].replace('Target="worksheets/sheet1.xml"','TargetMode="External" Target="https://example.invalid/x"')
        self.assertEqual(extract(workbook(mutate=mutate))["reason"],"unsafe_structure")

    def test_dtd_utf8_utf16_denied(self):
        for encoding in ("utf-8","utf-16"):
            def mutate(p):
                p["xl/sharedStrings.xml"]=('<?xml version="1.0"?><!DOCTYPE sst [<!ENTITY x "evil">]>'+p["xl/sharedStrings.xml"]).encode(encoding)
            self.assertEqual(extract(workbook(mutate=mutate))["reason"],"unsafe_structure")

    def test_zip_expansion_limit(self):
        data=workbook(mutate=lambda p:p.update({"xl/theme/theme1.xml":"x"*1000000}))
        self.assertEqual(extract(data)["reason"],"limit")

    def test_bad_format_and_out_of_range(self):
        self.assertEqual(extract(b"%PDF-1.7")["reason"],"unsupported_format")
        bad=workbook([("M",sheet([row(1,cell("XFE1","x"))]),"visible")])
        self.assertEqual(extract(bad)["reason"],"unsafe_structure")

    def test_candidate_limit_partial(self):
        rows=[head()]+[row(n,cell("B"+str(n),"Work "+str(n)),cell("D"+str(n),"1","n")) for n in range(2,504)]
        r=extract(workbook([("M",sheet(rows),"visible")]))
        self.assertEqual(r["status"],"partial")
        self.assertEqual(r["reason"],"limit")
        self.assertEqual(len(r["candidates"]),500)
        self.assertEqual(checked(encoded(r)),r)

    def test_contract_rejects_forgery(self):
        r=extract(workbook())
        r["candidates"][2]["proposal"]["quantity"]="4"
        with self.assertRaises(Failure): checked(encoded(r))
        r=extract(workbook());r["evidence"][0]["location"]["cells"]="XFE1"
        with self.assertRaises(Failure): checked(encoded(r))
        r=extract(workbook());r["candidates"][0]["proposal"]["price"]="100"
        with self.assertRaises(Failure): checked(encoded(r))

def synthetic(data):
    ids=[str(uuid.uuid4()) for _ in range(6)]
    scope=Scope(*ids[:4])
    source={"attempt":ids[4],"path":"/".join(("quarantine",scope.org,scope.opportunity,scope.document,ids[4])),
            "hash":hashlib.sha256(data).hexdigest(),"size":len(data),"mime":MIME}
    claim={"status":"running","job_id":scope.job,"lease":ids[5],"parser":PARSER,"config":CONFIG,"source":source}
    class Control:
        calls=[]
        def claim(self,s):
            assert s==scope
            self.calls.append("claim")
            return claim
        def finish(self,s,l,h,r):
            assert s==scope and l==ids[5] and h==source["hash"]
            self.calls.append(r)
            return r
    class Storage:
        calls=[]
        def chunks(self,bucket,path,deadline):
            assert bucket=="romax-request-attachments" and path==source["path"]
            self.calls.append(path)
            for i in range(0,len(data),1024): yield data[i:i+1024]
    return scope,claim,Control(),Storage()

class DockerReaderTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.image=os.environ["ROMAX_QA_XLSX_IMAGE_ID"]

    def test_real_container_and_broker(self):
        # Large, incompressible-to-pipe test payload, entirely synthetic.
        data=workbook(mutate=lambda p:p.update({"docProps/core.xml":"<core>"+"x"*70000+"</core>"}),compression=zipfile.ZIP_STORED)
        self.assertGreater(len(data),65536)
        scope,claim,control,storage=synthetic(data)
        r=XlsxQABroker(control,storage,self.image,[claim["source"]["hash"]]).execute(scope,enabled=True)
        self.assertEqual(r,extract(data))
        self.assertEqual(r["status"],"succeeded")
        self.assertEqual(len(control.calls),2)

    def test_real_container_rejects_unsafe_structure(self):
        data=workbook(mutate=lambda p:p.update({"xl/vbaProject.bin":"fake"}))
        scope,claim,control,storage=synthetic(data)
        r=XlsxQABroker(control,storage,self.image,[claim["source"]["hash"]]).execute(scope,enabled=True)
        self.assertEqual(r,result("unsupported","unsafe_structure"))

    def test_no_live_adapter_or_unapproved_digest(self):
        data=workbook()
        scope,claim,control,storage=synthetic(data)
        b=XlsxQABroker(control,storage,self.image,[])
        with self.assertRaises(Failure): b.execute(scope)
        self.assertEqual(control.calls,[])
        with self.assertRaises(Failure): b.execute(scope,enabled=True)
        self.assertEqual(storage.calls,[])
        self.assertEqual(control.calls,["claim"])

    def test_no_orphan(self):
        self.assertEqual(subprocess.check_output(["docker","ps","-aq","--filter","name=romax-qa-"],text=True).strip(),"")

if __name__=="__main__":
    unittest.main(verbosity=2)
