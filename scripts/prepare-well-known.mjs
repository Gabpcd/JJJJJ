import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';

const assetlinksPath = resolve('public/.well-known/assetlinks.json');
const requireAndroidAppLinks = process.env.REQUIRE_ANDROID_APP_LINKS === '1';
const rawFingerprints =
  process.env.ANDROID_SHA256_CERT_FINGERPRINTS ||
  process.env.ANDROID_UPLOAD_CERT_SHA256 ||
  '';

const fingerprints = rawFingerprints
  .split(/[,\s]+/)
  .map((value) => value.trim())
  .filter(Boolean);

const fingerprintPattern = /^[0-9A-F]{2}(:[0-9A-F]{2}){31}$/i;

function assetLinksValide() {
  if (!existsSync(assetlinksPath)) return false;
  try {
    const document = JSON.parse(readFileSync(assetlinksPath, 'utf8'));
    if (!Array.isArray(document)) return false;
    return document.some((entry) => {
      const declared = entry?.target?.sha256_cert_fingerprints;
      return entry?.relation?.includes('delegate_permission/common.handle_all_urls')
        && entry?.target?.namespace === 'android_app'
        && entry?.target?.package_name === 'app.jolene'
        && Array.isArray(declared)
        && declared.length > 0
        && declared.every((value) => typeof value === 'string' && fingerprintPattern.test(value));
    });
  } catch {
    return false;
  }
}

if (fingerprints.length > 0) {
  const invalid = fingerprints.filter((value) => !fingerprintPattern.test(value));
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
} else if (!assetLinksValide()) {
  const message = 'public/.well-known/assetlinks.json is missing or invalid; set ANDROID_SHA256_CERT_FINGERPRINTS before store release.';
  if (requireAndroidAppLinks) throw new Error(message);
  console.warn(message);
}
