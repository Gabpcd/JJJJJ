import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';

const assetlinksPath = resolve('public/.well-known/assetlinks.json');
const rawFingerprints =
  process.env.ANDROID_SHA256_CERT_FINGERPRINTS ||
  process.env.ANDROID_UPLOAD_CERT_SHA256 ||
  '';

const fingerprints = rawFingerprints
  .split(/[,\s]+/)
  .map((value) => value.trim())
  .filter(Boolean);

if (fingerprints.length > 0) {
  const invalid = fingerprints.filter((value) => !/^[0-9A-F]{2}(:[0-9A-F]{2}){31}$/i.test(value));
  if (invalid.length > 0) {
    throw new Error('ANDROID_SHA256_CERT_FINGERPRINTS must contain SHA-256 fingerprints like AA:BB:...:FF.');
  }

  const assetlinks = [
    {
      relation: ['delegate_permission/common.handle_all_urls'],
      target: {
        namespace: 'android_app',
        package_name: 'app.jolene',
        sha256_cert_fingerprints: fingerprints,
      },
    },
  ];
  writeFileSync(assetlinksPath, `${JSON.stringify(assetlinks, null, 2)}\n`);
  console.log('public/.well-known/assetlinks.json generated from Android SHA-256 fingerprint(s).');
} else if (existsSync(assetlinksPath) && readFileSync(assetlinksPath, 'utf8').includes('REPLACE_WITH_YOUR_SHA256_FINGERPRINT')) {
  console.warn('public/.well-known/assetlinks.json still contains a placeholder; set ANDROID_SHA256_CERT_FINGERPRINTS before store release.');
}
