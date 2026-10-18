import React from 'react';
import { fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import DetailFacture from './DetailFacture';

const mocks = vi.hoisted(() => ({ user: { id: 'membre' }, rpc: vi.fn(), from: vi.fn(), notification: vi.fn(), checkout: vi.fn(),
  permissions: { loading: false, permissions: { lecture_paiement: true, paiement: true }, error: null, recharger: vi.fn() } }));
vi.mock('@/hooks/usePageTitle', () => ({ usePageTitle: () => undefined }));
vi.mock('@/hooks/useEtablissementScope', () => ({ useEtablissementScope: () => ({ user: mocks.user, etablissementId: 'etab', loading: false, resolved: true, error: null, retry: vi.fn() }) }));
vi.mock('@/hooks/useEtabPermissions', () => ({ useEtabPermissions: () => mocks.permissions }));
vi.mock('@/contexts/AuthContext', () => ({ useAuth: () => ({ user: mocks.user }) }));
vi.mock('@/contexts/NotificationContext', () => ({ useNotification: () => ({ afficherNotification: mocks.notification }) }));
vi.mock('@/components/LayoutApp', () => ({ LayoutApp: ({ children }: React.PropsWithChildren) => <>{children}</> }));
vi.mock('@/components/StripeEmbeddedCheckout', () => ({ StripeEmbeddedCheckout: (props: unknown) => { mocks.checkout(props); return null; } }));
vi.mock('@/lib/sentry', () => ({ capturerErreurSentry: vi.fn() }));
vi.mock('@/lib/logger', () => ({ logger: { warn: vi.fn() } }));
vi.mock('@/integrations/supabase/client', () => ({ supabase: { rpc: mocks.rpc, from: mocks.from } }));

let facture: Record<string, unknown>;
let admission: Record<string, unknown>;
let declaration: Record<string, unknown>;
let modeCommission: string;
const honoraires = { id: 'honoraires', etablissement_id: 'etab', mission_id: 'mission', numero_facture: 'HON-001',
  periode_debut: '2026-09-21', periode_fin: '2026-09-27', quantite_heures_snapshot: 4, taux_horaire_snapshot: 20, montant_ht: 80 };
function ouvrir() {
  return render(<MemoryRouter initialEntries={['/etablissement/facturation/commission']}><Routes>
    <Route path="/etablissement/facturation/:id" element={<DetailFacture />} />
  </Routes></MemoryRouter>);
}
beforeEach(() => {
  vi.clearAllMocks(); mocks.permissions.permissions.paiement = true;
  modeCommission = 'CARTE';
  facture = { id: 'commission', etablissement_id: 'etab', mission_id: 'mission', facture_honoraire_id: 'honoraires',
    type_document: 'FACTURE', statut: 'EMISE', mode_paiement: 'STRIPE', numero_facture: 'COM-001',
    date_emission: '2026-09-30', date_echeance: '2026-10-30', montant_ht: 12, montant_tva: 2.4, montant_ttc: 14.4,
    montant_avoirs_imputes: 0, montant_a_payer: 14.4, rapprochement_paiement_requis: false, nombre_missions: 1 };
  admission = { facture_id: 'commission', virement_autorise: true, motif: null };
  declaration = { success: true };
  mocks.rpc.mockImplementation((name: string) => {
    if (name === 'fn_detail_facture') return Promise.resolve({ data: { facture: { ...facture }, missions: [] }, error: null });
    if (name === 'fn_mon_etablissement_complet') return Promise.resolve({ data: { id: 'etab', mode_paiement_commission: modeCommission }, error: null });
    if (name === 'fn_modalites_reglement_commission') return Promise.resolve({ data: { ...admission }, error: null });
    if (name === 'fn_declarer_virement') return Promise.resolve({ data: declaration, error: null });
    throw new Error(`RPC inattendue: ${name}`);
  });
  mocks.from.mockImplementation((table: string) => {
    const q: any = {};
    for (const method of ['select', 'eq']) q[method] = () => q;
    q.single = () => Promise.resolve({ data: table === 'factures' ? { ...facture } : honoraires, error: null });
    return q;
  });
});

describe('Commission séparée — admission exacte et déclaration', () => {
  it('propose le seul virement après honoraires directs, sans Checkout lié ni réception bancaire implicite', async () => {
    ouvrir();
    expect(await screen.findByRole('button', { name: 'Virement' })).toBeEnabled();
    expect(screen.getByText(/ne prouve pas la réception des fonds/)).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Payer' })).not.toBeInTheDocument();
    expect(mocks.checkout).not.toHaveBeenCalled();
    expect(mocks.rpc).toHaveBeenCalledWith('fn_modalites_reglement_commission', { p_facture_id: 'commission' });
  });
  it.each(['PAIEMENT_EN_LIGNE_ENGAGE', 'HONORAIRES_DIRECTS_REQUIS', 'AVOIR_A_RAPPROCHER'])('refuse le paiement séparé si le serveur retourne %s', async motif => {
    admission = { facture_id: 'commission', virement_autorise: false, motif };
    ouvrir(); await screen.findByText('COM-001');
    expect(screen.queryByRole('button', { name: 'Virement' })).not.toBeInTheDocument();
    expect(mocks.checkout).not.toHaveBeenCalled();
  });
  it('une admission d’une autre pièce ferme le détail', async () => {
    admission.facture_id = 'autre-commission'; ouvrir();
    expect(await screen.findByRole('heading', { name: 'Facture indisponible' })).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Virement' })).not.toBeInTheDocument();
  });
  it('le membre en lecture seule consulte sans déclarer', async () => {
    mocks.permissions.permissions.paiement = false; ouvrir(); await screen.findByText('COM-001');
    expect(screen.queryByRole('button', { name: 'Virement' })).not.toBeInTheDocument();
  });
  it.each([{ error: 'PAIEMENT_EN_LIGNE_ENGAGE', message: 'Paiement engagé depuis le chargement.' }, {}])('ne transforme pas un refus ou une réponse vide en succès', async refus => {
    declaration = refus; ouvrir();
    fireEvent.click(await screen.findByRole('button', { name: 'Virement' }));
    fireEvent.change(screen.getByLabelText('Référence de votre virement'), { target: { value: 'VIR-COM-2026-001' } });
    fireEvent.click(screen.getByRole('button', { name: /J'ai effectué le virement/ }));
    await waitFor(() => expect(mocks.notification).toHaveBeenCalledWith(expect.objectContaining({ type: 'erreur' })));
    expect(mocks.notification).not.toHaveBeenCalledWith(expect.objectContaining({ type: 'succes' }));
    expect(mocks.rpc).toHaveBeenCalledWith('fn_declarer_virement', { p_facture_id: 'commission', p_reference: 'VIR-COM-2026-001' });
  });
});

describe('Imputation des avoirs — montant documentaire et règlement', () => {
  it.each([0.01, 0.49])('permet le virement du petit solde SEPA %s uniquement avec admission serveur', async net => {
    modeCommission = 'SEPA_DEBIT';
    Object.assign(facture, { facture_honoraire_id: null, mission_id: null,
      montant_ttc: 120, montant_avoirs_imputes: Math.round((120 - net) * 100) / 100, montant_a_payer: net });
    ouvrir();
    fireEvent.click(await screen.findByRole('button', { name: /^Virement$/ }));
    expect(screen.getByText('Montant à virer :').parentElement).toHaveTextContent(new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(net).replace(/\s/g, ' '));
    expect(screen.queryByRole('button', { name: /^Payer$/ })).not.toBeInTheDocument();
    expect(screen.getByText(/solde est inférieur au minimum du prélèvement SEPA/)).toBeInTheDocument();
  });
  it.each([[0.01, false], [0.50, true]])('conserve le refus SEPA au seuil ou sans admission (%s, %s)', async (net, autorise) => {
    modeCommission = 'SEPA_DEBIT';
    Object.assign(facture, { facture_honoraire_id: null, mission_id: null,
      montant_ttc: 120, montant_avoirs_imputes: Math.round((120 - Number(net)) * 100) / 100, montant_a_payer: net });
    admission.virement_autorise = autorise;
    ouvrir(); await screen.findByText('COM-001');
    expect(screen.queryByRole('button', { name: /^Virement$/ })).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /^Payer$/ })).not.toBeInTheDocument();
  });
  function avecAvoir() {
    Object.assign(facture, { montant_ht: 100, montant_tva: 20, montant_ttc: 120,
      montant_avoirs_imputes: 40, montant_a_payer: 80, rapprochement_paiement_requis: false });
  }
  function totaux() {
    return within(screen.getByText('Total TTC', { exact: true }).parentElement!.parentElement!);
  }
  function valeur(libelle: string) {
    const section = totaux();
    return within(section.getByText(libelle, { exact: true }).parentElement!).getByRole('definition');
  }
  it('conserve le TTC120 et propose seulement le virement du net80, aussi après remontage', async () => {
    avecAvoir();
    const vue = ouvrir();
    await screen.findByText('COM-001');
    expect(totaux().getByText(/^120,00\s*€$/)).toBeInTheDocument();
    expect(valeur('Avoirs déduits')).toHaveTextContent(/^−40,00\s*€$/);
    expect(valeur('Montant à régler')).toHaveTextContent(/^80,00\s*€$/);
    fireEvent.click(screen.getByRole('button', { name: /^Virement$/ }));
    expect(screen.getByText('Montant à virer :', { exact: true }).parentElement).toHaveTextContent(/80,00\s*€/);
    expect(screen.getByText('Montant à virer :', { exact: true }).parentElement).not.toHaveTextContent(/120,00\s*€/);
    expect(mocks.checkout).not.toHaveBeenCalled();
    vue.unmount(); ouvrir(); await screen.findByText('COM-001');
    expect(valeur('Montant à régler')).toHaveTextContent(/^80,00\s*€$/);
    expect(facture.montant_ttc).toBe(120);
    expect(facture.montant_a_payer).toBe(80);
    expect(mocks.rpc.mock.calls.filter(([nom]) => nom === 'fn_declarer_virement')).toEqual([]);
  });
  it('PAYEE conserve le montant externe80 sans nouvelle demande de règlement', async () => {
    avecAvoir(); Object.assign(facture, { statut: 'PAYEE', date_paiement: '2026-10-18T10:00:00Z' });
    admission.virement_autorise = false; admission.motif = 'FACTURE_NON_PAYABLE';
    ouvrir(); await screen.findByText('COM-001');
    expect(totaux().getByText(/^120,00\s*€$/)).toBeInTheDocument();
    expect(valeur('Montant réglé hors avoirs')).toHaveTextContent(/^80,00\s*€$/);
    expect(valeur('Restant à payer')).toHaveTextContent(/^0,00\s*€$/);
    expect(screen.queryByRole('button', { name: /^Payer$/ })).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /^Virement$/ })).not.toBeInTheDocument();
    expect(facture.montant_a_payer).toBe(80);
  });
  it('net0 PAYEE par AVOIR annonce aucun débit et ne monte pas Checkout', async () => {
    avecAvoir(); Object.assign(facture, { statut: 'PAYEE', mode_paiement: 'AVOIR',
      montant_avoirs_imputes: 120, montant_a_payer: 0, stripe_payment_intent_id: null,
      date_paiement: '2026-10-18T10:00:00Z' });
    admission.virement_autorise = false; admission.motif = 'FACTURE_NON_PAYABLE';
    ouvrir(); await screen.findByText('COM-001');
    expect(totaux().getByText('Soldée par avoir. Aucun débit bancaire.', { exact: true })).toBeInTheDocument();
    expect(valeur('Montant réglé hors avoirs')).toHaveTextContent(/^0,00\s*€$/);
    expect(screen.queryByRole('button', { name: /^Payer$/ })).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /^Virement$/ })).not.toBeInTheDocument();
    expect(mocks.checkout).not.toHaveBeenCalled();
  });
  it.each([
    ['net absent', { montant_a_payer: undefined }],
    ['avoirs absents', { montant_avoirs_imputes: undefined }],
    ['flag absent', { rapprochement_paiement_requis: undefined }],
    ['net incohérent', { montant_a_payer: 120 }],
    ['rapprochement requis', { rapprochement_paiement_requis: true }],
  ])('ferme les actions pour %s, même si l’ancienne admission virement est positive', async (_nom, projection) => {
    avecAvoir(); Object.assign(facture, projection);
    ouvrir(); await screen.findByText('COM-001');
    const section = totaux();
    expect(section.getByRole('status')).toHaveTextContent(
      facture.rapprochement_paiement_requis === true ? 'Règlement à rapprocher après remboursement.' : 'Solde indisponible.');
    expect(section.getByText(/^120,00\s*€$/)).toBeInTheDocument();
    expect(section.queryByText('Montant à régler', { exact: true })).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /^Virement$/ })).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /^Payer$/ })).not.toBeInTheDocument();
    expect(mocks.checkout).not.toHaveBeenCalled();
    expect(mocks.rpc.mock.calls.filter(([nom]) => nom === 'fn_declarer_virement')).toEqual([]);
  });
});
