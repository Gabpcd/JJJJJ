// ============================================================
// process-stripe-refunds — CP-STRIPE-5 (H3 + A21/T13)
// ============================================================
// Cron qui consomme stripe_refunds_queue pour exécuter les
// remboursements Stripe associés aux avoirs AUTO_STRIPE.
//
// Cycle statut :
//   EN_ATTENTE → EN_COURS (lock) → TRAITE (succès) OU EN_ATTENTE (retry)
//                                → ECHEC (permanent ou 3 tentatives)
//
// Idempotence : UPDATE conditionnel `WHERE statut='EN_ATTENTE'` fait
// office de lock optimiste. Si 2 crons tournent en parallèle, la ligne
// ne sera prise qu'une fois.
//
// Webhook filet de sécurité : charge.refunded (CP-STRIPE-4) fait
// UPDATE TRAITE idempotent si le cron tombe entre refunds.create et
// le UPDATE final.
// ============================================================

import Stripe from "npm:stripe@18.5.0";
import { createClient } from "npm:@supabase/supabase-js@2";

const URL = Deno.env.get("SUPABASE_URL")!;
const KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const STRIPE_KEY = Deno.env.get("STRIPE_SECRET_KEY") || "";

// Codes d'erreur Stripe considérés comme permanents (ECHEC direct, pas de retry)
const PERMANENT_ERROR_CODES = new Set([
  "payment_intent_unexpected_state",
  "amount_too_large",
  "charge_disputed",
  "charge_expired",
  "missing_source",
  "resource_missing", // payment_intent introuvable
]);

// Codes considérés comme succès idempotent (le refund existe déjà côté Stripe)
const ALREADY_REFUNDED_CODES = new Set([
  "charge_already_refunded",
]);

const MAX_TENTATIVES = 3;

interface QueueRow {
  id: string;
  avoir_id: string | null;
  facture_origine_id: string | null;
  stripe_payment_intent_id: string;
  montant_cts: number;
  tentatives: number;
  // Escrow 7b-D PR 4 (nullable : legacy = null/false)
  paiement_escrow_id: string | null;
  reverse_transfer: boolean | null;
  refund_application_fee_cts: number | null;
  absorbe_plateforme: boolean | null;
}

interface StripeErrorLike {
  type?: string;
  code?: string;
  message?: string;
  raw?: { code?: string; message?: string };
}

// Auth résiliente : accepte legacy JWT ou nouveau secret asymétrique (vault).
let _vaultSecret: string | null = null;
async function getVaultSecret(sb: any): Promise<string> {
  if (_vaultSecret) return _vaultSecret;
  const env = Deno.env.get("SUPABASE_SECRET_KEY") || Deno.env.get("SB_SECRET_KEY") || "";
  if (env) { _vaultSecret = env; return env; }
  try {
    const { data } = await sb.rpc('fn_lire_secret_cron');
    if (data) { _vaultSecret = data; return data; }
  } catch { /* ignore */ }
  return "";
}

Deno.serve(async (req) => {
  const t0 = Date.now();

  try {
    const sb = createClient(URL, KEY);

    // 1. Auth : Bearer service_role (legacy JWT OU vault secret)
    const authHeader = req.headers.get("Authorization") || "";
    const bearer = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : "";
    const vaultSecret = await getVaultSecret(sb);
    const validBearers = [KEY, vaultSecret].filter(Boolean);
    if (!bearer || !validBearers.includes(bearer)) {
      return new Response(JSON.stringify({ error: "Non autorisé" }), {
        status: 401,
        headers: { "Content-Type": "application/json" },
      });
    }

    const stripe = new Stripe(STRIPE_KEY, { apiVersion: "2025-08-27.basil" });

    // 2. SELECT des lignes éligibles (max 10 / run)
    const { data: rows, error: selErr } = await sb
      .from("stripe_refunds_queue")
      .select("id, avoir_id, facture_origine_id, stripe_payment_intent_id, montant_cts, tentatives, paiement_escrow_id, reverse_transfer, refund_application_fee_cts, absorbe_plateforme")
      .eq("statut", "EN_ATTENTE")
      .lt("tentatives", MAX_TENTATIVES)
      .or(`dernier_essai_le.is.null,dernier_essai_le.lt.${new Date(Date.now() - 15 * 60 * 1000).toISOString()}`)
      .order("cree_le", { ascending: true })
      .limit(10);

    if (selErr) {
      console.error("stripe_refunds_queue SELECT error:", selErr);
      return new Response(
        JSON.stringify({ error: "Lecture queue impossible", details: selErr.message }),
        { status: 500, headers: { "Content-Type": "application/json" } },
      );
    }

    const queue = (rows || []) as QueueRow[];
    if (queue.length === 0) {
      return new Response(
        JSON.stringify({
          success: true,
          processed: 0,
          message: "Queue vide",
          duration_ms: Date.now() - t0,
        }),
        { headers: { "Content-Type": "application/json" } },
      );
    }

    let successCount = 0;
    let retryCount = 0;
    let echecCount = 0;

    for (const item of queue) {
      // 3a. Lock atomique : EN_ATTENTE → EN_COURS
      const { data: locked, error: lockErr } = await sb
        .from("stripe_refunds_queue")
        .update({
          statut: "EN_COURS",
          dernier_essai_le: new Date().toISOString(),
        })
        .eq("id", item.id)
        .eq("statut", "EN_ATTENTE")
        .select("id")
        .maybeSingle();

      if (lockErr || !locked) {
        // Autre cron a déjà pris la ligne — skip
        console.log(`Queue row ${item.id} already locked by another cron, skipping`);
        continue;
      }

      // 3b. Appel Stripe refunds.create
      try {
        // Escrow 7b-D PR 4 — destination charge : le refund doit reprendre les
        // fonds côté compte connecté du soignant (reverse_transfer) AVANT release
        // (A5) et rembourser tout ou partie de la commission (A6). APRÈS release
        // (absorbe_plateforme), refund simple sur le solde plateforme : Jolene
        // absorbe, pas de reversal, jamais de solde négatif imposé à la soignante.
        const refundParams: Stripe.RefundCreateParams = {
          payment_intent: item.stripe_payment_intent_id,
          amount: item.montant_cts,
          reason: "requested_by_customer",
          metadata: {
            avoir_id: item.avoir_id ?? "",
            facture_origine_id: item.facture_origine_id ?? "",
            queue_id: item.id,
            source: "jolene_refunds_cron",
            paiement_escrow_id: item.paiement_escrow_id ?? "",
          },
        };
        if (item.paiement_escrow_id) {
          if (item.reverse_transfer) refundParams.reverse_transfer = true;
          // refund_application_fee reprend la commission côté plateforme. On ne
          // le passe qu'avec reverse_transfer (destination charge pré-release) et
          // seulement si une part de commission est à rembourser (A6).
          if (item.reverse_transfer && (item.refund_application_fee_cts ?? 0) > 0) {
            refundParams.refund_application_fee = true;
          }
        }
        // Idempotency key = queue id : un retry ne crée jamais un 2e refund.
        const refund = await stripe.refunds.create(refundParams, {
          idempotencyKey: `refund_queue_${item.id}`,
        });

        // 3c. Succès → TRAITE
        await sb
          .from("stripe_refunds_queue")
          .update({
            statut: "TRAITE",
            stripe_refund_id: refund.id,
            traite_le: new Date().toISOString(),
            erreur: null,
          })
          .eq("id", item.id);

        console.log(`Refund ${refund.id} created for queue ${item.id} (avoir ${item.avoir_id})`);
        successCount++;
      } catch (err) {
        const stripeErr = err as StripeErrorLike;
        const code = stripeErr.code || stripeErr.raw?.code || "";
        const errMsg = stripeErr.message || stripeErr.raw?.message || String(err);
        const errType = stripeErr.type || "";

        // 3d. Déterminer action selon type d'erreur
        let nouveauStatut: "TRAITE" | "ECHEC" | "EN_ATTENTE";
        let alertAdmin = false;

        if (ALREADY_REFUNDED_CODES.has(code)) {
          // Idempotence Stripe : on considère que le refund existe → TRAITE
          nouveauStatut = "TRAITE";
          console.log(`Queue ${item.id}: charge_already_refunded — marking TRAITE (idempotence)`);
        } else if (errType === "StripeAuthenticationError") {
          // Config cassée — ECHEC permanent ET alerte admin URGENT
          nouveauStatut = "ECHEC";
          alertAdmin = true;
          console.error(`Queue ${item.id}: StripeAuthenticationError — ECHEC + alert admin`);
        } else if (PERMANENT_ERROR_CODES.has(code)) {
          // Erreur permanente (donnée invalide) — ECHEC + alerte admin
          nouveauStatut = "ECHEC";
          alertAdmin = true;
          console.error(`Queue ${item.id}: permanent Stripe error ${code} — ECHEC`);
        } else if ((item.tentatives + 1) >= MAX_TENTATIVES) {
          // 3e tentative échouée → ECHEC permanent + alerte
          nouveauStatut = "ECHEC";
          alertAdmin = true;
          console.error(`Queue ${item.id}: max retries reached — ECHEC`);
        } else {
          // Erreur retryable (rate limit, network, etc.) → retour EN_ATTENTE
          nouveauStatut = "EN_ATTENTE";
          console.warn(
            `Queue ${item.id}: retryable error (${code || errType}), tentatives=${item.tentatives + 1}`,
          );
        }

        await sb
          .from("stripe_refunds_queue")
          .update({
            statut: nouveauStatut,
            tentatives: item.tentatives + 1,
            erreur: errMsg.substring(0, 500),
          })
          .eq("id", item.id);

        if (nouveauStatut === "TRAITE") {
          successCount++;
        } else if (nouveauStatut === "ECHEC") {
          echecCount++;
        } else {
          retryCount++;
        }

        // 3f. Email admin si ECHEC
        if (alertAdmin) {
          try {
            // Récupérer les détails avoir + contexte pour le mail
            const { data: avoir } = await sb
              .from("factures_honoraires")
              .select("numero_facture, montant_ttc, soignant_id, mission_id")
              .eq("id", item.avoir_id)
              .maybeSingle();

            let soignantNom = "";
            let etabNom = "";
            if (avoir) {
              const { data: s } = await sb
                .from("soignants")
                .select("prenom, nom")
                .eq("id", avoir.soignant_id)
                .maybeSingle();
              soignantNom = s ? `${s.prenom || ""} ${s.nom || ""}`.trim() : "";

              const { data: m } = await sb
                .from("missions")
                .select("etablissements(nom)")
                .eq("id", avoir.mission_id)
                .maybeSingle();
              etabNom = (m?.etablissements as { nom?: string } | null)?.nom || "";
            }

            const { data: admins } = await sb.rpc("fn_list_admin_user_ids");
            for (const adminId of (admins || []) as string[]) {
              await sb.functions.invoke("send-email", {
                body: {
                  type: "REFUND_ECHEC_ADMIN",
                  destinataire_id: adminId,
                  data: {
                    avoir_id: item.avoir_id,
                    numero_avoir: avoir?.numero_facture || "—",
                    montant_formatte: (item.montant_cts / 100).toFixed(2),
                    payment_intent_id: item.stripe_payment_intent_id,
                    tentatives: item.tentatives + 1,
                    erreur_stripe: errMsg.substring(0, 300),
                    erreur_code: code || errType || "unknown",
                    soignant_nom: soignantNom,
                    etablissement_nom: etabNom,
                  },
                },
              });
            }
          } catch (emailErr) {
            console.error("send-email REFUND_ECHEC_ADMIN failed:", emailErr);
          }
        }

        // Audit trail pour investigation
        await sb.rpc("fn_ecrire_audit_safe", {
          p_acteur_id: "00000000-0000-0000-0000-000000000000",
          p_type_acteur: "SYSTEME",
          p_action: nouveauStatut === "TRAITE"
            ? "FINANCE_REFUND_TRAITE_IDEMPOTENT"
            : nouveauStatut === "ECHEC"
            ? "FINANCE_REFUND_ECHEC"
            : "FINANCE_REFUND_RETRY",
          p_type_ressource: "stripe_refunds_queue",
          p_id_ressource: item.id,
          p_cle_s3: null,
          p_details: {
            avoir_id: item.avoir_id,
            payment_intent_id: item.stripe_payment_intent_id,
            montant_cts: item.montant_cts,
            erreur_code: code,
            erreur_type: errType,
            erreur_message: errMsg.substring(0, 500),
            tentatives: item.tentatives + 1,
          },
          p_ip: null,
          p_navigateur: "process-stripe-refunds",
        });
      }
    }

    return new Response(
      JSON.stringify({
        success: true,
        processed: queue.length,
        success_count: successCount,
        retry_count: retryCount,
        echec_count: echecCount,
        duration_ms: Date.now() - t0,
      }),
      { headers: { "Content-Type": "application/json" } },
    );
  } catch (err) {
    const errMsg = err instanceof Error ? err.message : String(err);
    console.error("process-stripe-refunds fatal:", errMsg);
    return new Response(
      JSON.stringify({ error: "Une erreur interne est survenue.", details: errMsg }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }
});
