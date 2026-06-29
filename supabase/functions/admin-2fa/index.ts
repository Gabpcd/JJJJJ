import { createClient } from "npm:@supabase/supabase-js@2";

// 2FA admin par email (gratuit, alternative au SMS payant).
// actions : status | request | verify. Réservé aux ADMIN_PLATEFORME.

function getCorsOrigin(req: Request): string {
  const origin = req.headers.get("origin") || "";
  if (origin === "https://jolene.app" || origin === "https://app.jolene.app" || origin === "https://www.jolene.app" || origin === "http://localhost:5173" || origin === "http://localhost:8080") return origin;
  return "https://jolene.app";
}
function corsHeaders(req: Request) {
  return { "Access-Control-Allow-Origin": getCorsOrigin(req), "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type", "Content-Type": "application/json" };
}

async function sha256(s: string): Promise<string> {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
  return Array.from(new Uint8Array(buf)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

const VALIDITE_H = 12;        // une vérif 2FA reste valable 12h
const CODE_TTL_MIN = 10;      // un code email expire après 10 min
const MAX_TENTATIVES = 5;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders(req) });
  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader?.startsWith("Bearer ")) return new Response(JSON.stringify({ error: "Non autorisé" }), { status: 401, headers: corsHeaders(req) });
    const token = authHeader.replace("Bearer ", "");

    const url = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const admin = createClient(url, serviceKey, { auth: { persistSession: false } });

    const authClient = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!);
    const { data: { user }, error: authErr } = await authClient.auth.getUser(token);
    if (authErr || !user) return new Response(JSON.stringify({ error: "Token invalide" }), { status: 401, headers: corsHeaders(req) });

    // Le caller doit être ADMIN_PLATEFORME.
    const { data: u } = await admin.auth.admin.getUserById(user.id);
    const role = (u?.user?.app_metadata as any)?.role;
    if (role !== "ADMIN_PLATEFORME") return new Response(JSON.stringify({ error: "Accès admin requis" }), { status: 403, headers: corsHeaders(req) });
    const emailConnexion = u?.user?.email || "";
    const lastSignIn = u?.user?.last_sign_in_at ? new Date(u.user.last_sign_in_at) : null;

    // Destination du code : boîte email RÉELLE paramétrée (admin_securite).
    // Fallback SQL direct car le client service_role + RLS peut ne pas bypass
    // correctement selon la version supabase-js.
    let emailDest = emailConnexion;
    try {
      const { data: rows } = await admin.rpc("fn_lire_email_2fa", { p_admin_id: user.id });
      if (rows) emailDest = String(rows);
    } catch {
      // RPC absente ou erreur → fallback emailConnexion
    }
    const email = emailDest.trim();

    const { action, code } = await req.json().catch(() => ({}));

    // ── STATUS ──────────────────────────────────────────────
    if (action === "status") {
      const { data: row } = await admin.from("admin_2fa_codes").select("verifie_le").eq("admin_id", user.id).maybeSingle();
      const v = (row as any)?.verifie_le ? new Date((row as any).verifie_le) : null;
      const valide = !!v
        && v.getTime() > Date.now() - VALIDITE_H * 3600_000
        && (!lastSignIn || v.getTime() >= lastSignIn.getTime() - 60_000);
      return new Response(JSON.stringify({ valid: valide }), { headers: corsHeaders(req) });
    }

    // ── REQUEST (génère + envoie le code) ───────────────────
    if (action === "request") {
      const c = String(Math.floor(100000 + Math.random() * 900000));
      const hash = await sha256(c);
      const RESEND = Deno.env.get("RESEND_API_KEY");
      if (!RESEND || !email) {
        console.error("[admin-2fa] RESEND_API_KEY ou email destinataire manquant");
        return new Response(JSON.stringify({
          success: false,
          error: "Envoi du code 2FA indisponible. Vérifiez la configuration email admin.",
        }), { status: 503, headers: corsHeaders(req) });
      }

      const { error: upsertErr } = await admin.from("admin_2fa_codes").upsert({
        admin_id: user.id,
        code_hash: hash,
        expire_le: new Date(Date.now() + CODE_TTL_MIN * 60_000).toISOString(),
        tentatives: 0,
      } as any, { onConflict: "admin_id" });
      if (upsertErr) {
        console.error("[admin-2fa] stockage code impossible", upsertErr);
        return new Response(JSON.stringify({
          success: false,
          error: "Impossible de préparer le code 2FA.",
        }), { status: 500, headers: corsHeaders(req) });
      }

      try {
        const resendResp = await fetch("https://api.resend.com/emails", {
          method: "POST",
          headers: { "Authorization": `Bearer ${RESEND}`, "Content-Type": "application/json" },
          body: JSON.stringify({
            from: "Jolene Sécurité <bonjour@jolene.app>",
            to: [email],
            reply_to: "support@jolene.app",
            subject: `Jolene — code de connexion admin : ${c}`,
            html: `<div style="font-family:sans-serif;max-width:480px;margin:auto">
              <h2 style="color:#E91E8C">Connexion administration Jolene</h2>
              <p>Votre code de vérification à usage unique :</p>
              <p style="font-size:32px;font-weight:bold;letter-spacing:8px;color:#111">${c}</p>
              <p style="color:#666;font-size:13px">Ce code expire dans ${CODE_TTL_MIN} minutes. Si vous n'êtes pas à l'origine de cette connexion, changez votre mot de passe immédiatement.</p>
            </div>`,
          }),
        });
        if (!resendResp.ok) {
          const body = await resendResp.text().catch(() => "");
          console.error("[admin-2fa] envoi Resend refusé", resendResp.status, body.slice(0, 500));
          await admin.from("admin_2fa_codes").update({
            code_hash: null,
            expire_le: new Date().toISOString(),
            tentatives: 0,
          } as any).eq("admin_id", user.id);
          return new Response(JSON.stringify({
            success: false,
            error: "Le code 2FA n'a pas pu être envoyé. Vérifiez Resend avant de continuer.",
          }), { status: 502, headers: corsHeaders(req) });
        }
      } catch (e) {
        console.error("[admin-2fa] erreur envoi Resend", e);
        await admin.from("admin_2fa_codes").update({
          code_hash: null,
          expire_le: new Date().toISOString(),
          tentatives: 0,
        } as any).eq("admin_id", user.id);
        return new Response(JSON.stringify({
          success: false,
          error: "Le code 2FA n'a pas pu être envoyé.",
        }), { status: 502, headers: corsHeaders(req) });
      }
      return new Response(JSON.stringify({ success: true, email_masque: email.replace(/^(.).*(@.*)$/, "$1•••$2") }), { headers: corsHeaders(req) });
    }

    // ── VERIFY ──────────────────────────────────────────────
    if (action === "verify") {
      if (!code || !/^\d{6}$/.test(String(code))) return new Response(JSON.stringify({ success: false, error: "Code à 6 chiffres requis." }), { headers: corsHeaders(req) });
      const { data: row } = await admin.from("admin_2fa_codes").select("code_hash, expire_le, tentatives").eq("admin_id", user.id).maybeSingle();
      if (!row || !(row as any).code_hash) return new Response(JSON.stringify({ success: false, error: "Aucun code en attente. Demandez-en un nouveau." }), { headers: corsHeaders(req) });
      if ((row as any).tentatives >= MAX_TENTATIVES) return new Response(JSON.stringify({ success: false, error: "Trop de tentatives. Demandez un nouveau code." }), { headers: corsHeaders(req) });
      if (new Date((row as any).expire_le).getTime() < Date.now()) return new Response(JSON.stringify({ success: false, error: "Code expiré. Demandez-en un nouveau." }), { headers: corsHeaders(req) });

      const hash = await sha256(String(code));
      if (hash !== (row as any).code_hash) {
        await admin.from("admin_2fa_codes").update({ tentatives: ((row as any).tentatives || 0) + 1 } as any).eq("admin_id", user.id);
        return new Response(JSON.stringify({ success: false, error: "Code incorrect." }), { headers: corsHeaders(req) });
      }
      // OK : marquer vérifié + invalider le code.
      await admin.from("admin_2fa_codes").update({ verifie_le: new Date().toISOString(), code_hash: null, tentatives: 0 } as any).eq("admin_id", user.id);
      return new Response(JSON.stringify({ success: true }), { headers: corsHeaders(req) });
    }

    return new Response(JSON.stringify({ error: "Action inconnue" }), { status: 400, headers: corsHeaders(req) });
  } catch (e: any) {
    return new Response(JSON.stringify({ error: e?.message || "Erreur interne" }), { status: 500, headers: corsHeaders(req) });
  }
});
