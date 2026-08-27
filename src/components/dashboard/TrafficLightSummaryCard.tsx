import { TrafficCone } from 'lucide-react';
import { useAuth } from '@/contexts/AuthContext';
import { useAssetTrafficLight } from '@/hooks/useAssetTrafficLight';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { cn } from '@/lib/utils';
import { TRAFFIC_LIGHT_DOT_CLASS, TRAFFIC_LIGHT_LABELS } from '@/lib/trafficLightLabels';

/**
 * Real-source summary (green/amber/red asset counts) for the dashboard
 * landing view — computed live via useAssetTrafficLight, same source as
 * AssetsView/AssetDetail. Assets only exist for client_company
 * organizations in this codebase, so this renders nothing otherwise (never
 * an empty/fake card). See docs/ASSET_TRAFFIC_LIGHT.md.
 */
export function TrafficLightSummaryCard() {
  const { currentOrganization } = useAuth();
  const isClientCompany = currentOrganization?.organizationType === 'client_company';
  const { summary, loading } = useAssetTrafficLight(isClientCompany ? currentOrganization?.id : undefined);

  if (!isClientCompany) return null;

  return (
    <Card>
      <CardHeader className="pb-2">
        <CardTitle className="flex items-center gap-2 text-base">
          <TrafficCone className="h-4 w-4 text-muted-foreground" />
          Semáforo operativo de activos
        </CardTitle>
      </CardHeader>
      <CardContent>
        {loading ? (
          <p className="text-sm text-muted-foreground">Cargando…</p>
        ) : (
          <div className="flex flex-wrap gap-6">
            {(['green', 'amber', 'red'] as const).map((color) => (
              <div key={color} className="flex items-center gap-2">
                <span className={cn('h-3 w-3 rounded-full', TRAFFIC_LIGHT_DOT_CLASS[color])} />
                <span className="text-2xl font-bold">{summary[color]}</span>
                <span className="text-sm text-muted-foreground">{TRAFFIC_LIGHT_LABELS[color]}</span>
              </div>
            ))}
          </div>
        )}
      </CardContent>
    </Card>
  );
}
