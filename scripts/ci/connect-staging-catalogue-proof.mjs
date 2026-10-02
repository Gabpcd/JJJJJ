// Preuve annulée du delta Connect, dans le job staging existant. Aucun COMMIT,
// déploiement Edge, allocation TEST ou accès Stripe. Les pins restent fermés.
import { readFileSync, writeFileSync } from 'node:fs';
import { isAbsolute, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { isDeepStrictEqual } from 'node:util';
import { structuralJsonSql, catalogueSelect } from './connect-staging-closed-sql.mjs';
import { PROJECT, REPOSITORY, MIGRATION, CAPACITY, ADMISSION, digest, canonical, git } from './connect-staging-closed.mjs';
import { renderStagingAdmission } from './connect-staging-admission-render.mjs';

const VERSION = '20261001201055';
const ROUTINES = [
  'private.fn_connect_exiger_service', 'private.fn_connect_operation_verrouiller',
  'private.fn_connect_protocole_ouvert', 'private.fn_connect_creation_autorisee',
  'private.fn_connect_garder_orientation_trace', 'private.fn_connect_garder_operation',
  'public.fn_connect_checkout_preparer', 'public.fn_connect_checkout_lier',
  'public.fn_connect_checkout_verifier', 'public.fn_connect_avant_transfert_lire',
  'public.fn_connect_avant_transfert_arbitrer', 'public.fn_connect_remboursement_prendre',
  'public.fn_connect_remboursement_demarrer', 'public.fn_connect_remboursement_constater',
  'public.fn_connect_remboursements_a_traiter', 'public.fn_stripe_payment_flow_claim',
  'public.fn_stripe_payment_flow_claim_connect_v1', 'public.fn_stripe_webhook_event_claim',
  'public.fn_stripe_webhook_event_claim_connect_v1', 'public.fn_suivi_remboursements_connect_facture',
  'private.fn_connect_test_cohorte', 'private.fn_connect_test_scope',
  'private.fn_connect_test_operation_connue', 'private.fn_connect_test_creation_autorisee',
  'public.fn_connect_test_capacite_lire', 'private.fn_connect_test_reserver_checkout',
  'private.fn_connect_test_reserver_refund', 'private.fn_connect_test_verifier_arbitrage',
  'public.fn_connect_test_checkout_autoriser', 'private.fn_connect_test_exiger_claim',
  'private.fn_connect_test_exiger_evenement', 'public.fn_stripe_payment_flow_claim_connect_test_v1',
  'public.fn_stripe_webhook_event_claim_connect_test_v1', 'public.fn_connect_remboursements_test_a_traiter',
];
const TABLES = ['private.stripe_connect_avant_transfert', 'private.stripe_connect_release_gate', 'private.stripe_connect_test_capacities'];
const TRIGGERS = ['private.stripe_connect_avant_transfert.trg_connect_garder_operation', 'public.stripe_transfers.trg_connect_garder_orientation'];
const quote = v => `'${v.replaceAll("'", "''")}'`;
const array = values => `ARRAY[${values.map(quote).join(',')}]::text[]`;
const hex = (value, length) => typeof value === 'string' && new RegExp(`^[a-f0-9]{${length}}$`).test(value);
const refuse = code => { throw new Error(`CONNECT_CATALOGUE_${code}`); };
const inventoryNames = ROUTINES.filter(x => x.startsWith('public.')).map(x => x.slice(7));

// Les lignes restent dans PostgreSQL. query_to_xml ne contient qu'un MD5 par
// table ; les noms viennent du catalogue et sont quotés comme identifiants.
// L'inventaire autorisé est comparé au témoin PG17, y compris droits/définitions.
const allRowsSql = `(SELECT md5(COALESCE(jsonb_agg(jsonb_build_array(n.nspname,c.relname,
  xpath('/table/row/digest/text()',query_to_xml(format(
    'SELECT md5(COALESCE(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text)::text,''[]'')) AS digest FROM %I.%I t %s',
    n.nspname,c.relname,CASE WHEN n.nspname='private' AND c.relname='security_definer_inventory'
      THEN ${quote(`WHERE regexp_replace(split_part(signature,'(',1),'^public\\.','')<>ALL(${array(inventoryNames)})`)} ELSE '' END),false,false,''))::text)
  ORDER BY n.nspname,c.relname)::text,'[]'))
  FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname IN('public','private','auth') AND c.relkind IN('r','p')
    AND (n.nspname||'.'||c.relname)<>ALL(${array(TABLES)}))`;
export function baselineSql() {
  return `BEGIN READ ONLY; SET LOCAL search_path=pg_catalog; SET LOCAL statement_timeout='30s'; SET LOCAL TIME ZONE 'UTC';
    SELECT s.*,${allRowsSql} AS all_rows FROM (${catalogueSelect(false)}) s; ROLLBACK;`;
}

// Toute surcharge supplémentaire modifie aussi ce fingerprint : aucune règle
// LIKE/prefixe n'autorise implicitement une nouvelle routine ou un nouveau trigger.
function partitionSql(structure, permitted) {
  const belongs = `CASE
    WHEN part.key='routines' THEN ((item->>0)||'.'||(item->>1))=ANY(${array(ROUTINES)})
    WHEN part.key IN('relations','columns','constraints','indexes') THEN ((item->>0)||'.'||(item->>1))=ANY(${array(TABLES)})
    WHEN part.key='triggers' THEN ((item->>0)||'.'||(item->>1)||'.'||(item->>2))=ANY(${array(TRIGGERS)})
    WHEN part.key='inventory' THEN regexp_replace(split_part(item->>'signature','(',1),'^public\\.','')=ANY(${array(inventoryNames)})
    ELSE FALSE END`;
  return `(SELECT jsonb_object_agg(part.key, (SELECT COALESCE(jsonb_agg(item ORDER BY position),'[]'::jsonb)
    FROM jsonb_array_elements(part.value) WITH ORDINALITY entries(item,position)
    WHERE ${permitted ? '' : 'NOT '}(${belongs}))) FROM jsonb_each(${structure}) part)`;
}

export function sourceManifest(root, candidateSha = git(root, ['rev-parse', 'HEAD'])) {
  if (!hex(candidateSha, 40) || git(root, ['rev-parse', 'HEAD']) !== candidateSha
    || git(root,['status','--porcelain','--untracked-files=no']) !== '') refuse('CANDIDATE_REQUIRED');
  const candidate = { sha: candidateSha, tree: git(root, ['rev-parse', 'HEAD^{tree}']) };
  const migration = readFileSync(resolve(root, MIGRATION), 'utf8');
  const capacity = readFileSync(resolve(root, CAPACITY), 'utf8');
  const admission = renderStagingAdmission(migration, readFileSync(resolve(root, ADMISSION), 'utf8'));
  const hashes = { migrationSha256: digest(migration), capacitySha256: digest(capacity), admissionSha256: digest(admission) };
  return { candidate, ...hashes, manifestSha256: digest(JSON.stringify(canonical({ candidate, ...hashes }))), migration, capacity, admission };
}

const publicManifest = source => Object.fromEntries(['candidate','migrationSha256','capacitySha256','admissionSha256','manifestSha256'].map(k => [k, source[k]]));
export function referenceSql(source) {
  return `BEGIN READ ONLY; SET LOCAL search_path=pg_catalog; SET LOCAL TIME ZONE 'UTC';
    WITH allowed AS (SELECT ${partitionSql(structuralJsonSql, true)} doc)
    SELECT jsonb_build_object('schemaVersion',1,'sources',${quote(JSON.stringify(publicManifest(source)))}::jsonb,
      'deltaMd5',md5(doc::text),'counts',(SELECT jsonb_object_agg(key,jsonb_array_length(value)) FROM jsonb_each(doc))) AS reference
    FROM allowed; ROLLBACK;`;
}

export function checkReference(reference, source) {
  if (source.migrationSha256 !== digest(source.migration) || source.capacitySha256 !== digest(source.capacity)
    || source.admissionSha256 !== digest(source.admission)) refuse('SOURCE_CHANGED');
  const manifest = { candidate:source.candidate, migrationSha256:source.migrationSha256,
    capacitySha256:source.capacitySha256, admissionSha256:source.admissionSha256 };
  if (!hex(source.candidate?.sha,40) || !hex(source.candidate?.tree,40)
    || source.manifestSha256 !== digest(JSON.stringify(canonical(manifest)))) refuse('MANIFEST_REQUIRED');
  if (!reference || reference.schemaVersion !== 1 || !isDeepStrictEqual(reference.sources, publicManifest(source))
    || !hex(reference.deltaMd5, 32) || !reference.counts
    || reference.counts.routines !== ROUTINES.length || reference.counts.relations !== 3
    || reference.counts.triggers !== 2 || reference.counts.inventory !== 19
    || reference.counts.views !== 0 || reference.counts.policies !== 0
    || !Object.values(reference.counts).every(x => Number.isSafeInteger(x) && x >= 0)) refuse('REFERENCE_REQUIRED');
}

// Même partition que la preuve distante, pour éprouver ses détecteurs de
// mutation dans le témoin PostgreSQL réel avant de produire des empreintes.
export function detectorSql() {
  return `SET LOCAL search_path=pg_catalog;
    SELECT jsonb_build_object('allowed',md5((${partitionSql(structuralJsonSql,true)})::text),
      'outside',md5((${partitionSql(structuralJsonSql,false)})::text),'rows',${allRowsSql}) AS detector;`;
}

function snapshot(rows, versions) {
  if (!Array.isArray(rows) || rows.length !== 1) refuse('SNAPSHOT_SHAPE');
  const s = rows[0];
  if (!['catalogue','registry','rows','all_rows'].every(k => hex(s[k],32)) || s.quiescent !== true
    || s.gate_closed !== true || s.capacity_closed !== true
    || !isDeepStrictEqual(s.versions, versions)) refuse('BASELINE_REFUSED');
  return s;
}

export function rollbackSql(source, reference, before) {
  checkReference(reference, source);
  if (!['catalogue','registry','rows','all_rows'].every(k => hex(before[k],32))) refuse('BASELINE_REFUSED');
  if ((source.migration.match(/^BEGIN;\s*$/gm)||[]).length !== 1
    || (source.migration.match(/^COMMIT;\s*$/gm)||[]).length !== 1
    || /^\s*(BEGIN|COMMIT|ROLLBACK)\s*;/im.test(source.capacity + '\n' + source.admission)) refuse('TRANSACTION_REQUIRED');
  const body = source.migration.replace(/^BEGIN;\s*$/m, '').replace(/^COMMIT;\s*$/m, '');
  return `BEGIN; SET LOCAL statement_timeout='90s'; SET LOCAL lock_timeout='3s'; SET LOCAL TIME ZONE 'UTC';
    SELECT pg_advisory_xact_lock(184731,1017);
    LOCK TABLE supabase_migrations.schema_migrations IN SHARE ROW EXCLUSIVE MODE NOWAIT;
    SET LOCAL search_path=pg_catalog;
    CREATE TEMP TABLE connect_catalogue_before ON COMMIT DROP AS
      SELECT ${structuralJsonSql} AS structure,to_jsonb(s) AS snapshot FROM (${catalogueSelect(false)}) s;
    DO $before$ DECLARE s jsonb; BEGIN
      SELECT snapshot INTO STRICT s FROM pg_temp.connect_catalogue_before;
      IF s->>'catalogue' IS DISTINCT FROM '${before.catalogue}' OR s->>'registry' IS DISTINCT FROM '${before.registry}'
        OR s->>'rows' IS DISTINCT FROM '${before.rows}'
        OR ${allRowsSql} IS DISTINCT FROM '${before.all_rows}'
        OR s->'quiescent' IS DISTINCT FROM 'true'::jsonb OR s->'gate_closed' IS DISTINCT FROM 'true'::jsonb
        OR s->'capacity_closed' IS DISTINCT FROM 'true'::jsonb
      THEN RAISE EXCEPTION 'CONNECT_CATALOGUE_BASELINE_MOVED'; END IF;
    END $before$;
    ${body}
    ${source.capacity}
    ${source.admission}
    SET LOCAL search_path=pg_catalog;
    DO $delta$ DECLARE b jsonb; a jsonb; BEGIN
      SELECT structure INTO STRICT b FROM pg_temp.connect_catalogue_before;
      SELECT ${structuralJsonSql} INTO a;
      IF ${partitionSql('b', false)} IS DISTINCT FROM ${partitionSql('a', false)}
      THEN RAISE EXCEPTION 'CONNECT_CATALOGUE_OUTSIDE_DELTA_CHANGED'; END IF;
      IF md5((${partitionSql('a', true)})::text) IS DISTINCT FROM '${reference.deltaMd5}'
      THEN RAISE EXCEPTION 'CONNECT_CATALOGUE_REFERENCE_MISMATCH'; END IF;
    END $delta$;
    INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
      VALUES('${VERSION}','reserver_remboursement_connect_avant_transfert',ARRAY[${quote(source.migration)}]);
    DO $after$ DECLARE s record; registry_unchanged text; BEGIN
      SELECT * INTO STRICT s FROM (${catalogueSelect(true)}) x;
      SELECT md5(COALESCE(jsonb_agg(to_jsonb(m) ORDER BY version)::text,'[]')) INTO registry_unchanged
        FROM supabase_migrations.schema_migrations m WHERE version<>'${VERSION}';
      IF registry_unchanged IS DISTINCT FROM '${before.registry}' OR s.rows IS DISTINCT FROM '${before.rows}'
        OR ${allRowsSql} IS DISTINCT FROM '${before.all_rows}'
        OR s.quiescent IS DISTINCT FROM TRUE OR s.gate_closed IS DISTINCT FROM TRUE OR s.capacity_closed IS DISTINCT FROM TRUE
      THEN RAISE EXCEPTION 'CONNECT_CATALOGUE_DATA_OR_CLOSED_STATE_CHANGED'; END IF;
    END $after$;
    SELECT jsonb_build_object('schemaVersion',1,'before',jsonb_build_object('catalogue','${before.catalogue}','registry','${before.registry}'),
      'after',jsonb_build_object('catalogue',s.catalogue,'registry',s.registry),'deltaVerified',true,'businessRowsUnchanged',true,
      'closedStateVerified',true) AS proof FROM (${catalogueSelect(true)}) s;
    ROLLBACK;`;
}

export async function proveCatalogue({ env, source, reference, versions, fetcher = fetch }) {
  if (env.GITHUB_ACTIONS !== 'true' || env.GITHUB_EVENT_NAME !== 'pull_request' || env.GITHUB_REPOSITORY !== REPOSITORY
    || env.STAGING_SUPABASE_PROJECT_REF !== PROJECT || !env.STAGING_SUPABASE_ACCESS_TOKEN
    || env.CANDIDATE_SHA !== source.candidate.sha || !hex(env.BASE_SHA,40)
    || !Array.isArray(versions) || !versions.length || versions.includes(VERSION)
    || versions.some(x => !/^\d{14}$/.test(x)) || !isDeepStrictEqual([...new Set(versions)].sort(),versions)) refuse('CONTEXT_REFUSED');
  checkReference(reference, source);
  const query = async (sql, readOnly) => {
    let response;
    try {
      response = await fetcher(`https://api.supabase.com/v1/projects/${PROJECT}/database/query`, {
        method:'POST', redirect:'error', signal:AbortSignal.timeout(110000),
        headers:{Authorization:`Bearer ${env.STAGING_SUPABASE_ACCESS_TOKEN}`,'Content-Type':'application/json'},
        body:JSON.stringify({query:sql,read_only:readOnly}),
      });
      if (!response.ok) refuse('QUERY_REFUSED');
      const text = await response.text(); if (text.length > 100000) refuse('RESPONSE_TOO_LARGE');
      return JSON.parse(text);
    } catch { refuse('QUERY_OR_TRANSPORT_REFUSED'); }
  };
  const before = snapshot(await query(baselineSql(),true),versions);
  let result, transactionError;
  try { result = await query(rollbackSql(source,reference,before),false); }
  catch(error) { transactionError = error; }
  // Toujours une nouvelle requête indépendante, y compris après erreur SQL ou transport.
  const restored = snapshot(await query(baselineSql(),true),versions);
  if (!isDeepStrictEqual(before,restored)) refuse('ROLLBACK_NOT_RESTORED');
  if (transactionError) throw transactionError;
  if (!Array.isArray(result) || result.length !== 1) refuse('PROOF_SHAPE');
  const proof = result[0].proof;
  if (!proof || proof.schemaVersion !== 1 || proof.deltaVerified !== true || proof.businessRowsUnchanged !== true
    || proof.closedStateVerified !== true || proof.before?.catalogue !== before.catalogue || proof.before?.registry !== before.registry
    || !hex(proof.after?.catalogue,32) || !hex(proof.after?.registry,32)) refuse('PROOF_REFUSED');
  // Projection explicite : aucun champ supplémentaire du transport ne devient
  // un artefact public, même si les empreintes obligatoires sont présentes.
  return { schemaVersion:1, before:{catalogue:proof.before.catalogue,registry:proof.before.registry},
    after:{catalogue:proof.after.catalogue,registry:proof.after.registry},
    deltaVerified:true,businessRowsUnchanged:true,closedStateVerified:true,
    sources:publicManifest(source), referenceDeltaMd5:reference.deltaMd5,
    rollbackVerified:true, protocolEnabled:false, capabilityEnabled:false, providerInvoked:false };
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    if (process.argv[2] === 'detector-sql' && process.argv.length === 3) process.stdout.write(detectorSql());
    else if (process.argv[2] === 'reference-sql' && process.argv.length === 3) {
      process.stdout.write(referenceSql(sourceManifest(process.cwd(),process.env.CANDIDATE_SHA)));
    } else if (process.argv[2] === 'proof' && process.argv.length === 3) {
      const source = sourceManifest(process.cwd(),process.env.CANDIDATE_SHA);
      const dir = process.env.RUNNER_TEMP;
      if (!dir || !isAbsolute(dir)) refuse('PATH_REFUSED');
      const reference = JSON.parse(readFileSync(resolve(dir,'connect-catalogue-reference.json'),'utf8'));
      const versions = git(process.cwd(),['ls-tree','-r','--name-only',process.env.BASE_SHA,'supabase/migrations'])
        .split('\n').map(x => /^supabase\/migrations\/(\d{14})_[^/]+\.sql$/.exec(x)?.[1]).filter(Boolean).sort();
      const proof = await proveCatalogue({env:process.env,source,reference,versions});
      writeFileSync(resolve(dir,'connect-catalogue-proof.json'),JSON.stringify(proof,null,2)+'\n',{flag:'wx',mode:0o600});
      console.log('CONNECT_CATALOGUE_DELTA_ET_ROLLBACK_VERIFIES');
    } else refuse('MODE_REFUSED');
  } catch(error) {
    console.error(error.message?.startsWith('CONNECT_CATALOGUE_') ? error.message : 'CONNECT_CATALOGUE_LOCAL_REFUSED');
    process.exitCode=1;
  }
}
