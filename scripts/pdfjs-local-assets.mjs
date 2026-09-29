import { readFileSync, readdirSync } from 'node:fs';
import { createRequire } from 'node:module';
import path from 'node:path';

/** PDF.js resources are served by this app; no document or font goes to a CDN. */
export function pdfjsLocalAssets() {
  const require = createRequire(import.meta.url);
  const root = path.dirname(require.resolve('pdfjs-dist/package.json'));
  const { version } = JSON.parse(readFileSync(path.join(root, 'package.json'), 'utf8'));
  const prefix = `pdfjs-assets/${version}/`;
  const files = new Map();
  for (const directory of ['cmaps', 'standard_fonts', 'wasm']) {
    for (const name of readdirSync(path.join(root, directory))) {
      // No scripting engine, wasm runtime, complete viewer or source maps.
      if (directory === 'wasm' && !['openjpeg_nowasm_fallback.js', 'jbig2_nowasm_fallback.js', 'LICENSE_OPENJPEG', 'LICENSE_JBIG2', 'LICENSE_PDFJS_OPENJPEG', 'LICENSE_PDFJS_JBIG2'].includes(name)) continue;
      files.set(`${prefix}${directory}/${name}`, path.join(root, directory, name));
    }
  }
  let base = '/';
  return {
    name: 'pdfjs-local-assets',
    configResolved(config) { base = config.base; },
    configureServer(server) {
      server.middlewares.use((request, response, next) => {
        const pathname = new URL(request.url || '/', 'http://localhost').pathname;
        const start = `${base}${prefix}`;
        if (!pathname.startsWith(start)) return next();
        const file = files.get(pathname.slice(base.length));
        if (!file || !['GET', 'HEAD'].includes(request.method || '')) { response.statusCode = 404; response.end(); return; }
        response.setHeader('Content-Type', file.endsWith('.js') ? 'text/javascript' : file.endsWith('.ttf') ? 'font/ttf' : 'application/octet-stream');
        response.setHeader('Cache-Control', 'public, max-age=31536000, immutable');
        response.end(request.method === 'HEAD' ? undefined : readFileSync(file));
      });
    },
    generateBundle() {
      for (const [fileName, file] of files) this.emitFile({ type: 'asset', fileName, source: readFileSync(file) });
    },
  };
}
