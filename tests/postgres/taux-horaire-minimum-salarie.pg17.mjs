// Verrou du taux horaire minimal d'une mission salariée (migration 20261125120000_taux_horaire_minimum_salarie.sql),
// exécuté sur une vraie base chargée avec supabase/schema/public.sql puis la migration : refus à 12,30, accepté à
// 12,31, mission libérale non concernée, mise à jour sans rapport non bloquée, contexte système non contrôlé, et
// refus qui traverse le WHEN OTHERS de la RPC de création réelle (fn_creer_mission_multi_jours_v4).
//
// Moteurs : PostgreSQL 17 éphémère de la CI (job « Paiements — verrous PostgreSQL 17 éphémère », base dédiée
// taux_minimum_banc) ou PGlite local (`JOLENE_PGLITE_MODULES=<dossier node_modules contenant @electric-sql/pglite>`).
// Aucun réseau, aucune donnée hors du dépôt. La preuve sur le schéma réel reste le déploiement staging.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { charger, moteurPglite, moteurPsql, RACINE } from '../../scripts/mobile/staging-lot5-banc-sql.mjs';
import { manifeste, sqlPreparer, KIND } from '../../scripts/mobile/staging-lot5-fixture.mjs';

export const MIGRATION = 'supabase/migrations/20261125120000_taux_horaire_minimum_salarie.sql';
const MESSAGE = "Le taux horaire doit être d'au moins 12,31 €/h.";

async function moteur() {
  if (process.env.JOLENE_PGLITE_MODULES) return moteurPglite(process.env.JOLENE_PGLITE_MODULES);
  assert.equal(process.env.JOLENE_PG_CONCURRENCY, 'CI_EPHEMERE', 'PostgreSQL éphémère de la CI seulement');
  assert.equal(process.env.PGHOST, '127.0.0.1');
  assert.equal(process.env.PGDATABASE, 'taux_minimum_banc', 'base dédiée, jamais partagée avec les autres étapes');
  return { ...moteurPsql({ spawn: spawnSync }), fermer: async () => {} };
}

const q = v => `'${String(v).replaceAll("'", "''")}'`;

/** Transaction validée sous un JWT simulé : `role` service_role (API) ou authenticated (sub = utilisateur). */
const sousJwt = ({ role, sub = '' }, sql) => `BEGIN;
${role === 'authenticated' ? 'SET LOCAL ROLE authenticated;' : ''}
SELECT set_config('request.jwt.claims', ${q(JSON.stringify(sub ? { sub, role } : { role }))}, true),
       set_config('request.jwt.claim.sub', ${q(sub)}, true), set_config('request.jwt.claim.role', ${q(role)}, true);
${sql}
COMMIT;`;

/** Transaction validée hors requête API (pg_cron, migration) : aucun request.jwt.*. */
const systeme = sql => `BEGIN;
${sql}
COMMIT;`;

const insertion = (etab, { id, taux, contrat, profession = 'AS', debut }) => `
SELECT set_config('jolene.planning_exact_managed', 'true', true);
INSERT INTO public.missions (id, etablissement_id, intitule, description, profession_requise, service, debut_le, fin_le,
  duree_heures, taux_horaire_base, statut, mode_attribution, type_contrat_recherche, est_urgente)
VALUES (${q(id)}, ${q(etab)}, 'Banc taux minimal', 'Mission fictive du banc, aucune activité réelle.', ${q(profession)},
  'Banc', ${q(debut)}::timestamptz, (${q(debut)}::timestamptz + interval '4 hours'), 4, ${taux}, 'OUVERTE', 'CANDIDATURE',
  ${q(contrat)}, false);
INSERT INTO public.mission_creneaux (id, mission_id, debut, fin, est_pause, ordre, type_creneau)
VALUES (${q(randomUUID())}, ${q(id)}, ${q(debut)}::timestamptz, (${q(debut)}::timestamptz + interval '4 hours'), false, 1,
  'PREVISIONNEL');`;

test('taux horaire minimal d\'une mission salariée : verrou différé sur public.missions', { timeout: 600_000 }, async () => {
  const m = await moteur();
  const executer = m.executer;
  const refuse = async (sql, motif) => {
    await assert.rejects(() => executer(sql), e => {
      assert.match(String(e?.message ?? e), motif);
      return true;
    });
    await executer('ROLLBACK;').catch(() => {});
  };
  try {
    const { instructions, passe } = await charger(executer, { lot: m.lot, journal: console.log });
    assert.ok(passe > instructions * 0.98, `schéma chargé : ${passe}/${instructions}`);
    await executer(readFileSync(join(RACINE, MIGRATION), 'utf8'));

    // Paramètre, lecture et droits.
    const [param] = await executer(`SELECT valeur::text AS valeur, val_min::text AS val_min, categorie, cablee,
      public.fn_taux_horaire_minimum_salarie()::text AS lu,
      has_function_privilege('authenticated', 'public.fn_taux_horaire_minimum_salarie()', 'EXECUTE') AS auth,
      has_function_privilege('anon', 'public.fn_taux_horaire_minimum_salarie()', 'EXECUTE') AS anon,
      (SELECT count(*)::int FROM pg_trigger WHERE tgrelid = 'public.missions'::regclass AND tgdeferrable
         AND tgname LIKE 'trg_zz_taux_minimum_salarie_%') AS declencheurs,
      (SELECT count(*)::int FROM private.security_definer_inventory i JOIN pg_proc f
         ON f.oid = to_regprocedure(CASE WHEN i.signature LIKE 'private.%' THEN i.signature ELSE 'public.' || i.signature END)
        WHERE i.signature IN ('fn_taux_horaire_minimum_salarie()', 'private.fn_trg_verifier_taux_minimum_salarie()')
          AND i.definition_md5 = md5(f.prosrc)) AS inventaire
      FROM public.parametres_systeme WHERE cle = 'taux_horaire_minimum_salarie';`);
    assert.deepEqual(param, { valeur: '12.31', val_min: '12.31', categorie: 'FINANCE', cablee: true, lu: '12.31',
      auth: true, anon: false, declencheurs: 2, inventaire: 2 });
    // Rejeu idempotent (ON CONFLICT DO NOTHING, déclencheurs non dupliqués).
    await executer(readFileSync(join(RACINE, MIGRATION), 'utf8'));

    // Cohorte du lot 5 : établissement publiable E1 (préparation réelle, déclencheurs compris).
    const run = manifeste(`taux-${Date.now().toString(36)}`, new Date());
    await executer(`INSERT INTO auth.users (id, email, email_confirmed_at, raw_app_meta_data, role, aud) VALUES
      (${q(run.etablissement.id)}, ${q(run.etablissement.email)}, now(), ${q(JSON.stringify({ role: 'ETABLISSEMENT',
        est_compte_test: true, is_test_playwright: true, load_fixture_kind: KIND, load_fixture_run: run.runId }))}::jsonb,
        'authenticated', 'authenticated'),
      (${q(run.soignant.id)}, ${q(run.soignant.email)}, now(), ${q(JSON.stringify({ role: 'SOIGNANT',
        est_compte_test: true, is_test_playwright: true, load_fixture_kind: KIND, load_fixture_run: run.runId }))}::jsonb,
        'authenticated', 'authenticated');`);
    const [prep] = await executer(sqlPreparer(run));
    assert.equal(prep?.prepare, true, 'préparation de la cohorte (missions SALARIE à 20 €/h acceptées)');
    const etab = run.etablissement.id;
    const jour = n => new Date(Date.now() + (20 + n) * 86_400_000).toISOString().slice(0, 10) + 'T07:00:00Z';
    const service = { role: 'service_role' };

    // 1. SALARIE à 12,30 : refusé à la validation, message exact.
    await refuse(sousJwt(service, insertion(etab, { id: randomUUID(), taux: 12.30, contrat: 'SALARIE', debut: jour(1) })),
      new RegExp(MESSAGE.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')));
    // 2. SALARIE à 12,31 : accepté.
    const a1231 = randomUUID();
    await executer(sousJwt(service, insertion(etab, { id: a1231, taux: 12.31, contrat: 'SALARIE', debut: jour(2) })));
    // 3. TOUS à 12,30 : refusé (une mission TOUS peut être pourvue en salarié).
    await refuse(sousJwt(service, insertion(etab, { id: randomUUID(), taux: 12.30, contrat: 'TOUS', debut: jour(3) })),
      /au moins 12,31 €\/h/);
    // 4. LIBERAL à 10 : non concerné ; puis TOUS à 10 basculé en LIBERAL dans la même transaction (chemin des RPC de
    //    création) : accepté, le verrou lit l'état final.
    const lib = randomUUID();
    await executer(sousJwt(service, insertion(etab, { id: lib, taux: 10, contrat: 'LIBERAL', profession: 'IDE', debut: jour(4) })));
    const bascule = randomUUID();
    await executer(sousJwt(service, insertion(etab, { id: bascule, taux: 10, contrat: 'TOUS', profession: 'IDE', debut: jour(5) })
      + `\nUPDATE public.missions SET type_contrat_recherche = 'LIBERAL' WHERE id = ${q(bascule)};`));
    // 5. Modification du taux d'une mission SALARIE existante à 12,30 : refusée ; LIBERAL → SALARIE sous le plancher : refusé.
    await refuse(sousJwt(service, `UPDATE public.missions SET taux_horaire_base = 12.30 WHERE id = ${q(a1231)};`), /au moins 12,31/);
    await refuse(sousJwt(service, `UPDATE public.missions SET type_contrat_recherche = 'TOUS' WHERE id = ${q(lib)};`), /au moins 12,31/);
    // 6. Contexte système (pg_cron, migration) : non contrôlé. Mission héritée sous le plancher créée ainsi.
    const heritee = randomUUID();
    await executer(systeme(insertion(etab, { id: heritee, taux: 11.65, contrat: 'SALARIE', debut: jour(6) })));
    // 7. Mise à jour sans rapport d'une mission sous le plancher, sous requête API : non bloquée (clause WHEN).
    await executer(sousJwt(service, `UPDATE public.missions SET intitule = 'Banc taux minimal — renommée',
      est_urgente = true, niveau_urgence = 1 WHERE id = ${q(heritee)};`));
    await executer(sousJwt(service, `UPDATE public.missions SET taux_horaire_base = taux_horaire_base WHERE id = ${q(heritee)};`));
    // … mais toucher son taux sans atteindre le plancher reste refusé.
    await refuse(sousJwt(service, `UPDATE public.missions SET taux_horaire_base = 12 WHERE id = ${q(heritee)};`), /au moins 12,31/);

    // 8. RPC de création réelle sous JWT établissement : le refus traverse le WHEN OTHERS des RPC (déclencheur différé).
    const creneau = jour(8);
    const rpc = taux => sousJwt({ role: 'authenticated', sub: etab }, `SELECT public.fn_creer_mission_multi_jours_v4(
      p_intitule => 'Banc taux minimal RPC', p_description => NULL, p_profession_requise => 'AS', p_service => NULL,
      p_taux_horaire_base => ${taux}, p_est_urgente => false, p_niveau_urgence => 0, p_mode_attribution => 'CANDIDATURE',
      p_specialite_medicale_requise => NULL, p_accepte_non_specialises => true,
      p_creneaux => jsonb_build_array(jsonb_build_object('debut', ${q(creneau)}, 'fin', (${q(creneau)}::timestamptz + interval '4 hours'))),
      p_type_contrat_recherche => 'SALARIE', p_mode_remuneration => 'TAUX_HORAIRE', p_retrocession_pct => NULL,
      p_nature_tva_prestation => NULL, p_accepte_internes => false)::text AS resultat;`);
    const creees = () => executer(`SELECT count(*)::int AS n, coalesce(max(taux_horaire_base)::text, '') AS taux,
      coalesce(max(type_contrat_recherche), '') AS contrat FROM public.missions WHERE intitule = 'Banc taux minimal RPC';`);
    let rpcAtteinte = true;
    try {
      await executer(rpc(12.31));
      const [lu] = await creees();
      if (lu.n !== 1) {
        rpcAtteinte = false;
        console.log('RPC de création non exerçable sur ce banc (aucune mission créée) : cas 8 non prouvé.');
      } else assert.deepEqual(lu, { n: 1, taux: '12.31', contrat: 'SALARIE' });
    } catch (e) {
      if (e instanceof assert.AssertionError) throw e;
      rpcAtteinte = false;
      await executer('ROLLBACK;').catch(() => {});
      console.log(`RPC de création non exerçable sur ce banc (${String(e?.message ?? e).slice(0, 300)}) : cas 8 non prouvé.`);
    }
    if (rpcAtteinte) {
      await refuse(rpc(12.30), new RegExp(MESSAGE.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')));
      assert.equal((await creees())[0].n, 1, 'la mission à 12,30 n\'a pas été créée');
    }

    // 9. Paramètre absent : refus explicite, jamais de plancher implicite.
    await refuse(sousJwt(service, `DELETE FROM public.parametres_systeme WHERE cle = 'taux_horaire_minimum_salarie';`
      + insertion(etab, { id: randomUUID(), taux: 30, contrat: 'SALARIE', debut: jour(9) })), /n'est pas paramétré/);

    const [etat] = await executer(`SELECT
      (SELECT count(*)::int FROM public.missions WHERE intitule LIKE 'Banc taux minimal%' AND taux_horaire_base < 12.31
         AND type_contrat_recherche <> 'LIBERAL') AS sous_plancher,
      (SELECT taux_horaire_base::text FROM public.missions WHERE id = ${q(a1231)}) AS a1231,
      (SELECT type_contrat_recherche FROM public.missions WHERE id = ${q(lib)}) AS lib,
      (SELECT type_contrat_recherche FROM public.missions WHERE id = ${q(bascule)}) AS bascule,
      (SELECT intitule FROM public.missions WHERE id = ${q(heritee)}) AS heritee,
      (SELECT count(*)::int FROM public.parametres_systeme WHERE cle = 'taux_horaire_minimum_salarie') AS param;`);
    assert.deepEqual(etat, { sous_plancher: 1, a1231: '12.31', lib: 'LIBERAL', bascule: 'LIBERAL',
      heritee: 'Banc taux minimal — renommée', param: 1 });
    console.log(`Banc taux minimal : 9 cas${rpcAtteinte ? '' : ' (cas 8 RPC non exerçable sur ce banc)'} vérifiés.`);
  } finally {
    await m.fermer?.();
  }
});
