import assert from 'node:assert/strict';
import test from 'node:test';
import { advancePresenceVisibility, reconcilePresencePresentation } from './transitions';
import type { ConfirmedPresenceScan, PresenceScanResult } from '../../workflows/presence/types';

const confirmed: ConfirmedPresenceScan = { kind: 'confirmed', attemptId: 'attempt-one', gps: 'not_requested', journalStatus: 'unverified',
  mission: { id: 'actual-mission-b', etablissement_id: 'establishment', soignant_assigne_id: 'caregiver', intitule: 'Mission B',
    service: null, statut: 'EN_COURS', debut_le: '2026-10-27T10:00:00Z', fin_le: '2026-10-27T18:00:00Z', nb_creneaux: 1 },
  proof: { id: 'proof-one', mission_id: 'actual-mission-b', soignant_id: 'caregiver', numero_scan: 1, type_scan: 'OUVERTURE',
    scanne_le: '2026-10-27T10:00:00Z', horodatage_arrondi: '2026-10-27T10:00:00Z', creneau_effectif_id: 'effective-one',
    validation_etab_requise: false, valide_par_etab: false },
  segment: { id: 'effective-one', mission_id: 'actual-mission-b', debut: '2026-10-27T10:00:00Z', fin: null, est_pause: false, type_creneau: 'EFFECTIF' },
  message: 'Arrivée enregistrée.' };
const uncertain = (attemptId = 'attempt-one'): PresenceScanResult => ({ kind: 'unconfirmed', attemptId, gps: 'not_requested',
  mission: null, proof: null, segment: null, message: 'Relecture indisponible.' });

test('a confirmed business result survives an uncertain read of the same attempt', () => {
  const display = reconcilePresencePresentation(confirmed, uncertain());
  assert.equal(display.result, confirmed);
  assert.equal(display.result.mission?.id, 'actual-mission-b');
  assert.ok(display.localReadWarning?.includes('reste enregistré'));
});
test('business confirmation is never copied to another attempt or invented for an initial uncertainty', () => {
  const other = uncertain('attempt-two');
  assert.equal(reconcilePresencePresentation(confirmed, other).result, other);
  assert.equal(reconcilePresencePresentation(null, uncertain()).result.kind, 'unconfirmed');
});
test('a new verified cleanup replaces the previous cleanup warning without losing the actual mission', () => {
  const recovered = { ...confirmed, journalStatus: 'cleared' as const };
  assert.deepEqual(reconcilePresencePresentation(confirmed, recovered), { result: recovered, localReadWarning: null });
});
test('inactive then active batched by React still invalidates operations and triggers a fresh read', () => {
  const initial = { active: true, revision: 0 };
  const inactive = advancePresenceVisibility(initial, false);
  const resumed = advancePresenceVisibility(inactive, true);
  assert.equal(resumed.active, initial.active);
  assert.equal(resumed.revision, 2);
  assert.notEqual(resumed, initial);
  assert.equal(advancePresenceVisibility(resumed, true), resumed);
});
