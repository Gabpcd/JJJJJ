import { createHash } from 'node:crypto';
import { appendFileSync, existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

export const STAGING_REF = 'mejpriaetwgtcstbgfid';
export const STAGING_URL = `https://${STAGING_REF}.supabase.co`;
const villes = [
  ['Paris', '75001'], ['Lyon', '69002'], ['Marseille', '13001'], ['Toulouse', '31000'], ['Nice', '06000'],
  ['Nantes', '44000'], ['Strasbourg', '67000'], ['Bordeaux', '33000'], ['Lille', '59000'], ['Rennes', '35000'],
];
const professions = ['IDE', 'AS', 'IADE', 'IBODE', 'AES', 'AUXILIAIRE_PUERICULTURE', 'KINE', 'SAGE_FEMME', 'MEDECIN', 'DENTISTE'];
const literal = value => `'${String(value).replaceAll("'", "''")}'`;
const uuid = value => {
  const hex = createHash('sha256').update(`jolene-staging-load-fixture-v1:${value}`).digest('hex');
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-4${hex.slice(13, 16)}-a${hex.slice(17, 20)}-${hex.slice(20, 32)}`;
};
export function configuration(env) {
  if (env.STAGING_SUPABASE_PROJECT_REF !== STAGING_REF || env.STAGING_SUPABASE_URL !== STAGING_URL) {
    throw new Error('Destination refusée : seules les fixtures du staging Jolene sont autorisées.');
  }
  const runId = env.LOAD_TEST_RUN_ID;
  if (!/^[A-Za-z0-9][A-Za-z0-9_-]{0,79}$/.test(runId ?? '')) throw new Error('LOAD_TEST_RUN_ID explicite et valide requis.');
  const brut = env.LOAD_FIXTURE_COUNT ?? '500';
  if (!/^[0-9]+$/.test(brut) || Number(brut) < 100 || Number(brut) > 1000) throw new Error('LOAD_FIXTURE_COUNT doit être entre 100 et 1000.');
  return { runId, count: Number(brut), manifestPath: resolve(env.LOAD_FIXTURE_MANIFEST || 'tests/load/results/fixture-missions-manifest.json') };
}
export function creerManifeste({ runId, count }) {
  // Identifiants déterministes : le même run retrouve exclusivement ses propres données.
  const marker = `RECETTE CHARGE ${runId}`;
  const etabs = villes.map(([ville, codePostal], i) => ({
    id: uuid(`${runId}:etablissement:${i}`), nom: `${marker} — ${ville}`, ville, codePostal,
    email: `recette-charge-${uuid(`${runId}:etablissement:${i}`).slice(0, 8)}@example.invalid`,
    siret: '99' + (BigInt('0x' + createHash('sha256').update(`${runId}:siret:${i}`).digest('hex').slice(0, 12)) % 1_000_000_000_000n).toString().padStart(12, '0'),
  }));
  const missions = Array.from({ length: count }, (_, i) => ({
    id: uuid(`${runId}:mission:${i}`), etablissementId: etabs[i % etabs.length].id,
    intitule: `${marker} — mission ${String(i + 1).padStart(4, '0')}`,
    profession: professions[Math.floor(i / etabs.length) % professions.length], jour: i % 14,
  }));
  return { version: 1, projectRef: STAGING_REF, runId, count, marker, etabs, missions };
}
function verifierManifeste(manifest, config) {
  const attendu = creerManifeste(config);
  for (const key of Object.keys(attendu)) {
    if (JSON.stringify(manifest[key]) !== JSON.stringify(attendu[key])) throw new Error(`Manifeste incohérent (${key}) : aucune suppression autorisée.`);
  }
  return attendu;
}
const tableauIds = rows => `ARRAY[${rows.map(row => `${literal(row.id)}::uuid`).join(',')}]::uuid[]`;
const verrouRun = manifest => {
  // 60 bits positifs : même clé bigint pour prepare/cleanup, distincte entre runs.
  const cle = BigInt(`0x${createHash('sha256').update(`jolene-load-fixtures-lock-v1:${STAGING_REF}:${manifest.runId}`).digest('hex').slice(0, 15)}`);
  return `DO $load_lock$ BEGIN PERFORM pg_advisory_xact_lock(${cle}::bigint); END $load_lock$;`;
};
const idRecuNettoyage = manifest => literal(uuid(`${manifest.runId}:nettoyage-confirme`));
const garde = `
  IF EXISTS (SELECT 1 FROM cron.job WHERE active) THEN
    RAISE EXCEPTION 'Fixtures de charge interdites tant qu un cron staging est actif';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid IN ('public.missions'::regclass, 'public.etablissements'::regclass)
      AND NOT tgisinternal AND tgenabled IN ('R', 'A')) THEN
    RAISE EXCEPTION 'Trigger replica/always non prévu : préparation abandonnée';
  END IF;
  -- Une lecture filtrée par RLS ne peut servir d’oracle pour un reçu immuable.
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = current_user AND (rolsuper OR rolbypassrls)) THEN
    RAISE EXCEPTION 'Rôle Management sans lecture complète du journal : opération refusée';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = 'public.journaux_audit'::regclass
      AND NOT tgisinternal AND tgenabled <> 'D' AND (tgtype & 4) <> 0
      AND tgfoid <> 'public.fn_mirror_teleportation_alerte_systeme()'::regprocedure) THEN
    RAISE EXCEPTION 'Trigger insertion audit non prévu : opération refusée';
  END IF;
`;
export function sqlPreparation(manifest) {
  verifierManifeste(manifest, { runId: manifest.runId, count: manifest.count });
  const etabs = manifest.etabs.map(e => `(${literal(e.id)}::uuid, ${literal(e.nom)}, ${literal(e.siret)}, 'CLINIQUE'::public.type_etablissement,
    'Adresse fictive de recette', ${literal(e.ville)}, ${literal(e.codePostal)}, ${literal(e.email)},
    false, 'VERIFIE', true, false, false, ${literal(manifest.marker)})`).join(',\n');
  const missions = manifest.missions.map(m => `(${literal(m.id)}::uuid, ${literal(m.etablissementId)}::uuid, ${literal(m.intitule)},
    ${literal(manifest.marker + ' — données fictives, recherche uniquement, aucun acte ni destinataire réel.')},
    ${literal(m.profession)}::public.type_profession, 'Recette de charge',
    current_date + interval '14 days 9 hours' + ${m.jour} * interval '1 day',
    current_date + interval '14 days 17 hours' + ${m.jour} * interval '1 day',
    8, 30, 'OUVERTE'::public.statut_mission, NULL, false, 'CANDIDATURE', 'SALARIE')`).join(',\n');
  return `BEGIN;
SET LOCAL statement_timeout = '25s';
SET LOCAL lock_timeout = '5s';
${verrouRun(manifest)}
DO $load_guard$
BEGIN
${garde}
  IF EXISTS (SELECT 1 FROM public.journaux_audit WHERE id = ${idRecuNettoyage(manifest)}::uuid) THEN
    RAISE EXCEPTION 'Run déjà nettoyé : toute préparation tardive est interdite';
  END IF;
  IF EXISTS (SELECT 1 FROM public.etablissements WHERE id = ANY(${tableauIds(manifest.etabs)}))
      OR EXISTS (SELECT 1 FROM public.missions WHERE id = ANY(${tableauIds(manifest.missions)})) THEN
    RAISE EXCEPTION 'IDs du run déjà présents : nettoyer le manifeste avant toute nouvelle préparation';
  END IF;
END $load_guard$;
-- Strictement local à cette transaction staging : aucun email/notification, aucune génération ni réseau.
-- Les CHECK restent actifs ; les seuls liens non nuls fournis sont vérifiés explicitement ci-dessous.
SET LOCAL session_replication_role = replica;
INSERT INTO public.etablissements
  (id, nom, siret, type, adresse_rue, adresse_ville, adresse_code_postal, email_contact,
   est_compte_test, statut_verification, peut_publier_missions, sms_actif, chorus_pro_actif, source_acquisition)
VALUES ${etabs};
INSERT INTO public.missions
  (id, etablissement_id, intitule, description, profession_requise, service, debut_le, fin_le,
   duree_heures, taux_horaire_base, statut, soignant_assigne_id, est_urgente, mode_attribution, type_contrat_recherche)
VALUES ${missions};
SET LOCAL session_replication_role = origin;
DO $load_verify$
DECLARE v_count integer;
BEGIN
  IF EXISTS (SELECT 1 FROM public.missions m LEFT JOIN public.etablissements e ON e.id = m.etablissement_id
      WHERE m.id = ANY(${tableauIds(manifest.missions)}) AND
      (e.id IS NULL OR NOT (e.id = ANY(${tableauIds(manifest.etabs)}))) ) THEN
    RAISE EXCEPTION 'Parent de mission absent ou hors fixture';
  END IF;
  SELECT count(*) INTO v_count FROM public.fn_missions_publiques_recherche(NULL, NULL) r
    WHERE r.id = ANY(${tableauIds(manifest.missions)});
  IF v_count <> ${manifest.count} THEN RAISE EXCEPTION 'Catalogue non visible : % au lieu de ${manifest.count}', v_count; END IF;
END $load_verify$;
COMMIT;
SELECT ${manifest.count}::integer AS missions_preparees, ${manifest.etabs.length}::integer AS etablissements_prepares;
`;
}
export function sqlNettoyage(manifest) {
  verifierManifeste(manifest, { runId: manifest.runId, count: manifest.count });
  return `BEGIN;
SET LOCAL statement_timeout = '25s';
SET LOCAL lock_timeout = '5s';
${verrouRun(manifest)}
-- Le nettoyage garde les contraintes FK actives et refuse toute donnée métier dépendante.
SET LOCAL session_replication_role = origin;
DO $load_cleanup$
DECLARE v_fk record; v_count bigint; v_ids uuid[]; v_parent regclass;
BEGIN
${garde}
  IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid IN ('public.missions'::regclass, 'public.etablissements'::regclass)
      AND NOT tgisinternal AND tgenabled <> 'D' AND (tgtype & 8) <> 0) THEN
    RAISE EXCEPTION 'Trigger de suppression non prévu : nettoyage abandonné';
  END IF;
  IF EXISTS (SELECT 1 FROM public.missions WHERE id = ANY(${tableauIds(manifest.missions)})
    AND (intitule NOT LIKE ${literal(manifest.marker + ' — mission %')}
      OR NOT (etablissement_id = ANY(${tableauIds(manifest.etabs)})) OR statut <> 'OUVERTE' OR soignant_assigne_id IS NOT NULL)) THEN
    RAISE EXCEPTION 'Mission du manifeste modifiée : nettoyage manuel requis';
  END IF;
  IF EXISTS (SELECT 1 FROM public.etablissements WHERE id = ANY(${tableauIds(manifest.etabs)})
    AND (source_acquisition IS DISTINCT FROM ${literal(manifest.marker)} OR email_contact NOT LIKE '%@example.invalid')) THEN
    RAISE EXCEPTION 'Établissement hors marqueur : nettoyage refusé';
  END IF;
  FOREACH v_parent IN ARRAY ARRAY['public.missions'::regclass, 'public.etablissements'::regclass] LOOP
    v_ids := CASE WHEN v_parent = 'public.missions'::regclass THEN ${tableauIds(manifest.missions)} ELSE ${tableauIds(manifest.etabs)} END;
    FOR v_fk IN SELECT c.conrelid::regclass AS enfant, c.conkey, c.confkey, a.attname AS colonne
      FROM pg_constraint c JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = c.conkey[1]
      WHERE c.contype = 'f' AND c.confrelid = v_parent LOOP
      IF cardinality(v_fk.conkey) <> 1 OR cardinality(v_fk.confkey) <> 1 THEN
        RAISE EXCEPTION 'FK composite non prévue : nettoyage refusé';
      END IF;
      EXECUTE format('SELECT count(*) FROM %s WHERE %I = ANY($1)', v_fk.enfant, v_fk.colonne) INTO v_count USING v_ids;
      IF v_count > 0 THEN RAISE EXCEPTION 'Dépendance métier dans % : nettoyage refusé', v_fk.enfant; END IF;
    END LOOP;
    IF v_parent = 'public.missions'::regclass THEN
      DELETE FROM public.missions WHERE id = ANY(v_ids);
    ELSE
      DELETE FROM public.etablissements WHERE id = ANY(v_ids);
    END IF;
  END LOOP;
  -- La confirmation appartient à la transaction qui détient encore le verrou du run.
  IF EXISTS (SELECT 1 FROM public.missions WHERE id = ANY(${tableauIds(manifest.missions)}))
      OR EXISTS (SELECT 1 FROM public.etablissements WHERE id = ANY(${tableauIds(manifest.etabs)})) THEN
    RAISE EXCEPTION 'Nettoyage incomplet : manifeste à conserver';
  END IF;
  -- Même sans fixtures, ce reçu empêche une requête prepare retardée de créer le lot après cleanup.
  -- SYSTEM est l’action autorisée par le CHECK existant ; le marqueur précis reste dans details.
  INSERT INTO public.journaux_audit (id, acteur_id, type_acteur, action, type_ressource, details)
    VALUES (${idRecuNettoyage(manifest)}::uuid, NULL, 'SYSTEME', 'SYSTEM', 'RECETTE_CHARGE',
      jsonb_build_object('evenement', 'RECETTE_CHARGE_NETTOYEE', 'run_id', ${literal(manifest.runId)},
        'project_ref', ${literal(STAGING_REF)}, 'missions_prevues', ${manifest.count}))
    ON CONFLICT (id) DO NOTHING;
  IF NOT EXISTS (SELECT 1 FROM public.journaux_audit
      WHERE id = ${idRecuNettoyage(manifest)}::uuid AND acteur_id IS NULL
      AND type_acteur = 'SYSTEME' AND action = 'SYSTEM' AND type_ressource = 'RECETTE_CHARGE'
      AND details->>'evenement' = 'RECETTE_CHARGE_NETTOYEE'
      AND details->>'run_id' = ${literal(manifest.runId)} AND details->>'project_ref' = ${literal(STAGING_REF)}) THEN
    RAISE EXCEPTION 'Reçu de nettoyage incohérent : manifeste à conserver';
  END IF;
END $load_cleanup$;
COMMIT;
SELECT 0::integer AS missions_restantes, 0::integer AS etablissements_restants;
`;
}
class ErreurRequeteSQL extends Error {
  constructor(message, reessayable) { super(message); this.reessayable = reessayable; }
}
export async function executerFixtures({ action, env = process.env, fetchImpl = fetch, log = console.log,
  attendre = ms => new Promise(resolveAttente => setTimeout(resolveAttente, ms)) }) {
  if (!['prepare', 'cleanup'].includes(action)) throw new Error('Action attendue : prepare ou cleanup.');
  const config = configuration(env);
  const token = env.STAGING_SUPABASE_ACCESS_TOKEN;
  if (!token) throw new Error('Accès Management API staging absent.');
  const requete = async query => {
    let response;
    try {
      response = await fetchImpl(`https://api.supabase.com/v1/projects/${STAGING_REF}/database/query`, {
        method: 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ query }), signal: AbortSignal.timeout(35_000),
      });
    } catch {
      throw new ErreurRequeteSQL('Réponse SQL staging interrompue ou expirée. Le manifeste est conservé.', true);
    }
    if (!response.ok) {
      // Le corps sert uniquement à reconnaître les timeouts PostgreSQL. Jamais journalisé.
      const corps = await response.text?.().catch(() => '') ?? '';
      const timeoutSQL = /\b55P03\b|\b57014\b|\b(?:lock|statement) timeout\b/i.test(corps);
      throw new ErreurRequeteSQL(`SQL staging impossible (HTTP ${response.status}). Le manifeste est conservé pour le nettoyage.`,
        timeoutSQL || [408, 429, 500, 502, 503, 504].includes(response.status));
    }
    let rows;
    try { rows = await response.json(); }
    catch { throw new ErreurRequeteSQL('Réponse SQL staging illisible. Le manifeste est conservé.', true); }
    if (!Array.isArray(rows)) throw new Error('Réponse SQL staging invalide. Le manifeste est conservé.');
    return rows;
  };
  if (action === 'cleanup') {
    if (!existsSync(config.manifestPath)) { log('Aucun manifeste de fixture : aucune suppression.'); return { skipped: true }; }
    const fichier = JSON.parse(readFileSync(config.manifestPath, 'utf8'));
    const manifest = verifierManifeste(fichier, config);
    let result;
    for (let tentative = 1; tentative <= 3; tentative++) {
      try { [result] = await requete(sqlNettoyage(manifest)); break; }
      catch (error) {
        // Seul cleanup est rejoué : UUID exacts, contrôle de dépendances et verrou identiques.
        if (!(error instanceof ErreurRequeteSQL) || !error.reessayable || tentative === 3) throw error;
        log(`Nettoyage non confirmé, nouvelle tentative ${tentative + 1}/3 ; manifeste conservé.`);
        await attendre(tentative * 1000);
      }
    }
    if (result?.missions_restantes !== 0 || result?.etablissements_restants !== 0) throw new Error('Nettoyage non confirmé : conserver le manifeste.');
    writeFileSync(config.manifestPath, JSON.stringify({ ...manifest, status: 'cleaned' }, null, 2));
    log(`Nettoyage confirmé : 0 mission et 0 établissement du run ${config.runId} restants.`);
    return result;
  }
  if (!env.STAGING_SUPABASE_ANON_KEY) throw new Error('Clé anonyme staging requise pour vérifier le vrai parcours public.');
  const manifest = creerManifeste(config);
  mkdirSync(dirname(config.manifestPath), { recursive: true });
  // Écrit avant le réseau. Un HTTP ambigu n’efface jamais les IDs à nettoyer.
  writeFileSync(config.manifestPath, JSON.stringify({ ...manifest, status: 'planned' }, null, 2), { flag: 'wx', mode: 0o600 });
  const [result] = await requete(sqlPreparation(manifest));
  if (result?.missions_preparees !== config.count || result?.etablissements_prepares !== manifest.etabs.length) throw new Error('Quantité de fixtures non confirmée.');
  const response = await fetchImpl(`${STAGING_URL}/rest/v1/rpc/fn_missions_publiques_recherche`, {
    method: 'POST', headers: { apikey: env.STAGING_SUPABASE_ANON_KEY, Authorization: `Bearer ${env.STAGING_SUPABASE_ANON_KEY}`, 'Content-Type': 'application/json' },
    body: '{}', signal: AbortSignal.timeout(15_000),
  });
  if (!response.ok) throw new Error(`Catalogue public de recette inaccessible (HTTP ${response.status}).`);
  const rows = await response.json();
  const ids = new Set(manifest.missions.map(m => m.id));
  const visible = Array.isArray(rows) ? new Set(rows.filter(r => ids.has(r.id)).map(r => r.id)).size : 0;
  if (visible !== config.count) throw new Error(`Catalogue public incomplet : ${visible}/${config.count} missions de la fixture.`);
  writeFileSync(config.manifestPath, JSON.stringify({ ...manifest, status: 'prepared', visible }, null, 2));
  if (env.GITHUB_ENV) appendFileSync(env.GITHUB_ENV, `LOAD_TEST_EXPECTED_MISSIONS=${config.count}\n`);
  log(`Catalogue staging prêt : ${visible} missions visibles, ${manifest.etabs.length} villes, ${professions.length} professions. Aucun compte Auth ni notification créé.`);
  return { ...result, missions_visibles: visible };
}
if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  await executerFixtures({ action: process.argv[2] });
}
