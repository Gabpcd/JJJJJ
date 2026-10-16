import { act, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import SuiviVersementsConnect from './SuiviVersementsConnect';

const mocks = vi.hoisted(() => ({
  user: { id: 'soignant-1' } as { id: string } | null,
  role: { role: 'SOIGNANT', loading: false, resolved: true, error: null as Error | null },
  from: vi.fn(), eq: vi.fn(), responses: [] as Promise<{ data: unknown; error: unknown }>[],
}));
vi.mock('@/contexts/AuthContext', () => ({ useAuth: () => ({ user: mocks.user }) }));
vi.mock('@/hooks/useRole', () => ({ useRole: () => mocks.role }));
vi.mock('@/integrations/supabase/client', () => ({ supabase: { from: mocks.from } }));

const trace = (overrides = {}) => ({ id: 'trace-1', mission_id: 'mission-1', statut: 'TRANSFERE', montant_soignant: 80,
  stripe_payout_id: null, standard_payout_state: 'WAITING', paye_le: null, ...overrides });
const wrapper = () => <MemoryRouter><SuiviVersementsConnect /></MemoryRouter>;

describe('SuiviVersementsConnect', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.user = { id: 'soignant-1' };
    mocks.role = { role: 'SOIGNANT', loading: false, resolved: true, error: null };
    mocks.responses = [];
    mocks.from.mockImplementation(() => {
      const response = mocks.responses.shift() ?? Promise.resolve({ data: [trace()], error: null });
      const q: any = { select: () => q, eq: (...args: unknown[]) => { mocks.eq(...args); return q; },
        in: () => q, order: () => q, limit: () => q, abortSignal: () => q, then: response.then.bind(response) };
      return q;
    });
  });

  it.each([
    ['WAITING', null, 'Transféré sur Stripe'],
    ['SUBMITTED', 'po_fixture', 'Versement bancaire en cours'],
    ['FAILED', 'po_fixture', 'Versement bancaire échoué'],
    ['REVIEW', null, 'Versement bancaire à vérifier'],
  ])('ne confirme pas la banque pour TRANSFERE/%s', async (state, payout, label) => {
    mocks.responses = [Promise.resolve({ data: [trace({ standard_payout_state: state, stripe_payout_id: payout })], error: null })];
    render(wrapper());
    expect(await screen.findByText(new RegExp('^' + label))).toHaveTextContent('80,00');
    expect(screen.queryByText(/^Versement bancaire confirmé/)).not.toBeInTheDocument();
    expect(mocks.from).toHaveBeenCalledWith('stripe_transfers');
    expect(mocks.eq).toHaveBeenCalledWith('soignant_id', 'soignant-1');
  });

  it('confirme uniquement PAYE/PAID avec objet bancaire et date', async () => {
    mocks.responses = [Promise.resolve({ data: [trace({ statut: 'PAYE', standard_payout_state: 'PAID', stripe_payout_id: 'po_fixture', paye_le: '2026-10-16T12:00:00Z' })], error: null })];
    render(wrapper());
    expect(await screen.findByText(/^Versement bancaire confirmé/)).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Voir la mission' })).toHaveAttribute('href', '/soignant/missions/mission-1');
  });

  it('présente un ancien paiement sans état bancaire comme restant à vérifier', async () => {
    const { standard_payout_state: _absent, ...legacy } = trace({ statut: 'PAYE',
      stripe_payout_id: 'po_fixture', paye_le: '2026-10-16T12:00:00Z' });
    mocks.responses = [Promise.resolve({ data: [legacy], error: null })];
    render(wrapper());
    expect(await screen.findByText(/^Versement bancaire à vérifier/)).toHaveTextContent('80,00');
    expect(screen.queryByText(/^Versement bancaire confirmé/)).not.toBeInTheDocument();
    expect(screen.queryByText(/Le suivi des versements bancaires est indisponible/)).not.toBeInTheDocument();
  });

  it.each(['INCONNU', 'ADMIN_ETABLISSEMENT', 'ADMIN_PLATEFORME'])('ne lit aucun ledger pour le rôle %s', async role => {
    mocks.role.role = role;
    render(wrapper());
    expect(mocks.from).not.toHaveBeenCalled();
    expect(screen.queryByRole('region')).not.toBeInTheDocument();
  });

  it('rend une panne visible sans masquer son absence de preuve, puis relit sur demande', async () => {
    mocks.responses = [Promise.resolve({ data: null, error: { message: 'private-provider-canary' } }), Promise.resolve({ data: [trace()], error: null })];
    render(wrapper());
    expect(await screen.findByText(/Le suivi des versements bancaires est indisponible/)).toHaveTextContent('Aucun versement bancaire ne peut être confirmé');
    expect(screen.queryByText(/private-provider-canary/)).not.toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: 'Réessayer le suivi des versements' }));
    expect(await screen.findByText(/^Transféré sur Stripe/)).toBeInTheDocument();
    expect(mocks.from).toHaveBeenCalledTimes(2);
  });

  it('refuse un montant non fini au lieu de présenter un paiement confirmé', async () => {
    mocks.responses = [Promise.resolve({ data: [trace({ statut: 'PAYE', standard_payout_state: 'PAID', montant_soignant: Infinity })], error: null })];
    render(wrapper());
    expect(await screen.findByText(/Le suivi des versements bancaires est indisponible/)).toBeInTheDocument();
    expect(screen.queryByText(/^Versement bancaire confirmé/)).not.toBeInTheDocument();
  });

  it('ignore une réponse tardive du compte précédent', async () => {
    let resolveOld!: (value: { data: unknown; error: unknown }) => void;
    mocks.responses = [new Promise(resolve => { resolveOld = resolve; }), Promise.resolve({ data: [trace({ id: 'trace-2', montant_soignant: 120 })], error: null })];
    const view = render(wrapper());
    await waitFor(() => expect(mocks.from).toHaveBeenCalledTimes(1));
    mocks.user = { id: 'soignant-2' };
    view.rerender(wrapper());
    expect(await screen.findByText(/^Transféré sur Stripe/)).toHaveTextContent('120,00');
    await act(async () => { resolveOld({ data: [trace()], error: null }); });
    expect(screen.getByText(/^Transféré sur Stripe/)).toHaveTextContent('120,00');
    expect(screen.queryByText(/80,00/)).not.toBeInTheDocument();
  });
});
