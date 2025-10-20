export interface Provider {
  id: string;
  name: string;
  email: string;
  specialties: string[];
  rating: number;
}

export type ServiceType = 'emergencia' | 'correctivo' | 'preventivo' | 'proyecto';

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
  selectedProviders: string[];
  status: 'draft' | 'sent' | 'quoted' | 'completed';
  createdAt: string;
  createdBy: string;
}

export const MOCK_PROVIDERS: Provider[] = [
  {
    id: '1',
    name: 'Servicios Técnicos Integrales S.A.',
    email: 'contacto@sti.com',
    specialties: ['Mantenimiento Preventivo', 'Mantenimiento Correctivo'],
    rating: 4.8,
  },
  {
    id: '2',
    name: 'Reparaciones Express Ltda.',
    email: 'servicios@reparacionesexpress.com',
    specialties: ['Emergencias', 'Reparaciones Urgentes'],
    rating: 4.5,
  },
  {
    id: '3',
    name: 'Proyectos y Obras Industriales',
    email: 'info@proyectosindustriales.com',
    specialties: ['Proyectos', 'Instalaciones'],
    rating: 4.9,
  },
  {
    id: '4',
    name: 'Mantenimiento Global Corp.',
    email: 'ventas@mantenimientoglobal.com',
    specialties: ['Mantenimiento Preventivo', 'Mantenimiento Correctivo', 'Proyectos'],
    rating: 4.7,
  },
  {
    id: '5',
    name: 'Soluciones Técnicas del Norte',
    email: 'contacto@solucionesnorte.com',
    specialties: ['Emergencias', 'Mantenimiento Correctivo'],
    rating: 4.6,
  },
  {
    id: '6',
    name: 'Ingeniería y Servicios Avanzados',
    email: 'info@ingenieriaavanzada.com',
    specialties: ['Proyectos', 'Mantenimiento Preventivo'],
    rating: 4.9,
  },
];
