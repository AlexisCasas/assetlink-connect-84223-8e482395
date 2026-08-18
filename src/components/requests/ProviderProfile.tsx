import { OrganizationProfile } from '@/components/organization/OrganizationProfile';

// Compatibility export for legacy imports. Provider data is now organization based.
export function ProviderProfile() {
  return <OrganizationProfile />;
}
