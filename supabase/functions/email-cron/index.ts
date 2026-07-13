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
    // Les appels Edge -> Edge doivent toujours porter explicitement le secret
    // interne. Sans cet en-tete, functions.invoke peut n'envoyer que `apikey`
    // selon la version du client et send-sms rejette alors justement l'appel.
    const sb = createClient(URL, KEY, {
      auth: { persistSession: false },
      global: { headers: { Authorization: `Bearer ${KEY}` } },
    });

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
    let smsJ1 = 0;
    for (const r of r1 || []) {
      // Email rappel J-1 (existant)
      await sb.functions.invoke("send-email", { body: { type: "RAPPEL_MISSION", destinataire_id: r.soignant_id, data: { prenom: r.prenom, mission: r.mission, etablissement: r.etablissement, heure_debut: r.heure_debut } } });
      c++;

      // SMS rappel J-1 en parallèle, best-effort. send-sms vérifie sms_actif AND
      // sms_alertes_actives côté serveur — on filtre déjà ici sur la présence
      // du téléphone pour éviter un appel inutile.
      try {
        const { data: soignant } = await sb.from('soignants')
          .select('telephone, sms_actif, sms_alertes_actives')
          .eq('id', r.soignant_id)
          .maybeSingle();
        const optedIn = !!soignant?.telephone
          && soignant?.sms_actif !== false
          && soignant?.sms_alertes_actives !== false;
        if (optedIn) {
          const intitule = (r.mission || '').toString().slice(0, 40);
          const etab = (r.etablissement || '').toString().slice(0, 30);
          const smsBody = `📅 Rappel : votre mission ${intitule} démarre demain à ${r.heure_debut} chez ${etab}. Bonne journée !`;
          const { error: smsError } = await sb.functions.invoke('send-sms', {
            body: {
              type: 'RAPPEL_MISSION_J1',
              destinataire_id: r.soignant_id,
              telephone: soignant.telephone,
              contenu: smsBody,
              prefix_type: 'RAPPEL_MISSION_J1',
            },
            headers: { Authorization: `Bearer ${KEY}` },
          });
          if (smsError) throw new Error(`send-sms: ${smsError.message}`);
          smsJ1++;
        }
      } catch (e) {
        console.warn('[email-cron] SMS rappel J-1 failed for', r.soignant_id, e);
      }
    }
    results.rappels_j1 = c;
    results.rappels_j1_sms = smsJ1;
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
            });
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
            });
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
          });
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
            });
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

    // [J2.3.C.2] Alertes filtres sauvegardés (QUOTIDIENNE/HEBDOMADAIRE/IMMEDIATE).
    // Boucle sur les filtres éligibles, envoie un email par filtre avec
    // les nouveaux résultats matchants. fn_evaluer_alertes_filtres met à
    // jour dernier_check_le et nb_resultats_dernier_check côté DB.
    let alertesEnvoyees = 0, alertesErreurs = 0;
    try {
      // Param p_frequence = NULL → toutes fréquences (la fenêtre de marge
      // dans la fonction filtre par elle-même : QUOTIDIENNE>23h, etc.).
      const { data: filtresMatchants } = await sb.rpc('fn_evaluer_alertes_filtres', { p_frequence: null });
      for (const fm of ((filtresMatchants as any[]) || [])) {
        try {
          // Récupérer aperçu top 5 résultats
          const { data: apercu } = await sb.rpc('fn_obtenir_apercu_filtre', {
            p_filtre_id: fm.filtre_id, p_since: '1970-01-01T00:00:00Z', p_limit: 5,
          });
          const items = (apercu as any[]) || [];

          // Préparer payload selon audience
          let emailType: string;
          const payload: any = {
            nom_filtre: fm.nom,
            count: fm.nb_nouveaux,
          };
          if (fm.audience === 'SOIGNANT_RECHERCHE_MISSIONS') {
            emailType = 'NOUVELLES_MISSIONS_FILTRE';
            // Récupérer prénom soignant
            const { data: s } = await sb.from('soignants').select('prenom').eq('id', fm.utilisateur_id).maybeSingle();
            payload.prenom = (s as any)?.prenom || '';
            payload.missions = items;
          } else {
            emailType = 'NOUVEAUX_SOIGNANTS_FILTRE';
            const { data: e } = await sb.from('etablissements').select('nom').eq('id', fm.utilisateur_id).maybeSingle();
            payload.nom_etab = (e as any)?.nom || '';
            payload.soignants = items;
          }

          const { error: emailErr } = await sb.functions.invoke('send-email', {
            body: {
              type: emailType,
              destinataire_id: fm.utilisateur_id,
              data: payload,
            },
          });
          if (emailErr) throw new Error(emailErr.message || 'invoke error');

          await sb.from('journaux_audit').insert({
            acteur_id: null, type_acteur: 'SYSTEME',
            action: 'ALERTE_ENVOYEE', type_ressource: 'filtre_sauvegarde',
            id_ressource: fm.filtre_id,
            details: { audience: fm.audience, nb_nouveaux: fm.nb_nouveaux, nom: fm.nom },
          });
          alertesEnvoyees++;
        } catch (err: any) {
          alertesErreurs++;
          console.error('[email-cron] Alerte filtre erreur:', err?.message || err);
        }
      }
    } catch (err) {
      console.error('[email-cron] Erreur globale alertes filtres:', err);
    }
    results.alertes_filtres_envoyees = alertesEnvoyees;
    results.alertes_filtres_erreurs = alertesErreurs;

    // [Refonte.D.1] Médiation litiges : transition automatique MEDIATION_EN_COURS > 7j → REVUE_ADMIN
    try {
      const { data: medRes } = await sb.rpc('fn_basculer_litiges_revue_admin_timeout');
      results.litiges_basculer_revue_admin = (medRes as any)?.count ?? 0;
    } catch (err: any) {
      console.error('[email-cron] Erreur fn_basculer_litiges_revue_admin_timeout:', err?.message || err);
      results.litiges_basculer_revue_admin = -1;
    }

    // [Refonte.D.3] Email J+1 post-mission notation : scan missions TERMINEE 24-48h
    // sans notation pour rappel email aux 2 parties (idempotence via notifications_notation_j1).
    try {
      const { data: rappRes } = await sb.rpc('fn_envoyer_rappels_notation_j1');
      results.rappels_notation_etab = (rappRes as any)?.count_etab ?? 0;
      results.rappels_notation_soignant = (rappRes as any)?.count_soignant ?? 0;
    } catch (err: any) {
      console.error('[email-cron] Erreur fn_envoyer_rappels_notation_j1:', err?.message || err);
      results.rappels_notation_etab = -1;
      results.rappels_notation_soignant = -1;
    }

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

          const { error: smsError } = await sb.functions.invoke('send-sms', {
            body: {
              telephone: email.data.telephone,
              type: email.type,
              contenu: smsContenu,
              destinataire_id: email.destinataire_id,
            },
            headers: { Authorization: `Bearer ${KEY}` },
          });
          if (smsError) throw new Error(`send-sms: ${smsError.message}`);
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
