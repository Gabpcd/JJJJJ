import React from 'react';
import { render, screen, within } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import { ResumeReglementCommission } from './ResumeReglementCommission';

const facture = {
  type_document: 'FACTURE', statut: 'EMISE', montant_ttc: 120,
  montant_avoirs_imputes: 40, montant_a_payer: 80, rapprochement_paiement_requis: false,
};
const montant = (libelle: string) => within(screen.getByText(libelle, { exact: true }).parentElement!).getByRole('definition');

describe('Résumé du règlement commission — document et solde distincts', () => {
  it('déduit 40 euros et demande 80 euros sans changer les 120 euros documentaires', () => {
    const document = Object.freeze({ ...facture });
    render(<ResumeReglementCommission facture={document} />);
    expect(montant('Avoirs déduits')).toHaveTextContent(/^−40,00\s*€$/);
    expect(montant('Montant à régler')).toHaveTextContent(/^80,00\s*€$/);
    expect(screen.queryByText('Restant à payer')).not.toBeInTheDocument();
    expect(document).toEqual(facture);
    expect(document.montant_ttc).toBe(120);
  });

  it('conserve le règlement externe de 80 euros après PAYEE et affiche un reste nul', () => {
    const vue = render(<ResumeReglementCommission facture={facture} />);
    const payee = Object.freeze({ ...facture, statut: 'PAYEE' });
    vue.rerender(<ResumeReglementCommission facture={payee} />);
    expect(montant('Avoirs déduits')).toHaveTextContent(/^−40,00\s*€$/);
    expect(montant('Montant réglé hors avoirs')).toHaveTextContent(/^80,00\s*€$/);
    expect(montant('Restant à payer')).toHaveTextContent(/^0,00\s*€$/);
    expect(screen.queryByText('Montant à régler')).not.toBeInTheDocument();
    expect(payee.montant_a_payer).toBe(80);
    expect(payee.montant_ttc).toBe(120);
  });

  it('distingue une facture PAYEE entièrement soldée par avoir de tout débit bancaire', () => {
    const document = { ...facture, statut: 'PAYEE', mode_paiement: 'AVOIR', stripe_payment_intent_id: null, montant_avoirs_imputes: 120, montant_a_payer: 0 };
    render(<ResumeReglementCommission facture={document} />);
    expect(montant('Avoirs déduits')).toHaveTextContent(/^−120,00\s*€$/);
    expect(montant('Montant réglé hors avoirs')).toHaveTextContent(/^0,00\s*€$/);
    expect(montant('Restant à payer')).toHaveTextContent(/^0,00\s*€$/);
    expect(screen.getByText('Soldée par avoir. Aucun débit bancaire.', { exact: true })).toBeInTheDocument();
    expect(screen.queryByText('Montant à régler')).not.toBeInTheDocument();
  });

  it('annonce le rapprochement sans présenter un nouveau montant à payer', () => {
    render(<ResumeReglementCommission facture={{ ...facture, rapprochement_paiement_requis: true }} />);
    expect(screen.getByRole('status')).toHaveTextContent('Règlement à rapprocher après remboursement. Aucun nouveau paiement n’est demandé pendant la vérification.');
    expect(screen.queryByText('Montant à régler')).not.toBeInTheDocument();
    expect(screen.queryByRole('definition')).not.toBeInTheDocument();
  });

  it.each([
    ['avoirs absents', { montant_avoirs_imputes: undefined }],
    ['net absent', { montant_a_payer: undefined }],
    ['projection nulle', { montant_a_payer: null }],
    ['flag absent', { rapprochement_paiement_requis: undefined }],
    ['flag non booléen', { rapprochement_paiement_requis: 'false' }],
    ['net incohérent', { montant_a_payer: 120 }],
    ['avoirs négatifs', { montant_avoirs_imputes: -40 }],
    ['avoirs supérieurs au TTC', { montant_avoirs_imputes: 121, montant_a_payer: 0 }],
    ['centime fractionnaire', { montant_a_payer: 80.001 }],
    ['montant non fini', { montant_ttc: Infinity }],
  ] as const)('refuse %s sans repli sur le TTC', (_nom, projection) => {
    render(<ResumeReglementCommission facture={{ ...facture, ...projection }} />);
    expect(screen.getByRole('status')).toHaveTextContent('Solde indisponible. Rechargez la facture avant de régler.');
    expect(screen.queryByText('Montant à régler')).not.toBeInTheDocument();
    expect(screen.queryByText(/120,00\s*€/)).not.toBeInTheDocument();
  });

  it('accepte les montants décimaux canoniques de la réponse SQL', () => {
    render(<ResumeReglementCommission facture={{ ...facture, montant_ttc: '120.00', montant_avoirs_imputes: '40.00', montant_a_payer: '80.00' }} />);
    expect(montant('Montant à régler')).toHaveTextContent(/^80,00\s*€$/);
    expect(screen.queryByRole('status')).not.toBeInTheDocument();
  });

  it('ne transforme pas un document AVOIR en demande de paiement', () => {
    const vue = render(<ResumeReglementCommission facture={{ ...facture, type_document: 'AVOIR' }} />);
    expect(vue.container).toBeEmptyDOMElement();
  });
});
