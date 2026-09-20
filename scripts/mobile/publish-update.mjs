import { execFileSync } from 'node:child_process';
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { createHash } from 'node:crypto';
const build = JSON.parse(readFileSync('config/mobile-release.json', 'utf8')).buildNumber;
const sha = execFileSync('git', ['rev-parse', 'HEAD'], { encoding: 'utf8' }).trim();
const tag = `mobile-ota-${build}`;
const gh = (...args) => execFileSync('gh', args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
let release;
try { release = JSON.parse(gh('release', 'view', tag, '--json', 'assets')); }
catch { gh('release', 'create', tag, '--target', sha, '--prerelease', '--title', tag, '--notes', 'Signed compatible mobile corrections.'); release = { assets: [] }; }
const names = new Set(release.assets.map(asset => asset.name));
const archive = `${sha}.zip`;
const manifest = `${sha}.json`;
if (names.has(archive) && names.has(manifest)) {
  // Reuse byte-for-byte artifacts from the first run, never overwrite a ZIP.
  mkdirSync('mobile-update/existing', { recursive: true });
  gh('release', 'download', tag, '--pattern', archive, '--pattern', manifest, '--dir', 'mobile-update/existing', '--clobber');
  const envelope = readFileSync(`mobile-update/existing/${manifest}`);
  const update = JSON.parse(JSON.parse(envelope).payload);
  const checksum = createHash('sha256').update(readFileSync(`mobile-update/existing/${archive}`)).digest('hex');
  if (checksum !== update.checksum || update.id !== sha) throw new Error('Published archive does not match its manifest');
  writeFileSync('mobile-update/manifest.json', envelope);
} else {
  if (names.has(archive) || names.has(manifest)) throw new Error('Incomplete immutable release; inspect artifacts before retrying');
  writeFileSync(`mobile-update/${manifest}`, readFileSync('mobile-update/manifest.json'));
  gh('release', 'upload', tag, `mobile-update/${archive}`, `mobile-update/${manifest}`);
}
gh('release', 'upload', tag, 'mobile-update/manifest.json', '--clobber');
console.log(`Published ${sha} to ${tag}`);
