import Stripe from "npm:stripe@18.5.0";
import { createClient } from "npm:@supabase/supabase-js@2";
import { mapStripeError } from "../_shared/stripe-errors.ts";

function getCorsOrigin(req: Request): string {
  const origin = req.headers.get("origin") || "";
  if (
    origin === "https://jolene.app" ||
    origin === "https://app.jolene.app" ||
    origin === "https://www.jolene.app" ||
    origin === "http://localhost:5173" ||
    origin === "http://localhost:8080"
  ) {
    return origin;
  }
  return "https://jolene.app";
}

function corsHeaders(req: Request) {
  return {
    "Access-Control-Allow-Origin": getCorsOrigin(req),
    "Access-Control-Allow-Headers":
      "authorization, x-client-info, apikey, content-type, x-supabase-client-platform, x-supabase-client-platform-version, x-supabase-client-runtime, x-supabase-client-runtime-version",
  };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders(req) });
  }

  const supabaseAdmin = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    { auth: { persistSession: false } }
  );

  let step = "init";

  try {
    step = "1_auth_header";
    const authHeader = req.headers.get("Authorization");
    const hasAuth = !!authHeader;
    const authLen = authHeader?.length ?? 0;
    console.log(`[stripe-connect-pay-mission] step=1 hasAuth=${hasAuth} len=${authLen}`);
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Non autorisé — header manquant" }), {
        status: 401,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    step = "2_auth_user";
    const supabaseClient = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_ANON_KEY") ?? ""
    );
    const {
      data: { user },
      error: authError,
    } = await supabaseClient.auth.getUser(authHeader.replace("Bearer ", ""));
    if (authError || !user) {
      console.error(`[stripe-connect-pay-mission] step=2 getUser failed: authError=${authError?.message ?? "null"} user=${!!user}`);
      return new Response(JSON.stringify({
        error: "Non autorisé",
        reason: authError?.message || "user_not_found",
      }), {
        status: 401,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }
    console.log(`[stripe-connect-pay-mission] step=2 user=${user.id}`);

    const { mission_id } = await req.json();
    if (!mission_id) {
      return new Response(JSON.stringify({ error: "mission_id requis" }), {
        status: 400,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    // Fetch mission
    const { data: mission } = await supabaseAdmin
      .from("missions")
      .select(
        "id, etablissement_id, soignant_assigne_id, statut, montant_commission_ttc, net_a_payer, type_contrat_applique"
      )
      .eq("id", mission_id)
      .single();

    if (!mission) {
      return new Response(JSON.stringify({ error: "Mission introuvable" }), {
        status: 404,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    if (mission.statut !== "TERMINEE") {
      return new Response(
        JSON.stringify({ error: "La mission doit être terminée" }),
        {
          status: 400,
          headers: { ...corsHeaders(req), "Content-Type": "application/json" },
        }
      );
    }

    // BUG-UI-OBLIG-1 Fix#3 — défense en profondeur : les missions SALARIE
    // ne peuvent pas être payées via Stripe (bulletin de paie + virement SEPA).
    if (mission.type_contrat_applique === "SALARIE") {
      return new Response(
        JSON.stringify({
          error: "CONTRAT_SALARIE_NON_STRIPE",
          message:
            "Les missions en contrat salarié doivent être payées par virement SEPA (bulletin de paie). Utilisez le flux 'Déclarer virement' à la place.",
        }),
        {
          status: 400,
          headers: { ...corsHeaders(req), "Content-Type": "application/json" },
        }
      );
    }

    // Verify caller is the établissement owner
    const { data: etab } = await supabaseAdmin
      .from("etablissements")
      .select("id, stripe_customer_id, nom, email_contact")
      .eq("id", mission.etablissement_id)
      .single();

    if (!etab) {
      return new Response(
        JSON.stringify({ error: "Établissement introuvable" }),
        {
          status: 404,
          headers: { ...corsHeaders(req), "Content-Type": "application/json" },
        }
      );
    }

    // Verify user is linked to this établissement via auth metadata
    const { data: adminUserData } = await supabaseAdmin.auth.admin.getUserById(user.id);
    const userEtabId = adminUserData?.user?.app_metadata?.etablissement_id || user.id;

    // Check group membership for the specific establishment's group
    let isGroupAdmin = false;
    if (userEtabId !== mission.etablissement_id && etab) {
      const { data: missionEtab } = await supabaseAdmin
        .from("etablissements")
        .select("groupe_sante_id")
        .eq("id", mission.etablissement_id)
        .single();

      if (missionEtab?.groupe_sante_id) {
        const { data: membership } = await supabaseAdmin
          .from("admins_groupe_sante")
          .select("id")
          .eq("utilisateur_id", user.id)
          .eq("groupe_id", missionEtab.groupe_sante_id)
          .limit(1);

        isGroupAdmin = !!membership && membership.length > 0;
      }
    }

    if (userEtabId !== mission.etablissement_id && !isGroupAdmin) {
      return new Response(
        JSON.stringify({ error: "Vous n'êtes pas autorisé à payer cette mission" }),
        {
          status: 403,
          headers: { ...corsHeaders(req), "Content-Type": "application/json" },
        }
      );
    }

    // Check soignant is LIBERAL or MIXTE
    const soignantId = mission.soignant_assigne_id;
    const { data: soignant } = await supabaseAdmin
      .from("soignants")
      .select("type_exercice, statut_liberal")
      .eq("id", soignantId)
      .single();

    const soignantEligible = soignant && (
      soignant.type_exercice === "LIBERAL"
      || soignant.type_exercice === "MIXTE"
      || (soignant as any).statut_liberal === "ACTIF"
    );

    if (!soignantEligible) {
      return new Response(
        JSON.stringify({
          error:
            "Le paiement Connect est réservé aux soignants en exercice libéral ou mixte",
        }),
        {
          status: 403,
          headers: { ...corsHeaders(req), "Content-Type": "application/json" },
        }
      );
    }

    // [CP-STRIPE-2 H1/H14] Lookup facture_honoraires liée à la mission.
    // On exige qu'elle existe avant de créer la Checkout Session — ainsi on
    // peut (1) injecter son id dans la metadata Stripe pour que le webhook
    // update le bon row, (2) éviter les sessions orphelines si la facture
    // n'a jamais été générée, (3) supporter les avoirs AUTO_STRIPE futurs
    // qui nécessitent un stripe_payment_intent_id sur la facture d'origine.
    const { data: factureHonoraires } = await supabaseAdmin
      .from("factures_honoraires")
      .select("id, statut")
      .eq("mission_id", mission_id)
      .eq("soignant_id", soignantId)
      .in("statut", ["EMISE", "EN_RETARD"])
      .order("date_emission", { ascending: true })
      .limit(1)
      .maybeSingle();

    if (!factureHonoraires) {
      return new Response(
        JSON.stringify({
          error: "FACTURE_NON_GENEREE",
          message:
            "Facture honoraires non générée pour cette mission. Cliquez sur 'Générer facture' avant de payer.",
        }),
        {
          status: 400,
          headers: { ...corsHeaders(req), "Content-Type": "application/json" },
        }
      );
    }

    // Check soignant has Connect account
    const { data: connectOnboarding } = await supabaseAdmin
      .from("stripe_connect_onboarding")
      .select("stripe_account_id, statut")
      .eq("soignant_id", soignantId)
      .maybeSingle();

    if (
      !connectOnboarding ||
      connectOnboarding.statut !== "COMPLET" ||
      !connectOnboarding.stripe_account_id
    ) {
      return new Response(
        JSON.stringify({
          error: "Le soignant n'a pas de compte Stripe Connect actif",
        }),
        {
          status: 400,
          headers: { ...corsHeaders(req), "Content-Type": "application/json" },
        }
      );
    }

    // BUG-UI-OBLIG-1 Fix#2 — idempotence avec fenêtre de 15 min pour
    // éviter qu'un transfer `EN_ATTENTE` orphelin (Checkout abandonné, session
    // expirée, erreur Stripe non propagée) bloque indéfiniment la re-tentative.
    //   - TRANSFERE / CHARGE_REUSSI / PAYE  : paiement réellement abouti → bloquer.
    //   - EN_ATTENTE < 15 min               : paiement Stripe possiblement en vol → bloquer, message timing.
    //   - EN_ATTENTE >= 15 min              : orphelin → marquer ECHOUE puis laisser repartir une nouvelle session.
    const { data: existingTransfer } = await supabaseAdmin
      .from("stripe_transfers")
      .select("id, statut, cree_le")
      .eq("mission_id", mission_id)
      .order("cree_le", { ascending: false })
      .limit(1)
      .maybeSingle();

    const FENETRE_ORPHELIN_MINUTES = 15;
    const statutBloquantDefinitif = ["TRANSFERE", "CHARGE_REUSSI", "PAYE"];

    if (existingTransfer && statutBloquantDefinitif.includes(existingTransfer.statut)) {
      return new Response(
        JSON.stringify({
          already_paid: true,
          statut: existingTransfer.statut,
          message: "Ce paiement a déjà été effectué",
        }),
        {
          status: 200,
          headers: { ...corsHeaders(req), "Content-Type": "application/json" },
        }
      );
    }

    let transferAReutiliserId: string | null = existingTransfer?.id ?? null;

    if (existingTransfer?.statut === "EN_ATTENTE") {
      const ageMs = Date.now() - new Date(existingTransfer.cree_le).getTime();
      const ageMinutes = Math.floor(ageMs / 60000);

      if (ageMinutes < FENETRE_ORPHELIN_MINUTES) {
        const minutesRestantes = FENETRE_ORPHELIN_MINUTES - ageMinutes;
        return new Response(
          JSON.stringify({
            already_paid: true,
            statut: "EN_ATTENTE",
            message: `Paiement en cours de traitement Stripe, réessayez dans ${minutesRestantes} minute${minutesRestantes > 1 ? "s" : ""}.`,
          }),
          {
            status: 200,
            headers: { ...corsHeaders(req), "Content-Type": "application/json" },
          }
        );
      }

      // Orphelin > 15 min : marquer ECHOUE et autoriser une nouvelle session.
      await supabaseAdmin
        .from("stripe_transfers")
        .update({
          statut: "ECHOUE",
          erreur: `Orphelin auto-cleanup (>${FENETRE_ORPHELIN_MINUTES} min sans webhook) — BUG-UI-OBLIG-1`,
        })
        .eq("id", existingTransfer.id);

      transferAReutiliserId = null;
    }

    const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY") || "", {
      apiVersion: "2025-08-27.basil",
    });

    // Calculate amounts
    const commissionCents = Math.round(
      (mission.montant_commission_ttc || 0) * 100
    );
    const soignantCents = Math.round((mission.net_a_payer || 0) * 100);
    const totalCents = commissionCents + soignantCents;

    // Reuse or create Stripe customer
    let customerId = etab.stripe_customer_id;
    if (!customerId) {
      const customer = await stripe.customers.create({
        name: etab.nom,
        email: etab.email_contact,
        metadata: { etablissement_id: etab.id },
      });
      customerId = customer.id;
      await supabaseAdmin
        .from("etablissements")
        .update({ stripe_customer_id: customerId })
        .eq("id", etab.id);
    }

    // Create Checkout Session (embedded)
    const origin = req.headers.get("origin") || "https://jolene.app";
    const session = await stripe.checkout.sessions.create({
      customer: customerId,
      ui_mode: "embedded",
      mode: "payment",
      line_items: [
        {
          price_data: {
            currency: "eur",
            unit_amount: commissionCents,
            product_data: { name: "Commission Jolene" },
          },
          quantity: 1,
        },
        {
          price_data: {
            currency: "eur",
            unit_amount: soignantCents,
            product_data: { name: "Honoraires soignant" },
          },
          quantity: 1,
        },
      ],
      payment_intent_data: {
        transfer_group: `mission_${mission_id}`,
        statement_descriptor: "JOLENE",
        metadata: {
          type: "CONNECT_MISSION_PAYMENT",
          mission_id,
          soignant_id: soignantId,
          connected_account_id: connectOnboarding.stripe_account_id,
          soignant_cents: soignantCents.toString(),
          commission_cents: commissionCents.toString(),
          facture_honoraires_id: factureHonoraires.id,
        },
      },
      metadata: {
        // BUG-BOUCLE-PAIEMENT Fix D.1 — metadata COMPLÈTE niveau session Checkout.
        // Avant ce fix, seuls type/mission_id/facture_honoraires_id étaient au
        // niveau session ; les champs soignant_id/connected_account_id/soignant_cents
        // n'étaient que sur payment_intent_data.metadata. Le webhook lisait
        // session.metadata → condition L93 false → branche CONNECT_MISSION_PAYMENT
        // skippée silencieusement après paiement réussi.
        // Maintenant : redondance sender-side + fallback defensive côté webhook.
        type: "CONNECT_MISSION_PAYMENT",
        mission_id,
        soignant_id: soignantId,
        connected_account_id: connectOnboarding.stripe_account_id,
        soignant_cents: soignantCents.toString(),
        commission_cents: commissionCents.toString(),
        facture_honoraires_id: factureHonoraires.id,
      },
      return_url: `${origin}/etablissement/facturation?paiement=succes`,
    });

    // [CP-STRIPE-3 H5] Compensation Checkout Session orpheline.
    // Les 2 opérations DB ci-dessous (upsert stripe_transfers + update missions)
    // peuvent échouer APRÈS que la Session Stripe ait été créée. Sans compensation,
    // on laisserait une session payable côté Stripe sans trace DB plateforme.
    //
    // Stratégie : try/catch englobant, si DB écrit échoue → expire la session
    // Stripe (fire-and-forget, on log mais on n'échoue pas si expire échoue).
    //
    // Décision architecturale (Option A, strict) : si malgré l'expire le user
    // complète quand même le paiement (expire a pu échouer), le webhook n'a
    // AUCUN row stripe_transfers correspondant → idempotency check ligne 198
    // ne matche pas mais le webhook part dans la branche CONNECT_MISSION_PAYMENT
    // et tente un stripe.transfers.create(). Le webhook actuel ne crée pas de
    // nouveau row stripe_transfers en secours, donc le paiement reste "dans
    // les mains de Stripe" côté comptable sans qu'il soit rattaché à une
    // mission côté plateforme. C'est intentionnel : on préfère laisser une
    // anomalie visible (audit entry + pas de PAYEE sur factures_honoraires)
    // plutôt qu'un flow miraculeux qui masque le bug DB initial. L'admin
    // intervient manuellement pour réconcilier (via INSERT stripe_transfers
    // ou refund Stripe).
    const paymentIntentId = typeof session.payment_intent === 'string' ? session.payment_intent : session.payment_intent?.id || null;

    try {
      if (transferAReutiliserId) {
        const { error: updErr } = await supabaseAdmin
          .from("stripe_transfers")
          .update({
            stripe_payment_intent_id: paymentIntentId,
            montant_soignant: soignantCents / 100,
            montant_commission: commissionCents / 100,
            montant_total: totalCents / 100,
            statut: "EN_ATTENTE",
          })
          .eq("id", transferAReutiliserId);
        if (updErr) throw updErr;
      } else {
        const { error: insErr } = await supabaseAdmin.from("stripe_transfers").insert({
          mission_id,
          soignant_id: soignantId,
          etablissement_id: mission.etablissement_id,
          montant_soignant: soignantCents / 100,
          montant_commission: commissionCents / 100,
          montant_total: totalCents / 100,
          stripe_payment_intent_id: paymentIntentId,
          statut: "EN_ATTENTE",
        });
        if (insErr) throw insErr;
      }

      // Update mission payment mode
      const { error: missionErr } = await supabaseAdmin
        .from("missions")
        .update({ mode_paiement_soignant: "STRIPE_CONNECT" })
        .eq("id", mission_id);
      if (missionErr) throw missionErr;
    } catch (dbErr) {
      // DB écrit échoué post-Checkout Session → compensation
      const dbErrMsg = dbErr instanceof Error ? dbErr.message : String(dbErr);
      console.error("CHECKOUT_CREATED_DB_WRITE_FAILED:", dbErrMsg);

      // Expire la session Stripe (fire-and-forget — si ça échoue, la session
      // reste ouverte côté Stripe ; le webhook traitera l'anomalie Option A).
      try {
        await stripe.checkout.sessions.expire(session.id);
        console.log(`Stripe session ${session.id} expired (compensation)`);
      } catch (expireErr) {
        const expireMsg = expireErr instanceof Error ? expireErr.message : String(expireErr);
        console.error(`SESSION_EXPIRE_FAILED for ${session.id}:`, expireMsg);
      }

      // Audit trail pour investigation admin
      await supabaseAdmin.rpc("fn_ecrire_audit_safe", {
        p_acteur_id: mission.etablissement_id,
        p_type_acteur: "SYSTEME",
        p_action: "STRIPE_CHECKOUT_ORPHANED_RECOVERED",
        p_type_ressource: "mission",
        p_id_ressource: mission_id,
        p_cle_s3: null,
        p_details: {
          stripe_session_id: session.id,
          stripe_payment_intent_id: paymentIntentId,
          db_error: dbErrMsg,
          compensation_expire_attempted: true,
        },
        p_ip: null,
        p_navigateur: "stripe-connect-pay-mission",
      });

      return new Response(
        JSON.stringify({
          error: "CHECKOUT_FAILED_RETRY",
          message: "Paiement impossible, veuillez réessayer dans quelques instants.",
        }),
        {
          status: 500,
          headers: { ...corsHeaders(req), "Content-Type": "application/json" },
        }
      );
    }

    return new Response(
      JSON.stringify({
        success: true,
        client_secret: session.client_secret,
        total: totalCents / 100,
        commission: commissionCents / 100,
        soignant: soignantCents / 100,
      }),
      {
        status: 200,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      }
    );
  } catch (error: unknown) {
    // [CP-STRIPE-6 H9] Mapping typed Stripe errors
    const mapped = mapStripeError(error);
    console[mapped.logLevel](`[stripe-connect-pay-mission] step=${step} ERROR:`, {
      code: mapped.code,
      raw: error instanceof Error ? error.message : String(error),
    });
    return new Response(
      JSON.stringify({ error: mapped.code, message: mapped.userMessage, failed_at_step: step }),
      {
        status: mapped.status,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      }
    );
  }
});
