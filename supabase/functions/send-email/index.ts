import { createClient } from 'npm:@supabase/supabase-js@2.99.2';
import { applyRateLimit, getClientIp } from '../_shared/rate-limit.ts';
import { verifyAdminOrServiceRole } from '../_shared/admin-auth.ts';
import {
  resolveOperationalTestAccount,
  resolveOperationalTestSource,
} from '../_shared/test-account.ts';

function getCorsOrigin(req: Request): string {
  const origin = req.headers.get("origin") || "";
  if (
    origin === "https://jolene.app" ||
    origin === "https://app.jolene.app" ||
    origin === "https://www.jolene.app" ||
    origin === "https://localhost" ||
    origin === "capacitor://localhost" ||
    origin === "http://localhost:5173" ||
    origin === "http://localhost:8080"
  ) {
    return origin;
  }
  return "https://jolene.app";
}

function corsHeaders(req: Request) {
  return {
    'Access-Control-Allow-Origin': getCorsOrigin(req),
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-supabase-client-platform, x-supabase-client-platform-version, x-supabase-client-runtime, x-supabase-client-runtime-version',
  };
}

const APP_URL = Deno.env.get('APP_URL') || 'https://jolene.app';
const BRAND_LOGO_URL = 'https://jolene.app/logo-jolene-carre.png';
// URL publique des edge functions (pour les liens cliquables qui doivent atteindre
// une fonction directement, ex. confirmation e-mail pro de l'établissement).
const FUNCTIONS_URL = (Deno.env.get('SUPABASE_URL') || '').replace(/\/$/, '') + '/functions/v1';

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

function canonicalizeJson(value: unknown): unknown {
  if (Array.isArray(value)) {
    return value.map(canonicalizeJson);
  }
  if (value !== null && typeof value === 'object') {
    const objectValue = value as Record<string, unknown>;
    return Object.fromEntries(
      Object.keys(objectValue)
        .sort()
        .filter((key) => objectValue[key] !== undefined)
        .map((key) => [key, canonicalizeJson(objectValue[key])]),
    );
  }
  return value;
}

async function sha256Hex(value: unknown): Promise<string> {
  const bytes = new TextEncoder().encode(
    JSON.stringify(canonicalizeJson(value)),
  );
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, '0'))
    .join('');
}

// ─── Email template helpers ──────────────────────────────

const WRAPPER = (content: string, opts?: { hasAttachment?: boolean }) => `
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width"></head>
<body style="margin:0;padding:0;background:#F8FAFC;font-family:'Segoe UI',Arial,sans-serif;">
  <div style="max-width:600px;margin:0 auto;background:white;border-radius:0 0 12px 12px;overflow:hidden;">
    <div style="background:#0F172A;padding:28px 24px;text-align:center;">
      <img src="${BRAND_LOGO_URL}" alt="Jolene" width="72" height="72" style="display:block;width:72px;height:72px;margin:0 auto 10px;border:0;border-radius:16px;object-fit:cover;" />
      <span style="display:block;color:#FFFFFF;font-size:25px;font-weight:bold;letter-spacing:-0.5px;">Jolene</span>
    </div>
    <div style="padding:36px 28px 24px;">
      ${content}
    </div>
    <div style="border-top:1px solid #E2E8F0;padding:20px 24px;text-align:center;font-size:11px;color:#94A3B8;line-height:1.6;">
      <p style="margin:0 0 14px;font-size:13px;color:#475569;line-height:1.5;">
        <strong style="color:#1E293B;">Gabrielle Picard</strong><br/>
        Fondatrice — Jolene<br/>
        <span style="color:#94A3B8;">La plateforme qui connecte établissements de santé et soignants vérifiés.</span>
      </p>
      <p style="margin:0 0 6px;">Vous recevez cet email parce que vous êtes inscrit sur <a href="${APP_URL}" style="color:#E04590;text-decoration:none;">jolene.app</a>.</p>
      <p style="margin:0 0 8px;">
        <a href="${APP_URL}/soignant/parametres/notifications" style="color:#94A3B8;">Préférences notifications (soignant)</a> ·
        <a href="${APP_URL}/etablissement/parametres/notifications" style="color:#94A3B8;">Préférences notifications (étab)</a>
      </p>
      <p style="margin:0 0 6px;font-size:10px;color:#CBD5E1;">
        Jolene SASU · 103 rue de Vaugirard, 75006 Paris · RCS Paris 103 305 744
      </p>
      <p style="margin:0;font-size:10px;color:#CBD5E1;">
        <a href="${APP_URL}/cgu" style="color:#CBD5E1;text-decoration:none;">CGU</a> ·
        <a href="${APP_URL}/confidentialite" style="color:#CBD5E1;text-decoration:none;">Confidentialité</a> ·
        <a href="mailto:support@jolene.app" style="color:#CBD5E1;text-decoration:none;">Contact DPO</a>
      </p>
      ${opts?.hasAttachment
        ? `<p style="margin:8px 0 0;font-size:10px;color:#CBD5E1;">📎 Le document est joint à cet email.</p>`
        : `<p style="margin:8px 0 0;font-size:10px;color:#CBD5E1;">🔒 Aucune pièce jointe — consultez tout dans l'app sécurisée.</p>`}
    </div>
  </div>
</body>
</html>`;

const BUTTON = (text: string, url: string) =>
  `<div style="text-align:center;margin:24px 0;"><a href="${url}" style="display:inline-block;background:#E04590;color:white;padding:14px 32px;border-radius:8px;text-decoration:none;font-weight:bold;font-size:15px;">${text}</a></div>`;

const INFO_BOX = (content: string) =>
  `<div style="background:#FDF2F8;border-left:4px solid #E04590;padding:16px 18px;margin:16px 0;border-radius:0 8px 8px 0;">${content}</div>`;

const CARD_BOX = (content: string) =>
  `<div style="background:#FDF2F8;border:1px solid #E04590;border-radius:8px;padding:16px 18px;margin:16px 0;">${content}</div>`;

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
  'RAPPEL_DOCUMENTS', 'MISSION_URGENTE', 'MISSION_PROPOSEE',
  'EVALUATION_RECUE', 'PAIEMENT_CONFIRME', 'PARRAINAGE_PRIME_VERSEE',
  'ADMIN_BROADCAST',
  'MISSION_NON_POURVUE', 'PAIEMENT_RAPIDE_RECU',
  'LITIGE_OUVERTURE', 'LITIGE_NOUVEAU_MESSAGE', 'LITIGE_ESCALADE_ADMIN',
  'LITIGE_RESOLU_AJUSTE', 'AVOIR_EMIS', 'REMBOURSEMENT_CONFIRME',
  'LITIGE_RAPPEL_J1', 'LITIGE_RAPPEL_J3', 'LITIGE_RAPPEL_J5',
  'REGULARISATION_SOCIALE_REQUISE', 'LITIGE_MEDIATION_PRIORITAIRE',
  'COMMISSION_AJUSTEE',
  // [CP-STRIPE-4] 6 templates webhook events Stripe
  'CHARGE_FAILED_ETAB',
  'DISPUTE_OUVERTE_ADMIN', 'DISPUTE_CLOSE_ADMIN',
  'PAYOUT_FAILED_ADMIN', 'PAYOUT_FAILED_SOIGNANT',
  'PAYOUT_CANCELED_ADMIN',
  // [CP-STRIPE-5] template refund process cron
  'REFUND_ECHEC_ADMIN',
  // [CP-C-1] template déclaration paiement soignant par étab
  'PAIEMENT_SOIGNANT_DECLARE',
  // [CP-C-2] relances paiement + blocage
  'RAPPEL_PAIEMENT_J7', 'PAIEMENT_RETARD_J21', 'PUBLICATION_SUSPENDUE',
  // [CP-C-3] déblocage auto post-régularisation
  'PUBLICATION_REACTIVEE',
  // [J2.1.B.2.3] contrat de travail SALARIE étab → soignant
  'CONTRAT_TRAVAIL_DEPOSE', 'CONTRAT_TRAVAIL_RAPPEL_ETAB', 'CONTRAT_TRAVAIL_MANQUANT_SOIGNANT',
  // [J2.3.B] série email welcome onboarding J0-J7
  'SERIE_SOIGNANT_J0','SERIE_SOIGNANT_J1','SERIE_SOIGNANT_J3','SERIE_SOIGNANT_J7',
  'SERIE_ETAB_J0','SERIE_ETAB_J1','SERIE_ETAB_J3','SERIE_ETAB_J7',
  // [J2.3.C] alertes filtres sauvegardés
  'NOUVELLES_MISSIONS_FILTRE','NOUVEAUX_SOIGNANTS_FILTRE',
  // [J5.C] pool urgence push email
  'MISSION_URGENTE_POOL',
  // [J5.G] favoris bidirectionnels
  'FAVORI_NOUVELLE_MISSION',
  // [Refonte.D.2] suspension auto + levée
  'COMPTE_SUSPENDU','COMPTE_REACTIVE',
  // [Refonte.D.3] rappel notation J+1
  'RAPPEL_NOTATION_ETAB','RAPPEL_NOTATION_SOIGNANT',
  // [Sprint 5.7 PR 4 → Sprint 6 PR 1] invitation équipe étab multi-utilisateurs
  'INVITATION_EQUIPE_ETAB',
  // [Sprint 15 PR 3] DPAE déclarée par l'étab → notif soignant avec n° URSSAF
  'DPAE_DECLAREE_SOIGNANT', 'DPAE_ANNULATION_RAPPEL',
  // Fallback idempotent lorsque tous les abonnements push sont invalides
  'NOTIFICATION_PUSH_FALLBACK',
  // Confirmation de l'adresse professionnelle d'un établissement
  'CONFIRMATION_EMAIL_PRO_ETAB',
]);

// Ces messages sont indispensables a la securite du compte, a une obligation
// legale ou au traitement d'un incident financier. Tous les autres types,
// meme absents de l'enum fin des preferences, respectent au minimum canal_email.
const ALWAYS_SEND_TRANSACTIONAL_TYPES = new Set([
  'INVITATION_EQUIPE_ETAB',
  'COMPTE_SUSPENDU', 'COMPTE_REACTIVE',
  'PUBLICATION_SUSPENDUE', 'PUBLICATION_REACTIVEE',
  'REGULARISATION_SOCIALE_REQUISE', 'PAIEMENT_RETARD_J21',
  'CHARGE_FAILED_ETAB',
  'DISPUTE_OUVERTE_ADMIN', 'DISPUTE_CLOSE_ADMIN',
  'PAYOUT_FAILED_ADMIN', 'PAYOUT_FAILED_SOIGNANT', 'PAYOUT_CANCELED_ADMIN',
  'REFUND_ECHEC_ADMIN',
  'DPAE_DECLAREE_SOIGNANT', 'DPAE_ANNULATION_RAPPEL',
]);

interface TemplateResult { subject: string; html: string; hasAttachment?: boolean }

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
          <h2 style="color:#0F172A;margin:0 0 12px;">Bienvenue ${data.prenom || ''} ! 🎉</h2>
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
          <h2 style="color:#0F172A;margin:0 0 12px;">Bienvenue ${data.nom || ''} !</h2>
          <p style="color:#334155;">Votre établissement est enregistré sur Jolene.</p>
          ${INFO_BOX(`
            <strong style="color:#0F172A;">1.</strong> Complétez votre profil (SIRET, FINESS, adresse)<br/>
            <strong style="color:#0F172A;">2.</strong> Publiez votre première mission<br/>
            <strong style="color:#0F172A;">3.</strong> Recevez des candidatures en quelques heures
          `)}
          ${BUTTON('Publier une mission →', `${APP_URL}/etablissement/missions/creer`)}
        `),
      };

    case 'INVITATION_EQUIPE_ETAB': {
      const lienAcceptation = `${APP_URL}/etab/invitation/${data.token || ''}`;
      const roleLabels: Record<string, string> = {
        ADMIN_GROUPE: 'Admin groupe (tout sauf gestion équipe)',
        RH: 'Ressources humaines (missions, candidatures, contrats, pointage)',
        POINTAGE_ONLY: 'Pointage uniquement',
        LECTURE_SEULE: 'Lecture seule (consultations sans actions)',
      };
      const roleLabel = roleLabels[data.role || ''] || data.role || '';
      return {
        subject: `Vous êtes invité à rejoindre ${data.nom_etablissement || 'une équipe'} sur Jolene`,
        html: WRAPPER(`
          <h2 style="color:#0F172A;margin:0 0 12px;">Invitation à rejoindre une équipe</h2>
          <p style="color:#334155;">
            <strong>${data.invite_par_nom || 'L\'administrateur'}</strong> vous invite à rejoindre
            l'équipe <strong>${data.nom_etablissement || ''}</strong> sur Jolene avec le rôle :
          </p>
          ${INFO_BOX(`<strong style="color:#0F172A;">${roleLabel}</strong>`)}
          <p style="color:#334155;">
            Cliquez sur le bouton ci-dessous pour accepter l'invitation. Le lien expire le
            <strong>${data.expire_le || 'dans 7 jours'}</strong>.
          </p>
          ${BUTTON("Accepter l'invitation →", lienAcceptation)}
          <p style="color:#64748B;font-size:13px;margin-top:24px;">
            Si vous n'êtes pas concerné(e) par cette invitation, ignorez simplement cet e-mail —
            elle s'auto-annulera après 7 jours.
          </p>
        `),
      };
    }

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

    case 'RAPPEL_DOCUMENTS': {
      const docsList = Array.isArray(rawData.documents_manquants)
        ? (rawData.documents_manquants as unknown as string[]).map(d => escapeHtml(d)).join(', ')
        : data.documents_manquants || 'certains documents';
      return {
        subject: 'Complétez votre dossier sur Jolene',
        html: WRAPPER(`
          <h2 style="color:#0F172A;margin:0 0 12px;">📋 Documents à compléter</h2>
          <p style="color:#334155;">Bonjour ${data.prenom},</p>
          <p style="color:#334155;">Il manque des documents à votre profil pour pouvoir accepter des missions :</p>
          ${INFO_BOX(`<strong style="color:#0F172A;">Documents concernés :</strong> ${docsList}`)}
          <p style="color:#334155;">Complétez-les dès maintenant pour rester éligible aux missions.</p>
          ${BUTTON('Compléter mes documents →', `${APP_URL}/soignant/documents`)}
          ${SECURITY_NOTE}
        `),
      };
    }

    case 'MISSION_URGENTE':
      return {
        subject: `🚨 Mission urgente : ${data.mission}`,
        html: WRAPPER(`
          <h2 style="color:#0F172A;margin:0 0 12px;">🚨 Mission urgente disponible</h2>
          <p style="color:#334155;">Bonjour ${data.prenom},</p>
          <p style="color:#334155;">Une mission urgente correspondant à votre profil vient d'être publiée :</p>
          ${CARD_BOX(`
            <strong style="color:#0F172A;">${data.mission}</strong><br/>
            <span style="color:#334155;">📍 ${data.etablissement}</span><br/>
            <span style="color:#334155;">📅 ${data.date}</span><br/>
            <span style="color:#334155;">🕐 ${data.heure_debut} → ${data.heure_fin}</span><br/>
            <span style="color:#334155;">💰 ${data.taux_horaire} €/h</span>
          `)}
          ${INFO_BOX('<strong style="color:#0F172A;">⏰ Place limitée</strong> — le premier soignant qui accepte remporte la mission.')}
          ${BUTTON('Voir la mission →', `${APP_URL}/soignant/missions/${data.mission_id || ''}`)}
          ${SECURITY_NOTE}
        `),
      };

    case 'MISSION_PROPOSEE':
      return {
        subject: `Mission proposée : ${data.mission}`,
        html: WRAPPER(`
          <h2 style="color:#0F172A;margin:0 0 12px;">📩 Mission proposée</h2>
          <p style="color:#334155;">Bonjour ${data.prenom},</p>
          <p style="color:#334155;">L'établissement <strong>${data.etablissement}</strong> vous propose une mission :</p>
          ${CARD_BOX(`
            <strong style="color:#0F172A;">${data.mission}</strong><br/>
            <span style="color:#334155;">📅 ${data.date}</span><br/>
            <span style="color:#334155;">🕐 ${data.heure_debut} → ${data.heure_fin}</span><br/>
            <span style="color:#334155;">💰 ${data.taux_horaire} €/h</span>
          `)}
          ${INFO_BOX('Vous avez <strong>2 heures</strong> pour accepter ou refuser cette proposition.')}
          ${BUTTON('Accepter ou refuser →', `${APP_URL}/soignant/dashboard`)}
          ${SECURITY_NOTE}
        `),
      };

    case 'EVALUATION_RECUE':
      return {
        subject: `Nouvelle évaluation reçue${data.note ? ` — ${data.note}/5` : ''}`,
        html: WRAPPER(`
          <h2 style="color:#0F172A;margin:0 0 12px;">⭐ Vous avez reçu une évaluation</h2>
          <p style="color:#334155;">Un ${data.type_evaluateur === 'SOIGNANT' ? 'soignant' : 'établissement'} vous a évalué${data.mission ? ` pour la mission <strong>${data.mission}</strong>` : ''}.</p>
          ${data.note ? CARD_BOX(`<strong style="color:#0F172A;font-size:24px;">${'⭐'.repeat(Number(data.note))}</strong><br/><span style="color:#334155;">${data.note}/5</span>`) : ''}
          ${data.commentaire ? INFO_BOX(`<em style="color:#334155;">"${data.commentaire}"</em>`) : ''}
          ${BUTTON('Voir mon profil →', `${APP_URL}/soignant/profil`)}
          ${SECURITY_NOTE}
        `),
      };

    case 'PAIEMENT_CONFIRME':
      return {
        subject: `Paiement confirmé — ${data.montant ? data.montant + ' €' : ''}`,
        html: WRAPPER(`
          <h2 style="color:#0F172A;margin:0 0 12px;">✅ Paiement confirmé</h2>
          <p style="color:#334155;">Le soignant <strong>${data.soignant || ''}</strong> a confirmé la réception du paiement${data.mission ? ` pour la mission <strong>${data.mission}</strong>` : ''}.</p>
          ${CARD_BOX(`
            <strong style="color:#0F172A;">Montant :</strong> ${data.montant || '—'} €<br/>
            <strong style="color:#0F172A;">Référence :</strong> ${data.reference || '—'}
          `)}
          <p style="color:#334155;">Aucune action requise de votre part.</p>
          ${BUTTON('Voir la facturation →', `${APP_URL}/etablissement/facturation`)}
        `),
      };

    case 'PARRAINAGE_PRIME_VERSEE':
      return {
        subject: `🎉 Votre prime de parrainage de ${data.montant || 50}€ a été versée`,
        html: WRAPPER(`
          <h2 style="color:#0F172A;margin:0 0 12px;">🎉 Prime de parrainage versée${data.prenom ? `, ${escapeHtml(String(data.prenom))}` : ''} !</h2>
          <p style="color:#334155;">Votre prime de parrainage vient d'être virée sur votre compte bancaire.</p>
          ${CARD_BOX(`
            <strong style="color:#0F172A;font-size:24px;">${data.montant || 50} €</strong><br/>
            <span style="color:#334155;">${data.canal === 'STRIPE_CONNECT' ? 'Versée via Stripe' : 'Virement SEPA en cours (réception sous 1 à 2 jours ouvrés)'}</span>
          `)}
          <p style="color:#334155;">Merci de faire grandir la communauté Jolene 💜</p>
          ${BUTTON('Voir mon parrainage →', `${APP_URL}/soignant/parrainage`)}
        `),
      };

    case 'ADMIN_BROADCAST':
      return {
        subject: data.subject || 'Message de Jolene',
        html: WRAPPER(`
          <h2 style="color:#0F172A;margin:0 0 12px;">📢 ${escapeHtml(data.subject || 'Message de Jolene')}</h2>
          <div style="color:#334155;white-space:pre-wrap;">${escapeHtml(data.body || '')}</div>
          ${data.groupe ? `<p style="color:#94A3B8;font-size:12px;margin-top:16px;">Envoyé au groupe : ${data.groupe}</p>` : ''}
          ${BUTTON('Accéder à Jolene →', APP_URL)}
        `),
      };

    case 'MISSION_NON_POURVUE':
      return {
        subject: `Mission non pourvue — ${data.mission || ''}`,
        html: WRAPPER(`
          <h2 style="color:#0F172A;margin:0 0 12px;">⚠️ Mission annulée automatiquement</h2>
          <p style="color:#334155;">Votre mission <strong>${data.mission || ''}</strong> n'a trouvé aucun soignant et a été automatiquement annulée.</p>
          ${INFO_BOX('Vous pouvez la republier depuis votre espace missions.')}
          ${BUTTON('Republier la mission →', `${APP_URL}/etablissement/missions`)}
        `),
      };

    case 'PAIEMENT_RAPIDE_RECU':
      // Trois contextes supportés :
      //  - contexte=CONNECT_MISSION_PAYMENT : soignant payé en Stripe Connect (étab a payé)
      //  - contexte=CONNECT_PAYOUT_PAID    : argent arrivé sur le compte bancaire du soignant (payout Stripe)
      //  - par défaut                      : avance Defacto (factor), template historique
      if (data.contexte === 'CONNECT_MISSION_PAYMENT') {
        return {
          subject: `Paiement reçu pour votre mission — ${data.numero_facture || ''}`,
          html: WRAPPER(`
            <h2 style="color:#0F172A;margin:0 0 12px;">💸 Paiement reçu</h2>
            <p style="color:#334155;">Bonjour ${data.soignant_prenom || ''},</p>
            <p style="color:#334155;">L'établissement a payé votre mission via Stripe Connect. Les fonds sont en route vers votre compte bancaire (délai standard Stripe).</p>
            ${CARD_BOX(`
              <strong style="color:#0F172A;">${data.mission_intitule || 'Mission'}</strong><br/>
              <span style="color:#334155;">🏥 ${data.etablissement_nom || ''}</span><br/>
              <span style="color:#334155;">📄 Facture ${data.numero_facture || ''}</span><br/>
              <span style="color:#E04590;font-weight:bold;font-size:18px;">${data.montant_ttc || '0.00'} € TTC</span>
            `)}
            ${INFO_BOX(`Votre facture honoraires est désormais marquée <strong>PAYEE</strong>. Consultez-la dans votre espace facturation.`)}
            ${BUTTON('Voir mes factures →', `${APP_URL}/soignant/mes-factures-honoraires`)}
            ${SECURITY_NOTE}
          `),
        };
      }
      if (data.contexte === 'CONNECT_PAYOUT_PAID') {
        return {
          subject: `💰 Paiement arrivé sur votre compte bancaire`,
          html: WRAPPER(`
            <h2 style="color:#0F172A;margin:0 0 12px;">💰 Paiement arrivé !</h2>
            <p style="color:#334155;">Bonjour ${data.soignant_prenom || ''},</p>
            <p style="color:#334155;">L'argent de vos missions est bien arrivé sur votre compte bancaire.</p>
            ${CARD_BOX(`
              <strong style="color:#0F172A;">Montant crédité :</strong> <span style="color:#E04590;font-weight:bold;font-size:18px;">${data.montant_ttc || '0.00'} €</span><br/>
              <strong style="color:#0F172A;">Compte :</strong> IBAN se terminant par ${data.iban_last4 || '—'}<br/>
              <strong style="color:#0F172A;">Date d'arrivée :</strong> ${data.arrival_date || 'aujourd\'hui'}
            `)}
            ${INFO_BOX('Vous pouvez consulter le détail du versement dans votre espace Stripe Connect.')}
            ${BUTTON('Voir mes paiements →', `${APP_URL}/soignant/mes-factures-honoraires`)}
            ${SECURITY_NOTE}
          `),
        };
      }
      return {
        subject: `Paiement rapide reçu 💸`,
        html: WRAPPER(`
          <h2 style="color:#0F172A;margin:0 0 12px;">💸 Votre paiement rapide a été versé</h2>
          <p style="color:#334155;">Votre demande d'avance a été traitée. Le montant a été crédité sur votre compte bancaire sous 24-48h.</p>
          ${BUTTON('Voir mes avances →', `${APP_URL}/soignant/mes-avances`)}
          ${SECURITY_NOTE}
        `),
      };

    // ─── Templates Litiges (CP-LITIGES-5) ──────────────────

    case 'LITIGE_OUVERTURE':
      return {
        subject: `Un litige a été ouvert sur votre mission du ${data.date_mission || ''}`,
        html: WRAPPER(`
          <h2 style="color:#0F172A;margin:0 0 12px;">⚠️ Litige ouvert</h2>
          <p style="color:#334155;">Un litige de type <strong>${data.type_litige_libelle || data.type_litige || ''}</strong> a été ouvert ${data.initie_par === 'SOIGNANT' ? 'par le soignant' : data.initie_par === 'ETABLISSEMENT' ? 'par l\'établissement' : ''} sur la mission :</p>
          ${CARD_BOX(`
            <strong style="color:#0F172A;">${data.mission_intitule || data.mission || 'Mission'}</strong><br/>
            <span style="color:#334155;">📅 ${data.date_mission || ''}</span>
          `)}
          ${INFO_BOX(`<strong>Motif :</strong> ${data.motif || 'Non précisé'}`)}
          <p style="color:#334155;">Vous disposez de <strong>${data.delai_reponse_texte || '72h'}</strong> pour répondre avant escalade automatique.</p>
          ${BUTTON('Répondre au litige →', `${APP_URL}${data.url_litige || '/soignant/litiges'}`)}
          ${SECURITY_NOTE}
        `),
      };

    case 'LITIGE_NOUVEAU_MESSAGE':
      return {
        subject: `Nouveau message sur votre litige`,
        html: WRAPPER(`
          <h2 style="color:#0F172A;margin:0 0 12px;">💬 Nouveau message</h2>
          <p style="color:#334155;"><strong>${data.auteur || 'Un participant'}</strong> a ajouté un message à votre litige :</p>
          ${INFO_BOX(`"${data.extrait_message || '...'}"`.substring(0, 200))}
          ${BUTTON('Voir la discussion →', `${APP_URL}${data.url_litige || '/soignant/litiges'}`)}
          ${SECURITY_NOTE}
        `),
      };

    case 'LITIGE_ESCALADE_ADMIN':
      return {
        subject: `🚨 Litige escaladé — action requise`,
        html: WRAPPER(`
          <h2 style="color:#DC2626;margin:0 0 12px;">🚨 Litige escaladé en médiation</h2>
          <p style="color:#334155;">Un litige nécessite votre intervention :</p>
          ${CARD_BOX(`
            <strong style="color:#0F172A;">Type :</strong> ${data.type_litige || ''}<br/>
            <strong style="color:#0F172A;">Soignant :</strong> ${data.soignant_nom || '—'}<br/>
            <strong style="color:#0F172A;">Établissement :</strong> ${data.etablissement_nom || '—'}<br/>
            <strong style="color:#0F172A;">Mission :</strong> ${data.mission_intitule || data.mission_id || '—'}<br/>
            <strong style="color:#0F172A;">Ouvert depuis :</strong> ${data.jours_ouverture || '?'} jours<br/>
            ${data.montant_bloque ? `<strong style="color:#DC2626;">Trésorerie bloquée :</strong> ${data.montant_bloque} €` : ''}
          `)}
          ${BUTTON('Résoudre le litige →', `${APP_URL}/admin/moderation`)}
        `),
      };

    case 'LITIGE_MEDIATION_PRIORITAIRE':
      return {
        subject: `🚨 Litige en médiation depuis > ${data.jours_depuis_escalade || 7} jours`,
        html: WRAPPER(`
          <h2 style="color:#DC2626;margin:0 0 12px;">🚨 Alerte prioritaire — médiation prolongée</h2>
          <p style="color:#334155;">Un litige est en médiation depuis plus de <strong>${data.jours_depuis_escalade || 7} jours</strong> sans action.</p>
          ${CARD_BOX(`
            <strong style="color:#0F172A;">Type :</strong> ${data.type_litige || ''}<br/>
            <strong style="color:#0F172A;">Mission :</strong> ${data.mission_id || '—'}
          `)}
          ${BUTTON('Traiter le litige →', `${APP_URL}/admin/moderation`)}
        `),
      };

    case 'LITIGE_RESOLU_AJUSTE': {
      const action = (data.action_financiere || 'AUCUNE') as string;
      const actionBlock = action === 'AVOIR' ? `
          <p style="color:#334155;">📄 Un avoir <strong>${data.numero_avoir || '—'}</strong> a été émis. Vous recevrez l'avoir dans un email séparé avec le PDF joint.</p>
          <p style="color:#334155;">💡 Le document est disponible <strong>immédiatement</strong> dans votre espace (pas de délai de 24h).</p>
        ` : action === 'RECALCUL' ? `
          <p style="color:#334155;">🧮 Votre facture <strong>${data.numero_facture || '—'}</strong> a été recalculée avec les nouveaux montants.</p>
          <p style="color:#334155;">💡 Le PDF mis à jour est disponible <strong>immédiatement</strong> dans votre espace (pas de délai de 24h).</p>
        ` : action === 'ANNULER_REEMETTRE' ? `
          <p style="color:#334155;">🔄 Une nouvelle facture <strong>${data.numero_nouvelle || '—'}</strong> remplace <strong>${data.numero_ancienne || '—'}</strong>.</p>
          <p style="color:#334155;">💡 Les deux documents (ancien + nouveau) sont disponibles <strong>immédiatement</strong> dans votre espace (pas de délai de 24h).</p>
        ` : '';
      return {
        subject: `Litige résolu — ajustement appliqué`,
        html: WRAPPER(`
          <h2 style="color:#0F172A;margin:0 0 12px;">✅ Litige résolu</h2>
          <p style="color:#334155;">Le litige a été résolu ${data.en_faveur_de ? `en faveur du <strong>${data.en_faveur_de === 'SOIGNANT' ? 'soignant' : 'établissement'}</strong>` : 'par l\'administration'}.</p>
          ${INFO_BOX(`<strong>Résolution :</strong> ${data.resolution || '—'}`)}
          ${data.heures_avant ? CARD_BOX(`
            <strong style="color:#0F172A;">Ajustement :</strong><br/>
            Heures : ${data.heures_avant}h → ${data.heures_apres}h<br/>
            Montant : ${data.montant_avant} € → ${data.montant_apres} €
          `) : ''}
          ${actionBlock}
          ${data.url_facture ? BUTTON('Voir la facture →', data.url_facture) : BUTTON('Voir le détail →', `${APP_URL}/soignant/litiges`)}
          ${SECURITY_NOTE}
        `),
      };
    }

    case 'AVOIR_EMIS':
      return {
        subject: `Avoir ${data.numero_avoir || ''} émis — Jolene`,
        hasAttachment: true,
        html: WRAPPER(`
          <h2 style="color:#0F172A;margin:0 0 12px;">📄 Avoir émis</h2>
          <p style="color:#334155;">Un avoir a été émis suite à la résolution d'un litige :</p>
          ${CARD_BOX(`
            <strong style="color:#0F172A;">N° avoir :</strong> ${data.numero_avoir || '—'}<br/>
            <strong style="color:#0F172A;">Facture d'origine :</strong> ${data.numero_facture_origine || '—'}<br/>
            <strong style="color:#0F172A;">Montant :</strong> -${data.montant_avoir || '0'} €<br/>
            <strong style="color:#0F172A;">Remboursement :</strong> ${data.mode_remboursement_texte || 'Virement sous 7 jours ouvrés'}
          `)}
          ${data.date_remboursement_prevue ? `<p style="color:#334155;">Remboursement prévu : <strong>${data.date_remboursement_prevue}</strong></p>` : ''}
          ${BUTTON('Consulter l\'avoir →', `${APP_URL}/soignant/mes-factures`)}
          <p style="font-size:12px;color:#94A3B8;text-align:center;margin-top:20px;">📎 Le PDF de l'avoir est joint à cet email. En cas de problème, consultez-le directement dans l'application.</p>
        `, { hasAttachment: true }),
      };

    case 'REMBOURSEMENT_CONFIRME':
      return {
        subject: `Remboursement de ${data.montant || ''} € effectué`,
        html: WRAPPER(`
          <h2 style="color:#0F172A;margin:0 0 12px;">💸 Remboursement effectué</h2>
          <p style="color:#334155;">Votre remboursement a été traité :</p>
          ${CARD_BOX(`
            <strong style="color:#0F172A;">Montant :</strong> ${data.montant || '—'} €<br/>
            <strong style="color:#0F172A;">Mode :</strong> ${data.mode_texte || '—'}<br/>
            <strong style="color:#0F172A;">Référence :</strong> ${data.reference || '—'}<br/>
            <strong style="color:#0F172A;">Avoir n° :</strong> ${data.numero_avoir || '—'}
          `)}
          <p style="color:#334155;">⏱️ Délai bancaire : ${data.delai_bancaire || '2 à 5 jours ouvrés'}.</p>
          ${BUTTON('Voir mes factures →', `${APP_URL}/soignant/mes-factures`)}
          ${SECURITY_NOTE}
        `),
      };

    case 'LITIGE_RAPPEL_J1':
      return {
        subject: 'Rappel : litige en attente de votre réponse',
        html: WRAPPER(`
          <h2 style="color:#0F172A;margin:0 0 12px;">⏰ Rappel — litige en attente</h2>
          <p style="color:#334155;">Un litige est en attente de votre réponse depuis <strong>1 jour</strong>.</p>
          ${INFO_BOX('Répondez avant l\'escalade automatique en médiation.')}
          ${BUTTON('Répondre →', `${APP_URL}${data.url_litige || '/soignant/litiges'}`)}
          ${SECURITY_NOTE}
        `),
      };

    case 'LITIGE_RAPPEL_J3':
      return {
        subject: '⚠️ Rappel urgent : litige en attente depuis 3 jours',
        html: WRAPPER(`
          <h2 style="color:#F59E0B;margin:0 0 12px;">⚠️ Rappel urgent — 3 jours</h2>
          <p style="color:#334155;">Un litige est en attente de votre réponse depuis <strong>3 jours</strong>.</p>
          ${INFO_BOX('<strong>Sans réponse, ce litige sera automatiquement escaladé en médiation.</strong>')}
          ${BUTTON('Répondre maintenant →', `${APP_URL}${data.url_litige || '/soignant/litiges'}`)}
          ${SECURITY_NOTE}
        `),
      };

    case 'LITIGE_RAPPEL_J5':
      return {
        subject: '🚨 Dernier rappel — escalade imminente',
        html: WRAPPER(`
          <h2 style="color:#DC2626;margin:0 0 12px;">🚨 Dernier rappel — jour 5</h2>
          <p style="color:#334155;">Un litige est en attente de votre réponse depuis <strong>5 jours ouvrés</strong>. L'escalade en médiation est imminente.</p>
          ${INFO_BOX('<strong>Ceci est le dernier rappel automatique. Sans réponse, un administrateur interviendra.</strong>')}
          ${BUTTON('Répondre immédiatement →', `${APP_URL}${data.url_litige || '/soignant/litiges'}`)}
          ${SECURITY_NOTE}
        `),
      };

    case 'REGULARISATION_SOCIALE_REQUISE':
      return {
        subject: 'Ajustement de vos heures — régularisation URSSAF/Carpimko à prévoir',
        html: WRAPPER(`
          <h2 style="color:#0F172A;margin:0 0 12px;">📋 Régularisation sociale à prévoir</h2>
          <p style="color:#334155;">Suite à la résolution d'un litige, vos heures déclarées ont été ajustées :</p>
          ${CARD_BOX(`
            <strong style="color:#0F172A;">Mission :</strong> ${data.mission_intitule || '—'}<br/>
            <strong style="color:#0F172A;">Heures :</strong> ${data.ancien_nombre_heures || '—'}h → ${data.nouveau_nombre_heures || '—'}h<br/>
            <strong style="color:#0F172A;">Montant :</strong> ${data.ancien_montant || '—'} € → ${data.nouveau_montant || '—'} €<br/>
            <strong style="color:#0F172A;">Facture d'origine :</strong> émise le ${data.date_origine_facture || '—'}
          `)}
          ${INFO_BOX(`
            <strong>⚠️ Important :</strong> cette résolution modifie vos heures déclarées. Si vous avez déjà déclaré ces revenus (URSSAF, Carpimko), une régularisation peut être nécessaire.<br/><br/>
            <strong>Nous vous recommandons de consulter votre comptable.</strong>
          `)}
          ${data.url_nouvelle_facture_ou_avoir ? BUTTON('Voir le document →', data.url_nouvelle_facture_ou_avoir) : BUTTON('Voir mes factures →', `${APP_URL}/soignant/mes-factures`)}
          ${SECURITY_NOTE}
        `),
      };

    case 'COMMISSION_AJUSTEE': {
      const isAvoir = (data.type_document || 'AVOIR') === 'AVOIR';
      const bodyLine = isAvoir
        ? `Un <strong>avoir commission ${data.numero_document || '—'}</strong> de <strong>${data.montant || '—'} €</strong> a été émis suite à la résolution du litige sur la mission <strong>${data.mission_intitule || '—'}</strong>. Cet avoir sera déduit de votre prochaine facture mensuelle.`
        : `Une <strong>facture complémentaire ${data.numero_document || '—'}</strong> de <strong>${data.montant || '—'} €</strong> a été émise suite à la résolution du litige sur la mission <strong>${data.mission_intitule || '—'}</strong>. Cette facture sera due aux conditions habituelles.`;
      return {
        subject: isAvoir
          ? `Avoir commission ${data.numero_document || ''} — ajustement litige`
          : `Facture complémentaire ${data.numero_document || ''} — ajustement litige`,
        html: WRAPPER(`
          <h2 style="color:#0F172A;margin:0 0 12px;">${isAvoir ? '📉' : '📈'} Commission ajustée suite à résolution de litige</h2>
          <p style="color:#334155;">${bodyLine}</p>
          ${CARD_BOX(`
            <strong style="color:#0F172A;">Type :</strong> ${isAvoir ? 'Avoir commission' : 'Facture complémentaire'}<br/>
            <strong style="color:#0F172A;">Numéro :</strong> ${data.numero_document || '—'}<br/>
            <strong style="color:#0F172A;">Montant :</strong> ${isAvoir ? '-' : ''}${data.montant || '—'} € TTC<br/>
            <strong style="color:#0F172A;">Mission :</strong> ${data.mission_intitule || '—'}
          `)}
          ${INFO_BOX(`<strong>Origine :</strong> recalcul automatique des commissions Jolene après résolution du litige #${data.litige_id || '—'}.`)}
          ${data.litige_id ? BUTTON('Voir le litige →', `${APP_URL}/admin/moderation?litige=${data.litige_id}`) : BUTTON('Voir mes factures →', `${APP_URL}/etablissement/factures`)}
          ${SECURITY_NOTE}
        `),
      };
    }

    // ─── Templates CP-STRIPE-4 (webhook events Stripe) ────────

    case 'CHARGE_FAILED_ETAB':
      return {
        subject: `⚠️ Paiement échoué — Facture ${data.numero_facture || ''}`,
        html: WRAPPER(`
          <h2 style="color:#0F172A;margin:0 0 12px;">⚠️ Paiement échoué</h2>
          <p style="color:#334155;">Le paiement de votre facture Jolene a échoué :</p>
          ${CARD_BOX(`
            <strong style="color:#0F172A;">Facture :</strong> ${data.numero_facture || '—'}<br/>
            <strong style="color:#0F172A;">Montant :</strong> ${data.montant_ttc || '—'} € TTC<br/>
            <strong style="color:#0F172A;">Raison :</strong> ${data.failure_message || 'Erreur carte'}
          `)}
          ${INFO_BOX('Merci de relancer le paiement depuis votre espace facturation. Si le problème persiste, vérifiez votre moyen de paiement ou contactez votre banque.')}
          ${BUTTON('Relancer le paiement →', `${APP_URL}/etablissement/facturation`)}
          ${SECURITY_NOTE}
        `),
      };

    case 'DISPUTE_OUVERTE_ADMIN':
      return {
        subject: `⚠️ Litige Stripe ouvert — action sous 7 jours`,
        html: WRAPPER(`
          <h2 style="color:#0F172A;margin:0 0 12px;">⚠️ Chargeback Stripe</h2>
          <p style="color:#334155;">Un établissement a contesté un paiement via sa banque. Action admin requise sous 7 jours (sinon dispute perdu automatiquement) :</p>
          ${CARD_BOX(`
            <strong style="color:#0F172A;">Dispute ID :</strong> ${data.dispute_id || '—'}<br/>
            <strong style="color:#0F172A;">Mission :</strong> ${data.mission_id || '—'}<br/>
            <strong style="color:#0F172A;">Montant :</strong> ${data.montant || '—'} €<br/>
            <strong style="color:#0F172A;">Raison Stripe :</strong> ${data.reason || '—'}<br/>
            <strong style="color:#0F172A;">Échéance preuves :</strong> ${data.evidence_due_by || '—'}
          `)}
          ${INFO_BOX('Connectez-vous au dashboard Stripe pour soumettre les preuves (contrat signé, facture, échanges) AVANT la deadline.')}
          ${BUTTON('Dashboard Stripe →', 'https://dashboard.stripe.com/disputes')}
        `),
      };

    case 'DISPUTE_CLOSE_ADMIN':
      return {
        subject: `Litige Stripe clôturé — résultat : ${data.dispute_status || ''}`,
        html: WRAPPER(`
          <h2 style="color:#0F172A;margin:0 0 12px;">Litige Stripe clôturé</h2>
          ${CARD_BOX(`
            <strong style="color:#0F172A;">Dispute ID :</strong> ${data.dispute_id || '—'}<br/>
            <strong style="color:#0F172A;">Résultat :</strong> ${data.dispute_status || '—'}<br/>
            <strong style="color:#0F172A;">Mission :</strong> ${data.mission_id || '—'}<br/>
            <strong style="color:#0F172A;">Montant :</strong> ${data.montant || '—'} €
          `)}
          ${data.dispute_status === 'lost'
            ? INFO_BOX('⚠️ <strong>Dispute perdu</strong> — l\'argent a été restitué à l\'étab côté Stripe. Potentielle récupération via ouverture d\'un litige Jolene.')
            : INFO_BOX('Aucune action requise.')}
          ${BUTTON('Dashboard Stripe →', 'https://dashboard.stripe.com/disputes')}
        `),
      };

    case 'PAYOUT_FAILED_ADMIN':
      return {
        subject: `🚨 Payout Stripe échoué — soignant ${data.soignant_nom || ''}`,
        html: WRAPPER(`
          <h2 style="color:#0F172A;margin:0 0 12px;">🚨 Payout soignant échoué</h2>
          <p style="color:#334155;">Un versement Stripe vers un compte bancaire soignant a échoué :</p>
          ${CARD_BOX(`
            <strong style="color:#0F172A;">Soignant :</strong> ${data.soignant_nom || '—'}<br/>
            <strong style="color:#0F172A;">Payout ID :</strong> ${data.payout_id || '—'}<br/>
            <strong style="color:#0F172A;">Montant :</strong> ${data.montant || '—'} €<br/>
            <strong style="color:#0F172A;">Raison :</strong> ${data.failure_message || '—'} (code ${data.failure_code || '—'})
          `)}
          ${INFO_BOX('Causes fréquentes : IBAN invalide, compte fermé, vérification KYC incomplète. Le soignant a été notifié séparément.')}
          ${BUTTON('Dashboard Stripe Payouts →', 'https://dashboard.stripe.com/payouts')}
        `),
      };

    case 'PAYOUT_FAILED_SOIGNANT':
      return {
        subject: `⚠️ Problème avec votre RIB — action requise`,
        html: WRAPPER(`
          <h2 style="color:#0F172A;margin:0 0 12px;">⚠️ Votre paiement est bloqué</h2>
          <p style="color:#334155;">Bonjour ${data.soignant_prenom || ''},</p>
          <p style="color:#334155;">Le versement de <strong>${data.montant || '—'} €</strong> vers votre compte bancaire a échoué. Cause probable :</p>
          ${INFO_BOX(`<strong>${data.raison_simplifiee || data.failure_message || 'Vérification du compte bancaire'}</strong>`)}
          <p style="color:#334155;">Merci de :</p>
          <ul style="color:#334155;padding-left:20px;">
            <li>Vérifier vos informations bancaires (IBAN, RIB) dans votre espace Stripe Connect</li>
            <li>Vous assurer que votre compte bancaire est bien actif</li>
            <li>Compléter les vérifications KYC si demandées</li>
          </ul>
          <p style="color:#334155;">L'équipe Jolene relance le versement dès que votre compte est à jour.</p>
          ${BUTTON('Vérifier mon compte Stripe →', `${APP_URL}/soignant/stripe-connect`)}
          ${SECURITY_NOTE}
        `),
      };

    case 'PAYOUT_CANCELED_ADMIN':
      return {
        subject: `Payout annulé — ${data.payout_id || ''}`,
        html: WRAPPER(`
          <h2 style="color:#0F172A;margin:0 0 12px;">Payout Stripe annulé</h2>
          <p style="color:#334155;">Un payout a été annulé (côté Stripe ou par l'admin plateforme) :</p>
          ${CARD_BOX(`
            <strong style="color:#0F172A;">Payout ID :</strong> ${data.payout_id || '—'}<br/>
            <strong style="color:#0F172A;">Soignant :</strong> ${data.soignant_nom || '—'}<br/>
            <strong style="color:#0F172A;">Montant :</strong> ${data.montant || '—'} €
          `)}
          ${INFO_BOX('Les stripe_transfers associés ont été mis en statut ANNULEE. Vérifier si un nouveau payout doit être initié.')}
        `),
      };

    // ─── Template CP-STRIPE-5 (refund cron échec permanent) ────

    // ─── Template CP-C-1 (déclaration paiement soignant par étab) ────

    case 'PAIEMENT_SOIGNANT_DECLARE':
      return {
        subject: `Votre établissement a déclaré vous avoir payé ${data.montant_formatte || ''} € — confirmez`,
        html: WRAPPER(`
          <h2 style="color:#0F172A;margin:0 0 12px;">💶 Paiement déclaré par votre établissement</h2>
          <p style="color:#334155;">Bonjour ${data.soignant_prenom || ''},</p>
          <p style="color:#334155;">
            <strong>${data.etablissement_nom || 'Votre établissement'}</strong> a déclaré vous avoir payé pour la mission
            <strong>${data.mission_intitule || ''}</strong>. Merci de confirmer la réception du paiement dans votre espace Jolene.
          </p>
          ${CARD_BOX(`
            <strong style="color:#0F172A;">Montant :</strong> <span style="color:#E04590;font-weight:bold;font-size:18px;">${data.montant_formatte || '—'} €</span><br/>
            <strong style="color:#0F172A;">Méthode :</strong> ${data.methode_libelle || data.methode || '—'}<br/>
            ${data.reference_virement ? '<strong style="color:#0F172A;">Référence :</strong> ' + data.reference_virement + '<br/>' : ''}
            <strong style="color:#0F172A;">Date paiement déclarée :</strong> ${data.date_paiement_fr || data.date_paiement || '—'}
          `)}
          ${INFO_BOX(`⚠️ <strong>Action requise</strong> : connectez-vous pour confirmer que vous avez bien reçu ce paiement sur votre compte bancaire. En cas de désaccord, vous pouvez ouvrir une contestation.`)}
          ${BUTTON('Confirmer la réception dans mon espace Jolene', `${APP_URL}${data.deep_link || '/soignant/mes-gains'}`)}
          <p style="font-size:12px;color:#94A3B8;margin-top:16px;">
            Cette déclaration a été faite par l'établissement sous attestation sur l'honneur (URSSAF + Code pénal art. 441-1).
            Vous avez 30 jours pour confirmer ou contester.
          </p>
          ${SECURITY_NOTE}
        `),
      };

    case 'REFUND_ECHEC_ADMIN':
      return {
        subject: `🚨 Remboursement Stripe permanent en échec — avoir ${data.numero_avoir || ''}`,
        html: WRAPPER(`
          <h2 style="color:#0F172A;margin:0 0 12px;">🚨 Remboursement Stripe en échec permanent</h2>
          <p style="color:#334155;">Le cron <code>process-stripe-refunds</code> n'a pas pu exécuter un remboursement après ${data.tentatives || '—'} tentative(s). Action admin requise.</p>
          ${CARD_BOX(`
            <strong style="color:#0F172A;">Avoir :</strong> ${data.numero_avoir || '—'} (id ${data.avoir_id || '—'})<br/>
            <strong style="color:#0F172A;">Montant :</strong> ${data.montant_formatte || '—'} €<br/>
            <strong style="color:#0F172A;">Soignant :</strong> ${data.soignant_nom || '—'}<br/>
            <strong style="color:#0F172A;">Établissement :</strong> ${data.etablissement_nom || '—'}<br/>
            <strong style="color:#0F172A;">Payment Intent :</strong> <code>${data.payment_intent_id || '—'}</code>
          `)}
          ${INFO_BOX(`
            <strong>Erreur Stripe :</strong><br/>
            Code : <code>${data.erreur_code || '—'}</code><br/>
            Message : ${data.erreur_stripe || '—'}
          `)}
          <p style="color:#334155;"><strong>Actions possibles :</strong></p>
          <ul style="color:#334155;padding-left:20px;">
            <li><strong>Retry manuel</strong> : si l'erreur est transitoire, <code>UPDATE stripe_refunds_queue SET statut='EN_ATTENTE', tentatives=0, erreur=NULL WHERE avoir_id='${data.avoir_id || ''}';</code></li>
            <li><strong>Virement manuel</strong> : exécuter le remboursement hors Stripe et passer l'avoir en statut REMBOURSEE</li>
            <li><strong>Contact Stripe</strong> : si le payment_intent est corrompu côté Stripe</li>
          </ul>
          ${BUTTON('Dashboard Stripe Refunds →', 'https://dashboard.stripe.com/refunds')}
          <p style="font-size:12px;color:#94A3B8;text-align:center;margin-top:20px;">Ce mail est envoyé automatiquement par le cron process-stripe-refunds (toutes les 15 min).</p>
        `),
      };

    // ─── Templates CP-C-2 (relances paiement étab) ──────────

    case 'RAPPEL_PAIEMENT_J7': {
      const isFacture = data.type_obligation === 'FACTURE_COMMISSION';
      const cta = isFacture
        ? `${APP_URL}/etablissement/facturation`
        : `${APP_URL}/etablissement/obligations-financieres`;
      const titre = isFacture
        ? `Rappel : facture ${data.numero_facture || ''} à régler`
        : `Rappel : paiement de ${data.soignant_prenom || ''} ${data.soignant_nom || ''} à déclarer`;
      return {
        subject: `${titre} — 7 jours`,
        html: WRAPPER(`
          <h2 style="color:#0F172A;margin:0 0 12px;">🔔 Rappel de régularisation</h2>
          <p style="color:#334155;">Bonjour,</p>
          <p style="color:#334155;">
            Pour l'établissement <strong>${data.etablissement_nom || '—'}</strong>, une obligation de régularisation a été identifiée il y a <strong>7 jours</strong>.
          </p>
          ${CARD_BOX(isFacture ? `
            <strong style="color:#0F172A;">Type :</strong> Facture de commission Jolene<br/>
            <strong style="color:#0F172A;">Numéro :</strong> ${data.numero_facture || '—'}<br/>
            <strong style="color:#0F172A;">Montant TTC :</strong> <span style="color:#E04590;font-weight:bold;">${data.montant_ttc || '—'} €</span><br/>
            <strong style="color:#0F172A;">Émise le :</strong> ${data.date_emission || '—'}
          ` : `
            <strong style="color:#0F172A;">Type :</strong> Paiement soignant à déclarer<br/>
            <strong style="color:#0F172A;">Mission :</strong> ${data.mission_intitule || '—'}<br/>
            <strong style="color:#0F172A;">Soignant :</strong> ${data.soignant_prenom || ''} ${data.soignant_nom || ''}<br/>
            <strong style="color:#0F172A;">Montant estimé :</strong> <span style="color:#E04590;font-weight:bold;">${data.montant_estime || '—'} €</span><br/>
            <strong style="color:#0F172A;">Fin de mission :</strong> ${data.date_fin_mission || '—'}
          `)}
          ${INFO_BOX('Un simple clic sur le bouton ci-dessous suffit pour régulariser. Cette notification est un rappel amical, aucune sanction n\'est appliquée à ce stade.')}
          ${BUTTON('Régulariser maintenant →', cta)}
          ${SECURITY_NOTE}
        `),
      };
    }

    case 'PAIEMENT_RETARD_J21': {
      const isFacture = data.type_obligation === 'FACTURE_COMMISSION';
      const cta = isFacture
        ? `${APP_URL}/etablissement/facturation`
        : `${APP_URL}/etablissement/obligations-financieres`;
      const titre = isFacture
        ? `Facture ${data.numero_facture || ''} en retard de 21 jours`
        : `Paiement ${data.soignant_prenom || ''} ${data.soignant_nom || ''} en retard de 21 jours`;
      const mentionLegale = isFacture
        ? 'Les pénalités de retard légales s\'appliquent selon l\'article L441-10 du Code de commerce.'
        : 'Le non-paiement du soignant expose l\'établissement à des poursuites URSSAF (obligation de vigilance, article L8222-1 Code du travail).';
      return {
        subject: `⚠️ ${titre} — action requise`,
        html: WRAPPER(`
          <h2 style="color:#0F172A;margin:0 0 12px;">⚠️ Paiement en retard de 21 jours</h2>
          <p style="color:#334155;">Bonjour,</p>
          <p style="color:#334155;">
            Une obligation de régularisation identifiée depuis <strong>21 jours</strong> reste en attente pour l'établissement <strong>${data.etablissement_nom || '—'}</strong>.
          </p>
          ${CARD_BOX(isFacture ? `
            <strong style="color:#0F172A;">Type :</strong> Facture de commission Jolene<br/>
            <strong style="color:#0F172A;">Numéro :</strong> ${data.numero_facture || '—'}<br/>
            <strong style="color:#0F172A;">Montant TTC :</strong> <span style="color:#E04590;font-weight:bold;">${data.montant_ttc || '—'} €</span><br/>
            <strong style="color:#0F172A;">Émise le :</strong> ${data.date_emission || '—'}
          ` : `
            <strong style="color:#0F172A;">Type :</strong> Paiement soignant à déclarer<br/>
            <strong style="color:#0F172A;">Mission :</strong> ${data.mission_intitule || '—'}<br/>
            <strong style="color:#0F172A;">Soignant :</strong> ${data.soignant_prenom || ''} ${data.soignant_nom || ''}<br/>
            <strong style="color:#0F172A;">Montant estimé :</strong> <span style="color:#E04590;font-weight:bold;">${data.montant_estime || '—'} €</span><br/>
            <strong style="color:#0F172A;">Fin de mission :</strong> ${data.date_fin_mission || '—'}
          `)}
          ${INFO_BOX(`⚠️ <strong>Sans régularisation sous 24 jours</strong>, la publication de nouvelles missions sera automatiquement suspendue (seuil J+45).`)}
          ${BUTTON('Régulariser immédiatement →', cta)}
          <p style="font-size:12px;color:#94A3B8;margin-top:16px;">
            ${mentionLegale}
          </p>
          ${SECURITY_NOTE}
        `),
      };
    }

    case 'PUBLICATION_REACTIVEE':
      return {
        subject: '✅ Publication de missions réactivée',
        html: WRAPPER(`
          <h2 style="color:#0F172A;margin:0 0 12px;">✅ Publication réactivée</h2>
          <p style="color:#334155;">Bonjour,</p>
          <p style="color:#334155;">
            Vos obligations de paiement ont été régularisées pour <strong>${data.etablissement_nom || '—'}</strong>. La publication de nouvelles missions est à nouveau active.
          </p>
          ${INFO_BOX('Pour éviter toute nouvelle suspension, veillez à déclarer vos paiements soignants et régler vos factures de commission dans les délais (J+7 rappel / J+21 relance / J+45 blocage).')}
          ${BUTTON('Accéder à mon dashboard →', `${APP_URL}/etablissement/dashboard`)}
          ${SECURITY_NOTE}
        `),
      };

    case 'PUBLICATION_SUSPENDUE':
      return {
        subject: `❌ Publication de missions suspendue — ${data.etablissement_nom || 'action requise'}`,
        html: WRAPPER(`
          <h2 style="color:#0F172A;margin:0 0 12px;">❌ Publication suspendue</h2>
          <p style="color:#334155;">Bonjour,</p>
          <p style="color:#334155;">
            En raison d'obligations de paiement non régularisées depuis plus de <strong>45 jours</strong>, la publication de nouvelles missions est automatiquement suspendue pour l'établissement <strong>${data.etablissement_nom || '—'}</strong>.
          </p>
          ${CARD_BOX(`
            <strong style="color:#0F172A;">Obligations en cours :</strong><br/>
            ${data.obligations_en_cours || '—'}<br/>
            <strong style="color:#0F172A;">Total dû :</strong> <span style="color:#E04590;font-weight:bold;font-size:18px;">${data.total_montant_du || '—'} €</span><br/>
            <strong style="color:#0F172A;">Date de suspension :</strong> ${data.date_blocage || '—'}
          `)}
          ${INFO_BOX(`🔓 <strong>Déblocage automatique</strong> : votre compte sera immédiatement réactivé dès la régularisation complète de vos obligations.`)}
          ${BUTTON('Régulariser maintenant →', `${APP_URL}/etablissement/obligations-financieres`)}
          <p style="font-size:12px;color:#94A3B8;margin-top:16px;">
            Cette suspension intervient en application de notre obligation de vigilance (article L8222-1 Code du travail + article L441-10 Code de commerce). Jolene, en tant qu'intermédiaire, est tenu de garantir la régularité des paiements entre établissements et soignants.
          </p>
          ${SECURITY_NOTE}
        `),
      };

    case 'CONTRAT_TRAVAIL_DEPOSE':
      return {
        subject: 'Votre contrat de travail a été déposé',
        html: WRAPPER(`
          <h2 style="color:#0F172A;margin:0 0 12px;">Contrat de travail déposé</h2>
          <p style="color:#334155;">Bonjour ${data.prenom || ''},</p>
          <p style="color:#334155;">Votre établissement <strong>${data.nom_etablissement || ''}</strong> a déposé votre contrat de travail pour la mission <strong>${data.intitule_mission || 'à venir'}</strong>${data.date_debut ? ` qui débute le <strong>${data.date_debut}</strong>` : ''}.</p>
          ${INFO_BOX(`Vous pouvez télécharger votre contrat depuis le détail de la mission sur la plateforme Jolene.`)}
          ${BUTTON('Accéder à ma mission →', `${APP_URL}/soignant/missions/${data.mission_id || ''}`)}
        `),
      };

    case 'CONTRAT_TRAVAIL_RAPPEL_ETAB':
      return {
        subject: `Rappel : déposez le contrat de travail — ${data.intitule_mission || 'mission'}`,
        html: WRAPPER(`
          <h2 style="color:#0F172A;margin:0 0 12px;">Contrat de travail à déposer</h2>
          <p style="color:#334155;">Bonjour,</p>
          <p style="color:#334155;">La mission <strong>${data.intitule_mission || ''}</strong> assignée à <strong>${data.prenom_soignant || ''} ${data.nom_soignant || ''}</strong> commence <strong>${data.date_debut ? `le ${data.date_debut}` : 'demain'}</strong>.</p>
          ${INFO_BOX(`Le contrat de travail CDDU n'a pas encore été déposé sur la plateforme. En tant qu'employeur, vous devez le téléverser au plus tard le premier jour de mission.`)}
          ${BUTTON('Déposer le contrat →', `${APP_URL}/etablissement/missions/${data.mission_id || ''}`)}
        `),
      };

    case 'CONTRAT_TRAVAIL_MANQUANT_SOIGNANT':
      return {
        subject: 'Contrat de travail en attente',
        html: WRAPPER(`
          <h2 style="color:#0F172A;margin:0 0 12px;">Contrat de travail en attente</h2>
          <p style="color:#334155;">Bonjour ${data.prenom || ''},</p>
          <p style="color:#334155;">Votre établissement <strong>${data.nom_etablissement || ''}</strong> n'a pas encore déposé votre contrat de travail pour la mission <strong>${data.intitule_mission || ''}</strong> qui débute <strong>${data.date_debut ? `le ${data.date_debut}` : 'demain'}</strong>.</p>
          ${INFO_BOX(`Vous pouvez contacter directement votre établissement pour le rappeler. Le contrat doit être signé au plus tard le premier jour de mission.`)}
          ${BUTTON('Voir ma mission →', `${APP_URL}/soignant/missions/${data.mission_id || ''}`)}
        `),
      };

    // ════════ J2.3.B — Série onboarding SOIGNANT ════════
    case 'SERIE_SOIGNANT_J0':
      return {
        subject: `Bienvenue chez Jolene, ${data.prenom || ''} 🎉`,
        html: WRAPPER(`
          <h2 style="color:#0F172A;margin:0 0 12px;">Bienvenue ${data.prenom || ''} !</h2>
          <p style="color:#334155;">Votre compte soignant est créé sur Jolene. Voici les <strong>3 étapes</strong> pour démarrer rapidement :</p>
          ${INFO_BOX(`
            <strong style="color:#0F172A;">1. Complétez votre profil</strong> — RPPS, adresse, téléphone, types de contrat acceptés (libéral, salarié, mixte)<br/>
            <strong style="color:#0F172A;">2. Téléversez vos documents</strong> — diplôme, RCP, identité (vérifiés sous 24h ouvrées)<br/>
            <strong style="color:#0F172A;">3. Si libéral : signez votre mandat de facturation</strong> (art. 289 I-2 CGI)
          `)}
          <p style="color:#334155;">Une fois ces 3 étapes complètes, vous pouvez candidater à toutes les missions correspondant à votre profession et votre rayon de déplacement.</p>
          ${BUTTON('Compléter mon profil →', `${APP_URL}/soignant/profil`)}
          <p style="color:#64748B;font-size:13px;margin-top:16px;">Besoin d'aide ? Consultez notre <a href="${APP_URL}/aide" style="color:#9333EA;">centre d'aide</a> ou écrivez-nous à <a href="mailto:support@jolene.app" style="color:#9333EA;">support@jolene.app</a>.</p>
        `),
      };

    case 'SERIE_SOIGNANT_J1':
      return {
        subject: 'Complétez votre profil pour candidater',
        html: WRAPPER(`
          <h2 style="color:#0F172A;margin:0 0 12px;">${data.prenom || ''}, finalisez votre profil</h2>
          <p style="color:#334155;">Vous avez créé votre compte hier. Pour <strong>candidater aux missions</strong> et apparaître dans les recherches des établissements, votre profil doit être complet.</p>
          ${INFO_BOX(`
            <strong style="color:#0F172A;">Vérifications nécessaires :</strong><br/>
            ✅ RPPS vérifié (déjà fait à l'inscription si applicable)<br/>
            ⚠️ Documents requis téléversés (diplôme, RCP, identité)<br/>
            ⚠️ Mandat de facturation signé (uniquement si libéral)
          `)}
          <p style="color:#334155;"><strong>Pourquoi un profil complet ?</strong></p>
          <ul style="color:#334155;line-height:1.6;">
            <li>Visibilité maximum auprès des établissements</li>
            <li>Matching automatique avec les missions adaptées à votre rayon</li>
            <li>Aucun blocage administratif au moment de la candidature</li>
          </ul>
          ${BUTTON('Compléter mon profil →', `${APP_URL}/soignant/parametres`)}
          <p style="color:#64748B;font-size:13px;margin-top:16px;">Vous avez déjà tout complété ? Bravo ! Vous pouvez ignorer cet email.</p>
        `),
      };

    case 'SERIE_SOIGNANT_J3':
      return {
        subject: 'Découvrez les missions disponibles',
        html: WRAPPER(`
          <h2 style="color:#0F172A;margin:0 0 12px;">Trouvez votre prochaine mission</h2>
          <p style="color:#334155;">Plusieurs centaines de missions sont publiées chaque semaine sur Jolene par des établissements de santé près de chez vous.</p>
          ${INFO_BOX(`
            <strong style="color:#0F172A;">Conseils pour bien candidater :</strong><br/>
            • Filtrez par <strong>rayon de déplacement</strong> et <strong>taux horaire minimum</strong><br/>
            • Activez <strong>"Missions urgentes"</strong> pour être alerté en priorité<br/>
            • Ajoutez un <strong>message court et personnalisé</strong> à votre candidature<br/>
            • <strong>Sauvegardez vos recherches</strong> pour recevoir des alertes automatiques sur les nouvelles missions matchant vos critères
          `)}
          <p style="color:#334155;">Exemple de filtre utile : <em>« IDE, Paris, taux ≥ 25 €/h, urgences uniquement »</em>.</p>
          ${BUTTON('Voir les missions →', `${APP_URL}/soignant/missions`)}
          <p style="color:#64748B;font-size:13px;margin-top:16px;">Astuce : la vue Carte (Leaflet) vous permet de visualiser les missions près de chez vous.</p>
        `),
      };

    case 'SERIE_SOIGNANT_J7':
      return {
        subject: 'Avez-vous des questions ?',
        html: WRAPPER(`
          <h2 style="color:#0F172A;margin:0 0 12px;">Une semaine déjà sur Jolene !</h2>
          <p style="color:#334155;">Bonjour ${data.prenom || ''}, vous avez rejoint Jolene il y a une semaine. Comment se passe votre expérience ?</p>
          ${INFO_BOX(`
            <strong style="color:#0F172A;">Si vous bloquez quelque part, on est là :</strong><br/>
            • Centre d'aide <a href="${APP_URL}/aide" style="color:#9333EA;">jolene.app/aide</a> — 22 articles répondent aux questions courantes<br/>
            • Support : <a href="mailto:support@jolene.app" style="color:#9333EA;">support@jolene.app</a> (réponse sous 48h ouvrées)<br/>
            • DPO (questions RGPD) : <a href="mailto:support@jolene.app" style="color:#9333EA;">support@jolene.app</a>
          `)}
          <p style="color:#334155;"><strong>Quelques articles utiles :</strong></p>
          <ul style="color:#334155;line-height:1.6;">
            <li><a href="${APP_URL}/aide/comment-candidater-mission" style="color:#9333EA;">Comment candidater à une mission</a></li>
            <li><a href="${APP_URL}/aide/comment-fonctionne-pointage" style="color:#9333EA;">Comment fonctionne le pointage</a></li>
            <li><a href="${APP_URL}/aide/comprendre-ma-facture-honoraires" style="color:#9333EA;">Comprendre ma facture d'honoraires</a></li>
            <li><a href="${APP_URL}/aide/defacto-paiement-j2" style="color:#9333EA;">Defacto et le paiement J+2</a></li>
          </ul>
          ${BUTTON('Ouvrir le centre d\'aide →', `${APP_URL}/aide`)}
          <p style="color:#64748B;font-size:13px;margin-top:16px;">Vous pouvez désactiver cette série d'emails dans <a href="${APP_URL}/soignant/parametres/notifications" style="color:#9333EA;">Préférences de notifications</a>.</p>
        `),
      };

    // ════════ J2.3.B — Série onboarding ÉTABLISSEMENT ════════
    case 'SERIE_ETAB_J0':
      return {
        subject: `Bienvenue sur Jolene, ${data.nom_etablissement || ''} 🎉`,
        html: WRAPPER(`
          <h2 style="color:#0F172A;margin:0 0 12px;">Bienvenue ${data.nom_etablissement || ''} !</h2>
          <p style="color:#334155;">Votre établissement est enregistré sur Jolene. Pour publier votre première mission, <strong>2 étapes essentielles</strong> :</p>
          ${INFO_BOX(`
            <strong style="color:#0F172A;">1. Signer le contrat de service Jolene</strong><br/>
            Définit la relation Jolene ↔ Établissement (commission, obligations, seul employeur SALARIE).<br/><br/>
            <strong style="color:#0F172A;">2. Déposer votre RIB</strong><br/>
            Pour la facturation des commissions Jolene (PDF, JPG ou PNG, max 5 Mo, stockage privé sécurisé).
          `)}
          <p style="color:#334155;">Tant que ces 2 étapes ne sont pas finalisées, vous ne pouvez pas publier de missions. Un bandeau vous le rappellera dans l'app.</p>
          ${BUTTON('Finaliser mon inscription →', `${APP_URL}/etablissement/finaliser-inscription`)}
          <p style="color:#64748B;font-size:13px;margin-top:16px;">Besoin d'aide ? <a href="${APP_URL}/aide" style="color:#9333EA;">Centre d'aide</a> ou <a href="mailto:support@jolene.app" style="color:#9333EA;">support@jolene.app</a>.</p>
        `),
      };

    case 'SERIE_ETAB_J1':
      return {
        subject: 'Conseils pour attirer les meilleurs soignants',
        html: WRAPPER(`
          <h2 style="color:#0F172A;margin:0 0 12px;">Publier une mission attractive</h2>
          <p style="color:#334155;">Pour maximiser vos chances de recevoir des candidatures de qualité rapidement :</p>
          ${INFO_BOX(`
            <strong style="color:#0F172A;">1. Description précise</strong> — Service, équipe, matériel, contexte. Plus vous êtes clair, plus vos candidatures sont pertinentes.<br/><br/>
            <strong style="color:#0F172A;">2. Taux horaire compétitif</strong> — Comparez avec votre convention collective (FHP, FEHAP, CCU, FPH...) et le marché local.<br/><br/>
            <strong style="color:#0F172A;">3. Respect des planchers de majoration légaux Jolene :</strong><br/>
            • Nuit (21h-06h) : minimum <strong>+25 %</strong><br/>
            • Dimanche : minimum <strong>+25 %</strong><br/>
            • Jour férié : minimum <strong>+50 %</strong>
          `)}
          <p style="color:#334155;">Les missions urgentes (cochez la case lors de la création) bénéficient d'alertes push et SMS auprès des soignants disponibles dans le rayon.</p>
          ${BUTTON('Publier ma première mission →', `${APP_URL}/etablissement/missions/creer`)}
          <p style="color:#64748B;font-size:13px;margin-top:16px;">📖 <a href="${APP_URL}/aide/etab-publier-premiere-mission" style="color:#9333EA;">Article complet : Publier ma première mission</a></p>
        `),
      };

    case 'SERIE_ETAB_J3':
      return {
        subject: 'Astuces pour gérer vos missions efficacement',
        html: WRAPPER(`
          <h2 style="color:#0F172A;margin:0 0 12px;">Workflow d'une mission Jolene</h2>
          <p style="color:#334155;">Le cycle complet d'une mission, de la création au paiement :</p>
          ${INFO_BOX(`
            <strong style="color:#0F172A;">1.</strong> Création (étab) → <strong>Statut OUVERTE</strong><br/>
            <strong style="color:#0F172A;">2.</strong> Candidatures soignants (vous recevez emails + push)<br/>
            <strong style="color:#0F172A;">3.</strong> Acceptation = assignation → <strong>Statut ASSIGNEE</strong>, taux figés<br/>
            <strong style="color:#0F172A;">4.</strong> Si SALARIE : <strong>upload obligatoire du contrat de travail CDDU</strong> (art. 5.2 contrat de service Jolene)<br/>
            <strong style="color:#0F172A;">5.</strong> Pointage soignant via code 6 chiffres + GPS → <strong>Statut EN_COURS</strong> puis <strong>TERMINEE</strong><br/>
            <strong style="color:#0F172A;">6.</strong> Validation des heures (déclaration sous 48h) → facturation auto
          `)}
          <p style="color:#334155;"><strong>Gestion des absences soignants :</strong> 4 cas possibles (A/B/C/D), traités via la RPC <code>fn_resoudre_absence_mission</code>. Détails dans l'<a href="${APP_URL}/aide/etab-gerer-absence-soignant" style="color:#9333EA;">article dédié</a>.</p>
          <p style="color:#334155;"><strong>Important :</strong> déclarez les <strong>heures réellement travaillées dans les 48 heures</strong> (article 5.1 contrat de service). Cela conditionne la facturation et le respect des règles URSSAF.</p>
          ${BUTTON('Mon tableau de bord →', `${APP_URL}/etablissement/tableau-de-bord`)}
        `),
      };

    case 'SERIE_ETAB_J7':
      return {
        subject: 'Avez-vous publié votre première mission ?',
        html: WRAPPER(`
          <h2 style="color:#0F172A;margin:0 0 12px;">Une semaine sur Jolene !</h2>
          <p style="color:#334155;">${data.nom_etablissement || ''}, vous êtes sur Jolene depuis une semaine. Comment ça se passe de votre côté ?</p>
          ${INFO_BOX(`
            <strong style="color:#0F172A;">Si vous bloquez ou hésitez :</strong><br/>
            • Centre d'aide <a href="${APP_URL}/aide" style="color:#9333EA;">jolene.app/aide</a> — 22 articles dont 8 dédiés aux établissements<br/>
            • Support : <a href="mailto:support@jolene.app" style="color:#9333EA;">support@jolene.app</a> (réponse sous 48h ouvrées)<br/>
            • Onboarding personnalisé : nous pouvons organiser un appel 30 min pour vous accompagner sur votre première mission. Répondez simplement à cet email.
          `)}
          <p style="color:#334155;"><strong>Quelques articles utiles :</strong></p>
          <ul style="color:#334155;line-height:1.6;">
            <li><a href="${APP_URL}/aide/etab-publier-premiere-mission" style="color:#9333EA;">Publier ma première mission</a></li>
            <li><a href="${APP_URL}/aide/etab-pourquoi-uploader-contrat-travail" style="color:#9333EA;">Pourquoi uploader le contrat de travail SALARIE</a></li>
            <li><a href="${APP_URL}/aide/etab-comprendre-commission-jolene" style="color:#9333EA;">Comprendre la commission Jolene</a></li>
            <li><a href="${APP_URL}/aide/etab-resoudre-litige" style="color:#9333EA;">Comment résoudre un litige</a></li>
          </ul>
          ${BUTTON('Ouvrir le centre d\'aide →', `${APP_URL}/aide`)}
          <p style="color:#64748B;font-size:13px;margin-top:16px;">Vous pouvez désactiver cette série d'emails dans <a href="${APP_URL}/etablissement/parametres/notifications" style="color:#9333EA;">Préférences de notifications</a>.</p>
        `),
      };

    // ════════ J2.3.C — Alertes filtres sauvegardés ════════

    case 'NOUVELLES_MISSIONS_FILTRE': {
      const count = Number(rawData.count) || 0;
      const items = Array.isArray(rawData.missions) ? (rawData.missions as any[]) : [];
      const remainingCount = count - items.length;
      const itemsHtml = items.map((m: any) => `
        <div style="border:1px solid #E2E8F0;border-radius:8px;padding:12px;margin:8px 0;background:#fff;">
          <strong style="color:#0F172A;">${escapeHtml(m.intitule || 'Mission')}</strong>
          ${m.urgente ? ' <span style="background:#DC2626;color:white;padding:2px 6px;border-radius:4px;font-size:11px;">URGENT</span>' : ''}
          <br/>
          <span style="color:#334155;">📍 ${escapeHtml(m.etablissement || '—')} · ${escapeHtml(m.ville || '')}</span><br/>
          <span style="color:#334155;">💰 ${m.taux_horaire ? Number(m.taux_horaire).toFixed(2) + ' €/h' : '—'}</span>
        </div>
      `).join('');
      return {
        subject: `${count} nouvelle${count > 1 ? 's' : ''} mission${count > 1 ? 's' : ''} pour « ${data.nom_filtre || 'votre recherche'} »`,
        html: WRAPPER(`
          <h2 style="color:#0F172A;margin:0 0 12px;">🔔 Nouvelles missions pour vous</h2>
          <p style="color:#334155;">Bonjour ${data.prenom || ''},</p>
          <p style="color:#334155;"><strong>${count} mission${count > 1 ? 's' : ''} récente${count > 1 ? 's' : ''}</strong> match${count > 1 ? 'ent' : ''} votre recherche sauvegardée <strong>« ${escapeHtml(data.nom_filtre || '')} »</strong>.</p>
          ${itemsHtml}
          ${remainingCount > 0 ? `<p style="color:#64748B;font-size:13px;text-align:center;margin:12px 0;">+ ${remainingCount} autre${remainingCount > 1 ? 's' : ''} mission${remainingCount > 1 ? 's' : ''}</p>` : ''}
          ${BUTTON('Voir toutes les missions →', `${APP_URL}/soignant/recherche-missions`)}
          <p style="color:#64748B;font-size:13px;margin-top:16px;">
            Vous recevez cet email car vous avez activé les alertes pour cette recherche.
            <a href="${APP_URL}/soignant/parametres/recherches-sauvegardees" style="color:#9333EA;">Gérer mes recherches sauvegardées</a>.
          </p>
        `),
      };
    }

    case 'NOUVEAUX_SOIGNANTS_FILTRE': {
      const count = Number(rawData.count) || 0;
      const items = Array.isArray(rawData.soignants) ? (rawData.soignants as any[]) : [];
      const remainingCount = count - items.length;
      const itemsHtml = items.map((s: any) => `
        <div style="border:1px solid #E2E8F0;border-radius:8px;padding:12px;margin:8px 0;background:#fff;">
          <strong style="color:#0F172A;">${escapeHtml(s.prenom || '')} ${escapeHtml(s.nom_initiale || '')}</strong>
          <br/>
          <span style="color:#334155;">🩺 ${escapeHtml(s.profession || '')}</span>
          ${s.note_moyenne ? `<br/><span style="color:#334155;">⭐ ${Number(s.note_moyenne).toFixed(1)}/5</span>` : ''}
        </div>
      `).join('');
      return {
        subject: `${count} nouveau${count > 1 ? 'x' : ''} soignant${count > 1 ? 's' : ''} pour « ${data.nom_filtre || 'votre recherche'} »`,
        html: WRAPPER(`
          <h2 style="color:#0F172A;margin:0 0 12px;">🔔 Nouveaux soignants pour votre établissement</h2>
          <p style="color:#334155;">Bonjour ${data.nom_etab || ''},</p>
          <p style="color:#334155;"><strong>${count} soignant${count > 1 ? 's' : ''} récent${count > 1 ? 's' : ''}</strong> match${count > 1 ? 'ent' : ''} votre recherche <strong>« ${escapeHtml(data.nom_filtre || '')} »</strong>.</p>
          ${itemsHtml}
          ${remainingCount > 0 ? `<p style="color:#64748B;font-size:13px;text-align:center;margin:12px 0;">+ ${remainingCount} autre${remainingCount > 1 ? 's' : ''} soignant${remainingCount > 1 ? 's' : ''}</p>` : ''}
          ${BUTTON('Accéder à mon dashboard →', `${APP_URL}/etablissement/tableau-de-bord`)}
          <p style="color:#64748B;font-size:13px;margin-top:16px;">
            Vous recevez cet email car vous avez activé les alertes pour cette recherche.
            <a href="${APP_URL}/etablissement/parametres/recherches-sauvegardees" style="color:#9333EA;">Gérer mes recherches sauvegardées</a>.
          </p>
        `),
      };
    }

    case 'MISSION_URGENTE_POOL':
      return {
        subject: `🚨 Mission urgente : ${data.mission_intitule || data.profession || 'opportunité'}`,
        html: WRAPPER(`
          <h2 style="color:#dc2626;margin:0 0 12px;">🚨 Mission urgente près de chez vous</h2>
          <p style="color:#334155;">Bonjour ${data.prenom || ''},</p>
          <p style="color:#334155;"><strong>${data.etab_nom || data.ville || 'Un établissement'}</strong> a publié une mission urgente correspondant à votre profil :</p>
          ${INFO_BOX(`
            <strong>Mission :</strong> ${data.mission_intitule || data.profession || '-'}<br/>
            <strong>Profession :</strong> ${data.profession || '-'}<br/>
            <strong>Lieu :</strong> ${data.ville || '-'}${data.distance_km ? ` (${data.distance_km} km)` : ''}<br/>
            <strong>Taux :</strong> ${data.taux_horaire || '-'} €/h<br/>
            <strong>Début :</strong> ${data.debut_le || '-'}
          `)}
          <p style="color:#334155;"><strong>Acceptez en 1 clic</strong> sur votre espace pool urgence — l'établissement validera ensuite sous 1h.</p>
          ${BUTTON('Voir la mission urgente', `${APP_URL}/soignant/pool-urgence`)}
        `),
      };

    case 'FAVORI_NOUVELLE_MISSION':
      return {
        subject: `⭐ Nouvelle mission chez ${data.etab_nom || 'votre établissement favori'}`,
        html: WRAPPER(`
          <h2 style="color:#0F172A;margin:0 0 12px;">⭐ Nouvelle mission d'un établissement favori</h2>
          <p style="color:#334155;"><strong>${data.etab_nom || 'Un de vos établissements favoris'}</strong> a publié une nouvelle mission :</p>
          ${INFO_BOX(`
            <strong>Mission :</strong> ${data.mission_intitule || '-'}<br/>
            <strong>Lieu :</strong> ${data.etab_ville || '-'}<br/>
            <strong>Taux :</strong> ${data.taux_horaire || '-'} €/h<br/>
            <strong>Début :</strong> ${data.debut_le || '-'}
          `)}
          <p style="color:#334155;">Cet établissement fait partie de vos favoris — vous êtes notifié·e en priorité avant tous les autres soignants.</p>
          ${BUTTON('Voir la mission', `${APP_URL}/soignant/missions/${data.mission_id || ''}`)}
        `),
      };

    case 'COMPTE_SUSPENDU':
      return {
        subject: `🚫 Votre compte Jolene est suspendu`,
        html: WRAPPER(`
          <h2 style="color:#dc2626;margin:0 0 12px;">🚫 Compte suspendu</h2>
          <p style="color:#334155;">Bonjour ${data.prenom || ''},</p>
          <p style="color:#334155;">Votre compte Jolene a été <strong>suspendu</strong>. Raison : ${data.raison === 'absences_sans_prevenir' ? `${data.nb_absences || 3} absences sans prévenir sur les 6 derniers mois` : (data.raison || 'décision admin')}.</p>
          <p style="color:#334155;">Pendant la suspension, vous ne pouvez plus candidater à de nouvelles missions. Les missions déjà acceptées restent valides.</p>
          ${INFO_BOX(`
            <strong>Pour faire un recours</strong>, écrivez à <a href="mailto:support@jolene.app" style="color:#6366f1;">support@jolene.app</a> en précisant votre nom + raison du recours.<br/>
            L'équipe examinera votre dossier sous 72h ouvrées.
          `)}
        `),
      };

    case 'COMPTE_REACTIVE':
      return {
        subject: `✅ Votre compte Jolene est réactivé`,
        html: WRAPPER(`
          <h2 style="color:#10b981;margin:0 0 12px;">✅ Compte réactivé</h2>
          <p style="color:#334155;">Bonjour ${data.prenom || ''},</p>
          <p style="color:#334155;">Bonne nouvelle : votre compte Jolene est <strong>réactivé</strong>. Vous pouvez à nouveau candidater aux missions et utiliser toutes les fonctionnalités.</p>
          ${data.raison ? INFO_BOX(`<strong>Raison :</strong> ${data.raison}`) : ''}
          ${BUTTON('Retour à mon tableau de bord', `${APP_URL}/soignant/tableau-de-bord`)}
        `),
      };

    case 'RAPPEL_NOTATION_ETAB':
      return {
        subject: `Notez votre soignant pour la mission "${data.mission_intitule || ''}"`,
        html: WRAPPER(`
          <h2 style="color:#0F172A;margin:0 0 12px;">⭐ Notez votre soignant</h2>
          <p style="color:#334155;">La mission <strong>"${data.mission_intitule || '-'}"</strong> est terminée depuis hier.</p>
          <p style="color:#334155;">Votre notation aide à enrichir le profil du soignant et à améliorer la qualité de la communauté Jolene.</p>
          ${INFO_BOX(`
            <strong>Vous évaluez 4 critères :</strong><br/>
            • Ponctualité<br/>
            • Professionnalisme<br/>
            • Qualité du soin<br/>
            • Communication<br/>
            <em>Anonyme côté soignant — il voit "Établissement anonyme" + 4 étoiles.</em>
          `)}
          ${BUTTON('Noter le soignant', `${APP_URL}/etablissement/missions/${data.mission_id || ''}`)}
        `),
      };

    case 'RAPPEL_NOTATION_SOIGNANT':
      return {
        subject: `Notez l'établissement pour la mission "${data.mission_intitule || ''}"`,
        html: WRAPPER(`
          <h2 style="color:#0F172A;margin:0 0 12px;">⭐ Notez l'établissement</h2>
          <p style="color:#334155;">La mission <strong>"${data.mission_intitule || '-'}"</strong> est terminée depuis hier.</p>
          <p style="color:#334155;">Vos notations améliorent <strong>votre score de fiabilité</strong> (composante "Vous notez les étabs") et alimentent le score qualité de l'établissement.</p>
          ${INFO_BOX(`
            <strong>Vous évaluez 4 critères :</strong><br/>
            • Accueil<br/>
            • Encadrement<br/>
            • Clarté des consignes<br/>
            • Paiement à temps<br/>
            <em>Anonyme côté étab — il voit "Soignant anonyme" + 4 étoiles.</em>
          `)}
          ${BUTTON('Noter l\'établissement', `${APP_URL}/soignant/missions/${data.mission_id || ''}`)}
        `),
      };

    case 'DPAE_DECLAREE_SOIGNANT':
      return {
        subject: `Votre DPAE a été déclarée pour ${data.mission_intitule || 'votre mission'}`,
        html: WRAPPER(`
          <h2 style="color:#0F172A;margin:0 0 12px;">Votre DPAE a été déclarée ✅</h2>
          <p style="color:#334155;">Bonjour ${data.prenom || ''},</p>
          <p style="color:#334155;">
            <strong>${data.etablissement_nom || "L'établissement"}</strong> a déclaré votre
            Déclaration Préalable à l'Embauche (DPAE) auprès de l'URSSAF pour la mission
            <strong>${data.mission_intitule || 'à venir'}</strong>.
          </p>
          ${CARD_BOX(`
            <strong style="color:#0F172A;">Numéro DPAE URSSAF</strong><br/>
            <span style="font-family:monospace;font-size:16px;color:#E04590;">${data.dpae_numero || '—'}</span>
          `)}
          <p style="color:#334155;font-size:13px;">
            Conservez ce numéro : il prouve votre embauche déclarée auprès des organismes sociaux.
            Vous pouvez vous présenter à votre poste en toute conformité.
          </p>
          ${BUTTON('Voir mon contrat', `${APP_URL}/contrat/${data.contrat_id || ''}`)}
          ${SECURITY_NOTE}
        `),
      };

    case 'DPAE_ANNULATION_RAPPEL':
      return {
        subject: `Action requise — annuler la DPAE du contrat ${data.numero_contrat || ''}`,
        html: WRAPPER(`
          <h2 style="color:#DC2626;margin:0 0 12px;">Annulation DPAE à effectuer</h2>
          <p style="color:#334155;">Le contrat <strong>${escapeHtml(data.numero_contrat || '—')}</strong> a été annulé.</p>
          ${CARD_BOX(`
            <strong>Type :</strong> ${escapeHtml(data.type_contrat || '—')}<br/>
            <strong>DPAE :</strong> ${escapeHtml(data.dpae_numero || '—')}<br/>
            <strong>Délai :</strong> ${escapeHtml(data.echeance_legale_h || 48)} heures
          `)}
          ${INFO_BOX('Effectuez l’annulation sur Net-Entreprises et conservez la preuve dans votre dossier.')}
          ${BUTTON('Ouvrir Net-Entreprises →', 'https://www.net-entreprises.fr/declaration-prealable-embauche/')}
          ${SECURITY_NOTE}
        `),
      };

    case 'NOTIFICATION_PUSH_FALLBACK':
      return {
        subject: `Notification Jolene — ${data.titre || 'nouvelle information'}`,
        html: WRAPPER(`
          <h2 style="color:#0F172A;margin:0 0 12px;">${data.titre || 'Nouvelle notification'}</h2>
          <p style="color:#334155;">${data.corps || 'Une nouvelle information vous attend dans Jolene.'}</p>
          ${BUTTON('Ouvrir Jolene →', APP_URL)}
          ${SECURITY_NOTE}
        `),
      };

    case 'CONFIRMATION_EMAIL_PRO_ETAB': {
      const confirmUrl = `${FUNCTIONS_URL}/confirm-email-etab?token=${encodeURIComponent(String(data.token || ''))}`;
      return {
        subject: 'Confirmez votre adresse e-mail professionnelle — Jolene',
        html: WRAPPER(`
          <h2 style="color:#0F172A;margin:0 0 12px;">Confirmez votre e-mail professionnel</h2>
          <p style="color:#334155;">Vous avez demandé à rattacher l'établissement <strong>${escapeHtml(data.etablissement_nom)}</strong> à cette adresse e-mail.</p>
          <p style="color:#334155;">Pour valider votre identité professionnelle et activer la publication de missions, cliquez sur le bouton ci-dessous :</p>
          ${BUTTON('Confirmer mon adresse e-mail', confirmUrl)}
          <p style="color:#64748B;font-size:13px;margin-top:16px;">Ce lien est valable 24 heures. Si vous n'êtes pas à l'origine de cette demande, ignorez cet e-mail.</p>
        `),
      };
    }

    default:
      return null;
  }
}

// ─── Main handler ────────────────────────────────────────

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders(req) });
  }

  // Warm ping admin/interne uniquement : il divulgue l'etat d'un fournisseur
  // payant et ne doit pas devenir un endpoint public sans quota.
  // Body attendu : { warm: true }. Réponse : { warm: true } 200.
  try {
    const peeked = await req.clone().json().catch(() => null);
    if (peeked && (peeked as Record<string, unknown>).warm === true) {
      const warmAuth = await verifyAdminOrServiceRole(req);
      if (!warmAuth.ok) {
        return new Response(JSON.stringify({ error: warmAuth.error }), {
          status: warmAuth.status,
          headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
        });
      }
      return new Response(JSON.stringify({ warm: true }), {
        status: 200,
        headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
      });
    }
  } catch { /* fallthrough to normal flow */ }

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
  // Nouveau format asymétrique sb_secret_… stocké en vault (pg_cron / RPC).
  const newSecretKey = Deno.env.get('SUPABASE_SECRET_KEY') || Deno.env.get('SB_SECRET_KEY') || '';

  // C1: Strict equality for service_role validation (prevents partial key match) —
  // accepte legacy JWT, nouveau secret asymétrique, ou secret stocké en vault.
  let isServiceRole = (token === serviceRoleKey) || (!!newSecretKey && token === newSecretKey);
  if (!isServiceRole) {
    try {
      const sbAdmin = createClient(supabaseUrl, serviceRoleKey);
      const { data: vaultSecret } = await sbAdmin.rpc('fn_lire_secret_cron');
      if (vaultSecret && token === vaultSecret) isServiceRole = true;
    } catch (_e) { /* ignore */ }
  }

  let userId: string | null = null;
  let userEmail: string | null = null;
  let isPlatformAdmin = false;

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
    isPlatformAdmin = user.app_metadata?.role === 'ADMIN_PLATEFORME';
  }

  // Les crons service_role peuvent légitimement envoyer des lots de plus de
  // cinq messages. Les utilisateurs et admins restent limités, mais seulement
  // après validation du JWT afin qu'un appel anonyme ne consomme pas leur quota.
  if (
    !isServiceRole
    && applyRateLimit('send-email', getClientIp(req), {
      max: 5,
      windowMs: 60_000,
    })
  ) {
    return new Response(JSON.stringify({
      error: 'Trop d\'emails envoyés. Réessayez dans 1 minute.',
    }), {
      status: 429,
      headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
    });
  }

  try {
    const body = await req.json();
    const {
      type,
      data: templateData,
      destinataire_id,
      destinataire_email: bodyEmail,
      idempotency_key: idempotencyKey,
    } = body;

    if (isPlatformAdmin) {
      const adminAuth = await verifyAdminOrServiceRole(req);
      if (!adminAuth.ok) {
        return new Response(JSON.stringify({ error: adminAuth.error }), {
          status: adminAuth.status,
          headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
        });
      }
    }

    // [Sprint 6 PR 1] INVITATION_EQUIPE_ETAB peut viser un email non-user (invité externe).
    // Pour ce cas précis, on accepte destinataire_email sans destinataire_id mais on exige
    // service_role pour empêcher l'envoi d'emails arbitraires depuis le browser.
    const isExternalInviteFlow = type === 'INVITATION_EQUIPE_ETAB' && !destinataire_id && bodyEmail;
    if (isExternalInviteFlow && !isServiceRole) {
      return new Response(JSON.stringify({ error: 'INVITATION_EQUIPE_ETAB externe nécessite service_role' }), {
        status: 403,
        headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
      });
    }

    // Strict validation: type requis, destinataire_id OU (INVITATION_EQUIPE_ETAB + destinataire_email)
    if (!type || (!destinataire_id && !isExternalInviteFlow)) {
      return new Response(JSON.stringify({ error: 'Paramètres requis : type, destinataire_id, data' }), {
        status: 400,
        headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
      });
    }

    // C2-FIX: Validate destinataire_id is a strict UUID to prevent PostgREST filter injection
    const UUID_REGEX = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
    if (destinataire_id && !UUID_REGEX.test(destinataire_id)) {
      return new Response(JSON.stringify({ error: 'destinataire_id invalide' }), {
        status: 400,
        headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
      });
    }

    const IDEMPOTENCY_KEY_REGEX = /^[A-Za-z0-9][A-Za-z0-9._:-]{7,199}$/;
    if (
      idempotencyKey !== undefined
      && (
        typeof idempotencyKey !== 'string'
        || !IDEMPOTENCY_KEY_REGEX.test(idempotencyKey)
      )
    ) {
      return new Response(JSON.stringify({
        error: 'idempotency_key invalide (8 à 200 caractères sûrs)',
      }), {
        status: 400,
        headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
      });
    }

    if (isExternalInviteFlow) {
      const EMAIL_REGEX = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;
      if (!EMAIL_REGEX.test(bodyEmail)) {
        return new Response(JSON.stringify({ error: 'destinataire_email invalide' }), {
          status: 400,
          headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
        });
      }
    }

    if (!ALLOWED_TYPES.has(type)) {
      return new Response(JSON.stringify({ error: 'Type inconnu' }), {
        status: 400,
        headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
      });
    }

    const supabaseService = createClient(supabaseUrl, serviceRoleKey);

    // Autoriser la cible avant toute classification, lecture de préférences ou
    // résolution d'adresse. Sinon les réponses test_account / preference_off /
    // introuvable deviennent un oracle sur l'existence et l'état d'un compte.
    // Le flow externe est déjà limité au service_role plus haut.
    if (!isServiceRole && !isPlatformAdmin && !isExternalInviteFlow && destinataire_id !== userId) {
      const { count } = await supabaseService
        .from('missions')
        .select('id', { count: 'exact', head: true })
        .or(
          `and(etablissement_id.eq.${userId},soignant_assigne_id.eq.${destinataire_id}),` +
          `and(etablissement_id.eq.${destinataire_id},soignant_assigne_id.eq.${userId})`
        );

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

    // Les fixtures conservent leurs notifications in-app mais ne déclenchent
    // jamais un fournisseur email réel. Une erreur de classification bloque
    // également l'envoi (fail-closed).
    if (destinataire_id) {
      const testAccount = await resolveOperationalTestAccount(
        supabaseService,
        destinataire_id,
      );
      if (!testAccount.ok) {
        console.error('[send-email] classification test indisponible');
        return new Response(JSON.stringify({
          error: 'Classification du destinataire indisponible',
        }), {
          status: 503,
          headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
        });
      }
      if (testAccount.isTest) {
        await Promise.resolve(supabaseService.from('journaux_audit').insert({
          acteur_id: null,
          type_acteur: 'SYSTEME',
          action: 'NOTIFICATION_SKIPPED',
          type_ressource: 'email',
          id_ressource: destinataire_id,
          details: { type, canal: 'EMAIL', raison: 'test_account' },
        })).catch(() => {});
        return new Response(JSON.stringify({
          success: true,
          skipped: true,
          reason: 'test_account',
        }), {
          status: 200,
          headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
        });
      }
    }

    const sourceAccount = await resolveOperationalTestSource(
      supabaseService,
      templateData,
    );
    if (!sourceAccount.ok) {
      console.error('[send-email] classification source test indisponible');
      return new Response(JSON.stringify({
        error: 'Classification de la source indisponible',
      }), {
        status: 503,
        headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
      });
    }
    if (sourceAccount.isTest) {
      await Promise.resolve(supabaseService.from('journaux_audit').insert({
        acteur_id: null,
        type_acteur: 'SYSTEME',
        action: 'NOTIFICATION_SKIPPED',
        type_ressource: 'email',
        id_ressource: destinataire_id || null,
        details: { type, canal: 'EMAIL', raison: 'test_source' },
      })).catch(() => {});
      return new Response(JSON.stringify({
        success: true,
        skipped: true,
        reason: 'test_source',
      }), {
        status: 200,
        headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
      });
    }

    // [J2.3.A] Vérification préférences notifications avant envoi
    // Mapping type Resend → type_evenement_notification (enum DB)
    const TYPE_TO_EVENT: Record<string, string> = {
      'BIENVENUE_SOIGNANT': 'SERIE_ONBOARDING',
      'BIENVENUE_ETABLISSEMENT': 'SERIE_ONBOARDING',
      'SERIE_SOIGNANT_J0': 'SERIE_ONBOARDING', 'SERIE_SOIGNANT_J1': 'SERIE_ONBOARDING',
      'SERIE_SOIGNANT_J3': 'SERIE_ONBOARDING', 'SERIE_SOIGNANT_J7': 'SERIE_ONBOARDING',
      'SERIE_ETAB_J0': 'SERIE_ONBOARDING', 'SERIE_ETAB_J1': 'SERIE_ONBOARDING',
      'SERIE_ETAB_J3': 'SERIE_ONBOARDING', 'SERIE_ETAB_J7': 'SERIE_ONBOARDING',
      'MISSION_ACCEPTEE_SOIGNANT': 'CANDIDATURE_ACCEPTEE',
      'MISSION_ACCEPTEE_ETABLISSEMENT': 'CANDIDATURE_RECUE',
      'MISSION_PROPOSEE': 'MISSION_ASSIGNEE',
      'RAPPEL_MISSION': 'RAPPEL_J1_MISSION',
      'MISSION_TERMINEE': 'MISSION_ASSIGNEE',
      'MISSION_URGENTE': 'URGENCE',
      'FACTURE_EMISE': 'FACTURE_EMISE',
      'FACTURE_PAYEE': 'PAIEMENT_RECU',
      'PAIEMENT_CONFIRME': 'PAIEMENT_RECU', 'PAIEMENT_RAPIDE_RECU': 'PAIEMENT_RECU',
      'RAPPEL_FACTURE': 'FACTURE_EMISE',
      'DOCUMENT_EXPIRANT': 'DOCUMENT_EXPIRANT',
      'RAPPEL_DOCUMENTS': 'DOCUMENT_EXPIRANT',
      'CONTRAT_TRAVAIL_DEPOSE': 'CONTRAT_TRAVAIL_DEPOSE',
      'CONTRAT_TRAVAIL_RAPPEL_ETAB': 'CONTRAT_TRAVAIL_DEPOSE',
      'CONTRAT_TRAVAIL_MANQUANT_SOIGNANT': 'CONTRAT_TRAVAIL_DEPOSE',
      'CONTRAT_A_SIGNER': 'CONTRAT_TRAVAIL_DEPOSE',
      'CONTRAT_SIGNE': 'CONTRAT_TRAVAIL_DEPOSE',
      'LITIGE_OUVERTURE': 'LITIGE_OUVERT', 'LITIGE_NOUVEAU_MESSAGE': 'LITIGE_OUVERT',
      'LITIGE_RESOLU_AJUSTE': 'LITIGE_RESOLU', 'LITIGE_RAPPEL_J1': 'LITIGE_OUVERT',
      'LITIGE_RAPPEL_J3': 'LITIGE_OUVERT', 'LITIGE_RAPPEL_J5': 'LITIGE_OUVERT',
      'LITIGE_ESCALADE_ADMIN': 'URGENCE', 'LITIGE_MEDIATION_PRIORITAIRE': 'URGENCE',
      // [J2.3.C] alertes filtres sauvegardés
      'NOUVELLES_MISSIONS_FILTRE': 'NOUVELLE_MISSION_MATCHANT_FILTRE',
      'NOUVEAUX_SOIGNANTS_FILTRE': 'NOUVEAU_SOIGNANT_MATCHANT_FILTRE',
      // [J5.C] pool urgence
      'MISSION_URGENTE_POOL': 'URGENCE',
      // [J5.G] favoris bidirectionnels
      'FAVORI_NOUVELLE_MISSION': 'FAVORI_NOUVELLE_MISSION',
      // [Refonte.D.3] rappel notation J+1
      'RAPPEL_NOTATION_ETAB': 'NOTATION_RAPPEL',
      'RAPPEL_NOTATION_SOIGNANT': 'NOTATION_RAPPEL',
      'EVALUATION_RECUE': 'NOTATION_RAPPEL',
      'AVOIR_EMIS': 'PAIEMENT_RECU',
      'REMBOURSEMENT_CONFIRME': 'PAIEMENT_RECU',
      'COMMISSION_AJUSTEE': 'PAIEMENT_RECU',
      'PAIEMENT_SOIGNANT_DECLARE': 'PAIEMENT_RECU',
      'RAPPEL_PAIEMENT_J7': 'PAIEMENT_RECU',
      // Les types ALWAYS_SEND_TRANSACTIONAL_TYPES sont explicitement exempts.
    };
    const typeEvenement = TYPE_TO_EVENT[type] || null;

    // Flow externe/transactionnel obligatoire : pas de preference utilisateur.
    // Pour tout le reste, un type hors enum respecte au minimum canal_email.
    if (!isExternalInviteFlow && !ALWAYS_SEND_TRANSACTIONAL_TYPES.has(type)) {
      const supabaseCheck = createClient(supabaseUrl, serviceRoleKey);
      let shouldNotify: boolean;
      if (typeEvenement) {
        const { data, error } = await supabaseCheck.rpc('fn_doit_notifier' as any, {
          p_utilisateur_id: destinataire_id,
          p_type_evenement: typeEvenement,
          p_canal: 'EMAIL',
        });
        if (error || typeof data !== 'boolean') {
          console.error('[send-email] verification preferences impossible', error?.message);
          return new Response(JSON.stringify({ error: 'Verification des preferences indisponible' }), {
            status: 503,
            headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
          });
        }
        shouldNotify = data;
      } else {
        const { data, error } = await supabaseCheck
          .from('preferences_notifications')
          .select('canal_email')
          .eq('utilisateur_id', destinataire_id)
          .maybeSingle();
        if (error) {
          console.error('[send-email] lecture preference globale impossible', error.message);
          return new Response(JSON.stringify({ error: 'Verification des preferences indisponible' }), {
            status: 503,
            headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
          });
        }
        shouldNotify = data?.canal_email ?? true;
      }
      if (shouldNotify === false) {
        // Audit le skip pour traçabilité, puis return 200 silent
        await Promise.resolve(supabaseCheck.from('journaux_audit').insert({
          acteur_id: null, type_acteur: 'SYSTEME',
          action: 'NOTIFICATION_SKIPPED', type_ressource: 'email',
          id_ressource: destinataire_id,
          details: { type, type_evenement: typeEvenement, canal: 'EMAIL', raison: 'preference_user_off' },
        })).catch(() => {});
        return new Response(JSON.stringify({ success: true, skipped: true, reason: 'preference_user_off' }), {
          status: 200,
          headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
        });
      }
    }

    // Resolve email server-side from destinataire_id.
    // Order de fallback (auth.admin.getUserById ne marche plus avec sb_secret_
    // bearer côté Supabase platform — régression observée 2026-04-29) :
    //   1. soignants.email (table denormalisée)
    //   2. etablissements.email_contact
    //   3. auth.users.email (via SQL direct, plus auth.admin)
    let resolvedEmail: string | null = null;

    if (isExternalInviteFlow) {
      // Flow externe : destinataire_email fourni directement (invité non-user)
      resolvedEmail = bodyEmail;
    } else {
      const { data: soignant } = await supabaseService
        .from('soignants').select('email').eq('id', destinataire_id).maybeSingle();
      if (soignant?.email) {
        resolvedEmail = soignant.email;
      } else {
        const { data: etab } = await supabaseService
          .from('etablissements').select('email_contact').eq('id', destinataire_id).maybeSingle();
        if (etab?.email_contact) {
          resolvedEmail = etab.email_contact;
        } else {
          // Dernier fallback : auth.admin (peut échouer avec sb_secret_)
          try {
            const { data: authUser } = await supabaseService.auth.admin.getUserById(destinataire_id);
            if (authUser?.user?.email) resolvedEmail = authUser.user.email;
          } catch (_e) { /* silently fall through to 404 */ }
        }
      }
    }

    if (!resolvedEmail) {
      return new Response(JSON.stringify({ error: 'Destinataire introuvable' }), {
        status: 404,
        headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
      });
    }

    const rendered = renderTemplate(type, templateData || {});
    if (!rendered) {
      return new Response(JSON.stringify({ error: 'Type inconnu' }), {
        status: 400,
        headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
      });
    }

    const { subject, html } = rendered;

    // CP-LITIGES-7a FIX 16 : attachment PDF pour AVOIR_EMIS
    const MAX_ATTACHMENT_BYTES = 10 * 1024 * 1024; // 10 MB
    let attachments: Array<{ filename: string; content: string }> | undefined;

    if (rendered.hasAttachment && type === 'AVOIR_EMIS' && templateData?.avoir_id) {
      try {
        const { data: avoir } = await supabaseService
          .from('factures_honoraires')
          .select('pdf_s3_key, numero_facture')
          .eq('id', templateData.avoir_id)
          .single();

        if (avoir?.pdf_s3_key) {
          const { data: blob, error: dlErr } = await supabaseService.storage
            .from('jolene-documents')
            .download(avoir.pdf_s3_key);

          if (dlErr || !blob) {
            console.warn(`[send-email] AVOIR_EMIS attachment: PDF download failed (${avoir.pdf_s3_key}):`, dlErr);
          } else if (blob.size > MAX_ATTACHMENT_BYTES) {
            console.warn(`[send-email] AVOIR_EMIS attachment: PDF too large (${blob.size} bytes > ${MAX_ATTACHMENT_BYTES}), skipping attachment`);
          } else {
            const buffer = await blob.arrayBuffer();
            const bytes = new Uint8Array(buffer);
            let binary = '';
            for (let i = 0; i < bytes.length; i++) {
              binary += String.fromCharCode(bytes[i]);
            }
            const base64 = btoa(binary);
            const safeNumero = (avoir.numero_facture || 'avoir').replace(/[^a-zA-Z0-9_-]/g, '_');
            attachments = [{ filename: `avoir-${safeNumero}.pdf`, content: base64 }];
          }
        } else {
          console.warn(`[send-email] AVOIR_EMIS attachment: no pdf_s3_key for avoir ${templateData.avoir_id} — PDF not yet generated`);
        }
      } catch (e) {
        console.warn('[send-email] AVOIR_EMIS attachment fetch error:', e);
      }
    }

    // Comptes de test E2E : ne JAMAIS envoyer de vrai email (les tests
    // Playwright déroulent les flux réels contre la prod — 200+ notifications
    // le 12/06 ont épuisé le quota Resend quotidien et bombardé des boîtes
    // inexistantes = bounces qui dégradent la réputation du domaine).
    // Succès silencieux : les flux appelants ne doivent pas échouer.
    if (/^playwright-[a-z0-9.-]*@jolene\.app$/i.test(resolvedEmail)) {
      console.log(`[send-email] compte de test E2E (${resolvedEmail}) — envoi ignoré`);
      return new Response(JSON.stringify({ success: true, skipped: true, reason: 'compte_test_e2e' }), {
        headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
      });
    }

    const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY');
    if (!RESEND_API_KEY) {
      console.error('RESEND_API_KEY not configured');
      return new Response(JSON.stringify({
        success: false,
        error: 'Fournisseur email non configuré',
      }), {
        status: 503,
        headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
      });
    }

    let requestFingerprint: string | null = null;
    if (idempotencyKey) {
      requestFingerprint = await sha256Hex({
        type,
        destinataire_id: destinataire_id || null,
        destinataire_email: resolvedEmail.trim().toLowerCase(),
        data: templateData || {},
      });

      const { data: reservation, error: reservationError } =
        await supabaseService.rpc('fn_reserver_envoi_email_idempotent' as any, {
          p_idempotency_key: idempotencyKey,
          p_request_fingerprint: requestFingerprint,
        });

      if (reservationError || !reservation || typeof reservation !== 'object') {
        console.error(
          '[send-email] réservation idempotente indisponible',
          reservationError?.message,
        );
        return new Response(JSON.stringify({
          error: 'Réservation idempotente indisponible',
        }), {
          status: 503,
          headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
        });
      }

      const reservationStatus = (reservation as Record<string, unknown>).statut;
      if (reservationStatus === 'CONFLIT') {
        return new Response(JSON.stringify({
          error: 'idempotency_key déjà utilisée pour une autre requête',
        }), {
          status: 409,
          headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
        });
      }
      if (reservationStatus === 'DEJA_ENVOYE') {
        return new Response(JSON.stringify({
          success: true,
          skipped: true,
          reason: 'idempotency_already_sent',
        }), {
          status: 200,
          headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
        });
      }
      if (reservationStatus === 'EN_COURS') {
        return new Response(JSON.stringify({
          success: true,
          pending: true,
          reason: 'idempotency_in_progress',
        }), {
          status: 202,
          headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
        });
      }
      if (reservationStatus !== 'RESERVE') {
        console.error('[send-email] état de réservation idempotente inconnu');
        return new Response(JSON.stringify({
          error: 'Réservation idempotente invalide',
        }), {
          status: 503,
          headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
        });
      }
    }

    const emailPayload: Record<string, unknown> = {
      from: 'Jolene <bonjour@jolene.app>',
      // bonjour@ n'a pas de boîte de réception (expéditeur Resend uniquement) :
      // les réponses sont routées vers une boîte réelle et relevée.
      reply_to: 'gabrielle@jolene.app',
      to: [resolvedEmail],
      subject,
      html,
    };
    if (attachments && attachments.length > 0) {
      emailPayload.attachments = attachments;
    }

    const resendHeaders: Record<string, string> = {
      'Authorization': `Bearer ${RESEND_API_KEY}`,
      'Content-Type': 'application/json',
    };
    if (idempotencyKey) {
      resendHeaders['Idempotency-Key'] = idempotencyKey;
    }

    let response: Response;
    let resData: Record<string, unknown>;
    try {
      response = await fetch('https://api.resend.com/emails', {
        method: 'POST',
        headers: resendHeaders,
        body: JSON.stringify(emailPayload),
      });
      const responseText = await response.text();
      try {
        resData = responseText
          ? JSON.parse(responseText) as Record<string, unknown>
          : {};
      } catch {
        resData = { error: 'Réponse fournisseur non JSON' };
      }
    } catch {
      if (idempotencyKey && requestFingerprint) {
        await supabaseService.rpc(
          'fn_finaliser_envoi_email_idempotent' as any,
          {
            p_idempotency_key: idempotencyKey,
            p_request_fingerprint: requestFingerprint,
            p_succes: false,
            p_provider_id: null,
            p_erreur: 'Erreur réseau fournisseur',
          },
        );
      }
      return new Response(JSON.stringify({
        success: false,
        error: 'Fournisseur email indisponible',
      }), {
        status: 502,
        headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
      });
    }

    if (idempotencyKey && requestFingerprint) {
      const { error: finalizationError } = await supabaseService.rpc(
        'fn_finaliser_envoi_email_idempotent' as any,
        {
          p_idempotency_key: idempotencyKey,
          p_request_fingerprint: requestFingerprint,
          p_succes: response.ok,
          p_provider_id: typeof resData.id === 'string' ? resData.id : null,
          p_erreur: response.ok ? null : JSON.stringify(resData).slice(0, 2000),
        },
      );
      if (finalizationError) {
        console.error(
          '[send-email] finalisation idempotente indisponible',
          finalizationError.message,
        );
      }
    }

    // Log in emails_envoyes
    const emailAudit = {
      destinataire_email: resolvedEmail,
      destinataire_id: destinataire_id || null,
      type,
      sujet: subject,
      provider_id: typeof resData.id === 'string' ? resData.id : null,
      statut: response.ok ? 'ENVOYE' : 'ERREUR',
      erreur: response.ok ? null : JSON.stringify(resData),
      idempotency_key: idempotencyKey || null,
    };
    const { error: auditError } = idempotencyKey
      ? await supabaseService
        .from('emails_envoyes')
        .upsert(emailAudit, { onConflict: 'idempotency_key' })
      : await supabaseService.from('emails_envoyes').insert(emailAudit);
    if (auditError) {
      console.error('[send-email] journal email indisponible', auditError.message);
    }

    return new Response(JSON.stringify({ success: response.ok }), {
      status: response.ok ? 200 : 502,
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
