import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { QuoteSummaryData } from '@/types/quote-template';
import { QuoteSection, QuoteCalculationSummary } from '@/types/request';
import { calcSectionSubtotal, calculateQuote, formatSoles } from '@/lib/quoteCalculations';

interface NewProps {
  sections: QuoteSection[];
  generalExpensesPercentage: number;
  utilitiesPercentage: number;
  generalExpensesEnabled: boolean;
  utilitiesEnabled: boolean;
}

interface LegacyProps {
  data: QuoteSummaryData;
  deliveryDays?: number;
  validityDays?: number;
}

type Props = NewProps | LegacyProps;

const isLegacy = (p: Props): p is LegacyProps =>
  (p as LegacyProps).data !== undefined;

export const QuoteSummary = (props: Props) => {
  if (isLegacy(props)) {
    const { data } = props;
    return (
      <Card>
        <CardHeader>
          <CardTitle>Resumen económico</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="space-y-2 text-sm">
            {data.fields.map((f, i) => (
              <div key={i} className="flex justify-between">
                <span>{f.title}</span>
                <span className="font-mono">{formatSoles(f.total)}</span>
              </div>
            ))}
            <div className="flex justify-between border-t pt-2 font-semibold">
              <span>Subtotal</span>
              <span className="font-mono">{formatSoles(data.subtotal)}</span>
            </div>
            {data.percentageFields.map((p, i) => (
              <div key={i} className="flex justify-between">
                <span>{p.name}</span>
                <span className="font-mono">{formatSoles(p.amount)}</span>
              </div>
            ))}
            <div className="flex justify-between">
              <span>I.G.V. 18%</span>
              <span className="font-mono">{formatSoles(data.igv)}</span>
            </div>
            <div className="flex justify-between border-t pt-2 text-base font-bold">
              <span>Total</span>
              <span className="font-mono">{formatSoles(data.total)}</span>
            </div>
          </div>
        </CardContent>
      </Card>
    );
  }

  const {
    sections,
    generalExpensesPercentage,
    utilitiesPercentage,
    generalExpensesEnabled,
    utilitiesEnabled,
  } = props;

  const calc: QuoteCalculationSummary = calculateQuote(
    sections,
    generalExpensesPercentage,
    utilitiesPercentage,
    generalExpensesEnabled,
    utilitiesEnabled,
  );

  return (
    <Card>
      <CardHeader>
        <CardTitle>Resumen Económico</CardTitle>
      </CardHeader>
      <CardContent>
        <div className="space-y-1.5 text-sm">
          {sections.filter(s => s.enabled).map((s) => (
            <div key={s.id} className="flex justify-between">
              <span className="text-muted-foreground">{s.name}</span>
              <span className="font-mono">{formatSoles(calcSectionSubtotal(s))}</span>
            </div>
          ))}
          <div className="flex justify-between border-t pt-2 font-semibold">
            <span>Subtotal base</span>
            <span className="font-mono">{formatSoles(calc.baseSubtotal)}</span>
          </div>
          {generalExpensesEnabled && (
            <div className="flex justify-between">
              <span>Gastos Generales ({calc.generalExpensesPercentage}%)</span>
              <span className="font-mono">{formatSoles(calc.generalExpensesAmount)}</span>
            </div>
          )}
          {utilitiesEnabled && (
            <div className="flex justify-between">
              <span>Utilidades ({calc.utilitiesPercentage}%)</span>
              <span className="font-mono">{formatSoles(calc.utilitiesAmount)}</span>
            </div>
          )}
          <div className="flex justify-between border-t pt-2 font-semibold">
            <span>Subtotal</span>
            <span className="font-mono">{formatSoles(calc.subtotal)}</span>
          </div>
          <div className="flex justify-between">
            <span>I.G.V. 18%</span>
            <span className="font-mono">{formatSoles(calc.igvAmount)}</span>
          </div>
          <div className="flex justify-between border-t pt-2 text-lg font-bold text-primary">
            <span>Total</span>
            <span className="font-mono">{formatSoles(calc.totalAmount)}</span>
          </div>
        </div>
      </CardContent>
    </Card>
  );
};
