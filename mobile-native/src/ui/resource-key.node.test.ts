import assert from 'node:assert/strict';
import test from 'node:test';
import type { MissionReadContext, SoignantProfile } from '../data/types';
import { missionResourceKey } from './resource-key';

const context: MissionReadContext = {
  userId: 'soignant-test', email: 'soignant@example.invalid',
  profile: {
    id: 'soignant-test', profession: 'IDE', adresse_lat: 48.86, adresse_lng: 2.35,
    rayon_deplacement_km: 50, tous_documents_valides: true, type_contrat: 'CDD',
    types_contrat_acceptes: '["CDD","LIBERAL"]', type_exercice: 'MIXTE', taux_horaire_minimum: 25,
  },
};
const list = { kind: 'list' as const, filters: { typeContrat: 'TOUS' as const, ville: 'Paris' } };
const detail = { kind: 'detail' as const, id: 'mission-test' };

test('a refreshed equivalent profile retains list and detail resources', () => {
  const copy = { ...context, profile: Object.fromEntries(Object.entries(context.profile).reverse()) as unknown as SoignantProfile };
  assert.equal(missionResourceKey(1, context, list), missionResourceKey(1, copy, list));
  assert.equal(missionResourceKey(1, context, detail), missionResourceKey(1, copy, detail));
  assert.equal(missionResourceKey(1, context, list), missionResourceKey(1, copy, {
    kind: 'list', filters: { ville: 'Paris', typeContrat: 'TOUS' },
  }));
});

test('a profile visibility change invalidates both list and detail', () => {
  const changes: Partial<SoignantProfile>[] = [
    { profession: 'MEDECIN' }, { type_contrat: 'LIBERAL' },
    { types_contrat_acceptes: '["CDD"]' }, { type_exercice: 'SALARIE' },
    { adresse_lat: 43.6 }, { adresse_lng: 1.44 }, { rayon_deplacement_km: 10 },
    { tous_documents_valides: false }, { taux_horaire_minimum: 30 }, { id: 'other-profile' },
  ];
  for (const change of changes) {
    const revised = { ...context, profile: { ...context.profile, ...change } };
    assert.notEqual(missionResourceKey(1, context, list), missionResourceKey(1, revised, list), JSON.stringify(change));
    assert.notEqual(missionResourceKey(1, context, detail), missionResourceKey(1, revised, detail), JSON.stringify(change));
  }
});

test('identity, session, filter and mission boundaries have separate resources', () => {
  const original = missionResourceKey(1, context, list);
  assert.notEqual(original, missionResourceKey(2, context, list));
  assert.notEqual(original, missionResourceKey(1, { ...context, userId: 'other-user' }, list));
  assert.notEqual(original, missionResourceKey(1, { ...context, email: 'other@example.invalid' }, list));
  assert.notEqual(original, missionResourceKey(1, context, { kind: 'list', filters: { ...list.filters, ville: 'Lyon' } }));
  assert.notEqual(missionResourceKey(1, context, detail), missionResourceKey(1, context, { kind: 'detail', id: 'other-mission' }));
});
