import { supabase } from '@/integrations/supabase/client';

const PROVIDERS_DATA = [
  { name: 'Servicios Técnicos Integrales S.A.', email: 'contacto@sti.com', specialties: ['Mantenimiento Preventivo', 'Mantenimiento Correctivo'], rating: 4.8, certified: true },
  { name: 'Reparaciones Express Ltda.', email: 'servicios@reparacionesexpress.com', specialties: ['Emergencias', 'Reparaciones Urgentes'], rating: 4.5, certified: true },
  { name: 'Proyectos y Obras Industriales', email: 'info@proyectosindustriales.com', specialties: ['Proyectos', 'Instalaciones'], rating: 4.9, certified: true },
  { name: 'Mantenimiento Global Corp.', email: 'ventas@mantenimientoglobal.com', specialties: ['Mantenimiento Preventivo', 'Mantenimiento Correctivo', 'Proyectos'], rating: 4.7, certified: true },
  { name: 'Soluciones Técnicas del Norte', email: 'contacto@solucionesnorte.com', specialties: ['Emergencias', 'Mantenimiento Correctivo'], rating: 4.6, certified: false },
  { name: 'Ingeniería y Servicios Avanzados', email: 'info@ingenieriaavanzada.com', specialties: ['Proyectos', 'Mantenimiento Preventivo'], rating: 4.9, certified: true },
  { name: 'TecnoService Pro', email: 'admin@tecnoservicepro.com', specialties: ['Mantenimiento Correctivo', 'Emergencias'], rating: 4.4, certified: false },
  { name: 'Mantenimiento Industrial Express', email: 'contacto@mie.com', specialties: ['Mantenimiento Preventivo', 'Proyectos'], rating: 4.6, certified: true },
  { name: 'Servicios Rápidos S.A.C.', email: 'ventas@serviciosrapidos.com', specialties: ['Emergencias', 'Reparaciones Urgentes'], rating: 4.3, certified: false },
  { name: 'Obras y Proyectos del Sur', email: 'proyectos@obrassur.com', specialties: ['Proyectos', 'Instalaciones'], rating: 4.8, certified: true },
  { name: 'Mantenimiento Integral 360', email: 'info@mi360.com', specialties: ['Mantenimiento Preventivo', 'Mantenimiento Correctivo'], rating: 4.7, certified: true },
  { name: 'Técnicos Especializados SAC', email: 'contacto@tecnicos.com', specialties: ['Emergencias', 'Mantenimiento Correctivo'], rating: 4.5, certified: false },
  { name: 'Proyectos Modernos E.I.R.L.', email: 'ventas@proyectosmodernos.com', specialties: ['Proyectos', 'Instalaciones'], rating: 4.6, certified: true },
  { name: 'Servicios Generales Premium', email: 'admin@sgpremium.com', specialties: ['Mantenimiento Preventivo', 'Proyectos'], rating: 4.8, certified: true },
  { name: 'Reparaciones del Centro', email: 'info@reparacionescentro.com', specialties: ['Mantenimiento Correctivo', 'Emergencias'], rating: 4.4, certified: false },
  { name: 'Ingeniería Total S.A.', email: 'contacto@ingenieriatotal.com', specialties: ['Proyectos', 'Instalaciones'], rating: 4.9, certified: true },
  { name: 'Mantenimiento Plus', email: 'ventas@mantenimientoplus.com', specialties: ['Mantenimiento Preventivo', 'Mantenimiento Correctivo'], rating: 4.5, certified: false },
  { name: 'Servicios Técnicos del Este', email: 'este@servicios.com', specialties: ['Emergencias', 'Reparaciones Urgentes'], rating: 4.6, certified: true },
  { name: 'Proyectos & Soluciones', email: 'info@proyectosysoluciones.com', specialties: ['Proyectos', 'Mantenimiento Preventivo'], rating: 4.7, certified: true },
  { name: 'Operaciones Industriales SAC', email: 'admin@operacionesindustriales.com', specialties: ['Mantenimiento Correctivo', 'Proyectos'], rating: 4.5, certified: false },
];

const TEAM_MEMBERS = [
  { name: 'Juan Pérez', email: 'juan@sti.com', providerIndex: 0 },
  { name: 'María García', email: 'maria@sti.com', providerIndex: 0 },
  { name: 'Carlos Rodríguez', email: 'carlos@reparaciones.com', providerIndex: 1 },
  { name: 'Ana Martínez', email: 'ana@proyectos.com', providerIndex: 2 },
  { name: 'Luis Torres', email: 'luis@proyectos.com', providerIndex: 2 },
  { name: 'Pedro Sánchez', email: 'pedro@global.com', providerIndex: 3 },
  { name: 'Sofia López', email: 'sofia@norte.com', providerIndex: 4 },
  { name: 'Miguel Ángel', email: 'miguel@norte.com', providerIndex: 4 },
  { name: 'Roberto Díaz', email: 'roberto@ingenieria.com', providerIndex: 5 },
];

const SAMPLE_REQUESTS = [
  {
    request_number: 'SOL-001234',
    description: 'Revisión general del motor y sistema de frenos',
    asset: 'Bus Mercedes Benz O500',
    location: 'Terminal Norte',
    service_type: 'preventivo',
    observations: 'Programar con anticipación',
    deadline: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString(),
    start_time: new Date(Date.now() + 10 * 24 * 60 * 60 * 1000).toISOString(),
    status: 'sent',
    created_by: 'admin@empresa.com',
    priority: 3,
    client_name: 'Transportes Unidos S.A.',
    client_branch: 'Lima Centro',
    is_public: false,
  },
  {
    request_number: 'SOL-001235',
    description: 'Reparación urgente de sistema eléctrico',
    asset: 'Bus Volvo B7R',
    location: 'Terminal Sur',
    service_type: 'emergencia',
    observations: 'Atención inmediata requerida',
    deadline: new Date(Date.now() + 1 * 24 * 60 * 60 * 1000).toISOString(),
    status: 'sent',
    created_by: 'admin@empresa.com',
    priority: 1,
    client_name: 'Transportes Unidos S.A.',
    client_branch: 'Lima Sur',
    is_public: false,
  },
  {
    request_number: 'SOL-001236',
    description: 'Cambio de neumáticos y alineación',
    asset: 'Bus Scania K360',
    location: 'Taller Central',
    service_type: 'correctivo',
    observations: 'Verificar desgaste de ejes',
    deadline: new Date(Date.now() + 5 * 24 * 60 * 60 * 1000).toISOString(),
    start_time: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString(),
    status: 'sent',
    created_by: 'admin@empresa.com',
    priority: 2,
    client_name: 'Transportes Unidos S.A.',
    client_branch: 'Miraflores',
    is_public: false,
  },
  {
    request_number: 'SOL-001237',
    description: 'Instalación de sistema de GPS y cámaras',
    asset: 'Flota completa - 15 buses',
    location: 'Todas las sedes',
    service_type: 'proyecto',
    observations: 'Proyecto a largo plazo',
    deadline: new Date(Date.now() + 14 * 24 * 60 * 60 * 1000).toISOString(),
    start_time: new Date(Date.now() + 21 * 24 * 60 * 60 * 1000).toISOString(),
    status: 'sent',
    created_by: 'admin@empresa.com',
    priority: 4,
    client_name: 'Transportes Unidos S.A.',
    client_branch: 'Sede Principal',
    is_public: true,
  },
  {
    request_number: 'SOL-001238',
    description: 'Mantenimiento de aire acondicionado',
    asset: 'Bus Marcopolo G7',
    location: 'Terminal Este',
    service_type: 'correctivo',
    observations: 'Cliente reporta que no enfría',
    deadline: new Date(Date.now() + 4 * 24 * 60 * 60 * 1000).toISOString(),
    start_time: new Date(Date.now() + 6 * 24 * 60 * 60 * 1000).toISOString(),
    status: 'sent',
    created_by: 'admin@empresa.com',
    priority: 2,
    client_name: 'Transportes Unidos S.A.',
    client_branch: 'Lima Este',
    is_public: true,
  },
];

export const seedDatabase = async () => {
  try {
    console.log('Starting database seeding...');

    // 1. Insert providers
    const { data: insertedProviders, error: providersError } = await supabase
      .from('providers')
      .upsert(
        PROVIDERS_DATA.map((p, index) => ({
          id: `provider-${index + 1}`,
          ...p,
        })),
        { onConflict: 'id' }
      )
      .select();

    if (providersError) {
      console.error('Error inserting providers:', providersError);
      throw providersError;
    }

    console.log(`Inserted ${insertedProviders?.length} providers`);

    // 2. Insert team members
    if (insertedProviders && insertedProviders.length > 0) {
      const teamMembersData = TEAM_MEMBERS.map((tm, index) => ({
        id: `team-member-${index + 1}`,
        name: tm.name,
        email: tm.email,
        provider_id: insertedProviders[tm.providerIndex]?.id || insertedProviders[0].id,
      }));

      const { error: teamError } = await supabase
        .from('team_members')
        .upsert(teamMembersData, { onConflict: 'id' });

      if (teamError) {
        console.error('Error inserting team members:', teamError);
      } else {
        console.log(`Inserted ${teamMembersData.length} team members`);
      }
    }

    // 3. Insert sample requests
    const { data: insertedRequests, error: requestsError } = await supabase
      .from('requests')
      .upsert(
        SAMPLE_REQUESTS.map((r, index) => ({
          id: `request-${index + 1}`,
          ...r,
          service_type: r.service_type as 'emergencia' | 'correctivo' | 'preventivo' | 'proyecto',
        })),
        { onConflict: 'id' }
      )
      .select();

    if (requestsError) {
      console.error('Error inserting requests:', requestsError);
    } else {
      console.log(`Inserted ${insertedRequests?.length} requests`);
    }

    // 4. Link requests to providers
    if (insertedRequests && insertedProviders) {
      const requestProvidersData = [];
      
      // Link first 3 requests to first 3 providers
      for (let i = 0; i < 3 && i < insertedRequests.length; i++) {
        for (let j = 0; j < 3 && j < insertedProviders.length; j++) {
          requestProvidersData.push({
            request_id: insertedRequests[i].id,
            provider_id: insertedProviders[j].id,
          });
        }
      }

      if (requestProvidersData.length > 0) {
        const { error: rpError } = await supabase
          .from('request_providers')
          .upsert(requestProvidersData, { onConflict: 'id', ignoreDuplicates: true });

        if (rpError) {
          console.error('Error linking requests to providers:', rpError);
        } else {
          console.log(`Linked requests to providers`);
        }
      }
    }

    console.log('Database seeding completed successfully!');
    return { success: true };
  } catch (error) {
    console.error('Error seeding database:', error);
    return { success: false, error };
  }
};
