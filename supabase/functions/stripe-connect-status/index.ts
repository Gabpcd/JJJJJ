import Stripe from "npm:stripe@18.5.0";
import { createClient } from "npm:@supabase/supabase-js@2.99.2";
import { mapStripeError } from "../_shared/stripe-errors.ts";
import { assertStripeSecretMode } from "../_shared/stripe-production.ts";
import { jsonResponse, preflightResponse } from "../_shared/cors.ts";
import { verifyUserOrServiceRole } from "../_shared/admin-auth.ts";

// [CP-STRIPE-6 H10] TTL du cache : si onboarding.modifie_le est plus
// récent que CACHE_TTL_MS, on retourne les données DB sans appeler
// stripe.accounts.retrieve (économise quota Stripe + latence UI).
// Le webhook account.updated (CP4) bumpe modifie_le = invalidation
// automatique à chaque changement réel côté Stripe.
const CACHE_TTL_MS = 5 * 60 * 1000;

const NON_DEMANDE = {
  statut: 'NON_DEMANDE',
  onboarding_complete: false,
  charges_enabled: false,
  payouts_enabled: false,
  iban_last4: null,
  requirements: [],
  disabled_reason: null,
  cached: true,
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return preflightResponse(req);
  }
  if (req.method !== 'POST') return jsonResponse(req, { error: 'Methode non autorisee' }, 405);

  try {
    const auth = await verifyUserOrServiceRole(req);
    if (!auth.ok) return jsonResponse(req, { error: auth.error }, auth.status);
    if (auth.isServiceRole || !auth.userId) {
      return jsonResponse(req, { error: 'Consultation utilisateur uniquement' }, 403);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    if (!supabaseUrl || !serviceRoleKey) {
      return jsonResponse(req, { error: 'Configuration serveur incomplete' }, 503);
    }
    const supabaseAdmin = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false } });

    const { data: onboarding, error: onboardingError } = await supabaseAdmin
      .from("stripe_connect_onboarding")
      .select("id, stripe_account_id, statut, modifie_le, charges_enabled, payouts_enabled, details_submitted, iban_last4")
      .eq("soignant_id", auth.userId)
      .maybeSingle();
    if (onboardingError) {
      console.error('[stripe-connect-status] lecture onboarding impossible', onboardingError.code);
      return jsonResponse(req, { error: 'STRIPE_STATUS_UNAVAILABLE', message: 'Statut de paiement temporairement indisponible.' }, 503);
    }

    // Aucun onboarding (cas normal, y compris comptes de demonstration) n'est
    // pas une panne Stripe et ne doit jamais initialiser le SDK ni appeler son API.
    if (!onboarding || onboarding.statut === 'NON_DEMANDE' || !onboarding.stripe_account_id) {
      return jsonResponse(req, NON_DEMANDE);
    }

    // [CP-STRIPE-6 H11] Si déjà marqué SUPPRIME, pas besoin de re-tenter
    // un retrieve Stripe qui échouera de la même manière.
    if (onboarding.statut === "SUPPRIME") {
      return jsonResponse(req, {
          statut: "SUPPRIME",
          onboarding_complete: false,
          charges_enabled: false,
          payouts_enabled: false,
          iban_last4: onboarding.iban_last4 || null,
          requirements: [],
          disabled_reason: "account_deleted",
          message: "Votre compte Stripe Connect a été supprimé. Contactez le support ou recommencez l'onboarding.",
          cached: true,
        });
    }

    // [CP-STRIPE-6 H10] Check cache via modifie_le
    const url = new URL(req.url);
    const forceRefresh = url.searchParams.get("force") === "true";
    const modifieLe = onboarding.modifie_le
      ? new Date(onboarding.modifie_le).getTime()
      : 0;
    const cacheAge = Date.now() - modifieLe;
    const cacheValid = !forceRefresh && cacheAge < CACHE_TTL_MS;

    if (cacheValid) {
      // Cache hit : pas d'appel Stripe
      const onboardingComplete = !!(
        onboarding.charges_enabled &&
        onboarding.payouts_enabled &&
        onboarding.details_submitted
      );
      return jsonResponse(req, {
          statut: onboarding.statut,
          onboarding_complete: onboardingComplete,
          charges_enabled: !!onboarding.charges_enabled,
          payouts_enabled: !!onboarding.payouts_enabled,
          iban_last4: onboarding.iban_last4 || null,
          requirements: [],
          disabled_reason: null,
          cached: true,
          cache_age_seconds: Math.round(cacheAge / 1000),
        });
    }

    // Cache miss : call Stripe API
    const stripeSecretKey = Deno.env.get("STRIPE_SECRET_KEY") || "";
    if (!stripeSecretKey) {
      return jsonResponse(req, { error: 'STRIPE_NOT_CONFIGURED', message: 'Service Stripe temporairement indisponible.' }, 503);
    }
    assertStripeSecretMode(stripeSecretKey);
    const stripe = new Stripe(stripeSecretKey, {
      apiVersion: "2025-08-27.basil",
    });

    let account: Stripe.Account;
    try {
      account = await stripe.accounts.retrieve(onboarding.stripe_account_id);
    } catch (retrieveErr: unknown) {
      // [CP-STRIPE-6 H11] Compte supprimé côté Stripe (resource_missing/account_invalid)
      const e = retrieveErr as { code?: string; type?: string };
      if (e.code === "resource_missing" || e.code === "account_invalid") {
        console.warn(
          `Connect account ${onboarding.stripe_account_id} deleted on Stripe side — marking SUPPRIME`
        );

        await supabaseAdmin
          .from("stripe_connect_onboarding")
          .update({
            statut: "SUPPRIME",
            charges_enabled: false,
            payouts_enabled: false,
            modifie_le: new Date().toISOString(),
          })
          .eq("soignant_id", auth.userId);

        // Audit RGPD
        await supabaseAdmin.rpc("fn_ecrire_audit_safe", {
          p_acteur_id: auth.userId,
          p_type_acteur: "SYSTEME",
          p_action: "STRIPE_CONNECT_ACCOUNT_DELETED",
          p_type_ressource: "stripe_connect_onboarding",
          p_id_ressource: onboarding.id,
          p_cle_s3: null,
          p_details: {
            stripe_account_id: onboarding.stripe_account_id,
            stripe_error_code: e.code,
            detected_at: new Date().toISOString(),
          },
          p_ip: null,
          p_navigateur: "stripe-connect-status",
        });

        return jsonResponse(req, {
            statut: "SUPPRIME",
            onboarding_complete: false,
            charges_enabled: false,
            payouts_enabled: false,
            iban_last4: null,
            requirements: [],
            disabled_reason: "account_deleted",
            message: "Votre compte Stripe Connect a été supprimé. Contactez le support ou recommencez l'onboarding.",
          });
      }
      // Autre erreur → remonter au catch global (mapStripeError)
      throw retrieveErr;
    }

    const onboardingComplete =
      !!account.details_submitted &&
      !!account.charges_enabled &&
      !!account.payouts_enabled;

    // Determine status
    let statut: string;
    if (onboardingComplete) {
      statut = "COMPLET";
    } else if (account.requirements?.disabled_reason) {
      statut = "SUSPENDU";
    } else {
      statut = "EN_COURS";
    }

    // Extract IBAN last4 from external accounts
    let ibanLast4: string | null = null;
    if (account.external_accounts?.data?.length) {
      const bankAccount = account.external_accounts.data[0];
      if ("last4" in bankAccount) {
        ibanLast4 = bankAccount.last4 as string;
      }
    }

    // Update onboarding record (bumpe modifie_le pour le cache)
    await supabaseAdmin
      .from("stripe_connect_onboarding")
      .update({
        statut,
        charges_enabled: account.charges_enabled ?? false,
        payouts_enabled: account.payouts_enabled ?? false,
        details_submitted: account.details_submitted ?? false,
        iban_last4: ibanLast4,
        modifie_le: new Date().toISOString(),
      })
      .eq("soignant_id", auth.userId);

    return jsonResponse(req, {
        statut,
        onboarding_complete: onboardingComplete,
        charges_enabled: account.charges_enabled ?? false,
        payouts_enabled: account.payouts_enabled ?? false,
        iban_last4: ibanLast4,
        requirements: account.requirements?.currently_due ?? [],
        disabled_reason: account.requirements?.disabled_reason ?? null,
        cached: false,
      });
  } catch (error: unknown) {
    // [CP-STRIPE-6 H9] Mapping typed Stripe errors
    const mapped = mapStripeError(error);
    console[mapped.logLevel]("stripe-connect-status error:", {
      code: mapped.code,
      raw: error instanceof Error ? error.message : String(error),
    });
    return jsonResponse(req, { error: mapped.code, message: mapped.userMessage }, mapped.status);
  }
});
