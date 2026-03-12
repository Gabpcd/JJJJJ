const HEADER = `<div style="font-family:'Inter',Helvetica,Arial,sans-serif;max-width:600px;margin:0 auto;background:#fff;border-radius:16px;overflow:hidden;">
<div style="background:linear-gradient(135deg,#0e9aa7,#3dc1d3);padding:24px;text-align:center;">
  <span style="color:#fff;font-size:24px;font-weight:bold;">❤️ Soin Direct</span>
</div>`;

const FOOTER = `<div style="background:#f8fafc;padding:16px;text-align:center;border-top:1px solid #e2e8f0;">
  <p style="font-size:12px;color:#94a3b8;margin:0;">Soin Direct SAS — <a href="https://soindirect.com" style="color:#0e9aa7;">soindirect.com</a></p>
  <p style="font-size:11px;color:#94a3b8;margin:4px 0 0;">Vous recevez cet email car vous êtes inscrit(e) sur Soin Direct.</p>
</div></div>`;

export function emailBienvenueSoignant(prenom: string) {
  return `${HEADER}
  <div style="padding:32px 24px;">
    <h2 style="color:#1e293b;margin:0 0 16px;">Bienvenue ${prenom} ! 🎉</h2>
    <p style="color:#475569;font-size:14px;line-height:1.6;">Votre compte Soin Direct est créé. Voici les prochaines étapes :</p>
    <ol style="color:#475569;font-size:14px;line-height:2;">
      <li>Complétez votre profil (profession, RPPS, adresse)</li>
      <li>Téléversez vos documents (diplôme, RCP, identité)</li>
      <li>Parcourez les missions disponibles près de chez vous</li>
    </ol>
    <div style="text-align:center;margin-top:24px;">
      <a href="https://soindirect.com/soignant/profil" style="background:#0e9aa7;color:#fff;padding:12px 32px;border-radius:12px;text-decoration:none;font-weight:600;display:inline-block;">Compléter mon profil →</a>
    </div>
  </div>
  ${FOOTER}`;
}

export function emailMissionAcceptee(prenom: string, mission: string, date: string, etablissement: string) {
  return `${HEADER}
  <div style="padding:32px 24px;">
    <h2 style="color:#1e293b;margin:0 0 16px;">Mission confirmée ✅</h2>
    <p style="color:#475569;font-size:14px;">Bonjour ${prenom},</p>
    <p style="color:#475569;font-size:14px;">Votre mission a été confirmée :</p>
    <div style="background:#f0fdfa;border:1px solid #99f6e4;border-radius:12px;padding:16px;margin:16px 0;">
      <p style="margin:0;font-weight:600;color:#1e293b;">${mission}</p>
      <p style="margin:4px 0 0;color:#475569;font-size:13px;">📍 ${etablissement}</p>
      <p style="margin:4px 0 0;color:#475569;font-size:13px;">📅 ${date}</p>
    </div>
    <p style="color:#475569;font-size:14px;">N'oubliez pas de pointer votre arrivée dans l'app le jour J !</p>
  </div>
  ${FOOTER}`;
}

export function emailFactureMensuelle(nomEtab: string, numero: string, montantTTC: string, lienPaiement: string) {
  return `${HEADER}
  <div style="padding:32px 24px;">
    <h2 style="color:#1e293b;margin:0 0 16px;">Facture ${numero}</h2>
    <p style="color:#475569;font-size:14px;">Bonjour,</p>
    <p style="color:#475569;font-size:14px;">Votre facture de commission Soin Direct est disponible :</p>
    <div style="background:#f8fafc;border:1px solid #e2e8f0;border-radius:12px;padding:16px;margin:16px 0;">
      <p style="margin:0;font-weight:600;color:#1e293b;">Facture ${numero}</p>
      <p style="margin:4px 0 0;color:#475569;font-size:13px;">Montant TTC : ${montantTTC} €</p>
      <p style="margin:4px 0 0;color:#475569;font-size:13px;">Échéance : 30 jours</p>
    </div>
    <div style="text-align:center;margin-top:24px;">
      <a href="${lienPaiement}" style="background:#0e9aa7;color:#fff;padding:12px 32px;border-radius:12px;text-decoration:none;font-weight:600;display:inline-block;">💳 Payer la facture →</a>
    </div>
  </div>
  ${FOOTER}`;
}

export function emailMissionRappel(prenom: string, mission: string, heure: string, etablissement: string) {
  return `${HEADER}
  <div style="padding:32px 24px;">
    <h2 style="color:#1e293b;margin:0 0 16px;">⏰ Rappel : mission demain</h2>
    <p style="color:#475569;font-size:14px;">Bonjour ${prenom},</p>
    <p style="color:#475569;font-size:14px;">Rappel : vous avez une mission demain :</p>
    <div style="background:#fffbeb;border:1px solid #fde68a;border-radius:12px;padding:16px;margin:16px 0;">
      <p style="margin:0;font-weight:600;color:#1e293b;">${mission}</p>
      <p style="margin:4px 0 0;color:#475569;font-size:13px;">📍 ${etablissement}</p>
      <p style="margin:4px 0 0;color:#475569;font-size:13px;">🕐 Début : ${heure}</p>
    </div>
  </div>
  ${FOOTER}`;
}

export function emailDocumentExpirant(prenom: string, typeDoc: string, dateExpiration: string) {
  return `${HEADER}
  <div style="padding:32px 24px;">
    <h2 style="color:#1e293b;margin:0 0 16px;">⚠️ Document bientôt expiré</h2>
    <p style="color:#475569;font-size:14px;">Bonjour ${prenom},</p>
    <p style="color:#475569;font-size:14px;">Votre <strong>${typeDoc}</strong> expire le <strong>${dateExpiration}</strong>.</p>
    <p style="color:#475569;font-size:14px;">Pensez à le renouveler et à téléverser la nouvelle version dans votre coffre-fort.</p>
    <div style="text-align:center;margin-top:24px;">
      <a href="https://soindirect.com/soignant/documents" style="background:#0e9aa7;color:#fff;padding:12px 32px;border-radius:12px;text-decoration:none;font-weight:600;display:inline-block;">Mettre à jour mes documents →</a>
    </div>
  </div>
  ${FOOTER}`;
}
