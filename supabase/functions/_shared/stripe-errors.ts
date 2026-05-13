// ============================================================
// _shared/stripe-errors.ts — CP-STRIPE-6 (H9)
// ============================================================
// Helper partagé pour mapper une erreur Stripe en réponse HTTP
// cohérente. Utilisé par stripe-connect-onboard, stripe-connect-
// status, stripe-connect-pay-mission.
//
// stripe-webhook a déjà une gestion granulaire par event (ne
// l'utilise pas). process-stripe-refunds a son propre mapping
// typé CP-STRIPE-5 (ne l'utilise pas non plus).
// ============================================================

export type StripeErrorMapped = {
  status: number;
  code: string;
  userMessage: string;
  retryable: boolean;
  logLevel: "warn" | "error";
};

export function mapStripeError(err: unknown): StripeErrorMapped {
  const e = err as {
    type?: string;
    code?: string;
    message?: string;
    raw?: { code?: string; message?: string };
  };

  const stripeType = e.type || "";
  const code = e.code || e.raw?.code || "";

  // Auth error : config Stripe cassée (clé révoquée, mauvais env)
  if (stripeType === "StripeAuthenticationError") {
    return {
      status: 500,
      code: "STRIPE_AUTH_FAILED",
      userMessage: "Configuration Stripe invalide, contactez le support.",
      retryable: false,
      logLevel: "error",
    };
  }

  // Rate limit : retry conseillé
  if (stripeType === "StripeRateLimitError") {
    return {
      status: 503,
      code: "STRIPE_RATE_LIMIT",
      userMessage: "Trop de requêtes, réessayez dans quelques instants.",
      retryable: true,
      logLevel: "warn",
    };
  }

  // Resource missing / account invalid : compte supprimé, PI introuvable, etc.
  if (code === "resource_missing" || code === "account_invalid") {
    return {
      status: 404,
      code: "STRIPE_RESOURCE_MISSING",
      userMessage: "Ressource Stripe introuvable ou supprimée.",
      retryable: false,
      logLevel: "warn",
    };
  }

  // F-15 fix — Balance insufficient : compte plateforme ou Connect sans solde.
  // Vu en mode test surtout, mais peut arriver en prod si payouts trop fréquents
  // ou holds en cours. Retryable une fois le solde reconstitué.
  if (code === "balance_insufficient") {
    return {
      status: 402,
      code: "STRIPE_BALANCE_INSUFFICIENT",
      userMessage: "Solde Stripe insuffisant pour effectuer le virement. Le paiement sera retenté dès que le solde sera disponible.",
      retryable: true,
      logLevel: "error",
    };
  }

  // Invalid request : paramètre fautif côté appel Stripe
  if (stripeType === "StripeInvalidRequestError") {
    return {
      status: 400,
      code: code || "STRIPE_INVALID_REQUEST",
      userMessage: "Requête Stripe invalide. Vérifiez les données envoyées.",
      retryable: false,
      logLevel: "error",
    };
  }

  // Connection / API : Stripe temporairement indisponible
  if (stripeType === "StripeConnectionError" || stripeType === "StripeAPIError") {
    return {
      status: 503,
      code: "STRIPE_CONNECTION_ERROR",
      userMessage: "Service Stripe temporairement indisponible, réessayez.",
      retryable: true,
      logLevel: "warn",
    };
  }

  // Carte refusée (cas edge, peu probable hors flow checkout direct)
  if (stripeType === "StripeCardError") {
    return {
      status: 400,
      code: code || "STRIPE_CARD_ERROR",
      userMessage: e.message || "Votre moyen de paiement a été refusé.",
      retryable: false,
      logLevel: "warn",
    };
  }

  // Fallback générique : erreur non-Stripe ou type non classifié
  return {
    status: 500,
    code: "STRIPE_UNKNOWN_ERROR",
    userMessage: "Une erreur interne est survenue.",
    retryable: false,
    logLevel: "error",
  };
}
