import { useEffect, useState, useCallback } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import type { ProviderProfileRow } from '@/types/provider';
import { MyInfoCard } from '@/components/provider/MyInfoCard';
import { CompanyCard } from '@/components/provider/CompanyCard';
import { CommercialInfoCard } from '@/components/provider/CommercialInfoCard';
import { Card } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Loader2, AlertTriangle } from 'lucide-react';
import { ensureProviderForUser, DEMO_PROFILE_DEFAULTS } from '@/lib/providerHelpers';

export const ProviderProfile = () => {
  const { user } = useAuth();
  const [profile, setProfile] = useState<ProviderProfileRow | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [specialties, setSpecialties] = useState<string[]>([]);

  const load = useCallback(async () => {
    if (!user || user.role !== 'proveedor') { setLoading(false); return; }
    setLoading(true); setError(null);
    try {
      const providerId = await ensureProviderForUser({ email: user.email, role: user.role });

      const { data: prov } = await supabase.from('providers').select('specialties').eq('id', providerId).maybeSingle();
      setSpecialties(prov?.specialties ?? []);

      const { data: existing, error: fErr } = await supabase
        .from('provider_profiles').select('*').eq('provider_id', providerId).maybeSingle();
      if (fErr) throw fErr;

      if (existing) {
        setProfile(existing as ProviderProfileRow);
      } else {
        const { data: created, error: iErr } = await supabase
          .from('provider_profiles')
          .upsert({
            provider_id: providerId,
            owner_user_id: user.id,
            ...DEMO_PROFILE_DEFAULTS,
            contact_email: user.email,
          }, { onConflict: 'provider_id' })
          .select().single();
        if (iErr) throw iErr;
        setProfile(created as ProviderProfileRow);
      }
    } catch (e: any) {
      console.error('ProviderProfile load error:', e);
      setError(e?.message ?? 'Error desconocido');
    } finally {
      setLoading(false);
    }
  }, [user]);

  useEffect(() => { load(); }, [load]);

  if (!user || user.role !== 'proveedor') {
    return (
      <div className="p-6">
        <Card className="p-8 text-center">
          <h2 className="text-xl font-semibold mb-2">Acceso no permitido</h2>
          <p className="text-muted-foreground">Esta sección está disponible solo para usuarios proveedor.</p>
        </Card>
      </div>
    );
  }

  if (loading) {
    return <div className="p-6 flex items-center justify-center"><Loader2 className="h-6 w-6 animate-spin" /></div>;
  }

  if (error || !profile) {
    return (
      <div className="p-6">
        <Card className="p-8 text-center space-y-4">
          <AlertTriangle className="h-10 w-10 mx-auto text-destructive" />
          <h2 className="text-xl font-semibold">No se pudo cargar el perfil del proveedor</h2>
          {error && import.meta.env.DEV && (
            <p className="text-xs text-muted-foreground font-mono break-all">{error}</p>
          )}
          <Button onClick={load}>Reintentar</Button>
        </Card>
      </div>
    );
  }

  return (
    <div className="p-6 space-y-6 max-w-6xl mx-auto">
      <div>
        <h1 className="text-3xl font-bold">Mi Perfil</h1>
        <p className="text-muted-foreground">Gestiona tu información como proveedor</p>
      </div>

      <MyInfoCard profile={profile} onUpdated={setProfile} />
      <CompanyCard profile={profile} onUpdated={setProfile} />
      <CommercialInfoCard profile={profile} onUpdated={setProfile} specialties={specialties} />
    </div>
  );
};
