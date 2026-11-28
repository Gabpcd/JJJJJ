// B9 : notifications écrites par les clients et classement des soignants (migration 20261128150000), sur une vraie
// base chargée avec supabase/schema/public.sql :
//   1. constat avant la migration, sur les corps LIVE : un établissement connecté écrit une notification arbitraire
//      (titre, corps, lien externe) à un soignant sans aucun lien avec lui, et lit dans le classement l'identifiant,
//      le prénom et le nom complet d'un soignant réel ;
//   2. la migration, puis la suite SQL tests/security/notifications-classement-b9.test.sql telle que le staging
//      l'exécute (BEGIN … ROLLBACK), puis le même constat refusé (42501, classement vide), puis aucun résidu.
// Schéma chargé : le dump d'une révision épinglée antérieure à la migration (tests/postgres/schema-avant-migration.mjs),
// jamais le dump courant, qui contient le corps APRÈS migration dès la re-baseline suivant le déploiement ;
// un test sans base vérifie que le dump courant est AVANT ou APRÈS, rien d'autre.
// Moteurs : PostgreSQL 17 éphémère de la CI (job « Paiements — verrous PostgreSQL 17 éphémère », base dédiée
// notifications_b9_banc) ou PGlite local (`JOLENE_PGLITE_MODULES=<dossier node_modules contenant @electric-sql/pglite>`).
// Aucun réseau, aucune donnée hors du dépôt. La preuve sur le schéma réel reste la suite sur le staging.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { charger, moteurPglite, moteurPsql, parametresRequis, RACINE } from '../../scripts/mobile/staging-lot5-banc-sql.mjs';
import { DUMP_AVANT_B9_NOTIFICATIONS, etatDuDumpCourant, racineAvant } from './schema-avant-migration.mjs';

// Mêmes lecteurs que tests/postgres/suppression-compte-soignant-preuves.pg17.mjs (non importé : ses tests s'y
// enregistreraient) : psql en VERBOSITY verbose porte le SQLSTATE sur la ligne d'erreur, PGlite dans `code`.
const avecVerbosite = spawn => (commande, args, options) => spawn(commande, ['-v', 'VERBOSITY=verbose', ...args], options);
function sqlstate(erreur) {
  if (typeof erreur?.code === 'string' && /^[0-9A-Z]{5}$/.test(erreur.code)) return erreur.code;
  return /\bERROR:\s+([0-9A-Z]{5}):/.exec(String(erreur?.message ?? ''))?.[1];
}

export const MIGRATION = 'supabase/migrations/20261128150000_borner_notifications_et_classement.sql';
export const SUITE = 'tests/security/notifications-classement-b9.test.sql';
const ETAB = 'b9c1c0ff-0000-4000-8000-000000000001';
const SOIGNANT = 'b9c1c0ff-0000-4000-8000-000000000002';

async function moteur() {
  if (process.env.JOLENE_PGLITE_MODULES) return moteurPglite(process.env.JOLENE_PGLITE_MODULES);
  assert.equal(process.env.JOLENE_PG_CONCURRENCY, 'CI_EPHEMERE', 'PostgreSQL éphémère de la CI seulement');
  assert.equal(process.env.PGHOST, '127.0.0.1');
  assert.equal(process.env.PGDATABASE, 'notifications_b9_banc', 'base dédiée, jamais partagée avec les autres étapes');
  return { ...moteurPsql({ spawn: avecVerbosite(spawnSync) }), fermer: async () => {} };
}

/** Un établissement réel et un soignant réel sans aucun lien, pièces vérifiées ; puis, sous l'établissement connecté. */
const FIXTURES = `
INSERT INTO public.parametres_systeme (cle, valeur, label, description, unite, val_min, val_max, categorie, avertissement, cablee)
VALUES ('inscriptions_publiques_actives', 1, 'Inscriptions publiques actives', 'Banc B9 (transaction annulée).',
        'booléen', 0, 1, 'GENERAL', 'Banc.', true)
ON CONFLICT (cle) DO UPDATE SET valeur = 1;
INSERT INTO auth.users (id, instance_id, email, role, aud, raw_app_meta_data, email_confirmed_at)
VALUES ('${ETAB}', '00000000-0000-0000-0000-000000000000', 'banc-b9-etab@example.invalid', 'authenticated', 'authenticated',
        '{"role":"ADMIN_ETABLISSEMENT"}', now()),
       ('${SOIGNANT}', '00000000-0000-0000-0000-000000000000', 'banc-b9-soignant@example.invalid', 'authenticated',
        'authenticated', '{"role":"SOIGNANT"}', now());
INSERT INTO public.etablissements (id, nom, siret, type, adresse_rue, adresse_ville, adresse_code_postal, email_contact, est_compte_test)
VALUES ('${ETAB}', 'Banc B9', '99195000000001', 'CLINIQUE_PRIVEE', '1 rue du Banc', 'Paris', '75001', 'banc-b9-etab@example.invalid', false);
INSERT INTO public.soignants (id, prenom, nom, email, profession, est_compte_test, date_naissance)
VALUES ('${SOIGNANT}', 'B9Constat', 'Nomcomplet', 'banc-b9-soignant@example.invalid', 'AUXILIAIRE_PUERICULTURE', false, date '1990-01-15');
INSERT INTO public.documents_soignants (soignant_id, type_document, s3_cle, nom_fichier, statut_verification, est_critique, valide_jusqua, resultat_ia)
VALUES ('${SOIGNANT}', 'CARTE_IDENTITE', 'tests/banc-b9/cni', 'cni.pdf', 'VERIFIE', true, current_date + 365, '{}'),
       ('${SOIGNANT}', 'DIPLOME', 'tests/banc-b9/diplome', 'diplome.pdf', 'VERIFIE', true, NULL, '{"profession_certifiee":"AUXILIAIRE_PUERICULTURE"}');
SELECT set_config('request.jwt.claim.sub', '${ETAB}', true);
SELECT set_config('request.jwt.claim.role', 'authenticated', true);
SELECT set_config('request.jwt.claims', '{"sub":"${ETAB}","role":"authenticated"}', true);
SET LOCAL ROLE authenticated;`;

/** Les deux failles, lues en une instruction sous l'établissement connecté. */
export const CONSTAT = `
BEGIN;
${FIXTURES}
SELECT
  (SELECT count(*)::int FROM public.fn_top_soignants('AUXILIAIRE_PUERICULTURE', 50) t
    WHERE t.id = '${SOIGNANT}' AND t.prenom = 'B9Constat' AND t.nom = 'Nomcomplet') AS classement_nominatif,
  public.fn_creer_notification('${SOIGNANT}', 'SOIGNANT', 'SYSTEM', 'Action requise',
    'Vérifiez votre compte', 'https://exemple.invalid/connexion', NULL, NULL) IS NOT NULL AS notification_arbitraire;`;

/** Après la migration : la notification arbitraire est refusée. */
export const CONSTAT_NOTIFICATION_APRES = `
BEGIN;
${FIXTURES}
SELECT public.fn_creer_notification('${SOIGNANT}', 'SOIGNANT', 'SYSTEM', 'Action requise',
  'Vérifiez votre compte', 'https://exemple.invalid/connexion', NULL, NULL) IS NOT NULL AS notification_arbitraire;`;

/** Après la migration : l'établissement ne lit plus aucune ligne du classement. */
export const CONSTAT_CLASSEMENT_APRES = `
BEGIN;
${FIXTURES}
SELECT (SELECT count(*)::int FROM public.fn_top_soignants('AUXILIAIRE_PUERICULTURE', 50)) AS lignes_etablissement;`;

const REDEFINITION = [{ schema: 'public', nom: 'fn_top_soignants',
  avant: '1565a9c0a7908e833f8bdae9f96f852e', apres: '50122640d61db0021246adba36f8a2d3' }];

test('dump épinglé AVANT la migration ; dump courant AVANT ou APRÈS (sans base)', () => {
  const avant = racineAvant(DUMP_AVANT_B9_NOTIFICATIONS);
  try {
    const dump = readFileSync(join(avant.racine, 'supabase/schema/public.sql'), 'utf8');
    assert.equal(etatDuDumpCourant(REDEFINITION, dump).etat, 'AVANT');
    assert.match(dump, /\nGRANT ALL ON FUNCTION "public"\."fn_creer_notification"\([^\n]*\) TO "authenticated";\n/);
  } finally {
    avant.nettoyer();
  }
  const courant = etatDuDumpCourant(REDEFINITION);
  assert.ok(['AVANT', 'APRES'].includes(courant.etat), `dump courant incohérent avec la migration : ${JSON.stringify(courant.fonctions)}`);
});

test('B9 notifications et classement : failles reproduites sur le LIVE, fermées par la migration', { timeout: 900_000 }, async () => {
  const m = await moteur();
  const executer = m.executer;
  const avant = racineAvant(DUMP_AVANT_B9_NOTIFICATIONS);
  try {
    const { instructions, passe } = await charger(executer, { racine: avant.racine, lot: m.lot, journal: console.log });
    assert.ok(passe > instructions * 0.98, `schéma chargé : ${passe}/${instructions}`);
    for (const instr of parametresRequis(RACINE, ['inscriptions_publiques_actives', 'taux_horaire_minimum_salarie'])) await executer(instr);

    // 1. Constat sur les corps LIVE : les deux failles, dans une transaction annulée.
    const [constat] = await executer(CONSTAT);
    await executer('ROLLBACK;').catch(() => {});
    assert.deepEqual(constat, { classement_nominatif: 1, notification_arbitraire: true }, 'constat non reproduit');

    // 2. Migration, puis la suite du staging telle quelle.
    await executer(readFileSync(join(RACINE, MIGRATION), 'utf8'));
    await executer(readFileSync(join(RACINE, SUITE), 'utf8'));

    // 3. Le même constat après : notification refusée (42501), classement vide pour l'établissement.
    let refus = null;
    try {
      await executer(CONSTAT_NOTIFICATION_APRES);
    } catch (e) {
      refus = e;
    }
    await executer('ROLLBACK;').catch(() => {});
    assert.equal(sqlstate(refus), '42501', `notification arbitraire encore acceptée (${refus?.message ?? 'aucun refus'})`);
    const [classement] = await executer(CONSTAT_CLASSEMENT_APRES);
    await executer('ROLLBACK;').catch(() => {});
    assert.deepEqual(classement, { lignes_etablissement: 0 });

    const [residus] = await executer(`SELECT
      (SELECT count(*)::int FROM auth.users WHERE id::text LIKE 'b9c1%') AS comptes,
      (SELECT count(*)::int FROM public.soignants WHERE id::text LIKE 'b9c1%') AS soignants,
      (SELECT count(*)::int FROM public.notifications WHERE destinataire_id::text LIKE 'b9c1%') AS notifications;`);
    assert.deepEqual(residus, { comptes: 0, soignants: 0, notifications: 0 });
    console.log('Banc B9 : deux failles reproduites avant migration, suite SQL complète après, constat refusé, aucun résidu.');
  } finally {
    avant.nettoyer();
    await m.fermer?.();
  }
});
