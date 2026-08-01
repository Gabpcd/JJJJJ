import { describe, expect, it } from 'vitest';
import {
  estDocumentComptabilise,
  estFactureRelancable,
  montantDocumentComptable,
} from './adminInvoiceAccounting';

describe('règles comptables des factures admin', () => {
  it('additionne une facture émise avec ses montants positifs', () => {
    const facture = {
      statut: 'EMISE',
      type_document: 'FACTURE',
      montant_signe: 100,
      montant_ht: 100,
      montant_tva: 20,
      montant_ttc: 120,
    };

    expect(estDocumentComptabilise(facture)).toBe(true);
    expect(montantDocumentComptable(facture, 'ht')).toBe(100);
    expect(montantDocumentComptable(facture, 'tva')).toBe(20);
    expect(montantDocumentComptable(facture, 'ttc')).toBe(120);
  });

  it('soustrait un avoir émis du CA, de la TVA et du TTC', () => {
    const avoir = {
      statut: 'EMISE',
      type_document: 'AVOIR',
      montant_signe: -40,
      montant_ht: 40,
      montant_tva: 8,
      montant_ttc: 48,
    };

    expect(montantDocumentComptable(avoir, 'ht')).toBe(-40);
    expect(montantDocumentComptable(avoir, 'tva')).toBe(-8);
    expect(montantDocumentComptable(avoir, 'ttc')).toBe(-48);
  });

  it('exclut entièrement les brouillons et documents annulés', () => {
    for (const statut of ['BROUILLON', 'ANNULEE']) {
      const document = {
        statut,
        type_document: 'FACTURE',
        montant_signe: 100,
        montant_ht: 100,
        montant_tva: 20,
        montant_ttc: 120,
      };
      expect(estDocumentComptabilise(document)).toBe(false);
      expect(montantDocumentComptable(document, 'ht')).toBe(0);
      expect(montantDocumentComptable(document, 'tva')).toBe(0);
      expect(montantDocumentComptable(document, 'ttc')).toBe(0);
    }
  });

  it('ne considère jamais un avoir comme une facture à relancer', () => {
    const maintenant = new Date('2026-08-01T12:00:00Z');
    expect(estFactureRelancable({ statut: 'EMISE', type_document: 'FACTURE', date_echeance: '2026-07-31' }, maintenant)).toBe(true);
    expect(estFactureRelancable({ statut: 'EN_RETARD', type_document: 'FACTURE', date_echeance: '2026-07-31' }, maintenant)).toBe(true);
    expect(estFactureRelancable({ statut: 'EMISE', type_document: 'AVOIR', date_echeance: '2026-07-31' }, maintenant)).toBe(false);
    expect(estFactureRelancable({ statut: 'EN_RETARD', type_document: 'AVOIR', date_echeance: '2026-07-31' }, maintenant)).toBe(false);
    expect(estFactureRelancable({ statut: 'PAYEE', type_document: 'FACTURE', date_echeance: '2026-07-31' }, maintenant)).toBe(false);
  });

  it('ne qualifie jamais une facture non échue comme impayée ou relançable', () => {
    const maintenant = new Date('2026-08-01T12:00:00Z');
    expect(estFactureRelancable({ statut: 'EMISE', type_document: 'FACTURE', date_echeance: '2026-08-17' }, maintenant)).toBe(false);
    expect(estFactureRelancable({ statut: 'EN_RETARD', type_document: 'FACTURE', date_echeance: '2026-08-17' }, maintenant)).toBe(false);
    expect(estFactureRelancable({ statut: 'EMISE', type_document: 'FACTURE', date_echeance: '2026-08-01' }, maintenant)).toBe(false);
  });

  it('bascule au retard selon le jour civil français, y compris autour de minuit', () => {
    // 00 h 30 le 2 août à Paris, mais encore le 1er août en UTC.
    const maintenant = new Date('2026-08-01T22:30:00Z');
    expect(estFactureRelancable({
      statut: 'EMISE',
      type_document: 'FACTURE',
      date_echeance: '2026-08-01',
    }, maintenant)).toBe(true);
  });

  it('conserve les anciennes factures explicitement en retard sans échéance', () => {
    expect(estFactureRelancable({ statut: 'EN_RETARD', type_document: 'FACTURE' })).toBe(true);
    expect(estFactureRelancable({ statut: 'EMISE', type_document: 'FACTURE' })).toBe(false);
  });
});
