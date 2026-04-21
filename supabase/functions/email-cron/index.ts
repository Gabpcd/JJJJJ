import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
const URL = Deno.env.get("SUPABASE_URL")!;
const KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
Deno.serve(async (req) => {
  try {
    // Auth: service_role only
    const authHeader = req.headers.get('Authorization');
    if (authHeader !== `Bearer ${KEY}`) {
      return new Response(JSON.stringify({ error: 'Non autorisé' }), {
        status: 401,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    const sb = createClient(URL, KEY);
    const results: Record<string, number> = {};
    const { data: r1 } = await sb.rpc("fn_email_rappels_j1");
    let c = 0;
    for (const r of r1 || []) { await sb.functions.invoke("send-email", { body: { type: "RAPPEL_MISSION", destinataire_id: r.soignant_id, data: { prenom: r.prenom, mission: r.mission, etablissement: r.etablissement, heure_debut: r.heure_debut } } }); c++; }
    results.rappels_j1 = c;
    const { data: v2 } = await sb.rpc("fn_verifier_documents_expirants");
    results.docs_expirants = v2 || 0;
    const { data: v3 } = await sb.rpc("fn_auto_facturation_mensuelle");
    results.factures = v3 || 0;
    const { data: v4 } = await sb.rpc("fn_purger_gps_ancien");
    results.purge_gps = v4 || 0;
    const { data: v5 } = await sb.rpc("fn_nettoyer_tokens_push");
    results.tokens_push = v5 || 0;

    // Traiter la queue d'emails ET SMS (notifications automatiques des triggers DB)
    // [CP-C-3 D] Source de vérité : statut='EN_ATTENTE' (colonne envoye deprecated)
    let emailQueueCount = 0;
    let smsQueueCount = 0;
    const { data: pendingEmails } = await sb.from('email_queue').select('*').eq('statut', 'EN_ATTENTE').order('cree_le').limit(50);
    for (const email of (pendingEmails || [])) {
      try {
        // Si c'est un SMS (type commence par SMS_), envoyer via send-sms
        if (email.type?.startsWith('SMS_') && email.data?.telephone) {
          const smsContenu = email.data.contenu
            ? String(email.data.contenu)
            : email.type === 'SMS_MISSION_URGENTE'
            ? `${email.data.prenom}, mission urgente dispo : ${email.data.mission}. Postulez sur jolene.app`
            : email.type === 'SMS_ANNULATION_TARDIVE'
            ? `Annulation tardive sur "${email.data.mission}". Trouvez un remplaçant sur jolene.app`
            : `Notification Jolene: ${email.data.mission || 'Voir l\'app'}`;

          await sb.functions.invoke('send-sms', {
            body: {
              telephone: email.data.telephone,
              type: email.type,
              contenu: smsContenu,
              destinataire_id: email.destinataire_id,
            },
          });
          smsQueueCount++;
        } else {
          // Email classique
          await sb.functions.invoke('send-email', {
            body: {
              type: email.type,
              destinataire_id: email.destinataire_id,
              destinataire_email: email.destinataire_email,
              data: email.data,
            },
          });
          emailQueueCount++;
        }
        await sb.from('email_queue').update({ statut: 'ENVOYE', envoye: true, envoye_le: new Date().toISOString() }).eq('id', email.id);
      } catch (err: any) {
        await sb.from('email_queue').update({ statut: 'ERREUR', erreur: err?.message || 'Erreur envoi' }).eq('id', email.id);
      }
    }
    results.email_queue = emailQueueCount;
    results.sms_queue = smsQueueCount;

    return new Response(JSON.stringify({ success: true, results }), { headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": (Deno.env.get("APP_URL") || "https://jolene.app") } });
  } catch (err) {
    console.error("email-cron error:", err);
    return new Response(JSON.stringify({ error: "Une erreur interne est survenue." }), { status: 500, headers: { "Content-Type": "application/json" } });
  }
});
