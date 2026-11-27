// Missions de revue des stores et cloisonnement des missions par cohorte de test (migrations 20261126100000 et
// 20261126100100), sur une vraie base chargée avec supabase/schema/public.sql puis les deux migrations :
//   1. désignation par les e-mails publics de la migration : un établissement réel, puis un soignant réel, la font
//      échouer en entier (rien n'est écrit) ; deux comptes de test sont désignés et l'établissement reçoit ses
//      3 missions dès la migration (premier remplissage), sans aucun envoi ;
//   2. la suite SQL tests/security/revue-store-missions-isolees.test.sql telle que le staging l'exécute (test-gardes
//      des émetteurs et des lecteurs, refus des comptes réels, stock, idempotence, retrait, nettoyage, diffusion
//      nulle, visibilité RLS, suppressions de comptes), puis aucun résidu.
//
// Le banc enregistre les appels net.http_post dans net.http_request_queue (corps en bytea, comme pg_net) et pose un
// jeton de service fictif dans vault : les branches push et e-mail s'exécutent et sont observées.
// Schéma chargé : le dump d'une révision épinglée antérieure aux migrations (tests/postgres/schema-avant-migration.mjs),
// jamais le dump courant, qui contient les corps APRÈS migration dès la re-baseline suivant le déploiement (#1204) ;
// un test sans base vérifie que le dump courant est, pour les fonctions redéfinies, tout AVANT ou tout APRÈS.
// Le chargeur du banc installe la dernière définition de chaque fonction private de TOUTES les migrations, donc
// déjà celles des migrations candidates : les définitions antérieures (état LIVE) sont rejouées avant d'appliquer
// les migrations, dont le préflight vérifie l'empreinte LIVE.
// Moteurs : PostgreSQL 17 éphémère de la CI (job « Paiements — verrous PostgreSQL 17 éphémère », base dédiée
// revue_store_banc) ou PGlite local (`JOLENE_PGLITE_MODULES=<dossier node_modules contenant @electric-sql/pglite>`).
// Aucun réseau, aucune donnée hors du dépôt. La preuve sur le schéma réel reste la suite sur le staging.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { charger, decouper, moteurPglite, moteurPsql, parametresRequis, RACINE } from '../../scripts/mobile/staging-lot5-banc-sql.mjs';
import { DUMP_AVANT_REVUE_ET_SUPPRESSION, dumpEpingle, etatDuDumpCourant, racineAvant } from './schema-avant-migration.mjs';

export const MIGRATIONS = [
  'supabase/migrations/20261126100000_cloisonner_missions_cohorte_et_revue.sql',
  'supabase/migrations/20261126100100_missions_revue_store.sql',
];
export const SUITE = 'tests/security/revue-store-missions-isolees.test.sql';
const ETAB_REVUE = 'a5f0e0ff-0000-4000-8000-000000000001';
const SOIGNANT_REVUE = 'a5f0e0ff-0000-4000-8000-000000000002';
const NETTOYAGE_LIVE = '5a25967b3550051aedbd5cd02dec44e6';

async function moteur() {
  if (process.env.JOLENE_PGLITE_MODULES) return moteurPglite(process.env.JOLENE_PGLITE_MODULES);
  assert.equal(process.env.JOLENE_PG_CONCURRENCY, 'CI_EPHEMERE', 'PostgreSQL éphémère de la CI seulement');
  assert.equal(process.env.PGHOST, '127.0.0.1');
  assert.equal(process.env.PGDATABASE, 'revue_store_banc', 'base dédiée, jamais partagée avec les autres étapes');
  return { ...moteurPsql({ spawn: spawnSync }), fermer: async () => {} };
}

/** Dernière définition, antérieure aux migrations candidates, des fonctions private qu'elles redéfinissent. */
export function definitionsPriveesAnterieures() {
  const dossier = join(RACINE, 'supabase/migrations');
  const premiere = MIGRATIONS[0].split('/').pop();
  const noms = new Set(MIGRATIONS.flatMap(f => [...readFileSync(join(RACINE, f), 'utf8')
    .matchAll(/CREATE OR REPLACE FUNCTION private\.([a-z0-9_]+)\(/g)].map(x => x[1])));
  const derniere = new Map();
  for (const f of readdirSync(dossier).filter(f => f.endsWith('.sql') && f < premiere).sort()) {
    for (const instruction of decouper(readFileSync(join(dossier, f), 'utf8'))) {
      const texte = instruction.replace(/^(?:\s*--[^\n]*\n)*\s*/, '');
      const x = /^CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+private\.([a-z0-9_]+)\s*\(/i.exec(texte);
      if (x && noms.has(x[1])) derniere.set(x[1], texte.replace(/^CREATE\s+FUNCTION/i, 'CREATE OR REPLACE FUNCTION'));
    }
  }
  return derniere;
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

/**
 * Référentiel documentaire IDE (données de référence de la production, relues le 26/11/2026). Le staging en a un :
 * sans lui, la suite n'insère aucune pièce aux fixtures et les chemins qui touchent des pièces vérifiées (exigence
 * documentaire, anonymisation d'un profil) ne sont pas exercés par le banc (job SQL du 27/11/2026).
 */
export const REFERENTIEL_DOCUMENTS = `
INSERT INTO public.documents_requis_par_profession (id, profession, type_document, est_critique, a_expiration,
  duree_validite_mois, type_exercice_requis)
SELECT gen_random_uuid(), 'IDE', r.type_document::public.type_document, r.est_critique, r.a_expiration, r.duree, r.exercice
  FROM (VALUES ('ATTESTATION_URSSAF', true, true, 6, 'LIBERAL_ONLY'), ('AUTORISATION_EXERCICE', false, false, NULL, 'TOUS'),
    ('CARTE_IDENTITE', true, true, NULL, 'TOUS'), ('DIPLOME', true, false, NULL, 'TOUS'),
    ('RCP_ASSURANCE', true, true, 12, 'LIBERAL_ONLY'), ('RIB', true, false, NULL, 'TOUS'), ('RPPS_ADELI', true, false, NULL, 'TOUS')
  ) AS r(type_document, est_critique, a_expiration, duree, exercice)
 WHERE NOT EXISTS (SELECT 1 FROM public.documents_requis_par_profession WHERE profession = 'IDE');`;

/** Comptes joignables par les e-mails publics de la migration, réels ou de test. */
const comptesRevue = ({ etabTest, soignantTest }) => `
UPDATE public.parametres_systeme SET valeur = 1 WHERE cle = 'inscriptions_publiques_actives';
INSERT INTO auth.users (id, instance_id, email, role, aud, raw_app_meta_data, email_confirmed_at)
VALUES ('${ETAB_REVUE}', '00000000-0000-0000-0000-000000000000', 'etab@jolene.app', 'authenticated', 'authenticated',
  '${JSON.stringify(etabTest ? { role: 'ADMIN_ETABLISSEMENT', est_compte_test: true } : { role: 'ADMIN_ETABLISSEMENT' })}', now()),
  ('${SOIGNANT_REVUE}', '00000000-0000-0000-0000-000000000000', 'marie.lefevre@jolene-demo.dev', 'authenticated', 'authenticated',
  '${JSON.stringify(soignantTest ? { role: 'SOIGNANT', est_compte_test: true } : { role: 'SOIGNANT' })}', now());
INSERT INTO public.etablissements (id, nom, siret, type, adresse_rue, adresse_ville, adresse_code_postal, adresse_lat,
  adresse_lng, email_contact, est_compte_test)
VALUES ('${ETAB_REVUE}', 'Banc établissement de revue', '99178000000199', 'CLINIQUE_PRIVEE', '3 rue du Banc', 'Paris', '75002',
  48.8686, 2.3417, 'banc-revue@example.invalid', ${etabTest});
INSERT INTO public.soignants (id, prenom, nom, email, profession, est_compte_test)
VALUES ('${SOIGNANT_REVUE}', 'Banc', 'Revue', 'banc-soignant-revue@example.invalid', 'IDE', ${soignantTest});
UPDATE public.parametres_systeme SET valeur = 0 WHERE cle = 'inscriptions_publiques_actives';`;

/** Fonctions public redéfinies par les deux migrations : corps LIVE d'avant (préflight) et corps installé (post-condition). */
export const REDEFINITIONS_PUBLIQUES = [
  ['fn_soignant_eligible_mission', 'f10aeb9ced376cae6ef5a4a863a2cf6b', '6db2aebbc7342bb721108b66688b62bc'],
  ['fn_resoudre_contrat_mission', 'e39388880b3e026e8b81b0d94d0de777', '91bf0908b53aaca7b5b4ea2cefaf4110'],
  ['fn_pool_urgence_etablissement', '178dbb066ceb8720c38c30ab0fb74f7d', 'a4308cb167e6c0d895efda615c5da297'],
  ['fn_notifier_favoris_expirants', 'd44ae13e1e450ab85942c1863d107b7e', '8d3fa4597fb5835e8658bc4f31a3730c'],
  ['fn_relancer_missions_sans_candidat', '49ae7d9e38110b4009e70af2d3a77c9f', '6d9af12f3446ccdabe4f840d93debfc7'],
  ['fn_mes_favoris_etablissements', '26c080a4e6e197018a5b27195981473a', '100f3988e20a0446673267ce804bb3b0'],
  ['fn_admin_generer_posts', 'fd4a9e677fa1cdae1c0a75a061b789c4', 'f822983bb47bd93f1d984cdcb41a4b15'],
  ['fn_cleanup_missions_test', '5a25967b3550051aedbd5cd02dec44e6', 'ee0c90c2fa777643b8261956ef7e3d6f'],
  ['fn_supprimer_mon_compte_etablissement', 'a43978aee09ef1ae4a157dbee9911b2f', 'a5dd6e6858e7ad641f4bd353753f3223'],
].map(([nom, avant, apres]) => ({ schema: 'public', nom, avant, apres }));

test('dump épinglé tout AVANT les migrations ; dump courant tout AVANT ou tout APRÈS (sans base)', () => {
  const avant = racineAvant(DUMP_AVANT_REVUE_ET_SUPPRESSION);
  try {
    assert.equal(etatDuDumpCourant(REDEFINITIONS_PUBLIQUES, readFileSync(join(avant.racine, 'supabase/schema/public.sql'), 'utf8')).etat, 'AVANT');
  } finally {
    avant.nettoyer();
  }
  const courant = etatDuDumpCourant(REDEFINITIONS_PUBLIQUES);
  assert.ok(['AVANT', 'APRES'].includes(courant.etat), `dump courant incohérent avec les migrations : ${JSON.stringify(courant.fonctions)}`);
  console.log(`Dump courant : corps ${courant.etat === 'APRES' ? 'post-condition (re-baseline faite)' : 'LIVE d’avant (re-baseline à venir)'}.`);
  // Le dump épinglé n'est accepté que vérifié : commit présent, blob attendu, SHA-256 attendu.
  const epingle = DUMP_AVANT_REVUE_ET_SUPPRESSION;
  assert.throws(() => dumpEpingle(epingle, () => { throw new Error('absent'); }), /--depth=1 origin 739f3fcb4/);
  assert.throws(() => dumpEpingle(epingle, args => (args[0] === 'rev-parse' ? `${'0'.repeat(40)}\n` : '')), /blob/);
  assert.throws(() => dumpEpingle(epingle, args => (args[0] === 'rev-parse' ? `${epingle.blob}\n` : 'dump altéré')), /SHA-256/);
});

test('missions de revue des stores : stock garanti, diffusées à personne, lues par le seul soignant de revue', { timeout: 900_000 }, async () => {
  const m = await moteur();
  const executer = m.executer;
  const avant = racineAvant(DUMP_AVANT_REVUE_ET_SUPPRESSION);
  try {
    const { instructions, passe } = await charger(executer, { racine: avant.racine, lot: m.lot, journal: console.log });
    assert.ok(passe > instructions * 0.98, `schéma chargé : ${passe}/${instructions}`);
    // Paramètre du staging (0 : cohorte test forcée) relu dans sa migration, puis file HTTP et jeton fictifs.
    for (const instr of parametresRequis(RACINE, ['inscriptions_publiques_actives'])) await executer(instr);
    await executer(FILE_HTTP);
    await executer(REFERENTIEL_DOCUMENTS);
    const [referentiel] = await executer(`SELECT count(*)::int AS n FROM public.documents_requis_par_profession
      WHERE profession = 'IDE' AND est_critique AND type_exercice_requis IN ('TOUS', 'SALARIE_ONLY') AND type_document <> 'RPPS_ADELI';`);
    assert.equal(referentiel.n, 3, 'référentiel documentaire IDE chargé : la suite insère des pièces vérifiées');
    const anterieures = definitionsPriveesAnterieures();
    assert.ok(anterieures.has('fn_soignant_visible_pool_etablissement') && anterieures.has('fn_resultats_filtre_missions'),
      'définitions LIVE des fonctions private redéfinies introuvables');
    for (const sql of anterieures.values()) await executer(sql);
    await executer(readFileSync(join(RACINE, MIGRATIONS[0]), 'utf8'));
    const seconde = readFileSync(join(RACINE, MIGRATIONS[1]), 'utf8');

    // 1a. Établissement réel, puis soignant réel, aux e-mails de la migration : elle échoue en entier.
    for (const [comptes, motif] of [
      [{ etabTest: false, soignantTest: true }, /l'établissement .* n'est pas un compte de test/],
      [{ etabTest: true, soignantTest: false }, /le soignant .* n'est pas un compte de test/],
    ]) {
      let refus = null;
      try {
        await executer(`BEGIN;\n${comptesRevue(comptes)}\n${seconde}\nCOMMIT;`);
      } catch (e) {
        refus = String(e?.message ?? e);
      }
      await executer('ROLLBACK;').catch(() => {});
      assert.match(refus ?? '', motif, `migration non refusée (${JSON.stringify(comptes)} : ${refus})`);
      const [vide] = await executer(`SELECT
        (SELECT count(*)::int FROM auth.users WHERE id IN ('${ETAB_REVUE}', '${SOIGNANT_REVUE}')) AS comptes,
        (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'public.fn_cleanup_missions_test()'::regprocedure) AS nettoyage;`);
      assert.deepEqual(vide, { comptes: 0, nettoyage: NETTOYAGE_LIVE }, 'aucun effet de la migration refusée');
    }

    // 1b. Comptes de test : désignés et stock rempli par la migration elle-même, sans aucun envoi.
    await executer(`BEGIN;\n${comptesRevue({ etabTest: true, soignantTest: true })}\n${seconde}\nCOMMIT;`);
    const [stock] = await executer(`SELECT
      (SELECT count(*)::int FROM private.etablissements_revue_store WHERE etablissement_id = '${ETAB_REVUE}') AS etab_designe,
      (SELECT count(*)::int FROM private.soignants_revue_store WHERE soignant_id = '${SOIGNANT_REVUE}') AS soignant_designe,
      (SELECT count(*)::int FROM public.missions WHERE etablissement_id = '${ETAB_REVUE}' AND statut = 'OUVERTE'
         AND mission_source = 'REVUE_STORE' AND profession_requise = 'IDE' AND type_contrat_recherche = 'TOUS'
         AND duree_heures = 6
         AND (debut_le AT TIME ZONE 'Europe/Paris')::date BETWEEN (now() AT TIME ZONE 'Europe/Paris')::date + 7
             AND (now() AT TIME ZONE 'Europe/Paris')::date + 21) AS ouvertes,
      (SELECT count(*)::int FROM public.notifications) AS notifications,
      (SELECT count(*)::int FROM net.http_request_queue) AS http,
      public.fn_cleanup_missions_test() AS purgees_maintenant;`);
    assert.deepEqual(stock, { etab_designe: 1, soignant_designe: 1, ouvertes: 3, notifications: 0, http: 0, purgees_maintenant: 0 });

    // 2. La suite du staging, telle quelle (BEGIN … ROLLBACK), puis aucun résidu.
    await executer(readFileSync(join(RACINE, SUITE), 'utf8'));
    const [residus] = await executer(`SELECT
      (SELECT count(*)::int FROM auth.users WHERE id::text LIKE 'a5f0e00%') AS comptes,
      (SELECT count(*)::int FROM public.missions WHERE etablissement_id::text LIKE 'a5f0e00%') AS missions,
      (SELECT count(*)::int FROM private.etablissements_revue_store) AS etablissements_designes,
      (SELECT count(*)::int FROM private.soignants_revue_store) AS soignants_designes,
      (SELECT count(*)::int FROM public.missions WHERE etablissement_id = '${ETAB_REVUE}' AND statut = 'OUVERTE') AS stock,
      (SELECT count(*)::int FROM net.http_request_queue) AS http;`);
    assert.deepEqual(residus, { comptes: 0, missions: 0, etablissements_designes: 1, soignants_designes: 1, stock: 3, http: 0 });
    console.log('Banc revue store : refus réels à la migration, premier remplissage, suite SQL complète, aucun résidu.');
  } finally {
    avant.nettoyer();
    await m.fermer?.();
  }
});
