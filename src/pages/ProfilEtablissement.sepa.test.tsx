import React from 'react';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { SepaSetupSection } from './ProfilEtablissement';

const mocks = vi.hoisted(() => ({ invoke: vi.fn(), maybeSingle: vi.fn(), eq: vi.fn() }));
vi.mock('@/components/LayoutApp', () => ({ LayoutApp: () => null }));
vi.mock('@/lib/stripe', () => ({ isStripeConfigured: true, stripePromise: null }));
vi.mock('@stripe/react-stripe-js', () => ({
  Elements: ({ children }: { children: React.ReactNode }) => <>{children}</>,
  IbanElement: () => <input aria-label="IBAN Stripe" />,
  useStripe: () => null,
  useElements: () => null,
}));
vi.mock('@/integrations/supabase/client', () => ({
  supabase: { functions: { invoke: mocks.invoke }, from: () => ({ select: () => ({ eq: mocks.eq }) }) },
  SUPABASE_URL: 'http://localhost', SUPABASE_PUBLISHABLE_KEY: 'test',
}));

beforeEach(() => {
  vi.clearAllMocks();
  mocks.eq.mockReturnValue({ maybeSingle: mocks.maybeSingle });
  mocks.maybeSingle.mockResolvedValue({ data: { est_compte_test: false }, error: null });
});

describe('Mandat SEPA après inscription', () => {
  it('garde les paiements des comptes test désactivés sans appeler le service', async () => {
    mocks.maybeSingle.mockResolvedValue({ data: { est_compte_test: true }, error: null });
    render(<SepaSetupSection etablissementId="etablissement-test" />);
    expect(await screen.findByRole('status')).toHaveTextContent('aucun prélèvement réel');
    expect(mocks.invoke).not.toHaveBeenCalled();
    expect(mocks.eq).toHaveBeenCalledWith('id', 'etablissement-test');
    expect(screen.queryByLabelText('IBAN Stripe')).not.toBeInTheDocument();
  });

  it('ne contacte pas Stripe lorsque la classification du compte est inconnue', async () => {
    mocks.maybeSingle.mockResolvedValue({ data: null, error: { message: 'Indisponible' } });
    render(<SepaSetupSection etablissementId="etablissement-reel" />);
    expect(await screen.findByRole('alert')).toHaveTextContent('Impossible de vérifier le compte');
    expect(mocks.invoke).not.toHaveBeenCalled();
    expect(screen.queryByLabelText('IBAN Stripe')).not.toBeInTheDocument();
  });

  it('ne propose pas un nouveau mandat après une lecture refusée et permet de réessayer', async () => {
    mocks.invoke.mockResolvedValueOnce({ data: { error: 'Lecture indisponible' }, error: null })
      .mockResolvedValueOnce({ data: { has_sepa: true, last4: '1234' }, error: null });
    render(<SepaSetupSection etablissementId="etablissement-reel" />);
    expect(await screen.findByRole('alert')).toHaveTextContent('Lecture indisponible');
    expect(screen.queryByLabelText('IBAN Stripe')).not.toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: 'Réessayer' }));
    expect(await screen.findByText(/Mandat SEPA actif/)).toHaveTextContent('1234');
    await waitFor(() => expect(mocks.invoke).toHaveBeenCalledTimes(2));
  });

  it('conserve le formulaire pour un compte réel sans mandat après lecture réussie', async () => {
    mocks.invoke.mockResolvedValue({ data: { has_sepa: false }, error: null });
    render(<SepaSetupSection etablissementId="etablissement-reel" />);
    expect(await screen.findByLabelText('IBAN Stripe')).toBeInTheDocument();
    expect(mocks.invoke).toHaveBeenCalledWith('setup-sepa', { body: { action: 'get_sepa_status' } });
  });
});
