import { mkdirSync, writeFileSync } from 'node:fs';
import path from 'node:path';

const platform = process.argv[2];
const dir = path.join(process.env.RUNNER_TEMP, 'jolene-signing');
mkdirSync(dir, { recursive: true, mode: 0o700 });
function secret(name) {
  const value = process.env[name];
  if (!value) throw new Error(`Required release secret missing: ${name}`);
  return value;
}
function decode(name, file) {
  writeFileSync(path.join(dir, file), Buffer.from(secret(name), 'base64'), { mode: 0o600 });
}
if (platform === 'android') {
  decode('ANDROID_UPLOAD_KEYSTORE_BASE64', 'upload.jks');
  decode('GOOGLE_PLAY_SERVICE_ACCOUNT_BASE64', 'play.json');
  const password = secret('ANDROID_UPLOAD_PASSWORD');
  if (/[\r\n\\]/.test(password)) throw new Error('Unsupported keystore password encoding');
  writeFileSync('android/keystore.properties', `storeFile=${path.join(dir, 'upload.jks')}\nstorePassword=${password}\nkeyAlias=jolene-upload\nkeyPassword=${password}\n`, { mode: 0o600 });
} else if (platform === 'ios') {
  decode('IOS_DISTRIBUTION_P12_BASE64', 'distribution.p12');
  decode('IOS_PROFILE_BASE64', 'distribution.mobileprovision');
  for (const name of ['IOS_CERTIFICATE_PASSWORD', 'ASC_KEY_ID', 'ASC_ISSUER_ID', 'ASC_PRIVATE_KEY_BASE64']) secret(name);
} else throw new Error('Unknown platform');
