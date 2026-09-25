import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { configuration, creerManifeste, STAGING_REF } from './prepare-load-fixtures.mjs';

// Définition LIVE staging relue le 25/09/2026. Si elle change, relire le SQL
// avant de comparer le plan développé : celui-ci n'est jamais installé en DB.
export const SEARCH_DEFINITION_MD5 = '6b3e673608b0848e2d2a2026587708d6';
const ENDPOINT = `https://api.supabase.com/v1/projects/${STAGING_REF}/database/query`;
const MAX_RESPONSE_BYTES = 512 * 1024;
const EXPLAIN = 'EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)';
const literal = value => `'${String(value).replaceAll("'", "''")}'`;

const contexte = (query, mode = 'auto') => `BEGIN READ ONLY;
SET LOCAL statement_timeout = '8s';
SET LOCAL lock_timeout = '2s';
SET LOCAL plan_cache_mode = '${mode}';
SET LOCAL request.jwt.claims = '{"role":"anon"}';
SET LOCAL request.jwt.claim.sub = '';
SET LOCAL request.jwt.claim.role = 'anon';
DO $diagnostic_guard$
BEGIN
  IF auth.uid() IS NOT NULL THEN RAISE EXCEPTION 'Identité anonyme requise'; END IF;
  IF md5(pg_get_functiondef('public.fn_missions_publiques_recherche(text,text)'::regprocedure))
      <> '${SEARCH_DEFINITION_MD5}' THEN RAISE EXCEPTION 'Définition recherche modifiée'; END IF;
  IF EXISTS (SELECT 1 FROM cron.job WHERE active) THEN RAISE EXCEPTION 'Cron staging actif'; END IF;
END $diagnostic_guard$;
${query}
ROLLBACK;`;

// Même SELECT que le corps LIVE, avec les quatre variables du chemin public
// remplacées par leurs valeurs : profession/ville/uid NULL, soignant false.
// Le RPC reste la mesure principale ; ce plan révèle seulement ses nœuds internes.
const rechercheInterneAnonyme = `WITH filtered AS (
  SELECT m.id AS mid, m.intitule AS mintitule, m.profession_requise::text AS mprof,
    e.adresse_ville::text AS mville, e.adresse_code_postal::text AS mcp,
    m.debut_le AS mdebut, m.fin_le AS mfin, m.taux_horaire_base AS mtaux,
    COALESCE(m.est_urgente, false) AS murgente,
    m.type_contrat_recherche::text AS mcontrat, m.cree_le AS mcree
  FROM public.missions m JOIN public.etablissements e ON e.id = m.etablissement_id
  WHERE m.statut = 'OUVERTE' AND m.debut_le > now()
    AND e.supprime_le IS NULL AND COALESCE(e.est_compte_test, false) = false
    AND e.statut_verification = 'VERIFIE' AND COALESCE(e.peut_publier_missions, false) = true
    AND e.type <> 'PHARMACIE_OFFICINE' AND m.intitule NOT LIKE '[%'
    AND (NULL::text IS NULL OR btrim(NULL::text) = '' OR m.profession_requise::text = btrim(NULL::text))
    AND (NULL::text IS NULL OR btrim(NULL::text) = ''
      OR e.adresse_ville ILIKE '%' || btrim(NULL::text) || '%'
      OR e.adresse_code_postal LIKE btrim(NULL::text) || '%')
    AND (NOT false OR public.fn_soignant_eligible_mission(NULL::uuid, m.id, false))
    AND (NULL::uuid IS NULL OR NOT public.fn_est_exclu(NULL::uuid, m.etablissement_id))
), counted AS (SELECT count(*)::bigint AS cnt FROM filtered)
SELECT f.mid, f.mintitule, f.mprof, f.mville, f.mcp, f.mdebut, f.mfin,
  f.mtaux, f.murgente, f.mcontrat, c.cnt
FROM filtered f CROSS JOIN counted c ORDER BY f.murgente DESC, f.mcree DESC`;

export function sondesDiagnostic(manifest) {
  const ids = manifest.missions.map(m => `${literal(m.id)}::uuid`).join(',');
  const rpc = (profession, ville) => `SELECT COALESCE(json_agg(r), '[]'::json)
    FROM public.fn_missions_publiques_recherche(${profession}, ${ville}) r;`;
  const metadata = `SELECT jsonb_build_object(
    'definition_md5', md5(pg_get_functiondef('public.fn_missions_publiques_recherche(text,text)'::regprocedure)),
    'uid_null', auth.uid() IS NULL, 'role', current_user, 'read_only', current_setting('transaction_read_only'),
    'function_owner', pg_get_userbyid((SELECT proowner FROM pg_proc
      WHERE oid='public.fn_missions_publiques_recherche(text,text)'::regprocedure)),
    'server_version', current_setting('server_version'), 'jit', current_setting('jit'),
    'plan_cache_mode', current_setting('plan_cache_mode'), 'timezone', current_setting('TimeZone'),
    'captured_at', clock_timestamp(),
    'fixture_count', (SELECT count(*) FROM public.missions WHERE id = ANY(ARRAY[${ids}]::uuid[])),
    'tables', (SELECT jsonb_agg(jsonb_build_object('table', relname, 'live', n_live_tup,
      'dead', n_dead_tup, 'last_analyze', last_analyze, 'last_autoanalyze', last_autoanalyze,
      'mod_since_analyze', n_mod_since_analyze) ORDER BY relname)
      FROM pg_stat_user_tables WHERE schemaname='public' AND relname IN ('missions','etablissements','soignants')),
    'activity', (SELECT jsonb_build_object('active', count(*) FILTER (WHERE state='active'),
      'waiting', count(*) FILTER (WHERE state='active' AND wait_event IS NOT NULL))
      FROM pg_stat_activity WHERE datname=current_database() AND pid<>pg_backend_pid()),
    'search_statements', (SELECT COALESCE(jsonb_agg(to_jsonb(s)), '[]'::jsonb) FROM (
      SELECT queryid::text AS query_id, calls, rows, total_exec_time, mean_exec_time,
        min_exec_time, max_exec_time, shared_blks_hit, shared_blks_read, temp_blks_written
      FROM extensions.pg_stat_statements WHERE query ILIKE '%fn_missions_publiques_recherche%'
        AND query NOT ILIKE '%pg_stat_statements%'
      ORDER BY total_exec_time DESC LIMIT 12
    ) s)
  ) AS metadata;`;
  const tailles = 'SELECT cas, lignes, octets_json, octets_pg FROM (\n' + ['NULL,NULL', "'IDE','Paris'", "NULL,'Paris'"].map((args, i) => `SELECT ${i} AS ordre, '${['sans_filtre','ide_paris','ville_paris'][i]}' AS cas,
    count(*)::integer AS lignes, octet_length(COALESCE(json_agg(r), '[]'::json)::text) AS octets_json,
    pg_column_size(COALESCE(json_agg(r), '[]'::json)) AS octets_pg
    FROM public.fn_missions_publiques_recherche(${args}) r`).join('\nUNION ALL\n') + '\n) mesures ORDER BY ordre;';
  return [
    { id: '01-metadonnees', kind: 'metadata', query: contexte(metadata) },
    { id: '02-volumes', kind: 'sizes', query: contexte(tailles) },
    { id: '03-rpc-sans-filtre-auto', kind: 'plan', query: contexte(`${EXPLAIN}\n${rpc('NULL', 'NULL')}`) },
    { id: '04-rpc-ide-paris-auto', kind: 'plan', query: contexte(`${EXPLAIN}\n${rpc("'IDE'", "'Paris'")}`) },
    { id: '05-rpc-sans-filtre-custom', kind: 'plan', query: contexte(`${EXPLAIN}\n${rpc('NULL', 'NULL')}`, 'force_custom_plan') },
    { id: '06-select-interne-public', kind: 'plan', query: contexte(`DO $diagnostic_owner$
BEGIN
  IF current_user <> pg_get_userbyid((SELECT proowner FROM pg_proc
      WHERE oid='public.fn_missions_publiques_recherche(text,text)'::regprocedure)) THEN
    RAISE EXCEPTION 'Le plan interne doit utiliser le propriétaire du RPC';
  END IF;
END $diagnostic_owner$;
${EXPLAIN}\n${rechercheInterneAnonyme};`) },
  ];
}

async function lireJSON(response) {
  // Un corps inattendu/immense ne doit ni remplir les artifacts ni être journalisé.
  const reader = response.body?.getReader();
  if (!reader) throw new Error('Réponse SQL sans corps JSON.');
  const chunks = []; let length = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      length += value.byteLength;
      if (length > MAX_RESPONSE_BYTES) { await reader.cancel(); throw new Error('limite'); }
      chunks.push(value);
    }
    return JSON.parse(Buffer.concat(chunks, length).toString('utf8'));
  } catch { throw new Error('Réponse SQL JSON invalide ou trop volumineuse.'); }
}

function verifierResultat(sonde, data, count) {
  if (!Array.isArray(data)) throw new Error('Format de résultat SQL inattendu.');
  if (sonde.kind === 'metadata') {
    const m = data[0]?.metadata;
    if (data.length !== 1 || m?.definition_md5 !== SEARCH_DEFINITION_MD5 || m.uid_null !== true
      || m.read_only !== 'on' || Number(m.fixture_count) !== count) {
      throw new Error('Contexte SQL ou catalogue fictif non confirmé.');
    }
  } else if (sonde.kind === 'sizes') {
    if (data.length !== 3 || !data.every((r, i) => r.cas === ['sans_filtre','ide_paris','ville_paris'][i]
      && Number.isSafeInteger(r.lignes) && r.lignes >= 0
      && Number.isSafeInteger(r.octets_json) && r.octets_json > 0
      && Number.isSafeInteger(r.octets_pg) && r.octets_pg > 0)
      || data[0].lignes < count) throw new Error('Mesure de volume incohérente.');
  } else if (data.length !== 1 || !Array.isArray(data[0]?.['QUERY PLAN'])
    || data[0]['QUERY PLAN'].length !== 1 || !data[0]['QUERY PLAN'][0]?.Plan) {
    throw new Error('Plan SQL JSON absent.');
  }
  return data;
}

export async function executerDiagnostic({ env = process.env, fetchImpl = fetch, log = console.log,
  maintenant = Date.now } = {}) {
  const config = configuration(env);
  if (!env.STAGING_SUPABASE_ACCESS_TOKEN) throw new Error('Accès Management API staging absent.');
  let fichier;
  try { fichier = JSON.parse(readFileSync(config.manifestPath, 'utf8')); }
  catch { throw new Error('Manifeste de charge préparé requis.'); }
  const manifest = creerManifeste(config);
  if (fichier.status !== 'prepared' || fichier.visible !== config.count
    || Object.keys(manifest).some(key => JSON.stringify(fichier[key]) !== JSON.stringify(manifest[key]))) {
    throw new Error('Manifeste non préparé ou incohérent : aucun diagnostic exécuté.');
  }
  const output = resolve(env.LOAD_DIAGNOSTICS_PATH || 'tests/load/results/diagnostic-recherche.json');
  const report = { version: 1, projectRef: STAGING_REF, runId: config.runId, fixtureCount: config.count,
    status: 'running', probes: [],
    limites: 'Sondes SQL hors charge, auth.uid() NULL et claims anon, rôle de connexion Management consigné. Ne mesure ni pool PostgREST ni latence HTTP. Le SELECT interne est une expansion diagnostique, pas une modification du RPC. Les caches peuvent être réchauffés ; les statistiques pg_stat_statements sont cumulatives.' };
  mkdirSync(dirname(output), { recursive: true });
  const sauvegarder = () => writeFileSync(output, JSON.stringify(report, null, 2) + '\n', { mode: 0o600 });
  sauvegarder();
  const deadline = maintenant() + 75_000;
  try {
    for (const sonde of sondesDiagnostic(manifest)) {
      const restant = deadline - maintenant();
      if (restant <= 0) throw new Error('Budget global du diagnostic expiré.');
      const start = maintenant(); let response;
      try {
        response = await fetchImpl(ENDPOINT, {
          method: 'POST', redirect: 'error',
          headers: { Authorization: `Bearer ${env.STAGING_SUPABASE_ACCESS_TOKEN}`, 'Content-Type': 'application/json' },
          // La lecture seule est imposée par BEGIN READ ONLY puis ROLLBACK.
          // Le rôle Management doit rester le propriétaire du RPC pour son plan
          // développé ; supabase_read_only_user n'a pas EXECUTE sur ce RPC.
          body: JSON.stringify({ query: sonde.query }),
          signal: AbortSignal.timeout(Math.min(12_000, restant)),
        });
      } catch { throw new Error(`Sonde ${sonde.id} interrompue ou expirée.`); }
      // Ne pas lire le corps d'une erreur : il peut contenir SQL, jeton ou données.
      if (!response.ok) throw new Error(`Sonde ${sonde.id} refusée (HTTP ${Number(response.status) || 0}).`);
      const data = verifierResultat(sonde, await lireJSON(response), config.count);
      report.probes.push({ id: sonde.id, kind: sonde.kind, elapsedMs: maintenant() - start, result: data });
      sauvegarder(); log(`Diagnostic staging : ${sonde.id} confirmé.`);
    }
    report.status = 'completed'; sauvegarder();
    log('Diagnostic staging terminé : six sondes en lecture seule, aucun résultat métier exporté.');
    return report;
  } catch (error) {
    report.status = 'failed'; sauvegarder();
    throw error;
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  try { await executerDiagnostic(); }
  catch (error) { console.error(error.message); process.exitCode = 1; }
}
