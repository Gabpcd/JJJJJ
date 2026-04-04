import { loadStripe } from '@stripe/stripe-js';

// Stripe publishable key: use env var with hardcoded fallback for backwards compatibility
export const STRIPE_PUBLISHABLE_KEY = import.meta.env.VITE_STRIPE_PUBLISHABLE_KEY || 'pk_test_51T9pssEjmfMLV1pV64N90ZsFENmEliR8vqGFRi7pmVRqg4HXYkRFTd2Bn5WxGCfuYc26I3pHgntEQN6gBBbNrDh700X5Mxaiow';

export const stripePromise = loadStripe(STRIPE_PUBLISHABLE_KEY);
