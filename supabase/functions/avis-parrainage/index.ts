// Post-mission terminée : email de remerciement au soignant avec
// (1) demande d'avis Google (si growth_config.lien_avis_google renseigné) et
// (2) nudge parrainage avec son code. Dédupliqué via emails_post_mission.
// Déclenché par pg_cron (tous les jours 11h UTC) : Authorization Bearer service_role/vault.

import { createClient } from "npm:@supabase/supabase-js@2";
import { resolveOperationalTestAccount } from "../_shared/test-account.ts";

// Auth cron : Bearer = service_role (env) ou secret vault sb_secret_* envoyé par
// pg_cron (cf. CLAUDE.md "Auth crons pg_cron"). Plus de secret en dur dans le repo.
let _vaultSecret: string | null = null;
async function bearerAutorise(req: Request): Promise<boolean> {
  const bearer = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "").trim();
  if (!bearer) return false;
  const svc = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
  if (svc && bearer === svc) return true;
  if (_vaultSecret) return bearer === _vaultSecret;
  try {
    const admin = createClient(Deno.env.get("SUPABASE_URL")!, svc, { auth: { persistSession: false } });
    const { data } = await admin.rpc("fn_lire_secret_cron");
    if (data && typeof data === "string") { _vaultSecret = data; return bearer === data; }
  } catch { /* ignore */ }
  return false;
}

Deno.serve(async (req) => {
  try {
    if (!(await bearerAutorise(req))) return new Response(JSON.stringify({ error: "forbidden" }), { status: 403 });

    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      { auth: { persistSession: false } },
    );
    const { data: gardeFou, error: gardeFouError } = await admin
      .from("growth_config")
      .select("valeur")
      .eq("cle", "automatisations_marketing_actives")
      .maybeSingle();
    if (gardeFouError) {
      return new Response(JSON.stringify({ error: gardeFouError.message }), { status: 500 });
    }
    if (gardeFou?.valeur !== "true") {
      return new Response(JSON.stringify({
        success: true,
        skipped: true,
        reason: "PRELANCEMENT_AUTOMATISATIONS_MARKETING_DESACTIVEES",
        envoyes: 0,
      }), { headers: { "Content-Type": "application/json" } });
    }
    const RESEND = Deno.env.get("RESEND_API_KEY");
    if (!RESEND) return new Response(JSON.stringify({ error: "RESEND_API_KEY manquante" }), { status: 500 });

    const { data: cfg } = await admin.from("growth_config").select("valeur").eq("cle", "lien_avis_google").maybeSingle();
    const lienAvis = (cfg?.valeur || "").trim();

    const { data: missions, error } = await admin.rpc("fn_missions_terminees_a_remercier");
    if (error) return new Response(JSON.stringify({ error: error.message }), { status: 500 });

    let envoyes = 0;
    let ignoresTest = 0;
    for (const m of (missions as any[]) || []) {
      if (!m.soignant_email) continue;
      if (typeof m.soignant_id !== "string") {
        return new Response(JSON.stringify({
          error: "Classification du destinataire indisponible",
        }), { status: 503, headers: { "Content-Type": "application/json" } });
      }
      const testAccount = await resolveOperationalTestAccount(
        admin,
        m.soignant_id,
      );
      if (!testAccount.ok) {
        return new Response(JSON.stringify({
          error: "Classification du destinataire indisponible",
        }), { status: 503, headers: { "Content-Type": "application/json" } });
      }
      if (testAccount.isTest) {
        ignoresTest++;
        await Promise.resolve(admin.from("journaux_audit").insert({
          acteur_id: null,
          type_acteur: "SYSTEME",
          action: "NOTIFICATION_SKIPPED",
          type_ressource: "email",
          id_ressource: m.soignant_id,
          details: {
            fonction: "avis-parrainage",
            canal: "EMAIL",
            raison: "test_account",
            mission_id: m.mission_id,
          },
        })).catch(() => {});
        continue;
      }
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

    return new Response(JSON.stringify({
      missions: (missions as any[])?.length || 0,
      envoyes,
      ignores_test: ignoresTest,
      avis_actif: !!lienAvis,
    }), {
      headers: { "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: (e as Error)?.message || "erreur" }), { status: 500 });
  }
});
