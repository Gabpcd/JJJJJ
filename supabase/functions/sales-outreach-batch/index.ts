// Envoi EN MASSE du template de prospection (Resend) — étabs ou soignants.
// Cible : prospects avec email renseigné ET jamais emailés (email_envoye_le NULL).
// Garde anti-doublon : email_envoye_le posé après chaque envoi réussi.
// Rythme : 1 envoi / 600 ms (limite Resend), max 100 par exécution — relancer
// le bouton pour la tranche suivante. Réservé ADMIN_PLATEFORME.

import { createClient } from "npm:@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";

/** Enrobe le corps texte dans un email HTML chaleureux : bandeau marque dégradé,
 *  liens https cliquables soulignés, footer légal/STOP. Inline-CSS only. */
function emailHtmlProspection(corps: string): string {
  const esc = String(corps).replace(/&/g, "&amp;").replace(/</g, "&lt;");
  const lie = esc.replace(/(https?:\/\/[^\s<]+)/g,
    '<a href="$1" style="color:#E84393;font-weight:600;text-decoration:underline">$1</a>');
  const body = lie.replace(/\n/g, "<br/>");
  return `<div style="margin:0;padding:24px 12px;background:#f5f3f9;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif">
  <div style="max-width:560px;margin:0 auto;background:#ffffff;border-radius:18px;overflow:hidden;border:1px solid #efe9f5">
    <div style="background:#FF6BBE;background:linear-gradient(135deg,#FF6BBE 0%,#A66BFF 60%,#6BC5FF 100%);padding:22px 28px">
      <span style="color:#ffffff;font-size:24px;font-weight:800;letter-spacing:-.5px">Jolene</span>
      <span style="color:rgba(255,255,255,.88);font-size:13px;margin-left:8px">soignants vérifiés, sur demande</span>
    </div>
    <div style="padding:26px 28px;color:#1E293B;font-size:15px;line-height:1.65">${body}</div>
    <div style="padding:16px 28px;border-top:1px solid #f0ecf6;color:#9aa0ad;font-size:11px;line-height:1.5">
      Jolene SASU · <a href="https://jolene.app" style="color:#9aa0ad;text-decoration:underline">jolene.app</a><br/>
      Pour ne plus recevoir nos messages, répondez simplement « STOP » à cet email.
    </div>
  </div>
</div>`;
}

function remplir(tpl: string, p: Record<string, unknown>): string {
  return tpl
    .replace(/\{\{\s*nom\s*\}\}/gi, String(p.nom ?? ""))
    .replace(/\{\{\s*prenom\s*\}\}/gi, String(p.prenom ?? ""))
    .replace(/\{\{\s*ville\s*\}\}/gi, String(p.ville ?? ""))
    .replace(/\{\{\s*departement\s*\}\}/gi, String(p.departement ?? ""))
    .replace(/\{\{\s*profession\s*\}\}/gi, String(p.profession ?? ""))
    .replace(/\{\{\s*enseigne\s*\}\}/gi, String(p.enseigne ?? p.nom ?? ""))
    .replace(/\{\{\s*type\s*\}\}/gi, String(p.type_jolene ?? ""));
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders(req) });
  try {
    const auth = req.headers.get("Authorization");
    if (!auth?.startsWith("Bearer ")) return new Response(JSON.stringify({ error: "Non autorisé" }), { status: 401, headers: corsHeaders(req) });
    const url = Deno.env.get("SUPABASE_URL")!;
    const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
    const authClient = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!);
    const { data: { user } } = await authClient.auth.getUser(auth.replace("Bearer ", ""));
    if (!user) return new Response(JSON.stringify({ error: "Token invalide" }), { status: 401, headers: corsHeaders(req) });
    const { data: u } = await admin.auth.admin.getUserById(user.id);
    if ((u?.user?.app_metadata as any)?.role !== "ADMIN_PLATEFORME") {
      return new Response(JSON.stringify({ error: "Accès admin requis" }), { status: 403, headers: corsHeaders(req) });
    }

    const { cible, sujet, corps, departement, limite } = await req.json().catch(() => ({}));
    if (!["ETABLISSEMENT", "SOIGNANT"].includes(cible)) {
      return new Response(JSON.stringify({ error: "cible invalide (ETABLISSEMENT|SOIGNANT)" }), { status: 400, headers: corsHeaders(req) });
    }
    if (!sujet?.trim() || !corps?.trim()) {
      return new Response(JSON.stringify({ error: "Sujet et message requis." }), { status: 400, headers: corsHeaders(req) });
    }
    const RESEND = Deno.env.get("RESEND_API_KEY");
    if (!RESEND) return new Response(JSON.stringify({ error: "RESEND_API_KEY non configurée." }), { status: 500, headers: corsHeaders(req) });

    const table = cible === "ETABLISSEMENT" ? "prospects_etablissements" : "prospects_soignants";
    const pk = cible === "ETABLISSEMENT" ? "finess" : "cle";
    const max = Math.min(Number(limite) || 100, 100);

    let q = admin.from(table).select("*")
      .not("email", "is", null).neq("email", "")
      .is("email_envoye_le", null)
      .limit(max);
    if (departement) q = q.eq("departement", String(departement).toUpperCase());
    const { data: prospects, error: qErr } = await q;
    if (qErr) return new Response(JSON.stringify({ error: qErr.message }), { status: 500, headers: corsHeaders(req) });
    if (!prospects?.length) {
      return new Response(JSON.stringify({ success: true, envoyes: 0, echecs: 0, message: "Aucun prospect avec email non encore contacté." }), { headers: corsHeaders(req) });
    }

    let envoyes = 0; let echecs = 0;
    for (const p of prospects as any[]) {
      const dest = String(p.email).trim();
      if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(dest)) { echecs++; continue; }
      const sujetFinal = remplir(String(sujet), p).slice(0, 150);
      const corpsFinal = remplir(String(corps), p);
      const r = await fetch("https://api.resend.com/emails", {
        method: "POST",
        headers: { "Authorization": `Bearer ${RESEND}`, "Content-Type": "application/json" },
        body: JSON.stringify({
          from: "Gabrielle de Jolene <bonjour@jolene.app>",
          to: [dest],
          reply_to: "gabrielle@jolene.app",
          subject: sujetFinal,
          html: emailHtmlProspection(corpsFinal),
        }),
      });
      if (r.ok) {
        envoyes++;
        await admin.from(table).update({ email_envoye_le: new Date().toISOString() }).eq(pk, p[pk]);
        if (cible === "ETABLISSEMENT") {
          await admin.from("sales_contacts").upsert({
            type: "ETABLISSEMENT", nom: p.nom, ville: p.ville,
            telephone: p.telephone, email: dest, finess: p.finess,
            departement: p.departement, type_etab: p.type_jolene,
            statut: "CONTACTE", notes: `Sourcé automatiquement : email template envoyé en masse · FINESS ${p.finess}`,
          } as any, { onConflict: "finess", ignoreDuplicates: false });
        } else {
          await admin.from("sales_contacts").insert({
            type: "SOIGNANT", nom: `${p.prenom || ""} ${p.nom || ""}`.trim() || dest, ville: p.ville,
            telephone: p.telephone, email: dest, profession: p.profession, departement: p.departement,
            statut: "CONTACTE", notes: `Sourcé automatiquement : email template envoyé en masse`,
          } as any);
        }
      } else {
        echecs++;
      }
      await new Promise((res) => setTimeout(res, 600));
    }

    const { count: restants } = await admin.from(table)
      .select(pk, { count: "exact", head: true })
      .not("email", "is", null).neq("email", "").is("email_envoye_le", null);

    return new Response(JSON.stringify({ success: true, envoyes, echecs, restants: restants ?? 0 }), { headers: corsHeaders(req) });
  } catch (e) {
    return new Response(JSON.stringify({ error: (e as Error)?.message || "Erreur interne" }), { status: 500, headers: corsHeaders(req) });
  }
});
