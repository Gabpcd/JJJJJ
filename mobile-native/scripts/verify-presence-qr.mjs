import { readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { basename, resolve } from 'node:path';
import jsQR from 'jsqr';
import { PNG } from 'pngjs';
import { readPngDimensions } from './png-dimensions.mjs';

/** Decodes pixels from the actual synthetic simulator captures, not an accessibility label. */
export function verifyPresenceQrCaptures(directory, names) {
  const files = folder => readdirSync(folder, { withFileTypes: true }).flatMap(entry =>
    entry.isDirectory() ? files(resolve(folder, entry.name)) : [resolve(folder, entry.name)]);
  const candidates = files(directory);
  const expected = [['presences-code-initial', '123456'], ['presences-code-renouvele', '100002']];
  const results = expected.map(([suffix, value]) => {
    const selected = names.filter(name => name.endsWith(suffix));
    if (selected.length !== 1) throw new Error(`Capture QR manquante ou ambiguë : ${suffix}.`);
    const matching = candidates.filter(path => basename(path) === `${selected[0]}.png`);
    if (matching.length !== 1) throw new Error(`Image QR manquante ou ambiguë : ${suffix}.`);
    const bytes = readFileSync(matching[0]);
    const dimensions = readPngDimensions(bytes);
    if (dimensions.width * dimensions.height > 16_000_000) throw new Error('Capture QR trop grande.');
    const image = PNG.sync.read(bytes);
    const decoded = jsQR(new Uint8ClampedArray(image.data), image.width, image.height, { inversionAttempts: 'dontInvert' });
    if (decoded?.data !== value) throw new Error(`Le QR réellement affiché est absent, coupé ou incorrect : ${suffix}.`);
    return { screen: selected[0], decoded: value, ...dimensions };
  });
  writeFileSync(resolve(directory, 'presence-qr-decoded.json'), JSON.stringify({ synthetic: true, results }, null, 2));
  return results;
}
