import { useEffect, useState } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { MOCK_PROVIDERS } from '@/types/request';
import type { ProviderProfileRow } from '@/types/provider';
import { MyInfoCard } from '@/components/provider/MyInfoCard';
import { CompanyCard } from '@/components/provider/CompanyCard';
import { CommercialInfoCard } from '@/components/provider/CommercialInfoCard';
import { Card } from '@/components/ui/card';
import { Loader2 } from 'lucide-react';

export const ProviderProfile = () => {
  const { user } = useAuth();
  const [profile, setProfile] = useState<ProviderProfileRow | null>(null);
  const [loading, setLoading] = useState(true);
  const [specialties, setSpecialties] = useState<string[]>([]);

  useEffect(() => {
    if (!user || user.role !== 'proveedor') { setLoading(false); return; }
    (async () => {
      // Resolve provider_id: prefer providers.email match, else profiles.provider_id, else first provider
      let providerId: string | null = null;
      const { data: byEmail } = await supabase.from('providers').select('id, specialties').eq('email', user.email).maybeSingle();
      if (byEmail) { providerId = byEmail.id; setSpecialties(byEmail.specialties ?? []); }
      if (!providerId && user.providerId) {
        providerId = user.providerId;
        const { data: p } = await supabase.from('providers').select('specialties').eq('id', user.providerId).maybeSingle();
        setSpecialties(p?.specialties ?? []);
      }
      if (!providerId) {
        const { data: any1 } = await supabase.from('providers').select('id, specialties').limit(1).maybeSingle();
        if (any1) { providerId = any1.id; setSpecialties(any1.specialties ?? []); }
      }
      if (!providerId) { setLoading(false); return; }

      const { data: existing } = await supabase.from('provider_profiles').select('*').eq('provider_id', providerId).maybeSingle();
      if (existing) {
        setProfile(existing as ProviderProfileRow);
      } else {
        const { data: created } = await supabase.from('provider_profiles').insert({
          provider_id: providerId,
          owner_user_id: user.id,
          contact_email: user.email,
          contact_name: user.name ?? null,
        }).select().single();
        if (created) setProfile(created as ProviderProfileRow);
      }
      setLoading(false);
    })();
  }, [user]);

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

  if (loading || !profile) {
    return <div className="p-6 flex items-center justify-center"><Loader2 className="h-6 w-6 animate-spin" /></div>;
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

// Keep MOCK_PROVIDERS imported to preserve type linkage
void MOCK_PROVIDERS;