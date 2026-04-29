import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
const URL = Deno.env.get("SUPABASE_URL")!;
const KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// Cache du secret attendu (lu depuis vault au premier appel)
let expectedSecret: string | null = null;
async function loadExpectedSecret(sb: any): Promise<string> {
  if (expectedSecret) return expectedSecret;
  // Essayer plusieurs noms d'env (legacy + new asymmetric)
  const envSecret = Deno.env.get("SUPABASE_SECRET_KEY")
    || Deno.env.get("SB_SECRET_KEY")
    || Deno.env.get("CRON_SECRET")
    || "";
  if (envSecret) { expectedSecret = envSecret; return envSecret; }
  // Fallback : lire le secret depuis vault.decrypted_secrets
  // (nécessite que KEY puisse query vault — ce qui est le cas pour service_role)
  try {
    const { data } = await sb.from('vault.decrypted_secrets')
      .select('decrypted_secret')
      .eq('name', 'service_role_key')
      .maybeSingle();
    if (data?.decrypted_secret) { expectedSecret = data.decrypted_secret; return data.decrypted_secret; }
  } catch (_e) { /* ignore */ }
  // Dernier recours : RPC qui lit vault (à créer si besoin)
  try {
    const { data } = await sb.rpc('fn_lire_secret_cron');
    if (data) { expectedSecret = data; return data; }
  } catch (_e) { /* ignore */ }
  return "";
}

Deno.serve(async (req) => {
  try {
    const sb = createClient(URL, KEY);

    // Auth: service_role only — accepte legacy JWT (KEY) OU le secret stocké en vault
    const authHeader = req.headers.get('Authorization') || '';
    const bearer = authHeader.startsWith('Bearer ') ? authHeader.slice(7) : '';
    const vaultSecret = await loadExpectedSecret(sb);
    const validBearers = [KEY, vaultSecret].filter(Boolean);
    if (!bearer || !validBearers.includes(bearer)) {
      return new Response(JSON.stringify({ error: 'Non autorisé' }), {
        status: 401,
        headers: { 'Content-Type': 'application/json' },
      });
    }

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

    // [J2.1.B.2.3.B] Rappels J-1 contrat de travail SALARIE
    let contratTravailRappels = 0;
    try {
      const { data: missionsManquantes } = await sb.rpc("fn_lister_missions_contrat_travail_manquant");
      for (const mission of (missionsManquantes as any[]) || []) {
        const dateDebut = mission.debut_le ? new Date(mission.debut_le).toLocaleDateString('fr-FR') : 'demain';
        const intitule = mission.intitule || 'mission';
        // Email étab
        try {
          await sb.functions.invoke('send-email', {
            body: {
              type: 'CONTRAT_TRAVAIL_RAPPEL_ETAB',
              destinataire_id: mission.etablissement_id,
              data: {
                intitule_mission: intitule,
                prenom_soignant: mission.prenom_soignant,
                nom_soignant: mission.nom_soignant,
                date_debut: dateDebut,
                mission_id: mission.mission_id,
              },
            },
          });
        } catch (e) { console.warn('email étab fail', e); }
        // Email soignant
        try {
          await sb.functions.invoke('send-email', {
            body: {
              type: 'CONTRAT_TRAVAIL_MANQUANT_SOIGNANT',
              destinataire_id: mission.soignant_id,
              data: {
                prenom: mission.prenom_soignant,
                nom_etablissement: mission.nom_etablissement,
                intitule_mission: intitule,
                date_debut: dateDebut,
                mission_id: mission.mission_id,
              },
            },
          });
        } catch (e) { console.warn('email soignant fail', e); }
        // Marquer comme envoyé (idempotence)
        await sb.rpc('fn_marquer_rappel_contrat_travail_envoye', {
          p_mission_id: mission.mission_id,
          p_cible_etab: true,
          p_cible_soignant: true,
        });
        contratTravailRappels++;
      }
    } catch (err) {
      console.error('Erreur rappels contrat travail:', err);
    }
    results.contrat_travail_rappels = contratTravailRappels;

    // [J2.3.B.2] Cron envoi série email onboarding J0-J7
    let serieEnvoyes = 0, serieSkipped = 0, serieErreurs = 0;
    try {
      const { data: aTraiter } = await sb
        .from('serie_email_envois')
        .select('id, utilisateur_id, serie, etape, tentatives')
        .eq('statut', 'PLANIFIE')
        .lt('planifie_le', new Date().toISOString())
        .lt('tentatives', 3)
        .order('planifie_le', { ascending: true })
        .limit(50);

      for (const envoi of (aTraiter as any[]) || []) {
        try {
          // 1. Vérifier conditions de skip métier
          const { data: skipCheck } = await sb.rpc('fn_verifier_skip_serie_onboarding', { p_envoi_id: envoi.id });
          if (skipCheck && (skipCheck as any).skip === true) {
            await sb.from('serie_email_envois').update({
              statut: 'SKIPPED',
              skip_raison: (skipCheck as any).raison,
            }).eq('id', envoi.id);
            await sb.from('journaux_audit').insert({
              acteur_id: null, type_acteur: 'SYSTEME',
              action: 'SERIE_EMAIL_SKIPPED', type_ressource: 'serie_email_envois',
              id_ressource: envoi.id,
              details: { serie: envoi.serie, etape: envoi.etape, raison: (skipCheck as any).raison },
            }).then(() => {}).catch(() => {});
            serieSkipped++;
            continue;
          }

          // 2. Vérifier préférences notifications utilisateur
          const { data: shouldNotify } = await sb.rpc('fn_doit_notifier', {
            p_utilisateur_id: envoi.utilisateur_id,
            p_type_evenement: 'SERIE_ONBOARDING',
            p_canal: 'EMAIL',
          });
          if (shouldNotify === false) {
            await sb.from('serie_email_envois').update({
              statut: 'SKIPPED', skip_raison: 'NOTIFICATION_DESACTIVEE',
            }).eq('id', envoi.id);
            await sb.from('journaux_audit').insert({
              acteur_id: null, type_acteur: 'SYSTEME',
              action: 'SERIE_EMAIL_SKIPPED', type_ressource: 'serie_email_envois',
              id_ressource: envoi.id,
              details: { serie: envoi.serie, etape: envoi.etape, raison: 'NOTIFICATION_DESACTIVEE' },
            }).then(() => {}).catch(() => {});
            serieSkipped++;
            continue;
          }

          // 3. Récupérer les données dynamiques pour le template
          const { data: tplData } = await sb.rpc('fn_obtenir_donnees_template_serie', { p_envoi_id: envoi.id });

          // 4. Construire le type Resend
          const audience = envoi.serie === 'SOIGNANT_ONBOARDING' ? 'SOIGNANT' : 'ETAB';
          const emailType = `SERIE_${audience}_${envoi.etape}`;

          // 5. Invoke send-email
          const { error: emailErr } = await sb.functions.invoke('send-email', {
            body: {
              type: emailType,
              destinataire_id: envoi.utilisateur_id,
              data: tplData || {},
            },
          });

          if (emailErr) throw new Error(emailErr.message || 'invoke error');

          await sb.from('serie_email_envois').update({
            statut: 'ENVOYE',
            envoye_le: new Date().toISOString(),
            tentatives: (envoi.tentatives || 0) + 1,
          }).eq('id', envoi.id);
          await sb.from('journaux_audit').insert({
            acteur_id: null, type_acteur: 'SYSTEME',
            action: 'SERIE_EMAIL_ENVOYE', type_ressource: 'serie_email_envois',
            id_ressource: envoi.id,
            details: { serie: envoi.serie, etape: envoi.etape, type: emailType },
          }).then(() => {}).catch(() => {});
          serieEnvoyes++;

        } catch (err: any) {
          serieErreurs++;
          const newTentatives = (envoi.tentatives || 0) + 1;
          const definitif = newTentatives >= 3;
          await sb.from('serie_email_envois').update({
            statut: definitif ? 'ERREUR' : 'PLANIFIE',
            tentatives: newTentatives,
            erreur_message: err?.message || String(err),
          }).eq('id', envoi.id);
          if (definitif) {
            await sb.from('journaux_audit').insert({
              acteur_id: null, type_acteur: 'SYSTEME',
              action: 'ADMIN_ACTION', type_ressource: 'serie_email_envois',
              id_ressource: envoi.id,
              details: { event: 'SERIE_EMAIL_ERREUR_DEFINITIVE', serie: envoi.serie, etape: envoi.etape, error: err?.message },
            }).then(() => {}).catch(() => {});
          }
          console.error(`[email-cron] Erreur série email ${envoi.id}:`, err);
        }
      }
    } catch (err) {
      console.error('[email-cron] Erreur globale série email:', err);
    }
    results.serie_envoyes = serieEnvoyes;
    results.serie_skipped = serieSkipped;
    results.serie_erreurs = serieErreurs;

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
