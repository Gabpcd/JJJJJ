import React from 'react';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
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
const honoraires = { id: 'honoraires', etablissement_id: 'etab', mission_id: 'mission', numero_facture: 'HON-001',
  periode_debut: '2026-09-21', periode_fin: '2026-09-27', quantite_heures_snapshot: 4, taux_horaire_snapshot: 20, montant_ht: 80 };
function ouvrir() {
  return render(<MemoryRouter initialEntries={['/etablissement/facturation/commission']}><Routes>
    <Route path="/etablissement/facturation/:id" element={<DetailFacture />} />
  </Routes></MemoryRouter>);
}
beforeEach(() => {
  vi.clearAllMocks(); mocks.permissions.permissions.paiement = true;
  facture = { id: 'commission', etablissement_id: 'etab', mission_id: 'mission', facture_honoraire_id: 'honoraires',
    type_document: 'FACTURE', statut: 'EMISE', mode_paiement: 'STRIPE', numero_facture: 'COM-001',
    date_emission: '2026-09-30', date_echeance: '2026-10-30', montant_ht: 12, montant_tva: 2.4, montant_ttc: 14.4, nombre_missions: 1 };
  admission = { facture_id: 'commission', virement_autorise: true, motif: null };
  declaration = { success: true };
  mocks.rpc.mockImplementation((name: string) => {
    if (name === 'fn_detail_facture') return Promise.resolve({ data: { facture: { ...facture }, missions: [] }, error: null });
    if (name === 'fn_mon_etablissement_complet') return Promise.resolve({ data: { id: 'etab', mode_paiement_commission: 'CARTE' }, error: null });
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
