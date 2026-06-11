// Envoi EN MASSE du template de prospection (Resend) — étabs ou soignants.
// Cible : prospects avec email renseigné ET jamais emailés (email_envoye_le NULL).
// Garde anti-doublon : email_envoye_le posé après chaque envoi réussi.
// Rythme : 1 envoi / 600 ms (limite Resend), max 100 par exécution — relancer
// le bouton pour la tranche suivante. Réservé ADMIN_PLATEFORME.

import { createClient } from "npm:@supabase/supabase-js@2";

function getCorsOrigin(req: Request): string {
  const o = req.headers.get("origin") || "";
  if (["https://jolene.app", "https://app.jolene.app", "https://www.jolene.app", "http://localhost:5173", "http://localhost:8080"].includes(o)) return o;
  return "https://jolene.app";
}
function cors(req: Request) {
  return { "Access-Control-Allow-Origin": getCorsOrigin(req), "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type", "Content-Type": "application/json" };
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

    const { cible, sujet, corps, departement, limite } = await req.json().catch(() => ({}));
    if (!["ETABLISSEMENT", "SOIGNANT"].includes(cible)) {
      return new Response(JSON.stringify({ error: "cible invalide (ETABLISSEMENT|SOIGNANT)" }), { status: 400, headers: cors(req) });
    }
    if (!sujet?.trim() || !corps?.trim()) {
      return new Response(JSON.stringify({ error: "Sujet et message requis." }), { status: 400, headers: cors(req) });
    }
    const RESEND = Deno.env.get("RESEND_API_KEY");
    if (!RESEND) return new Response(JSON.stringify({ error: "RESEND_API_KEY non configurée." }), { status: 500, headers: cors(req) });

    const table = cible === "ETABLISSEMENT" ? "prospects_etablissements" : "prospects_soignants";
    const pk = cible === "ETABLISSEMENT" ? "finess" : "cle";
    const max = Math.min(Number(limite) || 100, 100);

    let q = admin.from(table).select("*")
      .not("email", "is", null).neq("email", "")
      .is("email_envoye_le", null)
      .limit(max);
    if (departement) q = q.eq("departement", String(departement).toUpperCase());
    const { data: prospects, error: qErr } = await q;
    if (qErr) return new Response(JSON.stringify({ error: qErr.message }), { status: 500, headers: cors(req) });
    if (!prospects?.length) {
      return new Response(JSON.stringify({ success: true, envoyes: 0, echecs: 0, message: "Aucun prospect avec email non encore contacté." }), { headers: cors(req) });
    }

    let envoyes = 0; let echecs = 0;
    for (const p of prospects as any[]) {
      const dest = String(p.email).trim();
      if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(dest)) { echecs++; continue; }
      const sujetFinal = remplir(String(sujet), p).slice(0, 150);
      const corpsFinal = remplir(String(corps), p);
      const corpsHtml = corpsFinal.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/\n/g, "<br/>");
      const r = await fetch("https://api.resend.com/emails", {
        method: "POST",
        headers: { "Authorization": `Bearer ${RESEND}`, "Content-Type": "application/json" },
        body: JSON.stringify({
          from: "Gabrielle de Jolene <bonjour@jolene.app>",
          to: [dest],
          reply_to: "gabrielle.pcd@outlook.com",
          subject: sujetFinal,
          html: `<div style="font-family:sans-serif;max-width:560px;margin:auto;line-height:1.5">${corpsHtml}
            <p style="color:#999;font-size:11px;margin-top:24px">Jolene SASU — jolene.app · Pour ne plus recevoir nos messages, répondez « STOP ».</p></div>`,
        }),
      });
      if (r.ok) {
        envoyes++;
        await admin.from(table).update({ email_envoye_le: new Date().toISOString() }).eq(pk, p[pk]);
        if (cible === "ETABLISSEMENT") {
          await admin.from("sales_contacts").upsert({
            type: "ETABLISSEMENT", nom: p.nom, ville: p.ville,
            telephone: p.telephone, email: dest, finess: p.finess,
            statut: "CONTACTE", notes: `Email template envoyé en masse · FINESS ${p.finess}`,
          } as any, { onConflict: "finess", ignoreDuplicates: false });
        }
      } else {
        echecs++;
      }
      await new Promise((res) => setTimeout(res, 600));
    }

    const { count: restants } = await admin.from(table)
      .select(pk, { count: "exact", head: true })
      .not("email", "is", null).neq("email", "").is("email_envoye_le", null);

    return new Response(JSON.stringify({ success: true, envoyes, echecs, restants: restants ?? 0 }), { headers: cors(req) });
  } catch (e) {
    return new Response(JSON.stringify({ error: (e as Error)?.message || "Erreur interne" }), { status: 500, headers: cors(req) });
  }
});
