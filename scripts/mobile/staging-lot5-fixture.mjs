#!/usr/bin/env node
/**
 * Cohorte de recette STAGING du lot 5 (tranche L5-T13, `docs/mobile-swift/LOT5_PLAN.md` §3 T13, cohorte D5) : ce que
 * l'espace établissement de l'app iOS native doit trouver sur le serveur de test pour que
 * `ios-native/JoleneUITests/StagingEtabParcoursTests.swift` le parcoure, puis les relectures en base et le nettoyage.
 *
 * Cohorte d'un run (aucune donnée réelle : adresses `@example.invalid`, nom et intitulés au marqueur `RECETTE-L5-<run>`,
 * `est_compte_test` partout, transports de notification fermés, aucun téléphone) :
 *   - E1, établissement propriétaire legacy (`auth.users.id = etablissements.id`, rôle `ETABLISSEMENT`, aucune ligne
 *     `membres_etablissement`), vérifié, paiement de la commission en `FACTURE_MENSUELLE` (sans mandat SEPA : correction 16
 *     du plan, aucune acceptation bloquée, aucun escrow) ;
 *   - S1, soignant aide-soignant salarié, deux justificatifs `VERIFIE` (identité, diplôme) déclarés côté service ;
 *   - M1, mission `SALARIE` OUVERTE en candidature, un créneau à J+3, et la candidature `EN_ATTENTE` de S1, déposée par
 *     `fn_postuler_mission` sous le JWT de S1 (traces métier réelles) ;
 *   - M2, mission `SALARIE` assignée à S1 par `fn_test_update_mission` (jamais d'UPDATE direct, CLAUDE.md), un créneau
 *     court qui commence quelques minutes après la préparation (code affichable tout de suite, présence validable à sa
 *     fin), un code de pointage actif et un contrat `SIGNE_COMPLET` inséré côté service : aucun OTP, AUCUN SMS.
 *
 * Actions (`node scripts/mobile/staging-lot5-fixture.mjs <action>`) :
 *   - `acces`     : clé publishable du STAGING lue par la Management API, masquée, écrite dans `GITHUB_ENV` ;
 *   - `preparer`  : cohorte créée, manifeste privé (0600) écrit AVANT la première écriture, entrée privée du XCUITest ;
 *   - `scanner`   : entre les deux phases du XCUITest, code relu inchangé (empreinte comparée à celle de la préparation),
 *                   scans d'arrivée puis de départ sous le JWT de S1 (125 s d'écart, anti-rejeu serveur), attente de la
 *                   fin du créneau planifié, identifiant de la présence ajouté à l'entrée privée ;
 *   - `verifier`  : relectures en base après le parcours (candidature ACCEPTEE, présence validée, aucune ligne d'escrow…) ;
 *   - `nettoyer`  : suppression de la cohorte du manifeste (une transaction, dépendances inconnues refusées), comptes
 *                   Auth supprimés, compte final des objets marqués exigé à 0 ; à lancer même si le parcours échoue ;
 *   - `nettoyer_run` : reprise SANS manifeste (le runner hébergé l'efface avec lui) : la cohorte d'un run passé est
 *                   retrouvée par son étiquette (`LOT5_NETTOYER_RUN`, nom exact `RECETTE-L5-<run>` de l'établissement,
 *                   adresses `recette-l5-{e1,s1}-<run>@example.invalid`, métadonnées Auth du run), avec les mêmes verrous ;
 *                   refus si l'étiquette n'a pas la forme attendue, si plus d'un établissement ou d'un soignant
 *                   correspond, ou si une ligne trouvée n'est pas un compte TEST de ce run ;
 *   - `compter`   : compte des objets marqués, lecture seule.
 *
 * Verrou : toute action refuse de s'exécuter, avant le moindre appel réseau, si la référence de projet est celle de la
 * production (`flripxtsyegjshnhzjkz`) ou n'est pas explicitement celle du STAGING (`mejpriaetwgtcstbgfid`) ; chaque
 * requête est ensuite bornée à `api.supabase.com/v1/projects/<staging>/…` et `<staging>.supabase.co`. Les actions qui
 * écrivent exigent en plus `LOT5_STAGING_ECRITURE=COHORTE_D5` (posé par le workflow seulement).
 *
 * Secrets : seuls `STAGING_SUPABASE_ACCESS_TOKEN` et `STAGING_SUPABASE_PROJECT_REF` sont lus ; les clés du projet sont
 * relues à chaque action par la Management API et ne quittent jamais le processus (jamais dans `GITHUB_ENV`, sauf la clé
 * publishable). Mots de passe, adresses et code de pointage : jamais journalisés (masqués, empreinte SHA-256 seulement).
 *
 * Tests (transport simulé, aucun réseau) : `tests/node/staging-lot5-fixture.node.mjs`.
 * Workflow : `.github/workflows/ios-swift-lot5-staging.yml` (dispatch manuel sur `main`).
 */
import { createHash, randomBytes, randomUUID } from 'node:crypto';
import { appendFileSync, existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

export const STAGING_REF = 'mejpriaetwgtcstbgfid';
export const PRODUCTION_REF = 'flripxtsyegjshnhzjkz';
export const STAGING_URL = `https://${STAGING_REF}.supabase.co`;
export const MANAGEMENT_URL = `https://api.supabase.com/v1/projects/${STAGING_REF}`;
export const KIND = 'LOT5_D5';
export const PURPOSE = 'lot5-staging-etab-v1';
export const ECRITURE_APPROUVEE = 'COHORTE_D5';
/** Anti-rejeu de `fn_scanner_code_pointage` : deux scans séparés d'au moins 2 min (`public.sql` l.56215-56219), marge de 5 s. */
export const ECART_SCANS_MS = 125_000;
/** Début du créneau de M2 après la préparation : la phase 1 du XCUITest voit le code (fenêtre de 15 min avant). */
export const M2_DEBUT_APRES_MIN = 12;
/** Durée du créneau de M2 : les deux scans et l'attente anti-rejeu y tiennent. */
export const M2_DUREE_MIN = 6;
const ACTIONS = ['acces', 'preparer', 'scanner', 'verifier', 'nettoyer', 'nettoyer_run', 'compter'];
const ECRITURES = new Set(['preparer', 'scanner', 'nettoyer', 'nettoyer_run']);
const RUN = /^[A-Za-z0-9][A-Za-z0-9-]{0,39}$/;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;

/** Littéral SQL (apostrophes doublées) ; toute valeur interpolée passe ici ou par `uuid()`. */
export const q = v => `'${String(v).replaceAll("'", "''")}'`;
const uuid = v => {
  if (!UUID.test(String(v))) throw new Error('Identifiant L5 invalide.');
  return `${q(v)}::uuid`;
};
const uuids = liste => `ARRAY[${liste.map(uuid).join(',')}]::uuid[]`;
export const sha256 = v => createHash('sha256').update(String(v), 'utf8').digest('hex');

// MARK: - Verrou de projet

/**
 * Verrou de destination, appelé avant tout appel réseau. Refuse la production nommément, puis toute référence qui n'est
 * pas explicitement celle du STAGING attendu. La valeur reçue n'est jamais recopiée dans le message (c'est un secret
 * de dépôt).
 */
export function verifierProjet(env) {
  const ref = String(env.STAGING_SUPABASE_PROJECT_REF ?? '').trim();
  const urls = [env.STAGING_SUPABASE_URL, env.SUPABASE_URL, env.JOLENE_SUPABASE_URL].map(u => String(u ?? ''));
  if (ref === PRODUCTION_REF || urls.some(u => u.includes(PRODUCTION_REF))) {
    throw new Error(`Fixture lot 5 refusée : ${PRODUCTION_REF} est le projet de PRODUCTION. `
      + `Seul le projet STAGING ${STAGING_REF} est admis ; aucune écriture n'a été tentée.`);
  }
  if (ref !== STAGING_REF) {
    throw new Error(`Fixture lot 5 refusée : STAGING_SUPABASE_PROJECT_REF n'est pas explicitement le projet STAGING `
      + `${STAGING_REF} (valeur absente ou autre, non recopiée) ; aucune requête n'a été envoyée.`);
  }
  if (urls[0] && urls[0] !== STAGING_URL) throw new Error(`Fixture lot 5 refusée : STAGING_SUPABASE_URL doit valoir ${STAGING_URL}.`);
  return ref;
}

/** Seules destinations admises : la Management API du projet STAGING et le projet STAGING lui-même. */
export function destinationAdmise(url) {
  let u;
  try { u = new URL(url); } catch { return false; }
  if (u.protocol !== 'https:' || u.port !== '' || u.username || u.password) return false;
  if (u.hostname === 'api.supabase.com') return u.pathname.startsWith(`/v1/projects/${STAGING_REF}/`);
  return u.hostname === `${STAGING_REF}.supabase.co`;
}

// MARK: - Manifeste

/** Adresses des deux comptes d'un run : dérivées de l'étiquette seule (reprise sans manifeste). */
export const emailsDuRun = runId => ({
  etablissement: `recette-l5-e1-${runId.toLowerCase()}@example.invalid`,
  soignant: `recette-l5-s1-${runId.toLowerCase()}@example.invalid`,
});

/** Commande de reprise d'un run dont le nettoyage a échoué (le manifeste disparaît avec le runner). */
export const repriseDuRun = runId => `reprise : relancer ios-swift-lot5-staging.yml avec l'entrée nettoyer_run=${runId}`;

export function runIdDepuis(env) {
  const brut = env.LOT5_RUN_ID || `local-${randomUUID().slice(0, 8)}`;
  if (!/^[A-Za-z0-9][A-Za-z0-9-]{0,39}$/.test(brut)) throw new Error('LOT5_RUN_ID invalide (lettres, chiffres, tirets).');
  return brut;
}

/** Identifiants et horaires d'un run, tous connus avant la première écriture. */
export function manifeste(runId, maintenant) {
  const t0 = maintenant.getTime();
  const minute = 60_000;
  const jourM1 = new Date(t0 + 3 * 24 * 60 * minute);
  jourM1.setUTCHours(7, 0, 0, 0);
  const m2Debut = new Date(Math.ceil((t0 + M2_DEBUT_APRES_MIN * minute) / minute) * minute);
  const marker = `RECETTE-L5-${runId}`;
  const siret = '99' + (BigInt('0x' + sha256(`l5:${runId}`).slice(0, 12)) % 1_000_000_000_000n).toString().padStart(12, '0');
  return {
    purpose: PURPOSE, kind: KIND, projectRef: STAGING_REF, runId, marker, siret, preparedAt: maintenant.toISOString(),
    etablissement: { id: randomUUID(), email: emailsDuRun(runId).etablissement },
    soignant: { id: randomUUID(), email: emailsDuRun(runId).soignant },
    documents: [randomUUID(), randomUUID()],
    m1: { id: randomUUID(), creneauId: randomUUID(), intitule: `${marker} · M1 candidature`,
      debut: jourM1.toISOString(), fin: new Date(jourM1.getTime() + 4 * 60 * minute).toISOString() },
    m2: { id: randomUUID(), creneauId: randomUUID(), contratId: randomUUID(), intitule: `${marker} · M2 pointage`,
      numeroContrat: `${marker}-M2`, debut: m2Debut.toISOString(),
      fin: new Date(m2Debut.getTime() + M2_DUREE_MIN * minute).toISOString() },
    status: 'planned', auth: { etablissement: 'not-started', soignant: 'not-started' },
    candidatureId: null, codeSha256: null, presenceId: null,
  };
}

export function validerManifeste(doc) {
  const ok = doc && doc.purpose === PURPOSE && doc.kind === KIND && doc.projectRef === STAGING_REF
    && /^[A-Za-z0-9][A-Za-z0-9-]{0,39}$/.test(doc.runId ?? '') && doc.marker === `RECETTE-L5-${doc.runId}`
    && [doc.etablissement?.id, doc.soignant?.id, ...(doc.documents ?? []), doc.m1?.id, doc.m1?.creneauId, doc.m2?.id,
      doc.m2?.creneauId, doc.m2?.contratId].every(v => UUID.test(String(v)))
    && new Set([doc.etablissement.id, doc.soignant.id, doc.m1.id, doc.m2.id, doc.m2.contratId]).size === 5
    && [doc.etablissement.email, doc.soignant.email].every(e => typeof e === 'string' && e.endsWith('@example.invalid'))
    && (doc.candidatureId === null || UUID.test(doc.candidatureId))
    && (doc.presenceId === null || UUID.test(doc.presenceId));
  if (!ok) throw new Error('Manifeste L5 altéré ou d un autre run : aucune action.');
  return doc;
}

// MARK: - SQL

const entete = m => `BEGIN;
SET LOCAL statement_timeout = '60s';
SET LOCAL lock_timeout = '10s';
SET LOCAL request.jwt.claims = '{"role":"service_role"}';
SET LOCAL request.jwt.claim.sub = '';
SET LOCAL request.jwt.claim.role = 'service_role';
SET LOCAL app.test_mode = 'true';
SELECT pg_advisory_xact_lock(${BigInt('0x' + sha256(`L5:${m.runId}`).slice(0, 15))}::bigint);
`;

/** Identifiant facultatif (reprise par étiquette : une partie de la cohorte peut manquer) : `NULL` ne désigne aucune ligne. */
const u = v => (v ? uuid(v) : 'NULL::uuid');
const ids = m => uuids([m.etablissement?.id, m.soignant?.id].filter(Boolean));
const missions = m => uuids([m.m1?.id, m.m2?.id].filter(Boolean));
const authDuRun = (m, qui, role) => `u.id = ${uuid(m[qui].id)} AND u.email = ${q(m[qui].email)}
    AND u.email_confirmed_at IS NOT NULL AND u.raw_app_meta_data->>'role' = ${q(role)}
    AND u.raw_app_meta_data->'est_compte_test' = 'true'::jsonb AND u.raw_app_meta_data->'is_test_playwright' = 'true'::jsonb
    AND u.raw_app_meta_data->>'load_fixture_kind' = ${q(KIND)} AND u.raw_app_meta_data->>'load_fixture_run' = ${q(m.runId)}`;

/** Préparation côté service (une transaction) : E1, S1, justificatifs, M1, M2 assignée, contrat signé, code actif. */
export function sqlPreparer(m) {
  const e = m.etablissement, s = m.soignant;
  return `${entete(m)}DO $l5_seed$
DECLARE v_code text; v_essais integer := 0;
BEGIN
  IF auth.uid() IS NOT NULL OR auth.role() IS DISTINCT FROM 'service_role' THEN RAISE EXCEPTION 'Contexte service requis (L5)'; END IF;
  IF NOT EXISTS (SELECT 1 FROM auth.users u WHERE ${authDuRun(m, 'etablissement', 'ETABLISSEMENT')}
       AND NOT (u.raw_app_meta_data ? 'etablissement_id')) THEN RAISE EXCEPTION 'Auth E1 du run L5 non confirmée'; END IF;
  IF NOT EXISTS (SELECT 1 FROM auth.users u WHERE ${authDuRun(m, 'soignant', 'SOIGNANT')}) THEN RAISE EXCEPTION 'Auth S1 du run L5 non confirmée'; END IF;
  IF EXISTS (SELECT 1 FROM public.etablissements WHERE id = ANY(${ids(m)}) OR source_acquisition = ${q(m.marker)})
     OR EXISTS (SELECT 1 FROM public.soignants WHERE id = ANY(${ids(m)}) OR source_acquisition = ${q(m.marker)})
     OR EXISTS (SELECT 1 FROM public.missions WHERE id = ANY(${missions(m)}))
     OR EXISTS (SELECT 1 FROM public.membres_etablissement WHERE etablissement_id = ${uuid(e.id)} OR user_id = ANY(${ids(m)})) THEN
    RAISE EXCEPTION 'Run L5 déjà utilisé : aucune recréation';
  END IF;

  INSERT INTO public.soignants (id, prenom, nom, email, profession, type_exercice, date_naissance, est_compte_test,
    source_acquisition, sms_actif, sms_alertes_actives)
  VALUES (${uuid(s.id)}, 'Recette', 'Lot cinq', ${q(s.email)}, 'AS', 'SALARIE', '1990-01-01', true, ${q(m.marker)}, false, false);
  INSERT INTO public.documents_soignants (id, soignant_id, type_document, libelle, s3_cle, nom_fichier, type_mime,
    statut_verification, verifie_le, valide_depuis, valide_jusqua)
  VALUES (${uuid(m.documents[0])}, ${uuid(s.id)}, 'CARTE_IDENTITE', ${q(m.marker)}, ${q(`recette-l5/${m.runId}/identite-fictive.pdf`)},
          'identite-fictive.pdf', 'application/pdf', 'VERIFIE', now(), current_date - 30, current_date + 365),
         (${uuid(m.documents[1])}, ${uuid(s.id)}, 'DIPLOME', ${q(m.marker)}, ${q(`recette-l5/${m.runId}/diplome-fictif.pdf`)},
          'diplome-fictif.pdf', 'application/pdf', 'VERIFIE', now(), current_date - 30, current_date + 365);

  INSERT INTO public.etablissements (id, nom, siret, type, adresse_rue, adresse_ville, adresse_code_postal, email_contact,
    telephone_contact, est_compte_test, source_acquisition, sms_actif, chorus_pro_actif, statut_verification,
    peut_publier_missions, siret_verifie, finess_verifie, representant_identite_verifiee, rattachement_verifie,
    contrat_service_signe)
  VALUES (${uuid(e.id)}, ${q(m.marker)}, ${q(m.siret)}, 'CLINIQUE_PRIVEE', 'Adresse fictive de recette', 'Paris', '75001',
          ${q(e.email)}, NULL, true, ${q(m.marker)}, false, false, 'VERIFIE', true, true, true, true, true, true);
  -- L'INSERT d'un établissement privé impose SEPA_DEBIT : sans mandat, toute acceptation lèverait P0001 (correction 16).
  UPDATE public.etablissements SET mode_paiement_commission = 'FACTURE_MENSUELLE', stripe_sepa_payment_method_id = NULL,
    stripe_customer_id = NULL WHERE id = ${uuid(e.id)};
  IF NOT EXISTS (SELECT 1 FROM public.etablissements WHERE id = ${uuid(e.id)} AND est_compte_test AND statut_verification = 'VERIFIE'
       AND peut_publier_missions AND siret_verifie AND finess_verifie AND representant_identite_verifiee AND rattachement_verifie
       AND contrat_service_signe AND mode_paiement_commission = 'FACTURE_MENSUELLE' AND NOT coalesce(sms_actif, false)) THEN
    RAISE EXCEPTION 'Vérifications de E1 invalidées par un déclencheur';
  END IF;
  IF public.fn_blocage_publication_etab(${uuid(e.id)}) IS NOT NULL THEN RAISE EXCEPTION 'Publication de E1 bloquée'; END IF;
  IF EXISTS (SELECT 1 FROM public.membres_etablissement WHERE etablissement_id = ${uuid(e.id)}) THEN
    RAISE EXCEPTION 'E1 doit rester propriétaire legacy (aucune ligne membres_etablissement)';
  END IF;

  UPDATE public.preferences_notifications SET canal_email = false, canal_sms = false, canal_push = false
   WHERE utilisateur_id = ANY(${ids(m)});
  IF EXISTS (SELECT 1 FROM public.preferences_notifications WHERE utilisateur_id = ANY(${ids(m)})
       AND (canal_email IS DISTINCT FROM false OR canal_sms IS DISTINCT FROM false OR canal_push IS DISTINCT FROM false)) THEN
    RAISE EXCEPTION 'Transports de notification L5 non fermés';
  END IF;

  PERFORM set_config('jolene.planning_exact_managed', 'true', true);
  INSERT INTO public.missions (id, etablissement_id, intitule, description, profession_requise, service, debut_le, fin_le,
    duree_heures, taux_horaire_base, statut, mode_attribution, type_contrat_recherche, est_urgente)
  VALUES (${uuid(m.m1.id)}, ${uuid(e.id)}, ${q(m.m1.intitule)}, 'Mission fictive de recette L5, aucune activité réelle.', 'AS',
          'Recette L5', ${q(m.m1.debut)}::timestamptz, ${q(m.m1.fin)}::timestamptz, 4, 20, 'OUVERTE', 'CANDIDATURE', 'SALARIE', false),
         (${uuid(m.m2.id)}, ${uuid(e.id)}, ${q(m.m2.intitule)}, 'Mission fictive de recette L5, aucune activité réelle.', 'AS',
          'Recette L5', ${q(m.m2.debut)}::timestamptz, ${q(m.m2.fin)}::timestamptz, ${(M2_DUREE_MIN / 60).toFixed(2)}, 20,
          'OUVERTE', 'CANDIDATURE', 'SALARIE', false);
  INSERT INTO public.mission_creneaux (id, mission_id, debut, fin, est_pause, ordre, type_creneau)
  VALUES (${uuid(m.m1.creneauId)}, ${uuid(m.m1.id)}, ${q(m.m1.debut)}::timestamptz, ${q(m.m1.fin)}::timestamptz, false, 1, 'PREVISIONNEL'),
         (${uuid(m.m2.creneauId)}, ${uuid(m.m2.id)}, ${q(m.m2.debut)}::timestamptz, ${q(m.m2.fin)}::timestamptz, false, 1, 'PREVISIONNEL');

  -- Code de pointage : six chiffres, unique parmi les missions actives (même règle que fn_scanner_code_pointage).
  LOOP
    v_code := lpad(floor(random() * 1000000)::text, 6, '0');
    EXIT WHEN NOT EXISTS (SELECT 1 FROM public.missions WHERE code_pointage_actif = v_code AND statut IN ('ASSIGNEE', 'EN_COURS'));
    v_essais := v_essais + 1;
    IF v_essais > 50 THEN RAISE EXCEPTION 'Code de pointage L5 introuvable'; END IF;
  END LOOP;
  PERFORM public.fn_test_update_mission(${uuid(m.m2.id)}, jsonb_build_object('statut', 'ASSIGNEE',
    'soignant_assigne_id', ${q(s.id)}, 'type_contrat_applique', 'SALARIE', 'code_pointage_actif', v_code,
    'prochain_type_scan', 'OUVERTURE', 'nb_scans', 0));
  IF NOT EXISTS (SELECT 1 FROM public.missions WHERE id = ${uuid(m.m2.id)} AND statut = 'ASSIGNEE'
       AND soignant_assigne_id = ${uuid(s.id)} AND type_contrat_applique = 'SALARIE' AND code_pointage_actif = v_code) THEN
    RAISE EXCEPTION 'Assignation de M2 non appliquée (fn_test_update_mission)';
  END IF;

  -- Contrat déjà signé, inséré côté service : aucun OTP, aucun SMS (le compte TEST coupe aussi e-mail et push).
  INSERT INTO public.contrats_mission (id, mission_id, etablissement_id, soignant_id, type_contrat, numero_contrat,
    contenu_html, statut, signature_etablissement, signature_etablissement_le, signature_soignant, signature_soignant_le,
    mode_signature)
  VALUES (${uuid(m.m2.contratId)}, ${uuid(m.m2.id)}, ${uuid(e.id)}, ${uuid(s.id)}, 'CDD', ${q(m.m2.numeroContrat)},
          ${q(`<p>Contrat fictif de recette ${m.marker}, sans portée juridique.</p>`)}, 'SIGNE_COMPLET',
          true, now(), true, now(), 'JOLENE_OTP');
  IF EXISTS (SELECT 1 FROM public.paiements_escrow WHERE mission_id = ANY(${missions(m)})) THEN
    RAISE EXCEPTION 'Escrow créé pour une mission salariée L5';
  END IF;
END $l5_seed$;
COMMIT;
SELECT true AS prepare;`;
}

/** Code de pointage actif de M2, lu côté service (jamais journalisé : seule son empreinte sort du script). */
export const sqlCode = m => `SELECT code_pointage_actif AS code, prochain_type_scan, statut::text AS statut
FROM public.missions WHERE id = ${uuid(m.m2.id)} AND etablissement_id = ${uuid(m.etablissement.id)};`;

export const sqlCandidature = m => `SELECT id, statut FROM public.candidatures
WHERE mission_id = ${uuid(m.m1.id)} AND soignant_id = ${uuid(m.soignant.id)};`;

export const sqlPresence = m => `SELECT id, pointage_arrivee_le IS NOT NULL AS arrivee, pointage_depart_le IS NOT NULL AS depart,
  coalesce(valide_par_etablissement, false) AS validee
FROM public.presences WHERE mission_id = ${uuid(m.m2.id)} AND soignant_id = ${uuid(m.soignant.id)};`;

/** Relectures après le parcours : chaque colonne est une assertion de `validerRelectures`. */
export function sqlVerifier(m) {
  const presence = m.presenceId ? uuid(m.presenceId) : 'NULL::uuid';
  const candidature = m.candidatureId ? uuid(m.candidatureId) : 'NULL::uuid';
  return `SELECT
  (SELECT statut FROM public.candidatures WHERE id = ${candidature}) AS candidature_statut,
  (SELECT traite_le IS NOT NULL FROM public.candidatures WHERE id = ${candidature}) AS candidature_traitee,
  (SELECT statut::text FROM public.missions WHERE id = ${uuid(m.m1.id)}) AS m1_statut,
  (SELECT soignant_assigne_id = ${uuid(m.soignant.id)} FROM public.missions WHERE id = ${uuid(m.m1.id)}) AS m1_assignee_s1,
  (SELECT count(*)::integer FROM public.contrats_mission WHERE mission_id = ${uuid(m.m1.id)}) AS m1_contrats,
  (SELECT statut FROM public.contrats_mission WHERE id = ${uuid(m.m2.contratId)}) AS m2_contrat_statut,
  (SELECT coalesce(valide_par_etablissement, false) FROM public.presences WHERE id = ${presence} AND mission_id = ${uuid(m.m2.id)}) AS presence_validee,
  (SELECT valide_le IS NOT NULL FROM public.presences WHERE id = ${presence}) AS presence_valide_le,
  (SELECT count(*)::integer FROM public.notations_missions WHERE mission_id = ${uuid(m.m2.id)} AND sens = 'ETAB_VERS_SOIGNANT') AS m2_notations,
  (SELECT count(*)::integer FROM public.paiements_escrow WHERE mission_id = ANY(${missions(m)})) AS escrow,
  (SELECT count(*)::integer FROM public.escrow_release_queue WHERE mission_id = ANY(${missions(m)})) AS escrow_file,
  (SELECT count(*)::integer FROM public.notifications WHERE id_ressource = ANY(${missions(m)})
     AND NOT (destinataire_id = ANY(${ids(m)}))) AS notifications_hors_cohorte,
  (SELECT count(*)::integer FROM public.email_queue WHERE destinataire_id = ANY(${ids(m)})) AS emails_cohorte,
  (SELECT count(*)::integer FROM public.preferences_notifications WHERE utilisateur_id = ANY(${ids(m)})
     AND (canal_email IS DISTINCT FROM false OR canal_sms IS DISTINCT FROM false OR canal_push IS DISTINCT FROM false)) AS canaux_ouverts;`;
}

/**
 * Tables à vider avant les racines de la cohorte (`missions`, `etablissements`, `soignants`) : fermeture transitive des
 * clés étrangères du dump `supabase/schema/public.sql` vers une racine ou vers une table déjà retenue, hors `SET NULL` /
 * `SET DEFAULT` (la ligne enfant survit) et hors auto-références. Les enfants `CASCADE` sont retenus aussi : leurs propres
 * enfants restrictifs doivent partir avant eux. Ordre : parents avant enfants (les suppressions se font en sens inverse).
 * Format : `table:colonne>parent,…`. Liste PROUVÉE, pas écrite à la main : `tests/node/staging-lot5-fixture.node.mjs`
 * la recalcule depuis le dump et échoue à la moindre différence (régénérer avec `node … graphe`).
 */
export const GRAPHE_NETTOYAGE = [
  'api_keys:etablissement_id>etablissements',
  'assurance_config:etablissement_id>etablissements',
  'assurances_mission:etablissement_id>etablissements,mission_id>missions',
  'attestations_heures_externes:soignant_id>soignants',
  'badges_soignant:soignant_id>soignants',
  'bfa_suivi:etablissement_id>etablissements',
  'calendar_events_sync:mission_id>missions',
  'candidatures:mission_id>missions,soignant_id>soignants',
  'chorus_pro_config:etablissement_id>etablissements',
  'codes_secours_mission:mission_id>missions',
  'conformite_travail:mission_id>missions,soignant_id>soignants',
  'contrats_mission:etablissement_id>etablissements,mission_id>missions,soignant_id>soignants',
  'contrats_service_signatures:etablissement_id>etablissements',
  'contrats_travail_missions:etablissement_id>etablissements,mission_id>missions,soignant_id>soignants',
  'conversations:etablissement_id>etablissements,mission_id>missions,soignant_id>soignants',
  'conversions_liberal:soignant_id>soignants',
  'copies_bulletins_paie:etablissement_id>etablissements,soignant_id>soignants',
  'cotisations_sociales:mission_id>missions,soignant_id>soignants',
  'credits_etablissement:etablissement_id>etablissements',
  'documents_soignants:soignant_id>soignants',
  'equipes:etablissement_id>etablissements',
  'escrow_etablissement_etat:etablissement_id>etablissements',
  'etablissement_preuve_audit:etablissement_id>etablissements',
  'evaluations:mission_id>missions',
  'factures_honoraires:etablissement_id>etablissements,mission_id>missions,soignant_id>soignants',
  'favoris_soignant_etab:etablissement_id>etablissements,soignant_id>soignants',
  'heures_externes_soignants:soignant_id>soignants',
  'historique_blocages_etablissements:etablissement_id>etablissements',
  'invitations_etablissement:etablissement_id>etablissements',
  'mandats_facturation_signatures:soignant_id>soignants',
  'matching_preferences_soignant:soignant_id>soignants',
  'matching_scores:mission_id>missions,soignant_id>soignants',
  'membres_etablissement:etablissement_id>etablissements',
  'messages_mission:mission_id>missions',
  'mission_creneaux:mission_id>missions',
  'mission_series:etablissement_id>etablissements',
  'missions_sauvegardees:mission_id>missions,soignant_id>soignants',
  'notations_missions:mission_id>missions',
  'notifications_notation_j1:mission_id>missions',
  'paiements_escrow:etablissement_id>etablissements,mission_id>missions,soignant_id>soignants',
  'paiements_mission:etablissement_id>etablissements,mission_id>missions',
  'parcours_liberal_soignants:soignant_id>soignants',
  'parrainages_etablissements:filleul_etab_id>etablissements,parrain_etab_id>etablissements',
  'pings_gps_mission:mission_id>missions',
  'presences:mission_id>missions,soignant_id>soignants',
  'prevoyance_liste_attente:soignant_id>soignants',
  'qr_codes_mission:mission_id>missions',
  'rappels_contrat_travail:mission_id>missions',
  'reclamations:mission_id>missions',
  'reclamations_scoring:mission_id>missions,soignant_id>soignants',
  'scoring_breakdown:soignant_id>soignants',
  'souscriptions_prevoyance:soignant_id>soignants',
  'streaks_soignant:soignant_id>soignants',
  'stripe_connect_onboarding:soignant_id>soignants',
  'suivi_conversion_3200h:soignant_id>soignants',
  'super_swipes_quota:soignant_id>soignants',
  'swipes:mission_id>missions,soignant_id>soignants',
  'cessions_creance:facture_honoraire_id>factures_honoraires,soignant_id>soignants',
  'chorus_submissions:invoice_id>factures_honoraires',
  'equipe_membres:equipe_id>equipes',
  'escrow_exposition_releases:etablissement_id>etablissements,paiement_escrow_id>paiements_escrow',
  'escrow_release_queue:mission_id>missions,paiement_escrow_id>paiements_escrow',
  'factor_advances:etablissement_id>etablissements,facture_honoraire_id>factures_honoraires,mission_id>missions,soignant_id>soignants',
  'factures:etablissement_id>etablissements,facture_honoraire_id>factures_honoraires,mission_id>missions',
  'factures_honoraires_documents:facture_honoraire_id>factures_honoraires',
  'heures_externes:document_id>documents_soignants,soignant_id>soignants',
  'invoice_audit_log:invoice_id>factures_honoraires',
  'messages_chat:conversation_id>conversations',
  'paiements_soignant:etablissement_id>etablissements,facture_honoraire_id>factures_honoraires,mission_id>missions,soignant_id>soignants',
  'partages_rib:contrat_id>contrats_mission,document_rib_id>documents_soignants,etablissement_id>etablissements,mission_id>missions,soignant_id>soignants',
  'pauses_presence:presence_id>presences,soignant_id>soignants',
  'scans_pointage:creneau_effectif_id>mission_creneaux,mission_id>missions',
  'shifts:equipe_id>equipes,etablissement_id>etablissements',
  'signalements_copies_bulletins:copie_id>copies_bulletins_paie',
  'signatures_contrats:contrat_id>contrats_mission',
  'stripe_refunds_queue:avoir_id>factures_honoraires,facture_origine_id>factures_honoraires,paiement_escrow_id>paiements_escrow',
  'typing_status:conversation_id>conversations',
  'litiges:etablissement_id>etablissements,mission_id>missions,paiement_soignant_id>paiements_soignant,presence_id>presences,soignant_id>soignants',
  'shift_affectations:mission_id>missions,shift_id>shifts',
  'stripe_transfers:etablissement_id>etablissements,facture_honoraire_id>factures_honoraires,facture_id>factures,mission_id>missions,soignant_id>soignants',
  'bulletins_paie:etablissement_id>etablissements,litige_id>litiges,mission_id>missions,soignant_id>soignants',
  'factures_honoraires_rectifications:facture_honoraire_id>factures_honoraires,litige_id>litiges',
  'messages_litige:litige_id>litiges',
];

export const RACINES_COHORTE = ['missions', 'etablissements', 'soignants'];
export function grapheNettoyage(dump) {
  const re = /ALTER TABLE ONLY "public"\."(\w+)"\s+ADD CONSTRAINT "\w+" FOREIGN KEY \(([^)]*)\) REFERENCES "public"\."(\w+)"\(([^)]*)\)([^;]*);/g;
  const liens = [];
  for (const [, enfant, cols, parent, ref, reste] of dump.matchAll(re)) {
    const action = /ON DELETE (CASCADE|SET NULL|SET DEFAULT|RESTRICT|NO ACTION)/.exec(reste)?.[1] ?? 'NO ACTION';
    const colonnes = cols.replaceAll('"', '').split(',').map(c => c.trim());
    liens.push({ enfant, colonnes, parent, ref: ref.replaceAll('"', '').trim(), action });
  }
  const suivis = liens.filter(l => l.enfant !== l.parent && !['SET NULL', 'SET DEFAULT'].includes(l.action) && !RACINES_COHORTE.includes(l.enfant));
  const dans = new Set(RACINES_COHORTE), file = [...RACINES_COHORTE];
  while (file.length) { const t = file.shift(); for (const l of suivis) if (l.parent === t && !dans.has(l.enfant)) { dans.add(l.enfant); file.push(l.enfant); } }
  const tables = [...dans].filter(t => !RACINES_COHORTE.includes(t));
  const entrants = new Map(tables.map(t => [t, suivis.filter(l => l.enfant === t && dans.has(l.parent))]));
  for (const [t, ls] of entrants) for (const l of ls) if (l.colonnes.length !== 1 || l.ref !== 'id') throw new Error(`FK non gérée ${t}`);
  // ordre : parents avant enfants (Kahn), égalités par nom
  const ordre = [], places = new Set(RACINES_COHORTE);
  let reste = [...tables].sort();
  while (reste.length) {
    const prets = reste.filter(t => entrants.get(t).every(l => places.has(l.parent)));
    if (!prets.length) throw new Error(`cycle : ${reste.join(',')}`);
    for (const t of prets) { ordre.push(t); places.add(t); }
    reste = reste.filter(t => !places.has(t));
  }
  return ordre.map(t => `${t}:${[...new Set(entrants.get(t).map(l => `${l.colonnes[0]}>${l.parent}`))].sort().join(',')}`);
}

/** Lecture de `GRAPHE_NETTOYAGE` : `[{ table, liens: [{ colonne, parent }] }]`, dans l'ordre parents → enfants. */
export function lireGraphe(graphe = GRAPHE_NETTOYAGE) {
  return graphe.map(ligne => {
    const [table, reste] = ligne.split(':');
    return { table, liens: reste.split(',').map(l => { const [colonne, parent] = l.split('>'); return { colonne, parent }; }) };
  });
}

const IDENT = /^[a-z_][a-z0-9_]*$/;
/** SQL de collecte (parents → enfants) puis de suppression (enfants → parents) de la fermeture, sur la table `l5_ids`. */
function sqlFermeture(graphe = GRAPHE_NETTOYAGE) {
  const tables = lireGraphe(graphe);
  for (const { table, liens } of tables) {
    if (!IDENT.test(table) || liens.some(l => !IDENT.test(l.colonne) || !IDENT.test(l.parent))) throw new Error('Graphe L5 invalide.');
  }
  const parents = new Set(tables.flatMap(t => t.liens.map(l => l.parent)));
  const condition = liens => liens.map(l => `x.${l.colonne} IN (SELECT id FROM l5_ids WHERE tbl = '${l.parent}')`).join(' OR ');
  const collecte = tables.filter(t => parents.has(t.table)).map(t =>
    `  INSERT INTO l5_ids SELECT '${t.table}', x.id FROM public.${t.table} x WHERE ${condition(t.liens)} ON CONFLICT DO NOTHING;`);
  const suppression = [...tables].reverse().map(t => `  DELETE FROM public.${t.table} x WHERE ${condition(t.liens)};`);
  return { collecte: collecte.join('\n'), suppression: suppression.join('\n') };
}

/**
 * Nettoyage (une transaction) : contrôle d'appartenance au run, suppression des enfants connus, refus nominatif de
 * toute dépendance inconnue (FK RESTRICT/NO ACTION vers une ligne de la cohorte) AVANT la suppression des parents.
 * `journaux_audit` est immuable et conservé (CLAUDE.md). Sans ligne à supprimer, la transaction est un no-op.
 */
export function sqlNettoyer(m) {
  const e = m.etablissement ?? {}, s = m.soignant ?? {};
  const fermeture = sqlFermeture();
  const lesMissions = `ARRAY(SELECT id FROM public.missions WHERE etablissement_id = ${u(e.id)} OR id = ANY(${missions(m)}))`;
  return `${entete(m)}DO $l5_clean$
DECLARE v_missions uuid[]; v_ids uuid[] := ${ids(m)}; fk record; n bigint;
BEGIN
  IF auth.uid() IS NOT NULL OR auth.role() IS DISTINCT FROM 'service_role' THEN RAISE EXCEPTION 'Contexte service requis (L5)'; END IF;
  IF EXISTS (SELECT 1 FROM auth.users u WHERE u.id = ANY(v_ids) AND (u.raw_app_meta_data->>'load_fixture_run' IS DISTINCT FROM ${q(m.runId)}
       OR u.raw_app_meta_data->>'load_fixture_kind' IS DISTINCT FROM ${q(KIND)} OR u.email NOT LIKE '%@example.invalid')) THEN
    RAISE EXCEPTION 'Identité hors du run L5 : aucune suppression';
  END IF;
  IF EXISTS (SELECT 1 FROM public.etablissements WHERE id = ${u(e.id)} AND (est_compte_test IS NOT TRUE OR nom IS DISTINCT FROM ${q(m.marker)}))
     OR EXISTS (SELECT 1 FROM public.soignants WHERE id = ${u(s.id)} AND (est_compte_test IS NOT TRUE OR source_acquisition IS DISTINCT FROM ${q(m.marker)})) THEN
    RAISE EXCEPTION 'Profil hors du run L5 (marqueur ou compte TEST absent) : aucune suppression';
  END IF;
  v_missions := ${lesMissions};
  IF EXISTS (SELECT 1 FROM public.missions WHERE id = ANY(v_missions) AND left(intitule, ${m.marker.length}) IS DISTINCT FROM ${q(m.marker)}) THEN
    RAISE EXCEPTION 'Mission de E1 sans le marqueur du run L5 : aucune suppression';
  END IF;

  UPDATE auth.users SET raw_app_meta_data = raw_app_meta_data || '{"load_cleanup_pending":true}'::jsonb WHERE id = ANY(v_ids);
  -- Sans clé étrangère : notifications (toutes celles des missions du run aussi, quel que soit le destinataire), file
  -- d'e-mails, compteurs, préférences, jetons push, présence en ligne.
  DELETE FROM public.notifications WHERE destinataire_id = ANY(v_ids) OR id_ressource = ANY(v_missions);
  DELETE FROM public.email_queue WHERE destinataire_id = ANY(v_ids);
  DELETE FROM public.rate_limits WHERE cle = ANY(v_ids::text[]);
  DELETE FROM public.preferences_notifications WHERE utilisateur_id = ANY(v_ids);
  DELETE FROM public.tokens_push WHERE utilisateur_id = ANY(v_ids);
  DELETE FROM public.presence_status WHERE user_id = ANY(v_ids);

  -- Fermeture des clés étrangères (GRAPHE_NETTOYAGE) : identifiants collectés des parents vers les enfants, puis
  -- suppression des enfants vers les parents.
  CREATE TEMP TABLE IF NOT EXISTS l5_ids (tbl text NOT NULL, id uuid NOT NULL, PRIMARY KEY (tbl, id)) ON COMMIT DROP;
  INSERT INTO l5_ids SELECT 'missions', x FROM unnest(v_missions) x;
  INSERT INTO l5_ids SELECT 'etablissements', ${u(e.id)} WHERE ${u(e.id)} IS NOT NULL;
  INSERT INTO l5_ids SELECT 'soignants', ${u(s.id)} WHERE ${u(s.id)} IS NOT NULL;
${fermeture.collecte}
  PERFORM set_config('jolene.sync_in_progress', 'true', true);
${fermeture.suppression}

  -- Dépendance inconnue : refus nominatif, rien n'est supprimé (rollback de toute la transaction).
  FOR fk IN SELECT c.conrelid::regclass AS enfant, c.confrelid::regclass AS parent, a.attname AS col
    FROM pg_constraint c JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = c.conkey[1]
    WHERE c.contype = 'f' AND cardinality(c.conkey) = 1 AND c.confdeltype NOT IN ('c', 'n', 'd')
      AND c.connamespace = 'public'::regnamespace AND c.conrelid <> 'public.journaux_audit'::regclass
      -- Parents supprimés juste après, dans cet ordre (missions → soignants → établissement) : une ligne étrangère qui les
      -- référencerait fait échouer leur DELETE, donc toute la transaction.
      AND c.conrelid NOT IN ('public.missions'::regclass, 'public.soignants'::regclass, 'public.etablissements'::regclass)
      AND c.confrelid IN ('public.missions'::regclass, 'public.etablissements'::regclass, 'public.soignants'::regclass, 'auth.users'::regclass)
  LOOP
    EXECUTE format('SELECT count(*) FROM %s WHERE %I = ANY($1)', fk.enfant, fk.col)
      INTO n USING CASE WHEN fk.parent = 'public.missions'::regclass THEN v_missions ELSE v_ids END;
    IF n > 0 THEN RAISE EXCEPTION 'Dépendance hors lot L5 : %.% → % (% ligne(s))', fk.enfant, fk.col, fk.parent, n; END IF;
  END LOOP;

  DELETE FROM public.missions WHERE id = ANY(v_missions);
  DELETE FROM public.soignants WHERE id = ${u(s.id)};
  DELETE FROM public.etablissements WHERE id = ${u(e.id)};
END $l5_clean$;
COMMIT;
SELECT true AS nettoye;`;
}

/** Objets marqués du run, lecture seule : tous à 0 après `nettoyer`. `journaux_audit` (immuable) n'est pas compté. */
export function sqlCompter(m) {
  const e = m.etablissement ?? {}, s = m.soignant ?? {};
  const lesMissions = `(SELECT coalesce(array_agg(id), '{}') FROM public.missions WHERE etablissement_id = ${u(e.id)}
      OR id = ANY(${missions(m)}) OR left(intitule, ${m.marker.length}) = ${q(m.marker)})`;
  return `SELECT
  (SELECT count(*)::integer FROM auth.users WHERE id = ANY(${ids(m)}) OR raw_app_meta_data->>'load_fixture_run' = ${q(m.runId)}
     AND raw_app_meta_data->>'load_fixture_kind' = ${q(KIND)}) AS auth,
  (SELECT count(*)::integer FROM public.etablissements WHERE id = ${u(e.id)} OR source_acquisition = ${q(m.marker)}) AS etablissements,
  (SELECT count(*)::integer FROM public.soignants WHERE id = ${u(s.id)} OR source_acquisition = ${q(m.marker)}) AS soignants,
  (SELECT count(*)::integer FROM public.missions WHERE id = ANY(${lesMissions})) AS missions,
  (SELECT count(*)::integer FROM public.mission_creneaux WHERE mission_id = ANY(${lesMissions})) AS creneaux,
  (SELECT count(*)::integer FROM public.candidatures WHERE mission_id = ANY(${lesMissions}) OR soignant_id = ${u(s.id)}) AS candidatures,
  (SELECT count(*)::integer FROM public.contrats_mission WHERE mission_id = ANY(${lesMissions}) OR etablissement_id = ${u(e.id)}
     OR soignant_id = ${u(s.id)}) AS contrats,
  (SELECT count(*)::integer FROM public.presences WHERE mission_id = ANY(${lesMissions}) OR soignant_id = ${u(s.id)}) AS presences,
  (SELECT count(*)::integer FROM public.scans_pointage WHERE mission_id = ANY(${lesMissions})) AS scans,
  (SELECT count(*)::integer FROM public.notations_missions WHERE mission_id = ANY(${lesMissions})) AS notations,
  (SELECT count(*)::integer FROM public.documents_soignants WHERE soignant_id = ${u(s.id)}) AS documents,
  (SELECT count(*)::integer FROM public.notifications WHERE destinataire_id = ANY(${ids(m)}) OR id_ressource = ANY(${lesMissions})) AS notifications,
  (SELECT count(*)::integer FROM public.membres_etablissement WHERE etablissement_id = ${u(e.id)} OR user_id = ANY(${ids(m)})) AS membres,
  (SELECT count(*)::integer FROM public.conversations WHERE etablissement_id = ${u(e.id)} OR soignant_id = ${u(s.id)}) AS conversations,
  (SELECT count(*)::integer FROM public.paiements_escrow WHERE mission_id = ANY(${lesMissions})) AS escrow,
  (SELECT count(*)::integer FROM public.preferences_notifications WHERE utilisateur_id = ANY(${ids(m)})) AS preferences;`;
}

/** Recherche, lecture seule, de la cohorte d'un run par son étiquette (aucun mot de passe, aucun jeton n'en sort). */
export function sqlRetrouverRun(runId) {
  if (!RUN.test(runId ?? '')) throw new Error('Étiquette de run L5 invalide.');
  const marker = `RECETTE-L5-${runId}`, emails = emailsDuRun(runId);
  return `SELECT
  (SELECT coalesce(jsonb_agg(jsonb_build_object('id', id, 'test', est_compte_test, 'email', email_contact) ORDER BY id), '[]'::jsonb)
     FROM public.etablissements WHERE nom = ${q(marker)} OR source_acquisition = ${q(marker)}) AS etablissements,
  (SELECT coalesce(jsonb_agg(jsonb_build_object('id', id, 'test', est_compte_test, 'email', email) ORDER BY id), '[]'::jsonb)
     FROM public.soignants WHERE email = ${q(emails.soignant)} OR source_acquisition = ${q(marker)}) AS soignants,
  (SELECT coalesce(jsonb_agg(jsonb_build_object('id', id, 'email', email, 'role', raw_app_meta_data->>'role',
       'run', raw_app_meta_data->>'load_fixture_run', 'kind', raw_app_meta_data->>'load_fixture_kind') ORDER BY id), '[]'::jsonb)
     FROM auth.users WHERE email IN (${q(emails.etablissement)}, ${q(emails.soignant)})
       OR (raw_app_meta_data->>'load_fixture_run' = ${q(runId)} AND raw_app_meta_data->>'load_fixture_kind' = ${q(KIND)})) AS auth;`;
}

/**
 * Cible de nettoyage d'un run retrouvé par étiquette. Refuse : plus d'un établissement ou d'un soignant, une ligne qui
 * n'est pas un compte TEST, une identité Auth d'un autre run, d'un autre rôle ou d'une autre adresse, un établissement
 * (propriétaire legacy) ou un soignant dont l'identifiant diffère de son compte Auth.
 */
export function cibleDepuisRecherche(runId, ligne) {
  if (!RUN.test(runId ?? '')) throw new Error('Étiquette de run L5 invalide.');
  const marker = `RECETTE-L5-${runId}`, emails = emailsDuRun(runId);
  const liste = v => (Array.isArray(v) ? v : null);
  const etabs = liste(ligne?.etablissements), soignants = liste(ligne?.soignants), auth = liste(ligne?.auth);
  if (!etabs || !soignants || !auth) throw new Error('Recherche du run L5 illisible : aucune suppression.');
  if (etabs.length > 1) throw new Error(`Plusieurs établissements portent l'étiquette ${marker} : aucune suppression.`);
  if (soignants.length > 1) throw new Error(`Plusieurs soignants correspondent au run ${runId} : aucune suppression.`);
  if ([...etabs, ...soignants].some(x => x?.test !== true || !UUID.test(String(x?.id)))) {
    throw new Error(`Ligne du run ${runId} sans compte TEST : aucune suppression.`);
  }
  if (etabs[0] && etabs[0].email !== emails.etablissement) throw new Error(`Établissement ${marker} sans l'adresse du run : aucune suppression.`);
  if (auth.length > 2) throw new Error(`Plus de deux identités Auth pour le run ${runId} : aucune suppression.`);
  const roles = { [emails.etablissement]: 'ETABLISSEMENT', [emails.soignant]: 'SOIGNANT' };
  for (const a of auth) {
    if (!UUID.test(String(a?.id)) || roles[a?.email] !== a?.role || a?.run !== runId || a?.kind !== KIND) {
      throw new Error(`Identité Auth hors du run ${runId} (adresse, rôle ou métadonnées) : aucune suppression.`);
    }
  }
  const authE = auth.find(a => a.role === 'ETABLISSEMENT'), authS = auth.find(a => a.role === 'SOIGNANT');
  if (etabs[0] && authE && etabs[0].id !== authE.id) throw new Error('Établissement et compte Auth du run L5 divergents : aucune suppression.');
  if (soignants[0] && authS && soignants[0].id !== authS.id) throw new Error('Soignant et compte Auth du run L5 divergents : aucune suppression.');
  return {
    runId, marker,
    etablissement: { id: etabs[0]?.id ?? authE?.id ?? null, email: emails.etablissement },
    soignant: { id: soignants[0]?.id ?? authS?.id ?? null, email: emails.soignant },
    auth: auth.map(a => ({ id: a.id, email: a.email })),
  };
}

export const COMPTES = ['auth', 'etablissements', 'soignants', 'missions', 'creneaux', 'candidatures', 'contrats', 'presences',
  'scans', 'notations', 'documents', 'notifications', 'membres', 'conversations', 'escrow', 'preferences'];

/** Total des objets marqués ; une colonne absente ou non entière n'est jamais un zéro. */
export function totalMarques(ligne) {
  let total = 0;
  for (const cle of COMPTES) {
    const n = ligne?.[cle];
    if (!Number.isInteger(n) || n < 0) throw new Error(`Compte L5 illisible (${cle}) : aucun zéro supposé.`);
    total += n;
  }
  return total;
}

/** Assertions des relectures ; renvoie la liste des écarts (vide si tout est conforme). */
export function validerRelectures(r) {
  const ecarts = [];
  const attendre = (cle, ok, attendu) => { if (!ok) ecarts.push(`${cle} : attendu ${attendu}, relu ${JSON.stringify(r?.[cle] ?? null)}`); };
  attendre('candidature_statut', r?.candidature_statut === 'ACCEPTEE', 'ACCEPTEE');
  attendre('candidature_traitee', r?.candidature_traitee === true, 'traite_le non nul');
  attendre('m1_statut', r?.m1_statut === 'ASSIGNEE', 'ASSIGNEE');
  attendre('m1_assignee_s1', r?.m1_assignee_s1 === true, 'soignant_assigne_id = S1');
  attendre('m1_contrats', Number.isInteger(r?.m1_contrats) && r.m1_contrats >= 1, 'au moins un contrat créé par l acceptation');
  attendre('m2_contrat_statut', r?.m2_contrat_statut === 'SIGNE_COMPLET', 'SIGNE_COMPLET');
  attendre('presence_validee', r?.presence_validee === true, 'presences.valide_par_etablissement = true');
  attendre('presence_valide_le', r?.presence_valide_le === true, 'valide_le non nul');
  attendre('m2_notations', Number.isInteger(r?.m2_notations) && r.m2_notations >= 1, 'une note ETAB_VERS_SOIGNANT');
  for (const cle of ['escrow', 'escrow_file', 'notifications_hors_cohorte', 'emails_cohorte', 'canaux_ouverts']) {
    attendre(cle, r?.[cle] === 0, '0');
  }
  return ecarts;
}

// MARK: - Exécution

export async function executer({ action, env = process.env, fetchImpl = fetch, log = console.log,
  attendre = ms => new Promise(r => setTimeout(r, ms)), maintenant = () => new Date(),
  genererMotDePasse = () => `Aa1!${randomBytes(36).toString('base64url')}` } = {}) {
  if (!ACTIONS.includes(action)) throw new Error(`Action L5 inconnue (attendu : ${ACTIONS.join(', ')}).`);
  verifierProjet(env); // verrou : avant tout appel réseau
  if (!env.STAGING_SUPABASE_ACCESS_TOKEN) throw new Error('STAGING_SUPABASE_ACCESS_TOKEN requis.');
  if (ECRITURES.has(action) && env.LOT5_STAGING_ECRITURE !== ECRITURE_APPROUVEE) {
    throw new Error(`Écriture STAGING L5 non approuvée : LOT5_STAGING_ECRITURE=${ECRITURE_APPROUVEE} requis (workflow seulement).`);
  }
  const masquer = v => { if (v) log(`::add-mask::${v}`); };

  const requete = async (url, { methode = 'GET', corps, cle, bearer, absent = false } = {}) => {
    if (!destinationAdmise(url)) throw new Error('Destination non admise par le verrou L5 : aucune requête.');
    let r;
    try {
      r = await fetchImpl(url, { method: methode, redirect: 'error', signal: AbortSignal.timeout(35_000),
        headers: { ...(cle ? { apikey: cle } : {}), Authorization: `Bearer ${bearer ?? cle}`, 'Content-Type': 'application/json' },
        ...(corps === undefined ? {} : { body: JSON.stringify(corps) }) });
    } catch {
      throw new Error('Réponse L5 ambiguë (réseau) : manifeste conservé, aucun réessai de mutation.');
    }
    if (absent && r.status === 404) return null;
    let json = null;
    try { json = await r.json(); } catch { json = null; }
    if (!r.ok) {
      // Seul un message métier borné est recopié (jamais de jeton ni d'en-tête).
      const message = typeof json?.message === 'string' ? json.message.slice(0, 200) : '';
      throw new Error(`Requête L5 refusée (HTTP ${Number(r.status) || 0})${message ? ` : ${message}` : ''}.`);
    }
    return json;
  };
  const jeton = env.STAGING_SUPABASE_ACCESS_TOKEN;
  const sql = async query => {
    const lignes = await requete(`${MANAGEMENT_URL}/database/query`, { methode: 'POST', corps: { query }, bearer: jeton });
    if (!Array.isArray(lignes)) throw new Error('Réponse SQL L5 illisible.');
    return lignes;
  };
  const cles = async () => {
    const liste = await requete(`${MANAGEMENT_URL}/api-keys?reveal=true`, { bearer: jeton });
    if (!Array.isArray(liste)) throw new Error('Clés STAGING illisibles.');
    const anon = liste.find(k => k?.name === 'anon')?.api_key;
    const service = liste.find(k => k?.name === 'service_role')?.api_key;
    const publishable = liste.find(k => k?.type === 'publishable' && /^sb_publishable_/.test(k?.api_key ?? ''))?.api_key;
    if (!anon || !service) throw new Error('Clés STAGING attendues absentes.');
    masquer(anon); masquer(service);
    return { anon, service, publishable };
  };

  if (action === 'acces') {
    if (!env.GITHUB_ENV) throw new Error('GITHUB_ENV requis.');
    const { publishable } = await cles();
    const cle = publishable ?? env.JOLENE_NATIVE_STAGING_PUBLISHABLE_KEY;
    if (!/^sb_publishable_[A-Za-z0-9_-]{16,}$/.test(cle ?? '')) throw new Error('Clé publishable STAGING absente ou invalide.');
    masquer(cle);
    appendFileSync(env.GITHUB_ENV, `JOLENE_STAGING_PUBLISHABLE_KEY=${cle}\n`);
    log('Clé publishable STAGING résolue (masquée) ; production exclue.');
    return { publishable: true };
  }

  /** Nettoyage d'une cible (manifeste ou étiquette) ; tout échec nomme la reprise par étiquette. */
  const nettoyerCible = async cible => {
    try {
      const { service } = await cles();
      const [sortie] = await sql(sqlNettoyer(cible));
      if (sortie?.nettoye !== true) throw new Error('Nettoyage SQL L5 non confirmé.');
      for (const attendu of cible.auth) {
        if (!attendu.id) continue;
        const url = `${STAGING_URL}/auth/v1/admin/users/${attendu.id}`;
        const u = await requete(url, { cle: service, absent: true });
        if (!u) continue;
        if (u.id !== attendu.id || u.email !== attendu.email || u.app_metadata?.load_fixture_run !== cible.runId
          || u.app_metadata?.load_fixture_kind !== KIND) throw new Error('Auth hors du run L5 : aucune suppression.');
        await requete(url, { methode: 'DELETE', cle: service, corps: { should_soft_delete: false } });
      }
      const [ligne] = await sql(sqlCompter(cible));
      const etat = { ...Object.fromEntries(COMPTES.map(c => [c, ligne?.[c]])), total: totalMarques(ligne) };
      if (etat.total !== 0) throw new Error(`objets marqués restants ${JSON.stringify(etat)}`);
      log(`Nettoyage L5 prouvé (run ${cible.runId}) : 0 objet marqué (${COMPTES.join(', ')}) ; journaux_audit conservés (immuables).`);
      return etat;
    } catch (e) {
      // Le manifeste disparaît avec le runner hébergé : la reprise passe par l'étiquette du run, jamais par lui.
      throw new Error(`Nettoyage L5 incomplet (run ${cible.runId}) : ${String(e?.message ?? e)} ; ${repriseDuRun(cible.runId)}.`);
    }
  };

  if (action === 'nettoyer_run') {
    const runId = String(env.LOT5_NETTOYER_RUN ?? '').trim();
    if (!RUN.test(runId)) throw new Error('LOT5_NETTOYER_RUN invalide : étiquette de run attendue (lettres, chiffres, tirets), aucune requête.');
    const [trouve] = await sql(sqlRetrouverRun(runId));
    const cible = cibleDepuisRecherche(runId, trouve);
    if (!cible.etablissement.id && !cible.soignant.id && !cible.auth.length) {
      const [ligne] = await sql(sqlCompter(cible));
      const total = totalMarques(ligne);
      if (total !== 0) throw new Error(`Run ${runId} introuvable par étiquette mais ${total} objet(s) marqué(s) : aucune suppression.`);
      log(`Run ${runId} : aucune cohorte trouvée, 0 objet marqué.`);
      return { total: 0, introuvable: true };
    }
    return nettoyerCible(cible);
  }

  const chemin = env.LOT5_MANIFEST;
  const entree = env.LOT5_XCUITEST_JSON;
  if (!chemin || !entree) throw new Error('LOT5_MANIFEST et LOT5_XCUITEST_JSON requis (fichiers privés du runner).');
  let doc;
  const enregistrer = () => writeFileSync(chemin, JSON.stringify(doc, null, 2) + '\n', { mode: 0o600 });
  const ecrireEntree = () => writeFileSync(entree, JSON.stringify({
    purpose: PURPOSE, projectRef: STAGING_REF, runId: doc.runId, marker: doc.marker,
    etablissement: { id: doc.etablissement.id, email: doc.etablissement.email, password: doc.etablissement.password },
    m1: { id: doc.m1.id, intitule: doc.m1.intitule }, m2: { id: doc.m2.id, intitule: doc.m2.intitule },
    candidatureId: doc.candidatureId, contratM2Id: doc.m2.contratId, codeSha256: doc.codeSha256, presenceId: doc.presenceId,
  }) + '\n', { mode: 0o600 });
  const lire = () => {
    try { doc = JSON.parse(readFileSync(chemin, 'utf8')); } catch { throw new Error('Manifeste L5 illisible.'); }
    validerManifeste(doc);
    for (const v of [doc.etablissement.email, doc.soignant.email, doc.etablissement.password, doc.soignant.password]) masquer(v);
  };
  const connecter = async (qui, anon) => {
    const s = await requete(`${STAGING_URL}/auth/v1/token?grant_type=password`, { methode: 'POST', cle: anon,
      corps: { email: doc[qui].email, password: doc[qui].password } });
    if (typeof s?.access_token !== 'string' || s.user?.id !== doc[qui].id) throw new Error(`Session ${qui} L5 non confirmée.`);
    masquer(s.access_token);
    return s.access_token;
  };
  const rpc = async (fonction, params, anon, jwt) =>
    requete(`${STAGING_URL}/rest/v1/rpc/${fonction}`, { methode: 'POST', cle: anon, bearer: jwt, corps: params });
  const codeActuel = async () => {
    const [ligne] = await sql(sqlCode(doc));
    if (!ligne || !/^\d{6}$/.test(ligne.code ?? '')) throw new Error('Code de pointage de M2 illisible.');
    masquer(ligne.code);
    return ligne;
  };
  const compter = async () => {
    const [ligne] = await sql(sqlCompter(doc));
    return { ...Object.fromEntries(COMPTES.map(c => [c, ligne?.[c]])), total: totalMarques(ligne) };
  };

  if (action === 'preparer') {
    if (existsSync(chemin)) throw new Error('Manifeste L5 déjà présent : aucune recréation.');
    doc = manifeste(runIdDepuis(env), maintenant());
    doc.etablissement.password = genererMotDePasse();
    doc.soignant.password = genererMotDePasse();
    if (doc.etablissement.password === doc.soignant.password || [doc.etablissement.password, doc.soignant.password]
      .some(p => typeof p !== 'string' || p.length < 32 || /[\r\n]/.test(p))) throw new Error('Deux mots de passe aléatoires distincts requis.');
    for (const v of [doc.etablissement.email, doc.soignant.email, doc.etablissement.password, doc.soignant.password]) masquer(v);
    mkdirSync(dirname(chemin), { recursive: true });
    // Tous les identifiants sont durables AVANT la première écriture distante.
    writeFileSync(chemin, JSON.stringify(doc, null, 2) + '\n', { flag: 'wx', mode: 0o600 });
    const { anon, service } = await cles();
    for (const [qui, role] of [['etablissement', 'ETABLISSEMENT'], ['soignant', 'SOIGNANT']]) {
      doc.auth[qui] = 'planned'; enregistrer();
      const u = await requete(`${STAGING_URL}/auth/v1/admin/users`, { methode: 'POST', cle: service, corps: {
        id: doc[qui].id, email: doc[qui].email, password: doc[qui].password, email_confirm: true,
        // E1 : propriétaire legacy, jamais d'etablissement_id dans app_metadata (repli user.id).
        app_metadata: { role, est_compte_test: true, is_test_playwright: true, load_fixture_kind: KIND, load_fixture_run: doc.runId } } });
      if (u?.id !== doc[qui].id || u?.app_metadata?.load_fixture_run !== doc.runId) throw new Error(`Auth ${qui} L5 créée non confirmée.`);
      doc.auth[qui] = 'created'; enregistrer();
    }
    const [seed] = await sql(sqlPreparer(doc));
    if (seed?.prepare !== true) throw new Error('Préparation SQL L5 non confirmée.');
    doc.status = 'seeded'; enregistrer();
    const jwtS1 = await connecter('soignant', anon);
    const reponse = await rpc('fn_postuler_mission', { p_mission_id: doc.m1.id, p_message: doc.marker, p_choix_contrat: 'SALARIE' }, anon, jwtS1);
    if (reponse && typeof reponse === 'object' && reponse.error) throw new Error(`Candidature de S1 refusée par le serveur : ${String(reponse.error).slice(0, 200)}`);
    const candidatures = await sql(sqlCandidature(doc));
    if (candidatures.length !== 1 || candidatures[0].statut !== 'EN_ATTENTE' || !UUID.test(candidatures[0].id)) {
      throw new Error('Candidature EN_ATTENTE de S1 sur M1 non relue.');
    }
    doc.candidatureId = candidatures[0].id;
    await connecter('etablissement', anon); // E1 se connecte (identifiants corrects, email confirmé), sans rien écrire
    const code = await codeActuel();
    if (code.statut !== 'ASSIGNEE' || code.prochain_type_scan !== 'OUVERTURE') throw new Error('M2 n est pas prête au pointage.');
    doc.codeSha256 = sha256(code.code);
    doc.status = 'prepared'; enregistrer(); ecrireEntree();
    log(`Cohorte L5 préparée (run ${doc.runId}) : E1 legacy, S1, M1 + candidature, M2 assignée (contrat signé, code actif) ; `
      + `créneau de M2 ${doc.m2.debut} → ${doc.m2.fin}.`);
    return { status: doc.status, m2: { debut: doc.m2.debut, fin: doc.m2.fin } };
  }

  if (!existsSync(chemin)) {
    if (action === 'nettoyer') { log('Aucun manifeste L5 : rien n a été créé, rien à nettoyer.'); return { skipped: true }; }
    throw new Error('Manifeste L5 absent.');
  }
  lire();

  if (action === 'compter') return compter();

  if (action === 'scanner') {
    if (doc.status !== 'prepared') throw new Error(`Scans L5 refusés : état ${doc.status}, attendu prepared.`);
    const { anon } = await cles();
    const avant = await codeActuel();
    // Le code change à chaque scan (correction 18) : la valeur montrée à la phase 1 doit être celle du serveur, inchangée.
    if (sha256(avant.code) !== doc.codeSha256 || avant.prochain_type_scan !== 'OUVERTURE') {
      throw new Error('Code de M2 modifié depuis la préparation : la comparaison de la phase 1 ne vaut plus.');
    }
    const jwt = await connecter('soignant', anon);
    const metadata = { id_terminal: `recette-l5-${doc.runId}` };
    await rpc('fn_scanner_code_pointage', { p_code: avant.code, p_metadata: metadata }, anon, jwt);
    await attendre(ECART_SCANS_MS);
    const milieu = await codeActuel();
    if (milieu.prochain_type_scan !== 'FERMETURE' || milieu.code === avant.code) throw new Error('Scan d arrivée de M2 non relu.');
    await rpc('fn_scanner_code_pointage', { p_code: milieu.code, p_metadata: metadata }, anon, await connecter('soignant', anon));
    const fin = new Date(doc.m2.fin).getTime() + 10_000;
    const reste = fin - maintenant().getTime();
    if (reste > 0) await attendre(reste); // validation possible seulement après la fin du créneau planifié
    const presences = await sql(sqlPresence(doc));
    if (presences.length !== 1 || !UUID.test(presences[0].id) || presences[0].arrivee !== true || presences[0].depart !== true
      || presences[0].validee !== false) throw new Error('Présence de S1 sur M2 non relue (arrivée, départ, non validée).');
    doc.presenceId = presences[0].id;
    doc.status = 'scanned'; enregistrer(); ecrireEntree();
    log('Scans d arrivée et de départ de M2 enregistrés sous le JWT de S1 ; présence à valider.');
    return { status: doc.status };
  }

  if (action === 'verifier') {
    const [relu] = await sql(sqlVerifier(doc));
    const ecarts = validerRelectures(relu);
    if (ecarts.length) throw new Error(`Relectures L5 non conformes :\n- ${ecarts.join('\n- ')}`);
    log('Relectures L5 conformes : candidature ACCEPTEE, M1 assignée, présence validée et notée, aucune ligne d escrow.');
    return { conforme: true };
  }

  // nettoyer : SQL d'abord (idempotent), puis comptes Auth, puis compte final exigé à 0.
  doc.status = 'cleanup-started'; enregistrer();
  const etat = await nettoyerCible({ ...doc, auth: ['etablissement', 'soignant'].map(qui => ({ id: doc[qui].id, email: doc[qui].email })) });
  doc.status = 'cleaned'; enregistrer();
  rmSync(entree, { force: true });
  return etat;
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  try {
    if (process.argv[2] === 'graphe') {
      // Hors réseau : régénère GRAPHE_NETTOYAGE depuis le dump du dépôt (à recopier dans ce fichier).
      const dump = readFileSync(new URL('../../supabase/schema/public.sql', import.meta.url), 'utf8');
      console.log(grapheNettoyage(dump).map(l => `  '${l}',`).join('\n'));
      process.exit(0);
    }
    const resultat = await executer({ action: process.argv[2] });
    console.log(JSON.stringify(resultat));
  } catch (e) {
    console.error(`::error::${String(e?.message ?? e).split('\n').join('%0A')}`);
    process.exitCode = 1;
  }
}
