import { describe, expect, it } from 'vitest';
import { navigationPathForEvent } from './pushNative';

describe('navigationPathForEvent', () => {
  it('refuse les liens externes et conserve les paramètres internes', () => {
    expect(navigationPathForEvent({ lien: 'https://evil.example/phishing' })).toBeNull();
    expect(navigationPathForEvent({ lien: '/soignant/missions?id=1#pointage' }))
      .toBe('/soignant/missions?id=1#pointage');
  });

  it('distingue les candidatures reçues des décisions', () => {
    expect(navigationPathForEvent({ type_evenement: 'CANDIDATURE_RECUE', mission_id: 'm1' }))
      .toBe('/etablissement/missions/m1');
    expect(navigationPathForEvent({ type_evenement: 'CANDIDATURE_ACCEPTEE', mission_id: 'm1' }))
      .toBe('/soignant/missions/m1');
  });

  it('route les annulations vers la bonne interface, même sans identifiant', () => {
    expect(navigationPathForEvent({ type_evenement: 'CANDIDATURE_ANNULEE_SOIGNANT' }, 'ADMIN_ETABLISSEMENT'))
      .toBe('/etablissement/missions');
    expect(navigationPathForEvent({ type_evenement: 'MISSION_ANNULEE_ETAB' }, 'SOIGNANT'))
      .toBe('/soignant/missions');
  });

  it('couvre les types réellement émis par les crons de mission et de DPAE', () => {
    expect(navigationPathForEvent({ type_evenement: 'MISSION_URGENTE', mission_id: 'm1' }, 'SOIGNANT'))
      .toBe('/soignant/missions/m1');
    expect(navigationPathForEvent({ type_evenement: 'MISSION_A_POURVOIR' }, 'SOIGNANT'))
      .toBe('/soignant/recherche-missions');
    expect(navigationPathForEvent({ type_evenement: 'RAPPEL_MISSION', mission_id: 'm1' }, 'SOIGNANT'))
      .toBe('/soignant/missions/m1');
    expect(navigationPathForEvent({ type_evenement: 'DPAE_NON_REGULARISEE_POINTAGE', contrat_id: 'c1' }, 'ADMIN_ETABLISSEMENT'))
      .toBe('/contrat/c1');
  });

  it('ignore le faux lien racine historique quand un type permet un fallback', () => {
    expect(navigationPathForEvent({ lien: '/', type_evenement: 'MISSION_ASSIGNEE' }, 'SOIGNANT'))
      .toBe('/soignant/missions');
    expect(navigationPathForEvent({ lien: '/' })).toBe('/');
  });

  it('route litiges et factures selon le rôle avec des routes existantes', () => {
    expect(navigationPathForEvent({ type_evenement: 'LITIGE_OUVERT', litige_id: 'l1' }, 'ADMIN_ETABLISSEMENT'))
      .toBe('/etablissement/litiges#l1');
    expect(navigationPathForEvent({ type_evenement: 'FACTURE_EMISE', facture_id: 'f1' }, 'ADMIN_ETABLISSEMENT'))
      .toBe('/etablissement/facturation/f1');
    expect(navigationPathForEvent({ type_evenement: 'FACTURE_EMISE' }, 'SOIGNANT'))
      .toBe('/soignant/mes-gains?tab=factures');
  });
});
