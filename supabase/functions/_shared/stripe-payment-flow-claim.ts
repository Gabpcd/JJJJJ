export type StripePaymentFlow =
  | "CHECKOUT_INVOICE"
  | "SEPA_INVOICE"
  | "CONNECT_MISSION";
export type StripePaymentClaimFlow = StripePaymentFlow | "LEGACY_UNKNOWN";

export type StripePaymentFlowClaimExpected = {
  mission_id: string | null;
  facture_id: string | null;
  flow: StripePaymentFlow;
  owner_token: string;
};

export type StripePaymentFlowClaim = Omit<StripePaymentFlowClaimExpected, "flow"> & {
  flow: StripePaymentClaimFlow;
  resources: string[];
  stripe_checkout_session_id: string | null;
  stripe_payment_intent_id: string | null;
};

type SupabaseLike = {
  from: (table: string) => any;
  rpc: (name: string, args: Record<string, unknown>) => any;
};

export async function acquireStripePaymentFlowClaim(
  supabase: SupabaseLike,
  expected: StripePaymentFlowClaimExpected,
): Promise<{ acquired: boolean; claim: StripePaymentFlowClaim }> {
  const { data, error } = await supabase.rpc("fn_stripe_payment_flow_claim", {
    p_flow: expected.flow,
    p_owner_token: expected.owner_token,
    p_facture_id: expected.facture_id,
    p_mission_id: expected.mission_id,
  });
  if (error || !data || typeof data !== "object") {
    throw new Error(
      `Stripe payment claim RPC failed: ${error?.message || "invalid response"}`,
    );
  }

  const result = data as {
    acquired?: boolean;
    flow?: StripePaymentClaimFlow;
    owner_token?: string;
    resources?: string[];
    stripe_checkout_session_id?: string | null;
    stripe_payment_intent_id?: string | null;
  };
  if (result.acquired !== true) {
    return {
      acquired: false,
      claim: {
        ...expected,
        flow: result.flow || expected.flow,
        owner_token: result.owner_token || expected.owner_token,
        resources: result.resources || [],
        stripe_checkout_session_id: result.stripe_checkout_session_id || null,
        stripe_payment_intent_id: result.stripe_payment_intent_id || null,
      },
    };
  }

  return {
    acquired: true,
    claim: {
      ...expected,
      resources: result.resources || [],
      stripe_checkout_session_id: result.stripe_checkout_session_id || null,
      stripe_payment_intent_id: result.stripe_payment_intent_id || null,
    },
  };
}

/**
 * Convertit atomiquement un claim issu du backfill historique, uniquement
 * après que l'appelant a relu et validé les objets Stripe exacts.
 */
export async function adoptLegacyStripePaymentFlowClaim(
  supabase: SupabaseLike,
  expected: StripePaymentFlowClaimExpected,
  evidence: {
    stripeCheckoutSessionId: string | null;
    stripePaymentIntentId: string | null;
  },
): Promise<void> {
  if (
    !expected.facture_id
    || expected.mission_id !== null
    || (
      evidence.stripeCheckoutSessionId === null
      && evidence.stripePaymentIntentId === null
    )
    || (
      expected.flow === "SEPA_INVOICE"
      && (
        evidence.stripeCheckoutSessionId !== null
        || evidence.stripePaymentIntentId === null
      )
    )
  ) {
    throw new Error("Stripe legacy adoption requires exact invoice evidence");
  }

  const { data, error } = await supabase.rpc(
    "fn_stripe_payment_flow_adopter_legacy",
    {
      p_flow: expected.flow,
      p_owner_token: expected.owner_token,
      p_facture_id: expected.facture_id,
      p_stripe_checkout_session_id: evidence.stripeCheckoutSessionId,
      p_stripe_payment_intent_id: evidence.stripePaymentIntentId,
    },
  );
  if (error || !data || typeof data !== "object") {
    throw new Error(
      `Stripe legacy claim adoption failed: ${error?.message || "invalid response"}`,
    );
  }

  const result = data as {
    flow?: StripePaymentFlow;
    owner_token?: string;
    resources?: string[];
    stripe_checkout_session_id?: string | null;
    stripe_payment_intent_id?: string | null;
  };
  if (
    result.flow !== expected.flow
    || result.owner_token !== expected.owner_token
    || !Array.isArray(result.resources)
    || result.resources.length === 0
    || result.stripe_checkout_session_id !== evidence.stripeCheckoutSessionId
    || result.stripe_payment_intent_id !== evidence.stripePaymentIntentId
  ) {
    throw new Error("Stripe legacy claim adoption returned inconsistent state");
  }
}

export async function bindStripePaymentFlowClaimSession(
  supabase: SupabaseLike,
  expected: StripePaymentFlowClaimExpected,
  stripeCheckoutSessionId: string,
  previousStripeCheckoutSessionId: string | null = null,
): Promise<void> {
  let bindQuery = supabase
    .from("stripe_payment_flow_claims")
    .update({
      stripe_checkout_session_id: stripeCheckoutSessionId,
      modifie_le: new Date().toISOString(),
    })
    .eq("flow", expected.flow)
    .eq("owner_token", expected.owner_token);
  bindQuery = previousStripeCheckoutSessionId
    ? bindQuery.eq("stripe_checkout_session_id", previousStripeCheckoutSessionId)
    : bindQuery.is("stripe_checkout_session_id", null);
  const { error } = await bindQuery.select("resource_key");
  if (error) throw new Error(`Stripe payment claim bind failed: ${error.message}`);

  const { data: current, error: currentError } = await supabase
    .from("stripe_payment_flow_claims")
    .select("resource_key, stripe_checkout_session_id")
    .eq("flow", expected.flow)
    .eq("owner_token", expected.owner_token);
  if (
    currentError
    || !Array.isArray(current)
    || current.length === 0
    || current.some((row: { stripe_checkout_session_id?: string | null }) => (
      row.stripe_checkout_session_id !== stripeCheckoutSessionId
    ))
  ) {
    throw new Error(
      `Stripe payment claim bind conflict: ${currentError?.message || "different session"}`,
    );
  }
}

export async function bindStripePaymentFlowClaimIntent(
  supabase: SupabaseLike,
  expected: StripePaymentFlowClaimExpected,
  stripePaymentIntentId: string,
  previousStripePaymentIntentId: string | null = null,
): Promise<void> {
  let bindQuery = supabase
    .from("stripe_payment_flow_claims")
    .update({
      stripe_payment_intent_id: stripePaymentIntentId,
      modifie_le: new Date().toISOString(),
    })
    .eq("flow", expected.flow)
    .eq("owner_token", expected.owner_token);
  bindQuery = previousStripePaymentIntentId
    ? bindQuery.eq("stripe_payment_intent_id", previousStripePaymentIntentId)
    : bindQuery.is("stripe_payment_intent_id", null);
  const { error } = await bindQuery.select("resource_key");
  if (error) throw new Error(`Stripe payment intent claim bind failed: ${error.message}`);

  const { data: current, error: currentError } = await supabase
    .from("stripe_payment_flow_claims")
    .select("resource_key, stripe_payment_intent_id")
    .eq("flow", expected.flow)
    .eq("owner_token", expected.owner_token);
  if (
    currentError
    || !Array.isArray(current)
    || current.length === 0
    || current.some((row: { stripe_payment_intent_id?: string | null }) => (
      row.stripe_payment_intent_id !== stripePaymentIntentId
    ))
  ) {
    throw new Error(
      `Stripe payment intent claim bind conflict: ${currentError?.message || "different intent"}`,
    );
  }
}

export async function releaseStripePaymentFlowClaimForExpiredSession(
  supabase: SupabaseLike,
  flow: StripePaymentFlow,
  stripeCheckoutSessionId: string,
): Promise<void> {
  const { error } = await supabase
    .from("stripe_payment_flow_claims")
    .delete()
    .eq("flow", flow)
    .eq("stripe_checkout_session_id", stripeCheckoutSessionId);
  if (error) throw new Error(`Stripe payment claim release failed: ${error.message}`);
}
