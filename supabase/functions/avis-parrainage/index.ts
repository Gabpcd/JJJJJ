// Post-mission terminée : email de remerciement au soignant avec
// (1) demande d'avis Google (si growth_config.lien_avis_google renseigné) et
// (2) nudge parrainage avec son code. Dédupliqué via emails_post_mission.
// Déclenché par pg_cron (tous les jours 11h UTC) : POST { secret }.

import { createClient } from "npm:@supabase/supabase-js@2";

const SECRET = "jolene-avis-2026";

Deno.serve(async (req) => {
  try {
    const { secret } = await req.json().catch(() => ({}));
    if (secret !== SECRET) return new Response(JSON.stringify({ error: "forbidden" }), { status: 403 });

    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      { auth: { persistSession: false } },
    );
    const RESEND = Deno.env.get("RESEND_API_KEY");
    if (!RESEND) return new Response(JSON.stringify({ error: "RESEND_API_KEY manquante" }), { status: 500 });

    const { data: cfg } = await admin.from("growth_config").select("valeur").eq("cle", "lien_avis_google").maybeSingle();
    const lienAvis = (cfg?.valeur || "").trim();

    const { data: missions, error } = await admin.rpc("fn_missions_terminees_a_remercier");
    if (error) return new Response(JSON.stringify({ error: error.message }), { status: 500 });

    let envoyes = 0;
    for (const m of (missions as any[]) || []) {
      if (!m.soignant_email) continue;
      const lienParrainage = `https://jolene.app/inscription/soignant?parrain=${encodeURIComponent(m.code_parrainage || "")}&utm_source=email&utm_medium=crm&utm_campaign=parrainage-post-mission`;
      const blocAvis = lienAvis
        ? `<p>Si Jolene vous a été utile, <a href="${lienAvis}">un avis Google</a> nous aide énormément à nous faire connaître (2 minutes).</p>`
        : "";
      const blocParrainage = m.code_parrainage
        ? `<p>Vous connaissez un(e) collègue qui cherche des missions ? Partagez votre lien de parrainage :</p>
           <p style="margin:16px 0"><a href="${lienParrainage}" style="background:#E91E8C;color:#fff;padding:12px 24px;border-radius:12px;text-decoration:none;font-weight:bold">Inviter un(e) collègue</a></p>
           <p style="color:#666;font-size:13px">Votre code : <strong>${m.code_parrainage}</strong></p>`
        : `<p>Vous connaissez un(e) collègue qui cherche des missions ? Parlez-lui de <a href="https://jolene.app">jolene.app</a>.</p>`;

      const r = await fetch("https://api.resend.com/emails", {
        method: "POST",
        headers: { "Authorization": `Bearer ${RESEND}`, "Content-Type": "application/json" },
        body: JSON.stringify({
          from: "Gabrielle de Jolene <bonjour@jolene.app>",
          to: [m.soignant_email],
          reply_to: "support@jolene.app",
          subject: `Merci pour votre mission chez ${m.etab_nom} 💜`,
          html: `<div style="font-family:sans-serif;max-width:560px;margin:auto;line-height:1.5">
            <p>Bonjour ${m.soignant_prenom || ""},</p>
            <p>Votre mission chez <strong>${m.etab_nom}</strong> est terminée — merci de faire confiance à Jolene.</p>
            ${blocAvis}
            ${blocParrainage}
            <p>Gabrielle — Jolene</p>
            <p style="color:#999;font-size:11px;margin-top:24px">Jolene SASU — jolene.app · Gérez vos préférences email depuis votre compte.</p>
          </div>`,
        }),
      });
      if (r.ok) {
        envoyes++;
        await admin.from("emails_post_mission").insert({ mission_id: m.mission_id, cible: "SOIGNANT" } as any);
      }
    }

    return new Response(JSON.stringify({ missions: (missions as any[])?.length || 0, envoyes, avis_actif: !!lienAvis }), {
      headers: { "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: (e as Error)?.message || "erreur" }), { status: 500 });
  }
});
