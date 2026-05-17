// Sprint 13-A PR 4 — Edge function notif-match
//
// Endpoint déclenché par trigger DB ou appel manuel quand un soignant
// effectue un SUPER_LIKE sur une mission. Envoie notification push + email
// à l'établissement propriétaire de la mission.
//
// Auth : service_role uniquement (interne).
//
// Payload :
//   { swipe_id: uuid } | { soignant_id, mission_id, direction }
//
// Action :
//   1. Validation direction = 'SUPER_LIKE' (autres directions ignorées)
//   2. Récup mission + étab + soignant
//   3. INSERT notifications (push immédiat + email)
//   4. INSERT journaux_audit (action SYSTEM, traçabilité)

import { createClient } from "npm:@supabase/supabase-js@2";
import { corsHeaders, preflightResponse, jsonResponse } from "../_shared/cors.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const SUPABASE_SECRET_KEY = Deno.env.get("SUPABASE_SECRET_KEY") ?? Deno.env.get("SB_SECRET_KEY") ?? "";

// Cache mémoire du secret vault (sb_secret_*) utilisé par pg_cron / triggers DB.
let _cachedVaultSecret: string | null = null;
async function getVaultCronSecret(sb: any): Promise<string> {
  if (_cachedVaultSecret) return _cachedVaultSecret;
  if (SUPABASE_SECRET_KEY) { _cachedVaultSecret = SUPABASE_SECRET_KEY; return SUPABASE_SECRET_KEY; }
  try {
    const { data } = await sb.rpc("fn_lire_secret_cron");
    if (data && typeof data === "string") { _cachedVaultSecret = data; return data; }
  } catch { /* ignore */ }
  return "";
}

interface NotifPayload {
  swipe_id?: string;
  soignant_id?: string;
  mission_id?: string;
  direction?: string;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return preflightResponse(req);

  const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

  // Auth service_role only (legacy JWT OU sb_secret_* via vault).
  const authHeader = req.headers.get("Authorization") || "";
  const bearer = authHeader.replace(/^Bearer\s+/i, "").trim();
  const vaultSecret = await getVaultCronSecret(admin);
  const matchesLegacy = SERVICE_ROLE_KEY && bearer === SERVICE_ROLE_KEY;
  const matchesNew = vaultSecret && bearer === vaultSecret;
  if (!matchesLegacy && !matchesNew) {
    return jsonResponse(req, { error: "Service role required" }, 401);
  }

  let payload: NotifPayload;
  try {
    payload = await req.json();
  } catch {
    return jsonResponse(req, { error: "Invalid JSON" }, 400);
  }

  let soignantId = payload.soignant_id;
  let missionId = payload.mission_id;
  const direction = payload.direction;

  // Résolution via swipe_id si fourni
  if (payload.swipe_id) {
    const { data: swipe } = await admin
      .from("swipes")
      .select("soignant_id, mission_id, direction")
      .eq("id", payload.swipe_id)
      .maybeSingle();
    if (!swipe) return jsonResponse(req, { error: "swipe_not_found" }, 404);
    soignantId = swipe.soignant_id;
    missionId = swipe.mission_id;
    if (swipe.direction !== "SUPER_LIKE") {
      return jsonResponse(req, { ok: true, skipped: "direction_not_super_like" });
    }
  } else if (direction !== "SUPER_LIKE") {
    return jsonResponse(req, { ok: true, skipped: "direction_not_super_like" });
  }

  if (!soignantId || !missionId) {
    return jsonResponse(req, { error: "missing_soignant_or_mission" }, 400);
  }

  // Récup mission + étab + soignant
  const { data: mission } = await admin
    .from("missions")
    .select("id, intitule, etablissement_id, debut_le")
    .eq("id", missionId)
    .maybeSingle();
  if (!mission) return jsonResponse(req, { error: "mission_not_found" }, 404);

  const { data: soignant } = await admin
    .from("soignants")
    .select("id, prenom, nom, profession")
    .eq("id", soignantId)
    .maybeSingle();
  if (!soignant) return jsonResponse(req, { error: "soignant_not_found" }, 404);

  const prenom = soignant.prenom || "Un soignant";
  const titreMission = mission.intitule || "votre mission";

  // INSERT notification destinée à l'établissement
  const { data: notif, error: notifErr } = await admin
    .from("notifications")
    .insert({
      destinataire_id: mission.etablissement_id,
      type_destinataire: "ETABLISSEMENT",
      type: "MATCHING_SUPER_LIKE",
      titre: "⭐ Intérêt prioritaire pour votre mission",
      corps: `${prenom} a montré un fort intérêt pour ${titreMission}. Découvrez son profil.`,
      lien: `/etablissement/missions/${missionId}/candidatures`,
      type_ressource: "mission",
      id_ressource: missionId,
    })
    .select("id")
    .maybeSingle();

  if (notifErr) {
    console.error("[notif-match] notification insert failed:", notifErr);
    return jsonResponse(req, { error: "notification_insert_failed", details: notifErr.message }, 500);
  }

  // Audit trail (action SYSTEM)
  try {
    await admin.rpc("fn_ecrire_audit_safe" as any, {
      p_acteur_id: soignantId,
      p_type_acteur: "SOIGNANT",
      p_action: "SYSTEM",
      p_type_ressource: "mission",
      p_id_ressource: missionId,
      p_cle_s3: null,
      p_details: {
        sous_action: "matching_super_like_notif_envoyee",
        notification_id: notif?.id,
        etablissement_id: mission.etablissement_id,
      },
      p_ip: null,
      p_navigateur: "edge:notif-match",
    });
  } catch (auditErr) {
    console.warn("[notif-match] audit log skipped:", auditErr);
  }

  return jsonResponse(req, {
    ok: true,
    notification_id: notif?.id,
    destinataire_etab: mission.etablissement_id,
  });
});
