// @vitest-environment node
import { describe, expect, it } from 'vitest';
import { CONTROLE_RPPS_SANS_SOURCE, presenterControleRpps } from './rpps-verification-provenance';

describe('Provenance du contrôle RPPS', () => {
  it('nomme explicitement le test de la réponse courante', () => {
    expect(presenterControleRpps('Mode test contrôlé')).toEqual({
      titre: 'Contrôle RPPS de test — aucune vérification officielle',
      source: 'Source : mode test contrôlé.',
    });
  });

  it('nomme l’Annuaire Santé uniquement pour la source FHIR exacte', () => {
    expect(presenterControleRpps('FHIR Annuaire Santé v2')).toEqual({
      titre: 'RPPS vérifié dans l’Annuaire Santé',
      source: 'Source : Annuaire Santé (ANS).',
    });
  });

  it.each([undefined, null, '', 'ANS', 'FHIR Annuaire Santé v2 ', 'Mode test contrôlé ',
    '00100123456', true, { source: 'FHIR Annuaire Santé v2' }])(
    'conserve le libellé neutre pour une provenance absente ou inconnue : %j', source => {
      expect(presenterControleRpps(source)).toEqual(CONTROLE_RPPS_SANS_SOURCE);
      expect(presenterControleRpps(source).source).not.toContain('Annuaire Santé');
    },
  );
});
