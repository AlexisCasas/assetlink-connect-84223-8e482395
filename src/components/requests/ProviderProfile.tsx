import { useState } from 'react';
import { Card } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Badge } from '@/components/ui/badge';
import { useToast } from '@/hooks/use-toast';
import { useAuth } from '@/contexts/AuthContext';
import { MOCK_PROVIDERS } from '@/types/request';
import { Upload, CheckCircle, X } from 'lucide-react';

export const ProviderProfile = () => {
  const { user } = useAuth();
  const { toast } = useToast();
  const provider = MOCK_PROVIDERS.find(p => p.email === user?.email);
  
  const [certificationDocuments, setCertificationDocuments] = useState<File[]>([]);
  const [isCertified, setIsCertified] = useState(provider?.certified || false);

  const handleFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    if (e.target.files) {
      const newFiles = Array.from(e.target.files);
      if (certificationDocuments.length + newFiles.length > 5) {
        toast({
          title: "Límite excedido",
          description: "Solo puedes subir un máximo de 5 documentos",
          variant: "destructive",
        });
        return;
      }
      setCertificationDocuments([...certificationDocuments, ...newFiles]);
    }
  };

  const removeDocument = (index: number) => {
    setCertificationDocuments(certificationDocuments.filter((_, i) => i !== index));
  };

  const handleSubmitCertification = () => {
    if (certificationDocuments.length !== 5) {
      toast({
        title: "Documentos incompletos",
        description: "Debes subir exactamente 5 documentos para la certificación",
        variant: "destructive",
      });
      return;
    }

    // Guardar en localStorage
    const providers = JSON.parse(localStorage.getItem('providers') || JSON.stringify(MOCK_PROVIDERS));
    const providerIndex = providers.findIndex((p: any) => p.email === user?.email);
    if (providerIndex !== -1) {
      providers[providerIndex].certified = true;
      providers[providerIndex].certificationDocuments = certificationDocuments.map(f => f.name);
      localStorage.setItem('providers', JSON.stringify(providers));
      setIsCertified(true);
      
      toast({
        title: "Certificación enviada",
        description: "Tu solicitud de certificación ha sido enviada exitosamente",
      });
    }
  };

  return (
    <div className="p-6 space-y-6">
      <div>
        <h1 className="text-3xl font-bold">Mi Perfil</h1>
        <p className="text-muted-foreground">Configuración de proveedor</p>
      </div>

      <Card className="p-6">
        <div className="space-y-4">
          <div>
            <h2 className="text-xl font-semibold mb-2">Información del Proveedor</h2>
            <div className="space-y-2">
              <p><strong>Nombre:</strong> {provider?.name}</p>
              <p><strong>Email:</strong> {provider?.email}</p>
              <p><strong>Calificación:</strong> {provider?.rating} ⭐</p>
              <p><strong>Especialidades:</strong> {provider?.specialties.join(', ')}</p>
            </div>
          </div>
        </div>
      </Card>

      <Card className="p-6">
        <div className="space-y-4">
          <div className="flex items-center justify-between">
            <h2 className="text-xl font-semibold">Certificación de Proveedor</h2>
            {isCertified && (
              <Badge variant="default" className="flex items-center gap-1">
                <CheckCircle className="h-4 w-4" />
                Certificado
              </Badge>
            )}
          </div>

          <p className="text-sm text-muted-foreground">
            Obtén la certificación subiendo 5 documentos que acrediten tu empresa. 
            Los proveedores certificados son más visibles para los clientes.
          </p>

          {!isCertified && (
            <>
              <div className="space-y-2">
                <Label htmlFor="certification-docs">
                  Documentos de Certificación ({certificationDocuments.length}/5)
                </Label>
                <Input
                  id="certification-docs"
                  type="file"
                  multiple
                  accept=".pdf,.doc,.docx,.jpg,.jpeg,.png"
                  onChange={handleFileChange}
                  disabled={certificationDocuments.length >= 5}
                />
              </div>

              {certificationDocuments.length > 0 && (
                <div className="space-y-2">
                  <Label>Documentos subidos:</Label>
                  <div className="space-y-1">
                    {certificationDocuments.map((file, index) => (
                      <div key={index} className="flex items-center justify-between p-2 bg-muted rounded">
                        <span className="text-sm">{file.name}</span>
                        <Button
                          variant="ghost"
                          size="sm"
                          onClick={() => removeDocument(index)}
                        >
                          <X className="h-4 w-4" />
                        </Button>
                      </div>
                    ))}
                  </div>
                </div>
              )}

              <Button
                onClick={handleSubmitCertification}
                disabled={certificationDocuments.length !== 5}
                className="w-full"
              >
                <Upload className="h-4 w-4 mr-2" />
                Enviar Solicitud de Certificación
              </Button>
            </>
          )}

          {isCertified && (
            <div className="text-center p-4 bg-muted rounded-lg">
              <CheckCircle className="h-12 w-12 mx-auto mb-2 text-green-600" />
              <p className="font-semibold">¡Eres un proveedor certificado!</p>
              <p className="text-sm text-muted-foreground">
                Los clientes pueden ver tu badge de certificación
              </p>
            </div>
          )}
        </div>
      </Card>
    </div>
  );
};
