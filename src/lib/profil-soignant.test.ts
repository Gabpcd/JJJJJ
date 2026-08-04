import { describe, expect, it } from 'vitest';
import { calculerCompletionProfil } from './profil-soignant';

const profilBase = {
  prenom: 'Marie',
  nom: 'Lefèvre',
  date_naissance: '1990-01-01',
  telephone: '0612345678',
  profession: 'IDE',
  rpps_verifie: true,
  adresse_lat: 48.8566,
  adresse_lng: 2.3522,
  tous_documents_valides: false,
  identite_verifiee: false,
} as any;

describe('calculerCompletionProfil', () => {
  it('sépare le profil des documents et de la vérification d’identité', () => {
    const resume = calculerCompletionProfil(profilBase);

    expect(resume.total_items).toBe(7);
    expect(resume.items_remplis).toBe(7);
    expect(resume.pourcentage).toBe(100);
    expect(resume.est_complet).toBe(true);
    expect(resume.peut_candidater).toBe(true);
    expect(resume.items.map((item) => item.cle)).not.toContain('documents');
    expect(resume.items.map((item) => item.cle)).not.toContain('identite');
  });

  it('laisse l’adresse recommandée sans bloquer la candidature', () => {
    const resume = calculerCompletionProfil({
      ...profilBase,
      adresse_lat: null,
      adresse_lng: null,
    });

    expect(resume.pourcentage).toBe(86);
    expect(resume.peut_candidater).toBe(true);
    expect(resume.items_recommandes_manquants.map((item) => item.cle)).toEqual(['adresse']);
  });

  it('continue de bloquer lorsqu’une information obligatoire manque', () => {
    const resume = calculerCompletionProfil({ ...profilBase, telephone: null });

    expect(resume.peut_candidater).toBe(false);
    expect(resume.items_obligatoires_manquants.map((item) => item.cle)).toEqual(['telephone']);
  });
});
