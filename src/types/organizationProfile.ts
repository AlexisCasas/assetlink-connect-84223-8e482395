export type OrganizationProfileClient = {
  razon_social: string;
  contact_name: string;
  email: string;
  phone: string;
  annex: string;
};

export type OrganizationProfileForm = {
  commercial_name: string;
  legal_name: string;
  tax_id: string;
  country: string;
  currency: string;
  timezone: string;
  contact_email: string;
  phone: string;
  whatsapp: string;
  website: string;
  logo_url: string;
  description: string;
  founded_year: string;
  employee_range: string;
  service_regions: string;
  primary_clients: OrganizationProfileClient[];
  presentation_file_url: string;
  certification_status: string;
  certification_notes: string;
  /** Only meaningful for provider-facing organizations (provider_company /
   * facility_manager / subcontractor_company) — belongs to the provider
   * itself, never to a client that homologates it. */
  specialties: string[];
};
