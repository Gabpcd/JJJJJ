import { describe, expect, it } from 'vitest';
import {
  classerPaiementSalaire,
  indexerDernierPaiementParMission,
  repartirPaiementConfirme,
} from './paiementSoignantUi';

describe('paiementSoignantUi', () => {
  it('choisit explicitement le paiement le plus récent par mission quel que soit l ordre reçu', () => {
    const resultat = indexerDernierPaiementParMission([
      { id: 'ancien', mission_id: 'm1', statut: 'DECLARE', cree_le: '2026-07-01T10:00:00Z' },
      { id: 'autre', mission_id: 'm2', statut: 'CONFIRME', cree_le: '2026-07-02T10:00:00Z' },
      { id: 'recent', mission_id: 'm1', statut: 'CONFIRME', cree_le: '2026-07-03T10:00:00Z' },
    ]);

    expect((resultat.m1 as { statut: string }).statut).toBe('CONFIRME');
    expect(resultat.m2.id).toBe('autre');
  });

  it('prend en compte une mise à jour plus récente et départage par identifiant', () => {
    const resultat = indexerDernierPaiementParMission([
      { id: 'a', mission_id: 'm1', modifie_le: '2026-07-04T10:00:00Z' },
      { id: 'b', mission_id: 'm1', modifie_le: '2026-07-04T10:00:00Z' },
      { id: 'cree-apres', mission_id: 'm2', cree_le: '2026-07-06T10:00:00Z', date_paiement: '2026-07-01' },
      { id: 'paye-apres', mission_id: 'm2', cree_le: '2026-07-05T10:00:00Z', date_paiement: '2026-07-07' },
    ]);

    expect(resultat.m1.id).toBe('b');
    expect(resultat.m2.id).toBe('cree-apres');
  });

  it('conserve le solde d’un règlement confirmé mais partiel', () => {
    expect(repartirPaiementConfirme(346.85, 300)).toEqual({
      montantPaye: 300,
      montantRestant: 46.85,
      estPartiel: true,
    });
  });

  it('ne fabrique aucun reste pour un règlement complet ou supérieur au dû', () => {
    expect(repartirPaiementConfirme(500, 500)).toEqual({
      montantPaye: 500,
      montantRestant: 0,
      estPartiel: false,
    });
    expect(repartirPaiementConfirme(500, 510)).toEqual({
      montantPaye: 510,
      montantRestant: 0,
      estPartiel: false,
    });
  });
});

describe('réception salariale déclarée', () => {
  const confirme = { statut: 'CONFIRME', confirme_par_soignant: true, conteste: false, montant_net: 300 };

  it('ne confond pas réception et référence employeur, sans fabriquer de solde', () => {
    expect(classerPaiementSalaire({ ...confirme, montant_du_reference: 425, source_montant_du: 'BULLETIN_OFFICIEL_ETABLISSEMENT' })).toEqual({
      etat: 'confirme', libelle: 'Réception confirmée', montantDeclare: 300, montantReferenceEmployeur: 425,
    });
  });

  it.each([false, null, undefined])('exige la confirmation explicite du soignant (%s)', confirmation => {
    expect(classerPaiementSalaire({ ...confirme, confirme_par_soignant: confirmation }).etat).toBe('a_verifier');
  });

  it.each([null, undefined, '', ' ', 0, '0', -1, 'invalide', NaN, Infinity, true, {}])('ne remplace jamais un montant invalide (%s)', montant => {
    const paiement = classerPaiementSalaire({ ...confirme, montant_net: montant });
    expect(paiement.etat).toBe('a_verifier');
    expect(paiement.montantDeclare).toBeNull();
  });

  it.each(['RESOLU', 'CONTESTE', 'DECLARE', 'EN_ATTENTE', 'INCONNU'])('ne déduit pas la réception du statut %s', statut => {
    expect(classerPaiementSalaire({ ...confirme, statut }).etat).not.toBe('confirme');
  });

  it('fait primer la contestation sur une ancienne confirmation', () => {
    expect(classerPaiementSalaire({ ...confirme, conteste: true }).etat).toBe('conteste');
  });

  it.each(['ESTIMATION_AVANT_PAS_A_CONFIRMER', 'FACTURE_HONORAIRES', null, undefined])('ne traite pas la source %s comme un net employeur', source => {
    expect(classerPaiementSalaire({ ...confirme, montant_du_reference: 999, source_montant_du: source }).montantReferenceEmployeur).toBeNull();
  });

  it('accepte les nombres décimaux PostgREST et distingue l’absence de déclaration', () => {
    expect(classerPaiementSalaire({ ...confirme, montant_net: '300.25' }).montantDeclare).toBe(300.25);
    expect(classerPaiementSalaire().etat).toBe('absent');
  });
});
