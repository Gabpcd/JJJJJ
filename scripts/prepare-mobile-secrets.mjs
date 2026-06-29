import { existsSync, mkdirSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';

const googleServicesPath = resolve('android/app/google-services.json');

function decodeGoogleServices() {
  if (process.env.GOOGLE_SERVICES_JSON_BASE64) {
    return Buffer.from(process.env.GOOGLE_SERVICES_JSON_BASE64, 'base64').toString('utf8');
  }
  if (process.env.GOOGLE_SERVICES_JSON) {
    return process.env.GOOGLE_SERVICES_JSON;
  }
  return null;
}

const googleServices = decodeGoogleServices();

if (googleServices) {
  JSON.parse(googleServices);
  mkdirSync(dirname(googleServicesPath), { recursive: true });
  writeFileSync(googleServicesPath, `${googleServices.trim()}\n`, { mode: 0o600 });
  console.log('android/app/google-services.json generated from environment.');
} else if (!existsSync(googleServicesPath)) {
  console.warn('android/app/google-services.json missing; Android FCM push will not work until GOOGLE_SERVICES_JSON is provided.');
}
