import { useAuth } from '@/contexts/AuthContext';
import { getFacilityManagementMode } from '@/lib/facilityManagement';
import { ClientFacilityManagersView } from './ClientFacilityManagersView';
import { FacilityManagerPortfolioView } from './FacilityManagerPortfolioView';

export function FacilityManagementAccessDenied() {
  return (
    <div className="flex h-full items-center justify-center p-6">
      <p className="text-sm text-muted-foreground">
        La gestión de Facility Managers solo está disponible para propietarios y administradores de una organización cliente o Facility Manager.
      </p>
    </div>
  );
}

/** #facility-management: la variante depende del tipo de la organización
 * activa y del rol del usuario en ella. Es un gate de UI; cada RPC vuelve a
 * autorizar en el servidor. */
export function FacilityManagementView() {
  const { currentOrganization, currentMembership } = useAuth();
  const mode = getFacilityManagementMode(currentOrganization, currentMembership);
  if (mode === 'client') return <ClientFacilityManagersView />;
  if (mode === 'facility_manager') return <FacilityManagerPortfolioView />;
  return <FacilityManagementAccessDenied />;
}
