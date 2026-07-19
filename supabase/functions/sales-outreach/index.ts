// Envoi 1-clic d'un email de prospection (Resend) depuis l'onglet Sales admin.
// Passe automatiquement le contact lié en CONTACTE. Réservé ADMIN_PLATEFORME.

import { createClient } from "npm:@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";

/** Enrobe le corps texte dans un email HTML chaleureux : bandeau marque dégradé,
 *  liens https auto-transformés en liens cliquables soulignés, footer légal/STOP.
 *  Inline-CSS uniquement (compatible Gmail/Outlook/Apple Mail), fallback couleur
 *  unie sous le dégradé pour les clients qui ignorent linear-gradient. */
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

    const { email, sujet, corps, contact_id, finess, cle, nom, ville, telephone, profession, departement } = await req.json().catch(() => ({}));
    if (!email || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
      return new Response(JSON.stringify({ error: "Email destinataire invalide." }), { status: 400, headers: corsHeaders(req) });
    }
    if (!sujet?.trim() || !corps?.trim()) {
      return new Response(JSON.stringify({ error: "Sujet et message requis." }), { status: 400, headers: corsHeaders(req) });
    }

    const RESEND = Deno.env.get("RESEND_API_KEY");
    if (!RESEND) return new Response(JSON.stringify({ error: "RESEND_API_KEY non configurée." }), { status: 500, headers: corsHeaders(req) });

    const r = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { "Authorization": `Bearer ${RESEND}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        from: "Gabrielle de Jolene <bonjour@jolene.app>",
        to: [email],
        reply_to: "gabrielle@jolene.app",
        subject: String(sujet).slice(0, 150),
        html: emailHtmlProspection(corps),
      }),
    });
    if (!r.ok) {
      const detail = await r.text().catch(() => "");
      return new Response(JSON.stringify({ error: `Envoi refusé (${r.status})`, detail: detail.slice(0, 200) }), { status: 502, headers: corsHeaders(req) });
    }

    // Suivi pipeline : contact existant → CONTACTE ; sinon création depuis le prospect
    // (étab via finess, soignant via cle). Le contact passe automatiquement en
    // « sourcé / CONTACTÉ » avec une note explicite (anti double-relance).
    const horodatage = new Date().toISOString();
    let crmContactId: string | null = null;
    if (contact_id) {
      await admin.from("sales_contacts").update({ statut: "CONTACTE", maj_le: horodatage }).eq("id", contact_id);
      crmContactId = contact_id;
    } else if (finess) {
      const { data: p } = await admin.from("prospects_etablissements").select("*").eq("finess", finess).maybeSingle();
      if (p) {
        const { data: contact } = await admin.from("sales_contacts").upsert({
          type: "ETABLISSEMENT", nom: (p as any).nom, ville: (p as any).ville,
          telephone: (p as any).telephone, email, finess,
          departement: (p as any).departement, type_etab: (p as any).type_jolene,
          statut: "CONTACTE", notes: `Sourcé automatiquement : email envoyé via Jolene le ${horodatage.slice(0, 10)} · FINESS ${finess}`,
        } as any, { onConflict: "finess", ignoreDuplicates: false }).select("id").single();
        crmContactId = (contact as any)?.id || null;
      }
      await admin.from("prospects_etablissements").update({ email_envoye_le: horodatage }).eq("finess", finess);
    } else if (cle) {
      const { data: contact } = await admin.from("sales_contacts").insert({
        type: "SOIGNANT", nom: nom || email, ville: ville || null,
        telephone: telephone || null, email, profession: profession || null, departement: departement || null,
        statut: "CONTACTE", notes: `Sourcé automatiquement : email envoyé via Jolene le ${horodatage.slice(0, 10)}`,
      } as any).select("id").single();
      crmContactId = (contact as any)?.id || null;
      await admin.from("prospects_soignants").update({ email_envoye_le: horodatage }).eq("cle", cle);
    }

    // Le CRM reprend automatiquement la main : journal, anti-doublon et
    // prochaine relance datée. Un échec de journalisation ne transforme pas un
    // email déjà accepté par Resend en faux échec d'envoi.
    if (crmContactId) {
      const { error: crmError } = await admin.rpc("fn_crm_enregistrer_email_envoye", {
        p_contact_id: crmContactId,
        p_automatisee: false,
        p_details: `Email envoyé via sales-outreach à ${email}`,
      });
      if (crmError) console.error("CRM journalisation email:", crmError.message);
    }

    return new Response(JSON.stringify({ success: true }), { headers: corsHeaders(req) });
  } catch (e) {
    return new Response(JSON.stringify({ error: (e as Error)?.message || "Erreur interne" }), { status: 500, headers: corsHeaders(req) });
  }
});
