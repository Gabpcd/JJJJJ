// Suppression du compte soignant avec pièces vérifiées (migration 20261127100000), sur une vraie base chargée avec
// supabase/schema/public.sql :
//   1. constat avant la migration : un soignant aux pièces VERIFIE qui supprime son compte par
//      fn_supprimer_compte_rate_limited (chemin de l'edge delete-account) est refusé (42501), rien n'est écrit ;
//   2. la migration, puis la suite SQL tests/security/suppression-compte-soignant-preuves.test.sql telle que le
//      staging l'exécute (BEGIN … ROLLBACK), puis aucun résidu.
// Moteurs : PostgreSQL 17 éphémère de la CI (job « Paiements — verrous PostgreSQL 17 éphémère », base dédiée
// suppression_preuves_banc) ou PGlite local (`JOLENE_PGLITE_MODULES=<dossier node_modules contenant @electric-sql/pglite>`).
// Aucun réseau, aucune donnée hors du dépôt. La preuve sur le schéma réel reste la suite sur le staging.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { charger, moteurPglite, moteurPsql, parametresRequis, RACINE } from '../../scripts/mobile/staging-lot5-banc-sql.mjs';

export const MIGRATION = 'supabase/migrations/20261127100000_suppression_compte_soignant_sans_revalidation.sql';
export const SUITE = 'tests/security/suppression-compte-soignant-preuves.test.sql';
const SOIGNANT = 'a5f1d0ff-0000-4000-8000-000000000001';

async function moteur() {
  if (process.env.JOLENE_PGLITE_MODULES) return moteurPglite(process.env.JOLENE_PGLITE_MODULES);
  assert.equal(process.env.JOLENE_PG_CONCURRENCY, 'CI_EPHEMERE', 'PostgreSQL éphémère de la CI seulement');
  assert.equal(process.env.PGHOST, '127.0.0.1');
  assert.equal(process.env.PGDATABASE, 'suppression_preuves_banc', 'base dédiée, jamais partagée avec les autres étapes');
  return { ...moteurPsql({ spawn: spawnSync }), fermer: async () => {} };
}

/** Soignant aux pièces vérifiées qui demande la suppression de son compte, en session utilisateur. */
export const CONSTAT = `
BEGIN;
INSERT INTO auth.users (id, instance_id, email, role, aud, raw_app_meta_data, email_confirmed_at)
VALUES ('${SOIGNANT}', '00000000-0000-0000-0000-000000000000', 'banc-suppression-preuves@example.invalid',
  'authenticated', 'authenticated', '{"role":"SOIGNANT"}', now());
INSERT INTO public.soignants (id, prenom, nom, email, profession, date_naissance)
VALUES ('${SOIGNANT}', 'Banc', 'Preuves', 'banc-suppression-preuves@example.invalid', 'IDE', date '1990-01-15');
INSERT INTO public.documents_soignants (soignant_id, type_document, s3_cle, nom_fichier, statut_verification, est_critique)
VALUES ('${SOIGNANT}', 'DIPLOME', 'tests/banc/${SOIGNANT}/diplome', 'diplome.pdf', 'VERIFIE', true);
SELECT set_config('request.jwt.claim.sub', '${SOIGNANT}', true);
SELECT set_config('request.jwt.claim.role', 'authenticated', true);
SELECT set_config('request.jwt.claims', '{"sub":"${SOIGNANT}","role":"authenticated"}', true);
SELECT public.fn_supprimer_compte_rate_limited() AS resultat;
COMMIT;`;

test('suppression du compte soignant : pièces vérifiées, anonymisation aboutie, protections intactes', { timeout: 900_000 }, async () => {
  const m = await moteur();
  const executer = m.executer;
  try {
    const { instructions, passe } = await charger(executer, { lot: m.lot, journal: console.log });
    assert.ok(passe > instructions * 0.98, `schéma chargé : ${passe}/${instructions}`);
    for (const instr of parametresRequis(RACINE, ['inscriptions_publiques_actives'])) await executer(instr);

    // 1. Constat sur le corps LIVE : refus 42501, transaction entière annulée.
    let refus = null;
    try {
      await executer(CONSTAT);
    } catch (e) {
      refus = e;
    }
    await executer('ROLLBACK;').catch(() => {});
    assert.equal(refus?.code, '42501', `constat non reproduit (${refus?.message ?? 'suppression acceptée'})`);
    assert.match(String(refus?.message), /Modification de preuve ou de validation interdite/);
    const [vide] = await executer(`SELECT (SELECT count(*)::int FROM auth.users WHERE id = '${SOIGNANT}') AS comptes;`);
    assert.deepEqual(vide, { comptes: 0 }, 'aucun effet de la suppression refusée');

    // 2. Migration, puis la suite du staging telle quelle, puis aucun résidu.
    await executer(readFileSync(join(RACINE, MIGRATION), 'utf8'));
    await executer(readFileSync(join(RACINE, SUITE), 'utf8'));
    const [residus] = await executer(`SELECT
      (SELECT count(*)::int FROM auth.users WHERE id::text LIKE 'a5f1d0%') AS comptes,
      (SELECT count(*)::int FROM public.soignants WHERE id::text LIKE 'a5f1d0%') AS soignants,
      (SELECT count(*)::int FROM public.documents_soignants WHERE soignant_id::text LIKE 'a5f1d0%') AS pieces;`);
    assert.deepEqual(residus, { comptes: 0, soignants: 0, pieces: 0 });
    console.log('Banc suppression soignant : constat reproduit avant migration, suite SQL complète après, aucun résidu.');
  } finally {
    await m.fermer?.();
  }
});
