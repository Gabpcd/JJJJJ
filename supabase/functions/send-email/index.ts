import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

function getCorsOrigin(req: Request): string {
  const origin = req.headers.get("origin") || "";
  if (
    origin === "https://app.joleneapp.com" ||
    origin === "http://localhost:5173" ||
    origin.endsWith(".lovable.app")
  ) {
    return origin;
  }
  return "https://app.joleneapp.com";
}

function corsHeaders(req: Request) {
  return {
    'Access-Control-Allow-Origin': getCorsOrigin(req),
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-supabase-client-platform, x-supabase-client-platform-version, x-supabase-client-runtime, x-supabase-client-runtime-version',
  };
}

const APP_URL = Deno.env.get('APP_URL') || 'https://app.joleneapp.com';

// ─── XSS prevention ─────────────────────────────────────

function escapeHtml(str: unknown): string {
  if (str === null || str === undefined) return '';
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

// ─── Email template helpers ──────────────────────────────

const WRAPPER = (content: string) => `
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width"></head>
<body style="margin:0;padding:0;background:#F8FAFC;font-family:'Segoe UI',Arial,sans-serif;">
  <div style="max-width:600px;margin:0 auto;background:white;border-radius:0 0 12px 12px;overflow:hidden;">
    <div style="background:#0F172A;padding:28px 24px;text-align:center;">
      <span style="color:#17A2B8;font-size:30px;font-weight:bold;letter-spacing:-0.5px;">❤️ Jolene</span>
    </div>
    <div style="padding:36px 28px 24px;">
      ${content}
    </div>
    <div style="border-top:1px solid #E2E8F0;padding:20px 24px;text-align:center;font-size:11px;color:#94A3B8;">
      <p style="margin:0 0 6px;">Jolene SAS — <a href="${APP_URL}" style="color:#17A2B8;text-decoration:none;">joleneapp.com</a></p>
      <p style="margin:0;"><a href="${APP_URL}/cgu" style="color:#94A3B8;text-decoration:none;">CGU</a> · 
         <a href="${APP_URL}/confidentialite" style="color:#94A3B8;text-decoration:none;">Confidentialité</a></p>
      <p style="margin:8px 0 0;font-size:10px;color:#CBD5E1;">🔒 Aucune pièce jointe — consultez tout dans l'app sécurisée.</p>
    </div>
  </div>
</body>
</html>`;

const BUTTON = (text: string, url: string) =>
  `<div style="text-align:center;margin:24px 0;"><a href="${url}" style="display:inline-block;background:#17A2B8;color:white;padding:14px 32px;border-radius:8px;text-decoration:none;font-weight:bold;font-size:15px;">${text}</a></div>`;

const INFO_BOX = (content: string) =>
  `<div style="background:#F0FDFA;border-left:4px solid #17A2B8;padding:16px 18px;margin:16px 0;border-radius:0 8px 8px 0;">${content}</div>`;

const CARD_BOX = (content: string) =>
  `<div style="background:#F0FDFA;border:1px solid #17A2B8;border-radius:8px;padding:16px 18px;margin:16px 0;">${content}</div>`;

const SECURITY_NOTE = `<p style="font-size:12px;color:#94A3B8;text-align:center;margin-top:20px;">🔒 Pour votre sécurité, connectez-vous à l'app pour consulter les détails.</p>`;

// ─── Template registry ───────────────────────────────────

const ALLOWED_TYPES = new Set([
  'BIENVENUE_SOIGNANT', 'BIENVENUE_ETABLISSEMENT',
  'MISSION_ACCEPTEE_SOIGNANT', 'MISSION_ACCEPTEE_ETABLISSEMENT',
  'RAPPEL_MISSION', 'MISSION_TERMINEE',
  'CONTRAT_A_SIGNER', 'CONTRAT_SIGNE',
  'FACTURE_EMISE', 'FACTURE_PAYEE',
  'DOCUMENT_EXPIRANT', 'RAPPEL_FACTURE',
  'ELIGIBLE_LIBERAL', 'RECAP_HEBDO',
]);

interface TemplateResult { subject: string; html: string }

function renderTemplate(type: string, rawData: Record<string, unknown>): TemplateResult | null {
  const data: Record<string, string> = {};
  for (const [key, value] of Object.entries(rawData)) {
    data[key] = escapeHtml(value);
  }

  switch (type) {
    case 'BIENVENUE_SOIGNANT':
      return {
        subject: `Bienvenue sur Jolene ! 🎉`,
        html: WRAPPER(`
          <h2 style="color:#0F172A;margin:0 0 12px;">Bienvenue ${data.prenom} ! 🎉</h2>
          <p style="color:#334155;">Votre compte soignant est créé. Voici les prochaines étapes :</p>
          ${INFO_BOX(`
            <strong style="color:#0F172A;">1.</strong> Complétez votre profil (RPPS, adresse)<br/>
            <strong style="color:#0F172A;">2.</strong> Téléversez vos documents (diplôme, RCP, identité)<br/>
            <strong style="color:#0F172A;">3.</strong> Parcourez les missions près de chez vous
          `)}
          ${BUTTON('Compléter mon profil →', `${APP_URL}/soignant/profil`)}
        `),
      };

    case 'BIENVENUE_ETABLISSEMENT':
      return {
        subject: 'Bienvenue sur Jolene !',
        html: WRAPPER(`
          <h2 style="color:#0F172A;margin:0 0 12px;">Bienvenue ${data.nom} !</h2>
          <p style="color:#334155;">Votre établissement est enregistré sur Jolene.</p>
          ${INFO_BOX(`
            <strong style="color:#0F172A;">1.</strong> Complétez votre profil (SIRET, FINESS, adresse)<br/>
            <strong style="color:#0F172A;">2.</strong> Publiez votre première mission<br/>
            <strong style="color:#0F172A;">3.</strong> Recevez des candidatures en quelques heures
          `)}
          ${BUTTON('Publier une mission →', `${APP_URL}/etablissement/missions/creer`)}
        `),
      };

    case 'MISSION_ACCEPTEE_SOIGNANT':
      return {
        subject: `Mission confirmée : ${data.mission}`,
        html: WRAPPER(`
          <h2 style="color:#0F172A;margin:0 0 12px;">Mission confirmée ✅</h2>
          <p style="color:#334155;">Bonjour ${data.prenom},</p>
          ${CARD_BOX(`
            <strong style="color:#0F172A;">${data.mission}</strong><br/>
            <span style="color:#334155;">📍 ${data.etablissement}</span><br/>
            <span style="color:#334155;">📅 ${data.date}</span><br/>
            <span style="color:#334155;">🕐 ${data.heure_debut} → ${data.heure_fin}</span><br/>
            <span style="color:#334155;">💰 ${data.taux_horaire} €/h</span>
          `)}
          <p style="color:#334155;">⚠️ Pensez à <strong>signer votre contrat</strong> dans l'app avant le début de la mission.</p>
          ${BUTTON('Voir la mission →', `${APP_URL}/soignant/missions/${data.mission_id || ''}`)}
          ${SECURITY_NOTE}
        `),
      };

    case 'MISSION_ACCEPTEE_ETABLISSEMENT':
      return {
        subject: `Mission acceptée : ${data.mission}`,
        html: WRAPPER(`
          <h2 style="color:#0F172A;margin:0 0 12px;">Mission acceptée par un soignant ✅</h2>
          <p style="color:#334155;">Bonjour,</p>
          <p style="color:#334155;"><strong>${data.soignant_nom}</strong> (${data.profession || 'soignant'}) a accepté votre mission :</p>
          ${CARD_BOX(`
            <strong style="color:#0F172A;">${data.mission}</strong><br/>
            <span style="color:#334155;">📅 ${data.date}</span>
          `)}
          <p style="color:#334155;">Un contrat sera généré automatiquement. Vous recevrez un email pour le signer.</p>
          ${BUTTON('Voir la mission →', `${APP_URL}/etablissement/missions/${data.mission_id || ''}`)}
          ${SECURITY_NOTE}
        `),
      };

    case 'CONTRAT_A_SIGNER':
      return {
        subject: `Contrat à signer : ${data.mission}`,
        html: WRAPPER(`
          <h2 style="color:#0F172A;margin:0 0 12px;">📝 Contrat à signer</h2>
          <p style="color:#334155;">Bonjour ${data.prenom || ''},</p>
          <p style="color:#334155;">Un contrat a été généré pour la mission <strong>"${data.mission}"</strong>.</p>
          ${INFO_BOX('Vous devez le signer <strong>avant le début de la mission</strong> pour pouvoir pointer votre arrivée.')}
          ${BUTTON('Signer le contrat →', `${APP_URL}/contrat/${data.contrat_id}`)}
          ${SECURITY_NOTE}
        `),
      };

    case 'CONTRAT_SIGNE':
      return {
        subject: `Contrat signé : ${data.mission}`,
        html: WRAPPER(`
          <h2 style="color:#0F172A;margin:0 0 12px;">✅ Contrat signé par les deux parties</h2>
          <p style="color:#334155;">Bonjour ${data.prenom || ''},</p>
          <p style="color:#334155;">Le contrat pour la mission <strong>"${data.mission}"</strong> est désormais signé par les deux parties.</p>
          ${INFO_BOX('Le soignant peut maintenant pointer son arrivée le jour de la mission.')}
          ${BUTTON('Voir le contrat →', `${APP_URL}/contrat/${data.contrat_id}`)}
          ${SECURITY_NOTE}
        `),
      };

    case 'MISSION_TERMINEE':
      return {
        subject: `Mission terminée : ${data.mission}`,
        html: WRAPPER(`
          <h2 style="color:#0F172A;margin:0 0 12px;">✅ Mission terminée</h2>
          <p style="color:#334155;">Bonjour ${data.prenom},</p>
          ${CARD_BOX(`
            <strong style="color:#0F172A;">${data.mission}</strong><br/>
            <span style="color:#334155;">📍 ${data.etablissement}</span><br/>
            <span style="color:#334155;">🕐 ${data.heures}h travaillées</span><br/>
            <span style="color:#334155;">💰 Net à payer : <strong>${data.net} €</strong></span>
          `)}
          <p style="color:#334155;">N'oubliez pas d'évaluer l'établissement !</p>
          ${BUTTON('Voir mes gains →', `${APP_URL}/soignant/mes-gains`)}
          ${SECURITY_NOTE}
        `),
      };

    case 'FACTURE_EMISE':
      return {
        subject: `Facture ${data.numero} — Jolene`,
        html: WRAPPER(`
          <h2 style="color:#0F172A;margin:0 0 12px;">Facture ${data.numero}</h2>
          <p style="color:#334155;">Bonjour,</p>
          ${CARD_BOX(`
            <strong style="color:#0F172A;">Facture ${data.numero}</strong><br/>
            <span style="color:#334155;">Montant HT : ${data.montant_ht} €</span><br/>
            <span style="color:#334155;">TVA : ${data.montant_tva} €</span><br/>
            <span style="color:#334155;">Montant TTC : <strong>${data.montant_ttc} €</strong></span><br/>
            <span style="color:#334155;">Échéance : 30 jours</span>
          `)}
          ${BUTTON('💳 Consulter et payer →', `${APP_URL}/etablissement/facturation/${data.facture_id || ''}`)}
          ${SECURITY_NOTE}
        `),
      };

    case 'FACTURE_PAYEE':
      return {
        subject: `Paiement confirmé — Facture ${data.numero}`,
        html: WRAPPER(`
          <h2 style="color:#0F172A;margin:0 0 12px;">💳 Paiement confirmé</h2>
          <p style="color:#334155;">Bonjour,</p>
          ${CARD_BOX(`
            <strong style="color:#0F172A;">Facture ${data.numero}</strong><br/>
            <span style="color:#334155;">Montant TTC : <strong>${data.montant_ttc} €</strong></span><br/>
            <span style="color:#334155;">Date de paiement : ${data.date_paiement}</span>
          `)}
          <p style="color:#334155;">Merci pour votre règlement. Votre facture est disponible dans l'app.</p>
          ${BUTTON('Voir la facture →', `${APP_URL}/etablissement/facturation/${data.facture_id || ''}`)}
          ${SECURITY_NOTE}
        `),
      };

    case 'RAPPEL_MISSION':
      return {
        subject: `Rappel : mission demain — ${data.mission}`,
        html: WRAPPER(`
          <h2 style="color:#0F172A;margin:0 0 12px;">📅 Rappel mission J-1</h2>
          <p style="color:#334155;">Bonjour ${data.prenom},</p>
          <p style="color:#334155;">Votre mission <strong>"${data.mission}"</strong> commence demain.</p>
          ${CARD_BOX(`
            <strong style="color:#0F172A;">${data.mission}</strong><br/>
            <span style="color:#334155;">📍 ${data.etablissement}</span><br/>
            <span style="color:#334155;">🕐 ${data.heure_debut} → ${data.heure_fin}</span>
          `)}
          ${INFO_BOX('Assurez-vous que votre contrat est signé et vos documents à jour.')}
          ${BUTTON('Voir la mission →', `${APP_URL}/soignant/missions/${data.mission_id || ''}`)}
          ${SECURITY_NOTE}
        `),
      };

    case 'DOCUMENT_EXPIRANT':
      return {
        subject: `Document expirant : ${data.type_document}`,
        html: WRAPPER(`
          <h2 style="color:#0F172A;margin:0 0 12px;">⚠️ Document bientôt expiré</h2>
          <p style="color:#334155;">Bonjour ${data.prenom},</p>
          <p style="color:#334155;">Votre document <strong>"${data.type_document}"</strong> expire le <strong>${data.date_expiration}</strong>.</p>
          ${INFO_BOX('Sans ce document à jour, vous ne pourrez plus postuler à de nouvelles missions.')}
          ${BUTTON('Mettre à jour →', `${APP_URL}/soignant/documents`)}
          ${SECURITY_NOTE}
        `),
      };

    case 'RAPPEL_FACTURE':
      return {
        subject: `Rappel : facture ${data.numero} en attente`,
        html: WRAPPER(`
          <h2 style="color:#0F172A;margin:0 0 12px;">💳 Rappel de paiement</h2>
          <p style="color:#334155;">Bonjour,</p>
          <p style="color:#334155;">La facture <strong>${data.numero}</strong> d'un montant de <strong>${data.montant_ttc} € TTC</strong> est toujours en attente de paiement.</p>
          ${INFO_BOX(`Échéance : <strong>${data.date_echeance}</strong>`)}
          ${BUTTON('Consulter et payer →', `${APP_URL}/etablissement/facturation/${data.facture_id || ''}`)}
          ${SECURITY_NOTE}
        `),
      };

    case 'ELIGIBLE_LIBERAL':
      return {
        subject: 'Vous êtes éligible au passage en libéral ! 🎉',
        html: WRAPPER(`
          <h2 style="color:#0F172A;margin:0 0 12px;">🎉 Éligible au passage en libéral</h2>
          <p style="color:#334155;">Bonjour ${data.prenom},</p>
          <p style="color:#334155;">Vous avez cumulé <strong>${data.heures_totales}h</strong> et êtes désormais éligible au passage en exercice libéral.</p>
          ${INFO_BOX('Jolene vous accompagne dans toutes les démarches : SIRET, assurance RCP, compte bancaire pro.')}
          ${BUTTON('Découvrir le parcours →', `${APP_URL}/soignant/passer-en-liberal`)}
          ${SECURITY_NOTE}
        `),
      };

    case 'RECAP_HEBDO':
      return {
        subject: 'Votre récap hebdomadaire — Jolene',
        html: WRAPPER(`
          <h2 style="color:#0F172A;margin:0 0 12px;">📊 Récap de la semaine</h2>
          <p style="color:#334155;">Bonjour ${data.prenom},</p>
          ${CARD_BOX(`
            <strong style="color:#0F172A;">Semaine du ${data.periode}</strong><br/>
            <span style="color:#334155;">✅ Missions réalisées : <strong>${data.missions_terminees}</strong></span><br/>
            <span style="color:#334155;">🕐 Heures travaillées : <strong>${data.heures}h</strong></span><br/>
            <span style="color:#334155;">💰 Gains nets : <strong>${data.gains_nets} €</strong></span>
          `)}
          ${BUTTON('Voir le détail →', `${APP_URL}/soignant/gains`)}
          ${SECURITY_NOTE}
        `),
      };

    default:
      return null;
  }
}

// ─── Main handler ────────────────────────────────────────

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders(req) });
  }

  // Vérification stricte du JWT
  const authHeader = req.headers.get('Authorization');
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return new Response(JSON.stringify({ error: 'Non autorisé' }), {
      status: 401,
      headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
    });
  }

  const token = authHeader.replace('Bearer ', '');
  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  const supabaseAnonKey = Deno.env.get('SUPABASE_ANON_KEY')!;
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

  // C1: Strict equality for service_role validation (prevents partial key match)
  const isServiceRole = authHeader === `Bearer ${serviceRoleKey}`;

  let userId: string | null = null;
  let userEmail: string | null = null;

  if (!isServiceRole) {
    const supabaseAuth = createClient(supabaseUrl, supabaseAnonKey);
    const { data: { user }, error: authError } = await supabaseAuth.auth.getUser(token);
    if (authError || !user) {
      return new Response(JSON.stringify({ error: 'Token invalide' }), {
        status: 401,
        headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
      });
    }
    userId = user.id;
    userEmail = user.email || null;
  }

  try {
    const body = await req.json();
    const { type, data: templateData, destinataire_id } = body;

    // Strict validation: only type + destinataire_id accepted
    if (!type || !destinataire_id) {
      return new Response(JSON.stringify({ error: 'Paramètres requis : type, destinataire_id, data' }), {
        status: 400,
        headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
      });
    }

    // C2-FIX: Validate destinataire_id is a strict UUID to prevent PostgREST filter injection
    const UUID_REGEX = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
    if (!UUID_REGEX.test(destinataire_id)) {
      return new Response(JSON.stringify({ error: 'destinataire_id invalide' }), {
        status: 400,
        headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
      });
    }

    if (!ALLOWED_TYPES.has(type)) {
      return new Response(JSON.stringify({ error: 'Type inconnu' }), {
        status: 400,
        headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
      });
    }

    // Resolve email server-side from destinataire_id
    const supabaseService = createClient(supabaseUrl, serviceRoleKey);

    // Try auth.users first, then etablissements
    let resolvedEmail: string | null = null;

    const { data: authUser } = await supabaseService.auth.admin.getUserById(destinataire_id);
    if (authUser?.user?.email) {
      resolvedEmail = authUser.user.email;
    } else {
      // Could be an etablissement_id
      const { data: etab } = await supabaseService.from('etablissements').select('email_contact').eq('id', destinataire_id).single();
      if (etab?.email_contact) {
        resolvedEmail = etab.email_contact;
      }
    }

    if (!resolvedEmail) {
      return new Response(JSON.stringify({ error: 'Destinataire introuvable' }), {
        status: 404,
        headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
      });
    }

    // Authorization: non-service-role users can only send to themselves
    // or to someone linked via a shared mission
    if (!isServiceRole && destinataire_id !== userId) {
      // Check if caller and destinataire share at least one mission
      const { count } = await supabaseService
        .from('missions')
        .select('id', { count: 'exact', head: true })
        .or(
          `and(etablissement_id.eq.${userId},soignant_assigne_id.eq.${destinataire_id}),` +
          `and(etablissement_id.eq.${destinataire_id},soignant_assigne_id.eq.${userId})`
        );

      // Also check if caller is an admin of the same groupe as the destinataire etablissement
      let isGroupeAdmin = false;
      if (!count) {
        const { data: adminData } = await supabaseService
          .from('admins_groupe_sante')
          .select('groupe_id')
          .eq('utilisateur_id', userId!);

        if (adminData && adminData.length > 0) {
          const groupeIds = adminData.map((a: any) => a.groupe_id);
          const { count: etabCount } = await supabaseService
            .from('etablissements')
            .select('id', { count: 'exact', head: true })
            .eq('id', destinataire_id)
            .in('groupe_sante_id', groupeIds);
          isGroupeAdmin = (etabCount ?? 0) > 0;
        }
      }

      if (!count && !isGroupeAdmin) {
        return new Response(JSON.stringify({ error: 'Non autorisé à envoyer un email à ce destinataire' }), {
          status: 403,
          headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
        });
      }
    }

    const rendered = renderTemplate(type, templateData || {});
    if (!rendered) {
      return new Response(JSON.stringify({ error: 'Type inconnu' }), {
        status: 400,
        headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
      });
    }

    const { subject, html } = rendered;

    const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY');
    if (!RESEND_API_KEY) {
      console.log('RESEND_API_KEY not configured — email skipped');
      return new Response(JSON.stringify({ success: true, skipped: true }), {
        headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
      });
    }

    const response = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${RESEND_API_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        from: 'Soin Direct <noreply@soindirect.com>',
        to: [resolvedEmail],
        subject,
        html,
      }),
    });

    const resData = await response.json();

    // Log in emails_envoyes
    await supabaseService.from('emails_envoyes').insert({
      destinataire_email: resolvedEmail,
      destinataire_id: destinataire_id,
      type,
      sujet: subject,
      provider_id: resData.id || null,
      statut: response.ok ? 'ENVOYE' : 'ERREUR',
      erreur: response.ok ? null : JSON.stringify(resData),
    });

    return new Response(JSON.stringify({ success: response.ok }), {
      headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
    });
  } catch (error) {
    console.error('send-email error:', error);
    return new Response(JSON.stringify({ success: false, error: 'Erreur interne' }), {
      status: 500,
      headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
    });
  }
});
