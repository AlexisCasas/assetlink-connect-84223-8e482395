export type CertificationStatus = 'not_started' | 'in_review' | 'certified' | 'rejected';

export interface ProviderProfileRow {
  provider_id: string;
  owner_user_id: string;
  contact_name: string | null;
  contact_email: string | null;
  phone: string | null;
  whatsapp_phone: string | null;
  position: string | null;
  business_name: string | null;
  commercial_name: string | null;
  tax_id: string | null;
  country: string | null;
  currency: string | null;
  timezone: string | null;
  fiscal_address: string | null;
  city: string | null;
  region: string | null;
  website: string | null;
  industry: string | null;
  logo_url: string | null;
  company_description: string | null;
  foundation_year: number | null;
  employee_range: string | null;
  coverage_area: string | null;
  presentation_letter_url: string | null;
  presentation_letter_name: string | null;
  receive_all_invitations: boolean;
  certification_status: CertificationStatus;
}

export interface ProviderCommercialClient {
  id: string;
  provider_id: string;
  business_name: string;
  contact_person: string | null;
  email: string | null;
  phone: string | null;
  extension: string | null;
}

export const EMPLOYEE_RANGES = [
  '1 a 5',
  'Entre 6 a 20',
  'Entre 21 a 50',
  'Entre 51 a 200',
  'Más de 200',
];

export const COUNTRIES = ['Perú', 'Chile', 'Colombia', 'México', 'Argentina', 'Ecuador'];
export const CURRENCIES = ['PEN', 'USD', 'CLP', 'COP', 'MXN', 'ARS'];
export const TIMEZONES = ['America/Lima', 'America/Santiago', 'America/Bogota', 'America/Mexico_City', 'America/Argentina/Buenos_Aires'];