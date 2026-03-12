const WRAPPER = (content: string) => `
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width"></head>
<body style="margin:0;padding:0;background:#F8FAFC;font-family:Arial,sans-serif;">
  <div style="max-width:600px;margin:0 auto;background:white;">
    <div style="background:#0F172A;padding:24px;text-align:center;">
      <span style="color:#17A2B8;font-size:28px;font-weight:bold;">❤️ Soin Direct</span>
    </div>
    <div style="padding:32px 24px;">
      ${content}
    </div>
    <div style="background:#F1F5F9;padding:16px 24px;text-align:center;font-size:11px;color:#94A3B8;">
      <p>Soin Direct SAS — <a href="https://soindirect.com" style="color:#17A2B8;">soindirect.com</a></p>
      <p><a href="https://soindirect.com/cgu" style="color:#94A3B8;">CGU</a> · 
         <a href="https://soindirect.com/confidentialite" style="color:#94A3B8;">Confidentialité</a></p>
    </div>
  </div>
</body>
</html>`;

const BUTTON = (text: string, url: string) =>
  `<a href="${url}" style="display:inline-block;background:#17A2B8;color:white;padding:14px 28px;border-radius:8px;text-decoration:none;font-weight:bold;margin:16px 0;">${text}</a>`;

export function emailBienvenueSoignant(prenom: string) {
  return WRAPPER(`
    <h2 style="color:#0F172A;">Bienvenue ${prenom} ! 🎉</h2>
    <p>Votre compte soignant est créé. Prochaines étapes :</p>
    <div style="background:#F0FDFA;border-left:4px solid #17A2B8;padding:16px;margin:16px 0;">
      <strong>1.</strong> Complétez votre profil (RPPS, adresse)<br/>
      <strong>2.</strong> Téléversez vos documents (diplôme, RCP, identité)<br/>
      <strong>3.</strong> Parcourez les missions près de chez vous
    </div>
    ${BUTTON('Compléter mon profil →', 'https://soindirect.com/soignant/profil')}
  `);
}

export function emailBienvenueEtablissement(nom: string) {
  return WRAPPER(`
    <h2 style="color:#0F172A;">Bienvenue ${nom} !</h2>
    <p>Votre établissement est enregistré sur Soin Direct.</p>
    <div style="background:#F0FDFA;border-left:4px solid #17A2B8;padding:16px;margin:16px 0;">
      <strong>1.</strong> Complétez votre profil (SIRET, FINESS, adresse)<br/>
      <strong>2.</strong> Publiez votre première mission<br/>
      <strong>3.</strong> Recevez des candidatures en quelques heures
    </div>
    ${BUTTON('Publier une mission →', 'https://soindirect.com/etablissement/missions/creer')}
  `);
}

export function emailMissionAcceptee(prenom: string, mission: string, date: string, etab: string) {
  return WRAPPER(`
    <h2 style="color:#0F172A;">Mission confirmée ✅</h2>
    <p>Bonjour ${prenom},</p>
    <div style="background:#F0FDFA;border:1px solid #17A2B8;border-radius:8px;padding:16px;margin:16px 0;">
      <strong>${mission}</strong><br/>
      📍 ${etab}<br/>
      📅 ${date}
    </div>
    <p>⚠️ Pensez à <strong>signer votre contrat</strong> dans l'app avant le début de la mission.</p>
    ${BUTTON('Voir la mission →', 'https://soindirect.com/soignant/missions')}
  `);
}

export function emailContratASignerSoignant(prenom: string, mission: string, contratId: string) {
  return WRAPPER(`
    <h2 style="color:#0F172A;">📝 Contrat à signer</h2>
    <p>Bonjour ${prenom},</p>
    <p>Un contrat a été généré pour votre mission <strong>"${mission}"</strong>.</p>
    <p>Vous devez le signer avant de pouvoir commencer votre mission.</p>
    ${BUTTON('Signer le contrat →', 'https://soindirect.com/contrat/' + contratId)}
    <p style="font-size:12px;color:#94A3B8;">Pour des raisons de sécurité, le contrat n'est pas en pièce jointe. Connectez-vous à l'app pour le consulter et le signer.</p>
  `);
}

export function emailContratASignerEtablissement(nomEtab: string, soignant: string, contratId: string) {
  return WRAPPER(`
    <h2 style="color:#0F172A;">📝 Contrat à signer</h2>
    <p>Bonjour,</p>
    <p><strong>${soignant}</strong> a accepté votre mission. Un contrat a été généré.</p>
    <p>Signez-le pour confirmer la collaboration.</p>
    ${BUTTON('Signer le contrat →', 'https://soindirect.com/contrat/' + contratId)}
  `);
}

export function emailFactureMensuelle(nomEtab: string, numero: string, ttc: string, factureId: string) {
  return WRAPPER(`
    <h2 style="color:#0F172A;">Facture ${numero}</h2>
    <p>Bonjour,</p>
    <div style="background:#F0FDFA;border:1px solid #17A2B8;border-radius:8px;padding:16px;margin:16px 0;">
      <strong>Facture ${numero}</strong><br/>
      Montant TTC : <strong>${ttc} €</strong><br/>
      Échéance : 30 jours
    </div>
    ${BUTTON('💳 Consulter et payer →', 'https://soindirect.com/etablissement/facturation/' + factureId)}
    <p style="font-size:12px;color:#94A3B8;">Pour des raisons de sécurité, la facture n'est pas en pièce jointe. Consultez-la dans votre espace.</p>
  `);
}

export function emailRappelMission(prenom: string, mission: string, heure: string, etab: string) {
  return WRAPPER(`
    <h2 style="color:#F59E0B;">⏰ Rappel : mission demain</h2>
    <p>Bonjour ${prenom},</p>
    <div style="background:#FEF3C7;border:1px solid #F59E0B;border-radius:8px;padding:16px;margin:16px 0;">
      <strong>${mission}</strong><br/>
      📍 ${etab}<br/>
      🕐 ${heure}
    </div>
    <p>N'oubliez pas votre pointage d'arrivée dans l'app !</p>
  `);
}

export function emailDocumentExpirant(prenom: string, typeDoc: string, dateExp: string) {
  return WRAPPER(`
    <h2 style="color:#F59E0B;">⚠️ Document bientôt expiré</h2>
    <p>Bonjour ${prenom},</p>
    <p>Votre <strong>${typeDoc}</strong> expire le <strong>${dateExp}</strong>.</p>
    ${BUTTON('Mettre à jour →', 'https://soindirect.com/soignant/documents')}
  `);
}
