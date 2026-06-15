// Envoi 1-clic d'un email de prospection (Resend) depuis l'onglet Sales admin.
// Passe automatiquement le contact lié en CONTACTE. Réservé ADMIN_PLATEFORME.

import { createClient } from "npm:@supabase/supabase-js@2";

function getCorsOrigin(req: Request): string {
  const o = req.headers.get("origin") || "";
  if (["https://jolene.app", "https://app.jolene.app", "https://www.jolene.app", "http://localhost:5173", "http://localhost:8080"].includes(o)) return o;
  return "https://jolene.app";
}
function cors(req: Request) {
  return { "Access-Control-Allow-Origin": getCorsOrigin(req), "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type", "Content-Type": "application/json" };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: cors(req) });
  try {
    const auth = req.headers.get("Authorization");
    if (!auth?.startsWith("Bearer ")) return new Response(JSON.stringify({ error: "Non autorisé" }), { status: 401, headers: cors(req) });
    const url = Deno.env.get("SUPABASE_URL")!;
    const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
    const authClient = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!);
    const { data: { user } } = await authClient.auth.getUser(auth.replace("Bearer ", ""));
    if (!user) return new Response(JSON.stringify({ error: "Token invalide" }), { status: 401, headers: cors(req) });
    const { data: u } = await admin.auth.admin.getUserById(user.id);
    if ((u?.user?.app_metadata as any)?.role !== "ADMIN_PLATEFORME") {
      return new Response(JSON.stringify({ error: "Accès admin requis" }), { status: 403, headers: cors(req) });
    }

    const { email, sujet, corps, contact_id, finess } = await req.json().catch(() => ({}));
    if (!email || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
      return new Response(JSON.stringify({ error: "Email destinataire invalide." }), { status: 400, headers: cors(req) });
    }
    if (!sujet?.trim() || !corps?.trim()) {
      return new Response(JSON.stringify({ error: "Sujet et message requis." }), { status: 400, headers: cors(req) });
    }

    const RESEND = Deno.env.get("RESEND_API_KEY");
    if (!RESEND) return new Response(JSON.stringify({ error: "RESEND_API_KEY non configurée." }), { status: 500, headers: cors(req) });

    const corpsHtml = String(corps).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/\n/g, "<br/>");
    const r = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { "Authorization": `Bearer ${RESEND}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        from: "Gabrielle de Jolene <bonjour@jolene.app>",
        to: [email],
        reply_to: "gabrielle@jolene.app",
        subject: String(sujet).slice(0, 150),
        html: `<div style="font-family:sans-serif;max-width:560px;margin:auto;line-height:1.5">${corpsHtml}
          <p style="color:#999;font-size:11px;margin-top:24px">Jolene SASU — jolene.app · Pour ne plus recevoir nos messages, répondez « STOP ».</p></div>`,
      }),
    });
    if (!r.ok) {
      const detail = await r.text().catch(() => "");
      return new Response(JSON.stringify({ error: `Envoi refusé (${r.status})`, detail: detail.slice(0, 200) }), { status: 502, headers: cors(req) });
    }

    // Suivi pipeline : contact existant → CONTACTE ; sinon création depuis le prospect
    if (contact_id) {
      await admin.from("sales_contacts").update({ statut: "CONTACTE", maj_le: new Date().toISOString() }).eq("id", contact_id);
    } else if (finess) {
      const { data: p } = await admin.from("prospects_etablissements").select("*").eq("finess", finess).maybeSingle();
      if (p) {
        await admin.from("sales_contacts").upsert({
          type: "ETABLISSEMENT", nom: (p as any).nom, ville: (p as any).ville,
          telephone: (p as any).telephone, email, finess,
          statut: "CONTACTE", notes: `Email envoyé via Jolene · FINESS ${finess}`,
        } as any, { onConflict: "finess", ignoreDuplicates: false });
      }
    }

    return new Response(JSON.stringify({ success: true }), { headers: cors(req) });
  } catch (e) {
    return new Response(JSON.stringify({ error: (e as Error)?.message || "Erreur interne" }), { status: 500, headers: cors(req) });
  }
});
