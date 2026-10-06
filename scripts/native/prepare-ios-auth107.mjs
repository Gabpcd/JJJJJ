// Adaptations du banc uniquement, dans le checkout CI jetable du commit livré.
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { readFile, writeFile, mkdir, readdir } from 'node:fs/promises';
import { resolve } from 'node:path';

const sha = 'bf1c0ebf771533bb1666ae5f2bfd09560e4b0c84';
assert.equal(process.env.CI, 'true');
assert.equal(process.env.NATIVE_RECETTE, '1');
assert.equal(process.env.GIT_COMMIT_SHA, sha);
assert.equal(execFileSync('git', ['rev-parse', 'HEAD'], { encoding: 'utf8' }).trim(), sha);
assert.equal(process.env.VITE_SUPABASE_URL, 'https://mejpriaetwgtcstbgfid.supabase.co');
assert(process.env.VITE_SUPABASE_PUBLISHABLE_KEY);
assert.equal(process.env.VITE_SENTRY_DSN, '');
const checksum = value => createHash('sha256').update(value).digest('hex');
const sourceHashes = {};
for (const path of ['ios/App/App.xcodeproj/project.pbxproj', 'ios/App/App/Info.plist',
  'capacitor.config.ts', 'tests/native/android/api.py', 'package-lock.json']) {
  sourceHashes[path] = checksum(await readFile(path));
}
let config = await readFile('capacitor.config.ts', 'utf8');
assert.equal(config.split("appId: 'app.jolene'").length, 2);
// Garder les plugins, le clavier et contentInset du produit ; seul l'ID diffère.
config = config.replace("appId: 'app.jolene'", "appId: 'app.jolene.recette'");
await writeFile('capacitor.config.ts', config);
let otaReplacements = 0;
async function isolate(directory) {
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    const path = resolve(directory, entry.name);
    if (entry.isDirectory()) { await isolate(path); continue; }
    if (!entry.name.endsWith('.js')) continue;
    const source = await readFile(path, 'utf8');
    const remote = 'https://github.com/Gabpcd/JJJJJ/releases/download/';
    otaReplacements += source.split(remote).length - 1;
    await writeFile(path, source.replaceAll(remote, 'http://127.0.0.1:8904/mobile-updates/'));
  }
}
await isolate('dist');
assert(otaReplacements > 0, 'La sonde OTA native doit être isolée');
let html = await readFile('dist/index.html', 'utf8');
html = html.replace(/<link\b(?=[^>]*\brel=["'](?:preconnect|dns-prefetch)["'])[^>]*>/gi, '');
const csp = "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self' data:; connect-src 'self' http://127.0.0.1:8904 ws://127.0.0.1:8904 https://mejpriaetwgtcstbgfid.supabase.co wss://mejpriaetwgtcstbgfid.supabase.co; frame-src 'none'; form-action 'none'; base-uri 'self'";
const monitor = `<script>localStorage.setItem('cookie-consent','refused');
const report=data=>fetch('http://127.0.0.1:8904/__recette/erreur',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(data)}).catch(()=>{});
const nativeFetch=window.fetch.bind(window);
window.fetch=async(...args)=>{const start=Date.now();try{const response=await nativeFetch(...args);
const url=new URL(typeof args[0]==='string'?args[0]:args[0].url);
if(url.hostname==='mejpriaetwgtcstbgfid.supabase.co')report({type:'request',path:url.pathname,status:response.status,duration:Date.now()-start});
return response;}catch(error){throw error;}};
window.addEventListener('error',e=>report({type:'error',message:e.message}));
window.addEventListener('unhandledrejection',e=>report({type:'rejection',message:String(e.reason)}));
// Observation seule : conserver les options, le callback et la promesse natifs.
if(navigator.locks){const originalRequest=navigator.locks.request.bind(navigator.locks);
navigator.locks.request=(name,...args)=>{const start=Date.now(),options=typeof args[0]==='object'?args[0]:{};
const path=String(name),status=options.steal?'steal':'normal';
report({type:'lock',path,status:status+'-requested',duration:0});
const pending=originalRequest(name,...args);pending.then(
()=>report({type:'lock',path,status:status+'-released',duration:Date.now()-start}),
error=>report({type:'lock',path,status:status+'-'+error.name,duration:Date.now()-start}));return pending;};}
report({type:'lifecycle',status:'html-loaded',duration:performance.now()});
window.addEventListener('load',()=>report({type:'lifecycle',status:'window-loaded',duration:performance.now()}));
window.addEventListener('securitypolicyviolation',e=>report({type:'csp',blockedURI:e.blockedURI,directive:e.violatedDirective}));</script>`;
assert(html.includes('<head>'));
await writeFile('dist/index.html', html.replace('<head>', `<head><meta http-equiv="Content-Security-Policy" content="${csp}">${monitor}`));
await mkdir('test-results/ios-native', { recursive: true });
await writeFile('test-results/ios-native/build-input.json', JSON.stringify({
  sha, toolingSha: process.env.GITHUB_SHA, runId: process.env.GITHUB_RUN_ID,
  version: '1.0.7', build: '24', bundle: 'app.jolene.recette', sourceHashes,
  api: 'https://mejpriaetwgtcstbgfid.supabase.co', otaReplacements,
  mode: 'SIMULATEUR_IOS_AUTH_ET_DB_STAGING_REELS', storeBinary: false, nativeUpdateLookupMayContactApple: true,
  adaptations: ['bundle isolé', 'API staging, email auto-confirmé comme en production pendant le test, restauration obligatoire', 'CSP locale et télémétrie désactivée',
    'sonde OTA locale sans mise à jour', 'ATS du banc pour HTTP local', 'signature désactivée pour simulateur'],
}, null, 2) + '\n');
