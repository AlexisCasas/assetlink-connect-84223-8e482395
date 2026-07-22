import { Card, CardContent } from '@/components/ui/card';
import { MessageSquare } from 'lucide-react';

// The legacy chat tables are intentionally not queried until the tenant-aware
// chat feature is implemented. This also keeps direct #contact navigation safe.
export const ContactList = () => (
  <div className="container mx-auto p-6">
    <div className="mb-6 flex items-center gap-3">
      <MessageSquare className="h-8 w-8 text-primary" />
      <h1 className="text-3xl font-bold">Contacto</h1>
    </div>
    <Card>
      <CardContent className="flex flex-col items-center justify-center py-12 text-center">
        <MessageSquare className="mb-4 h-12 w-12 text-muted-foreground" />
        <p className="font-medium">Chat pendiente de migracion tenant-aware</p>
        <p className="mt-1 text-sm text-muted-foreground">
          Las conversaciones y participantes volveran en una funcionalidad posterior.
        </p>
      </CardContent>
    </Card>
  </div>
);
