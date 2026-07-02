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
 *   200 + { success: true, sanitized_content }
 *   400 + { success: false, error: 'ANTI_LEAK_REFUSE', detected_type: 'TELEPHONE'|'EMAIL'|'URL'|'HANDLE'|'KEYWORD' }
 *   413 + { success: false, error: 'CONTENT_TOO_LARGE' }
 *   429 + { success: false, error: 'RATE_LIMIT' }
 *   401 + { success: false, error: 'NON_AUTHENTIFIE' }
 *
 * Note : cette function VALIDE uniquement. C'est le client qui doit ensuite
 * appeler fn_envoyer_message si validation passe (200). En cas de refus, le
 * frontend affiche une modale éducative et restaure le contenu pour édition.
 */
import { createClient } from "npm:@supabase/supabase-js@2";
import { applyRateLimit, getClientIp } from "../_shared/rate-limit.ts";
import { detecterLeak, masquerLeaks, sanitizeContent } from "../_shared/anti-leak.ts";

function getCorsOrigin(req: Request): string {
  const origin = req.headers.get("origin") || "";
  if (
    origin === "https://jolene.app" ||
    origin === "https://app.jolene.app" ||
    origin === "https://www.jolene.app" ||
    origin === "http://localhost:5173" ||
    origin === "http://localhost:8080"
  ) return origin;
  return "https://jolene.app";
}

function corsHeaders(req: Request) {
  return {
    "Access-Control-Allow-Origin": getCorsOrigin(req),
    "Access-Control-Allow-Headers":
      "authorization, x-client-info, apikey, content-type",
    "Content-Type": "application/json",
  };
}

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

    // Rate limit par IP (100 req/min)
    const ip = getClientIp(req);
    if (applyRateLimit("messagerie-validate", ip, { max: 100, windowMs: 60_000 })) {
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

    // Anti-leak detection — 7e-1 (Lot 7 v2 §6.4) : MASQUAGE, plus de blocage.
    // Le gré à gré est légal ; l'objectif est le GMV net, pas zéro fuite —
    // et un faux positif ne doit jamais casser l'envoi d'un message.
    const detection = detecterLeak(sanitized);
    if (detection.blocked) {
      const supabaseAdmin = createClient(
        Deno.env.get("SUPABASE_URL") || "",
        Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "",
        { auth: { persistSession: false } },
      );

      // Après CONFIRMATION de la mission liée, plus aucun masquage : les
      // coordonnées s'échangent librement (elles figurent au contrat).
      const { data: conv } = await supabaseAdmin
        .from("conversations")
        .select("mission_id, missions(statut)")
        .eq("id", conversation_id)
        .maybeSingle();
      const statutMission = (conv as any)?.missions?.statut as string | undefined;
      const missionConfirmee = ["ASSIGNEE", "EN_COURS", "TERMINEE"].includes(statutMission || "");

      if (missionConfirmee) {
        return new Response(
          JSON.stringify({ success: true, sanitized_content: sanitized }),
          { status: 200, headers: corsHeaders(req) },
        );
      }

      const contentHash = await hashContent(sanitized);
      const { texte: masque, nb } = masquerLeaks(sanitized);

      // Récidive = flag (compteur), jamais de blocage (faux positifs ≠ UX cassée).
      const { count: recidives } = await supabaseAdmin
        .from("journaux_audit")
        .select("id", { count: "exact", head: true })
        .eq("acteur_id", userId)
        .eq("action", "SYSTEM")
        .filter("details->>evenement", "eq", "CONTACT_LEAK_ATTEMPT");

      await supabaseAdmin.from("journaux_audit").insert({
        acteur_id: userId,
        type_acteur: "SOIGNANT",
        action: "SYSTEM",
        type_ressource: "conversations",
        id_ressource: conversation_id,
        details: {
          evenement: "CONTACT_LEAK_ATTEMPT",
          detected_type: detection.type,
          masque: nb > 0,
          nb_masques: nb,
          recidive_n: (recidives ?? 0) + 1,
          content_hash: contentHash,
          content_length: sanitized.length,
        },
      });

      // Mots-clés seuls (rien à masquer) : le message part tel quel — le
      // signal est loggé, l'utilisateur n'est pas puni pour une phrase ambiguë.
      return new Response(
        JSON.stringify({
          success: true,
          sanitized_content: nb > 0 ? masque : sanitized,
          leak_masque: nb > 0,
          detected_type: detection.type,
        }),
        { status: 200, headers: corsHeaders(req) },
      );
    }

    return new Response(
      JSON.stringify({ success: true, sanitized_content: sanitized }),
      { status: 200, headers: corsHeaders(req) },
    );
  } catch (err) {
    return new Response(
      JSON.stringify({ success: false, error: "INTERNAL_ERROR", message: String(err) }),
      { status: 500, headers: corsHeaders(req) },
    );
  }
});
