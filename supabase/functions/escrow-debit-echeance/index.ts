/**
 * escrow-debit-echeance — Escrow 7b-D PR 3
 *
 * Déclenché par pg_cron (toutes les heures). Crée la DESTINATION CHARGE Stripe
 * de chaque paiement escrow INITIE arrivé à échéance (debit_prevu_le <= now).
 *
 * Modèle destination charge (invariant : aucun fonds de mission ne stationne
 * sur le solde plateforme de Jolene) :
 *   - charge sur le mandat SEPA de l'établissement (off_session)
 *   - transfer_data[destination] = compte connecté du soignant
 *   - application_fee_amount = commission (seule part qui revient à Jolene)
 *   - on_behalf_of = compte connecté (le soignant est le marchand)
 *   → les honoraires vont DIRECTEMENT au solde connecté du soignant.
 *
 * La charge SEPA passe en `processing` puis `succeeded` (J+quelques jours) :
 * ce webhook (stripe-webhook, branche ESCROW_MISSION_PAYMENT) fait passer
 * paiements_escrow INITIE → DEBITE. Le release (payout) attend en plus que les
 * fonds soient `available` sur le solde connecté (A3, consumer PR 5).
 *
 * Auth : Bearer service_role (env) ou secret vault sb_secret_* (pg_cron),
 * cf. CLAUDE.md « Auth crons pg_cron ».
 *
 * NO-OP si feature_paiement_rapide_actif = 0 : aucun paiements_escrow n'existe
 * (le trigger de création est gaté par le même flag).
 */
import Stripe from "npm:stripe@18.5.0";
import { createClient } from "npm:@supabase/supabase-js@2";

let _vaultSecret: string | null = null;
async function bearerAutorise(req: Request, admin: any): Promise<boolean> {
  const bearer = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "").trim();
  if (!bearer) return false;
  const svc = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
  if (svc && bearer === svc) return true;
  if (_vaultSecret) return bearer === _vaultSecret;
  try {
    const { data } = await admin.rpc("fn_lire_secret_cron");
    if (data && typeof data === "string") { _vaultSecret = data; return bearer === data; }
  } catch { /* ignore */ }
  return false;
}

Deno.serve(async (req) => {
  const admin = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    { auth: { persistSession: false } },
  );

  if (!(await bearerAutorise(req, admin))) {
    return new Response(JSON.stringify({ error: "forbidden" }), { status: 403 });
  }

  const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY") || "", {
    apiVersion: "2025-08-27.basil",
  });

  // Débits à échéance (INITIE, debit_prevu_le <= now, < 3 tentatives).
  const { data: dus, error: dusErr } = await admin.rpc("fn_escrow_debits_a_echeance", { p_limit: 50 });
  if (dusErr) {
    return new Response(JSON.stringify({ error: dusErr.message }), { status: 500 });
  }

  const rows = (dus as any[]) || [];
  let debites = 0, echoues = 0, ignores = 0;

  for (const esc of rows) {
    try {
      // Relire les données fraîches nécessaires (montants déjà figés dans esc).
      const { data: etab } = await admin
        .from("etablissements")
        .select("stripe_customer_id, stripe_sepa_payment_method_id, mode_paiement_commission")
        .eq("id", esc.etablissement_id)
        .maybeSingle();

      const { data: onboarding } = await admin
        .from("stripe_connect_onboarding")
        .select("stripe_account_id, statut")
        .eq("soignant_id", esc.soignant_id)
        .maybeSingle();

      // Garde-fous : mandat SEPA + compte connecté complet. Si l'un manque
      // (mandat révoqué, onboarding incomplet), on abandonne proprement cette
      // ligne → régime standard (marquée ECHOUE, pas de retry infini).
      if (!etab?.stripe_customer_id || !etab?.stripe_sepa_payment_method_id
          || etab.mode_paiement_commission !== "SEPA_DEBIT") {
        await admin.rpc("fn_escrow_marquer_incident", {
          p_paiement_escrow_id: esc.id, p_type_incident: "ECHEC",
          p_detail: "Mandat SEPA établissement absent au moment du débit",
        });
        echoues++;
        continue;
      }
      if (!onboarding?.stripe_account_id || onboarding.statut !== "COMPLET") {
        await admin.rpc("fn_escrow_marquer_incident", {
          p_paiement_escrow_id: esc.id, p_type_incident: "ECHEC",
          p_detail: "Compte Stripe Connect soignant non COMPLET au moment du débit",
        });
        echoues++;
        continue;
      }

      // Compteur de tentatives (avant l'appel Stripe : une tentative = un essai).
      await admin
        .from("paiements_escrow")
        .update({ tentatives_debit: (esc.tentatives_debit ?? 0) + 1, derniere_tentative_le: new Date().toISOString() })
        .eq("id", esc.id);

      // DESTINATION CHARGE — idempotency key = escrow id (rejoue → même PI).
      const pi = await stripe.paymentIntents.create({
        amount: esc.montant_total_cents,
        currency: "eur",
        customer: etab.stripe_customer_id,
        payment_method: etab.stripe_sepa_payment_method_id,
        payment_method_types: ["sepa_debit"],
        confirm: true,
        off_session: true,
        application_fee_amount: esc.commission_cents,
        on_behalf_of: onboarding.stripe_account_id,
        transfer_data: { destination: onboarding.stripe_account_id },
        transfer_group: `mission_${esc.mission_id}`,
        statement_descriptor: "JOLENE",
        metadata: {
          type: "ESCROW_MISSION_PAYMENT",
          paiement_escrow_id: esc.id,
          mission_id: esc.mission_id,
          soignant_id: esc.soignant_id,
          etablissement_id: esc.etablissement_id,
          honoraires_cents: String(esc.honoraires_cents),
          commission_cents: String(esc.commission_cents),
          methode_debit: esc.methode_debit,
        },
      }, { idempotencyKey: `escrow_debit_${esc.id}` });

      // SEPA : `processing` (débit initié, settlement en cours). Le passage
      // DEBITE se fait sur payment_intent.succeeded (webhook). On enregistre le
      // PI et l'exposition (A2) dès l'initiation du débit.
      await admin
        .from("paiements_escrow")
        .update({
          stripe_payment_intent_id: pi.id,
          erreur: null,
          modifie_le: new Date().toISOString(),
        })
        .eq("id", esc.id);

      await admin.rpc("fn_escrow_enregistrer_exposition", { p_paiement_escrow_id: esc.id });

      await admin.rpc("fn_ecrire_audit_safe", {
        p_acteur_id: "00000000-0000-0000-0000-000000000000",
        p_type_acteur: "SYSTEME",
        p_action: "ESCROW_DEBIT_INITIE",
        p_type_ressource: "mission",
        p_id_ressource: esc.mission_id,
        p_cle_s3: null,
        p_details: {
          paiement_escrow_id: esc.id,
          stripe_payment_intent_id: pi.id,
          pi_status: pi.status,
          methode_debit: esc.methode_debit,
          total_cents: esc.montant_total_cents,
          honoraires_cents: esc.honoraires_cents,
          commission_cents: esc.commission_cents,
          destination: onboarding.stripe_account_id,
        },
        p_ip: null,
        p_navigateur: "escrow-debit-echeance",
      });
      debites++;
    } catch (err: any) {
      const code = err?.code || err?.raw?.code || null;
      const msg = err?.message || String(err);
      // Après 3 tentatives, on gèle + relance J+3 (incident). Avant, on laisse
      // la ligne INITIE pour un retry au prochain passage du cron.
      if ((esc.tentatives_debit ?? 0) + 1 >= 3) {
        await admin.rpc("fn_escrow_marquer_incident", {
          p_paiement_escrow_id: esc.id, p_type_incident: "ECHEC",
          p_detail: `${code || "erreur"} — ${msg}`.substring(0, 500),
        });
        echoues++;
      } else {
        await admin
          .from("paiements_escrow")
          .update({ erreur: `${code || "erreur"} — ${msg}`.substring(0, 500), modifie_le: new Date().toISOString() })
          .eq("id", esc.id);
        ignores++;
      }
      console.error(`escrow-debit-echeance mission=${esc.mission_id} code=${code} msg=${msg}`);
    }
  }

  return new Response(
    JSON.stringify({ ok: true, examined: rows.length, debites, echoues, retry_plus_tard: ignores }),
    { status: 200, headers: { "Content-Type": "application/json" } },
  );
});
