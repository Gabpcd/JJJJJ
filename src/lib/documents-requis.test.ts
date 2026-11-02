import { describe, expect, it } from 'vitest';
import { documentValidePourExigence, filtrerDocumentsRequis } from './documents-requis';

// Cas reconstitués depuis `DocumentsSoignant.tsx` (filtre profession ×
// type_exercice et dispenses par registre) avant leur extraction, pour que le
// web et le port natif partagent les mêmes vecteurs.
const regle = (type_document: string, extra: Record<string, unknown> = {}) => ({
  id: `${type_document}-${String(extra.profession ?? 'IDE')}-${String(extra.type_exercice_requis ?? 'TOUS')}`,
  profession: 'IDE',
  type_document,
  est_critique: true,
  type_exercice_requis: 'TOUS',
  ...extra,
});

const REGLES_IDE = [
  regle('CARTE_IDENTITE'),
  regle('DIPLOME'),
  regle('RPPS_ADELI'),
  regle('AUTORISATION_EXERCICE', { est_critique: false }),
  regle('VACCINATIONS'),
  regle('MEDECINE_TRAVAIL'),
  regle('RCP_ASSURANCE', { type_exercice_requis: 'LIBERAL_ONLY' }),
  regle('ATTESTATION_URSSAF', { type_exercice_requis: 'LIBERAL_ONLY' }),
  regle('CASIER_JUDICIAIRE', { type_exercice_requis: 'SALARIE_ONLY' }),
];

const soignant = (extra: Record<string, unknown> = {}) => ({
  profession: 'IDE',
  type_exercice: 'SALARIE',
  rpps_verifie: false,
  adeli_verifie: false,
  ...extra,
});

const types = (regles: Array<{ type_document: string }>) => regles.map((r) => r.type_document);

describe('filtrerDocumentsRequis — profession et type_exercice', () => {
  it('ne garde que les règles de la profession du soignant, dans l’ordre reçu', () => {
    const regles = [
      regle('DIPLOME', { profession: 'KINE' }),
      regle('CARTE_IDENTITE'),
      regle('DIPLOME'),
      regle('CARTE_IDENTITE', { profession: 'AS' }),
    ];
    expect(filtrerDocumentsRequis(regles, soignant()).map((r) => r.id)).toEqual([
      'CARTE_IDENTITE-IDE-TOUS',
      'DIPLOME-IDE-TOUS',
    ]);
  });

  it('exclut les types remplacés par l’attestation sur l’honneur (TYPES_DOCUMENTS_EXCLUS_UPLOAD)', () => {
    const resultat = types(filtrerDocumentsRequis(REGLES_IDE, soignant({ type_exercice: 'MIXTE' })));
    expect(resultat).not.toContain('VACCINATIONS');
    expect(resultat).not.toContain('MEDECINE_TRAVAIL');
  });

  it('un MIXTE cumule les obligations SALARIE_ONLY et LIBERAL_ONLY', () => {
    expect(types(filtrerDocumentsRequis(REGLES_IDE, soignant({ type_exercice: 'MIXTE' })))).toEqual([
      'CARTE_IDENTITE',
      'DIPLOME',
      'RPPS_ADELI',
      'AUTORISATION_EXERCICE',
      'RCP_ASSURANCE',
      'ATTESTATION_URSSAF',
      'CASIER_JUDICIAIRE',
    ]);
  });

  it('un LIBERAL a les LIBERAL_ONLY sans les SALARIE_ONLY', () => {
    expect(types(filtrerDocumentsRequis(REGLES_IDE, soignant({ type_exercice: 'LIBERAL' })))).toEqual([
      'CARTE_IDENTITE',
      'DIPLOME',
      'RPPS_ADELI',
      'AUTORISATION_EXERCICE',
      'RCP_ASSURANCE',
      'ATTESTATION_URSSAF',
    ]);
  });

  it('un régime salarié renseigné a les SALARIE_ONLY sans les LIBERAL_ONLY', () => {
    for (const typeExercice of ['SALARIE', 'CDD', 'INTERIM']) {
      expect(types(filtrerDocumentsRequis(REGLES_IDE, soignant({ type_exercice: typeExercice })))).toEqual([
        'CARTE_IDENTITE',
        'DIPLOME',
        'RPPS_ADELI',
        'AUTORISATION_EXERCICE',
        'CASIER_JUDICIAIRE',
      ]);
    }
  });

  it('sans type_exercice, ni SALARIE_ONLY ni LIBERAL_ONLY : seules les règles TOUS restent', () => {
    for (const typeExercice of [null, undefined, '']) {
      expect(types(filtrerDocumentsRequis(REGLES_IDE, soignant({ type_exercice: typeExercice })))).toEqual([
        'CARTE_IDENTITE',
        'DIPLOME',
        'RPPS_ADELI',
        'AUTORISATION_EXERCICE',
      ]);
    }
  });

  it('type_exercice_requis absent vaut TOUS ; une valeur inconnue n’exclut pas la règle', () => {
    const regles = [
      regle('CARTE_IDENTITE', { type_exercice_requis: null }),
      regle('DIPLOME', { type_exercice_requis: undefined }),
      regle('RIB', { type_exercice_requis: 'AUTRE_VALEUR' }),
    ];
    expect(types(filtrerDocumentsRequis(regles, soignant({ type_exercice: null })))).toEqual([
      'CARTE_IDENTITE',
      'DIPLOME',
      'RIB',
    ]);
  });

  it('une liste de règles absente donne une liste vide', () => {
    expect(filtrerDocumentsRequis(null, soignant())).toEqual([]);
    expect(filtrerDocumentsRequis(undefined, soignant())).toEqual([]);
  });
});

describe('filtrerDocumentsRequis — dispenses par registre professionnel', () => {
  it('un RPPS vérifié dispense du diplôme, de l’attestation RPPS et de l’autorisation d’exercice (IDE)', () => {
    expect(types(filtrerDocumentsRequis(REGLES_IDE, soignant({ rpps_verifie: true })))).toEqual([
      'CARTE_IDENTITE',
      'CASIER_JUDICIAIRE',
    ]);
  });

  it.each(['IADE', 'IBODE'])('le RPPS ne dispense pas %s du diplôme de spécialité', (profession) => {
    const regles = REGLES_IDE.map((r) => ({ ...r, profession }));
    expect(types(filtrerDocumentsRequis(regles, soignant({ profession, rpps_verifie: true })))).toEqual([
      'CARTE_IDENTITE',
      'DIPLOME',
      'CASIER_JUDICIAIRE',
    ]);
  });

  it.each(['AS', 'AES', 'AUXILIAIRE_PUERICULTURE'])(
    'une profession sans RPPS (%s) n’obtient aucune dispense d’un rpps_verifie',
    (profession) => {
      const regles = REGLES_IDE.map((r) => ({ ...r, profession }));
      expect(types(filtrerDocumentsRequis(regles, soignant({ profession, rpps_verifie: true })))).toEqual([
        'CARTE_IDENTITE',
        'DIPLOME',
        'RPPS_ADELI',
        'AUTORISATION_EXERCICE',
        'CASIER_JUDICIAIRE',
      ]);
    },
  );

  it('un ADELI vérifié ne dispense pas du diplôme mais masque RPPS_ADELI et AUTORISATION_EXERCICE', () => {
    expect(types(filtrerDocumentsRequis(REGLES_IDE, soignant({ adeli_verifie: true })))).toEqual([
      'CARTE_IDENTITE',
      'DIPLOME',
      'CASIER_JUDICIAIRE',
    ]);
  });

  it('un ADELI vérifié masque aussi RPPS_ADELI pour une profession sans RPPS, sans dispense de diplôme', () => {
    const regles = REGLES_IDE.map((r) => ({ ...r, profession: 'AS' }));
    expect(types(filtrerDocumentsRequis(regles, soignant({ profession: 'AS', adeli_verifie: true })))).toEqual([
      'CARTE_IDENTITE',
      'DIPLOME',
      'CASIER_JUDICIAIRE',
    ]);
  });

  it('seul rpps_verifie === true vaut vérifié pour la dispense de diplôme', () => {
    for (const valeur of [false, null, undefined]) {
      expect(types(filtrerDocumentsRequis(REGLES_IDE, soignant({ rpps_verifie: valeur })))).toContain('DIPLOME');
    }
  });
});

describe('documentValidePourExigence — pièce valide pour une exigence', () => {
  const maintenant = new Date('2026-11-02T10:00:00Z');
  const doc = (extra: Record<string, unknown> = {}) => ({
    type_document: 'CARTE_IDENTITE',
    statut_verification: 'VERIFIE',
    valide_jusqua: null,
    profession_certifiee: null,
    ...extra,
  });

  it('exige le même type et le statut VERIFIE', () => {
    const exigence = { type_document: 'CARTE_IDENTITE' };
    expect(documentValidePourExigence(doc(), exigence, 'IDE', maintenant)).toBe(true);
    expect(documentValidePourExigence(doc({ type_document: 'PASSEPORT' }), exigence, 'IDE', maintenant)).toBe(false);
    for (const statut of ['EN_ATTENTE', 'REJETE', 'EXPIRE', 'REVUE_MANUELLE_REQUISE', 'API_INDISPONIBLE']) {
      expect(documentValidePourExigence(doc({ statut_verification: statut }), exigence, 'IDE', maintenant)).toBe(false);
    }
  });

  it('refuse une pièce dont la fin de validité est atteinte ou dépassée', () => {
    const exigence = { type_document: 'CARTE_IDENTITE' };
    expect(documentValidePourExigence(doc({ valide_jusqua: '2026-11-02T10:00:00.001Z' }), exigence, 'IDE', maintenant)).toBe(true);
    expect(documentValidePourExigence(doc({ valide_jusqua: '2026-11-02T10:00:00Z' }), exigence, 'IDE', maintenant)).toBe(false);
    expect(documentValidePourExigence(doc({ valide_jusqua: '2026-11-01' }), exigence, 'IDE', maintenant)).toBe(false);
    expect(documentValidePourExigence(doc({ valide_jusqua: '' }), exigence, 'IDE', maintenant)).toBe(true);
  });

  it.each(['IADE', 'IBODE'])('un diplôme %s doit être certifié pour la spécialité exacte', (profession) => {
    const exigence = { type_document: 'DIPLOME' };
    const diplome = (certifiee: unknown) => doc({ type_document: 'DIPLOME', profession_certifiee: certifiee });
    expect(documentValidePourExigence(diplome(profession), exigence, profession, maintenant)).toBe(true);
    expect(documentValidePourExigence(diplome(profession.toLowerCase()), exigence, profession, maintenant)).toBe(true);
    expect(documentValidePourExigence(diplome('IDE'), exigence, profession, maintenant)).toBe(false);
    expect(documentValidePourExigence(diplome(null), exigence, profession, maintenant)).toBe(false);
  });

  it('la spécialité exacte ne concerne que l’exigence DIPLOME', () => {
    expect(documentValidePourExigence(doc(), { type_document: 'CARTE_IDENTITE' }, 'IADE', maintenant)).toBe(true);
    expect(documentValidePourExigence(
      doc({ type_document: 'DIPLOME', profession_certifiee: null }),
      { type_document: 'DIPLOME' },
      'IDE',
      maintenant,
    )).toBe(true);
  });
});
