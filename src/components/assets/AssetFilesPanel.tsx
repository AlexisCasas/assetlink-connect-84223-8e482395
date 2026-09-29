import { useRef, useState } from 'react';
import { format } from 'date-fns';
import { es } from 'date-fns/locale';
import { Download, FileText, ImageIcon, Loader2, Star, Trash2, Upload } from 'lucide-react';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from '@/components/ui/alert-dialog';
import { useToast } from '@/hooks/use-toast';
import { useAssetFileUrl, type UseAssetFilesResult } from '@/hooks/useAssetFiles';
import { ASSET_FILE_ACCEPT, UPLOAD_STAGE_LABELS, createAssetDownload, validateAssetFileForUpload } from '@/lib/assetFiles';
import type { AssetFile, AssetFileKind } from '@/types/assetFile';

const STATUS_LABELS: Record<AssetFile['status'], string> = {
  pending: 'Pendiente de confirmar',
  available: 'Disponible',
  deleting: 'Eliminando',
  failed: 'Fallido',
};

const formatFileSize =(bytes: number | null) => {
  if (bytes == null) return '—';
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
};

const formatDate = (value: string | null) => (value ? format(new Date(value), 'dd/MM/yyyy HH:mm', { locale: es }) : '—');

/** An available photo rendered from a short-lived signed URL. If the image
 * fails (e.g. the URL expired while the page was open) it re-signs ONCE —
 * never in a loop. */
export function AssetPhotoImage({ fileId, alt, className }: { fileId: string; alt: string; className?: string }) {
  const { url, loading, refresh } = useAssetFileUrl(fileId);
  const [retried, setRetried] = useState(false);
  const [resigning, setResigning] = useState(false);
  const [broken, setBroken] = useState(false);
  if (loading || resigning || !url || broken) {
    return (
      <div className={`flex items-center justify-center bg-muted ${className ?? ''}`}>
        {loading || resigning ? <Loader2 className="h-5 w-5 animate-spin text-muted-foreground" /> : <ImageIcon className="h-6 w-6 text-muted-foreground" />}
      </div>
    );
  }
  return (
    <img
      src={url}
      alt={alt}
      className={className}
      onError={() => {
        if (retried) { setBroken(true); return; }
        setRetried(true);
        // Unmount the <img> while re-signing: the new element always issues
        // a fresh request, even if the new URL is byte-identical (SigV4
        // X-Amz-Date has one-second resolution).
        setResigning(true);
        void refresh().finally(() => setResigning(false));
      }}
    />
  );
}

interface AssetFilesPanelProps {
  assetName: string;
  files: UseAssetFilesResult;
  /** scope.canManageFiles AND the asset is not archived. */
  canManage: boolean;
  archived: boolean;
}

/** "Fotos y documentos" tab of the asset sheet (Fase 1 · Punto 10). */
export function AssetFilesPanel({ assetName, files, canManage, archived }: AssetFilesPanelProps) {
  const { toast } = useToast();
  const photoInput = useRef<HTMLInputElement>(null);
  const documentInput = useRef<HTMLInputElement>(null);
  const [toDelete, setToDelete] = useState<AssetFile | null>(null);
  const [downloadingId, setDownloadingId] = useState<string | null>(null);

  const startUpload = async (kind: AssetFileKind, file: File | undefined) => {
    if (!file) return;
    const invalid = validateAssetFileForUpload(kind, file);
    if (invalid) {
      toast({ title: 'Archivo no válido', description: invalid, variant: 'destructive' });
      return;
    }
    try {
      await files.uploadFile({ kind, file });
      toast({ title: kind === 'photo' ? 'Foto subida' : 'Documento subido', description: file.name });
    } catch (error) {
      toast({ title: 'No se pudo subir el archivo', description: error instanceof Error ? error.message : undefined, variant: 'destructive' });
    }
  };

  // A fresh signed URL on every click, used immediately and never kept in
  // state. Documents are served as attachment, so navigating to the URL
  // just downloads (the page stays). Photos open in a new tab, pre-opened
  // synchronously in the click so popup blockers allow it.
  const download = async (file: AssetFile) => {
    const tab = file.kind === 'photo' ? window.open('about:blank', '_blank') : null;
    setDownloadingId(file.id);
    try {
      const { downloadUrl } = await createAssetDownload(file.id);
      if (tab) {
        tab.opener = null;
        tab.location.href = downloadUrl;
      } else {
        window.location.assign(downloadUrl);
      }
    } catch (error) {
      tab?.close();
      toast({ title: 'No se pudo descargar', description: error instanceof Error ? error.message : undefined, variant: 'destructive' });
    } finally {
      setDownloadingId(null);
    }
  };

  const confirmDelete = async () => {
    const file = toDelete;
    setToDelete(null);
    if (!file) return;
    try {
      await files.deleteFile(file.id);
      toast({ title: 'Archivo eliminado', description: file.name });
    } catch (error) {
      toast({ title: 'No se pudo eliminar', description: error instanceof Error ? error.message : undefined, variant: 'destructive' });
    }
  };

  const setPrimary = async (file: AssetFile) => {
    try {
      await files.setPrimary(file.id);
      toast({ title: 'Foto principal actualizada', description: file.name });
    } catch (error) {
      toast({ title: 'No se pudo marcar como principal', description: error instanceof Error ? error.message : undefined, variant: 'destructive' });
    }
  };

  const busy = files.uploading;
  const uploadingKind = files.upload?.kind ?? null;

  return (
    <div className="space-y-6" data-testid="asset-files-panel">
      {archived && (
        <p className="rounded-md border border-dashed bg-muted/40 p-3 text-sm text-muted-foreground">
          Activo archivado: los archivos se pueden ver y descargar, pero no subir, eliminar ni cambiar la foto principal.
        </p>
      )}
      {files.error && <p className="text-sm text-destructive">{files.error}</p>}

      {/* FOTOGRAFÍAS */}
      <section className="space-y-3" data-testid="asset-files-photos">
        <div className="flex items-center justify-between gap-2">
          <h3 className="font-semibold">Fotografías</h3>
          {canManage && (
            <>
              <input
                ref={photoInput}
                type="file"
                accept={ASSET_FILE_ACCEPT.photo}
                className="hidden"
                aria-label="Subir foto"
                data-testid="asset-photo-input"
                onChange={(event) => { const file = event.target.files?.[0]; event.target.value = ''; void startUpload('photo', file); }}
              />
              <Button size="sm" variant="outline" disabled={busy} onClick={() => photoInput.current?.click()}>
                <Upload className="mr-1 h-4 w-4" />Subir foto
              </Button>
            </>
          )}
        </div>
        {uploadingKind === 'photo' && files.upload && (
          <p className="text-sm text-muted-foreground" data-testid="asset-upload-stage">{UPLOAD_STAGE_LABELS[files.upload.stage]} {files.upload.fileName}</p>
        )}
        {files.loading ? (
          <p className="text-sm text-muted-foreground">Cargando…</p>
        ) : files.photos.length === 0 ? (
          <p className="text-sm text-muted-foreground">Sin fotografías.</p>
        ) : (
          <div className="grid grid-cols-2 gap-3 md:grid-cols-3">
            {files.photos.map((photo) => (
              <div key={photo.id} className="overflow-hidden rounded-lg border" data-testid="asset-photo-card">
                <AssetPhotoImage fileId={photo.id} alt={photo.name} className="h-28 w-full object-cover" />
                <div className="space-y-1 p-2 text-xs">
                  <div className="flex items-center gap-1">
                    <span className="truncate font-medium" title={photo.name}>{photo.name}</span>
                    {photo.isPrimary && <Badge variant="secondary" className="shrink-0 text-[10px]">Principal</Badge>}
                  </div>
                  <p className="text-muted-foreground">{formatFileSize(photo.sizeBytes)} · {formatDate(photo.confirmedAt ?? photo.createdAt)}</p>
                  <div className="flex flex-wrap gap-1">
                    <Button size="sm" variant="ghost" className="h-7 px-2" title="Abrir" disabled={downloadingId === photo.id} onClick={() => void download(photo)}>
                      <Download className="h-3.5 w-3.5" />
                    </Button>
                    {canManage && !photo.isPrimary && (
                      <Button size="sm" variant="ghost" className="h-7 px-2" title="Marcar como principal" disabled={files.settingPrimaryId === photo.id} onClick={() => void setPrimary(photo)}>
                        <Star className="h-3.5 w-3.5" />
                      </Button>
                    )}
                    {canManage && (
                      <Button size="sm" variant="ghost" className="h-7 px-2 text-destructive hover:text-destructive" title="Eliminar" disabled={files.deletingId === photo.id} onClick={() => setToDelete(photo)}>
                        <Trash2 className="h-3.5 w-3.5" />
                      </Button>
                    )}
                  </div>
                </div>
              </div>
            ))}
          </div>
        )}
        {canManage && <p className="text-xs text-muted-foreground">JPG, PNG o WEBP · máximo 10 MB.</p>}
      </section>

      {/* DOCUMENTOS */}
      <section className="space-y-3" data-testid="asset-files-documents">
        <div className="flex items-center justify-between gap-2">
          <h3 className="font-semibold">Documentos</h3>
          {canManage && (
            <>
              <input
                ref={documentInput}
                type="file"
                accept={ASSET_FILE_ACCEPT.document}
                className="hidden"
                aria-label="Agregar documento"
                data-testid="asset-document-input"
                onChange={(event) => { const file = event.target.files?.[0]; event.target.value = ''; void startUpload('document', file); }}
              />
              <Button size="sm" variant="outline" disabled={busy} onClick={() => documentInput.current?.click()}>
                <Upload className="mr-1 h-4 w-4" />Agregar documento
              </Button>
            </>
          )}
        </div>
        {uploadingKind === 'document' && files.upload && (
          <p className="text-sm text-muted-foreground" data-testid="asset-upload-stage">{UPLOAD_STAGE_LABELS[files.upload.stage]} {files.upload.fileName}</p>
        )}
        {files.loading ? (
          <p className="text-sm text-muted-foreground">Cargando…</p>
        ) : files.documents.length === 0 ? (
          <p className="text-sm text-muted-foreground">Sin documentos.</p>
        ) : (
          <ul className="divide-y rounded-lg border">
            {files.documents.map((doc) => (
              <li key={doc.id} className="flex items-center gap-3 p-3 text-sm" data-testid="asset-document-row">
                <FileText className="h-4 w-4 shrink-0 text-muted-foreground" />
                <div className="min-w-0 flex-1">
                  <p className="truncate font-medium" title={doc.name}>{doc.name}</p>
                  <p className="text-xs text-muted-foreground">{formatFileSize(doc.sizeBytes)} · {formatDate(doc.confirmedAt ?? doc.createdAt)}</p>
                </div>
                <Button size="sm" variant="outline" disabled={downloadingId === doc.id} onClick={() => void download(doc)}>
                  <Download className="mr-1 h-3.5 w-3.5" />Descargar
                </Button>
                {canManage && (
                  <Button size="sm" variant="ghost" className="text-destructive hover:text-destructive" title="Eliminar" disabled={files.deletingId === doc.id} onClick={() => setToDelete(doc)}>
                    <Trash2 className="h-4 w-4" />
                  </Button>
                )}
              </li>
            ))}
          </ul>
        )}
        {canManage && <p className="text-xs text-muted-foreground">PDF · máximo 25 MB.</p>}
      </section>

      {/* Estados operativos (solo quien gestiona los recibe del backend) */}
      {canManage && files.operational.length > 0 && (
        <section className="space-y-2" data-testid="asset-files-operational">
          <h3 className="text-sm font-semibold text-muted-foreground">En proceso o con errores</h3>
          <ul className="divide-y rounded-lg border">
            {files.operational.map((file) => (
              <li key={file.id} className="flex items-center gap-3 p-2 text-xs">
                <span className="min-w-0 flex-1 truncate">{file.name}</span>
                <Badge variant={file.status === 'failed' ? 'destructive' : 'outline'}>{STATUS_LABELS[file.status]}</Badge>
                <Button size="sm" variant="ghost" className="h-7 px-2 text-destructive hover:text-destructive" title="Eliminar" disabled={files.deletingId === file.id} onClick={() => setToDelete(file)}>
                  <Trash2 className="h-3.5 w-3.5" />
                </Button>
              </li>
            ))}
          </ul>
        </section>
      )}

      <AlertDialog open={!!toDelete} onOpenChange={(open) => { if (!open) setToDelete(null); }}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>¿Eliminar archivo?</AlertDialogTitle>
            <AlertDialogDescription>
              Se eliminará "{toDelete?.name}" de {assetName}. {toDelete?.isPrimary ? 'Era la foto principal: pasará a serlo la foto más antigua que quede.' : ''}
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancelar</AlertDialogCancel>
            <AlertDialogAction onClick={() => void confirmDelete()} className="bg-destructive text-destructive-foreground hover:bg-destructive/90">Eliminar</AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}
