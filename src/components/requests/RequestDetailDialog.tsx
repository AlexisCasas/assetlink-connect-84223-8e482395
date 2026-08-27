import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Badge } from '@/components/ui/badge';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Calendar, MapPin, Building2, Wrench, FileText, User, Image, File, List } from 'lucide-react';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { ScrollArea, ScrollBar } from '@/components/ui/scroll-area';
import { RequestAssetSummary } from './RequestAssetSummary';

interface RequestDetailDialogProps {
  request: any;
  assignment?: { team_member_name: string };
  onClose: () => void;
}

export const RequestDetailDialog = ({ request, assignment, onClose }: RequestDetailDialogProps) => {
  const getServiceTypeColor = (type: string) => {
    const colors = {
      emergencia: 'bg-red-500',
      correctivo: 'bg-orange-500',
      preventivo: 'bg-blue-500',
      proyecto: 'bg-purple-500',
    };
    return colors[type as keyof typeof colors] || 'bg-gray-500';
  };

  const getServiceTypeText = (type: string) => {
    const texts = {
      emergencia: 'Emergencia',
      correctivo: 'Correctivo',
      preventivo: 'Preventivo',
      proyecto: 'Proyecto',
    };
    return texts[type as keyof typeof texts] || type;
  };

  return (
    <Dialog open={true} onOpenChange={onClose}>
      <DialogContent className="max-w-3xl max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle className="text-2xl">
            Detalles de Solicitud {request.request_number}
          </DialogTitle>
        </DialogHeader>

        <div className="space-y-4">
          {/* Información General */}
          <Card>
            <CardHeader>
              <CardTitle className="text-lg flex items-center gap-2">
                <Building2 className="h-5 w-5" />
                Información General
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-3">
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <p className="text-sm text-muted-foreground">Cliente</p>
                  <p className="font-medium">{request.client_name || 'No especificado'}</p>
                </div>
                <div>
                  <p className="text-sm text-muted-foreground">Sucursal</p>
                  <p className="font-medium">{request.client_branch || 'No especificado'}</p>
                </div>
              </div>
              <div className="flex gap-4 items-center">
                <div>
                  <p className="text-sm text-muted-foreground mb-1">Tipo de Servicio</p>
                  <Badge className={getServiceTypeColor(request.service_type)}>
                    {getServiceTypeText(request.service_type)}
                  </Badge>
                </div>
                <div>
                  <p className="text-sm text-muted-foreground mb-1">Prioridad</p>
                  <Badge variant="outline">P{request.priority}</Badge>
                </div>
              </div>
            </CardContent>
          </Card>

          {/* Activo asociado */}
          <RequestAssetSummary assetId={request.asset_id} assetText={request.asset} />

          {/* Información Técnica General */}
          <Card>
            <CardHeader>
              <CardTitle className="text-lg flex items-center gap-2">
                <Wrench className="h-5 w-5" />
                Información Técnica
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-3">
              <div>
                <p className="text-sm text-muted-foreground">Ubicación</p>
                <p className="font-medium flex items-center gap-2">
                  <MapPin className="h-4 w-4" />
                  {request.location}
                </p>
              </div>
              <div>
                <p className="text-sm text-muted-foreground mb-1">Descripción</p>
                <p className="text-sm bg-muted p-3 rounded-md whitespace-pre-wrap">
                  {request.description}
                </p>
              </div>
              {request.observations && (
                <div>
                  <p className="text-sm text-muted-foreground mb-1">Observaciones</p>
                  <p className="text-sm bg-muted p-3 rounded-md whitespace-pre-wrap">
                    {request.observations}
                  </p>
                </div>
              )}
            </CardContent>
          </Card>

          {/* Detalle de la Solicitud en Tabla */}
          {request.details && request.details.length > 0 && (
            <Card>
              <CardHeader>
                <CardTitle className="text-lg flex items-center gap-2">
                  <List className="h-5 w-5" />
                  Detalle de la Solicitud ({request.details.length} {request.details.length === 1 ? 'fila' : 'filas'})
                </CardTitle>
              </CardHeader>
              <CardContent className="p-0">
                <ScrollArea className="w-full whitespace-nowrap">
                  <div className="min-w-max">
                    <Table>
                      <TableHeader>
                        <TableRow>
                          <TableHead className="min-w-[50px]">#</TableHead>
                          <TableHead className="min-w-[220px]">Actividad / Partida</TableHead>
                          <TableHead className="min-w-[180px]">Materiales</TableHead>
                          <TableHead className="min-w-[80px]">Cantidad</TableHead>
                          <TableHead className="min-w-[80px]">U.M</TableHead>
                          <TableHead className="min-w-[150px]">Observación</TableHead>
                          <TableHead className="min-w-[130px]">Encargado</TableHead>
                          <TableHead className="min-w-[100px]">Delegado</TableHead>
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {request.details.map((detail: any, index: number) => (
                          <TableRow key={index}>
                            <TableCell className="font-medium">{index + 1}</TableCell>
                            <TableCell>
                              {detail.activities || '-'}
                              {(detail.equipment || detail.area) && (
                                <p className="mt-0.5 text-xs text-muted-foreground">
                                  {[detail.equipment, detail.area].filter(Boolean).join(' · ')}
                                </p>
                              )}
                            </TableCell>
                            <TableCell>{detail.relevantMaterials || detail.relevant_materials || '-'}</TableCell>
                            <TableCell>{detail.quantity || '-'}</TableCell>
                            <TableCell>{detail.unitMeasure || detail.unit_measure || '-'}</TableCell>
                            <TableCell>{detail.observation || '-'}</TableCell>
                            <TableCell>{detail.responsibleUser || detail.responsible_user || '-'}</TableCell>
                            <TableCell>{detail.delegateType || detail.delegate_type || '-'}</TableCell>
                          </TableRow>
                        ))}
                      </TableBody>
                    </Table>
                  </div>
                  <ScrollBar orientation="horizontal" />
                </ScrollArea>
              </CardContent>
            </Card>
          )}

          {/* Fechas */}
          <Card>
            <CardHeader>
              <CardTitle className="text-lg flex items-center gap-2">
                <Calendar className="h-5 w-5" />
                Fechas
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-2">
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <p className="text-sm text-muted-foreground">Ingresado</p>
                  <p className="font-medium">
                    {new Date(request.created_at).toLocaleString('es-ES')}
                  </p>
                </div>
                <div>
                  <p className="text-sm text-muted-foreground">Fecha Límite</p>
                  <p className="font-medium">
                    {new Date(request.deadline).toLocaleDateString('es-ES')}
                  </p>
                </div>
              </div>
              {request.start_time && (
                <div>
                  <p className="text-sm text-muted-foreground">Programado Para</p>
                  <p className="font-medium">
                    {new Date(request.start_time).toLocaleString('es-ES')}
                  </p>
                </div>
              )}
            </CardContent>
          </Card>

          {/* Asignación */}
          {assignment && (
            <Card>
              <CardHeader>
                <CardTitle className="text-lg flex items-center gap-2">
                  <User className="h-5 w-5" />
                  Asignación
                </CardTitle>
              </CardHeader>
              <CardContent>
                <div>
                  <p className="text-sm text-muted-foreground">Coordinador</p>
                  <p className="font-medium">{assignment.team_member_name}</p>
                </div>
              </CardContent>
            </Card>
          )}

          {/* Archivos Adjuntos */}
          {(request.image_urls?.length > 0 || request.document_urls?.length > 0) && (
            <Card>
              <CardHeader>
                <CardTitle className="text-lg flex items-center gap-2">
                  <FileText className="h-5 w-5" />
                  Archivos Adjuntos
                </CardTitle>
              </CardHeader>
              <CardContent className="space-y-3">
                {request.image_urls?.length > 0 && (
                  <div>
                    <p className="text-sm text-muted-foreground mb-2 flex items-center gap-2">
                      <Image className="h-4 w-4" />
                      Imágenes ({request.image_urls.length})
                    </p>
                    <div className="flex flex-wrap gap-2">
                      {request.image_urls.map((url: string, idx: number) => (
                        <a
                          key={idx}
                          href={url}
                          target="_blank"
                          rel="noopener noreferrer"
                          className="text-blue-600 hover:underline text-sm"
                        >
                          imagen_{idx + 1}.jpg
                        </a>
                      ))}
                    </div>
                  </div>
                )}
                {request.document_urls?.length > 0 && (
                  <div>
                    <p className="text-sm text-muted-foreground mb-2 flex items-center gap-2">
                      <File className="h-4 w-4" />
                      Documentos ({request.document_urls.length})
                    </p>
                    <div className="flex flex-wrap gap-2">
                      {request.document_urls.map((url: string, idx: number) => (
                        <a
                          key={idx}
                          href={url}
                          target="_blank"
                          rel="noopener noreferrer"
                          className="text-blue-600 hover:underline text-sm"
                        >
                          documento_{idx + 1}.pdf
                        </a>
                      ))}
                    </div>
                  </div>
                )}
              </CardContent>
            </Card>
          )}
        </div>
      </DialogContent>
    </Dialog>
  );
};
