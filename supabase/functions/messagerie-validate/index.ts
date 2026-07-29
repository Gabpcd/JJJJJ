/**
 * Sprint 10-A v3 PR 2 — Edge function messagerie-validate
 *
 * Voir supabase/functions/_shared/anti-leak.ts pour la logique de détection
 * (logique pure, importable depuis tests Playwright Node).
 *
 * Endpoint : POST /functions/v1/messagerie-validate
 *   Body : { conversation_id: uuid, content: string }
 *   Auth : Bearer JWT obligatoire
 *
 * Réponse :
 *   200 + { success: true, message_id }
 *   400 + { success: false, error: 'ANTI_LEAK_REFUSE', detected_type: 'TELEPHONE'|'EMAIL'|'URL'|'HANDLE'|'KEYWORD' }
 *   413 + { success: false, error: 'CONTENT_TOO_LARGE' }
 *   429 + { success: false, error: 'RATE_LIMIT' }
 *   401 + { success: false, error: 'NON_AUTHENTIFIE' }
 *
 * Cette function valide ET insère atomiquement le contenu exact via une RPC
 * réservée au service_role. Aucun client ne peut contourner l'anti-fuite en
 * appelant directement la mutation SQL.
 */
import { createClient } from "npm:@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";
import { applyRateLimit } from "../_shared/rate-limit.ts";
import { detecterLeak, sanitizeContent } from "../_shared/anti-leak.ts";

const MAX_CONTENT_LENGTH = 4000;

/** Hash SHA-256 (audit trail sans contenu brut RGPD). */
async function hashContent(content: string): Promise<string> {
  const data = new TextEncoder().encode(content);
  const hashBuffer = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(hashBuffer))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders(req) });
  }

  if (req.method !== "POST") {
    return new Response(
      JSON.stringify({ success: false, error: "METHOD_NOT_ALLOWED" }),
      { status: 405, headers: corsHeaders(req) },
    );
  }

  try {
    // Auth obligatoire
    const authHeader = req.headers.get("Authorization");
    if (!authHeader?.startsWith("Bearer ")) {
      return new Response(
        JSON.stringify({ success: false, error: "NON_AUTHENTIFIE" }),
        { status: 401, headers: corsHeaders(req) },
      );
    }

    const token = authHeader.replace("Bearer ", "");
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") || "",
      Deno.env.get("SUPABASE_ANON_KEY") || "",
      { global: { headers: { Authorization: `Bearer ${token}` } } },
    );

    const { data: userData, error: userErr } = await supabase.auth.getUser(token);
    if (userErr || !userData?.user) {
      return new Response(
        JSON.stringify({ success: false, error: "NON_AUTHENTIFIE" }),
        { status: 401, headers: corsHeaders(req) },
      );
    }
    const userId = userData.user.id;

    // Limite Edge par compte : plusieurs salariés derrière le même réseau
    // d'hôpital ne partagent pas un quota IP. Le quota SQL durable complète ce
    // garde-fou local et reste exact entre toutes les instances.
    if (applyRateLimit("messagerie-validate", userId, { max: 60, windowMs: 60_000 })) {
      return new Response(
        JSON.stringify({ success: false, error: "RATE_LIMIT" }),
        { status: 429, headers: corsHeaders(req) },
      );
    }

    // Parse body
    const body = await req.json().catch(() => null);
    if (!body || typeof body !== "object") {
      return new Response(
        JSON.stringify({ success: false, error: "BAD_REQUEST" }),
        { status: 400, headers: corsHeaders(req) },
      );
    }

    const { conversation_id, content } = body as { conversation_id?: string; content?: string };
    if (typeof conversation_id !== "string" || typeof content !== "string") {
      return new Response(
        JSON.stringify({ success: false, error: "BAD_REQUEST" }),
        { status: 400, headers: corsHeaders(req) },
      );
    }

    if (content.length > MAX_CONTENT_LENGTH) {
      return new Response(
        JSON.stringify({ success: false, error: "CONTENT_TOO_LARGE", max: MAX_CONTENT_LENGTH }),
        { status: 413, headers: corsHeaders(req) },
      );
    }

    if (content.trim().length === 0) {
      return new Response(
        JSON.stringify({ success: false, error: "CONTENT_EMPTY" }),
        { status: 400, headers: corsHeaders(req) },
      );
    }

    const sanitized = sanitizeContent(content);

    // Vérification user-scoped AVANT toute lecture service_role : évite qu'un
    // UUID de conversation tiers serve d'oracle de statut ou d'audit BOLA.
    const { data: accessibleConv, error: accessibleErr } = await supabase
      .from("conversations")
      .select("id, mission_id, archived_at")
      .eq("id", conversation_id)
      .maybeSingle();
    if (accessibleErr || !accessibleConv) {
      return new Response(
        JSON.stringify({ success: false, error: "CONVERSATION_NON_AUTORISEE" }),
        { status: 403, headers: corsHeaders(req) },
      );
    }
    if (accessibleConv.archived_at) {
      return new Response(
        JSON.stringify({ success: false, error: "CONVERSATION_ARCHIVEE" }),
        { status: 409, headers: corsHeaders(req) },
      );
    }

    const { data: estAdminAutorise, error: adminErr } = await supabase.rpc("est_admin");
    if (adminErr) {
      return new Response(
        JSON.stringify({ success: false, error: "AUTORISATION_INDISPONIBLE" }),
        { status: 503, headers: corsHeaders(req) },
      );
    }

    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL") || "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "",
      { auth: { persistSession: false } },
    );

    // Anti-leak detection — BLOCAGE DUR (décision produit confirmée 02/07/2026 :
    // le message contenant des coordonnées n'est PAS envoyé).
    const detection = detecterLeak(sanitized);
    if (detection.blocked) {
      // 7e-1 (§6.4) : après CONFIRMATION de la mission liée, plus de blocage —
      // les coordonnées figurent au contrat, l'échange est légitime.
      const missionResponse = accessibleConv.mission_id
        ? await supabaseAdmin
          .from("missions")
          .select("statut")
          .eq("id", accessibleConv.mission_id)
          .maybeSingle()
        : { data: null };
      const mission = missionResponse.data;
      const statutMission = mission?.statut as string | undefined;
      const coordonneesAutorisees =
        ["ASSIGNEE", "EN_COURS", "TERMINEE"].includes(statutMission || "");

      if (!coordonneesAutorisees) {
        const contentHash = await hashContent(sanitized);

        // 7e-1 : compteur de récidive (flag analytics — blocage identique).
        const { count: recidives } = await supabaseAdmin
          .from("journaux_audit")
          .select("id", { count: "exact", head: true })
          .eq("acteur_id", userId)
          .eq("action", "SYSTEM")
          .filter("details->>evenement", "eq", "MESSAGERIE_ANTI_LEAK_REFUS");

        const { error: auditError } = await supabaseAdmin.from("journaux_audit").insert({
          acteur_id: userId,
          type_acteur: estAdminAutorise
            ? "ADMIN_PLATEFORME"
            : userData.user.app_metadata?.role === "SOIGNANT"
            ? "SOIGNANT"
            : "ADMIN_ETABLISSEMENT",
          action: "SYSTEM",
          type_ressource: "conversations",
          id_ressource: conversation_id,
          details: {
            evenement: "MESSAGERIE_ANTI_LEAK_REFUS",
            detected_type: detection.type,
            content_hash: contentHash,
            content_length: sanitized.length,
            recidive_n: (recidives ?? 0) + 1,
          },
        });
        if (auditError) {
          console.error("[messagerie-validate] anti-leak audit failed", auditError.message);
        }

      // Lot 16 (Couche 4) : événement de risque PAR PAIRE (étab, soignant) —
      // la donnée coule dès maintenant, le batch de scoring/escalade s'active
      // post-launch. La paire se dérive de la mission (etablissement_id) et des
      // participants de la conversation (le soignant = l'autre participant).
        try {
          const { data: convPaire } = await supabaseAdmin
            .from("conversations")
            .select("participant_1_id, participant_2_id, missions(etablissement_id)")
            .eq("id", conversation_id)
            .maybeSingle();
          let etabId = (convPaire as any)?.missions?.etablissement_id as string | undefined;
          const participants = [
            (convPaire as any)?.participant_1_id,
            (convPaire as any)?.participant_2_id,
          ].filter((id): id is string => typeof id === "string");
          const { data: profilsSoignants } = participants.length > 0
            ? await supabaseAdmin.from("soignants").select("id").in("id", participants)
            : { data: [] as Array<{ id: string }> };
          const soignantId = profilsSoignants?.[0]?.id;
          const interlocuteurId = participants.find((id) => id !== soignantId);

          // Une conversation Pool pré-confirmation n'a pas de mission_id. On
          // résout alors l'établissement depuis le vrai participant Auth.
          if (!etabId && interlocuteurId) {
            const { data: membership, error: membershipError } = await supabaseAdmin
              .from("membres_etablissement")
              .select("etablissement_id")
              .eq("user_id", interlocuteurId)
              .eq("actif", true)
              .in("role", ["PROPRIETAIRE", "ADMIN_GROUPE", "RH"])
              .limit(1)
              .maybeSingle();
            if (membershipError) {
              console.warn("[messagerie-validate] pool membership lookup failed", membershipError.message);
            }
            etabId = membership?.etablissement_id;
          }
          if (!etabId && interlocuteurId) {
            const { data: legacyEtab } = await supabaseAdmin
              .from("etablissements")
              .select("id")
              .eq("id", interlocuteurId)
              .is("supprime_le", null)
              .maybeSingle();
            etabId = legacyEtab?.id;
          }
          if (!etabId && interlocuteurId) {
            const { data: authUser } = await supabaseAdmin.auth.admin
              .getUserById(interlocuteurId);
            const metadataEtabId = authUser?.user?.app_metadata?.etablissement_id;
            if (typeof metadataEtabId === "string") {
              const { data: metadataEtab } = await supabaseAdmin
                .from("etablissements")
                .select("id")
                .eq("id", metadataEtabId)
                .is("supprime_le", null)
                .maybeSingle();
              etabId = metadataEtab?.id;
            }
          }
          if (etabId && soignantId) {
            const { error: riskError } = await supabaseAdmin
              .from("evenements_risque_paires")
              .insert({
              etablissement_id: etabId,
              soignant_id: soignantId,
              type_evenement: "CONTACT_TENTE",
              details: {
                detected_type: detection.type,
                content_hash: contentHash,
                recidive_n: (recidives ?? 0) + 1,
                initie_par: userId,
              },
            });
            if (riskError) {
              console.warn("[messagerie-validate] pair risk insert failed", riskError.message);
            }
          }
        } catch (_) {
          // best-effort : le risque ne bloque jamais le refus lui-même.
        }

        return new Response(
          JSON.stringify({
            success: false,
            error: "ANTI_LEAK_REFUSE",
            detected_type: detection.type,
          }),
          { status: 400, headers: corsHeaders(req) },
        );
      }
    }

    const { data: sendData, error: sendError } = await supabaseAdmin.rpc(
      "fn_envoyer_message_valide",
      {
        p_conversation_id: conversation_id,
        p_contenu: sanitized,
        p_acteur_id: userId,
        // Nom SQL historique uniquement : la valeur vient de est_admin(),
        // dont la garde de lancement ne requiert aucun MFA/AAL2.
        p_admin_aal2: estAdminAutorise === true,
        p_detected_type: detection.blocked ? detection.type : null,
      },
    );
    const sendResult = sendData as { success?: boolean; error?: string; message_id?: string } | null;
    if (sendError) {
      if (sendError.code === "P0001" && sendError.message.includes("Trop de messages")) {
        return new Response(
          JSON.stringify({ success: false, error: "RATE_LIMIT" }),
          { status: 429, headers: corsHeaders(req) },
        );
      }
      console.error("[messagerie-validate] atomic send failed", sendError.message);
      return new Response(
        JSON.stringify({ success: false, error: "ENVOI_INDISPONIBLE" }),
        { status: 503, headers: corsHeaders(req) },
      );
    }
    if (!sendResult?.success) {
      if (sendResult?.error === "ANTI_LEAK_REFUSE") {
        return new Response(
          JSON.stringify({
            success: false,
            error: "ANTI_LEAK_REFUSE",
            detected_type: detection.type,
          }),
          { status: 400, headers: corsHeaders(req) },
        );
      }
      return new Response(
        JSON.stringify({ success: false, error: sendResult?.error || "ENVOI_REFUSE" }),
        { status: 403, headers: corsHeaders(req) },
      );
    }

    return new Response(
      JSON.stringify({ success: true, message_id: sendResult.message_id }),
      { status: 200, headers: corsHeaders(req) },
    );
  } catch (err) {
    return new Response(
      JSON.stringify({ success: false, error: "INTERNAL_ERROR", message: String(err) }),
      { status: 500, headers: corsHeaders(req) },
    );
  }
});
