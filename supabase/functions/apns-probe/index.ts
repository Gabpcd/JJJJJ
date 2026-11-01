// apns-probe — vérifie que les secrets APNS_KEY_P8 / APNS_KEY_ID / APNS_TEAM_ID
// sont acceptés par Apple pour le topic app.jolene (décision 7,
// docs/mobile-swift/DECISIONS_LOT0.md). Réservé aux administrateurs et à la
// clé service_role ; n'envoie rien à un appareil réel ; ne renvoie aucun secret.
// Mode témoin (`temoin: true`) : vise un topic inexistant pour savoir si Apple
// contrôle le topic avant le jeton d'appareil (sinon « auth_ok » ne prouve que
// la signature, pas le droit de pousser vers app.jolene).
import { jsonResponse, preflightResponse } from "../_shared/cors.ts";
import { verifyAdminOrServiceRole } from "../_shared/admin-auth.ts";
import { apnsConfigured, probeApns } from "../_shared/apns-client.ts";

const TEAM_ID_ATTENDU = "GDU5AA28M9";

type Verdict = "auth_ok" | "auth_refusee" | "topic_refuse" | "indetermine" | "non_configure";

function verdictFor(status: number, reason: string): Verdict {
  if (status === 400 && reason === "BadDeviceToken") return "auth_ok";
  if (status === 410) return "auth_ok";
  if (status === 403) return "auth_refusee";
  if (status === 400 && reason === "TopicDisallowed") return "topic_refuse";
  if (status === 400 && (reason === "MissingProviderToken" || reason === "InvalidProviderToken")) return "auth_refusee";
  return "indetermine";
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return preflightResponse(req);
  if (req.method !== "POST") return jsonResponse(req, { error: "Méthode non autorisée" }, 405);

  const auth = await verifyAdminOrServiceRole(req);
  if (!auth.ok) return jsonResponse(req, { error: auth.error }, auth.status);

  let environment: "sandbox" | "production" = "sandbox";
  let temoin = false;
  try {
    const body = await req.json();
    if (body?.environment === "production") environment = "production";
    temoin = body?.temoin === true;
  } catch { /* corps absent : sandbox par défaut */ }
  const bundleId = Deno.env.get("APNS_BUNDLE_ID") || "app.jolene";
  const topic = temoin ? `${bundleId}.sonde-inexistante` : bundleId;

  if (!apnsConfigured()) {
    return jsonResponse(req, {
      verdict: "non_configure" satisfies Verdict,
      environment,
      team_id_attendu: TEAM_ID_ATTENDU,
      message: "APNS_KEY_P8, APNS_KEY_ID ou APNS_TEAM_ID absent des secrets Supabase.",
    }, 503);
  }

  try {
    const result = await probeApns({ environment, topic });
    const verdict = verdictFor(result.status, result.reason);
    const teamIdCorrespond = Deno.env.get("APNS_TEAM_ID") === TEAM_ID_ATTENDU;
    // Témoin concluant = Apple refuse le topic inexistant avant même de lire le
    // jeton d'appareil : la sonde nominale prouve alors le droit sur le topic.
    const ok = temoin ? verdict === "topic_refuse" : (verdict === "auth_ok" && teamIdCorrespond);
    return jsonResponse(req, {
      verdict,
      environment,
      temoin,
      topic: result.topic,
      host: result.host,
      apns_status: result.status,
      apns_reason: result.reason,
      team_id_attendu: TEAM_ID_ATTENDU,
      team_id_configure_longueur: (Deno.env.get("APNS_TEAM_ID") || "").length,
      team_id_correspond: teamIdCorrespond,
      checked_at: new Date().toISOString(),
    }, ok ? 200 : 409);
  } catch (err) {
    console.error("[apns-probe] échec de la sonde", err instanceof Error ? err.message : err);
    return jsonResponse(req, { verdict: "indetermine" satisfies Verdict, environment, error: "Sonde APNs impossible" }, 502);
  }
});
