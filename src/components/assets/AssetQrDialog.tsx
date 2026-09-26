import { useMemo, useRef } from 'react';
import { AlertTriangle, Copy, Download, Printer } from 'lucide-react';
import { QRCodeCanvas, QRCodeSVG } from 'qrcode.react';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { useToast } from '@/hooks/use-toast';
import { isPublicAppUrlLocal, publicAppUrl } from '@/lib/env';
import { buildAssetLabelHtml, buildAssetQrFilename, buildAssetQrUrl } from '@/lib/assetQr';

interface AssetQrDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  asset: { id: string; name: string; code: string | null };
  organizationId: string;
  /** Same gate AssetDetail already uses to allow editing: owner/admin/manager.
   * Everyone else can still view the QR and copy the link — the link isn't
   * sensitive, opening it still goes through session + tenant + RLS. Only
   * downloading/printing a physical label is restricted here. */
  canManageAssets: boolean;
}

const QR_DISPLAY_SIZE = 256;
const QR_DOWNLOAD_PNG_SIZE = 1024;

const downloadBlob = (blob: Blob, filename: string): void => {
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = filename;
  document.body.appendChild(link);
  link.click();
  document.body.removeChild(link);
  URL.revokeObjectURL(url);
};

/** Clones the live <svg> (so the visible one is never mutated), guarantees
 * the xmlns namespace the QR library sets by default, strips the Tailwind
 * `class` attribute used only for the on-screen responsive sizing (it has no
 * effect — and no meaning — once the file leaves this app's stylesheet), and
 * serializes it to a standalone XML string usable for both the .svg download
 * and the print label's embedded markup. */
const serializeSvg = (svg: SVGSVGElement): string => {
  const clone = svg.cloneNode(true) as SVGSVGElement;
  if (!clone.getAttribute('xmlns')) clone.setAttribute('xmlns', 'http://www.w3.org/2000/svg');
  clone.removeAttribute('class');
  return new XMLSerializer().serializeToString(clone);
};

/**
 * The asset's QR code: a small SVG for display/download plus a hidden,
 * higher-resolution canvas used only to export the PNG. Both encode the
 * SAME payload — `buildAssetQrUrl`, built from organizationId + assets.id
 * only (never name/code/branch/hierarchy/status/responsible, and never
 * assets.qr_code, which stays reserved and unused). Opening that URL still
 * requires a session and passes through the normal tenant + RLS checks:
 * the QR itself grants nothing. See docs/ASSET_QR.md.
 */
export function AssetQrDialog({ open, onOpenChange, asset, organizationId, canManageAssets }: AssetQrDialogProps) {
  const { toast } = useToast();
  const svgRef = useRef<SVGSVGElement>(null);
  const pngCanvasRef = useRef<HTMLCanvasElement>(null);

  const url = useMemo(() => buildAssetQrUrl(publicAppUrl, organizationId, asset.id), [organizationId, asset.id]);

  const handleCopyLink = async () => {
    try {
      await navigator.clipboard.writeText(url);
      toast({ title: 'Enlace copiado' });
    } catch {
      toast({ title: 'No se pudo copiar el enlace', description: 'Selecciónalo y cópialo manualmente.', variant: 'destructive' });
    }
  };

  const handleDownloadSvg = () => {
    const svg = svgRef.current;
    if (!svg) return;
    const markup = serializeSvg(svg);
    const blob = new Blob([`<?xml version="1.0" encoding="UTF-8"?>\n${markup}`], { type: 'image/svg+xml' });
    downloadBlob(blob, buildAssetQrFilename(asset, 'svg'));
  };

  const handleDownloadPng = () => {
    const canvas = pngCanvasRef.current;
    if (!canvas) return;
    canvas.toBlob((blob) => {
      if (!blob) {
        toast({ title: 'No se pudo generar el PNG', variant: 'destructive' });
        return;
      }
      downloadBlob(blob, buildAssetQrFilename(asset, 'png'));
    }, 'image/png');
  };

  const handlePrint = () => {
    const svg = svgRef.current;
    if (!svg) return;
    const qrMarkup = serializeSvg(svg);
    const logoUrl = new URL('/brand/logo-primary.png', window.location.origin).href;
    const html = buildAssetLabelHtml({ qrMarkup, name: asset.name, code: asset.code, logoUrl });

    // A hidden iframe (not a new window) prints without triggering a
    // popup blocker and never writes anything back to the app's own data.
    const iframe = document.createElement('iframe');
    iframe.style.position = 'fixed';
    iframe.style.right = '0';
    iframe.style.bottom = '0';
    iframe.style.width = '0';
    iframe.style.height = '0';
    iframe.style.border = '0';
    document.body.appendChild(iframe);

    const cleanup = () => {
      if (iframe.parentNode) document.body.removeChild(iframe);
    };
    iframe.onload = () => {
      try {
        iframe.contentWindow?.focus();
        iframe.contentWindow?.print();
      } finally {
        // Give the browser's print dialog time to read the iframe before it
        // is removed from the document.
        setTimeout(cleanup, 1000);
      }
    };
    iframe.srcdoc = html;
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="w-[calc(100vw-2rem)] max-w-lg">
        <DialogHeader>
          <DialogTitle>Código QR — {asset.name}</DialogTitle>
          <DialogDescription>
            Escanéalo para abrir directamente la ficha de este activo.
          </DialogDescription>
        </DialogHeader>

        {/* min-w-0: DialogContent is a CSS grid, and a grid/flex item's
         * default min-width is `auto` (its content's intrinsic width), not
         * 0 — without this, a long child (the link row below) would expand
         * this column past the dialog's own explicit width instead of
         * wrapping/truncating inside it. */}
        <div className="flex w-full min-w-0 flex-col items-center gap-3">
          <div className="mx-auto w-full max-w-[288px] rounded-lg border bg-white p-4">
            {/* w-full + h-auto make the SVG shrink with its container on
             * narrow viewports; the container's own max-width keeps the
             * displayed QR capped at ~256px (288px box minus the p-4
             * padding) on anything wide enough to show it at full size. */}
            <QRCodeSVG ref={svgRef} value={url} size={QR_DISPLAY_SIZE} level="M" marginSize={4} className="h-auto w-full" />
          </div>
          {/* Off-screen, higher-resolution render used only for the PNG
           * download — never shown to the user, always exported at the same
           * 1024px regardless of how the visible QR above is displayed. */}
          <div aria-hidden="true" style={{ position: 'absolute', width: 0, height: 0, overflow: 'hidden' }}>
            <QRCodeCanvas ref={pngCanvasRef} value={url} size={QR_DOWNLOAD_PNG_SIZE} level="M" marginSize={4} />
          </div>

          <div className="w-full space-y-1 text-center">
            <p className="text-sm font-medium">{asset.name}</p>
            {asset.code && <p className="text-xs text-muted-foreground">{asset.code}</p>}
          </div>

          <div className="flex w-full min-w-0 items-center gap-2">
            <code
              className="min-w-0 flex-1 overflow-hidden text-ellipsis whitespace-nowrap rounded-md border bg-muted/40 px-2 py-1.5 text-xs"
              title={url}
            >
              {url}
            </code>
            <Button size="icon" variant="outline" className="shrink-0" onClick={() => void handleCopyLink()} title="Copiar enlace">
              <Copy className="h-4 w-4" />
            </Button>
          </div>

          {isPublicAppUrlLocal && (
            <div className="flex w-full min-w-0 items-start gap-2 rounded-md border border-amber-500/40 bg-amber-500/10 p-3 text-xs">
              <AlertTriangle className="mt-0.5 h-3.5 w-3.5 shrink-0 text-amber-600" />
              <span className="min-w-0 break-words">
                QR de desarrollo. Este enlace apunta a <strong className="break-all">{publicAppUrl}</strong>. Configura{' '}
                <code>VITE_PUBLIC_APP_URL</code> antes de imprimir etiquetas definitivas.
              </span>
            </div>
          )}

          <p className="text-center text-xs text-muted-foreground">
            El QR solo abre la ficha para usuarios con sesión y acceso a esta organización.
          </p>
        </div>

        <DialogFooter className="flex-col gap-2 space-x-0 sm:flex-row sm:justify-between sm:space-x-0">
          <Button variant="outline" onClick={() => onOpenChange(false)}>Cerrar</Button>
          {canManageAssets && (
            <div className="flex flex-wrap gap-2">
              <Button variant="outline" onClick={handleDownloadPng}>
                <Download className="mr-2 h-4 w-4" /> PNG
              </Button>
              <Button variant="outline" onClick={handleDownloadSvg}>
                <Download className="mr-2 h-4 w-4" /> SVG
              </Button>
              <Button onClick={handlePrint}>
                <Printer className="mr-2 h-4 w-4" /> Imprimir etiqueta
              </Button>
            </div>
          )}
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
