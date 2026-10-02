import { afterEach, beforeEach, expect, it, vi } from 'vitest';

const mocks = vi.hoisted(() => ({ loadStripe: vi.fn() }));
vi.mock('@stripe/stripe-js', () => ({ loadStripe: mocks.loadStripe }));

beforeEach(() => { vi.resetModules(); vi.clearAllMocks(); });
afterEach(() => vi.unstubAllEnvs());

it('exposes actual null without a key and never initializes Stripe', async () => {
  vi.stubEnv('VITE_STRIPE_PUBLISHABLE_KEY', '');
  const { stripePromise, isStripeConfigured } = await import('./stripe');
  expect(stripePromise).toBeNull();
  expect(isStripeConfigured).toBe(false);
  expect(mocks.loadStripe).not.toHaveBeenCalled();
});

it('preserves the Stripe loader promise when a key is configured', async () => {
  vi.stubEnv('VITE_STRIPE_PUBLISHABLE_KEY', 'pk_test_fixture_configuration');
  const instance = { fixture: true }, promise = Promise.resolve(instance);
  mocks.loadStripe.mockReturnValue(promise);
  const { stripePromise, isStripeConfigured } = await import('./stripe');
  expect(isStripeConfigured).toBe(true);
  expect(stripePromise).toBe(promise);
  await expect(stripePromise).resolves.toBe(instance);
  expect(mocks.loadStripe).toHaveBeenCalledExactlyOnceWith('pk_test_fixture_configuration');
});
