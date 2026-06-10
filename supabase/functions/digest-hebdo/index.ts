// Digest hebdomadaire soignants : nombre de missions ouvertes pour leur
// profession + meilleur taux, CTA tracé. Déclenché par pg_cron (jeudi 9h UTC) :
// POST { secret }.

import { createClient } from "npm:@supabase/supabase-js@2";

const SECRET = "jolene-digest-2026";
const MAX_PAR_RUN = 500;

const LIBELLES: Record<string, string> = {
  IDE: "infirmier(ère)", AS: "aide-soignant(e)", AES: "AES",
  MEDECIN: "médecin", PHARMACIEN: "pharmacien(ne)", DENTISTE: "chirurgien-dentiste",
  KINE: "kinésithérapeute", SAGE_FEMME: "sage-femme",
};

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

    const { data: cibles, error } = await admin.rpc("fn_digest_hebdo_cibles", { p_limit: MAX_PAR_RUN });
    if (error) return new Response(JSON.stringify({ error: error.message }), { status: 500 });

    let envoyes = 0;
    for (const s of (cibles as any[]) || []) {
      const nb = Number(s.nb_missions) || 0;
      if (nb === 0) continue;
      const metier = LIBELLES[s.profession] || "votre profession";
      const taux = s.taux_max ? ` — jusqu'à ${Number(s.taux_max).toFixed(0)} €/h` : "";
      const cta = `https://jolene.app/soignant/recherche-missions?utm_source=email&utm_medium=crm&utm_campaign=digest-hebdo`;
      const r = await fetch("https://api.resend.com/emails", {
        method: "POST",
        headers: { "Authorization": `Bearer ${RESEND}`, "Content-Type": "application/json" },
        body: JSON.stringify({
          from: "Gabrielle de Jolene <bonjour@jolene.app>",
          to: [s.email],
          reply_to: "support@jolene.app",
          subject: `${s.prenom || ""}, ${nb} mission${nb > 1 ? "s" : ""} ${metier} cette semaine${taux}`,
          html: `<div style="font-family:sans-serif;max-width:560px;margin:auto;line-height:1.5">
            <p>Bonjour ${s.prenom || ""},</p>
            <p>Cette semaine sur Jolene : <strong>${nb} mission${nb > 1 ? "s" : ""} ouverte${nb > 1 ? "s" : ""}</strong> pour les ${metier}s${taux}.</p>
            <p style="margin:24px 0"><a href="${cta}" style="background:#E91E8C;color:#fff;padding:12px 24px;border-radius:12px;text-decoration:none;font-weight:bold">Voir les missions</a></p>
            <p>Les missions partent vite — les premiers à postuler sont les premiers servis.</p>
            <p>Gabrielle — Jolene</p>
            <p style="color:#999;font-size:11px;margin-top:24px">Jolene SASU — jolene.app · Gérez vos préférences email depuis votre compte.</p>
          </div>`,
        }),
      });
      if (r.ok) envoyes++;
    }

    return new Response(JSON.stringify({ cibles: (cibles as any[])?.length || 0, envoyes }), {
      headers: { "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: (e as Error)?.message || "erreur" }), { status: 500 });
  }
});
