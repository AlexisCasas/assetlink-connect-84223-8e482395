import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { QuoteSummaryData } from '@/types/quote-template';

interface QuoteSummaryProps {
  data: QuoteSummaryData;
  deliveryDays?: number;
  validityDays?: number;
}

export const QuoteSummary = ({ data, deliveryDays = 1, validityDays = 30 }: QuoteSummaryProps) => {
  return (
    <Card>
      <CardHeader>
        <CardTitle>RESUMEN ASPECTOS ECONÓMICOS COSTOS</CardTitle>
      </CardHeader>
      <CardContent>
        <div className="space-y-4">
          {/* Costos por campo */}
          <div className="border rounded-lg overflow-hidden">
            <div className="bg-muted p-3 font-semibold grid grid-cols-2">
              <span>TOTAL COSTOS POR EL SERVICIO</span>
              <span className="text-right">TOTAL S/.</span>
            </div>
            {data.fields.map((field, index) => (
              <div
                key={index}
                className="p-3 grid grid-cols-2 border-t hover:bg-muted/50 transition-colors"
              >
                <span>{index + 1}. {field.title.toUpperCase()}</span>
                <span className="text-right font-mono">
                  {field.total.toFixed(2)}
                </span>
              </div>
            ))}
          </div>

          {/* Subtotal y campos de porcentaje */}
          <div className="border rounded-lg overflow-hidden">
            <div className="p-3 grid grid-cols-2 bg-muted/50 font-semibold border-b">
              <span>SUB TOTAL COSTOS</span>
              <span className="text-right font-mono">
                {data.subtotal.toFixed(2)}
              </span>
            </div>

            {data.percentageFields.map((field, index) => (
              <div
                key={index}
                className="p-3 grid grid-cols-2 border-b last:border-b-0 hover:bg-muted/50 transition-colors"
              >
                <span>{field.name}</span>
                <span className="text-right font-mono">
                  {field.amount.toFixed(2)}
                </span>
              </div>
            ))}

            <div className="p-3 grid grid-cols-2 bg-muted font-semibold border-t-2">
              <span>COSTO TOTAL SIN IGV</span>
              <span className="text-right font-mono">
                S/. {(data.subtotal + data.percentageFields.reduce((sum, f) => sum + f.amount, 0)).toFixed(2)}
              </span>
            </div>

            <div className="p-3 grid grid-cols-2 border-t">
              <span>I.G.V. 18%</span>
              <span className="text-right font-mono">
                {data.igv.toFixed(2)}
              </span>
            </div>

            <div className="p-3 grid grid-cols-2 bg-primary text-primary-foreground font-bold text-lg border-t-2">
              <span>COSTO TOTAL CON IGV</span>
              <span className="text-right font-mono">
                S/. {data.total.toFixed(2)}
              </span>
            </div>
          </div>

          {/* Información adicional */}
          <div className="grid grid-cols-3 gap-4 p-4 bg-muted rounded-lg">
            <div className="text-center">
              <div className="text-2xl font-bold">{validityDays}</div>
              <div className="text-sm text-muted-foreground">DÍAS VIGENCIA</div>
            </div>
            <div className="text-center border-x">
              <div className="text-2xl font-bold">{deliveryDays}</div>
              <div className="text-sm text-muted-foreground">PLAZO ENTREGA</div>
            </div>
            <div className="text-center">
              <div className="text-2xl font-bold">{data.fields.length}</div>
              <div className="text-sm text-muted-foreground">ITEMS</div>
            </div>
          </div>
        </div>
      </CardContent>
    </Card>
  );
};
