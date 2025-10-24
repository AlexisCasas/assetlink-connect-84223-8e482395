import { supabase } from '@/integrations/supabase/client';
import { MOCK_PROVIDERS } from '@/types/request';

export const seedDatabase = async () => {
  try {
    // Check if providers already exist
    const { data: existingProviders } = await supabase
      .from('providers')
      .select('id')
      .limit(1);

    if (existingProviders && existingProviders.length > 0) {
      console.log('Database already seeded');
      return;
    }

    // Insert providers
    const providerInserts = MOCK_PROVIDERS.map(p => ({
      id: p.id,
      name: p.name,
      email: p.email,
      specialties: p.specialties,
      rating: p.rating,
      certified: p.certified || false
    }));

    const { error: providerError } = await supabase
      .from('providers')
      .insert(providerInserts);

    if (providerError) {
      console.error('Error inserting providers:', providerError);
      return;
    }

    // Insert team members
    const teamMemberInserts = MOCK_PROVIDERS.flatMap(p => 
      (p.team || []).map(tm => ({
        id: tm.id,
        provider_id: p.id,
        name: tm.name,
        email: tm.email
      }))
    );

    const { error: teamError } = await supabase
      .from('team_members')
      .insert(teamMemberInserts);

    if (teamError) {
      console.error('Error inserting team members:', teamError);
      return;
    }

    // Insert sample requests
    const sampleRequests = [
      {
        request_number: 'REQ-2025-001',
        description: 'Reparación urgente de sistema de aire acondicionado',
        asset: 'HVAC-001',
        location: 'Edificio A - Piso 3',
        service_type: 'emergencia' as const,
        observations: 'Sistema no enciende, temperatura elevada en área',
        deadline: new Date(Date.now() + 2 * 24 * 60 * 60 * 1000).toISOString(),
        status: 'sent' as const,
        created_by: 'cliente@test.com',
        priority: 1,
        client_name: 'Corporación XYZ',
        client_branch: 'Sede Central',
        is_public: true
      },
      {
        request_number: 'REQ-2025-002',
        description: 'Mantenimiento preventivo de montacargas',
        asset: 'MONTA-002',
        location: 'Bodega Principal',
        service_type: 'preventivo' as const,
        observations: 'Revisión trimestral programada',
        deadline: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString(),
        start_time: new Date(Date.now() + 3 * 24 * 60 * 60 * 1000).toISOString(),
        status: 'sent' as const,
        created_by: 'cliente@test.com',
        priority: 3,
        client_name: 'Industrias ABC',
        client_branch: 'Planta Norte',
        is_public: true
      },
      {
        request_number: 'REQ-2025-003',
        description: 'Instalación de nuevo sistema eléctrico',
        asset: 'ELEC-001',
        location: 'Edificio B - Piso 2',
        service_type: 'proyecto' as const,
        observations: 'Proyecto de ampliación de capacidad eléctrica',
        deadline: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString(),
        start_time: new Date(Date.now() + 15 * 24 * 60 * 60 * 1000).toISOString(),
        status: 'sent' as const,
        created_by: 'cliente@test.com',
        priority: 4,
        client_name: 'Comercial DEF',
        client_branch: 'Oficinas Centrales',
        is_public: true
      },
      {
        request_number: 'REQ-2025-004',
        description: 'Reparación de fuga en sistema hidráulico',
        asset: 'HYD-003',
        location: 'Planta de Producción',
        service_type: 'correctivo' as const,
        observations: 'Fuga detectada en tubería principal',
        deadline: new Date(Date.now() + 5 * 24 * 60 * 60 * 1000).toISOString(),
        start_time: new Date(Date.now() + 2 * 24 * 60 * 60 * 1000).toISOString(),
        status: 'sent' as const,
        created_by: 'cliente@test.com',
        priority: 2,
        client_name: 'Fábrica GHI',
        client_branch: 'Planta 1',
        is_public: false
      },
      {
        request_number: 'REQ-2025-005',
        description: 'Mantenimiento de generador de emergencia',
        asset: 'GEN-001',
        location: 'Cuarto de Máquinas',
        service_type: 'preventivo' as const,
        observations: 'Mantenimiento anual programado',
        deadline: new Date(Date.now() + 10 * 24 * 60 * 60 * 1000).toISOString(),
        start_time: new Date(Date.now() + 5 * 24 * 60 * 60 * 1000).toISOString(),
        status: 'sent' as const,
        created_by: 'cliente@test.com',
        priority: 3,
        client_name: 'Hospital JKL',
        client_branch: 'Sede Principal',
        is_public: false
      }
    ];

    const { error: requestError, data: insertedRequests } = await supabase
      .from('requests')
      .insert(sampleRequests)
      .select();

    if (requestError) {
      console.error('Error inserting requests:', requestError);
      return;
    }

    // Link some providers to the non-public request
    if (insertedRequests && insertedRequests.length > 0) {
      const nonPublicRequest = insertedRequests.find(r => !r.is_public);
      if (nonPublicRequest) {
        await supabase
          .from('request_providers')
          .insert([
            { request_id: nonPublicRequest.id, provider_id: '1' },
            { request_id: nonPublicRequest.id, provider_id: '2' }
          ]);
      }
    }

    console.log('Database seeded successfully');
  } catch (error) {
    console.error('Error seeding database:', error);
  }
};
