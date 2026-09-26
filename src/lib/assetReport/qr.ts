import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { QRCodeSVG } from 'qrcode.react';

/**
 * Renders the SAME QR the AssetQrDialog shows (qrcode.react's QRCodeSVG,
 * same payload from buildAssetQrUrl) to a static SVG string, then extracts
 * its `viewBox` and `<path>` elements so they can be redrawn with
 * @react-pdf/renderer's own <Svg>/<Path> — that engine cannot embed an
 * arbitrary <svg> element, only its own primitives, and this keeps the QR
 * vectorial (crisp at any size, no rasterization, no canvas).
 *
 * This intentionally does NOT use a generic SVG parser: qrcode.react@4.2.0's
 * QRCodeSVG always renders exactly two <path> children (background then
 * foreground) inside an <svg viewBox="0 0 N N">, which renderToStaticMarkup
 * serializes as `<path fill="..." d="..." shape-rendering="crispEdges">
 * </path>` (verified against node_modules/qrcode.react/lib/index.js — see
 * docs/ASSET_REPORT.md → "QR"). The regexes below only need to tolerate
 * THAT shape, and are covered by a real render+decode test outside the repo
 * (scratch script), per the approved diagnosis.
 */

export interface VectorQr {
  viewBox: string;
  paths: Array<{ d: string; fill: string }>;
}

// react-dom/server's renderToStaticMarkup does NOT self-close SVG <path>
// elements (it emits "<path ...></path>", not "<path .../>", since `path`
// is not an HTML void element) — this matches the opening tag only, so it
// tolerates either form.
const PATH_TAG_RE = /<path\s+([^>]*)>/g;
const ATTR_RE = /([a-zA-Z-]+)="([^"]*)"/g;

const parseAttrs = (raw: string): Record<string, string> => {
  const attrs: Record<string, string> = {};
  ATTR_RE.lastIndex = 0;
  let match: RegExpExecArray | null;
  while ((match = ATTR_RE.exec(raw))) attrs[match[1]] = match[2];
  return attrs;
};

/** Pure: takes the already-serialized markup and extracts viewBox + paths.
 * Kept separate from `buildVectorQr` so it is directly unit-testable against
 * a captured markup fixture without needing react-dom/server. */
export const parseQrSvgMarkup = (markup: string): VectorQr => {
  const viewBoxMatch = markup.match(/viewBox="([^"]*)"/);
  if (!viewBoxMatch) throw new Error('No se pudo generar el QR: viewBox no encontrado en el SVG.');

  const paths: Array<{ d: string; fill: string }> = [];
  let pathMatch: RegExpExecArray | null;
  PATH_TAG_RE.lastIndex = 0;
  while ((pathMatch = PATH_TAG_RE.exec(markup))) {
    const attrs = parseAttrs(pathMatch[1]);
    if (attrs.d && attrs.fill) paths.push({ d: attrs.d, fill: attrs.fill });
  }
  if (paths.length < 2) throw new Error('No se pudo generar el QR: no se hallaron los trazos esperados.');
  return { viewBox: viewBoxMatch[1], paths };
};

/** Renders the QR for `value` (the canonical asset URL from buildAssetQrUrl)
 * and returns its vector data. Never performs any network request — the QR
 * is generated entirely client-side, same as AssetQrDialog. */
export const buildVectorQr = (value: string): VectorQr => {
  const markup = renderToStaticMarkup(createElement(QRCodeSVG, { value, size: 256, level: 'M', marginSize: 4 }));
  return parseQrSvgMarkup(markup);
};
