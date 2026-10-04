import { phaseFailure } from './failure.mjs';
// Thin adapter over the unchanged qualified bootstrap, not a second bootstrap.
import { spawnSync } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { readFileSync, writeFileSync, lstatSync, mkdirSync, realpathSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { main as bootstrap, validatePlan, validateInspection, QUALIFICATION_DB, runName, projectSqlDiagnostic } from '../restore/bootstrap.mjs';
import { digest, fileTree } from './snapshot-restore.mjs';

const HERE = fileURLToPath(new URL('.', import.meta.url));
const LABEL = 'org.jolene.restore-drill', SIDES = ['source', 'target'], ROLES = ['db', 'auth', 'rest', 'storage', 'api'];
const requireValue = (ok, code, diagnostic) => { if (!ok) throw phaseFailure(code, diagnostic); };
const decodeLast = bytes => JSON.parse(bytes.toString('utf8').trim().split('\n').at(-1));
export function preparePlan(privateDir, run) {
  bootstrap(['plan-qualification', privateDir, run]);
  const file = join(privateDir, 'compose.private.json'), manifestFile = join(privateDir, 'manifest.json');
  const plan = JSON.parse(readFileSync(file, 'utf8')), manifest = JSON.parse(readFileSync(manifestFile, 'utf8'));
  // Exact volume copy requires equal internal file tenant prefixes. This identifier
  // is run-local; databases, volumes, keys/passwords, gateways and APIs stay distinct.
  for (const side of SIDES) plan.services[side + '-storage'].environment.TENANT_ID = run + '-restore';
  validatePlan(plan, run);
  const locked = new Set(JSON.parse(readFileSync(new URL('../../images.lock.json', import.meta.url))).images.map(image => image.reference));
  requireValue(Object.values(plan.services).every(service => locked.has(service.image)), 'RESTORE_IMAGES_NOT_PINNED');
  for (const [path, expected] of Object.entries(manifest.gateway_sha256)) {
    requireValue(['source-gateway.private.json', 'target-gateway.private.json'].includes(path)
      && lstatSync(join(privateDir, path)).isFile() && (lstatSync(join(privateDir, path)).mode & 0o077) === 0
      && digest(readFileSync(join(privateDir, path))) === expected, 'RESTORE_GATEWAY_PIN');
  }
  const bytes = Buffer.from(JSON.stringify(plan, null, 2));
  manifest.compose_sha256 = digest(bytes); manifest.app_restore = true;
  writeFileSync(file, bytes, { mode: 0o600 }); writeFileSync(manifestFile, JSON.stringify(manifest, null, 2), { mode: 0o600 });
  return { planned: true, containers: 10, volumes: 6, commonFileTenantOnly: true };
}

export function localRuntime(privateDir) {
  requireValue(realpathSync(privateDir) === resolve(privateDir) && (lstatSync(privateDir).mode & 0o077) === 0, 'RESTORE_PRIVATE_DIRECTORY');
  const manifest = JSON.parse(readFileSync(join(privateDir, 'manifest.json'), 'utf8'));
  const planBytes = readFileSync(join(privateDir, 'compose.private.json')), plan = JSON.parse(planBytes);
  const run = runName(manifest.run);
  requireValue(manifest.app_restore === true && manifest.qualification === true && manifest.database === QUALIFICATION_DB
    && digest(planBytes) === manifest.compose_sha256, 'RESTORE_PLAN_PIN');
  validatePlan(plan, run);
  const locked = new Set(JSON.parse(readFileSync(new URL('../../images.lock.json', import.meta.url))).images.map(image => image.reference));
  requireValue(Object.values(plan.services).every(service => locked.has(service.image)), 'RESTORE_IMAGES_NOT_PINNED');
  for (const [path, expected] of Object.entries(manifest.gateway_sha256)) requireValue(
    ['source-gateway.private.json', 'target-gateway.private.json'].includes(path)
    && lstatSync(join(privateDir, path)).isFile() && (lstatSync(join(privateDir, path)).mode & 0o077) === 0
    && digest(readFileSync(join(privateDir, path))) === expected, 'RESTORE_GATEWAY_PIN');
  for (const side of SIDES) requireValue(plan.services[side + '-storage'].environment.TENANT_ID === run + '-restore', 'RESTORE_TENANT');
  requireValue(plan.services['source-storage'].environment.AUTH_JWT_SECRET !== plan.services['target-storage'].environment.AUTH_JWT_SECRET
    && plan.services['source-db'].environment.POSTGRES_PASSWORD !== plan.services['target-db'].environment.POSTGRES_PASSWORD, 'RESTORE_DISTINCT_SECRETS');
  const commandNamespace = randomUUID();
  let commandNumber = 0;
  const call = (args, input) => {
    const result = spawnSync('docker', args, { input, encoding: null, maxBuffer: 64 * 1024 * 1024, timeout: 240_000,
      env: { PATH: process.env.PATH, HOME: process.env.HOME } });
    // A private diagnostic may contain SQL/fixture credentials. Never throw it or
    // send it to process stdout, GitHub outputs, attachments, or upload artifacts.
    writeFileSync(join(privateDir, `command-${commandNamespace}-${++commandNumber}.stderr.private`), result.stderr ?? Buffer.alloc(0), { mode: 0o600, flag: 'wx' });
    if (result.error || result.status !== 0 || result.signal !== null) {
      const error = new Error('RESTORE_LOCAL_COMMAND_FAILED');
      const diagnostic = projectSqlDiagnostic(result.stderr?.toString() ?? '');
      error.diagnostic = { sqlstate: diagnostic.sqlstate, line: diagnostic.line };
      throw error;
    }
    return result.stdout;
  };
  const local = JSON.parse(call(['context', 'inspect']));
  requireValue(local.length === 1 && /^unix:\/\/\//.test(local[0].Endpoints?.docker?.Host ?? ''), 'RESTORE_REMOTE_DOCKER_REFUSED');
  const name = (side, role) => { requireValue(SIDES.includes(side) && ROLES.includes(role), 'RESTORE_SERVICE'); return `${run}-${side}-${role}`; };
  const privatePath = path => { requireValue(resolve(path).startsWith(realpathSync(privateDir) + '/'), 'RESTORE_PRIVATE_PATH'); return path; };
  const inspect = () => {
    const names = call(['ps', '-a', '--filter', 'label=' + LABEL + '=' + run, '--format', '{{.Names}}']).toString().trim().split('\n').filter(Boolean);
    const containers = JSON.parse(call(['inspect', ...names]));
    const network = JSON.parse(call(['network', 'inspect', run + '-network']))[0];
    const volumes = JSON.parse(call(['volume', 'inspect', ...Object.values(plan.volumes).map(value => value.name)]));
    requireValue(containers.length === 10 && volumes.length === 6, 'RESTORE_EXACT_RESOURCES');
    validateInspection(plan, network, containers, volumes, { partial: true });
    for (const container of containers) {
      const service = Object.values(plan.services).find(value => '/' + value.container_name === container.Name);
      requireValue(service && container.HostConfig?.LogConfig?.Type === 'none', 'RESTORE_LOG_DRIVER');
      for (const [key, value] of Object.entries(service.environment)) requireValue(container.Config.Env.includes(key + '=' + value), 'RESTORE_ENV_CHANGED');
      if (container.Name.endsWith('-db')) requireValue(JSON.stringify(container.Config.Cmd) === JSON.stringify(service.command), 'RESTORE_WORKERS_CHANGED');
    }
    return containers;
  };
  const verifyState = async expected => {
    requireValue(expected.browser === 'absent', 'RESTORE_BROWSER_MUST_BE_REMOVED');
    const containers = inspect();
    for (const side of SIDES) {
      requireValue(['off', 'db-only', 'running'].includes(expected[side]), 'RESTORE_STATE');
      for (const role of ROLES) {
        const container = containers.find(value => value.Name === '/' + name(side, role));
        const running = expected[side] === 'running' || (expected[side] === 'db-only' && role === 'db');
        requireValue(container.State.Status === (running ? 'running' : 'exited'), 'RESTORE_SERVICE_STATE');
      }
    }
    return true;
  };
  const sql = (side, body, database = QUALIFICATION_DB, admin = false) => {
    requireValue([QUALIFICATION_DB, 'postgres'].includes(database), 'RESTORE_DATABASE'); inspect();
    return call(['exec', '-i', name(side, 'db'), 'psql', '-X', '-q', '-A', '-t', '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=verbose',
      '-U', admin ? 'supabase_admin' : 'postgres', '-h', '/var/run/postgresql', '-d', database, '-f', '-'], Buffer.from(body));
  };
  const runtime = {
    run, plan, side: 'source', verifyState,
    sql: body => sql('source', body), sqlJson: (side, body) => decodeLast(sql(side, body)),
    privateWrite: async (path, bytes) => writeFileSync(privatePath(path), bytes, { mode: 0o600, flag: 'wx' }),
    stopApis: async side => { inspect(); call(['stop', '--time', '10', ...ROLES.filter(role => role !== 'db').map(role => name(side, role))]); },
    stopSource: async () => { inspect(); call(['stop', '--time', '10', ...ROLES.map(role => name('source', role))]); },
    startApis: async side => {
      inspect(); for (const role of ['auth', 'rest', 'storage', 'api']) call(['start', name(side, role)]);
      let ready = false;
      for (let attempt = 0; attempt < 60; attempt++) {
        const state = inspect();
        ready = ROLES.every(role => state.find(container => container.Name === '/' + name(side, role))?.State?.Health?.Status === 'healthy');
        if (ready) break;
        await new Promise(done => setTimeout(done, 2000));
      }
      requireValue(ready, 'RESTORE_API_READINESS_TIMEOUT');
    },
    databaseTool: async (side, tool, args, bytes) => {
      requireValue(side === 'source' && tool === 'pg_dump' && !args.includes('--disable-triggers') && !args.includes('--clean')
        && args[args.indexOf('-d') + 1] === QUALIFICATION_DB, 'RESTORE_DATABASE_TOOL');
      inspect(); return call(['exec', '-i', name(side, 'db'), tool, ...args], bytes);
    },
    archiveList: async (side, bytes) => { inspect(); return call(['exec', '-i', name(side, 'db'), 'pg_restore', '--list'], bytes); },
    copyFilesOut: async (side, destination) => {
      inspect(); mkdirSync(privatePath(destination), { mode: 0o700 });
      call(['cp', '-a', name(side, 'storage') + ':/var/lib/storage/.', destination]);
    },
    assertTargetNativeEmpty: async () => sql('target', readFileSync(new URL('../restore/preflight-empty.sql', import.meta.url), 'utf8')),
    catalogue: async side => decodeLast(sql(side, readFileSync(join(HERE, 'sql/catalogue.sql'), 'utf8'))),

  };
  runtime.api = async (path, request) => {
    requireValue(path === '/auth/v1/admin/users' || /^\/storage\/v1\/object\/jolene-documents\/invoices\/restore\/[a-f0-9-]{36}\/invoice\.(pdf|xml)$/.test(path), 'RESTORE_PREPARATION_API_SCOPE');
    requireValue(request.method === 'POST', 'RESTORE_PREPARATION_API_METHOD'); inspect();
    const code = `let raw='';for await(const chunk of process.stdin)raw+=chunk;const p=JSON.parse(raw);try{const r=await fetch(p.origin+p.path,{method:'POST',redirect:'error',signal:AbortSignal.timeout(15000),headers:{apikey:process.env.SERVICE_KEY,Authorization:'Bearer '+process.env.SERVICE_KEY,'Content-Type':p.request.contentType||'application/json','x-upsert':'false'},body:p.request.binary?Buffer.from(p.request.binary,'base64'):JSON.stringify(p.request.body)});const json=await r.json().catch(()=>null);process.stdout.write(JSON.stringify({status:r.status,json}));}catch{process.exitCode=1;}`;
    return decodeLast(call(['exec', '-i', name('source', 'storage'), 'node', '--input-type=module', '-e', code],
      Buffer.from(JSON.stringify({ origin: `http://${name('source', 'api')}:8000`, path, request }))));
  };
  runtime.assertApiHealthy = async side => {
    inspect();
    const code = `let report={healthy:true,httpStatus:200};for(const path of ['/auth/v1/health','/rest/v1/','/storage/v1/status']){const r=await fetch(${JSON.stringify('http://') }+process.argv[1]+':8000'+path,{headers:{apikey:process.env.ANON_KEY,Authorization:'Bearer '+process.env.ANON_KEY},redirect:'error',signal:AbortSignal.timeout(10000)});if(r.status!==200){report={healthy:false,httpStatus:r.status};await r.body?.cancel();break;}await r.body?.cancel();}process.stdout.write(JSON.stringify(report));`;
    const report=decodeLast(call(['exec', name(side, 'storage'), 'node', '--input-type=module', '-e', code, name(side, 'api')]));
    requireValue(report.healthy===true, 'RESTORE_API_READINESS_TIMEOUT', { httpStatus: report.httpStatus });
  };
  runtime.verifyDocumentBytes = async fixture => {
    await verifyState({ source: 'running', target: 'db-only', browser: 'absent' });
    const expected = fixture.files.map(file => {
      requireValue(/^invoices\/restore\/[a-f0-9-]{36}\/invoice\.(pdf|xml)$/.test(file.key), 'RESTORE_OBJECT_KEY');
      return { key: file.key, bytes: file.bytes.length, sha256: digest(file.bytes) };
    });
    const code = `import {createHash} from 'node:crypto';let raw='';for await(const chunk of process.stdin)raw+=chunk;const p=JSON.parse(raw);try{let verified=0,httpStatus=200;for(const f of p.expected){const r=await fetch(p.origin+'/storage/v1/object/authenticated/jolene-documents/'+f.key,{headers:{apikey:process.env.SERVICE_KEY,Authorization:'Bearer '+process.env.SERVICE_KEY},redirect:'error',signal:AbortSignal.timeout(15000)});httpStatus=r.status;if(r.status!==200){await r.body?.cancel();break;}const bytes=Buffer.from(await r.arrayBuffer());if(bytes.length!==f.bytes||createHash('sha256').update(bytes).digest('hex')!==f.sha256)break;verified++;}process.stdout.write(JSON.stringify({verified,httpStatus}));}catch{process.exitCode=1;}`;
    const verified=decodeLast(call(['exec','-i',name('source','storage'),'node','--input-type=module','-e',code],Buffer.from(JSON.stringify({origin:`http://${name('source','api')}:8000`,expected}))));
    requireValue(verified.verified===2, 'RESTORE_OBJECT_READBACK', { httpStatus: verified.httpStatus });
    return { verified: 2 };
  };
  runtime.guard = async (phase, fixture) => {
    await verifyState({ source: 'running', target: 'db-only', browser: 'absent' });
    requireValue(['empty-imported', 'seeded'].includes(phase), 'RESTORE_SEED_PHASE');
    const users = phase === 'seeded' ? 5 : 0, objects = phase === 'seeded' ? 2 : 0;
    const report = decodeLast(sql('source', `BEGIN READ ONLY; SET LOCAL row_security=off;
SELECT jsonb_build_object('ok',current_database()='${QUALIFICATION_DB}' AND inet_server_addr() IS NULL
AND current_setting('cron.launch_active_jobs')='off' AND current_setting('max_worker_processes')='0'
AND (SELECT count(*) FROM auth.users)=${users} AND (SELECT count(*) FROM storage.objects)=${objects}
AND NOT EXISTS(SELECT 1 FROM cron.job WHERE active) AND NOT EXISTS(SELECT 1 FROM net.http_request_queue)
AND NOT EXISTS(SELECT 1 FROM vault.secrets) AND NOT EXISTS(SELECT 1 FROM auth.sessions)
AND NOT EXISTS(SELECT 1 FROM public.email_queue) AND NOT EXISTS(SELECT 1 FROM public.paiements_escrow)
AND NOT EXISTS(SELECT 1 FROM public.stripe_transfers)); ROLLBACK;`));
    requireValue(report.ok === true && (phase !== 'seeded' || fixture?.projectRef === 'LOCAL_PG17_RESTORE_APP'), 'RESTORE_SEED_GUARD');
  };
  return runtime;
}
