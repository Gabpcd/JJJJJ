/**
 * Global setup Playwright — pré-nettoyage de l'état de test.
 *
 * Pourquoi AVANT le run et pas seulement en afterEach : quand un job CI est
 * annulé ou tué en plein vol (matrices superflues annulées, timeout…), les
 * afterEach ne s'exécutent jamais et laissent des missions de test orphelines
 * en prod. Une mission EN_COURS orpheline assignée au soignant test bloque
 * ensuite TOUTES les acceptations des runs suivants (chevauchement / repos
 * 11 h / plafond 48 h) — incident du 12/06/2026, run 27429495070.
 *
 * Chaque run démarre donc sur un état propre, quelle que soit la façon dont
 * le run précédent est mort. Sans clé service_role (run local sans env), le
 * setup se contente d'un avertissement : les tests qui en dépendent géreront.
 */
import { createClient } from '@supabase/supabase-js';
import {
  nettoyerSessionsPlaywright,
  reactiverSoignantPlaywright,
} from './helpers/nettoyage-sessions-playwright';
import { garantirEtablissementPlaywright } from './helpers/garantir-etablissement-playwright';

const PREFIXES = ['[playwright-test]%', '[pw-test%'];

/** Tables enfants de missions en FK NO ACTION — ordre de purge obligatoire. */
const ENFANTS_MISSION = [
  // Référence mission + contrat + document RIB sans ON DELETE CASCADE : doit
  // impérativement précéder contrats_mission et documents_soignants.
  'partages_rib',
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
  'stripe_transfers',
  'paiements_escrow',
  'swipes',
  'matching_scores',
  'candidatures',
];

export default async function globalSetup() {
  const url = process.env.SUPABASE_URL || process.env.E2E_SUPABASE_URL;
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !serviceKey) {
    console.warn('[global-setup] SUPABASE_URL/SERVICE_ROLE_KEY absents — pré-nettoyage sauté.');
    return;
  }

  const admin = createClient(url, serviceKey, { auth: { persistSession: false } });

  // Le test de suspension admin bannit volontairement le compte technique. Si
  // GitHub interrompt le worker avant son finally, le run suivant doit réparer
  // Auth ET le profil avant le moindre login.
  await reactiverSoignantPlaywright(admin);

  // Le compte établissement est une fixture CI fixe. Le recréer
  // automatiquement s'il a été supprimé évite qu'un état de recette externe
  // fasse échouer toute la suite avant le premier test.
  const etablissementPlaywrightId =
    await garantirEtablissementPlaywright(admin);

  // Un run interrompu ne passe pas par global-teardown. Purger ses anciennes
  // sessions avant toute autre requête empêche Auth/PostgREST de se saturer.
  await nettoyerSessionsPlaywright(admin, '2 hours');

  // 1. Missions de test orphelines (tous préfixes confondus)
  const orFiltre = PREFIXES.map((p) => `intitule.like.${p}`).join(',');
  const { data: missions, error } = await admin
    .from('missions')
    .select('id, intitule, soignant_assigne_id')
    .or(orFiltre)
    .limit(500);
  if (error) {
    throw new Error(`[global-setup] lecture missions impossible : ${error.message}`);
  }
  const ids = (missions ?? []).map((m: { id: string }) => m.id);
  if (ids.length > 0) {
    // Les files Stripe référencent l'escrow (et non directement la mission).
    // Elles doivent donc être supprimées avant paiements_escrow. Le périmètre
    // reste strictement celui des missions techniques préfixées ci-dessus.
    const { data: escrows, error: escrowsError } = await admin
      .from('paiements_escrow')
      .select('id')
      .in('mission_id', ids);
    if (escrowsError) {
      throw new Error(`[global-setup] lecture escrows impossible : ${escrowsError.message}`);
    }
    const escrowIds = (escrows ?? []).map((escrow: { id: string }) => escrow.id);
    if (escrowIds.length > 0) {
      for (const table of [
        'escrow_exposition_releases',
        'escrow_release_queue',
        'stripe_refunds_queue',
      ]) {
        const { error: escrowChildError } = await admin
          .from(table as never)
          .delete()
          .in('paiement_escrow_id', escrowIds);
        if (escrowChildError) {
          throw new Error(
            `[global-setup] purge ${table} impossible : ${escrowChildError.message}`,
          );
        }
      }
    }

    // messages_chat est enfant de conversations (FK conversation_id, pas de
    // mission_id direct). Il DOIT être purgé avant conversations, sinon le DELETE
    // conversations échoue (FK) et bloque en cascade la suppression des missions
    // → missions orphelines EN_COURS qui rebloquent les runs suivants (chevauchement).
    const { data: convs, error: conversationsError } = await admin
      .from('conversations')
      .select('id')
      .in('mission_id', ids);
    if (conversationsError) {
      throw new Error(
        `[global-setup] lecture conversations impossible : ${conversationsError.message}`,
      );
    }
    const convIds = (convs ?? []).map((c: { id: string }) => c.id);
    if (convIds.length > 0) {
      const { error: eMc } = await admin.from('messages_chat').delete().in('conversation_id', convIds);
      if (eMc) {
        throw new Error(`[global-setup] purge messages_chat impossible : ${eMc.message}`);
      }
    }
    const { error: notificationsRessourceError } = await admin
      .from('notifications')
      .delete()
      .in('id_ressource', ids);
    if (notificationsRessourceError) {
      throw new Error(
        `[global-setup] purge notifications par ressource impossible : ${notificationsRessourceError.message}`,
      );
    }
    const { error: notificationsLienError } = await admin
      .from('notifications')
      .delete()
      .in('lien', ids.map((id) => `/etablissement/missions/${id}`));
    if (notificationsLienError) {
      throw new Error(
        `[global-setup] purge notifications par lien impossible : ${notificationsLienError.message}`,
      );
    }
    for (const mission of missions ?? []) {
      if (mission.soignant_assigne_id && mission.intitule) {
        const { error: evaluationError } = await admin
          .from('notifications')
          .delete()
          .eq('destinataire_id', mission.soignant_assigne_id)
          .eq('type_destinataire', 'SOIGNANT')
          .eq('type', 'SYSTEM')
          .eq('titre', "⭐ Évaluez l'établissement")
          .eq('corps', `La mission "${mission.intitule}" est terminée. Laissez une évaluation.`)
          .eq('lien', '/soignant/evaluations');
        if (evaluationError) {
          throw new Error(
            `[global-setup] purge rappel évaluation ${mission.id} impossible : ${evaluationError.message}`,
          );
        }
      }
      const { error: emailQueueError } = await admin
        .from('email_queue')
        .delete()
        .contains('data', { mission_id: mission.id });
      if (emailQueueError) {
        throw new Error(
          `[global-setup] purge file email ${mission.id} impossible : ${emailQueueError.message}`,
        );
      }
    }
    for (const table of ENFANTS_MISSION) {
      const { error: e } = await admin.from(table).delete().in('mission_id', ids);
      if (e) {
        throw new Error(`[global-setup] purge ${table} impossible : ${e.message}`);
      }
    }
    const { error: eM } = await admin.from('missions').delete().in('id', ids);
    if (eM) {
      throw new Error(`[global-setup] purge missions impossible : ${eM.message}`);
    }
    const { count: missionsRestantes, error: verificationMissionsError } = await admin
      .from('missions')
      .select('id', { count: 'exact', head: true })
      .in('id', ids);
    if (verificationMissionsError || (missionsRestantes ?? 0) !== 0) {
      throw new Error(
        `[global-setup] vérification purge missions impossible : ${verificationMissionsError?.message || `${missionsRestantes} restante(s)`}`,
      );
    }
    console.log(`[global-setup] ${ids.length} mission(s) de test orpheline(s) purgée(s).`);
  }

  // Fixtures établissement sans compte Auth utilisées uniquement pour vérifier
  // la contrainte de tolérance GPS. Un worker tué avant son finally ne doit pas
  // laisser ces lignes techniques dans la base partagée.
  const { error: gpsFixturesError } = await admin
    .from('etablissements')
    .delete()
    .eq('est_compte_test', true)
    .like('email_contact', 'playwright-test-gps-%@jolene.app');
  if (gpsFixturesError) {
    throw new Error(`[global-setup] purge fixtures GPS impossible : ${gpsFixturesError.message}`);
  }

  // 2. Factures résiduelles du compte TECHNIQUE Playwright. Ce compte est
  //    distinct des comptes de démonstration/review : toutes ses données sont
  //    exclusivement créées par la CI. Une facture EMISE laissée par un run
  //    ancien déclenche légitimement le gel J+15 et fait ensuite échouer toutes
  //    les créations de missions du run suivant. On annule donc uniquement les
  //    factures impayées de ce compte technique, sans toucher aux données démo.
  const { data: facturesAnnulees, error: facturesError } = await admin
    .from('factures')
    .update({ statut: 'ANNULEE' })
    .eq('etablissement_id', etablissementPlaywrightId)
    .eq('statut', 'EMISE')
    .select('id');
  if (facturesError) {
    throw new Error(`[global-setup] neutralisation des factures Playwright impossible : ${facturesError.message}`);
  }
  if ((facturesAnnulees ?? []).length > 0) {
    console.log(`[global-setup] ${(facturesAnnulees ?? []).length} facture(s) technique(s) Playwright annulée(s).`);
  }

  // 3. État volatile du soignant test (quota super-likes du jour, swipes badges
  //    résiduels) — repart de zéro pour les tests de matching.
  const { data: soignant, error: soignantError } = await admin
    .from('soignants')
    .select('id')
    .eq('email', 'playwright-soignant@jolene.app')
    .maybeSingle();
  if (soignantError) {
    throw new Error(`[global-setup] lecture soignant Playwright impossible : ${soignantError.message}`);
  }
  if (soignant?.id) {
    for (const table of ['super_swipes_quota', 'swipes', 'badges_soignant', 'streaks_soignant']) {
      const { error: volatileError } = await admin
        .from(table as never)
        .delete()
        .eq('soignant_id', soignant.id);
      if (volatileError) {
        throw new Error(
          `[global-setup] purge ${table} Playwright impossible : ${volatileError.message}`,
        );
      }
    }
  }

  console.log('[global-setup] état de test prêt.');
}
