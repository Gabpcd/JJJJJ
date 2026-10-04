import { createServer } from 'node:http';
import { lstatSync, readFileSync, realpathSync } from 'node:fs';
import { join, resolve, extname } from 'node:path';
import { pathToFileURL } from 'node:url';

export const EXTERNAL_TAGS = Object.freeze([
  '<link rel="preconnect" href="https://fonts.googleapis.com" />',
  '<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />',
  '<link rel="preconnect" href="https://flripxtsyegjshnhzjkz.supabase.co" crossorigin />',
  '<link rel="dns-prefetch" href="https://flripxtsyegjshnhzjkz.supabase.co" />',
  '<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700;800&display=swap" />',
]);
const requireValue = ok => { if (!ok) throw new Error('RESTORE_PRIVATE_APP_REFUSED'); };
const activeExternalLink = /<link\b(?=[^>]*\brel=["'](?:preconnect|dns-prefetch|stylesheet)["'])(?=[^>]*\bhref=["'](?:https?:)?\/\/)[^>]*>/i;
export function sanitizePrivateHtml(html) {
  requireValue(typeof html === 'string' && Buffer.byteLength(html) <= 512 * 1024);
  for (const tag of EXTERNAL_TAGS) {
    requireValue(html.split(tag).length === 2);
    html = html.replace(tag, '');
  }
  requireValue(!activeExternalLink.test(html));
  return html;
}

const TYPES = Object.freeze({ '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8', '.json': 'application/json', '.webmanifest': 'application/manifest+json',
  '.svg': 'image/svg+xml', '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.webp': 'image/webp',
  '.ico': 'image/x-icon', '.woff': 'font/woff', '.woff2': 'font/woff2', '.ttf': 'font/ttf', '.wasm': 'application/wasm' });
function fileWithin(root, relative) {
  const parts = relative.split('/');
  let path = root;
  for (const [index, part] of parts.entries()) {
    requireValue(part !== '' && part !== '.' && part !== '..' && !part.startsWith('.'));
    path = join(path, part);
    const stat = lstatSync(path);
    requireValue(!stat.isSymbolicLink() && (index === parts.length - 1 ? stat.isFile() && stat.nlink === 1 : stat.isDirectory()));
  }
  requireValue(realpathSync(path) === path);
  return path;
}
// Filesystem-only helper for refusal tests: never opens a listening socket.
export function readPrivateAsset(directory, target, method = 'GET') {
  try {
    if (!['GET', 'HEAD'].includes(method)) return { status: 405, body: Buffer.alloc(0) };
    requireValue(typeof target === 'string' && target.length <= 4096 && target.startsWith('/')
      && !target.startsWith('//') && !/[\\\x00-\x20#]/.test(target));
    const path = decodeURIComponent(target.split('?')[0]);
    requireValue(!/[\\\x00-\x20]/.test(path) && !/%/.test(path)
      && !path.split('/').some(part => part === '..' || part.startsWith('.')));
    const root = resolve(directory), info = lstatSync(root);
    requireValue(info.isDirectory() && !info.isSymbolicLink() && realpathSync(root) === root);
    const extension = extname(path);
    requireValue(extension === '' || Object.hasOwn(TYPES, extension));
    const relative = path === '/' || extension === '' ? 'index.html' : path.slice(1);
    const file = fileWithin(root, relative), stat = lstatSync(file);
    requireValue(stat.size <= (relative === 'index.html' ? 512 * 1024 : 10 * 1024 * 1024));
    const bytes = readFileSync(file);
    // build-app applies the exact five-tag transform once; serving never reapplies it.
    if (relative === 'index.html') requireValue(!EXTERNAL_TAGS.some(tag => bytes.toString('utf8').includes(tag))
      && !activeExternalLink.test(bytes.toString('utf8')) && bytes.includes(Buffer.from('id="root"')));
    return { status: 200, type: TYPES[extname(relative)], bytes: bytes.length, body: method === 'HEAD' ? Buffer.alloc(0) : bytes };
  } catch { return { status: 404, body: Buffer.alloc(0) }; }
}

export function createPrivateAppServer(directory) {
  requireValue(readPrivateAsset(directory, '/').status === 200);
  return createServer((request, response) => {
    const result = readPrivateAsset(directory, request.url, request.method);
    response.statusCode = result.status;
    response.setHeader('Cache-Control', 'no-store');
    response.setHeader('X-Content-Type-Options', 'nosniff');
    if (result.type) response.setHeader('Content-Type', result.type);
    if (result.bytes !== undefined) response.setHeader('Content-Length', result.bytes);
    response.end(result.body);
  });
}
export async function startPrivateServer(directory) {
  requireValue(directory === '/restore-dist');
  const server = createPrivateAppServer(directory);
  await new Promise((resolveReady, reject) => {
    server.once('error', () => reject(new Error('RESTORE_PRIVATE_APP_REFUSED')));
    server.listen(4173, '127.0.0.1', resolveReady);
  });
  return server;
}
if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  try {
    requireValue(process.argv.length === 4 && process.argv[2] === 'serve');
    await startPrivateServer(process.argv[3]);
  } catch { process.stderr.write('RESTORE_PRIVATE_APP_REFUSED\n'); process.exitCode = 1; }
}
