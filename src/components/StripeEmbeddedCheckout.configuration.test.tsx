import React from 'react';
import { fireEvent, render, screen, waitFor, cleanup } from '@testing-library/react';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import { StripeEmbeddedCheckout } from './StripeEmbeddedCheckout';

const mocks = vi.hoisted(() => ({
  stripe: null as Promise<unknown> | null, invoke: vi.fn(), redirect: vi.fn(), provider: vi.fn(),
}));
vi.mock('@/lib/stripe', () => ({ get stripePromise() { return mocks.stripe; } }));
vi.mock('@/integrations/supabase/client', () => ({ supabase: { functions: { invoke: mocks.invoke } } }));
vi.mock('sonner', () => ({ toast: { info: vi.fn(), success: vi.fn() } }));
vi.mock('@stripe/react-stripe-js', () => ({
  EmbeddedCheckoutProvider: ({ children, ...props }: React.PropsWithChildren) => {
    mocks.provider(props); return <div data-testid="stripe-provider">{children}</div>;
  },
  EmbeddedCheckout: () => <div>Formulaire Stripe simulé</div>,
}));
vi.mock('@/components/ui/dialog', () => ({
  Dialog: ({ open, children }: React.PropsWithChildren<{ open: boolean }>) => open ? <div role="dialog">{children}</div> : null,
  DialogContent: ({ children }: React.PropsWithChildren) => <div>{children}</div>,
  DialogHeader: ({ children }: React.PropsWithChildren) => <div>{children}</div>,
  DialogTitle: ({ children }: React.PropsWithChildren) => <h2>{children}</h2>,
  DialogDescription: ({ children }: React.PropsWithChildren) => <p>{children}</p>,
}));

const locationDescriptor = Object.getOwnPropertyDescriptor(window, 'location')!;
const hostedUrl = 'https://checkout.stripe.com/c/pay/cs_test_fixture';
const unavailable = 'Le paiement par carte est momentanément indisponible. Réessayez plus tard.';
const props = { factureId: 'facture-fixture', open: true, onClose: vi.fn(), onComplete: vi.fn() };
beforeEach(() => {
  vi.clearAllMocks(); mocks.stripe = null;
  Object.defineProperty(window, 'location', { configurable: true, value: { assign: mocks.redirect } });
});
afterEach(() => { cleanup(); Object.defineProperty(window, 'location', locationDescriptor); });

it.each([false, true])('uses an actual hosted response with configured=%s, including resumed sessions', async configured => {
  if (configured) mocks.stripe = Promise.resolve({ fixture: true });
  mocks.invoke.mockResolvedValue({ data: { url: hostedUrl, client_secret: null }, error: null });
  render(<StripeEmbeddedCheckout {...props} />);
  await waitFor(() => expect(mocks.redirect).toHaveBeenCalledExactlyOnceWith(hostedUrl));
  expect(mocks.invoke).toHaveBeenCalledExactlyOnceWith('create-invoice-payment', {
    body: { facture_id: props.factureId, embedded: configured },
  });
  expect(props.onComplete).not.toHaveBeenCalled();
});

it('keeps a resumed embedded session without key closed and never creates a second session', async () => {
  mocks.invoke.mockResolvedValue({ data: { client_secret: 'cs_test_fixture_secret' }, error: null });
  render(<StripeEmbeddedCheckout {...props} />);
  expect(await screen.findByText(unavailable)).toBeInTheDocument();
  expect(screen.queryByTestId('stripe-provider')).not.toBeInTheDocument();
  expect(mocks.redirect).not.toHaveBeenCalled();
  expect(mocks.invoke).toHaveBeenCalledTimes(1);
  fireEvent.click(screen.getByRole('button', { name: 'Fermer' }));
  expect(props.onClose).toHaveBeenCalledTimes(1);
  expect(props.onComplete).not.toHaveBeenCalled();
});

it('refuses a prepared embedded secret without key and does not call an Edge function', async () => {
  render(<StripeEmbeddedCheckout {...props} preparedClientSecret="cs_test_fixture_secret" />);
  expect(await screen.findByText(unavailable)).toBeInTheDocument();
  expect(screen.queryByTestId('stripe-provider')).not.toBeInTheDocument();
  expect(mocks.invoke).not.toHaveBeenCalled();
});

it('still passes the returned secret to the provider when configured', async () => {
  mocks.stripe = Promise.resolve({ fixture: true });
  mocks.invoke.mockResolvedValue({ data: { client_secret: 'cs_test_fixture_secret' }, error: null });
  render(<StripeEmbeddedCheckout {...props} />);
  await waitFor(() => expect(mocks.provider).toHaveBeenLastCalledWith(expect.objectContaining({
    stripe: mocks.stripe, options: expect.objectContaining({ clientSecret: 'cs_test_fixture_secret' }),
  })));
  expect(mocks.redirect).not.toHaveBeenCalled();
});

it('keeps the server refusal visible with a configured key and never retries payment creation', async () => {
  mocks.stripe = Promise.resolve({ fixture: true });
  mocks.invoke.mockResolvedValue({ data: { error: 'TEST_ACCOUNT_PAYMENT_DISABLED' }, error: null });
  render(<StripeEmbeddedCheckout {...props} />);
  expect(await screen.findByText('Compte de test : les paiements réels sont désactivés. Aucun débit n’a été effectué.')).toBeInTheDocument();
  expect(mocks.invoke).toHaveBeenCalledExactlyOnceWith('create-invoice-payment', {
    body: { facture_id: props.factureId, embedded: true },
  });
  expect(mocks.provider).not.toHaveBeenCalled();
  expect(mocks.redirect).not.toHaveBeenCalled();
  expect(props.onComplete).not.toHaveBeenCalled();
});
