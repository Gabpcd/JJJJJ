// Missions de revue App Store et cloisonnement des envois par cohorte de test (migrations 20261126100000 et
// 20261126100100), sur une vraie base chargée avec supabase/schema/public.sql puis les deux migrations :
//   1. désignation par l'e-mail de rôle à la migration : un établissement réel la fait échouer (rien n'est écrit),
//      un établissement de test reçoit ses 3 missions dès la migration (premier remplissage) ;
//   2. la suite SQL tests/security/revue-store-missions-isolees.test.sql telle que le staging l'exécute (test-garde
//      des émetteurs, refus d'un établissement réel, stock, idempotence, retrait, nettoyage, huit chemins d'envoi :
//      soignant de test notifié, soignant réel jamais, aucun appel HTTP en file qui le désigne), puis aucun résidu.
//
// Le banc enregistre les appels net.http_post dans net.http_request_queue (corps en bytea, comme pg_net) et pose un
// jeton de service fictif dans vault : les branches push et e-mail s'exécutent et sont observées.
// Moteurs : PostgreSQL 17 éphémère de la CI (job « Paiements — verrous PostgreSQL 17 éphémère », base dédiée
// revue_store_banc) ou PGlite local (`JOLENE_PGLITE_MODULES=<dossier node_modules contenant @electric-sql/pglite>`).
// Aucun réseau, aucune donnée hors du dépôt. La preuve sur le schéma réel reste la suite sur le staging.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { charger, moteurPglite, moteurPsql, parametresRequis, RACINE } from '../../scripts/mobile/staging-lot5-banc-sql.mjs';

export const MIGRATIONS = [
  'supabase/migrations/20261126100000_isoler_envois_missions_cohorte_test.sql',
  'supabase/migrations/20261126100100_missions_revue_store.sql',
];
export const SUITE = 'tests/security/revue-store-missions-isolees.test.sql';
const ETAB_REVUE = 'a5f0e0ff-0000-4000-8000-000000000001';

async function moteur() {
  if (process.env.JOLENE_PGLITE_MODULES) return moteurPglite(process.env.JOLENE_PGLITE_MODULES);
  assert.equal(process.env.JOLENE_PG_CONCURRENCY, 'CI_EPHEMERE', 'PostgreSQL éphémère de la CI seulement');
  assert.equal(process.env.PGHOST, '127.0.0.1');
  assert.equal(process.env.PGDATABASE, 'revue_store_banc', 'base dédiée, jamais partagée avec les autres étapes');
  return { ...moteurPsql({ spawn: spawnSync }), fermer: async () => {} };
}

/** File pg_net observable : mêmes colonnes utiles que net.http_request_queue (corps bytea). */
const FILE_HTTP = `
CREATE TABLE IF NOT EXISTS net.http_request_queue (id bigserial PRIMARY KEY, method text, url text, headers jsonb,
  body bytea, timeout_milliseconds integer);
CREATE OR REPLACE FUNCTION net.http_post(url text, body jsonb DEFAULT '{}'::jsonb, params jsonb DEFAULT '{}'::jsonb,
  headers jsonb DEFAULT '{}'::jsonb, timeout_milliseconds integer DEFAULT 5000) RETURNS bigint LANGUAGE sql AS $f$
  INSERT INTO net.http_request_queue (method, url, headers, body, timeout_milliseconds)
  VALUES ('POST', url, headers, convert_to(body::text, 'UTF8'), timeout_milliseconds) RETURNING id $f$;
INSERT INTO vault.secrets (name, secret) SELECT 'service_role_key', 'banc-jeton-fictif'
 WHERE NOT EXISTS (SELECT 1 FROM vault.secrets WHERE name = 'service_role_key');`;

/** Établissement joignable par l'e-mail de rôle de la migration, réel ou de test selon `test`. */
const etablissementRevue = estTest => `
UPDATE public.parametres_systeme SET valeur = 1 WHERE cle = 'inscriptions_publiques_actives';
INSERT INTO auth.users (id, instance_id, email, role, aud, raw_app_meta_data, email_confirmed_at)
VALUES ('${ETAB_REVUE}', '00000000-0000-0000-0000-000000000000', 'etab@jolene.app', 'authenticated', 'authenticated',
  '${JSON.stringify(estTest ? { role: 'ADMIN_ETABLISSEMENT', est_compte_test: true } : { role: 'ADMIN_ETABLISSEMENT' })}', now());
INSERT INTO public.etablissements (id, nom, siret, type, adresse_rue, adresse_ville, adresse_code_postal, adresse_lat,
  adresse_lng, email_contact, est_compte_test)
VALUES ('${ETAB_REVUE}', 'Banc établissement de revue', '99178000000199', 'CLINIQUE_PRIVEE', '3 rue du Banc', 'Paris', '75002',
  48.8686, 2.3417, 'banc-revue@example.invalid', ${estTest});
UPDATE public.parametres_systeme SET valeur = 0 WHERE cle = 'inscriptions_publiques_actives';`;

test('missions de revue App Store : stock garanti, cohorte de test seule destinataire', { timeout: 600_000 }, async () => {
  const m = await moteur();
  const executer = m.executer;
  try {
    const { instructions, passe } = await charger(executer, { lot: m.lot, journal: console.log });
    assert.ok(passe > instructions * 0.98, `schéma chargé : ${passe}/${instructions}`);
    // Paramètre du staging (0 : cohorte test forcée) relu dans sa migration, puis file HTTP et jeton fictifs.
    for (const instr of parametresRequis(RACINE, ['inscriptions_publiques_actives'])) await executer(instr);
    await executer(FILE_HTTP);
    await executer(readFileSync(join(RACINE, MIGRATIONS[0]), 'utf8'));

    // 1a. Établissement réel à l'e-mail de rôle : la migration échoue en entier, rien n'est écrit.
    let refus = null;
    try {
      await executer(`BEGIN;\n${etablissementRevue(false)}\n${readFileSync(join(RACINE, MIGRATIONS[1]), 'utf8')}\nCOMMIT;`);
    } catch (e) {
      refus = String(e?.message ?? e);
    }
    await executer('ROLLBACK;').catch(() => {});
    assert.match(refus ?? '', /n'est pas un compte de test/, `migration non refusée pour un établissement réel (${refus})`);
    const [vide] = await executer(`SELECT (SELECT count(*)::int FROM public.etablissements WHERE id = '${ETAB_REVUE}') AS etab,
      strpos((SELECT pg_get_constraintdef(c.oid) FROM pg_constraint c WHERE c.conname = 'missions_mission_source_check'),
        'REVUE_STORE') > 0 AS migree;`);
    assert.deepEqual(vide, { etab: 0, migree: false }, 'aucun effet de la migration refusée');

    // 1b. Établissement de test à l'e-mail de rôle : désigné et rempli par la migration elle-même.
    await executer(`BEGIN;\n${etablissementRevue(true)}\n${readFileSync(join(RACINE, MIGRATIONS[1]), 'utf8')}\nCOMMIT;`);
    const [stock] = await executer(`SELECT
      (SELECT count(*)::int FROM private.etablissements_revue_store WHERE etablissement_id = '${ETAB_REVUE}') AS designe,
      (SELECT count(*)::int FROM public.missions WHERE etablissement_id = '${ETAB_REVUE}' AND statut = 'OUVERTE'
         AND mission_source = 'REVUE_STORE' AND profession_requise = 'IDE' AND type_contrat_recherche = 'TOUS'
         AND (debut_le AT TIME ZONE 'Europe/Paris')::date BETWEEN (now() AT TIME ZONE 'Europe/Paris')::date + 7
             AND (now() AT TIME ZONE 'Europe/Paris')::date + 21) AS ouvertes,
      (SELECT count(*)::int FROM net.http_request_queue) AS http,
      public.fn_cleanup_missions_test() AS purgees_maintenant;`);
    assert.deepEqual(stock, { designe: 1, ouvertes: 3, http: 0, purgees_maintenant: 0 });

    // 2. La suite du staging, telle quelle (BEGIN … ROLLBACK), puis aucun résidu.
    await executer(readFileSync(join(RACINE, SUITE), 'utf8'));
    const [residus] = await executer(`SELECT
      (SELECT count(*)::int FROM auth.users WHERE id::text LIKE 'a5f0e00%') AS comptes,
      (SELECT count(*)::int FROM public.missions WHERE etablissement_id::text LIKE 'a5f0e00%') AS missions,
      (SELECT count(*)::int FROM private.etablissements_revue_store) AS designations,
      (SELECT count(*)::int FROM public.missions WHERE etablissement_id = '${ETAB_REVUE}' AND statut = 'OUVERTE') AS stock;`);
    assert.deepEqual(residus, { comptes: 0, missions: 0, designations: 1, stock: 3 });
    console.log('Banc revue store : refus réel à la migration, premier remplissage, suite SQL complète, aucun résidu.');
  } finally {
    await m.fermer?.();
  }
});
