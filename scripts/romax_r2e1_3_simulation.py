#!/usr/bin/env python3
"""Read-only ROMAX workbook homologation simulation. No database writes."""
import argparse
import json
import re
import unicodedata
from collections import Counter, defaultdict
from difflib import SequenceMatcher
from pathlib import Path
from openpyxl import load_workbook

UNITS = {"UND":"UND", "M":"M", "ML":"M", "GALÓN":"GAL", "GALON":"GAL", "KG":"KG", "ROLLO":"ROLLO", "RLL":"ROLLO", "M2":"M2", "M3":"M3", "CAJA":"CAJA", "BOLSA":"BOLSA", "BALDE":"BALDE", "MILLAR":"MILLAR", "PAR":"PAR", "PQT":"PQT"}
FAMILY_RULES = [
    ("Seguridad, señalización y consumibles", r"\b(respirador|guantes|casco|lentes|arnes|mascarilla|proteccion personal|epp|chaleco|botas)\b"),
    ("Pintura, recubrimientos e impermeabilización", r"\b(thinner|thiner|pintura|epox|esmalte|imprimante|sellador|removedor|brocha|rodillo|barniz|impermeabilizante|latex)\b"),
    ("Pisos, carpintería y acabados", r"\b(porcelanato|ceramico|piso vinilico|parquet|rodapie|zocalo|melamina)\b"),
    ("Albañilería y obras civiles", r"\b(cemento|arena|ladrillo|grout|concreto|yeso|mortero|tarrajeo|piedra|agregado)\b"),
    ("Drywall, cielos rasos y divisiones", r"\b(drywall|superboard|fibrocemento|placa de yeso|cielo raso|cielorraso|masilla drywall)\b"),
    ("Electricidad e iluminación", r"\b(cable|tablero|interruptor|tomacorriente|reflector|luminaria|conductor|contactor|breaker)\b"),
    ("Instalaciones sanitarias y griferías", r"\b(tuberia de agua|pvc desague|fluxometro|griferia|inodoro|lavatorio|valvula|sanitario)\b"),
    ("Electromecánica, bombas y ventilación", r"\b(bomba|motor electrico|ventilador|electronivel|rodamiento|chumacera)\b"),
    ("Metalmecánica y soldadura", r"\b(soldadura|perfil|viga|acero|plancha metal|perno|tuerca|tubo estructural|metalmecanica)\b"),
    ("Coberturas, techos y drenaje pluvial", r"\b(techo|cobertura|calamina|policarbonato|canalon|drenaje pluvial)\b"),
    ("Otros", r"\b(vidrio|espejo|mampara|ventana|jardineria|riego|sustrato)\b"),
]

def text(value):
    return "" if value is None else str(value).strip()

def norm(value):
    value = unicodedata.normalize("NFKD", text(value)).encode("ascii", "ignore").decode().lower()
    return " ".join(re.sub(r"[^a-z0-9]+", " ", value).split())

def records(ws, header_row):
    iterator = ws.iter_rows(min_row=header_row, values_only=True)
    headers = [text(v) for v in next(iterator)]
    out = []
    for values in iterator:
        row = {h: values[i] for i, h in enumerate(headers) if h}
        if any(v is not None and text(v) for v in row.values()):
            out.append(row)
    return out

def simulate(workbook_path, catalog):
    wb = load_workbook(workbook_path, data_only=True, read_only=True)
    required = {"Matriz materiales", "Dados de Alta", "Historial precios", "Categorías"}
    if required - set(wb.sheetnames):
        raise ValueError("Missing required ROMAX workbook sheets")
    matrix = records(wb["Matriz materiales"], 8)
    intake = records(wb["Dados de Alta"], 3)
    history = records(wb["Historial precios"], 4)
    taxonomy = records(wb["Categorías"], 1)
    m = {text(r.get("Código")): r for r in matrix}
    a = {text(r.get("Código")): r for r in intake}
    if len(m) != len(matrix) or len(a) != len(intake) or set(m) != set(a):
        raise ValueError("Source code universe is not unique and aligned between sheets")
    families = {norm(r.get("Categoría")): text(r.get("Código categoría")) for r in taxonomy if text(r.get("Categoría"))}
    catalog_by_name = defaultdict(list)
    for item in catalog:
        if not all(k in item for k in ("code", "name", "unit")):
            raise ValueError("Catalog snapshot items require code, name and unit")
        catalog_by_name[norm(item["name"])].append(item)
    unit_counts = Counter()
    family_counts = Counter()
    candidate_codes = set()
    unresolved_codes = set()
    duplicate_groups = defaultdict(list)
    matrix_conflicts = 0
    matrix_blank = 0
    priced_codes = set()
    record_status = Counter()
    validity_status = Counter()
    logistics = Counter()
    commercial = Counter()
    candidates = Counter()
    family_review_suggestions = 0
    subfamily_assigned = 0
    for code, row in a.items():
        name = text(row.get("Material propuesto"))
        family = text(row.get("Categoría"))
        raw_unit = text(row.get("Unidad"))
        canonical = UNITS.get(raw_unit.upper())
        unit_counts[raw_unit] += 1
        family_counts[family] += 1
        subfamily_assigned += bool(text(row.get("Subcategoría")))
        suggested = [f for f, pattern in FAMILY_RULES if re.search(pattern, name, re.I)]
        if len(suggested) == 1 and norm(suggested[0]) != norm(family):
            family_review_suggestions += 1
        if not canonical:
            unresolved_codes.add(code)
        matrix_row = m[code]
        matrix_family = text(matrix_row.get("Categoría"))
        if not matrix_family:
            matrix_blank += 1
        elif norm(matrix_family) != norm(family):
            matrix_conflicts += 1
        if isinstance(matrix_row.get("Costo mercado con IGV"), (int, float)):
            priced_codes.add(code)
        record_status[text(matrix_row.get("Estado del registro"))] += 1
        validity_status[text(matrix_row.get("Estado de vigencia"))] += 1
        logistics[text(row.get("Validación Logística"))] += 1
        commercial[text(row.get("Decisión líder comercial"))] += 1
        duplicate_groups[norm(name)].append((code, raw_unit, canonical))
        exact = catalog_by_name.get(norm(name), [])
        match = None
        kind = None
        if exact:
            match = exact[0]
            kind = "exact_same_unit" if canonical and canonical == text(match.get("unit")) else "exact_unit_review"
        else:
            ranked = sorted(((SequenceMatcher(None, norm(name), norm(i["name"])).ratio(), i) for i in catalog), key=lambda x: x[0], reverse=True)
            if ranked and ranked[0][0] >= 0.78:
                _, match = ranked[0]
                kind = "fuzzy_review"
        if match:
            candidate_codes.add(code)
            candidates[kind] += 1
    duplicate_same = set()
    duplicate_same_groups = 0
    duplicate_different_groups = 0
    duplicate_groups_count = 0
    for group in duplicate_groups.values():
        if len(group) < 2:
            continue
        duplicate_groups_count += 1
        units = {canonical if canonical else "UNRESOLVED:" + raw for _, raw, canonical in group}
        if len(units) == 1:
            duplicate_same_groups += 1
            duplicate_same.update(code for code, _, _ in group)
        else:
            duplicate_different_groups += 1
    history_codes = [text(r.get("Código material")) for r in history]
    history_ids = [text(r.get("Registro")) for r in history]
    orphan = sum(code not in a for code in history_codes)
    unique_history_codes = len(set(history_codes))
    review_existing = candidate_codes - unresolved_codes - duplicate_same
    create_ready = set(a) - unresolved_codes - review_existing - duplicate_same
    partition = len(create_ready) + len(review_existing) + len(duplicate_same) + len(unresolved_codes)
    if partition != len(a):
        raise ValueError("Simulation partition does not reconcile all source rows")
    priced_validity = Counter(text(m[code].get("Estado de vigencia")) for code in priced_codes)
    return {
        "source_items": len(a), "unique_source_codes": len(a), "existing_catalog_items": len(catalog),
        "taxonomy_families": len(families), "taxonomy_subfamilies": len(taxonomy), "families_used": len(family_counts),
        "families_unused": sorted(set(families) - {norm(k) for k in family_counts}),
        "subfamily_assigned": subfamily_assigned, "family_review_suggestions": family_review_suggestions,
        "matrix_family_blank": matrix_blank, "matrix_family_conflicts": matrix_conflicts,
        "raw_unit_labels": len(unit_counts), "unit_resolved_rows": len(a) - len(unresolved_codes), "unit_unresolved_rows": len(unresolved_codes),
        "unit_counts": dict(unit_counts), "exact_same_name_unit": candidates["exact_same_unit"],
        "exact_name_unit_conflict": candidates["exact_unit_review"], "fuzzy_candidates": candidates["fuzzy_review"],
        "candidate_rows": sum(candidates.values()), "duplicate_name_groups": duplicate_groups_count,
        "duplicate_same_unit_groups": duplicate_same_groups, "duplicate_different_unit_groups": duplicate_different_groups,
        "duplicate_same_unit_rows": len(duplicate_same), "history_records": len(history),
        "history_unique_material_codes": unique_history_codes, "history_orphans": orphan,
        "history_duplicate_ids": len(history_ids) - len(set(history_ids)),
        "history_vigencies": dict(Counter(text(r.get("Vigencia (días)")) for r in history)),
        "history_missing_validator": sum(not text(r.get("Validado por")) for r in history),
        "history_missing_registrar": sum(not text(r.get("Registrado por")) for r in history),
        "market_cost_records": len(priced_codes), "without_market_cost": len(a) - len(priced_codes),
        "priced_validity_status": dict(priced_validity), "record_status": dict(record_status),
        "logistics_status": dict(logistics), "commercial_decision": dict(commercial),
        "approved_by_count": sum(bool(text(r.get("Aprobado por"))) for r in matrix),
        "create_preliminary_candidates": len(create_ready), "review_existing_mapping_rows": len(review_existing),
        "review_duplicate_rows": len(duplicate_same), "stage_unit_review_rows": len(unresolved_codes),
        "partition_total": partition,
    }

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--catalog", required=True, type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    catalog = json.loads(args.catalog.read_text(encoding="utf-8"))
    if isinstance(catalog, dict):
        catalog = catalog.get("items", [])
    result = simulate(args.input, catalog)
    payload = json.dumps(result, ensure_ascii=False, indent=2)
    if args.output:
        args.output.write_text(payload + "\n", encoding="utf-8")
    print(payload)

if __name__ == "__main__":
    main()
