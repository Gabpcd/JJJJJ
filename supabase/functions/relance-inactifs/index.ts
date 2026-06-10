// Réactivation des soignants inscrits sans candidature — email hebdomadaire
// (Resend) avec le nombre de missions ouvertes pour leur profession + CTA tracé.
// Déclenché par pg_cron (lundi 10h) : POST { secret }.

import { createClient } from "npm:@supabase/supabase-js@2";

const SECRET = "jolene-relance-inactifs-2026";
const MAX_PAR_RUN = 150;

Deno.serve(async (req) => {
  try {
    const { secret } = await req.json().catch(() => ({}));
    if (secret !== SECRET) return new Response(JSON.stringify({ error: "forbidden" }), { status: 403 });

    const url = Deno.env.get("SUPABASE_URL")!;
    const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
    const RESEND = Deno.env.get("RESEND_API_KEY");
    if (!RESEND) return new Response(JSON.stringify({ error: "RESEND_API_KEY manquante" }), { status: 500 });

    // Cibles : inscrits depuis >3 jours, 0 candidature, pas relancés depuis 14 jours.
    const { data: cibles, error } = await admin.rpc("fn_soignants_inactifs_a_relancer", { p_limit: MAX_PAR_RUN });
    if (error) return new Response(JSON.stringify({ error: error.message }), { status: 500 });

    let envoyes = 0;
    for (const s of (cibles as any[]) || []) {
      const prenom = s.prenom || "";
      const nbMissions = Number(s.nb_missions_ouvertes) || 0;
      const sujet = nbMissions > 0
        ? `${prenom}, ${nbMissions} mission${nbMissions > 1 ? "s" : ""} vous attendent sur Jolene`
        : `${prenom}, votre profil Jolene est prêt — les missions arrivent`;
      const cta = `https://jolene.app/soignant/recherche-missions?utm_source=email&utm_medium=crm&utm_campaign=reactivation`;
      const corps = `
        <p>Bonjour ${prenom},</p>
        <p>Vous avez créé votre profil Jolene mais n'avez pas encore postulé.</p>
        ${nbMissions > 0
          ? `<p><strong>${nbMissions} mission${nbMissions > 1 ? "s" : ""} ouverte${nbMissions > 1 ? "s" : ""}</strong> correspond${nbMissions > 1 ? "ent" : ""} à votre profession en ce moment.</p>`
          : `<p>De nouvelles missions sont publiées chaque jour par des établissements vérifiés.</p>`}
        <p style="margin:24px 0"><a href="${cta}" style="background:#E91E8C;color:#fff;padding:12px 24px;border-radius:12px;text-decoration:none;font-weight:bold">Voir les missions</a></p>
        <p>Besoin d'aide pour finaliser votre profil ? Répondez simplement à cet email.</p>
        <p>Gabrielle — Jolene</p>`;

      const r = await fetch("https://api.resend.com/emails", {
        method: "POST",
        headers: { "Authorization": `Bearer ${RESEND}`, "Content-Type": "application/json" },
        body: JSON.stringify({
          from: "Gabrielle de Jolene <bonjour@jolene.app>",
          to: [s.email],
          reply_to: "support@jolene.app",
          subject: sujet,
          html: `<div style="font-family:sans-serif;max-width:560px;margin:auto;line-height:1.5">${corps}
            <p style="color:#999;font-size:11px;margin-top:24px">Jolene SASU — jolene.app · Gérez vos préférences email depuis votre compte.</p></div>`,
        }),
      });
      if (r.ok) {
        envoyes++;
        await admin.from("relances_soignants").insert({ soignant_id: s.id, type: "REACTIVATION" } as any);
      }
    }

    return new Response(JSON.stringify({ cibles: (cibles as any[])?.length || 0, envoyes }), {
      headers: { "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: (e as Error)?.message || "erreur" }), { status: 500 });
  }
});
