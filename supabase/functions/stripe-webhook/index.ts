/** Destination Stripe « Events on your account ». */
import { handleStripeWebhook } from "../_shared/stripe-webhook-handler.ts";

Deno.serve((req) => handleStripeWebhook(req, "PLATFORM"));
