import assert from 'node:assert/strict';
import { readFile, writeFile, mkdir, readdir, access } from 'node:fs/promises';
import { resolve } from 'node:path';

// Only an ephemeral CI checkout may be converted into an unpublishable fixture.
// This script never modifies application sources or the release signing setup.
assert.equal(process.env.CI, 'true', 'Use an isolated CI checkout for the native fixture');
assert.equal(process.env.NATIVE_RECETTE, '1', 'Explicit native simulation opt-in required');
const root = process.cwd();
const read = (path) => readFile(resolve(root, path), 'utf8');
const write = (path, value) => writeFile(resolve(root, path), value);
for (const secretFile of ['android/keystore.properties', 'android/app/google-services.json']) {
  await assert.rejects(access(resolve(root, secretFile)), `Unexpected release configuration: ${secretFile}`);
}
assert.equal(process.env.VITE_SUPABASE_URL, 'http://127.0.0.1:8904');
assert.equal(process.env.VITE_SUPABASE_PUBLISHABLE_KEY, 'sb_publishable_native_fixture');
assert.equal(process.env.VITE_SENTRY_DSN, '');
const originalGradle = await read('android/app/build.gradle');
assert.equal(originalGradle.split('applicationId "app.jolene"').length, 2);
await write('android/app/build.gradle', originalGradle.replace('applicationId "app.jolene"', 'applicationId "app.jolene.recette"'));

// Dedicated debug manifest. Release manifest and MainActivity remain unchanged.
await mkdir(resolve(root, 'android/app/src/debug/res/xml'), { recursive: true });
await mkdir(resolve(root, 'android/app/src/debug/res/values'), { recursive: true });
await write('android/app/src/debug/AndroidManifest.xml', `<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android" xmlns:tools="http://schemas.android.com/tools">
  <application android:usesCleartextTraffic="true" android:networkSecurityConfig="@xml/recette_network_security" tools:replace="android:usesCleartextTraffic">
    <meta-data android:name="firebase_messaging_auto_init_enabled" android:value="false" />
    <meta-data android:name="firebase_analytics_collection_enabled" android:value="false" />
  </application>
</manifest>\n`);
// The real push plugin calls FirebaseMessaging.getInstance() at logout even
// with notification permission denied. Initialize only a fictional demo app;
// no token registration, real Firebase project, credential or outbound access.
await write('android/app/src/debug/res/values/recette_firebase.xml', `<?xml version="1.0" encoding="utf-8"?>
<resources>
  <string name="google_app_id" translatable="false">1:000000000000:android:0000000000000000</string>
  <string name="google_api_key" translatable="false">AIzaSy000000000000000000000000000000000</string>
  <string name="gcm_defaultSenderId" translatable="false">000000000000</string>
  <string name="project_id" translatable="false">demo-jolene-native-recette</string>
</resources>\n`);
await write('android/app/src/debug/res/xml/recette_network_security.xml', `<?xml version="1.0" encoding="utf-8"?>
<network-security-config>
  <base-config cleartextTrafficPermitted="false" />
  <domain-config cleartextTrafficPermitted="true"><domain>127.0.0.1</domain><domain>localhost</domain></domain-config>
</network-security-config>\n`);
// Keep the real Capacitor plugins and local bundled assets. A cleartext local
// WebView origin is solely for the adb-reversed in-memory API (never release).
await write('capacitor.config.ts', `import type { CapacitorConfig } from '@capacitor/cli';
const config: CapacitorConfig = {
  appId: 'app.jolene.recette', appName: 'Jolene Recette', webDir: 'dist',
  server: { androidScheme: 'http', hostname: 'localhost', cleartext: true },
  android: { backgroundColor: '#FFFFFF', webContentsDebuggingEnabled: true },
  plugins: { SplashScreen: { launchShowDuration: 0 }, LiveUpdate: { autoUpdateStrategy: 'none' } },
};
export default config;\n`);

const dist = resolve(root, 'dist');
let updateReplacements = 0;
async function isolateAssets(directory) {
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    const file = resolve(directory, entry.name);
    if (entry.isDirectory()) { await isolateAssets(file); continue; }
    if (!entry.name.endsWith('.js')) continue;
    const text = await readFile(file, 'utf8');
    const remote = 'https://github.com/Gabpcd/JJJJJ/releases/download/';
    updateReplacements += text.split(remote).length - 1;
    // CapacitorHttp bypasses the WebView CSP: redirect its OTA probe too.
    await writeFile(file, text.replaceAll(remote, 'http://127.0.0.1:8904/mobile-updates/'));
  }
}
await isolateAssets(dist);
assert(updateReplacements > 0, 'The native OTA probe must be isolated explicitly');
let html = await read('dist/index.html');
html = html.replace(/<link\b(?=[^>]*\brel=["'](?:preconnect|dns-prefetch)["'])[^>]*>/gi, '');
const csp = "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self' data:; connect-src 'self' http://127.0.0.1:8904 ws://127.0.0.1:8904; frame-src 'none'; form-action 'none'; base-uri 'self'";
const monitor = `<script>
localStorage.setItem('cookie-consent','refused');
const report = data => fetch('http://127.0.0.1:8904/__recette/erreur',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(data)}).catch(()=>{});
window.addEventListener('error', e => report({type:'error',message:e.message}));
window.addEventListener('unhandledrejection', e => report({type:'rejection',message:String(e.reason)}));
window.addEventListener('securitypolicyviolation', e => report({type:'csp',blockedURI:e.blockedURI,directive:e.violatedDirective}));
</script>`;
html = html.replace('<head>', `<head><meta http-equiv="Content-Security-Policy" content="${csp}">${monitor}`);
await write('dist/index.html', html);
await mkdir(resolve(root, 'test-results/android-native'), { recursive: true });
await write('test-results/android-native/build.json', JSON.stringify({
  sha: process.env.GIT_COMMIT_SHA, nativePackage: 'app.jolene.recette',
  api: 'http://127.0.0.1:8904', otaProbeReplacements: updateReplacements,
  type: 'Capacitor debug APK with local fictional API; not a store build',
}, null, 2));
