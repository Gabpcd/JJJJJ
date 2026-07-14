// Sprint 13-C PR 4 — Edge function notif-candidature-acceptee
//
// Endpoint déclenché quand une candidature passe à ACCEPTEE (étab accepte).
// Envoie notification push immédiate au soignant : "C'est un match !"
//
// Auth : service_role uniquement (interne, appelable par trigger DB).
// Payload :
//   { candidature_id: uuid } OR { soignant_id, mission_id }

import { createClient } from "npm:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const SUPABASE_SECRET_KEY = Deno.env.get("SUPABASE_SECRET_KEY") ?? Deno.env.get("SB_SECRET_KEY") ?? "";

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

function corsHeaders(req: Request) {
  return {
    "Content-Type": "application/json",
    "Access-Control-Allow-Origin": req.headers.get("origin") || "*",
    "Access-Control-Allow-Headers": "authorization, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
  };
}

function json(req: Request, body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: corsHeaders(req) });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders(req) });

  const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

  const authHeader = req.headers.get("Authorization") || "";
  const bearer = authHeader.replace(/^Bearer\s+/i, "").trim();
  const vaultSecret = await getVaultCronSecret(admin);
  const matchesLegacy = SERVICE_ROLE_KEY && bearer === SERVICE_ROLE_KEY;
  const matchesNew = vaultSecret && bearer === vaultSecret;
  if (!matchesLegacy && !matchesNew) {
    return json(req, { error: "Service role required" }, 401);
  }

  let payload: any;
  try {
    payload = await req.json();
  } catch {
    return json(req, { error: "Invalid JSON" }, 400);
  }

  let soignantId = payload.soignant_id as string | undefined;
  let missionId = payload.mission_id as string | undefined;

  // Résolution candidature_id → soignant + mission
  if (payload.candidature_id) {
    const { data: cand } = await admin
      .from("candidatures")
      .select("soignant_id, mission_id, statut")
      .eq("id", payload.candidature_id)
      .maybeSingle();
    if (!cand) return json(req, { error: "candidature_not_found" }, 404);
    if (cand.statut !== "ACCEPTEE") {
      return json(req, { ok: true, skipped: "candidature_not_accepted" });
    }
    soignantId = cand.soignant_id;
    missionId = cand.mission_id;
  }

  if (!soignantId || !missionId) {
    return json(req, { error: "missing_soignant_or_mission" }, 400);
  }

  const { data: mission } = await admin
    .from("missions")
    .select("id, intitule, etablissement_id, soignant_assigne_id, statut")
    .eq("id", missionId)
    .maybeSingle();
  if (!mission) return json(req, { error: "mission_not_found" }, 404);
  if (mission.soignant_assigne_id !== soignantId || !["ASSIGNEE", "EN_COURS", "TERMINEE"].includes(mission.statut)) {
    return json(req, { ok: true, skipped: "mission_not_assigned_to_caregiver" });
  }

  const { data: etab } = await admin
    .from("etablissements")
    .select("id, nom")
    .eq("id", mission.etablissement_id)
    .maybeSingle();

  const etabNom = etab?.nom || "L'établissement";
  const titreMission = mission.intitule || "votre mission";

  // Vérifier qu'un swipe LIKE/SUPER_LIKE existe (match via swipe)
  const { data: swipe } = await admin
    .from("swipes")
    .select("direction")
    .eq("soignant_id", soignantId)
    .eq("mission_id", missionId)
    .in("direction", ["LIKE", "SUPER_LIKE"])
    .maybeSingle();

  const viaSwipe = !!swipe;
  const titre = viaSwipe ? "🎉 C'est un match !" : "Candidature acceptée";
  const corps = viaSwipe
    ? `${etabNom} a accepté votre candidature pour ${titreMission}. Bravo !`
    : `${etabNom} a accepté votre candidature pour ${titreMission}.`;

  // Un seul chemin SQL transactionnel sérialise création et retries, résout le
  // vrai interlocuteur Auth et retourne la route canonique. L'Edge ne fait
  // volontairement aucun INSERT direct dans notifications.
  const { data: notificationData, error: notificationError } = await admin.rpc(
    "fn_notifier_candidature_acceptee",
    {
      p_mission_id: missionId,
      p_soignant_id: soignantId,
      p_titre: titre,
      p_corps: corps,
    },
  );
  const notificationResult = notificationData as {
    success?: boolean;
    error?: string;
    notification_id?: string;
    lien?: string;
  } | null;
  if (notificationError || !notificationResult?.success) {
    console.error(
      "[notif-candidature-acceptee] transactional notification failed:",
      notificationError?.message || notificationResult?.error,
    );
    return json(req, {
      error: "notification_insert_failed",
      details: notificationError?.message || notificationResult?.error,
    }, 500);
  }
  const lien = notificationResult.lien || `/soignant/missions/${missionId}`;
  const notificationId = notificationResult.notification_id;

  // Audit trail
  try {
    await admin.rpc("fn_ecrire_audit_safe" as any, {
      p_acteur_id: mission.etablissement_id,
      p_type_acteur: "ADMIN_ETABLISSEMENT",
      p_action: "ASSIGNATION",
      p_type_ressource: "mission",
      p_id_ressource: missionId,
      p_cle_s3: null,
      p_details: {
        sous_action: "notif_candidature_acceptee_envoyee",
        notification_id: notificationId,
        soignant_id: soignantId,
        via_swipe: viaSwipe,
      },
      p_ip: null,
      p_navigateur: "edge:notif-candidature-acceptee",
    });
  } catch (auditErr) {
    console.warn("[notif-candidature-acceptee] audit log skipped:", auditErr);
  }

  return json(req, {
    ok: true,
    notification_id: notificationId,
    destinataire_soignant: soignantId,
    via_swipe: viaSwipe,
    lien,
  });
});
