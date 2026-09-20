import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { createHash, createPrivateKey, createPublicKey, sign } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import path from 'node:path';

// The private key is supplied by CI, never included in the application bundle.
const release = JSON.parse(readFileSync('config/mobile-release.json', 'utf8'));
const id = execFileSync('git', ['rev-parse', 'HEAD'], { encoding: 'utf8' }).trim();
const key = createPrivateKey(readFileSync(process.env.MOBILE_UPDATE_KEY_FILE));
const expected = createPublicKey(readFileSync('config/mobile-update-public.pem')).export({ type: 'spki', format: 'der' });
if (!createPublicKey(key).export({ type: 'spki', format: 'der' }).equals(expected)) throw new Error('OTA signing key does not match the native public key');
const output = path.resolve(process.env.MOBILE_UPDATE_OUTPUT || 'mobile-update');
mkdirSync(output, { recursive: true });
const archive = path.join(output, `${id}.zip`);
execFileSync('zip', ['-q', '-r', archive, '.', '-x', '*.map'], { cwd: 'dist' });
const bytes = readFileSync(archive);
const payload = JSON.stringify({
  schema: 1, appId: 'app.jolene', nativeVersion: release.marketingVersion,
  nativeBuild: String(release.buildNumber), id,
  url: `https://github.com/Gabpcd/JJJJJ/releases/download/mobile-ota-${release.buildNumber}/${id}.zip`,
  checksum: createHash('sha256').update(bytes).digest('hex'),
  signature: sign('sha256', bytes, key).toString('base64'),
});
writeFileSync(path.join(output, 'manifest.json'), JSON.stringify({ payload, signature: sign('sha256', Buffer.from(payload), key).toString('base64') }));
console.log(`Signed update ${id} for ${release.marketingVersion} (${release.buildNumber})`);
