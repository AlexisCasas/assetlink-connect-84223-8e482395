import { Document, Image, Page, Path, StyleSheet, Svg, Text, View } from '@react-pdf/renderer';
import type { AssetReportData } from './types';
import { formatReportDate, formatReportDateTime, pdfText } from './utils';
import { ASSET_NODE_TYPE_LABELS, ASSET_STATUS_LABELS, ASSET_CRITICALITY_LABELS } from '@/lib/assetLabels';
import { TRAFFIC_LIGHT_LABELS, TRAFFIC_LIGHT_SOURCE_LABELS } from '@/lib/trafficLightLabels';
import { MAINTENANCE_NOTICE_PRIORITY_LABELS, MAINTENANCE_NOTICE_STATUS_LABELS } from '@/types/maintenanceNotice';

/**
 * A4 report design (Fase 1 · Punto 5). Standard PDF fonts only (no embedded
 * .ttf — see utils.ts → pdfText for the symbol normalization that makes that
 * safe). Colors accompany text labels everywhere so the report stays
 * legible printed in black & white. See docs/ASSET_REPORT.md → "Diseño".
 *
 * Layout note: rows are rendered as bordered "cards" (label/value pairs or
 * one card per item) rather than a strict multi-page grid table — @react-pdf
 * has no built-in repeating table header across page breaks, and a card
 * layout reflows across pages with zero extra work while staying just as
 * readable for this MVP's row counts.
 */

const COLORS = {
  navy: '#002E42',
  blue: '#005A8C',
  brown: '#994608',
  border: '#D8E4EA',
  surface: '#EEF5F8',
  text: '#1A1A1A',
  muted: '#4B5563',
  red: '#B42318',
  amber: '#B54708',
  green: '#067647',
};

const styles = StyleSheet.create({
  page: { paddingTop: 60, paddingBottom: 46, paddingHorizontal: 36, fontSize: 9, fontFamily: 'Helvetica', color: COLORS.text },
  fixedHeader: {
    position: 'absolute', top: 0, left: 0, right: 0, height: 42,
    paddingHorizontal: 36, paddingTop: 12, paddingBottom: 8,
    flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
    borderBottomWidth: 1, borderBottomColor: COLORS.border,
  },
  fixedHeaderLogo: { width: 64, height: 18, objectFit: 'contain' },
  fixedHeaderAssetName: { fontSize: 9, fontWeight: 700, color: COLORS.navy, textAlign: 'right' },
  fixedHeaderAssetCode: { fontSize: 7, color: COLORS.muted, textAlign: 'right' },
  fixedFooter: {
    position: 'absolute', bottom: 0, left: 0, right: 0, height: 36,
    paddingHorizontal: 36, paddingTop: 6,
    borderTopWidth: 1, borderTopColor: COLORS.border,
  },
  footerRow: { flexDirection: 'row', justifyContent: 'space-between' },
  footerText: { fontSize: 7, color: COLORS.muted },
  footerNote: { fontSize: 6.5, color: COLORS.muted, marginTop: 2 },

  hero: { flexDirection: 'row', justifyContent: 'space-between', marginBottom: 10 },
  heroLeft: { flexShrink: 1, paddingRight: 12 },
  heroTitle: { fontSize: 16, fontWeight: 700, color: COLORS.navy, marginBottom: 4 },
  heroLine: { fontSize: 9, color: COLORS.text, marginBottom: 2 },
  heroMuted: { fontSize: 8, color: COLORS.muted, marginBottom: 2 },
  heroUuid: { fontSize: 6.5, color: COLORS.muted, marginTop: 4 },
  heroQrBlock: { alignItems: 'center', width: 88 },
  heroQrCaption: { fontSize: 6.5, color: COLORS.muted, textAlign: 'center', marginTop: 3 },
  heroQrWarning: { fontSize: 6.5, color: COLORS.amber, textAlign: 'center', marginTop: 2 },

  sectionTitle: { backgroundColor: COLORS.navy, paddingVertical: 4, paddingHorizontal: 6, marginTop: 12, marginBottom: 6 },
  sectionTitleText: { fontSize: 10, fontWeight: 700, color: '#FFFFFF' },

  fieldsGrid: { flexDirection: 'row', flexWrap: 'wrap' },
  fieldRow: { width: '50%', flexDirection: 'row', marginBottom: 4, paddingRight: 8 },
  fieldRowFull: { width: '100%', flexDirection: 'row', marginBottom: 4 },
  fieldLabel: { width: 110, fontSize: 7.5, color: COLORS.muted },
  fieldValue: { flex: 1, fontSize: 9, color: COLORS.text },

  emptyNote: { fontSize: 8.5, color: COLORS.muted, fontStyle: 'italic', marginBottom: 4 },

  card: { borderWidth: 1, borderColor: COLORS.border, borderRadius: 3, padding: 6, marginBottom: 6, backgroundColor: COLORS.surface },
  cardHeaderRow: { flexDirection: 'row', justifyContent: 'space-between', marginBottom: 2 },
  cardTitle: { fontSize: 9, fontWeight: 700, color: COLORS.navy },
  cardBadge: { fontSize: 7.5, color: COLORS.muted },
  cardLine: { fontSize: 8, color: COLORS.text, marginTop: 1 },
  cardMuted: { fontSize: 7.5, color: COLORS.muted, marginTop: 1 },

  reasonBlock: { borderLeftWidth: 2, borderLeftColor: COLORS.border, paddingLeft: 6, marginBottom: 4 },
  reasonTitle: { fontSize: 8, fontWeight: 700 },
  reasonDesc: { fontSize: 7.5, color: COLORS.muted, marginTop: 1 },
});

const severityColor = (severity: 'green' | 'amber' | 'red'): string => (
  severity === 'red' ? COLORS.red : severity === 'amber' ? COLORS.amber : COLORS.green
);

const FieldRow = ({ label, value, full }: { label: string; value: string; full?: boolean }) => (
  <View style={full ? styles.fieldRowFull : styles.fieldRow}>
    <Text style={styles.fieldLabel}>{label}</Text>
    <Text style={styles.fieldValue}>{value}</Text>
  </View>
);

const SectionTitle = ({ children }: { children: string }) => (
  <View style={styles.sectionTitle}><Text style={styles.sectionTitleText}>{children}</Text></View>
);

export interface AssetReportDocumentProps {
  data: AssetReportData;
  logoUrl: string;
}

export function AssetReportDocument({ data, logoUrl }: AssetReportDocumentProps) {
  const { asset } = data;
  const statusLabel = ASSET_STATUS_LABELS[asset.status];
  const nodeTypeLabel = ASSET_NODE_TYPE_LABELS[asset.nodeType];
  const responsibleLabel = data.responsible.kind === 'none'
    ? 'Sin responsable'
    : data.responsible.kind === 'unavailable'
      ? 'Responsable no disponible (inactivo o ya no elegible)'
      : data.responsible.name ?? 'Sin responsable';

  return (
    <Document title={`Reporte del activo — ${asset.name}`}>
      <Page size="A4" style={styles.page} wrap>
        <View style={styles.fixedHeader} fixed>
          <Image src={logoUrl} style={styles.fixedHeaderLogo} />
          <View>
            <Text style={styles.fixedHeaderAssetName}>{pdfText(asset.name)}</Text>
            {asset.code && <Text style={styles.fixedHeaderAssetCode}>{pdfText(asset.code)}</Text>}
          </View>
        </View>

        <View style={styles.fixedFooter} fixed>
          <View style={styles.footerRow}>
            <Text style={styles.footerText}>
              OneFacility · {pdfText(data.organizationName)}
              {data.generatedByName ? ` · Generado por ${pdfText(data.generatedByName)}` : ''}
            </Text>
            <Text style={styles.footerText} render={({ pageNumber, totalPages }) => `Página ${pageNumber} de ${totalPages}`} />
          </View>
          <Text style={styles.footerNote}>
            Generado el {formatReportDateTime(data.generatedAt)} · Estado al momento de generación, no es un registro histórico · ID: {asset.id}
          </Text>
        </View>

        {/* Hero — appears once, at the top of page 1 only (not `fixed`). */}
        <View style={styles.hero}>
          <View style={styles.heroLeft}>
            <Text style={styles.heroTitle}>Reporte del activo</Text>
            <Text style={styles.heroLine}>{pdfText(data.organizationName)}</Text>
            <Text style={styles.heroLine}>{pdfText(asset.name)}{asset.code ? ` · ${pdfText(asset.code)}` : ''}</Text>
            <Text style={styles.heroMuted}>Generado el {formatReportDateTime(data.generatedAt)}</Text>
            {data.generatedByName && <Text style={styles.heroMuted}>Generado por {pdfText(data.generatedByName)}</Text>}
            <Text style={styles.heroUuid}>ID técnico: {asset.id}</Text>
          </View>
          <View style={styles.heroQrBlock}>
            <Svg viewBox={data.qr.viewBox} style={{ width: 72, height: 72 }}>
              {data.qr.paths.map((path, index) => <Path key={index} d={path.d} fill={path.fill} />)}
            </Svg>
            <Text style={styles.heroQrCaption}>Escanea para abrir el activo</Text>
            {data.qr.isLocalOrigin && <Text style={styles.heroQrWarning}>QR de desarrollo</Text>}
          </View>
        </View>

        {/* 1. Identificación */}
        <SectionTitle>Identificación</SectionTitle>
        <View style={styles.fieldsGrid}>
          <FieldRow label="Nombre" value={pdfText(asset.name)} />
          <FieldRow label="Código" value={asset.code ? pdfText(asset.code) : 'No especificado'} />
          <FieldRow label="Tipo" value={nodeTypeLabel} />
          <FieldRow label="Estado" value={statusLabel} />
          <FieldRow label="Sede" value={data.branchName ? pdfText(data.branchName) : 'No especificado'} />
          <FieldRow label="Categoría" value={data.categoryName ? pdfText(data.categoryName) : 'No especificado'} />
          <FieldRow label="Ubicación" value={asset.locationText ? pdfText(asset.locationText) : 'No especificado'} />
          <FieldRow label="Responsable predeterminado" value={pdfText(responsibleLabel)} />
          <FieldRow label="Ruta jerárquica" value={pdfText(data.pathNames.join(' > '))} full />
        </View>

        {/* 2. Información técnica */}
        <SectionTitle>Información técnica</SectionTitle>
        <View style={styles.fieldsGrid}>
          <FieldRow label="Fabricante" value={asset.manufacturer ? pdfText(asset.manufacturer) : 'No especificado'} />
          <FieldRow label="Modelo" value={asset.model ? pdfText(asset.model) : 'No especificado'} />
          <FieldRow label="Número de serie" value={asset.serialNumber ? pdfText(asset.serialNumber) : 'No especificado'} />
          <FieldRow label="Código de barras" value={asset.barcode ? pdfText(asset.barcode) : 'No especificado'} />
          <FieldRow label="Fecha de compra" value={formatReportDate(asset.purchaseDate)} />
          <FieldRow label="Garantía hasta" value={formatReportDate(asset.warrantyUntil)} />
          <FieldRow label="Descripción" value={asset.description ? pdfText(asset.description) : 'No especificado'} full />
          {data.technicalFields.map((field) => (
            <FieldRow key={field.label} label={field.label} value={field.value} />
          ))}
        </View>

        {/* 3. Criticidad */}
        <SectionTitle>Criticidad</SectionTitle>
        <View style={styles.fieldsGrid}>
          <FieldRow label="Criticidad efectiva" value={asset.criticality ? ASSET_CRITICALITY_LABELS[asset.criticality] : 'No especificado'} />
          {data.criticality.latest && (
            <>
              <FieldRow label="Fecha de evaluación" value={formatReportDate(data.criticality.latest.createdAt)} />
              {data.criticality.latest.isCurrent && (
                <FieldRow label="Score" value={`${data.criticality.latest.score} (última evaluación vigente)`} />
              )}
              <FieldRow
                label="Umbrales usados"
                value={`Media desde ${data.criticality.latest.thresholds.mediumMin} · Alta desde ${data.criticality.latest.thresholds.highMin} · Muy Alta desde ${data.criticality.latest.thresholds.criticalMin}`}
                full
              />
            </>
          )}
        </View>
        {!data.criticality.latest && <Text style={styles.emptyNote}>Sin evaluaciones de criticidad registradas para este activo.</Text>}
        {data.criticality.latest && !data.criticality.latest.isCurrent && (
          <Text style={styles.emptyNote}>La evaluación anterior no representa el valor actual del activo (fue cambiado manualmente después).</Text>
        )}

        {/* 4. Estado operativo */}
        <SectionTitle>Estado operativo al momento de generación</SectionTitle>
        {data.trafficLight.archived ? (
          <Text style={styles.emptyNote}>Activo archivado - fuera del semáforo operativo.</Text>
        ) : (
          <>
            <View style={styles.fieldsGrid}>
              <FieldRow
                label="Directo"
                value={data.trafficLight.direct ? TRAFFIC_LIGHT_LABELS[data.trafficLight.direct] : 'No disponible'}
              />
              {data.trafficLight.hasChildren && (
                <FieldRow
                  label="Heredado (rollup)"
                  value={data.trafficLight.rollup ? TRAFFIC_LIGHT_LABELS[data.trafficLight.rollup] : 'No disponible'}
                />
              )}
            </View>
            {data.trafficLight.directReasons.length === 0 && data.trafficLight.rollupReasons.length === 0 ? (
              <Text style={styles.emptyNote}>Todo en regla - sin OT vencidas, inspecciones vencidas ni no conformidades.</Text>
            ) : (
              <>
                {data.trafficLight.directReasons.map((reason) => (
                  <View key={`${reason.sourceType}-${reason.sourceId}`} style={styles.reasonBlock} wrap={false}>
                    <Text style={[styles.reasonTitle, { color: severityColor(reason.severity) }]}>
                      {TRAFFIC_LIGHT_SOURCE_LABELS[reason.sourceType]} · {TRAFFIC_LIGHT_LABELS[reason.severity]}
                    </Text>
                    <Text style={styles.reasonDesc}>{pdfText(reason.description)}</Text>
                  </View>
                ))}
                {data.trafficLight.hasChildren && data.trafficLight.rollupReasons.map((reason, index) => (
                  <View key={`${reason.sourceType}-${reason.sourceId}-${index}`} style={styles.reasonBlock} wrap={false}>
                    <Text style={[styles.reasonTitle, { color: severityColor(reason.severity) }]}>
                      {reason.assetName ? `${pdfText(reason.assetName)} — ` : ''}{TRAFFIC_LIGHT_SOURCE_LABELS[reason.sourceType]} · {TRAFFIC_LIGHT_LABELS[reason.severity]}
                    </Text>
                    <Text style={styles.reasonDesc}>{pdfText(reason.description)}</Text>
                  </View>
                ))}
              </>
            )}
          </>
        )}

        {/* 5. Preventivo */}
        <SectionTitle>Mantenimiento preventivo</SectionTitle>
        {data.preventivePlans.length === 0 ? (
          <Text style={styles.emptyNote}>Sin planes preventivos asociados.</Text>
        ) : data.preventivePlans.map((plan) => (
          <View key={plan.id} style={styles.card} wrap={false}>
            <View style={styles.cardHeaderRow}>
              <Text style={styles.cardTitle}>{plan.cardCode} · {plan.cardName}</Text>
              <Text style={styles.cardBadge}>{plan.isActive ? 'Activo' : 'Inactivo'}</Text>
            </View>
            <Text style={styles.cardLine}>{plan.triggerLabel} · {plan.timingStatusLabel}</Text>
            <Text style={styles.cardLine}>{plan.nextCycleLabel}</Text>
            <Text style={styles.cardMuted}>Responsable: {plan.responsibleName ? pdfText(plan.responsibleName) : 'Sin responsable asignado'}</Text>
          </View>
        ))}

        {/* 6. Inspecciones */}
        <SectionTitle>Inspecciones</SectionTitle>
        {data.inspectionPlans.length === 0 ? (
          <Text style={styles.emptyNote}>Sin planes de inspección asociados directamente a este activo.</Text>
        ) : data.inspectionPlans.map((plan) => (
          <View key={plan.id} style={styles.card} wrap={false}>
            <View style={styles.cardHeaderRow}>
              <Text style={styles.cardTitle}>{plan.title}</Text>
              <Text style={styles.cardBadge}>{plan.isActive ? 'Activo' : 'Inactivo'}</Text>
            </View>
            <Text style={styles.cardLine}>Plantilla: {plan.templateName} · {plan.frequencyLabel}</Text>
            <Text style={styles.cardLine}>Próxima fecha: {plan.nextDueAtLabel}</Text>
            <Text style={styles.cardMuted}>Responsable: {plan.responsibleName ? pdfText(plan.responsibleName) : 'Sin responsable asignado'}</Text>
            <Text style={styles.cardMuted}>
              Última ejecución: {plan.lastRun ? `${plan.lastRun.dateLabel} · ${plan.lastRun.resultLabel}` : 'Sin ejecuciones registradas'}
            </Text>
          </View>
        ))}

        {/* 7. Avisos */}
        <SectionTitle>Avisos</SectionTitle>
        {data.notices.length === 0 ? (
          <Text style={styles.emptyNote}>Sin avisos registrados para este activo.</Text>
        ) : data.notices.map((notice) => (
          <View key={notice.id} style={styles.card} wrap={false}>
            <View style={styles.cardHeaderRow}>
              <Text style={styles.cardTitle}>{notice.noticeNumber} · {pdfText(notice.title)}</Text>
              <Text style={styles.cardBadge}>{MAINTENANCE_NOTICE_PRIORITY_LABELS[notice.priority]}</Text>
            </View>
            <Text style={styles.cardLine}>Estado: {MAINTENANCE_NOTICE_STATUS_LABELS[notice.status]}</Text>
            <Text style={styles.cardMuted}>
              Responsable: {notice.responsibleName ? pdfText(notice.responsibleName) : 'Sin responsable asignado'} · {formatReportDate(notice.reportedAt)}
            </Text>
          </View>
        ))}

        {/* 8. Historial operativo — starts on a new page */}
        <View break>
          <SectionTitle>Historial operativo</SectionTitle>
          {data.history.length === 0 ? (
            <Text style={styles.emptyNote}>Sin eventos registrados para este activo.</Text>
          ) : data.history.map((item) => (
            <View key={item.id} style={styles.card} wrap={false}>
              <View style={styles.cardHeaderRow}>
                <Text style={styles.cardTitle}>{item.eventLabel}</Text>
                <Text style={styles.cardBadge}>{formatReportDateTime(item.eventDate)}</Text>
              </View>
              <Text style={styles.cardLine}>{item.title}</Text>
              {item.description && <Text style={styles.cardMuted}>{item.description}</Text>}
              {item.detail && <Text style={styles.cardMuted}>{item.detail}</Text>}
              <Text style={styles.cardMuted}>
                {item.actorName ? `Por ${pdfText(item.actorName)}` : 'Sin actor registrado'}
                {item.status ? ` · Estado: ${pdfText(item.status)}` : ''}
              </Text>
            </View>
          ))}
        </View>
      </Page>
    </Document>
  );
}
