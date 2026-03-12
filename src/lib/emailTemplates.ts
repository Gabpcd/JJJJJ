const APP_URL = 'https://soindirect.com';

const WRAPPER = (content: string) => `
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width"></head>
<body style="margin:0;padding:0;background:#F8FAFC;font-family:'Segoe UI',Arial,sans-serif;">
  <div style="max-width:600px;margin:0 auto;background:white;border-radius:0 0 12px 12px;overflow:hidden;">
    <div style="background:#0F172A;padding:28px 24px;text-align:center;">
      <span style="color:#17A2B8;font-size:30px;font-weight:bold;letter-spacing:-0.5px;">❤️ Soin Direct</span>
    </div>
    <div style="padding:36px 28px 24px;">
      ${content}
    </div>
    <div style="border-top:1px solid #E2E8F0;padding:20px 24px;text-align:center;font-size:11px;color:#94A3B8;">
      <p style="margin:0 0 6px;">Soin Direct SAS — <a href="${APP_URL}" style="color:#17A2B8;text-decoration:none;">soindirect.com</a></p>
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

// ─── INSCRIPTION ─────────────────────────────────────────

export function emailBienvenueSoignant(prenom: string) {
  return WRAPPER(`
    <h2 style="color:#0F172A;margin:0 0 12px;">Bienvenue ${prenom} ! 🎉</h2>
    <p style="color:#334155;">Votre compte soignant est créé. Voici les prochaines étapes :</p>
    ${INFO_BOX(`
      <strong style="color:#0F172A;">1.</strong> Complétez votre profil (RPPS, adresse)<br/>
      <strong style="color:#0F172A;">2.</strong> Téléversez vos documents (diplôme, RCP, identité)<br/>
      <strong style="color:#0F172A;">3.</strong> Parcourez les missions près de chez vous
    `)}
    ${BUTTON('Compléter mon profil →', `${APP_URL}/soignant/profil`)}
  `);
}

export function emailBienvenueEtablissement(nom: string) {
  return WRAPPER(`
    <h2 style="color:#0F172A;margin:0 0 12px;">Bienvenue ${nom} !</h2>
    <p style="color:#334155;">Votre établissement est enregistré sur Soin Direct.</p>
    ${INFO_BOX(`
      <strong style="color:#0F172A;">1.</strong> Complétez votre profil (SIRET, FINESS, adresse)<br/>
      <strong style="color:#0F172A;">2.</strong> Publiez votre première mission<br/>
      <strong style="color:#0F172A;">3.</strong> Recevez des candidatures en quelques heures
    `)}
    ${BUTTON('Publier une mission →', `${APP_URL}/etablissement/missions/creer`)}
  `);
}

// ─── MISSION ACCEPTÉE ────────────────────────────────────

export function emailMissionAccepteeSoignant(prenom: string, mission: string, date: string, etab: string, missionId: string) {
  return WRAPPER(`
    <h2 style="color:#0F172A;margin:0 0 12px;">Mission confirmée ✅</h2>
    <p style="color:#334155;">Bonjour ${prenom},</p>
    ${CARD_BOX(`
      <strong style="color:#0F172A;">${mission}</strong><br/>
      <span style="color:#334155;">📍 ${etab}</span><br/>
      <span style="color:#334155;">📅 ${date}</span>
    `)}
    <p style="color:#334155;">⚠️ Pensez à <strong>signer votre contrat</strong> dans l'app avant le début de la mission.</p>
    ${BUTTON('Voir la mission →', `${APP_URL}/soignant/missions/${missionId}`)}
    ${SECURITY_NOTE}
  `);
}

export function emailMissionAccepteeEtablissement(nomEtab: string, soignantNom: string, mission: string, date: string, missionId: string) {
  return WRAPPER(`
    <h2 style="color:#0F172A;margin:0 0 12px;">Mission acceptée par un soignant ✅</h2>
    <p style="color:#334155;">Bonjour,</p>
    <p style="color:#334155;"><strong>${soignantNom}</strong> a accepté votre mission :</p>
    ${CARD_BOX(`
      <strong style="color:#0F172A;">${mission}</strong><br/>
      <span style="color:#334155;">📅 ${date}</span>
    `)}
    <p style="color:#334155;">Un contrat sera généré automatiquement. Vous recevrez un email pour le signer.</p>
    ${BUTTON('Voir la mission →', `${APP_URL}/etablissement/missions/${missionId}`)}
    ${SECURITY_NOTE}
  `);
}

// Keep legacy alias for backward compat
export function emailMissionAcceptee(prenom: string, mission: string, date: string, etab: string) {
  return emailMissionAccepteeSoignant(prenom, mission, date, etab, '');
}

// ─── CONTRAT ─────────────────────────────────────────────

export function emailContratASignerSoignant(prenom: string, mission: string, contratId: string) {
  return WRAPPER(`
    <h2 style="color:#0F172A;margin:0 0 12px;">📝 Contrat à signer</h2>
    <p style="color:#334155;">Bonjour ${prenom},</p>
    <p style="color:#334155;">Un contrat a été généré pour votre mission <strong>"${mission}"</strong>.</p>
    ${INFO_BOX('Vous devez le signer <strong>avant le début de la mission</strong> pour pouvoir pointer votre arrivée.')}
    ${BUTTON('Signer le contrat →', `${APP_URL}/contrat/${contratId}`)}
    ${SECURITY_NOTE}
  `);
}

export function emailContratASignerEtablissement(nomEtab: string, soignant: string, contratId: string) {
  return WRAPPER(`
    <h2 style="color:#0F172A;margin:0 0 12px;">📝 Contrat à signer</h2>
    <p style="color:#334155;">Bonjour,</p>
    <p style="color:#334155;"><strong>${soignant}</strong> a accepté votre mission. Un contrat a été généré.</p>
    <p style="color:#334155;">Signez-le pour confirmer la collaboration.</p>
    ${BUTTON('Signer le contrat →', `${APP_URL}/contrat/${contratId}`)}
    ${SECURITY_NOTE}
  `);
}

// ─── FACTURE ─────────────────────────────────────────────

export function emailFactureMensuelle(nomEtab: string, numero: string, ttc: string, factureId: string) {
  return WRAPPER(`
    <h2 style="color:#0F172A;margin:0 0 12px;">Facture ${numero}</h2>
    <p style="color:#334155;">Bonjour,</p>
    ${CARD_BOX(`
      <strong style="color:#0F172A;">Facture ${numero}</strong><br/>
      <span style="color:#334155;">Montant TTC : <strong>${ttc} €</strong></span><br/>
      <span style="color:#334155;">Échéance : 30 jours</span>
    `)}
    ${BUTTON('💳 Consulter et payer →', `${APP_URL}/etablissement/facturation/${factureId}`)}
    ${SECURITY_NOTE}
  `);
}

// ─── RAPPELS & ALERTES ───────────────────────────────────

export function emailRappelMission(prenom: string, mission: string, heure: string, etab: string) {
  return WRAPPER(`
    <h2 style="color:#F59E0B;margin:0 0 12px;">⏰ Rappel : mission demain</h2>
    <p style="color:#334155;">Bonjour ${prenom},</p>
    <div style="background:#FEF3C7;border:1px solid #F59E0B;border-radius:8px;padding:16px 18px;margin:16px 0;">
      <strong style="color:#0F172A;">${mission}</strong><br/>
      <span style="color:#334155;">📍 ${etab}</span><br/>
      <span style="color:#334155;">🕐 ${heure}</span>
    </div>
    <p style="color:#334155;">N'oubliez pas votre pointage d'arrivée dans l'app !</p>
    ${BUTTON('Voir mon planning →', `${APP_URL}/soignant/planning`)}
  `);
}

export function emailDocumentExpirant(prenom: string, typeDoc: string, dateExp: string) {
  return WRAPPER(`
    <h2 style="color:#F59E0B;margin:0 0 12px;">⚠️ Document bientôt expiré</h2>
    <p style="color:#334155;">Bonjour ${prenom},</p>
    <p style="color:#334155;">Votre <strong>${typeDoc}</strong> expire le <strong>${dateExp}</strong>.</p>
    <p style="color:#334155;">Sans document valide, vous ne pourrez plus accepter de missions.</p>
    ${BUTTON('Mettre à jour →', `${APP_URL}/soignant/documents`)}
  `);
}
