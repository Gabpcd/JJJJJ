import { readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { context, refreshInvoice, deployCommand, PROJECT, FUNCTION, EXPECTED, QUIESCENCE_SQL } from '../../scripts/ci/refresh-generate-invoice-staging.mjs';
const SHA = 'a'.repeat(40), TOKEN = 'MANAGEMENT_TOKEN_CANARY', SECRET = 'PASSWORD_CANARY';
const env = () => ({ GITHUB_ACTIONS: 'true', GITHUB_EVENT_NAME: 'workflow_dispatch', GITHUB_REPOSITORY: 'Gabpcd/JJJJJ',
  GITHUB_REF: 'refs/heads/main', GITHUB_SHA: SHA, INVOICE_EXPECTED_SHA: SHA, GITHUB_RUN_ID: '123456789', GITHUB_RUN_ATTEMPT: '1', STAGING_SUPABASE_ACCESS_TOKEN: TOKEN });
const local = () => ({ sha: SHA, clean: true, config: '[functions.other]\nverify_jwt = true\n\n[functions.generate-invoice]\nverify_jwt = false\n\n[functions.next]\nverify_jwt = true\n' });
const before = () => [
  { id: '00000000-0000-4000-8000-000000000001', slug: FUNCTION, status: 'ACTIVE', ...EXPECTED },
  { id: '00000000-0000-4000-8000-000000000002', slug: 'other-function', status: 'ACTIVE', version: 27, verify_jwt: true, ezbr_sha256: '2'.repeat(64), entrypoint_path: 'file:///opaque/index.ts' },
];
const after = () => { const rows = before(); rows[0].version++; rows[0].ezbr_sha256 = '3'.repeat(64); return rows; };
const quiet = () => [{ active_crons: 0, running_crons: 0, releases: 0, refunds: 0 }];
function harness(overrides = {}) {
  const state = { fetches: [], deployments: 0, checkpoints: [], metadataReads: 0, mainReads: 0 };
  const response = (body, status = 200) => new Response(typeof body === 'string' ? body : JSON.stringify(body), { status });
  const fetchImpl = async (url, options) => {
    state.fetches.push({ url, options });
    if (overrides.fetch) return overrides.fetch(url, options, state);
    if (url === 'https://api.github.com/repos/Gabpcd/JJJJJ/git/ref/heads/main') {
      state.mainReads++; return response({ ref: 'refs/heads/main', object: { type: 'commit', sha: overrides.mainSha?.(state.mainReads) ?? SHA } });
    }
    if (url === `https://api.supabase.com/v1/projects/${PROJECT}/functions`) return response(++state.metadataReads === 1 ? overrides.before ?? before() : overrides.after ?? after());
    if (url === `https://api.supabase.com/v1/projects/${PROJECT}/database/query`) return response(overrides.quiet ?? quiet());
    if (url === `https://${PROJECT}.supabase.co/functions/v1/${FUNCTION}` && options.method === 'OPTIONS') return response(overrides.optionsBody ?? '', overrides.optionsStatus ?? 200);
    if (url === `https://${PROJECT}.supabase.co/functions/v1/${FUNCTION}` && options.method === 'GET') return response(overrides.deniedBody ?? { error: 'Non autorisé' }, overrides.deniedStatus ?? 401);
    throw new Error('Unexpected destination: ' + SECRET);
  };
  const deploy = async () => { state.deployments++; if (overrides.deployError) throw new Error(SECRET); };
  const checkpoint = value => { state.checkpoints.push(value); if (overrides.checkpointError) throw new Error(SECRET); };
  return { state, run: () => refreshInvoice({ env: overrides.env ?? env(), local: overrides.local ?? local(), fetchImpl, deploy, checkpoint }) };
}
test('single staging deployment preserves JWT and other functions; public probes never carry credentials', async () => {
  const h = harness(), result = await h.run(); assert.equal(result.status, 'success'); assert.equal(h.state.deployments, 1);
  assert.equal(result.before.version, 22); assert.equal(result.after.version, 23); assert.equal(result.after.verify_jwt, false);
  assert.equal(result.after.other_functions_metadata_unchanged, true); assert.equal(result.after.other_functions_count, 1);
  assert.equal(result.business_flow_verified, false); assert.equal(result.cloud_font_rendering_verified, false); assert.equal(result.probes.exact_deployed_version_attributed, false);
  assert.equal(h.state.mainReads, 2); assert.equal(h.state.metadataReads, 2); assert.equal(h.state.fetches.length, 7);
  for (const { url, options } of h.state.fetches) {
    assert.equal(options.redirect, 'error'); assert.ok(options.signal instanceof AbortSignal);
    if (url.startsWith('https://api.supabase.com/')) assert.equal(options.headers.Authorization, `Bearer ${TOKEN}`);
    else assert.equal(options.headers.Authorization, undefined);
    assert.ok(!/secrets|api-keys|stripe\.com/.test(url));
    if (options.method === 'POST') assert.deepEqual(JSON.parse(options.body), { query: QUIESCENCE_SQL, read_only: true });
    else assert.equal(options.body, undefined);
  }
  for (const item of [result, ...h.state.checkpoints]) { const out = JSON.stringify(item); assert.ok(!out.includes(TOKEN)); assert.ok(!out.includes('metadata_digest')); assert.ok(!out.includes('file:///')); }
});
for (const [field, value] of [['GITHUB_ACTIONS','false'],['GITHUB_EVENT_NAME','pull_request'],['GITHUB_EVENT_NAME','push'],['GITHUB_REPOSITORY','other/repo'],['GITHUB_REF','refs/heads/feature'],['GITHUB_SHA','b'.repeat(40)],['INVOICE_EXPECTED_SHA','b'.repeat(40)],['GITHUB_RUN_ID','0'],['GITHUB_RUN_ATTEMPT','0'],['STAGING_SUPABASE_ACCESS_TOKEN','']]) {
  test(`refuses invalid context ${field}=${value} before any request`, async () => { const e = env(); e[field] = value; const h = harness({ env: e }), r = await h.run(); assert.equal(r.status, 'failed'); assert.equal(h.state.fetches.length, 0); assert.equal(h.state.deployments, 0); });
}
test('dirty checkout, wrong SHA, true/missing/duplicate JWT section or alternate entrypoint refuse locally', async () => {
  for (const change of [l=>l.clean=false,l=>l.sha='b'.repeat(40),l=>l.config=l.config.replace('verify_jwt = false','verify_jwt = true'),l=>l.config='',l=>l.config+='\n[functions.generate-invoice]\nverify_jwt = false',l=>l.config=l.config.replace('verify_jwt = false','verify_jwt = false\nentrypoint = "other.ts"')]) {
    const l = local(); change(l); const h = harness({ local: l }), r = await h.run(); assert.equal(r.status,'failed'); assert.equal(h.state.fetches.length,0);
  }
  assert.equal(context(env(), { ...local(), config: '[functions.generate-invoice]\n# explanatory comment\nverify_jwt = false # preserve\n' }).sha, SHA);
});
test('main movement is refused before metadata or immediately before deployment', async () => {
  for (const stage of [1,2]) { const h = harness({ mainSha: n => n === stage ? 'b'.repeat(40) : SHA }), r = await h.run(); assert.equal(r.code,'MAIN_MOVED'); assert.equal(h.state.deployments,0); assert.equal(h.state.metadataReads,stage === 1 ? 0 : 1); }
});
test('v22/JWT/hash/status drift, missing target, duplicate or malformed metadata cannot reach deploy', async () => {
  for (const mutate of [r=>r[0].version++,r=>r[0].verify_jwt=true,r=>r[0].ezbr_sha256='9'.repeat(64),r=>r[0].status='REMOVED',r=>r.shift(),r=>r.push(r[0]),r=>r[0].id='-'.repeat(36),r=>r[0].ezbr_sha256=SECRET,r=>r[0].ezbr_sha256='0'.repeat(64)]) {
    const rows=before(); mutate(rows); const h=harness({before:rows}),r=await h.run();assert.equal(r.status,'failed');assert.equal(h.state.deployments,0);assert.ok(!JSON.stringify(r).includes(SECRET));
  }
});
test('each nonzero count, lost row, string zero or added field refuses quiescence without writes', async () => {
  for (const key of ['active_crons','running_crons','releases','refunds']) { const q=quiet();q[0][key]=1;const h=harness({quiet:q});assert.equal((await h.run()).code,'STAGING_NOT_QUIESCENT');assert.equal(h.state.deployments,0); }
  for (const q of [[],[...quiet(),...quiet()],[{...quiet()[0],extra:0}],[{...quiet()[0],active_crons:'0'}]]) { const h=harness({quiet:q});assert.equal((await h.run()).status,'failed');assert.equal(h.state.deployments,0); }
});
test('other function addition/deletion or any metadata change fails even after successful deployment', async () => {
  for (const mutate of [r=>r.pop(),r=>r.push({...r[1],slug:'additional',id:'00000000-0000-4000-8000-000000000003'}),r=>r[1].version++,r=>r[1].verify_jwt=false,r=>r[1].ezbr_sha256='4'.repeat(64),r=>r[1].entrypoint_path='file:///changed.ts',r=>r[1].new_field=SECRET]) {
    const rows=after();mutate(rows);const h=harness({after:rows}),r=await h.run();assert.equal(r.code,'OTHER_FUNCTIONS_CHANGED');assert.equal(h.state.deployments,1);assert.equal(r.deployment_confirmed,false);assert.equal(r.probes,null);assert.ok(!JSON.stringify(r).includes(SECRET));
  }
});
test('same deployment, jumped version, changed ID/JWT and nonactive target never claim confirmation', async () => {
  for (const mutate of [r=>r[0].version=22,r=>r[0].version=24,r=>r[0].id='00000000-0000-4000-8000-000000000003',r=>r[0].verify_jwt=true,r=>r[0].status='THROTTLED',r=>r[0].ezbr_sha256=EXPECTED.ezbr_sha256]) { const rows=after();mutate(rows);const h=harness({after:rows}),r=await h.run();assert.equal(r.code,'DEPLOYMENT_NOT_CONFIRMED');assert.equal(h.state.deployments,1);assert.equal(r.probes,null); }
});
test('a lost CLI result is uncertain and never retried or followed by a business probe', async () => {
  const h=harness({deployError:true}),r=await h.run();assert.equal(r.code,'DEPLOY_RESULT_UNCERTAIN');assert.equal(r.deployment_attempted,true);assert.equal(r.deployment_confirmed,false);assert.equal(h.state.deployments,1);assert.equal(h.state.metadataReads,1);assert.equal(r.probes,null);assert.ok(!JSON.stringify(r).includes(SECRET));
});
test('checkpoint failure prevents deployment', async () => { const h=harness({checkpointError:true}),r=await h.run();assert.equal(r.code,'REPORT_WRITE_FAILED');assert.equal(h.state.deployments,0); });
test('public probes require exact handler status/contracts; failed probes keep a confirmed deployment distinct', async () => {
  for (const options of [{optionsStatus:503},{optionsBody:SECRET},{deniedStatus:200},{deniedBody:{error:'Invalid JWT'}},{deniedBody:{error:'Non autorisé',secret:SECRET}}]) { const h=harness(options),r=await h.run();assert.equal(r.status,'failed');assert.equal(r.deployment_confirmed,true);assert.equal(h.state.deployments,1);assert.equal(r.probes,null);assert.ok(!JSON.stringify(r).includes(SECRET)); }
});
test('provider HTTP/redirect/timeout/JSON errors remain closed with no retry', async () => {
  for (const fetch of [()=>{throw new Error('https://user:'+SECRET+'@host?token='+TOKEN)},()=>new Response(SECRET,{status:429}),()=>new Response(SECRET,{status:500}),()=>new Response(SECRET,{status:200})]) { const h=harness({fetch}),r=await h.run();assert.equal(r.status,'failed');assert.equal(h.state.fetches.length,1);assert.equal(h.state.deployments,0);assert.ok(!JSON.stringify(r).includes(SECRET));assert.ok(!JSON.stringify(r).includes(TOKEN)); }
});
test('CLI uses exactly one fixed deploy with a minimal environment and captures output privately', () => {
  const calls=[]; const execute=(...args)=>{calls.push(args);return calls.length===1?'2.98.0\n':SECRET;};
  deployCommand({...env(),PATH:'/usr/bin',HOME:'/tmp/unit-home',STRIPE_SECRET_KEY:SECRET,SUPABASE_ACCESS_TOKEN:'PROD_CANARY',HTTPS_PROXY:'https://canary'},'/tmp/checkout',execute);
  assert.equal(calls.length,2);assert.deepEqual(calls[0][1],['--version']);assert.deepEqual(calls[1][1],['functions','deploy',FUNCTION,'--project-ref',PROJECT,'--use-api','--no-verify-jwt']);
  const options=calls[1][2];assert.equal(options.cwd,'/tmp/checkout');assert.deepEqual(options.stdio,['ignore','pipe','pipe']);assert.equal(options.timeout,180000);
  assert.deepEqual(Object.keys(options.env).sort(),['CI','DO_NOT_TRACK','HOME','NO_COLOR','PATH','SUPABASE_ACCESS_TOKEN']);assert.equal(options.env.SUPABASE_ACCESS_TOKEN,TOKEN);assert.ok(!JSON.stringify(options).includes(SECRET));assert.ok(!JSON.stringify(options).includes('PROD_CANARY'));
  let count=0;assert.throws(()=>deployCommand(env(),'/tmp/unit',()=>{count++;return 'other-version\n';}),/CLI_VERSION_REFUSED/);assert.equal(count,1);
});

test('API row and key ordering differences are harmless, unlike a changed field', async () => {
  const rows = after().reverse().map(row => Object.fromEntries(Object.entries(row).reverse()));
  const h = harness({ after: rows }), r = await h.run();assert.equal(r.status,'success');assert.equal(r.after.other_functions_metadata_unchanged,true);
});

test('the actual workflow gate fails red on a wrong ref/SHA before checkout or credentials', () => {
  const workflow=readFileSync(new URL('../../.github/workflows/refresh-generate-invoice-staging.yml',import.meta.url),'utf8');
  const gate=workflow.split('        run: |\n')[1].split('      - name:')[0].replace(/^ {10}/gm,'');
  const base={...env(),EXPECTED_SHA:SHA,PATH:process.env.PATH};delete base.STAGING_SUPABASE_ACCESS_TOKEN;
  const ok=spawnSync('bash',['-c',gate],{env:base,encoding:'utf8'});assert.equal(ok.status,0);assert.equal(ok.stdout,'');
  for(const [key,value] of [['GITHUB_REF','refs/heads/pr'],['GITHUB_EVENT_NAME','pull_request_target'],['GITHUB_REPOSITORY','fork/repo'],['GITHUB_SHA','bad'],['EXPECTED_SHA',SECRET]]){
    const no=spawnSync('bash',['-c',gate],{env:{...base,[key]:value},encoding:'utf8'});assert.equal(no.status,1);assert.equal(no.stdout,'TRUSTED_MAIN_REQUIRED\n');assert.equal(no.stderr,'');
  }
});

test('the CLI version cache is ignored and untracked, so version setup preserves the strict clean-checkout guard', () => {
  const cwd = new URL('../../', import.meta.url);
  const path = 'supabase/.temp/cli-latest';
  const tracked = spawnSync('git', ['ls-files', '--error-unmatch', '--', path], { cwd, encoding: 'utf8' });
  assert.equal(tracked.status, 1, 'the CLI rewrites this cache even during --version');
  const ignored = spawnSync('git', ['check-ignore', '--no-index', '--', path], { cwd, encoding: 'utf8' });
  assert.equal(ignored.status, 0);
  assert.equal(ignored.stdout.trim(), path);
});
