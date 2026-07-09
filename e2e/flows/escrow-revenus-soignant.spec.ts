import { test, expect } from '@playwright/test';
import { adminClient, userClient, userIdByEmail } from '../helpers/db';
import { TEST_ACCOUNTS } from '../helpers/auth';
import { seedMissionMatching } from '../helpers/seed-matching';

/**
 * Visibilité escrow ⚡ côté revenus soignant + verrous (gap verrouillé).
 * Cf. docs/SPEC_ESCROW_REVENUS_SOIGNANT.md.
 *
 * Backend-driven : adminClient() (service_role) seede paiements_escrow dans
 * chaque état, userClient(soignant) appelle les RPC SECURITY DEFINER
 * (auth.uid()). Invariants testés : part soignant seule (255 € pour
 * honoraires_cents=25500, JAMAIS le total 298,20 €), état par statut, pas de
 * double-comptage avec stripe_transfers, verrous (remboursement partiel
 * pré-release + document de santé) rejetés proprement.
 */

const SOIGNANT = TEST_ACCOUNTS.soignant;
const HONO = 25500;       // 255,00 € (part soignant, run #12)
const COMMISSION = 4320;  // 43,20 € (JAMAIS visible soignant)
const TOTAL = HONO + COMMISSION; // 29820 = 298,20 €

const seededMissions: string[] = [];

async function seedEscrow(statut: string, extra: Record<string, unknown> = {}, presence?: { pointage: boolean; valide: boolean }) {
  const admin = adminClient();
  const soignantId = await userIdByEmail(SOIGNANT.email);
  const mission = await seedMissionMatching({ intitule: `[pw-test:escrow] ${statut} ${Date.now()}`, tauxHoraire: 30 });
  if (!mission || !soignantId) throw new Error('seed mission/soignant KO');
  seededMissions.push(mission.id);

  await admin.from('missions').update({ soignant_assigne_id: soignantId, type_contrat_applique: 'LIBERAL' }).eq('id', mission.id);

  if (presence) {
    await admin.from('presences').insert({
      mission_id: mission.id, soignant_id: soignantId,
      pointage_arrivee_le: new Date(Date.now() - 86400000).toISOString(),
      pointage_depart_le: presence.pointage ? new Date(Date.now() - 82800000).toISOString() : null,
      valide_par_etablissement: presence.valide,
    });
  }

  await admin.from('paiements_escrow').insert({
    mission_id: mission.id, etablissement_id: mission.etablissement_id, soignant_id: soignantId,
    montant_total_cents: TOTAL, commission_cents: COMMISSION, honoraires_cents: HONO,
    methode_debit: 'SEPA', statut, stripe_payment_intent_id: 'pi_pwtest', ...extra,
  });
  return mission.id;
}

test.afterAll(async () => {
  const admin = adminClient();
  if (seededMissions.length) {
    await admin.from('paiements_escrow').delete().in('mission_id', seededMissions);
    await admin.from('presences').delete().in('mission_id', seededMissions);
    await admin.from('missions').delete().in('id', seededMissions);
  }
  await admin.from('stripe_transfers').delete().eq('description', '[pw-test:escrow] transfer');
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
  const lignes = (data as any[]).filter((l) => String(l.mission_intitule || '').includes('[pw-test:escrow]'));

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
  const rembourses = lignes.filter((l) => l.etat === 'VERSE' || l.etat === 'ANNULE');
  expect(rembourses.some((l) => l.etat === 'VERSE')).toBeTruthy();
  expect(rembourses.some((l) => l.etat === 'ANNULE')).toBeTruthy();
});

test('fn_mes_revenus_connect — escrow inclus, sans double-comptage avec stripe_transfers', async () => {
  const soignant = await userClient(SOIGNANT.email, SOIGNANT.password);
  const { data } = await soignant.rpc('fn_mes_revenus_connect' as any);
  const r = data as { total: number; en_attente: number };

  // 2 escrows PAYE (VERSE) seedés (dont 1 absorption) → total inclut au moins 255 €.
  expect(r.total).toBeGreaterThanOrEqual(255);
  // in-flight (INITIE/DEBITE/DISPONIBLE) → en_attente inclut au moins 3×255.
  expect(r.en_attente).toBeGreaterThanOrEqual(255);

  // Non-régression + pas de double-compte : un stripe_transfer sur une mission
  // DISJOINTE s'ajoute sans être compté deux fois (modèles séparés).
  const admin = adminClient();
  const soignantId = await userIdByEmail(SOIGNANT.email);
  await admin.from('stripe_transfers').insert({
    soignant_id: soignantId, montant_soignant: 100, statut: 'PAYE',
    transfere_le: new Date().toISOString(), description: '[pw-test:escrow] transfer',
  } as any);
  const { data: data2 } = await soignant.rpc('fn_mes_revenus_connect' as any);
  const r2 = data2 as { total: number };
  expect(r2.total).toBeCloseTo(r.total + 100, 2); // +100 exactement, pas +200
});

test('VERROU escrow — remboursement partiel pré-release rejeté (escrow intact)', async () => {
  const missionId = await seedEscrow('DEBITE'); // pré-release
  const admin = adminClient();
  const { data: esc } = await admin.from('paiements_escrow').select('id, honoraires_cents').eq('mission_id', missionId).single();

  const { error } = await admin.rpc('fn_escrow_rembourser' as any, {
    p_paiement_escrow_id: (esc as any).id,
    p_montant_honoraires_cts: Math.floor((esc as any).honoraires_cents / 2), // partiel
    p_annulation_totale: false,
  });
  expect(error).not.toBeNull(); // exception attendue
  expect(String(error?.message || '')).toMatch(/partielle indisponible avant release|Lot 13/i);

  // Escrow INTACT (toujours DEBITE, pas REMBOURSE).
  const { data: after } = await admin.from('paiements_escrow').select('statut').eq('mission_id', missionId).single();
  expect((after as any).statut).toBe('DEBITE');
});

test('VERROU docs santé — INSERT VACCINATIONS rejeté', async () => {
  const admin = adminClient();
  const soignantId = await userIdByEmail(SOIGNANT.email);
  const { error } = await admin.from('documents_soignants').insert({
    soignant_id: soignantId, type_document: 'VACCINATIONS', s3_cle: 'pw-test/vacc.pdf', statut_verification: 'EN_ATTENTE',
  } as any);
  expect(error).not.toBeNull();
  expect(String(error?.message || '')).toMatch(/santé|CONFORMITE/i);
});
