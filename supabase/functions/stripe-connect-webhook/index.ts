/**
 * Destination Stripe « Events on connected accounts ».
 *
 * La logique métier est partagée avec stripe-webhook, mais l'entrée impose le
 * secret Connect et la présence de event.account avant toute écriture.
 */
import { handleStripeWebhook } from "../_shared/stripe-webhook-handler.ts";

Deno.serve((req) => handleStripeWebhook(req, "CONNECT"));
