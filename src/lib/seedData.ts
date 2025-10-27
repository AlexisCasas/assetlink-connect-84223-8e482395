import { supabase } from '@/integrations/supabase/client';

// Sample providers data (without manual IDs - let DB generate UUIDs)
const PROVIDERS_DATA = [
  { name: 'Servicios Técnicos Integrales S.A.', email: 'contacto@sti.com', specialties: ['Mantenimiento Preventivo', 'Mantenimiento Correctivo'], rating: 4.8, certified: true },
  { name: 'Reparaciones Express Ltda.', email: 'servicios@reparacionesexpress.com', specialties: ['Emergencias', 'Reparaciones Urgentes'], rating: 4.5, certified: true },
  { name: 'Proyectos y Obras Industriales', email: 'info@proyectosindustriales.com', specialties: ['Proyectos', 'Instalaciones'], rating: 4.9, certified: true },
  { name: 'Mantenimiento Global Corp.', email: 'ventas@mantenimientoglobal.com', specialties: ['Mantenimiento Preventivo', 'Mantenimiento Correctivo', 'Proyectos'], rating: 4.7, certified: true },
  { name: 'Soluciones Técnicas del Norte', email: 'contacto@solucionesnorte.com', specialties: ['Emergencias', 'Mantenimiento Correctivo'], rating: 4.6, certified: false },
];

const TEAM_MEMBERS = [
  { name: 'Juan Pérez', email: 'juan@sti.com', providerIndex: 0 },
  { name: 'María García', email: 'maria@sti.com', providerIndex: 0 },
  { name: 'Carlos Rodríguez', email: 'carlos@reparaciones.com', providerIndex: 1 },
  { name: 'Ana Martínez', email: 'ana@proyectos.com', providerIndex: 2 },
  { name: 'Luis Torres', email: 'luis@proyectos.com', providerIndex: 2 },
];

const SAMPLE_REQUESTS = [
  {
    request_number: 'SOL-001234',
    description: 'Revisión general del motor y sistema de frenos',
    asset: 'Bus Mercedes Benz O500',
    location: 'Terminal Norte',
    service_type: 'preventivo' as const,
    observations: 'Programar con anticipación',
    deadline: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString(),
    start_time: new Date(Date.now() + 10 * 24 * 60 * 60 * 1000).toISOString(),
    status: 'sent' as const,
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
    service_type: 'emergencia' as const,
    observations: 'Atención inmediata requerida',
    deadline: new Date(Date.now() + 1 * 24 * 60 * 60 * 1000).toISOString(),
    status: 'sent' as const,
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
    service_type: 'correctivo' as const,
    observations: 'Verificar desgaste de ejes',
    deadline: new Date(Date.now() + 5 * 24 * 60 * 60 * 1000).toISOString(),
    start_time: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString(),
    status: 'sent' as const,
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
    service_type: 'proyecto' as const,
    observations: 'Proyecto a largo plazo',
    deadline: new Date(Date.now() + 14 * 24 * 60 * 60 * 1000).toISOString(),
    start_time: new Date(Date.now() + 21 * 24 * 60 * 60 * 1000).toISOString(),
    status: 'sent' as const,
    created_by: 'admin@empresa.com',
    priority: 4,
    client_name: 'Transportes Unidos S.A.',
    client_branch: 'Sede Principal',
    is_public: false,
  },
  {
    request_number: 'SOL-001238',
    description: 'Mantenimiento de aire acondicionado',
    asset: 'Bus Marcopolo G7',
    location: 'Terminal Este',
    service_type: 'correctivo' as const,
    observations: 'Cliente reporta que no enfría',
    deadline: new Date(Date.now() + 4 * 24 * 60 * 60 * 1000).toISOString(),
    start_time: new Date(Date.now() + 6 * 24 * 60 * 60 * 1000).toISOString(),
    status: 'sent' as const,
    created_by: 'admin@empresa.com',
    priority: 2,
    client_name: 'Transportes Unidos S.A.',
    client_branch: 'Lima Este',
    is_public: false,
  },
  {
    request_number: 'SOL-001239',
    description: 'Inspección de sistema de suspensión',
    asset: 'Bus Volvo B9R',
    location: 'Terminal Oeste',
    service_type: 'preventivo' as const,
    observations: 'Ruidos anormales reportados',
    deadline: new Date(Date.now() + 6 * 24 * 60 * 60 * 1000).toISOString(),
    start_time: new Date(Date.now() + 8 * 24 * 60 * 60 * 1000).toISOString(),
    status: 'sent' as const,
    created_by: 'admin@empresa.com',
    priority: 2,
    client_name: 'Express Cargo S.A.C.',
    client_branch: 'San Isidro',
    is_public: false,
  },
  {
    request_number: 'SOL-001240',
    description: 'Reparación de caja de cambios',
    asset: 'Bus Mercedes Benz OF-1721',
    location: 'Taller Principal',
    service_type: 'correctivo' as const,
    observations: 'Dificultad al cambiar marchas',
    deadline: new Date(Date.now() + 3 * 24 * 60 * 60 * 1000).toISOString(),
    status: 'sent' as const,
    created_by: 'admin@empresa.com',
    priority: 1,
    client_name: 'Express Cargo S.A.C.',
    client_branch: 'Callao',
    is_public: false,
  },
  {
    request_number: 'SOL-001241',
    description: 'Modernización de sistema de iluminación LED',
    asset: 'Flota de 20 buses',
    location: 'Múltiples sedes',
    service_type: 'proyecto' as const,
    observations: 'Incluye instalación de luces interiores y exteriores',
    deadline: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString(),
    start_time: new Date(Date.now() + 35 * 24 * 60 * 60 * 1000).toISOString(),
    status: 'sent' as const,
    created_by: 'admin@empresa.com',
    priority: 4,
    client_name: 'Turismo Nacional EIRL',
    client_branch: 'Sede Central',
    is_public: false,
  },
  {
    request_number: 'SOL-001242',
    description: 'Falla en sistema de dirección hidráulica',
    asset: 'Bus Scania K310',
    location: 'Terminal Norte',
    service_type: 'emergencia' as const,
    observations: 'Bus no puede circular, alta prioridad',
    deadline: new Date(Date.now() + 0.5 * 24 * 60 * 60 * 1000).toISOString(),
    status: 'sent' as const,
    created_by: 'admin@empresa.com',
    priority: 1,
    client_name: 'Turismo Nacional EIRL',
    client_branch: 'Lima Norte',
    is_public: false,
  },
  {
    request_number: 'SOL-001243',
    description: 'Revisión de frenos ABS',
    asset: 'Bus Marcopolo Paradiso 1200',
    location: 'Terminal Sur',
    service_type: 'preventivo' as const,
    observations: 'Mantenimiento programado según kilometraje',
    deadline: new Date(Date.now() + 8 * 24 * 60 * 60 * 1000).toISOString(),
    start_time: new Date(Date.now() + 10 * 24 * 60 * 60 * 1000).toISOString(),
    status: 'sent' as const,
    created_by: 'admin@empresa.com',
    priority: 3,
    client_name: 'Rutas del Perú S.A.',
    client_branch: 'Chorrillos',
    is_public: false,
  },
  {
    request_number: 'SOL-001244',
    description: 'Cambio de motor diésel completo',
    asset: 'Bus Volvo B12R',
    location: 'Taller Especializado',
    service_type: 'correctivo' as const,
    observations: 'Motor con falla grave, requiere reemplazo',
    deadline: new Date(Date.now() + 15 * 24 * 60 * 60 * 1000).toISOString(),
    start_time: new Date(Date.now() + 18 * 24 * 60 * 60 * 1000).toISOString(),
    status: 'sent' as const,
    created_by: 'admin@empresa.com',
    priority: 1,
    client_name: 'Rutas del Perú S.A.',
    client_branch: 'Villa El Salvador',
    is_public: false,
  },
  {
    request_number: 'SOL-001245',
    description: 'Instalación de sistema de videovigilancia',
    asset: 'Bus Mercedes Benz O400',
    location: 'Terminal Este',
    service_type: 'proyecto' as const,
    observations: 'Incluye 6 cámaras HD y DVR',
    deadline: new Date(Date.now() + 12 * 24 * 60 * 60 * 1000).toISOString(),
    start_time: new Date(Date.now() + 15 * 24 * 60 * 60 * 1000).toISOString(),
    status: 'sent' as const,
    created_by: 'admin@empresa.com',
    priority: 3,
    client_name: 'Móvil Tours S.A.',
    client_branch: 'Ate Vitarte',
    is_public: false,
  },
  {
    request_number: 'SOL-001246',
    description: 'Reparación de sistema de refrigeración',
    asset: 'Bus Scania K380',
    location: 'Taller Central',
    service_type: 'correctivo' as const,
    observations: 'Sobrecalentamiento del motor',
    deadline: new Date(Date.now() + 2 * 24 * 60 * 60 * 1000).toISOString(),
    status: 'sent' as const,
    created_by: 'admin@empresa.com',
    priority: 1,
    client_name: 'Móvil Tours S.A.',
    client_branch: 'La Victoria',
    is_public: false,
  },
  {
    request_number: 'SOL-001247',
    description: 'Mantenimiento preventivo integral',
    asset: 'Bus Volvo B270F',
    location: 'Terminal Oeste',
    service_type: 'preventivo' as const,
    observations: 'Revisión de 10,000 km',
    deadline: new Date(Date.now() + 9 * 24 * 60 * 60 * 1000).toISOString(),
    start_time: new Date(Date.now() + 11 * 24 * 60 * 60 * 1000).toISOString(),
    status: 'sent' as const,
    created_by: 'admin@empresa.com',
    priority: 3,
    client_name: 'Cruz del Sur S.A.C.',
    client_branch: 'Javier Prado',
    is_public: false,
  },
  {
    request_number: 'SOL-001248',
    description: 'Falla en sistema eléctrico de puertas',
    asset: 'Bus Mercedes Benz OF-1722',
    location: 'Terminal Norte',
    service_type: 'emergencia' as const,
    observations: 'Puertas no abren/cierran correctamente',
    deadline: new Date(Date.now() + 1 * 24 * 60 * 60 * 1000).toISOString(),
    status: 'sent' as const,
    created_by: 'admin@empresa.com',
    priority: 1,
    client_name: 'Cruz del Sur S.A.C.',
    client_branch: 'Fiori',
    is_public: false,
  },
  {
    request_number: 'SOL-001249',
    description: 'Renovación de asientos de pasajeros',
    asset: 'Bus Marcopolo Andare Class',
    location: 'Taller de Tapicería',
    service_type: 'proyecto' as const,
    observations: 'Incluye 40 asientos nuevos',
    deadline: new Date(Date.now() + 20 * 24 * 60 * 60 * 1000).toISOString(),
    start_time: new Date(Date.now() + 25 * 24 * 60 * 60 * 1000).toISOString(),
    status: 'sent' as const,
    created_by: 'admin@empresa.com',
    priority: 4,
    client_name: 'Oltursa S.A.',
    client_branch: 'San Miguel',
    is_public: false,
  },
  {
    request_number: 'SOL-001250',
    description: 'Cambio de batería y alternador',
    asset: 'Bus Scania K124',
    location: 'Terminal Sur',
    service_type: 'correctivo' as const,
    observations: 'Batería descargada frecuentemente',
    deadline: new Date(Date.now() + 4 * 24 * 60 * 60 * 1000).toISOString(),
    status: 'sent' as const,
    created_by: 'admin@empresa.com',
    priority: 2,
    client_name: 'Oltursa S.A.',
    client_branch: 'Barranco',
    is_public: false,
  },
  {
    request_number: 'SOL-001251',
    description: 'Inspección técnica vehicular preparatoria',
    asset: 'Bus Volvo B340M',
    location: 'Taller Certificado',
    service_type: 'preventivo' as const,
    observations: 'Preparación para ITV anual',
    deadline: new Date(Date.now() + 10 * 24 * 60 * 60 * 1000).toISOString(),
    start_time: new Date(Date.now() + 12 * 24 * 60 * 60 * 1000).toISOString(),
    status: 'sent' as const,
    created_by: 'admin@empresa.com',
    priority: 3,
    client_name: 'Soyuz S.A.',
    client_branch: 'Surco',
    is_public: false,
  },
  {
    request_number: 'SOL-001252',
    description: 'Reparación de sistema de escape',
    asset: 'Bus Mercedes Benz LO-915',
    location: 'Taller Principal',
    service_type: 'correctivo' as const,
    observations: 'Ruidos excesivos y fuga de gases',
    deadline: new Date(Date.now() + 5 * 24 * 60 * 60 * 1000).toISOString(),
    start_time: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString(),
    status: 'sent' as const,
    created_by: 'admin@empresa.com',
    priority: 2,
    client_name: 'Soyuz S.A.',
    client_branch: 'La Molina',
    is_public: false,
  },
  {
    request_number: 'SOL-001253',
    description: 'Implementación de sistema de rastreo satelital',
    asset: 'Flota completa - 25 buses',
    location: 'Todas las unidades',
    service_type: 'proyecto' as const,
    observations: 'GPS con monitoreo en tiempo real',
    deadline: new Date(Date.now() + 40 * 24 * 60 * 60 * 1000).toISOString(),
    start_time: new Date(Date.now() + 45 * 24 * 60 * 60 * 1000).toISOString(),
    status: 'sent' as const,
    created_by: 'admin@empresa.com',
    priority: 4,
    client_name: 'Línea S.A.',
    client_branch: 'Oficina Central',
    is_public: false,
  },
];

export const seedDatabase = async (): Promise<{ success: boolean; error?: any }> => {
  try {
    console.log('Starting database seeding...');

    // Check if data already exists to avoid duplicates
    const { data: existingRequests } = await supabase
      .from('requests')
      .select('id')
      .limit(1);

    if (existingRequests && existingRequests.length > 0) {
      console.log('Database already has data. Skipping seeding.');
      return { success: true };
    }

    // Step 1: Insert providers and capture their IDs
    console.log('Seeding providers...');
    const { data: insertedProviders, error: providersError } = await supabase
      .from('providers')
      .insert(PROVIDERS_DATA)
      .select();

    if (providersError) {
      console.error('Error seeding providers:', providersError);
      return { success: false, error: providersError };
    }

    if (!insertedProviders || insertedProviders.length === 0) {
      console.error('No providers were inserted');
      return { success: false, error: 'No providers inserted' };
    }

    console.log(`Successfully inserted ${insertedProviders.length} providers`);

    // Step 2: Insert team members linked to providers
    console.log('Seeding team members...');
    const teamMembersWithProviderIds = TEAM_MEMBERS.map(member => ({
      name: member.name,
      email: member.email,
      provider_id: insertedProviders[member.providerIndex].id
    }));

    const { data: insertedTeamMembers, error: teamMembersError } = await supabase
      .from('team_members')
      .insert(teamMembersWithProviderIds)
      .select();

    if (teamMembersError) {
      console.error('Error seeding team members:', teamMembersError);
      return { success: false, error: teamMembersError };
    }

    console.log(`Successfully inserted ${insertedTeamMembers?.length || 0} team members`);

    // Step 3: Insert requests
    console.log('Seeding requests...');
    const { data: insertedRequests, error: requestsError } = await supabase
      .from('requests')
      .insert(SAMPLE_REQUESTS)
      .select();

    if (requestsError) {
      console.error('Error seeding requests:', requestsError);
      return { success: false, error: requestsError };
    }

    if (!insertedRequests || insertedRequests.length === 0) {
      console.error('No requests were inserted');
      return { success: false, error: 'No requests inserted' };
    }

    console.log(`Successfully inserted ${insertedRequests.length} requests`);

    // Step 4: Create relationships between ALL requests and ALL providers
    console.log('Creating request-provider relationships...');
    const requestProviderRelations = [];
    
    for (const request of insertedRequests) {
      for (const provider of insertedProviders) {
        requestProviderRelations.push({
          request_id: request.id,
          provider_id: provider.id
        });
      }
    }

    const { error: relationsError } = await supabase
      .from('request_providers')
      .insert(requestProviderRelations);

    if (relationsError) {
      console.error('Error creating request-provider relationships:', relationsError);
      return { success: false, error: relationsError };
    }

    console.log(`Successfully created ${requestProviderRelations.length} request-provider relationships`);

    // Step 5: Create sample assignments (assign first 10 requests to team members)
    if (insertedTeamMembers && insertedTeamMembers.length > 0 && insertedRequests.length >= 10) {
      console.log('Creating sample assignments...');
      const assignments = insertedRequests.slice(0, 10).map((request, index) => {
        const teamMember = insertedTeamMembers[index % insertedTeamMembers.length];
        const provider = insertedProviders[Math.floor(index / insertedTeamMembers.length) % insertedProviders.length];
        const deadline = new Date();
        deadline.setDate(deadline.getDate() + (index + 2) * 2); // 4, 6, 8, 10... days from now

        // Vary statuses: some pending, some accepted, some rejected
        let status: 'pending' | 'accepted' | 'rejected' = 'pending';
        let rejection_reason = null;
        let responded_at = null;
        
        if (index % 3 === 1) {
          status = 'accepted';
          responded_at = new Date(Date.now() - (index * 24 * 60 * 60 * 1000)).toISOString();
        } else if (index % 3 === 2) {
          status = 'rejected';
          rejection_reason = 'No cuento con las herramientas necesarias para este trabajo';
          responded_at = new Date(Date.now() - (index * 24 * 60 * 60 * 1000)).toISOString();
        }

        return {
          request_id: request.id,
          provider_id: provider.id,
          team_member_id: teamMember.id,
          team_member_name: teamMember.name,
          max_deadline: deadline.toISOString(),
          reason: index % 3 === 0 ? 'Especialidad en el área requerida' : 'Asignado por disponibilidad',
          status,
          rejection_reason,
          responded_at
        };
      });

      const { error: assignmentsError } = await supabase
        .from('assignments')
        .insert(assignments);

      if (assignmentsError) {
        console.error('Error creating assignments:', assignmentsError);
        return { success: false, error: assignmentsError };
      }

      console.log(`Successfully created ${assignments.length} sample assignments`);
    }

    console.log('Database seeding completed successfully!');
    
    return { success: true };
  } catch (error) {
    console.error('Unexpected error during seeding:', error);
    return { success: false, error };
  }
};
