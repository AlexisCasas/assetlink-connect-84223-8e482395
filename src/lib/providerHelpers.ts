import { supabase } from '@/integrations/supabase/client';

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export const isValidUuid = (v: unknown): v is string => typeof v === 'string' && UUID_RE.test(v);

export async function ensureProviderForUser(user: { email: string; role: string }): Promise<string> {
  const { data: existing, error: fErr } = await supabase
    .from('providers')
    .select('id')
    .eq('email', user.email)
    .maybeSingle();
  if (fErr) throw fErr;
  if (existing?.id) return existing.id;

  if (user.role !== 'proveedor') {
    throw new Error('No existe un proveedor asociado a este usuario.');
  }

  const { data: created, error: iErr } = await supabase
    .from('providers')
    .insert({
      name: 'ROMAX CONTRATISTAS S.A.C.',
      email: user.email,
      specialties: ['Mantenimiento', 'Servicios Generales', 'Instalaciones'],
      rating: 0,
      certified: false,
    })
    .select('id')
    .single();
  if (iErr) throw iErr;
  return created.id;
}

export const DEMO_PROFILE_DEFAULTS = {
  contact_name: 'Proveedor Demo',
  contact_email: 'proveedor@test.com',
  phone: '956604785',
  whatsapp_phone: '956604785',
  position: 'Gerente de Operaciones',
  business_name: 'ROMAX CONTRATISTAS S.A.C.',
  commercial_name: 'ROMAX',
  tax_id: '20604268843',
  country: 'Perú',
  currency: 'PEN',
  timezone: 'America/Lima',
  city: 'Lima',
  region: 'Lima',
  industry: 'Mantenimiento y servicios generales',
  foundation_year: 2019,
  employee_range: 'Entre 6 a 20',
  coverage_area: 'Lima, Norte, Sur, provincia',
  receive_all_invitations: true,
  certification_status: 'not_started' as const,
};
