// Suppression du compte soignant : fichiers des pièces et noms lus par l'IA effacés (migrations 20261128140000 et
// 20261128140100), sur une vraie base chargée avec supabase/schema/public.sql :
//   1. constat sur les corps LIVE : après la suppression d'un compte (chemin de l'edge delete-account,
//      fn_supprimer_compte_rate_limited en session utilisateur), les noms lus par l'IA, le nom de fichier d'origine,
//      l'attestation d'heures externes et le fichier restent, aucun fichier n'est mis en file, et l'audit
//      IDENTITE_PROFIL_MODIFIEE n'est pas écrit (CHECK, erreur avalée) ; transaction annulée ;
//   2. les deux migrations, puis la suite SQL tests/security/suppression-compte-soignant-effacement.test.sql telle
//      que le staging l'exécute (BEGIN … ROLLBACK), puis aucun résidu.
// Schéma chargé : le dump d'une révision épinglée antérieure aux migrations (tests/postgres/schema-avant-migration.mjs),
// jamais le dump courant, qui contient les corps APRÈS migration dès la re-baseline suivant le déploiement ; un test
// sans base vérifie que le dump courant est AVANT ou APRÈS, rien d'autre.
// Storage : le banc n'a que storage.objects (id, bucket_id, name) ; la table storage.buckets, absente du socle, est
// créée ici pour la seule clé étrangère des fixtures du staging. L'API Storage est simulée dans la suite par la
// suppression des lignes de storage.objects, comme sur le staging.
// Moteurs : PostgreSQL 17 éphémère de la CI (job « Paiements — verrous PostgreSQL 17 éphémère », base dédiée
// effacement_pieces_banc) ou PGlite local (`JOLENE_PGLITE_MODULES=<dossier node_modules contenant @electric-sql/pglite>`).
// Aucun réseau, aucune donnée hors du dépôt. La preuve sur le schéma réel reste la suite sur le staging.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { charger, moteurPglite, moteurPsql, parametresRequis, RACINE } from '../../scripts/mobile/staging-lot5-banc-sql.mjs';
import { DUMP_AVANT_EFFACEMENT_PIECES, etatDuDumpCourant, racineAvant } from './schema-avant-migration.mjs';

/** psql en VERBOSITY verbose : la ligne d'erreur porte le SQLSTATE (« ERROR:  P0001: … »), absent sinon. */
const avecVerbosite = spawn => (commande, args, options) => spawn(commande, ['-v', 'VERBOSITY=verbose', ...args], options);

export const MIGRATIONS = [
  'supabase/migrations/20261128140000_audit_actions_identite_et_suppression.sql',
  'supabase/migrations/20261128140100_suppression_compte_soignant_effacement_pieces.sql',
];
export const SUITE = 'tests/security/suppression-compte-soignant-effacement.test.sql';
const SOIGNANT = 'a5f1d002-0000-4000-8000-0000000000ff';

async function moteur() {
  if (process.env.JOLENE_PGLITE_MODULES) return moteurPglite(process.env.JOLENE_PGLITE_MODULES);
  assert.equal(process.env.JOLENE_PG_CONCURRENCY, 'CI_EPHEMERE', 'PostgreSQL éphémère de la CI seulement');
  assert.equal(process.env.PGHOST, '127.0.0.1');
  assert.equal(process.env.PGDATABASE, 'effacement_pieces_banc', 'base dédiée, jamais partagée avec les autres étapes');
  return { ...moteurPsql({ spawn: avecVerbosite(spawnSync) }), fermer: async () => {} };
}

/** Soignant aux pièces lues par l'IA qui supprime son compte sur les corps LIVE ; résidus relus avant ROLLBACK. */
export const CONSTAT = `
BEGIN;
INSERT INTO auth.users (id, instance_id, email, role, aud, raw_app_meta_data, email_confirmed_at)
VALUES ('${SOIGNANT}', '00000000-0000-0000-0000-000000000000', 'banc-effacement-pieces@example.invalid',
  'authenticated', 'authenticated', '{"role":"SOIGNANT"}', now());
INSERT INTO public.soignants (id, prenom, nom, email, profession, date_naissance)
VALUES ('${SOIGNANT}', 'Banc', 'Effacement', 'banc-effacement-pieces@example.invalid', 'IDE', date '1990-01-15');
INSERT INTO public.documents_soignants (soignant_id, type_document, s3_cle, nom_fichier, statut_verification, est_critique,
  resultat_ia, nom_extrait_ia, prenom_extrait_ia)
VALUES ('${SOIGNANT}', 'CARTE_IDENTITE', '${SOIGNANT}/documents/CARTE_IDENTITE/1700000000000-NOMIAMARQUEUR.pdf',
  'NOMIAMARQUEUR.pdf', 'VERIFIE', true, '{"nom_extrait":"NOMIAMARQUEUR"}', 'NOMIAMARQUEUR', 'PRENOMIAMARQUEUR');
INSERT INTO storage.objects (bucket_id, name)
VALUES ('jolene-documents', '${SOIGNANT}/documents/CARTE_IDENTITE/1700000000000-NOMIAMARQUEUR.pdf');
SELECT set_config('jolene.heures_externes_server_update', 'true', true);
INSERT INTO public.heures_externes_soignants (soignant_id, etablissement_nom, date_debut, date_fin, heures_declarees,
  attestation_url, resultat_ia)
VALUES ('${SOIGNANT}', 'Clinique NOMIAMARQUEUR', date '2026-01-01', date '2026-03-31', 120,
  '${SOIGNANT}/heures-externes/attestation.pdf', '{"nom_extrait":"NOMIAMARQUEUR"}');
SELECT set_config('jolene.heures_externes_server_update', '', true);
SELECT set_config('request.jwt.claim.sub', '${SOIGNANT}', true);
SELECT set_config('request.jwt.claim.role', 'authenticated', true);
SELECT set_config('request.jwt.claims', '{"sub":"${SOIGNANT}","role":"authenticated"}', true);
SELECT public.fn_supprimer_compte_rate_limited() AS resultat;
SELECT set_config('request.jwt.claim.sub', '', true);
SELECT set_config('request.jwt.claim.role', '', true);
SELECT set_config('request.jwt.claims', '', true);
SELECT
  (SELECT supprime_le IS NOT NULL FROM public.soignants WHERE id = '${SOIGNANT}') AS profil_supprime,
  (SELECT count(*)::int FROM public.documents_soignants WHERE soignant_id = '${SOIGNANT}'
     AND (nom_extrait_ia IS NOT NULL OR resultat_ia IS NOT NULL)) AS pieces_avec_noms_lus,
  (SELECT count(*)::int FROM public.documents_soignants WHERE soignant_id = '${SOIGNANT}'
     AND nom_fichier LIKE '%MARQUEUR%') AS noms_de_fichier,
  (SELECT count(*)::int FROM public.heures_externes_soignants WHERE soignant_id = '${SOIGNANT}') AS attestations_heures,
  (SELECT count(*)::int FROM storage.objects WHERE name LIKE '${SOIGNANT}/%') AS fichiers,
  (SELECT count(*)::int FROM private.rgpd_purges_stockage WHERE soignant_id = '${SOIGNANT}') AS fichiers_en_file,
  (SELECT count(*)::int FROM public.journaux_audit WHERE id_ressource = '${SOIGNANT}'
     AND action = 'IDENTITE_PROFIL_MODIFIEE') AS audits_identite;`;

/**
 * File pg_net observable (mêmes colonnes utiles que net.http_request_queue, corps bytea) et routage Vault fictif :
 * le cron appelle l'edge comme en production, la suite relit l'appel, et vérifie qu'aucune suppression n'en émet.
 */
const FILE_HTTP = `
CREATE TABLE IF NOT EXISTS net.http_request_queue (id bigserial PRIMARY KEY, method text, url text, headers jsonb,
  body bytea, timeout_milliseconds integer);
CREATE OR REPLACE FUNCTION net.http_post(url text, body jsonb DEFAULT '{}'::jsonb, params jsonb DEFAULT '{}'::jsonb,
  headers jsonb DEFAULT '{}'::jsonb, timeout_milliseconds integer DEFAULT 5000) RETURNS bigint LANGUAGE sql AS $f$
  INSERT INTO net.http_request_queue (method, url, headers, body, timeout_milliseconds)
  VALUES ('POST', url, headers, convert_to(body::text, 'UTF8'), timeout_milliseconds) RETURNING id $f$;
INSERT INTO vault.secrets (name, secret)
SELECT v.name, v.secret FROM (VALUES ('supabase_url', 'https://banc.invalid/'), ('cron_automations_key', 'banc-secret-fictif')) v(name, secret)
 WHERE NOT EXISTS (SELECT 1 FROM vault.secrets s WHERE s.name = v.name);`;

const REDEFINITIONS = [
  { schema: 'public', nom: 'fn_supprimer_mon_compte', avant: 'f3af23aeeb4e30aba07e422c0e819aeb', apres: 'bd8df04463ed3b683de237d78b6ecea3' },
  { schema: 'public', nom: 'fn_rgpd_purge_automatique_inactifs', avant: '5f23570c269b42d088b7e4ed5482660d', apres: 'f843b17f0b27a40a632bd0afe458ed4a' },
];

test('dump épinglé AVANT les migrations ; dump courant AVANT ou APRÈS (sans base)', () => {
  const avant = racineAvant(DUMP_AVANT_EFFACEMENT_PIECES);
  try {
    assert.equal(etatDuDumpCourant(REDEFINITIONS, readFileSync(join(avant.racine, 'supabase/schema/public.sql'), 'utf8')).etat, 'AVANT');
  } finally {
    avant.nettoyer();
  }
  const courant = etatDuDumpCourant(REDEFINITIONS);
  assert.ok(['AVANT', 'APRES'].includes(courant.etat), `dump courant incohérent avec la migration : ${JSON.stringify(courant.fonctions)}`);
});

test('suppression du compte soignant : fichiers et noms lus effacés, audit d’identité écrit, aucun résidu', { timeout: 900_000 }, async () => {
  const m = await moteur();
  const executer = m.executer;
  const avant = racineAvant(DUMP_AVANT_EFFACEMENT_PIECES);
  try {
    const { instructions, passe } = await charger(executer, { racine: avant.racine, lot: m.lot, journal: console.log });
    assert.ok(passe > instructions * 0.98, `schéma chargé : ${passe}/${instructions}`);
    for (const instr of parametresRequis(RACINE, ['inscriptions_publiques_actives'])) await executer(instr);
    await executer('CREATE TABLE IF NOT EXISTS storage.buckets (id text PRIMARY KEY, name text);');
    await executer(`INSERT INTO storage.buckets (id, name) VALUES ('jolene-documents', 'jolene-documents') ON CONFLICT (id) DO NOTHING;`);
    await executer(FILE_HTTP);

    // 1. Constat sur les corps LIVE : la suppression aboutit, mais tout reste ; transaction annulée.
    const [constat] = await executer(CONSTAT);
    await executer('ROLLBACK;').catch(() => {});
    assert.deepEqual(constat, {
      profil_supprime: true, pieces_avec_noms_lus: 1, noms_de_fichier: 1, attestations_heures: 1, fichiers: 1,
      fichiers_en_file: 0, audits_identite: 0,
    }, 'constat non reproduit');
    const [vide] = await executer(`SELECT (SELECT count(*)::int FROM auth.users WHERE id = '${SOIGNANT}') AS comptes;`);
    assert.deepEqual(vide, { comptes: 0 }, 'constat annulé');

    // 2. Migrations, puis la suite du staging telle quelle, puis aucun résidu.
    for (const migration of MIGRATIONS) await executer(readFileSync(join(RACINE, migration), 'utf8'));
    await executer(readFileSync(join(RACINE, SUITE), 'utf8'));
    const [residus] = await executer(`SELECT
      (SELECT count(*)::int FROM auth.users WHERE id::text LIKE 'a5f1d002%') AS comptes,
      (SELECT count(*)::int FROM public.soignants WHERE id::text LIKE 'a5f1d002%') AS soignants,
      (SELECT count(*)::int FROM public.documents_soignants WHERE soignant_id::text LIKE 'a5f1d002%') AS pieces,
      (SELECT count(*)::int FROM storage.objects WHERE name LIKE 'a5f1d002%' OR name LIKE 'invoices/a5f1d002%') AS fichiers,
      (SELECT count(*)::int FROM private.rgpd_purges_stockage) + (SELECT count(*)::int FROM private.rgpd_fichiers_a_classer) AS file_effacement,
      (SELECT count(*)::int FROM public.alertes_systeme WHERE source = 'rgpd-purge-stockage') AS alertes,
      (SELECT count(*)::int FROM net.http_request_queue) AS appels_reseau;`);
    assert.deepEqual(residus, { comptes: 0, soignants: 0, pieces: 0, fichiers: 0, file_effacement: 0, alertes: 0, appels_reseau: 0 });
    console.log('Banc effacement des pièces : constat reproduit sur les corps LIVE, suite SQL complète après migrations, aucun résidu.');
  } finally {
    avant.nettoyer();
    await m.fermer?.();
  }
});
