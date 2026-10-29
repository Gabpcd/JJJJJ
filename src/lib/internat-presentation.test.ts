import { describe, it, expect } from 'vitest';
import { erreurChoixInternes, presentationInternat } from './internat-presentation';

describe('internat : la présentation ne crée pas une preuve', () => {
  it('ne transforme pas une déclaration médicale en interne vérifié', () => {
    expect(presentationInternat(null, true, 'MEDECIN')).toMatchObject({ label: 'Étudiant en médecine · statut à vérifier', tone: 'pending', specialite: null });
    expect(presentationInternat({ specialite_medicale: 'SM26', specialite_verifiee: true }, true, 'MEDECIN')?.tone).toBe('pending');
  });
  it('ne confond pas un étudiant AS avec le parcours interne', () => {
    expect(presentationInternat(null, true, 'AS')).toBeNull();
  });
  it('affiche la projection protégée même si la case déclarative est décochée', () => {
    expect(presentationInternat({ statut: 'VERIFIE', specialite_code: 'SM26', specialite_label: 'Spécialité fictive', valide_jusqua: '2027-10-01' }, false, 'MEDECIN'))
      .toMatchObject({ label: 'Interne · licence vérifiée', specialite: 'Spécialité fictive', validite: '2027-10-01' });
  });
  it('ne montre aucune spécialité comme autorisée sur un état en attente', () => {
    // Le marqueur peut provenir d'une simple déclaration d'études médicales,
    // avant toute preuve de troisième cycle ou de licence.
    expect(presentationInternat({ statut: 'A_VERIFIER', specialite_label: 'Déclaration libre' }, true, 'MEDECIN'))
      .toMatchObject({ label: 'Parcours médical · vérification requise', tone: 'pending', specialite: null });
  });
  it('refuse un état vérifié incomplet ou une fausse date', () => {
    for (const valide_jusqua of [null, '2027-02-30']) expect(presentationInternat({ statut: 'VERIFIE', specialite_code: 'SM26', specialite_label: 'Fictive', valide_jusqua })?.tone).toBe('pending');
  });
  it('expose explicitement une licence expirée', () => {
    expect(presentationInternat({ statut: 'EXPIRE', specialite_code: 'SM26', specialite_label: 'Fictive', valide_jusqua: '2026-01-01' })?.tone).toBe('expired');
  });
  it('respecte le statut serveur non concerné', () => {
    expect(presentationInternat({ statut: 'NON_CONCERNE' }, true, 'MEDECIN')).toBeNull();
  });
  it('exige une spécialité lorsque l’établissement choisit les internes', () => {
    expect(erreurChoixInternes('MEDECIN', false, '')).toBeNull();
    expect(erreurChoixInternes('MEDECIN', true, '')).toBeTruthy();
    expect(erreurChoixInternes('IDE', true, 'SM26')).toBeTruthy();
    expect(erreurChoixInternes('MEDECIN', true, 'SM26')).toBeNull();
  });
});
