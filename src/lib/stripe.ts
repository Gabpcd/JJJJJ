import { loadStripe, Stripe } from '@stripe/stripe-js';

// Stripe publishable key from environment
export const STRIPE_PUBLISHABLE_KEY = import.meta.env.VITE_STRIPE_PUBLISHABLE_KEY ?? '';

// Only initialize Stripe if the key is configured, otherwise expose null promise
// (prevents "IntegrationError: empty string" from crashing unrelated pages)
export const stripePromise: Promise<Stripe | null> = STRIPE_PUBLISHABLE_KEY
  ? loadStripe(STRIPE_PUBLISHABLE_KEY)
  : Promise.resolve(null);

export const isStripeConfigured = !!STRIPE_PUBLISHABLE_KEY;
