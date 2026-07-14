import { test, expect } from '@playwright/test';
import type { SupabaseClient } from '@supabase/supabase-js';
import { adminClient, userClient } from '../helpers/db';
import { TEST_ACCOUNTS } from '../helpers/auth';
import {
  cleanupMissionCascade,
  createEphemeralVerifiedCaregiver,
  seedCandidature,
  seedContratMissionSigne,
  seedMission,
  type EphemeralVerifiedCaregiver,
} from '../helpers/seed';

/**
 * Visibilité escrow ⚡ côté revenus soignant + verrous (gap verrouillé).
 * Cf. docs/SPEC_ESCROW_REVENUS_SOIGNANT.md.
 *
 * ⚠️ La DB E2E est la PROD PARTAGÉE (cf. playwright-e2e.yml : E2E_SUPABASE_URL =
 * projet prod). Trois conséquences qui dictent la robustesse de ce spec :
 *   1. Des résidus de runs antérieurs persistent (parfois mutés en REMBOURSE par
 *      la machinerie escrow). → nonce unique `RUN`, purge en amont, assertions
 *      en DELTA plutôt qu'en valeur absolue.
 *   2. Un premier pointage exige désormais une mission ASSIGNEE, un contrat
 *      signé des deux côtés et les justificatifs du régime encore valides.
 *      Chaque seed passe donc par le vrai parcours candidature/acceptation/
 *      signatures avant d'insérer une présence dans sa fenêtre temporelle.
 *   3. Les verrous conformité sont obligatoires en production. La sonde santé
 *      échoue donc explicitement si le trigger attendu n'est pas actif ; le
 *      remboursement partiel est ensuite exercé sans aucun skip conditionnel.
 *
 * Invariants testés : part soignant seule (255 € pour honoraires_cents=25500,
 * JAMAIS le total 298,20 €), état par statut, pas de double-comptage avec
 * stripe_transfers, verrous (remboursement partiel pré-release + document de
 * santé) rejetés proprement.
 */

const HONO = 25500;       // 255,00 € (part soignant, run #12)
const COMMISSION = 4320;  // 43,20 € (JAMAIS visible soignant)
const TOTAL = HONO + COMMISSION; // 29820 = 298,20 €

// Nonce unique par run → immunise les assertions contre les résidus prod.
const RUN = `${Date.now()}-${Math.floor(Math.random() * 1e6)}`;
const TAG = `[pw-test:escrow:${RUN}]`;

const seededMissions: string[] = [];
let caregiver: EphemeralVerifiedCaregiver | undefined;
let etablissementClient: SupabaseClient | undefined;
let caregiverClient: SupabaseClient | undefined;
let missionSlot = 0;

// Les tests de ce fichier partagent une fixture soignante et comparent des
// deltas financiers. Ils doivent donc rester séquentiels, y compris quand un
// développeur lance Playwright localement avec plusieurs workers.
test.describe.configure({ mode: 'default', timeout: 120_000 });

function requireCaregiver(): EphemeralVerifiedCaregiver {
  if (!caregiver) throw new Error('seed: fixture soignante éphémère absente');
  return caregiver;
}

function requireEtablissementClient(): SupabaseClient {
  if (!etablissementClient) throw new Error('seed: client établissement absent');
  return etablissementClient;
}

function requireCaregiverClient(): SupabaseClient {
  if (!caregiverClient) throw new Error('seed: client soignante absent');
  return caregiverClient;
}

/**
 * Crée puis attribue une mission SAGE_FEMME libérale par le parcours métier
 * réel : candidature → acceptation authentifiée → contrat signé des 2 côtés.
 *
 * Chaque mission reçoit un créneau distinct espacé de 48 h : le trigger de
 * non-chevauchement et le repos de 11 h restent ainsi réellement exercés,
 * sans raccourci service_role ni mutation du compte de démonstration.
 */
async function seedMissionLiberaleAssignee(intitule: string): Promise<{
  id: string;
  etablissement_id: string;
  debut: Date;
}> {
  const fixture = requireCaregiver();
  const etab = requireEtablissementClient();
  const soignant = requireCaregiverClient();

  const debut = new Date(Date.now() + (8 + missionSlot * 2) * 86400000);
  missionSlot += 1;
  debut.setUTCHours(6, 0, 0, 0);
  const fin = new Date(debut.getTime() + 8 * 3600000);
  const mission = await seedMission({
    intitule,
    profession: 'SAGE_FEMME',
    debut,
    fin,
    tauxHoraire: 30,
    typeContratRecherche: 'LIBERAL',
  });
  if (!mission) throw new Error(`seed: mission KO (${intitule})`);
  // Enregistrer immédiatement l'ID garantit le cleanup même si une étape
  // métier ultérieure échoue.
  seededMissions.push(mission.id);

  const candidature = await seedCandidature(mission.id, fixture.id, 'LIBERAL');
  if (!candidature) throw new Error(`seed: candidature KO (${intitule})`);

  // Sur le schéma migré, cette RPC seede une vraie preuve externe validée.
  // Sur la production pré-déploiement, le helper n'autorise le repli cache
  // que si PostgREST confirme précisément que la RPC n'existe pas encore.
  const eligibilityIsCanonical = await fixture.ensureLiberalEligibility();
  const { data: acceptation, error: acceptationError } = await etab.rpc(
    'fn_traiter_candidature' as any,
    { p_candidature_id: candidature.id, p_decision: 'ACCEPTEE' },
  );
  if (
    acceptationError
    || (acceptation as any)?.success !== true
    || (acceptation as any)?.choix_applique !== 'LIBERAL'
  ) {
    throw new Error(
      `seed: acceptation libérale KO (${intitule}) — ${acceptationError?.message || (acceptation as any)?.error || JSON.stringify(acceptation)}`,
    );
  }

  if (eligibilityIsCanonical) {
    const { data: compteur, error: compteurError } = await adminClient()
      .from('soignants')
      .select('heures_cumulees')
      .eq('id', fixture.id)
      .single();
    expect(compteurError).toBeNull();
    expect(
      Number((compteur as { heures_cumulees: number | null } | null)?.heures_cumulees ?? 0),
      'une acceptation ne doit jamais effacer les heures externes canoniques',
    ).toBeGreaterThanOrEqual(3200);
  }

  await seedContratMissionSigne(mission.id, fixture, {
    caregiver: soignant,
    etablissement: etab,
  });

  const { data: assignee, error: assigneeError } = await adminClient()
    .from('missions')
    .select('statut, soignant_assigne_id, type_contrat_applique')
    .eq('id', mission.id)
    .single();
  if (
    assigneeError
    || (assignee as any)?.statut !== 'ASSIGNEE'
    || (assignee as any)?.soignant_assigne_id !== fixture.id
    || (assignee as any)?.type_contrat_applique !== 'LIBERAL'
  ) {
    throw new Error(
      `seed: état d'assignation incohérent (${intitule}) — ${assigneeError?.message || JSON.stringify(assignee)}`,
    );
  }

  return { ...mission, debut };
}

/**
 * Seed un escrow dans un `statut` donné sur une mission fraîche taguée `RUN`.
 * @param presence  si fourni, seede une présence sur le créneau de la mission
 *   légalement assignée et signée. `pointage` = départ pointé (travaillée),
 *   `valide` = validée par l'étab (→ non bloquante).
 * Toute erreur d'insert LÈVE (jamais d'échec silencieux : c'était la cause
 * racine des états manquants ATTENTE_VALIDATION / VERSEMENT_EN_COURS).
 */
async function seedEscrow(
  statut: string,
  extra: Record<string, unknown> = {},
  presence?: { pointage: boolean; valide: boolean },
): Promise<string> {
  const admin = adminClient();
  const fixture = requireCaregiver();
  const mission = await seedMissionLiberaleAssignee(`${TAG} ${statut} ${Date.now()}`);
  const { debut } = mission;

  // Le compte établissement E2E est en facturation mensuelle, sans moyen SEPA
  // auto : l'acceptation légale ne doit donc pas avoir créé un escrow réel.
  // Échouer explicitement protège le caractère déterministe de ce seed si la
  // configuration du compte change un jour.
  const { count: escrowAutomatique, error: escrowAutomatiqueError } = await admin
    .from('paiements_escrow')
    .select('id', { count: 'exact', head: true })
    .eq('mission_id', mission.id);
  if (escrowAutomatiqueError || escrowAutomatique !== 0) {
    throw new Error(
      `seed: escrow automatique inattendu (${statut}) — ${escrowAutomatiqueError?.message || escrowAutomatique}`,
    );
  }

  if (presence) {
    const arrivee = new Date(debut.getTime() + 5 * 60000);                          // début + 5 min (dans la fenêtre)
    const depart = presence.pointage ? new Date(debut.getTime() + 3 * 3600000) : null; // début + 3 h, > arrivée
    const { error: eP } = await admin.from('presences').insert({
      mission_id: mission.id, soignant_id: fixture.id,
      pointage_arrivee_le: arrivee.toISOString(),
      pointage_depart_le: depart ? depart.toISOString() : null,
      valide_par_etablissement: presence.valide,
    });
    if (eP) throw new Error(`seed: présence KO (${statut}) — ${eP.message}`);
  }

  const { error: eE } = await admin.from('paiements_escrow').insert({
    mission_id: mission.id, etablissement_id: mission.etablissement_id, soignant_id: fixture.id,
    montant_total_cents: TOTAL, commission_cents: COMMISSION, honoraires_cents: HONO,
    methode_debit: 'SEPA', statut,
    stripe_payment_intent_id: `pi_pwtest_${RUN}_${mission.id.replaceAll('-', '').slice(0, 12)}`,
    ...extra,
  });
  if (eE) throw new Error(`seed: escrow KO (${statut}) — ${eE.message}`);
  return mission.id;
}

/**
 * Purge complète d'une mission seedée : `fn_test_purge_mission` ne supprime PAS
 * les enfants `paiements_escrow` / `stripe_transfers` (FK
 * `paiements_escrow_mission_id_fkey` → le DELETE mission échoue en silence),
 * et `paiements_escrow` a lui-même 3 tables enfants FK (stripe_refunds_queue,
 * escrow_release_queue, escrow_exposition_releases — c'est la refunds_queue,
 * créée par fn_escrow_rembourser, qui bloquait la purge de la sonde en CI).
 * On retire donc TOUTE la descendance financière avant la cascade.
 */
async function purgeMissionFull(admin: ReturnType<typeof adminClient>, id: string): Promise<void> {
  const { data: escs, error: escrowsError } = await admin
    .from('paiements_escrow')
    .select('id')
    .eq('mission_id', id);
  if (escrowsError) throw new Error(`purge escrow: lecture ${id} — ${escrowsError.message}`);
  const escIds = ((escs || []) as Array<{ id: string }>).map((e) => e.id);
  if (escIds.length) {
    for (const table of [
      'stripe_refunds_queue',
      'escrow_release_queue',
      'escrow_exposition_releases',
    ] as const) {
      const { error } = await admin.from(table).delete().in('paiement_escrow_id', escIds);
      if (error) throw new Error(`purge escrow: ${table} ${id} — ${error.message}`);
    }
  }
  for (const table of ['stripe_transfers', 'paiements_escrow', 'presences'] as const) {
    const { error } = await admin.from(table).delete().eq('mission_id', id);
    if (error) throw new Error(`purge escrow: ${table} ${id} — ${error.message}`);
  }
  await cleanupMissionCascade(id);
}

test.beforeAll(async () => {
  const admin = adminClient();

  // Purge des résidus escrow de TOUS les runs antérieurs (prod partagée) :
  // sinon les deltas / états sont pollués.
  const { data: oldMissions } = await admin.from('missions').select('id').like('intitule', '[pw-test:escrow%');
  for (const m of (oldMissions || []) as Array<{ id: string }>) await purgeMissionFull(admin, m.id);

  // Fixture jetable dédiée à ce spec : le compte soignant de démonstration et
  // ses documents restent strictement intacts. SAGE_FEMME possède un cadre
  // libéral explicite pour la clinique privée du compte établissement E2E.
  caregiver = await createEphemeralVerifiedCaregiver('SAGE_FEMME', 'LIBERAL');
  etablissementClient = await userClient(
    TEST_ACCOUNTS.etab.email,
    TEST_ACCOUNTS.etab.password,
  );
  caregiverClient = await userClient(caregiver.email, caregiver.password);

  // Sonde fail-closed du verrou santé — SANS effet de bord : si l'INSERT passe,
  // sa ligne est supprimée avant de faire échouer la suite explicitement.
  const { data: doc, error } = await admin.from('documents_soignants').insert({
    soignant_id: caregiver.id, type_document: 'VACCINATIONS',
    s3_cle: `pw-test/${RUN}/probe.pdf`, nom_fichier: 'probe.pdf', statut_verification: 'EN_ATTENTE',
  } as never).select('id').single();
  if (!error && doc) {
    const { error: suppressionSondeError } = await admin
      .from('documents_soignants')
      .delete()
      .eq('id', (doc as { id: string }).id);
    if (suppressionSondeError) {
      throw new Error(
        `sonde conformité absente et cleanup impossible — ${suppressionSondeError.message}`,
      );
    }
    throw new Error('sonde conformité absente : INSERT VACCINATIONS accepté en production');
  }
  if (!/santé|CONFORMITE/i.test(error?.message || '')) {
    throw new Error(
      `sonde conformité ambiguë : ${error?.message || 'aucun rejet métier retourné'}`,
    );
  }
});

test.afterAll(async () => {
  const admin = adminClient();
  const erreurs: string[] = [];
  for (const id of new Set(seededMissions)) {
    try {
      await purgeMissionFull(admin, id);
    } catch (error) {
      erreurs.push(
        `mission ${id}: ${error instanceof Error ? error.message : String(error)}`,
      );
    }
  }
  try {
    await caregiver?.cleanup();
  } catch (error) {
    erreurs.push(
      `fixture caregiver: ${error instanceof Error ? error.message : String(error)}`,
    );
  } finally {
    caregiver = undefined;
    caregiverClient = undefined;
    etablissementClient = undefined;
  }
  if (erreurs.length > 0) {
    throw new Error(`[cleanup escrow] ${erreurs.join(' | ')}`);
  }
});

test('fn_mes_paiements_escrow — états soignant + part soignant seule (255 €, jamais le total)', async () => {
  await seedEscrow('INITIE');                                                   // → RESERVE
  await seedEscrow('DEBITE', {}, { pointage: true, valide: false });            // → ATTENTE_VALIDATION
  await seedEscrow('DISPONIBLE', { disponible_le: new Date().toISOString() }, { pointage: true, valide: true }); // → VERSEMENT_EN_COURS
  await seedEscrow('PAYE', { paye_le: new Date().toISOString() });              // → VERSE
  await seedEscrow('ECHOUE', { relance_prevue_le: new Date(Date.now() + 3 * 86400000).toISOString() }); // → RETARDE
  await seedEscrow('DISPUTE');                                                  // → LITIGE
  await seedEscrow('REMBOURSE');                                                // → ANNULE (pas de paye_le)
  await seedEscrow('REMBOURSE', { paye_le: new Date().toISOString() });         // → VERSE (absorption post-versement)

  const soignant = requireCaregiverClient();
  const { data, error } = await soignant.rpc('fn_mes_paiements_escrow' as any);
  expect(error).toBeNull();
  const lignes = (data as Array<Record<string, unknown>>).filter((l) => String(l.mission_intitule || '').includes(TAG));

  const etats = lignes.map((l) => l.etat).sort();
  expect(etats).toEqual(
    ['ANNULE', 'ATTENTE_VALIDATION', 'LITIGE', 'RESERVE', 'RETARDE', 'VERSE', 'VERSE', 'VERSEMENT_EN_COURS'].sort()
  );

  // Part soignant seule : honoraires 25500 cts partout, jamais le total 29820.
  for (const l of lignes) {
    expect(l.honoraires_cents).toBe(HONO);
    expect(l.honoraires_cents).not.toBe(TOTAL);
  }
  // Le REMBOURSE avec paye_le tombe en VERSE, sans paye_le en ANNULE.
  expect(lignes.some((l) => l.etat === 'VERSE')).toBeTruthy();
  expect(lignes.some((l) => l.etat === 'ANNULE')).toBeTruthy();
});

test('fn_mes_revenus_connect — escrow inclus (delta), sans double-comptage avec stripe_transfers', async () => {
  const soignant = requireCaregiverClient();
  const admin = adminClient();
  const fixture = requireCaregiver();

  // Assertions en DELTA autour de nos propres inserts → robustes aux résidus.
  const base = (await soignant.rpc('fn_mes_revenus_connect' as any)).data as { total: number; en_attente: number };

  // Un escrow PAYE (versé) → total += 255 (honoraires_cents/100, part soignant).
  await seedEscrow('PAYE', { paye_le: new Date().toISOString() });
  const a1 = (await soignant.rpc('fn_mes_revenus_connect' as any)).data as { total: number; en_attente: number };
  expect(a1.total).toBeCloseTo(base.total + 255, 2);

  // Un escrow in-flight (DEBITE) → en_attente += 255, total inchangé.
  await seedEscrow('DEBITE');
  const a2 = (await soignant.rpc('fn_mes_revenus_connect' as any)).data as { total: number; en_attente: number };
  expect(a2.en_attente).toBeCloseTo(a1.en_attente + 255, 2);
  expect(a2.total).toBeCloseTo(a1.total, 2);

  // Un stripe_transfer DISJOINT (mission sans escrow) s'ajoute +100 exactement
  // (modèles séparés, pas de double-compte escrow↔transfer).
  const tMission = await seedMissionLiberaleAssignee(`${TAG} transfer ${Date.now()}`);
  const { count: escrowsTransfer, error: escrowsTransferError } = await admin
    .from('paiements_escrow')
    .select('id', { count: 'exact', head: true })
    .eq('mission_id', tMission.id);
  expect(escrowsTransferError).toBeNull();
  expect(escrowsTransfer, 'la mission transfer doit rester disjointe de tout escrow').toBe(0);
  const { error: eT } = await admin.from('stripe_transfers').insert({
    mission_id: tMission.id, soignant_id: fixture.id, etablissement_id: tMission.etablissement_id,
    montant_total: 100, montant_commission: 0, montant_soignant: 100,
    statut: 'PAYE', transfere_le: new Date().toISOString(),
  } as never);
  if (eT) throw new Error(`seed: transfer KO — ${eT.message}`);
  const a3 = (await soignant.rpc('fn_mes_revenus_connect' as any)).data as { total: number };
  expect(a3.total).toBeCloseTo(a2.total + 100, 2);
});

test('VERROU escrow — remboursement partiel pré-release rejeté (escrow intact)', async () => {
  const missionId = await seedEscrow('DEBITE'); // pré-release
  const admin = adminClient();
  const { data: esc } = await admin.from('paiements_escrow').select('id, honoraires_cents').eq('mission_id', missionId).single();

  const { data, error } = await admin.rpc('fn_escrow_rembourser' as any, {
    p_paiement_escrow_id: (esc as { id: string }).id,
    p_montant_honoraires_cts: Math.floor((esc as { honoraires_cents: number }).honoraires_cents / 2), // partiel
    p_annulation_totale: false,
  });
  // Depuis le durcissement de finalisation des refunds, un refus métier est
  // renvoyé en JSON (transport RPC réussi) afin que l'UI puisse l'afficher
  // proprement. Le test historique attendait encore l'ancienne exception.
  expect(error).toBeNull();
  expect(data).toMatchObject({
    success: false,
    error: 'REMBOURSEMENT_PARTIEL_PRE_RELEASE_INDISPONIBLE',
    manual_resolution_required: true,
  });

  // Un rejet métier pré-release ne doit jamais mettre silencieusement un
  // remboursement en file d'attente.
  const { count: refundsEnFile, error: refundsEnFileError } = await admin
    .from('stripe_refunds_queue')
    .select('id', { count: 'exact', head: true })
    .eq('paiement_escrow_id', (esc as { id: string }).id);
  expect(refundsEnFileError).toBeNull();
  expect(refundsEnFile).toBe(0);

  // Escrow INTACT (toujours DEBITE, pas REMBOURSE).
  const { data: after } = await admin.from('paiements_escrow').select('statut').eq('mission_id', missionId).single();
  expect((after as { statut: string }).statut).toBe('DEBITE');
});

test('VERROU docs santé — INSERT VACCINATIONS rejeté', async () => {
  const admin = adminClient();
  const fixture = requireCaregiver();
  // nom_fichier fourni (NOT NULL) → l'échec est SANS ambiguïté celui du trigger santé.
  const { error } = await admin.from('documents_soignants').insert({
    soignant_id: fixture.id, type_document: 'VACCINATIONS',
    s3_cle: `pw-test/${RUN}/vacc.pdf`, nom_fichier: 'vacc.pdf', statut_verification: 'EN_ATTENTE',
  } as never);
  expect(error).not.toBeNull();
  expect(String(error?.message || '')).toMatch(/santé|CONFORMITE/i);
});
