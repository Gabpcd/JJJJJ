import { test, expect } from '@playwright/test';
import { adminClient, userClient, userIdByEmail } from '../helpers/db';
import { TEST_ACCOUNTS } from '../helpers/auth';
import { seedMissionMatching } from '../helpers/seed-matching';
import { cleanupMissionCascade } from '../helpers/seed';

/**
 * Visibilité escrow ⚡ côté revenus soignant + verrous (gap verrouillé).
 * Cf. docs/SPEC_ESCROW_REVENUS_SOIGNANT.md.
 *
 * ⚠️ La DB E2E est la PROD PARTAGÉE (cf. playwright-e2e.yml : E2E_SUPABASE_URL =
 * projet prod). Trois conséquences qui dictent la robustesse de ce spec :
 *   1. Des résidus de runs antérieurs persistent (parfois mutés en REMBOURSE par
 *      la machinerie escrow). → nonce unique `RUN`, purge en amont, assertions
 *      en DELTA plutôt qu'en valeur absolue.
 *   2. Les présences sont gardées par `dec_fenetre_pointage` (rejet si pointage
 *      < début-30min). Un seed de présence exige donc une mission dont la fenêtre
 *      de pointage est OUVERTE → on rétro-date `debut_le` (l'antifraude, elle,
 *      est non bloquante et ignorée sans GPS).
 *   3. Les verrous (migrations 170000/180000) ne sont sur prod qu'APRÈS le merge
 *      de cette PR (règle 9.0 : DDL via CI deploy-supabase, pas MCP). → sonde de
 *      déploiement + skip honnête tant qu'ils ne sont pas déployés ; assertion
 *      réelle sur le run push-main post-merge.
 *
 * Invariants testés : part soignant seule (255 € pour honoraires_cents=25500,
 * JAMAIS le total 298,20 €), état par statut, pas de double-comptage avec
 * stripe_transfers, verrous (remboursement partiel pré-release + document de
 * santé) rejetés proprement.
 */

const SOIGNANT = TEST_ACCOUNTS.soignant;
const HONO = 25500;       // 255,00 € (part soignant, run #12)
const COMMISSION = 4320;  // 43,20 € (JAMAIS visible soignant)
const TOTAL = HONO + COMMISSION; // 29820 = 298,20 €

// Nonce unique par run → immunise les assertions contre les résidus prod.
const RUN = `${Date.now()}-${Math.floor(Math.random() * 1e6)}`;
const TAG = `[pw-test:escrow:${RUN}]`;

const seededMissions: string[] = [];
let VERROUS_DEPLOYED = false; // 170000/180000 en prod ? (déployés au merge de cette PR)

/**
 * Seed un escrow dans un `statut` donné sur une mission fraîche taguée `RUN`.
 * @param presence  si fourni, seede une présence (mission rétro-datée pour
 *   passer la fenêtre de pointage). `pointage` = départ pointé (travaillée),
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
  const soignantId = await userIdByEmail(SOIGNANT.email);
  if (!soignantId) throw new Error('seed: compte soignant test introuvable');

  // Mission au futur (J+7, heure ronde) : `dec_mission_passee` refuse toute
  // création dans le passé, et un seed daté « maintenant » trahirait la donnée
  // de test. Le début est explicite → on en dérive les pointages (fenêtre
  // ouverte). `fn_mes_paiements_escrow` ne lit que « départ pointé ou non » +
  // validation, jamais l'horloge absolue → un pointage au futur est valide.
  const debut = new Date(Date.now() + 7 * 86400000); debut.setUTCHours(6, 0, 0, 0);
  const mission = await seedMissionMatching({ intitule: `${TAG} ${statut} ${Date.now()}`, tauxHoraire: 30, debut: presence ? debut : undefined });
  if (!mission) throw new Error(`seed: mission KO (${statut})`);
  seededMissions.push(mission.id);

  const { error: eMaj } = await admin.from('missions')
    .update({ soignant_assigne_id: soignantId, type_contrat_applique: 'LIBERAL' })
    .eq('id', mission.id);
  if (eMaj) throw new Error(`seed: maj mission KO (${statut}) — ${eMaj.message}`);

  if (presence) {
    const arrivee = new Date(debut.getTime() + 5 * 60000);                          // début + 5 min (dans la fenêtre)
    const depart = presence.pointage ? new Date(debut.getTime() + 3 * 3600000) : null; // début + 3 h, > arrivée
    const { error: eP } = await admin.from('presences').insert({
      mission_id: mission.id, soignant_id: soignantId,
      pointage_arrivee_le: arrivee.toISOString(),
      pointage_depart_le: depart ? depart.toISOString() : null,
      valide_par_etablissement: presence.valide,
    });
    if (eP) throw new Error(`seed: présence KO (${statut}) — ${eP.message}`);
  }

  const { error: eE } = await admin.from('paiements_escrow').insert({
    mission_id: mission.id, etablissement_id: mission.etablissement_id, soignant_id: soignantId,
    montant_total_cents: TOTAL, commission_cents: COMMISSION, honoraires_cents: HONO,
    methode_debit: 'SEPA', statut, stripe_payment_intent_id: `pi_pwtest_${RUN}`, ...extra,
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
  const { data: escs } = await admin.from('paiements_escrow').select('id').eq('mission_id', id);
  const escIds = ((escs || []) as Array<{ id: string }>).map((e) => e.id);
  if (escIds.length) {
    await admin.from('stripe_refunds_queue').delete().in('paiement_escrow_id', escIds);
    await admin.from('escrow_release_queue').delete().in('paiement_escrow_id', escIds);
    await admin.from('escrow_exposition_releases').delete().in('paiement_escrow_id', escIds);
  }
  await admin.from('stripe_transfers').delete().eq('mission_id', id);
  await admin.from('paiements_escrow').delete().eq('mission_id', id);
  await admin.from('presences').delete().eq('mission_id', id);
  await cleanupMissionCascade(id);
}

test.beforeAll(async () => {
  const admin = adminClient();
  const soignantId = await userIdByEmail(SOIGNANT.email);

  // Purge des résidus escrow de TOUS les runs antérieurs (prod partagée) :
  // sinon les deltas / états sont pollués.
  const { data: oldMissions } = await admin.from('missions').select('id').like('intitule', '[pw-test:escrow%');
  for (const m of (oldMissions || []) as Array<{ id: string }>) await purgeMissionFull(admin, m.id);

  // Sonde de déploiement des verrous — SANS effet de bord : tente un INSERT
  // documents santé (verrou 180000, même PR que 170000). Rejet santé/CONFORMITE
  // = verrous déployés ; insert passé (pas de verrou) = ligne supprimée aussitôt.
  if (soignantId) {
    const { data: doc, error } = await admin.from('documents_soignants').insert({
      soignant_id: soignantId, type_document: 'VACCINATIONS',
      s3_cle: `pw-test/${RUN}/probe.pdf`, nom_fichier: 'probe.pdf', statut_verification: 'EN_ATTENTE',
    } as never).select('id').single();
    VERROUS_DEPLOYED = /santé|CONFORMITE/i.test(error?.message || '');
    if (!error && doc) await admin.from('documents_soignants').delete().eq('id', (doc as { id: string }).id);
  }
});

test.afterAll(async () => {
  const admin = adminClient();
  for (const id of seededMissions) await purgeMissionFull(admin, id);
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

  const soignant = await userClient(SOIGNANT.email, SOIGNANT.password);
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
  const soignant = await userClient(SOIGNANT.email, SOIGNANT.password);
  const admin = adminClient();
  const soignantId = await userIdByEmail(SOIGNANT.email);

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
  const tMission = await seedMissionMatching({ intitule: `${TAG} transfer ${Date.now()}`, tauxHoraire: 30 });
  if (!tMission || !soignantId) throw new Error('seed: mission transfer KO');
  seededMissions.push(tMission.id);
  const { error: eT } = await admin.from('stripe_transfers').insert({
    mission_id: tMission.id, soignant_id: soignantId, etablissement_id: tMission.etablissement_id,
    montant_total: 100, montant_commission: 0, montant_soignant: 100,
    statut: 'PAYE', transfere_le: new Date().toISOString(),
  } as never);
  if (eT) throw new Error(`seed: transfer KO — ${eT.message}`);
  const a3 = (await soignant.rpc('fn_mes_revenus_connect' as any)).data as { total: number };
  expect(a3.total).toBeCloseTo(a2.total + 100, 2);
});

test('VERROU escrow — remboursement partiel pré-release rejeté (escrow intact)', async () => {
  test.skip(!VERROUS_DEPLOYED, 'Verrou 170000 pas encore déployé en prod (s’applique au merge de cette PR).');
  const missionId = await seedEscrow('DEBITE'); // pré-release
  const admin = adminClient();
  const { data: esc } = await admin.from('paiements_escrow').select('id, honoraires_cents').eq('mission_id', missionId).single();

  const { error } = await admin.rpc('fn_escrow_rembourser' as any, {
    p_paiement_escrow_id: (esc as { id: string }).id,
    p_montant_honoraires_cts: Math.floor((esc as { honoraires_cents: number }).honoraires_cents / 2), // partiel
    p_annulation_totale: false,
  });
  expect(error).not.toBeNull(); // exception attendue
  expect(String(error?.message || '')).toMatch(/partielle indisponible avant release|Lot 13/i);

  // Escrow INTACT (toujours DEBITE, pas REMBOURSE).
  const { data: after } = await admin.from('paiements_escrow').select('statut').eq('mission_id', missionId).single();
  expect((after as { statut: string }).statut).toBe('DEBITE');
});

test('VERROU docs santé — INSERT VACCINATIONS rejeté', async () => {
  test.skip(!VERROUS_DEPLOYED, 'Verrou 180000 pas encore déployé en prod (s’applique au merge de cette PR).');
  const admin = adminClient();
  const soignantId = await userIdByEmail(SOIGNANT.email);
  // nom_fichier fourni (NOT NULL) → l'échec est SANS ambiguïté celui du trigger santé.
  const { error } = await admin.from('documents_soignants').insert({
    soignant_id: soignantId, type_document: 'VACCINATIONS',
    s3_cle: `pw-test/${RUN}/vacc.pdf`, nom_fichier: 'vacc.pdf', statut_verification: 'EN_ATTENTE',
  } as never);
  expect(error).not.toBeNull();
  expect(String(error?.message || '')).toMatch(/santé|CONFORMITE/i);
});
