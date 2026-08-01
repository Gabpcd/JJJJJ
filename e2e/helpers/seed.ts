/**
 * Helpers de seed pour les tests E2E qui nécessitent des données préparées.
 *
 * Tous les seeds destructifs utilisent le préfixe `playwright-test-`. Les
 * comptes fixes `playwright-soignant@jolene.app` / `playwright-etab@jolene.app`
 * restent disponibles pour les parcours de démonstration, mais leurs données
 * métier et leurs documents ne doivent jamais être réécrits par ces helpers.
 *
 * Cleanup : `cleanupTestAccounts()` supprime les comptes éphémères en cascade
 * (FK supprime missions, candidatures, etc.). `resetTestAccount()` purge les
 * données mais garde les comptes fixes.
 */

import type { SupabaseClient } from '@supabase/supabase-js';
import { TEST_ACCOUNTS } from './auth';
import { adminClient, userClient, userIdByEmail } from './db';
import { isPgrst202EligibilityFallbackAllowed } from './liberal-eligibility-policy';
import {
  estBlocagePurgeTechniqueAttendu,
  estQuarantainePurgeAutorisee,
  preparerMissionTechniquePourPurge,
} from './cleanup-mission-test';

export type CaregiverProfession = 'IDE' | 'IADE' | 'IBODE' | 'SAGE_FEMME';
export type CaregiverExercise = 'SALARIE' | 'LIBERAL';

export interface EphemeralVerifiedCaregiver {
  id: string;
  email: string;
  password: string;
  profession: CaregiverProfession;
  typeExercice: CaregiverExercise;
  /**
   * Garantit les 3 200 h d'une fixture libérale via la preuve canonique.
   * `false` signale exclusivement le repli temporaire pré-déploiement.
   */
  ensureLiberalEligibility: () => Promise<boolean>;
  cleanup: () => Promise<void>;
}

const EPHEMERAL_CAREGIVER_EMAIL_PREFIX = 'playwright-test-caregiver-';

/**
 * Repli strictement E2E pour la PR qui tourne encore contre l'ancien purgeur
 * SQL de production. Sur une mission gelée, cet ancien purgeur annule toute sa
 * transaction au premier DELETE protégé (mission_creneaux) : ses suppressions
 * précédentes ne sont donc jamais conservées. Cette liste reprend l'ordre du
 * global-setup afin de détacher les fixtures soignants avant l'appel à la RPC.
 *
 * Elle n'est utilisée qu'après les contrôles stricts de
 * preparerMissionTechniquePourPurge (mission préfixée, établissement test et
 * tous les soignants liés marqués test).
 */
const ENFANTS_MISSION_AVANT_PURGE_RPC = [
  'conformite_travail',
  'cotisations_sociales',
  'bulletins_paie',
  'contrats_travail_missions',
  'contrats_mission',
  'rappels_contrat_travail',
  'scans_pointage',
  'presences',
  'codes_secours_mission',
  'qr_codes_mission',
  'messages_mission',
  'conversations',
  'swipes',
  'matching_scores',
  'candidatures',
] as const;

/**
 * Enfants directs d'une fixture soignant susceptibles de subsister si une
 * mission gelée reste volontairement en quarantaine jusqu'au déploiement SQL.
 * La validation id/email/est_compte_test de la fixture précède toujours cette
 * purge de secours.
 */
const ENFANTS_SOIGNANT_AVANT_PROFIL = [
  'partages_rib',
  'conformite_travail',
  'cotisations_sociales',
  'bulletins_paie',
  'contrats_travail_missions',
  'contrats_mission',
  'pauses_presence',
  'presences',
  'stripe_transfers',
  'paiements_escrow',
  'candidatures',
] as const;

/**
 * Seede l'éligibilité libérale uniquement sur un compte Playwright jetable.
 *
 * La RPC est la voie canonique après déploiement de la migration. Une PR est
 * toutefois testée contre le schéma de production encore pré-déploiement :
 * dans ce seul cas (`PGRST202`, fonction absente du cache PostgREST), on
 * rafraîchit les anciens champs dénormalisés. Toute autre erreur reste
 * bloquante afin de ne jamais masquer une régression de la RPC canonique.
 */
async function ensureEphemeralLiberalEligibility(
  fixture: Pick<EphemeralVerifiedCaregiver, 'id' | 'email' | 'typeExercice'>,
): Promise<boolean> {
  if (
    fixture.typeExercice !== 'LIBERAL'
    || !fixture.email.startsWith(EPHEMERAL_CAREGIVER_EMAIL_PREFIX)
  ) {
    throw new Error(
      `[fixture caregiver] seed libéral refusé hors fixture éphémère (${fixture.email})`,
    );
  }

  const admin = adminClient();
  const { data: profil, error: profilError } = await admin
    .from('soignants' as any)
    .select('id, email, est_compte_test, type_exercice')
    .eq('id', fixture.id)
    .maybeSingle();
  if (profilError) {
    throw new Error(
      `[fixture caregiver] contrôle du profil libéral impossible: ${profilError.message}`,
    );
  }
  const profilEphemere = profil as {
    id: string;
    email: string | null;
    est_compte_test: boolean | null;
    type_exercice: string | null;
  } | null;
  if (
    profilEphemere?.id !== fixture.id
    || profilEphemere.email !== fixture.email
    || profilEphemere.est_compte_test !== true
    || profilEphemere.type_exercice !== 'LIBERAL'
    || !profilEphemere.email.startsWith(EPHEMERAL_CAREGIVER_EMAIL_PREFIX)
  ) {
    throw new Error(
      `[fixture caregiver] identité libérale de fixture refusée pour ${fixture.id}`,
    );
  }

  const { error: rpcError } = await admin.rpc(
    'fn_test_seed_heures_externes_validees' as any,
    { p_soignant_id: fixture.id, p_heures: 3200 },
  );
  if (!rpcError) return true;
  if (rpcError.code !== 'PGRST202') {
    throw new Error(
      `[fixture caregiver] seed canonique des heures impossible: ${rpcError.code || 'RPC'} ${rpcError.message}`,
    );
  }

  if (!isPgrst202EligibilityFallbackAllowed()) {
    throw new Error(
      '[fixture caregiver] RPC canonique fn_test_seed_heures_externes_validees absente (PGRST202) ; repli interdit hors PR pré-déploiement explicite',
    );
  }

  // Compatibilité strictement temporaire avec la production avant migration.
  // Les prédicats du UPDATE répètent le garde-fou ci-dessus pour qu'aucun
  // compte de démonstration ou utilisateur réel ne puisse être modifié.
  const maintenant = new Date().toISOString();
  const { data: profilMisAJour, error: fallbackError } = await admin
    .from('soignants' as any)
    .update({
      heures_cumulees: 3200,
      eligible_conversion_3200h: true,
      validation_3200h_statut: 'VALIDEE',
      validation_3200h_le: maintenant,
    })
    .eq('id', fixture.id)
    .eq('email', fixture.email)
    .eq('est_compte_test', true)
    .eq('type_exercice', 'LIBERAL')
    .select('id')
    .maybeSingle();
  if (fallbackError || !profilMisAJour) {
    throw new Error(
      `[fixture caregiver] repli pré-déploiement refusé: ${fallbackError?.message || 'profil non éphémère'}`,
    );
  }
  return false;
}

/**
 * Seed non destructif des documents VÉRIFIÉS requis pour une mission salariée
 * ou libérale.
 * Ce helper refuse explicitement les comptes fixes : il ne peut écrire que sur
 * un profil éphémère `playwright-test-caregiver-*` marqué `est_compte_test`.
 */
export async function seedDocsRequisVerifie(
  soignantId: string,
  typeExercice: CaregiverExercise = 'SALARIE',
): Promise<void> {
  const admin = adminClient();
  const { data: sg, error: soignantError } = await admin
    .from('soignants' as any)
    .select('profession, email, est_compte_test, prenom, nom, date_naissance')
    .eq('id', soignantId)
    .maybeSingle();
  if (soignantError) {
    throw new Error(`[seed docs] lecture du soignant impossible: ${soignantError.message}`);
  }
  const profil = sg as {
    profession?: CaregiverProfession;
    email?: string;
    est_compte_test?: boolean;
    prenom?: string | null;
    nom?: string | null;
    date_naissance?: string | null;
  } | null;
  if (
    profil?.est_compte_test !== true
    || !profil.email?.startsWith(EPHEMERAL_CAREGIVER_EMAIL_PREFIX)
  ) {
    throw new Error(
      `[seed docs] écriture refusée hors fixture éphémère (${profil?.email || soignantId})`,
    );
  }
  const profession = profil.profession;
  if (!profession) {
    throw new Error(`[seed docs] profession absente pour le soignant ${soignantId}`);
  }
  const { data: requis, error: requisError } = await admin
    .from('documents_requis_par_profession' as any)
    .select('type_document, a_expiration')
    .eq('profession', profession)
    .eq('est_critique', true)
    .in('type_exercice_requis', [
      'TOUS',
      typeExercice === 'LIBERAL' ? 'LIBERAL_ONLY' : 'SALARIE_ONLY',
    ]);
  if (requisError) {
    throw new Error(`[seed docs] lecture des exigences impossible: ${requisError.message}`);
  }
  const exigencesBrutes = (requis as {
    type_document: string;
    a_expiration: boolean | null;
  }[] | null) ?? [];
  const typesIdentite = new Set(['CARTE_IDENTITE', 'PASSEPORT', 'TITRE_SEJOUR']);
  const identiteChoisie = ['CARTE_IDENTITE', 'PASSEPORT', 'TITRE_SEJOUR']
    .find((type) => exigencesBrutes.some((r) => r.type_document === type));
  const exigencesNormalisees = exigencesBrutes.filter((r) => (
    r.type_document !== 'RPPS_ADELI'
    && (!typesIdentite.has(r.type_document) || r.type_document === identiteChoisie)
  ));
  const exigences = Array.from(
    new Map(
      exigencesNormalisees.map((r) => [r.type_document, r] as const),
    ).values(),
  );
  if (exigences.length === 0) {
    throw new Error(
      `[seed docs] aucune exigence critique ${typeExercice.toLowerCase()} configurée pour ${profession}`,
    );
  }

  if (
    exigences.some(({ type_document: typeDocument }) => typesIdentite.has(typeDocument))
    && (!profil.prenom || !profil.nom || !profil.date_naissance)
  ) {
    throw new Error(`[seed docs] identité incomplète pour le soignant ${soignantId}`);
  }

  const { data: documentsExistants, error: existingError } = await admin
    .from('documents_soignants' as any)
    .select('id')
    .eq('soignant_id', soignantId)
    .limit(1);
  if (existingError) {
    throw new Error(`[seed docs] lecture des documents existants impossible: ${existingError.message}`);
  }
  if ((documentsExistants ?? []).length > 0) {
    throw new Error(`[seed docs] la fixture ${soignantId} n'est pas vierge`);
  }

  const verifieLe = new Date().toISOString();
  const { error: insertError } = await admin.from('documents_soignants' as any).insert(
    exigences.map(({ type_document: typeDocument, a_expiration: aExpiration }) => {
      const estIdentite = typesIdentite.has(typeDocument);
      const resultatIa = {
        fixture_e2e: true,
        profession_certifiee: profession,
        ...(estIdentite ? { date_naissance_extraite: profil.date_naissance } : {}),
      };
      return {
        soignant_id: soignantId,
        type_document: typeDocument,
        libelle: `Preuve E2E ${typeDocument}`,
        s3_bucket: 'jolene-documents',
        s3_cle: `${soignantId}/documents/e2e-${typeDocument}.pdf`,
        nom_fichier: `${typeDocument}.pdf`,
        type_mime: 'application/pdf',
        taille_octets: 1,
        statut_verification: 'VERIFIE',
        verifie_le: verifieLe,
        valide_depuis: verifieLe.slice(0, 10),
        est_critique: true,
        // NULL est traité comme expirant (fail-closed), jamais comme illimité.
        valide_jusqua: aExpiration === false ? null : '2100-12-31',
        resultat_ia: resultatIa,
        nom_extrait_ia: estIdentite ? profil.nom : null,
        prenom_extrait_ia: estIdentite ? profil.prenom : null,
        coherence_nom: estIdentite ? true : null,
        score_confiance_ia: 0.99,
      };
    }),
  );
  if (insertError) {
    throw new Error(`[seed docs] création des documents vérifiés impossible: ${insertError.message}`);
  }

  const { data: documentsOk, error: controleError } = await admin.rpc(
    'fn_documents_ok_pour_mission' as any,
    { p_soignant_id: soignantId, p_type_contrat: typeExercice },
  );
  if (controleError || documentsOk !== true) {
    throw new Error(
      `[seed docs] gate ${typeExercice.toLowerCase()} non satisfait: ${controleError?.message || String(documentsOk)}`,
    );
  }
}

/**
 * Supprime une fixture soignant sans toucher aux comptes de démonstration.
 * Le nettoyage est idempotent et purge d'abord toutes les missions auxquelles
 * le soignant éphémère a participé, puis son profil et son compte Auth.
 */
export async function cleanupEphemeralVerifiedCaregiver(
  fixture: Pick<EphemeralVerifiedCaregiver, 'id' | 'email'>,
): Promise<void> {
  if (!fixture.email.startsWith(EPHEMERAL_CAREGIVER_EMAIL_PREFIX)) {
    throw new Error(`[cleanup caregiver] email non éphémère refusé: ${fixture.email}`);
  }

  const admin = adminClient();
  // Valider l'identité de la fixture AVANT la moindre suppression. Un mauvais
  // couple id/email ne doit jamais pouvoir purger les données d'un vrai compte
  // dans la base partagée. Si le profil n'a pas encore été créé (setup partiel),
  // la source de vérité de repli est le compte Auth lui-même.
  const { data: profilInitial, error: profilInitialError } = await admin
    .from('soignants' as any)
    .select('email, est_compte_test')
    .eq('id', fixture.id)
    .maybeSingle();
  if (profilInitialError) {
    throw new Error(`[cleanup caregiver] validation du profil impossible: ${profilInitialError.message}`);
  }
  if (profilInitial) {
    const profilValide = profilInitial as { email: string | null; est_compte_test: boolean | null };
    if (
      profilValide.est_compte_test !== true
      || profilValide.email !== fixture.email
      || !profilValide.email.startsWith(EPHEMERAL_CAREGIVER_EMAIL_PREFIX)
    ) {
      throw new Error(`[cleanup caregiver] identité de fixture refusée pour ${fixture.id}`);
    }
  } else {
    const { data: authData, error: authReadError } = await admin.auth.admin.getUserById(fixture.id);
    if (authReadError && !/not found/i.test(authReadError.message)) {
      throw new Error(`[cleanup caregiver] validation Auth impossible: ${authReadError.message}`);
    }
    if (!authData.user) return;
    if (
      authData.user.email !== fixture.email
      || !authData.user.email.startsWith(EPHEMERAL_CAREGIVER_EMAIL_PREFIX)
      || authData.user.app_metadata?.role !== 'SOIGNANT'
    ) {
      throw new Error(`[cleanup caregiver] identité Auth de fixture refusée pour ${fixture.id}`);
    }
  }

  const erreurs: string[] = [];
  const missionIds = new Set<string>();
  const { data: missionsAssignees, error: missionsError } = await admin
    .from('missions' as any)
    .select('id')
    .eq('soignant_assigne_id', fixture.id);
  if (missionsError) erreurs.push(`lecture missions: ${missionsError.message}`);
  for (const mission of (missionsAssignees ?? []) as Array<{ id: string }>) {
    missionIds.add(mission.id);
  }

  const { data: candidatures, error: candidaturesError } = await admin
    .from('candidatures' as any)
    .select('mission_id')
    .eq('soignant_id', fixture.id);
  if (candidaturesError) erreurs.push(`lecture candidatures: ${candidaturesError.message}`);
  for (const candidature of (candidatures ?? []) as Array<{ mission_id: string }>) {
    missionIds.add(candidature.mission_id);
  }

  for (const missionId of missionIds) {
    try {
      await cleanupMissionCascade(missionId);
    } catch (error) {
      erreurs.push(
        `purge mission ${missionId}: ${error instanceof Error ? error.message : String(error)}`,
      );
    }
  }

  // Une mission gelée peut rester en quarantaine sur le backend pré-
  // déploiement, mais aucun de ses enfants ne doit conserver le compte
  // Playwright. Cette seconde passe est volontairement liée au soignant :
  // elle couvre aussi un cleanup mission interrompu entre deux DELETE.
  for (const table of ENFANTS_SOIGNANT_AVANT_PROFIL) {
    const { error } = await admin
      .from(table as any)
      .delete()
      .eq('soignant_id', fixture.id);
    if (error) erreurs.push(`purge ${table}: ${error.message}`);
  }

  for (const [table, colonne] of [
    ['notifications', 'destinataire_id'],
    ['email_queue', 'destinataire_id'],
    ['emails_envoyes', 'destinataire_id'],
    ['evenements_score_soignant', 'soignant_id'],
    // Le recalcul canonique des heures initialise désormais cette ligne dès
    // qu'une mission de la fixture est clôturée. La supprimer avant le profil
    // évite de laisser des comptes Playwright orphelins, sans jamais toucher
    // aux comptes fixes de démonstration.
    ['suivi_conversion_3200h', 'soignant_id'],
  ] as const) {
    const { error } = await admin.from(table as any).delete().eq(colonne, fixture.id);
    if (error) erreurs.push(`purge ${table}: ${error.message}`);
  }

  const { data: profil, error: profilReadError } = await admin
    .from('soignants' as any)
    .select('email')
    .eq('id', fixture.id)
    .maybeSingle();
  if (profilReadError) {
    erreurs.push(`lecture profil: ${profilReadError.message}`);
  } else if (profil && (profil as { email: string }).email !== fixture.email) {
    throw new Error(`[cleanup caregiver] identité de fixture incohérente pour ${fixture.id}`);
  }

  const { error: documentsError } = await admin
    .from('documents_soignants' as any)
    .delete()
    .eq('soignant_id', fixture.id);
  if (documentsError) erreurs.push(`purge documents: ${documentsError.message}`);

  let profilSupprime = profil === null;
  if (!profilSupprime) {
    const { error: profilDeleteError } = await admin
      .from('soignants' as any)
      .delete()
      .eq('id', fixture.id);
    if (profilDeleteError) {
      erreurs.push(`purge profil: ${profilDeleteError.message}`);
    } else {
      const { data: profilRestant, error: verificationError } = await admin
        .from('soignants' as any)
        .select('id')
        .eq('id', fixture.id)
        .maybeSingle();
      if (verificationError) {
        erreurs.push(`vérification purge profil: ${verificationError.message}`);
      } else {
        profilSupprime = profilRestant === null;
        if (!profilSupprime) erreurs.push('le profil existe encore après DELETE');
      }
    }
  }

  // Ne jamais supprimer Auth en laissant derrière lui un profil métier orphelin.
  if (profilSupprime) {
    const { error: authDeleteError } = await admin.auth.admin.deleteUser(fixture.id);
    if (authDeleteError && !/not found/i.test(authDeleteError.message)) {
      erreurs.push(`purge Auth: ${authDeleteError.message}`);
    }
  }

  if (erreurs.length > 0) {
    throw new Error(`[cleanup caregiver] ${erreurs.join(' | ')}`);
  }
}

/**
 * Crée un soignant vérifié jetable pour les flows DB/UI qui assignent une
 * mission. Le compte fixe de démonstration n'est jamais lu ni modifié.
 */
export async function createEphemeralVerifiedCaregiver(
  profession: CaregiverProfession = 'IDE',
  typeExercice: CaregiverExercise = 'SALARIE',
): Promise<EphemeralVerifiedCaregiver> {
  const admin = adminClient();
  const suffix = `${Date.now()}-${Math.random().toString(36).slice(2, 10)}`;
  const email = `${EPHEMERAL_CAREGIVER_EMAIL_PREFIX}${suffix}@jolene.app`;
  const password = `Playwright!${Math.random().toString(36).slice(2, 12)}Aa1`;
  const numeroRpps = Math.floor(Math.random() * 100_000_000_000)
    .toString()
    .padStart(11, '0');
  // Préfixe 13 chiffres + clé Luhn : évite de fabriquer un SIRET incohérent
  // même dans une fixture technique. Le verdict reste explicitement marqué
  // compte test et n'est jamais exposé aux utilisateurs réels.
  const siretPrefix = `${Date.now()}${Math.floor(Math.random() * 1_000_000)}`
    .replace(/\D/g, '')
    .slice(-13)
    .padStart(13, '9');
  const siretDigits = `${siretPrefix}0`.split('').map(Number);
  const luhnSum = siretDigits.reduce((sum, digit, index) => {
    const doubled = index % 2 === 0 ? digit * 2 : digit;
    return sum + (doubled > 9 ? doubled - 9 : doubled);
  }, 0);
  const siretLiberal = `${siretPrefix}${(10 - (luhnSum % 10)) % 10}`;

  const { data: authData, error: authError } = await admin.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    app_metadata: { role: 'SOIGNANT' },
    user_metadata: { prenom: 'Playwright', nom: 'Fixture', role: 'SOIGNANT' },
  });
  if (authError || !authData.user) {
    throw new Error(`[fixture caregiver] création Auth impossible: ${authError?.message || 'aucun user'}`);
  }

  const fixtureBase = { id: authData.user.id, email };
  const maintenant = new Date().toISOString();
  try {
    const { error: typeCompteError } = await admin
      .from('types_comptes_auth' as any)
      .insert({
        user_id: fixtureBase.id,
        type_compte: 'SOIGNANT',
        // Les deux valeurs doivent être identiques : le timestamp client de
        // finalisation peut sinon précéder le DEFAULT now() calculé côté DB.
        reserve_le: maintenant,
        finalise_le: maintenant,
      });
    if (typeCompteError) {
      throw new Error(`réservation du type de compte impossible: ${typeCompteError.message}`);
    }

    const { error: profilError } = await admin.from('soignants' as any).insert({
      id: fixtureBase.id,
      prenom: 'Playwright',
      nom: 'Fixture',
      email,
      date_naissance: '1990-01-01',
      profession,
      numero_rpps: numeroRpps,
      rpps_verifie: true,
      rpps_verifie_le: maintenant,
      rpps_profession_api: profession,
      rpps_nom_api: 'Fixture',
      rpps_prenom_api: 'Playwright',
      diplome_verifie: true,
      identite_verifiee: true,
      coherence_identite: 'COHERENT',
      type_exercice: typeExercice,
      statut_liberal: typeExercice === 'LIBERAL' ? 'ACTIF' : 'NON_LIBERAL',
      siret_liberal: typeExercice === 'LIBERAL' ? siretLiberal : null,
      siret_liberal_verifie: typeExercice === 'LIBERAL',
      siret_liberal_verifie_le: typeExercice === 'LIBERAL' ? maintenant : null,
      siret_liberal_coherence_identite: typeExercice === 'LIBERAL' ? true : null,
      siret_liberal_raison_sociale: typeExercice === 'LIBERAL'
        ? 'Playwright Fixture'
        : null,
      siret_liberal_source_verification: typeExercice === 'LIBERAL'
        ? 'REGISTRE_OFFICIEL'
        : null,
      statut_compte: 'ACTIF',
      est_compte_test: true,
      tous_documents_valides: false,
      score_fiabilite: 50,
      total_missions_annulees: 0,
      onboarding_etapes_completees: ['PROFIL', 'PROFESSION', 'DOCUMENTS'],
      onboarding_termine_le: maintenant,
    });
    if (profilError) {
      throw new Error(`création du profil impossible: ${profilError.message}`);
    }

    await seedDocsRequisVerifie(fixtureBase.id, typeExercice);

    const fixture: EphemeralVerifiedCaregiver = {
      ...fixtureBase,
      password,
      profession,
      typeExercice,
      ensureLiberalEligibility: async () => ensureEphemeralLiberalEligibility({
        ...fixtureBase,
        typeExercice,
      }),
      cleanup: async () => cleanupEphemeralVerifiedCaregiver(fixtureBase),
    };
    if (typeExercice === 'LIBERAL') {
      await fixture.ensureLiberalEligibility();
    }
    return fixture;
  } catch (error) {
    const setupMessage = error instanceof Error ? error.message : String(error);
    let cleanupMessage = '';
    try {
      await cleanupEphemeralVerifiedCaregiver(fixtureBase);
    } catch (cleanupError) {
      cleanupMessage = ` | cleanup également en échec: ${cleanupError instanceof Error ? cleanupError.message : String(cleanupError)}`;
    }
    throw new Error(
      `[fixture caregiver] setup impossible: ${setupMessage}${cleanupMessage}`,
    );
  }
}

/**
 * Signe le contrat par les deux vraies RPC, dans l'ordre métier obligatoire
 * soignant puis établissement, puis confirme l'état final en service_role.
 */
export async function seedContratMissionSigne(
  missionId: string,
  caregiver: Pick<EphemeralVerifiedCaregiver, 'id' | 'email' | 'password'>,
  clients: { caregiver?: SupabaseClient; etablissement?: SupabaseClient } = {},
): Promise<string> {
  const admin = adminClient();
  const { data: contrat, error: lectureError } = await admin
    .from('contrats_mission' as any)
    .select('id')
    .eq('mission_id', missionId)
    .eq('soignant_id', caregiver.id)
    .neq('statut', 'ANNULE')
    .order('cree_le', { ascending: false })
    .limit(1)
    .maybeSingle();
  if (lectureError || !contrat) {
    throw new Error(
      `[seed contrat] contrat introuvable: ${lectureError?.message || `${missionId}/${caregiver.id}`}`,
    );
  }

  const contratId = (contrat as { id: string }).id;
  const signature = 'data:image/png;base64,cGxheXdyaWdodA==';
  const caregiverClient = clients.caregiver
    ?? await userClient(caregiver.email, caregiver.password);
  const { data: signatureSoignant, error: signatureSoignantError } = await caregiverClient.rpc(
    'fn_signer_contrat_soignant' as any,
    { p_contrat_id: contratId, p_signature_image: signature },
  );
  if (signatureSoignantError || (signatureSoignant as any)?.success !== true) {
    throw new Error(
      `[seed contrat] signature soignant impossible: ${signatureSoignantError?.message || (signatureSoignant as any)?.error || JSON.stringify(signatureSoignant)}`,
    );
  }

  const etablissementClient = clients.etablissement
    ?? await userClient(TEST_ACCOUNTS.etab.email, TEST_ACCOUNTS.etab.password);
  const { data: signatureEtab, error: signatureEtabError } = await etablissementClient.rpc(
    'fn_signer_contrat_etablissement' as any,
    { p_contrat_id: contratId, p_signature_image: signature },
  );
  if (signatureEtabError || (signatureEtab as any)?.success !== true) {
    throw new Error(
      `[seed contrat] signature établissement impossible: ${signatureEtabError?.message || (signatureEtab as any)?.error || JSON.stringify(signatureEtab)}`,
    );
  }

  const { data: signe, error: signatureError } = await admin
    .from('contrats_mission' as any)
    .select('id, statut, signature_soignant, signature_etablissement')
    .eq('id', contratId)
    .single();
  if (
    signatureError
    || !signe
    || (signe as { statut?: string }).statut !== 'SIGNE_COMPLET'
    || (signe as { signature_soignant?: boolean }).signature_soignant !== true
    || (signe as { signature_etablissement?: boolean }).signature_etablissement !== true
  ) {
    throw new Error(`[seed contrat] état final incohérent: ${signatureError?.message || 'signatures incomplètes'}`);
  }
  return (signe as { id: string }).id;
}

/** Crée une mission OUVERTE pour le compte étab test. */
export async function seedMission(opts: {
  intitule?: string;
  profession?: string;
  debut?: Date;
  fin?: Date;
  tauxHoraire?: number;
  typeContratRecherche?: 'SALARIE' | 'LIBERAL' | 'TOUS';
} = {}): Promise<{ id: string; etablissement_id: string } | null> {
  const etabId = await userIdByEmail('playwright-etab@jolene.app');
  if (!etabId) return null;

  // J+7 à heure RONDE (06:00 UTC = 07h/08h Paris selon saison) : une mission
  // seedée à l'heure de lancement du run (ex. 22h19) est un tueur de
  // crédibilité si elle fuit en prod (échec de cleanup) — cf. Lot 6a.2.
  const debut = opts.debut || (() => { const d = new Date(Date.now() + 7 * 86400000); d.setUTCHours(6, 0, 0, 0); return d; })();
  const fin = opts.fin || new Date(debut.getTime() + 8 * 3600000); // 8h plus tard

  const { data: missionId, error } = await adminClient().rpc('fn_test_seed_mission' as any, {
    p_data: {
      etablissement_id: etabId,
      intitule: opts.intitule || `[playwright-test] Mission ${Date.now()}`,
      description: 'Mission générée par les tests Playwright',
      profession_requise: opts.profession || 'IDE',
      service: 'Test',
      debut_le: debut.toISOString(),
      fin_le: fin.toISOString(),
      duree_heures: 8,
      taux_horaire_base: opts.tauxHoraire || 25,
      statut: 'OUVERTE',
      type_contrat_recherche: opts.typeContratRecherche || 'SALARIE',
      mode_attribution: 'CANDIDATURE',
    },
  });

  if (error) {
    console.error('[seed] seedMission failed:', error.message);
    return null;
  }
  return { id: missionId as string, etablissement_id: etabId };
}

/** Crée une candidature, par défaut pour l'ancien compte test fixe. */
export async function seedCandidature(
  missionId: string,
  caregiverId?: string,
  typeContratChoisi: 'SALARIE' | 'LIBERAL' = 'SALARIE',
): Promise<{ id: string } | null> {
  const soignantId = caregiverId ?? await userIdByEmail('playwright-soignant@jolene.app');
  if (!soignantId) return null;

  const { data, error } = await adminClient()
    .from('candidatures' as any)
    .insert({
      mission_id: missionId,
      soignant_id: soignantId,
      statut: 'EN_ATTENTE',
      type_contrat_choisi: typeContratChoisi,
    })
    .select('id')
    .single();

  if (error) {
    console.error('[seed] seedCandidature failed:', error.message);
    return null;
  }
  return data as { id: string };
}

/**
 * Marque une mission comme TERMINEE (pour tester flow notation).
 *
 * @deprecated Neutralisé par le durcissement prod post-Sprint 17 :
 * fn_valider_transition_statut_mission rejette OUVERTE → TERMINEE direct,
 * dec_proteger_mission_soignant reverte soignant_assigne_id pour un caller
 * service_role (auth.uid() NULL) et fn_creer_notification raise
 * « Non authentifié ». Utiliser le cycle de vie réel à la place :
 * seedCandidature + fn_traiter_candidature ACCEPTEE via userClient étab,
 * puis transitions ASSIGNEE → EN_COURS → TERMINEE par l'étab
 * (cf. e2e/flows/pointage.spec.ts et notation.spec.ts).
 */
export async function markMissionTerminee(missionId: string): Promise<boolean> {
  const soignantId = await userIdByEmail('playwright-soignant@jolene.app');
  if (!soignantId) return false;

  const { error } = await adminClient().rpc('fn_test_update_mission' as any, {
    p_mission_id: missionId,
    p_data: { statut: 'TERMINEE', soignant_assigne_id: soignantId },
  });

  return !error;
}

/**
 * Purge ordonnée d'une mission seedée et de ses enfants en FK NO ACTION vers
 * missions (bulletin de paie, cotisations, conformité, contrats,
 * conversation…) créés par fn_traiter_candidature / la clôture TERMINEE.
 * Sans cette purge préalable, le DELETE missions échoue en silence
 * (pattern pointage.spec.ts / anti-triche-pointage.spec.ts).
 * Toute erreur remonte : un cleanup silencieusement incomplet polluerait la
 * base partagée et ferait échouer les suites suivantes.
 */
export async function cleanupMissionCascade(missionId?: string | null): Promise<void> {
  if (!missionId) return;
  // fn_test_purge_mission supprime dynamiquement TOUS les enfants FK (y compris
  // rappels_contrat_travail et messages_chat, que l'ancienne liste statique
  // oubliait) puis la mission, côté serveur. Sans ça le DELETE missions échouait
  // en silence → mission laissée ASSIGNÉE → test suivant en échec par chevauchement
  // sur le soignant de test partagé (run CI à 1 worker, donc en série).
  const admin = adminClient();
  const { data: mission, error: missionReadError } = await admin
    .from('missions' as any)
    .select('id, etablissement_id, soignant_assigne_id, intitule, fige_le, statut')
    .eq('id', missionId)
    .maybeSingle();
  if (missionReadError) {
    throw new Error(`[cleanup mission] lecture ${missionId}: ${missionReadError.message}`);
  }
  if (!mission) return;
  const intitule = String(mission.intitule ?? '');
  if (!intitule.startsWith('[pw-test:') && !intitule.startsWith('[playwright-test]')) {
    throw new Error(
      `[cleanup mission] refus de purger une mission non technique ${missionId} (${intitule || 'sans intitulé'})`,
    );
  }
  const preparation = await preparerMissionTechniquePourPurge(admin, mission);

  // La descendance financière a deux niveaux de FK : les trois files ci-dessous
  // doivent précéder paiements_escrow, lui-même enfant de la mission.
  const { data: escrows, error: escrowsReadError } = await admin
    .from('paiements_escrow' as any)
    .select('id')
    .eq('mission_id', missionId);
  if (escrowsReadError) {
    throw new Error(`[cleanup mission] lecture escrows ${missionId}: ${escrowsReadError.message}`);
  }
  const escrowIds = ((escrows ?? []) as Array<{ id: string }>).map((escrow) => escrow.id);
  if (escrowIds.length > 0) {
    for (const table of [
      'stripe_refunds_queue',
      'escrow_release_queue',
      'escrow_exposition_releases',
    ]) {
      const { error: escrowChildError } = await admin
        .from(table as any)
        .delete()
        .in('paiement_escrow_id', escrowIds);
      if (escrowChildError) {
        throw new Error(
          `[cleanup mission] purge ${table} ${missionId}: ${escrowChildError.message}`,
        );
      }
    }
  }
  for (const table of ['stripe_transfers', 'paiements_escrow']) {
    const { error: financialError } = await admin
      .from(table as any)
      .delete()
      .eq('mission_id', missionId);
    if (financialError) {
      throw new Error(
        `[cleanup mission] purge ${table} ${missionId}: ${financialError.message}`,
      );
    }
  }
  // partages_rib référence à la fois mission, contrat et document RIB sans
  // cascade. Le purgeur SQL générique parcourt les FK dans un ordre non garanti
  // et pouvait donc tenter contrats_mission avant partages_rib.
  const { error: partagesRibError } = await admin
    .from('partages_rib' as any)
    .delete()
    .eq('mission_id', missionId);
  if (partagesRibError) {
    throw new Error(`[cleanup mission] partages RIB ${missionId}: ${partagesRibError.message}`);
  }
  const { error: notificationsError } = await admin
    .from('notifications' as any)
    .delete()
    .eq('id_ressource', missionId);
  if (notificationsError) {
    throw new Error(`[cleanup mission] notifications ${missionId}: ${notificationsError.message}`);
  }
  // Certains triggers historiques n'attachent pas id_ressource. Le lien étab
  // reste spécifique à la mission et peut donc être purgé sans toucher aux
  // données de démonstration ni aux notifications d'une autre mission.
  const { error: notificationsLienError } = await admin
    .from('notifications' as any)
    .delete()
    .eq('lien', `/etablissement/missions/${missionId}`);
  if (notificationsLienError) {
    throw new Error(
      `[cleanup mission] notifications par lien ${missionId}: ${notificationsLienError.message}`,
    );
  }
  if (mission?.soignant_assigne_id && mission.intitule) {
    const { error: evaluationError } = await admin
      .from('notifications' as any)
      .delete()
      .eq('destinataire_id', mission.soignant_assigne_id)
      .eq('type_destinataire', 'SOIGNANT')
      .eq('type', 'SYSTEM')
      .eq('titre', "⭐ Évaluez l'établissement")
      .eq('corps', `La mission "${mission.intitule}" est terminée. Laissez une évaluation.`)
      .eq('lien', '/soignant/evaluations');
    if (evaluationError) {
      throw new Error(
        `[cleanup mission] rappel évaluation ${missionId}: ${evaluationError.message}`,
      );
    }
  }
  // La file email de fin de mission n'a pas de FK mission : la référence est
  // portée par data.mission_id. La supprimer avant le purgeur évite une file
  // technique persistante sur le compte établissement Playwright.
  const { error: emailQueueError } = await admin
    .from('email_queue' as any)
    .delete()
    .contains('data', { mission_id: missionId });
  if (emailQueueError) {
    throw new Error(`[cleanup mission] file email ${missionId}: ${emailQueueError.message}`);
  }

  // conversations a un enfant indirect sans mission_id. Il doit disparaître
  // avant la liste directe, sinon le DELETE conversations est bloqué.
  const { data: conversations, error: conversationsReadError } = await admin
    .from('conversations' as any)
    .select('id')
    .eq('mission_id', missionId);
  if (conversationsReadError) {
    throw new Error(
      `[cleanup mission] lecture conversations ${missionId}: ${conversationsReadError.message}`,
    );
  }
  const conversationIds = ((conversations ?? []) as Array<{ id: string }>).map(
    (conversation) => conversation.id,
  );
  if (conversationIds.length > 0) {
    const { error: messagesChatError } = await admin
      .from('messages_chat' as any)
      .delete()
      .in('conversation_id', conversationIds);
    if (messagesChatError) {
      throw new Error(
        `[cleanup mission] purge messages_chat ${missionId}: ${messagesChatError.message}`,
      );
    }
  }

  // Conserver l'ancienne RPC comme source de vérité pour supprimer la mission
  // elle-même. Les enfants directs sont toutefois purgés avant son appel : si
  // son unique blocage attendu est le planning gelé, la transaction annulée de
  // la RPC ne recrée plus de FK vers la fixture soignant.
  for (const table of ENFANTS_MISSION_AVANT_PURGE_RPC) {
    const { error: childError } = await admin
      .from(table as any)
      .delete()
      .eq('mission_id', missionId);
    if (childError) {
      throw new Error(
        `[cleanup mission] purge ${table} ${missionId}: ${childError.message}`,
      );
    }
  }
  const { error } = await admin
    .rpc('fn_test_purge_mission' as any, { p_mission_id: missionId });
  if (error) {
    if (
      preparation === 'QUARANTAINEE'
      && estQuarantainePurgeAutorisee()
      && estBlocagePurgeTechniqueAttendu(error)
    ) {
      console.warn(
        `[cleanup mission] ${missionId} reste en quarantaine jusqu'au déploiement du purgeur durable.`,
      );
      return;
    }
    throw new Error(`[cleanup mission] ${missionId}: ${error.message}`);
  }
}

/** Supprime toutes les données seedées par les helpers (cleanup test) */
export async function cleanupSeedData(): Promise<void> {
  const etabId = await userIdByEmail('playwright-etab@jolene.app');
  if (!etabId) return;

  // Cascade : missions étab test → candidatures, notations, etc.
  await adminClient()
    .from('missions' as any)
    .delete()
    .eq('etablissement_id', etabId)
    .like('intitule', '[playwright-test]%');
}

/**
 * Garde-fou : skip un test si compte test fixe pas seedé.
 *
 * Les comptes `playwright-soignant@jolene.app` et `playwright-etab@jolene.app`
 * sont seedés via la migration 20260503050000_playwright_seed_test_accounts.sql.
 * La présence des secrets SUPABASE_SERVICE_ROLE_KEY + PLAYWRIGHT_TEST_PASSWORD
 * en CI est la condition suffisante (la migration a été appliquée à la prod).
 *
 * On évite l'appel `auth.admin.listUsers()` qui peut échouer silencieusement
 * (pagination, timeout, rate limit) et créer de faux skips.
 */
export async function hasTestAccount(_role: 'SOIGNANT' | 'ADMIN_ETABLISSEMENT'): Promise<boolean> {
  return !!process.env.SUPABASE_SERVICE_ROLE_KEY && !!process.env.PLAYWRIGHT_TEST_PASSWORD;
}
