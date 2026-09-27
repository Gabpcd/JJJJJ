// SQL local uniquement : PGlite doit être installé, aucun accès Supabase.
// PGLITE_MODULE=/chemin/pglite/dist/index.js node tests/load/seed/verify-public-search-local.mjs
// Tables minimales et fonctions de droits sentinelles : preuve de la recherche,
// pas des RLS ni du métier interne des fonctions d'éligibilité et d'exclusion.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { creerManifeste } from '../../../scripts/ci/prepare-load-fixtures.mjs';

const { PGlite } = await import(process.env.PGLITE_MODULE || '@electric-sql/pglite');
const avant = readFileSync(new URL('./fixtures/public-search-before-20260925.sql', import.meta.url), 'utf8');
assert.equal(createHash('md5').update(avant).digest('hex'), '6b3e673608b0848e2d2a2026587708d6', 'Dump LIVE exact');
const migration = readFileSync(new URL('../../../supabase/migrations/20260925153200_recherche_missions_comptage_unique.sql', import.meta.url), 'utf8');
const apres = migration.match(/CREATE OR REPLACE FUNCTION public\.fn_missions_publiques_recherche\([\s\S]*?\$function\$;/)?.[0];
assert.ok(apres, 'Migration complète terminée par un point-virgule');
const attendu = avant.trim()
  .replace('  ), counted AS (\n    SELECT count(*)::bigint AS cnt FROM filtered\n  )', '  )')
  .replace('f.mcontrat, c.cnt', 'f.mcontrat, count(*) OVER ()')
  .replace('FROM filtered f CROSS JOIN counted c', 'FROM filtered f') + ';';
assert.equal(apres, attendu, 'Seul le comptage change : signature, guards, projection et ordre identiques');

const db = new PGlite();
const uid = 'ffffffff-ffff-4fff-afff-fffffffffff1';
const inconnu = 'ffffffff-ffff-4fff-afff-fffffffffff2';
const supprime = 'ffffffff-ffff-4fff-afff-fffffffffff3';
const manifeste = creerManifeste({ runId: 'equivalence-recherche-20260925', count: 500 });
const baseTime = Date.parse('2026-09-25T10:00:00Z');
const etabs = manifeste.etabs.map(e => ({
  id: e.id, adresse_ville: e.ville, adresse_code_postal: e.codePostal,
  type: 'CLINIQUE_PRIVEE', supprime_le: null, est_compte_test: false,
  statut_verification: 'VERIFIE', peut_publier_missions: true,
}));
const missions = manifeste.missions.map((m, i) => ({
  id: m.id, etablissement_id: m.etablissementId, intitule: m.intitule,
  profession_requise: m.profession, statut: 'OUVERTE',
  debut_le: '2099-01-01T07:00:00Z', fin_le: '2099-01-01T15:00:00Z',
  taux_horaire_base: 30 + i % 5, est_urgente: i % 9 === 0 ? null : i % 3 === 0,
  type_contrat_recherche: i % 2 === 0 ? 'LIBERAL' : 'SALARIE',
  // Ex aequo effectifs : aucun des deux SQL ne promet un tri par UUID.
  cree_le: new Date(baseTime - (i % 7) * 60_000).toISOString(),
}));
const byId = new Map(missions.map(m => [m.id, m]));
const paris = etabs.find(e => e.adresse_ville === 'Paris');
assert.ok(paris);
const sentinelle = n => `eeeeeeee-eeee-4eee-aeee-${String(n).padStart(12, '0')}`;
for (const [i, variation] of [
  { est_compte_test: true }, { supprime_le: '2026-01-01T00:00:00Z' },
  { statut_verification: 'EN_ATTENTE' }, { peut_publier_missions: false },
  { peut_publier_missions: null }, { type: 'PHARMACIE_OFFICINE' }, { type: null },
].entries()) {
  etabs.push({ ...etabs[0], ...variation, id: sentinelle(i + 1) });
  missions.push({ ...missions[0], id: sentinelle(i + 101), etablissement_id: sentinelle(i + 1) });
}
for (const [i, variation] of [
  { statut: 'TERMINEE' }, { debut_le: '2000-01-01T00:00:00Z' },
  { intitule: '[fixture cachée]' }, { intitule: null },
].entries()) missions.push({ ...missions[0], ...variation, id: sentinelle(i + 201) });

const cas = [];
try {
  await db.exec(`BEGIN;
    CREATE ROLE anon; CREATE ROLE authenticated; CREATE ROLE service_role; CREATE ROLE sans_droit;
    CREATE SCHEMA auth;
    CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql AS $$
      SELECT nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
    $$;
    CREATE TABLE public.etablissements(id uuid PRIMARY KEY, adresse_ville text, adresse_code_postal text,
      type text, supprime_le timestamptz, est_compte_test boolean, statut_verification text, peut_publier_missions boolean);
    CREATE TABLE public.missions(id uuid PRIMARY KEY, etablissement_id uuid REFERENCES public.etablissements,
      intitule text, profession_requise text, statut text, debut_le timestamptz, fin_le timestamptz,
      taux_horaire_base numeric, est_urgente boolean, type_contrat_recherche text, cree_le timestamptz);
    CREATE TABLE public.soignants(id uuid PRIMARY KEY, supprime_le timestamptz);
    CREATE TABLE public.refus_eligibilite(user_id uuid, mission_id uuid);
    CREATE TABLE public.exclusions(user_id uuid, etablissement_id uuid);
    CREATE TABLE public.appels_droits(nom text);
    CREATE FUNCTION public.fn_soignant_eligible_mission(u uuid, m uuid, strict boolean) RETURNS boolean
    LANGUAGE plpgsql AS $$BEGIN
      INSERT INTO public.appels_droits VALUES ('eligibilite');
      RETURN NOT EXISTS (SELECT 1 FROM public.refus_eligibilite WHERE user_id=u AND mission_id=m);
    END$$;
    CREATE FUNCTION public.fn_est_exclu(u uuid, e uuid) RETURNS boolean
    LANGUAGE plpgsql AS $$BEGIN
      INSERT INTO public.appels_droits VALUES ('exclusion');
      RETURN EXISTS (SELECT 1 FROM public.exclusions WHERE user_id=u AND etablissement_id=e);
    END$$;
  `);
  await db.query('INSERT INTO public.etablissements SELECT * FROM jsonb_populate_recordset(NULL::public.etablissements, $1::jsonb)', [JSON.stringify(etabs)]);
  await db.query('INSERT INTO public.missions SELECT * FROM jsonb_populate_recordset(NULL::public.missions, $1::jsonb)', [JSON.stringify(missions)]);
  await db.query('INSERT INTO public.soignants VALUES ($1, NULL), ($2, now())', [uid, supprime]);
  for (const m of manifeste.missions.slice(0, 5)) {
    for (const user of [uid, inconnu, supprime]) await db.query('INSERT INTO public.refus_eligibilite VALUES ($1, $2)', [user, m.id]);
  }
  for (const user of [uid, inconnu, supprime]) await db.query('INSERT INTO public.exclusions VALUES ($1, $2)', [user, paris.id]);
  await db.exec(avant.replace('public.fn_missions_publiques_recherche(', 'public.fn_recherche_reference(').trim() + ';');
  await db.exec(migration);
  await db.exec(migration);
  const meta = (await db.query(`SELECT p.prosecdef, p.provolatile, p.proconfig,
    md5(pg_get_functiondef(p.oid)) AS definition_md5,
    pg_get_function_result(p.oid) AS retour,
    has_function_privilege('anon',p.oid,'EXECUTE') AS anon,
    has_function_privilege('authenticated',p.oid,'EXECUTE') AS authenticated,
    has_function_privilege('service_role',p.oid,'EXECUTE') AS service_role,
    has_function_privilege('sans_droit',p.oid,'EXECUTE') AS sans_droit
    FROM pg_proc p WHERE p.oid='public.fn_missions_publiques_recherche(text,text)'::regprocedure`)).rows[0];
  assert.equal(meta.prosecdef, true);
  assert.equal(meta.definition_md5, '904e83ab283dac36554a465d7ee717a8', 'Empreinte de la définition compilée utilisée par le diagnostic');
  assert.equal(meta.provolatile, 'v');
  assert.deepEqual(meta.proconfig, ['search_path=public']);
  assert.match(meta.retour, /total_count bigint\)$/);
  assert.equal(meta.anon, true); assert.equal(meta.authenticated, true); assert.equal(meta.service_role, true); assert.equal(meta.sans_droit, false);

  const trier = rows => [...rows].sort((a, b) => a.id.localeCompare(b.id));
  const groupe = row => [row.est_urgente, byId.get(row.id).cree_le];
  async function comparer(nom, profession, ville, attendu, user = '') {
    await db.query("SELECT set_config('request.jwt.claim.sub', $1, true)", [user]);
    const anciennes = (await db.query('SELECT * FROM public.fn_recherche_reference($1, $2)', [profession, ville])).rows;
    await db.exec('TRUNCATE public.appels_droits');
    const nouvelles = (await db.query('SELECT * FROM public.fn_missions_publiques_recherche($1, $2)', [profession, ville])).rows;
    assert.equal(nouvelles.length, attendu, `${nom}: volume indépendant attendu`);
    assert.deepEqual(trier(nouvelles), trier(anciennes), `${nom}: mêmes lignes et toutes colonnes`);
    assert.ok(nouvelles.every(r => Number(r.total_count) === attendu), `${nom}: même total filtré sur chaque ligne`);
    assert.ok(nouvelles.every(r => byId.has(r.id)), `${nom}: aucune sentinelle invisible`);
    assert.deepEqual(nouvelles.map(groupe), anciennes.map(groupe), `${nom}: mêmes groupes de tri`);
    for (let i = 1; i < nouvelles.length; i++) {
      const a = groupe(nouvelles[i - 1]), b = groupe(nouvelles[i]);
      assert.ok(a[0] > b[0] || (a[0] === b[0] && a[1] >= b[1]), `${nom}: urgence puis création décroissantes`);
    }
    const appels = (await db.query('SELECT nom FROM public.appels_droits')).rows;
    if (user !== uid) assert.ok(appels.every(r => r.nom !== 'eligibilite'), `${nom}: guard inconnu/anonyme/supprimé conservé`);
    if (!user) assert.equal(appels.length, 0, `${nom}: anonyme sans lecture des droits privés`);
    cas.push({ nom, lignes: nouvelles.length, total_count: nouvelles[0]?.total_count ?? null });
  }
  for (const args of [
    ['sans_filtre', null, null, 500], ['paris', null, 'Paris', 50],
    ['profession', 'IDE', null, 50], ['ide_paris', 'IDE', 'Paris', 5],
    ['trim', ' IDE ', ' Paris ', 5], ['ville_casse_partielle', null, 'arI', 50],
    ['code_postal', null, '75', 50], ['filtres_blancs', '  ', '  ', 500],
    ['ville_absente', null, 'VilleIntrouvable', 0], ['profession_inconnue', 'INCONNUE', null, 0],
    ['profession_casse_exacte', 'ide', null, 0], ['wildcard_existant', null, '%', 500],
    ['soignant_eligible_et_exclusions', null, null, 446, uid],
    ['identite_inconnue_exclusions', null, null, 450, inconnu],
    ['soignant_supprime_exclusions', null, null, 450, supprime],
  ]) await comparer(...args);
  const tied = new Map();
  for (const m of manifeste.missions) {
    const row = byId.get(m.id), cle = `${!!row.est_urgente}:${row.cree_le}`;
    tied.set(cle, (tied.get(cle) || 0) + 1);
  }
  assert.ok([...tied.values()].some(n => n > 1), 'Fixtures avec ex aequo effectifs');

  // SELECT développé public, hors RPC/HTTP : même limite que la sonde staging.
  const selectPublic = source => source.match(/RETURN QUERY\s+([\s\S]*?);\s*END;/)[1]
    .replaceAll('p_profession', 'NULL::text').replaceAll('p_ville', 'NULL::text')
    .replaceAll('v_est_soignant', 'false').replaceAll('v_uid', 'NULL::uuid');
  const plan = async source => (await db.query(`EXPLAIN (ANALYZE, FORMAT JSON) ${selectPublic(source)}`)).rows[0]['QUERY PLAN'][0];
  const oldPlan = await plan(avant), newPlan = await plan(apres);
  const nodes = p => [p, ...(p.Plans || []).flatMap(nodes)];
  const window = nodes(newPlan.Plan).find(p => p['Node Type'] === 'WindowAgg');
  assert.ok(window, 'Le nouveau plan compte avec une fenêtre');
  assert.equal(window['Actual Loops'], 1);
  assert.equal(window['Actual Rows'], 500);
  const cout = p => ({ executionMs: p['Execution Time'], noeudsComptage: nodes(p.Plan)
    .filter(n => ['Aggregate', 'WindowAgg', 'CTE Scan'].includes(n['Node Type']))
    .map(n => ({ type: n['Node Type'], rows: n['Actual Rows'], loops: n['Actual Loops'] })) });
  await db.exec('ROLLBACK');
  assert.equal((await db.query("SELECT to_regclass('public.missions') AS table_restante")).rows[0].table_restante, null);
  console.log(JSON.stringify({ cas, definition_md5: meta.definition_md5, migrationAppliqueeDeuxFois: true, rollback: true, avant: cout(oldPlan), apres: cout(newPlan),
    limites: 'PGlite isolé et tables minimales ; droits appelés via sentinelles. Ordre des UUID dans un ex aequo non garanti. Aucun p95 HTTP, concurrence, pool ou service réel mesuré.' }, null, 2));
} finally {
  await db.close();
}
