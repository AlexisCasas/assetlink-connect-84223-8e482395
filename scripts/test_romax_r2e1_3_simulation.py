import importlib.util
import tempfile
import unittest
from pathlib import Path
from datetime import datetime
from openpyxl import Workbook

SCRIPT = Path(__file__).with_name("romax_r2e1_3_simulation.py")
spec = importlib.util.spec_from_file_location("romax_sim", SCRIPT)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class SimulationTests(unittest.TestCase):
    def workbook(self, path):
        wb = Workbook()
        m = wb.active
        m.title = "Matriz materiales"
        for c, v in enumerate(["Código", "Categoría", "Subcategoría", "Material", "Unidad de compra", "Costo mercado con IGV", "Estado de vigencia", "Estado del registro", "Aprobado por"], 1): m.cell(8, c, v)
        rows = [
            ["MAT-0001", "Electricidad", None, "Cable test", "ML", 10, "Vigente", "Pendiente", None],
            ["MAT-0002", None, None, "Thinner test", "GL", None, "Actualizar", "Pendiente", None],
            ["MAT-0003", None, None, "Duplicado test", "UND", None, "Actualizar", "Pendiente", None],
            ["MAT-0004", None, None, "Duplicado test", "UND", None, "Actualizar", "Pendiente", None],
        ]
        for ri, row in enumerate(rows, 9):
            for ci, v in enumerate(row, 1): m.cell(ri, ci, v)
        a = wb.create_sheet("Dados de Alta")
        for c, v in enumerate(["Código", "Categoría", "Subcategoría", "Material propuesto", "Unidad", "Validación Logística", "Decisión líder comercial"], 1): a.cell(3, c, v)
        rows = [
            ["MAT-0001", "Electricidad", None, "Cable test", "ML", "Pendiente", "Pendiente"],
            ["MAT-0002", "Pisos", None, "Thinner test", "GL", "Pendiente", "Pendiente"],
            ["MAT-0003", "Otros", None, "Duplicado test", "UND", "Pendiente", "Pendiente"],
            ["MAT-0004", "Otros", None, "Duplicado test", "UND", "Pendiente", "Pendiente"],
        ]
        for ri, row in enumerate(rows, 4):
            for ci, v in enumerate(row, 1): a.cell(ri, ci, v)
        h = wb.create_sheet("Historial precios")
        for c, v in enumerate(["Registro", "Código material", "Fecha consulta", "Vigencia (días)", "Evidencia / enlace", "Validado por", "Registrado por"], 1): h.cell(4, c, v)
        for c, v in enumerate(["HIS-1", "MAT-0001", datetime(2026, 1, 1), 120, "private", None, None], 1): h.cell(5, c, v)
        t = wb.create_sheet("Categorías")
        for c, v in enumerate(["Categoría", "Subcategoría", "Código categoría", "Código subcategoría"], 1): t.cell(1, c, v)
        for ri, row in enumerate([["Electricidad", "Cables", "C04", "C04-01"], ["Pisos", "Pisos", "C08", "C08-01"], ["Otros", "Otros", "C11", "C11-01"]], 2):
            for ci, v in enumerate(row, 1): t.cell(ri, ci, v)
        wb.save(path)

    def test_partition_reconciles_all_rows(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "synthetic.xlsx"
            self.workbook(path)
            result = module.simulate(path, [{"code": "EX-1", "name": "Cable test", "unit": "M"}])
            self.assertEqual(result["source_items"], 4)
            self.assertEqual(result["unit_unresolved_rows"], 1)
            self.assertEqual(result["exact_same_name_unit"], 1)
            self.assertEqual(result["duplicate_same_unit_rows"], 2)
            self.assertEqual(result["history_records"], 1)
            self.assertEqual(result["history_orphans"], 0)
            self.assertEqual(result["create_preliminary_candidates"], 0)
            self.assertEqual(result["review_existing_mapping_rows"], 1)
            self.assertEqual(result["review_duplicate_rows"], 2)
            self.assertEqual(result["stage_unit_review_rows"], 1)
            self.assertEqual(result["partition_total"], 4)

    def test_unknown_unit_is_not_guessed(self):
        self.assertIsNone(module.UNITS.get("GL"))
        self.assertIsNone(module.UNITS.get("ZZ"))
        self.assertEqual(module.UNITS.get("ML"), "M")
        self.assertEqual(module.UNITS.get("GALÓN"), "GAL")

if __name__ == "__main__":
    unittest.main()
