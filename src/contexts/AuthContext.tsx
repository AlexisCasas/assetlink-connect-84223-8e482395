import { createContext, useContext, useState, useEffect, ReactNode } from 'react';

export type UserRole = 'cliente' | 'proveedor' | 'team_member';

interface User {
  id: string;
  email: string;
  role: UserRole;
  name?: string;
  providerId?: string;
}

interface AuthContextType {
  user: User | null;
  login: (email: string, password: string, role: UserRole) => Promise<boolean>;
  register: (email: string, password: string, name: string, role: UserRole) => Promise<boolean>;
  logout: () => void;
  isAuthenticated: boolean;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

export const AuthProvider = ({ children }: { children: ReactNode }) => {
  const [user, setUser] = useState<User | null>(null);

  useEffect(() => {
    const storedUser = localStorage.getItem('user');
    if (storedUser) {
      setUser(JSON.parse(storedUser));
    }
  }, []);

  const login = async (email: string, password: string, role: UserRole): Promise<boolean> => {
    // Inicializar datos de ejemplo para cuentas de prueba
    if (email === 'cliente@test.com' && role === 'cliente') {
      initializeClientTestData();
    } else if (email === 'proveedor@test.com' && role === 'proveedor') {
      initializeProviderTestData();
    } else if (email === 'equipo@test.com' && role === 'team_member') {
      initializeTeamMemberTestData();
    }

    // Permitir login con cualquier cuenta sin registro previo
    let userData: User = {
      id: crypto.randomUUID(),
      email,
      role,
      name: email.split('@')[0],
    };

    // IDs específicos para cuentas de prueba
    if (email === 'cliente@test.com') {
      userData.id = 'test-client-001' as string;
      userData.name = 'Cliente Demo';
    } else if (email === 'proveedor@test.com') {
      userData.id = 'provider-1' as string;
      userData.name = 'Proveedor Demo';
    } else if (email === 'equipo@test.com') {
      userData.id = 'team-member-1' as string;
      userData.name = 'Juan Pérez';
      userData.providerId = 'provider-1';
    }

    setUser(userData);
    localStorage.setItem('user', JSON.stringify(userData));
    return true;
  };

  const register = async (email: string, password: string, name: string, role: UserRole): Promise<boolean> => {
    const users = JSON.parse(localStorage.getItem('users') || '[]');
    
    // Verificar si el usuario ya existe
    if (users.find((u: any) => u.email === email)) {
      return false;
    }

    const newUser = {
      id: crypto.randomUUID(),
      email,
      password,
      name,
      role,
    };

    users.push(newUser);
    localStorage.setItem('users', JSON.stringify(users));

    const userData = {
      id: newUser.id,
      email: newUser.email,
      role: newUser.role,
      name: newUser.name,
    };
    setUser(userData);
    localStorage.setItem('user', JSON.stringify(userData));
    return true;
  };

  const logout = () => {
    setUser(null);
    localStorage.removeItem('user');
  };

  return (
    <AuthContext.Provider
      value={{
        user,
        login,
        register,
        logout,
        isAuthenticated: !!user,
      }}
    >
      {children}
    </AuthContext.Provider>
  );
};

const initializeClientTestData = () => {
  const testRequests = [
    {
      id: 'req-001',
      requestNumber: 'SOL-2024-001',
      description: 'Reparación de sistema de aire acondicionado',
      asset: 'AC-001 - Aire Acondicionado Principal',
      location: 'Edificio A - Piso 3',
      serviceType: 'correctivo',
      observations: 'El equipo presenta fugas y no enfría adecuadamente',
      images: [],
      documents: [],
      quotationDeadline: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString(),
      selectedProviders: ['provider-1', 'provider-2'],
      status: 'sent',
      clientId: 'test-client-001',
      createdAt: new Date(Date.now() - 2 * 24 * 60 * 60 * 1000).toISOString(),
      startTime: new Date(Date.now() + 5 * 24 * 60 * 60 * 1000).toISOString(),
    },
    {
      id: 'req-002',
      requestNumber: 'SOL-2024-002',
      description: 'Mantenimiento preventivo de ascensores',
      asset: 'ASC-001 - Ascensor Principal',
      location: 'Edificio B',
      serviceType: 'preventivo',
      observations: 'Mantenimiento trimestral programado',
      images: [],
      documents: [],
      quotationDeadline: new Date(Date.now() + 10 * 24 * 60 * 60 * 1000).toISOString(),
      selectedProviders: ['provider-1'],
      status: 'sent',
      clientId: 'test-client-001',
      createdAt: new Date(Date.now() - 1 * 24 * 60 * 60 * 1000).toISOString(),
      startTime: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString(),
    }
  ];

  const testDrafts = [
    {
      id: 'draft-001',
      requestNumber: 'DRAFT-001',
      description: 'Instalación de sistema de seguridad',
      asset: 'SEG-001',
      location: 'Edificio C',
      serviceType: 'proyecto',
      observations: '',
      images: [],
      documents: [],
      quotationDeadline: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString(),
      selectedProviders: ['provider-3'],
      status: 'draft',
      clientId: 'test-client-001',
      createdAt: new Date().toISOString(),
      startTime: new Date(Date.now() + 60 * 24 * 60 * 60 * 1000).toISOString(),
    }
  ];

  localStorage.setItem('requests', JSON.stringify(testRequests));
  localStorage.setItem('drafts', JSON.stringify(testDrafts));
};

const initializeProviderTestData = () => {
  const testRequests = [
    {
      id: 'req-001',
      requestNumber: 'SOL-2024-001',
      description: 'Reparación de sistema de aire acondicionado',
      asset: 'AC-001 - Aire Acondicionado Principal',
      location: 'Edificio A - Piso 3',
      serviceType: 'correctivo',
      observations: 'El equipo presenta fugas y no enfría adecuadamente',
      images: [],
      documents: [],
      quotationDeadline: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString(),
      selectedProviders: ['provider-1', 'provider-2'],
      status: 'sent',
      clientId: 'test-client-001',
      createdAt: new Date(Date.now() - 2 * 24 * 60 * 60 * 1000).toISOString(),
      startTime: new Date(Date.now() + 5 * 24 * 60 * 60 * 1000).toISOString(),
      priority: 'media',
      assignments: [
        {
          id: 'assign-001',
          requestId: 'req-001',
          teamMemberId: 'team-member-1',
          teamMemberName: 'Juan Pérez',
          assignedBy: 'provider-1',
          assignedAt: new Date(Date.now() - 1 * 24 * 60 * 60 * 1000).toISOString(),
          deadline: new Date(Date.now() + 5 * 24 * 60 * 60 * 1000).toISOString(),
          status: 'pending'
        }
      ]
    },
    {
      id: 'req-002',
      requestNumber: 'SOL-2024-002',
      description: 'Mantenimiento preventivo de ascensores',
      asset: 'ASC-001 - Ascensor Principal',
      location: 'Edificio B',
      serviceType: 'preventivo',
      observations: 'Mantenimiento trimestral programado',
      images: [],
      documents: [],
      quotationDeadline: new Date(Date.now() + 10 * 24 * 60 * 60 * 1000).toISOString(),
      selectedProviders: ['provider-1'],
      status: 'sent',
      clientId: 'test-client-001',
      createdAt: new Date(Date.now() - 1 * 24 * 60 * 60 * 1000).toISOString(),
      startTime: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString(),
      priority: 'baja'
    },
    {
      id: 'req-003',
      requestNumber: 'SOL-2024-003',
      description: 'Fuga de agua en tubería principal',
      asset: 'TUB-001',
      location: 'Sótano - Edificio A',
      serviceType: 'emergencia',
      observations: 'Requiere atención inmediata',
      images: [],
      documents: [],
      quotationDeadline: new Date(Date.now() + 2 * 24 * 60 * 60 * 1000).toISOString(),
      selectedProviders: ['provider-1'],
      status: 'sent',
      clientId: 'test-client-002',
      createdAt: new Date(Date.now() - 3 * 60 * 60 * 1000).toISOString(),
      priority: 'alta'
    }
  ];

  localStorage.setItem('requests', JSON.stringify(testRequests));
};

const initializeTeamMemberTestData = () => {
  const testRequests = [
    {
      id: 'req-001',
      requestNumber: 'SOL-2024-001',
      description: 'Reparación de sistema de aire acondicionado',
      asset: 'AC-001 - Aire Acondicionado Principal',
      location: 'Edificio A - Piso 3',
      serviceType: 'correctivo',
      observations: 'El equipo presenta fugas y no enfría adecuadamente',
      images: [],
      documents: [],
      quotationDeadline: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString(),
      selectedProviders: ['provider-1', 'provider-2'],
      status: 'sent',
      clientId: 'test-client-001',
      createdAt: new Date(Date.now() - 2 * 24 * 60 * 60 * 1000).toISOString(),
      startTime: new Date(Date.now() + 5 * 24 * 60 * 60 * 1000).toISOString(),
      priority: 'media',
      assignments: [
        {
          id: 'assign-001',
          requestId: 'req-001',
          teamMemberId: 'team-member-1',
          teamMemberName: 'Juan Pérez',
          assignedBy: 'provider-1',
          assignedAt: new Date(Date.now() - 1 * 24 * 60 * 60 * 1000).toISOString(),
          deadline: new Date(Date.now() + 5 * 24 * 60 * 60 * 1000).toISOString(),
          status: 'pending'
        }
      ]
    }
  ];

  localStorage.setItem('requests', JSON.stringify(testRequests));
};

export const useAuth = () => {
  const context = useContext(AuthContext);
  if (!context) {
    throw new Error('useAuth must be used within AuthProvider');
  }
  return context;
};
