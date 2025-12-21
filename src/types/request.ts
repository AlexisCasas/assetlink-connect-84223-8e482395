export interface TeamMember {
  id: string;
  name: string;
  email: string;
  providerId: string;
}

export interface Provider {
  id: string;
  name: string;
  email: string;
  specialties: string[];
  rating: number;
  team?: TeamMember[];
  certified?: boolean;
  certificationDocuments?: File[];
}

export interface Assignment {
  teamMemberId: string;
  teamMemberName: string;
  reviewerId?: string;
  reviewerName?: string;
  approverId?: string;
  approverName?: string;
  assignedAt: string;
  maxDeadline: string;
  reason?: string;
}

export interface QuoteTableItem {
  id: string;
  description: string;
  unit: string; // UND, M2, GLN, etc.
  quantity: number;
  unitPrice: number;
  total: number;
}

export interface QuoteTableSection {
  title: string;
  items: QuoteTableItem[];
  subtotal: number;
}

export interface QuoteCondition {
  id: string;
  description: string;
}

export interface Quote {
  id: string;
  requestId: string;
  providerId: string;
  teamMemberId: string;
  amount: number;
  description: string;
  files?: File[];
  createdAt: string;
  status: 'draft' | 'submitted';
  // Nuevas secciones de la tabla de cotización
  serviceItems?: QuoteTableItem[];
  equipmentItems?: QuoteTableItem[];
  materialItems?: QuoteTableItem[];
  conditions?: QuoteCondition[];
  validityDate?: string;
  includesIGV?: boolean;
  needsTechnicalVisit?: boolean;
  elaboradoPor?: string;
  revisadoPor?: string;
  validoPor?: string;
}

export type ServiceType = 'emergencia' | 'correctivo' | 'preventivo' | 'proyecto';

export interface RequestDetailData {
  equipment?: string;
  subEquipment?: string;
  area?: string;
  subArea?: string;
  activities?: string;
  relevantMaterials?: string;
  quantity?: number;
  unitMeasure?: string;
  observation?: string;
  responsibleUser?: string;
  delegateType?: string;
  attachmentUrls?: string[];
}

export interface Request {
  id: string;
  requestNumber: string;
  description: string;
  asset: string;
  location: string;
  serviceType: ServiceType;
  observations?: string;
  images?: File[];
  documents?: File[];
  deadline: string;
  startTime?: string; // Para correctivo, preventivo y proyecto
  selectedProviders: string[]; // Vacío = solicitud pública
  status: 'draft' | 'sent' | 'quoted' | 'completed' | 'anulado';
  createdAt: string;
  createdBy: string;
  priority: number; // 1 = emergencia (más alta), 4 = proyecto (más baja)
  assignments?: { [providerId: string]: Assignment };
  technicalVisitRequested?: { [providerId: string]: boolean };
  quotes?: Quote[];
  clientName?: string;
  clientBranch?: string; // Sede o sucursal
  isPublic?: boolean; // True si no se seleccionaron proveedores
  notifiedAt?: string; // Última vez que se notificó a los proveedores
  // Nuevos campos de cabecera
  city?: string;
  store?: string;
  branch?: string;
  requiresVisit?: boolean;
  visitDate?: string;
  // Detalle (1 a muchos)
  details?: RequestDetailData[];
}

export const MOCK_PROVIDERS: Provider[] = [
  {
    id: '1',
    name: 'Servicios Técnicos Integrales S.A.',
    email: 'contacto@sti.com',
    specialties: ['Mantenimiento Preventivo', 'Mantenimiento Correctivo'],
    rating: 4.8,
    team: [
      { id: 'tm1', name: 'Juan Pérez', email: 'juan@sti.com', providerId: '1' },
      { id: 'tm2', name: 'María García', email: 'maria@sti.com', providerId: '1' },
    ],
  },
  {
    id: '2',
    name: 'Reparaciones Express Ltda.',
    email: 'servicios@reparacionesexpress.com',
    specialties: ['Emergencias', 'Reparaciones Urgentes'],
    rating: 4.5,
    team: [
      { id: 'tm3', name: 'Carlos Rodríguez', email: 'carlos@reparaciones.com', providerId: '2' },
    ],
  },
  {
    id: '3',
    name: 'Proyectos y Obras Industriales',
    email: 'info@proyectosindustriales.com',
    specialties: ['Proyectos', 'Instalaciones'],
    rating: 4.9,
    team: [
      { id: 'tm4', name: 'Ana Martínez', email: 'ana@proyectos.com', providerId: '3' },
      { id: 'tm5', name: 'Luis Torres', email: 'luis@proyectos.com', providerId: '3' },
    ],
  },
  {
    id: '4',
    name: 'Mantenimiento Global Corp.',
    email: 'ventas@mantenimientoglobal.com',
    specialties: ['Mantenimiento Preventivo', 'Mantenimiento Correctivo', 'Proyectos'],
    rating: 4.7,
    team: [
      { id: 'tm6', name: 'Pedro Sánchez', email: 'pedro@global.com', providerId: '4' },
    ],
  },
  {
    id: '5',
    name: 'Soluciones Técnicas del Norte',
    email: 'contacto@solucionesnorte.com',
    specialties: ['Emergencias', 'Mantenimiento Correctivo'],
    rating: 4.6,
    team: [
      { id: 'tm7', name: 'Sofia López', email: 'sofia@norte.com', providerId: '5' },
      { id: 'tm8', name: 'Miguel Ángel', email: 'miguel@norte.com', providerId: '5' },
    ],
  },
  {
    id: '6',
    name: 'Ingeniería y Servicios Avanzados',
    email: 'info@ingenieriaavanzada.com',
    specialties: ['Proyectos', 'Mantenimiento Preventivo'],
    rating: 4.9,
    team: [
      { id: 'tm9', name: 'Roberto Díaz', email: 'roberto@ingenieria.com', providerId: '6' },
    ],
  },
];
