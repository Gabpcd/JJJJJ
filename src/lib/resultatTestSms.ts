export type ResultatTestSms = {
  etat: 'accepte' | 'non-envoye' | 'incertain';
  detail: string;
};

/** L'acceptation par Twilio n'est pas un accusé de réception sur le téléphone. */
export function resultatTestSms(reponse: unknown): ResultatTestSms {
  const data = reponse && typeof reponse === 'object'
    ? reponse as Record<string, unknown> : {};
  if (data.configured === false) {
    return { etat: 'non-envoye', detail: 'Le service SMS n’est pas configuré.' };
  }
  if (data.pending === true) {
    return { etat: 'incertain', detail: 'Le résultat de l’envoi reste à confirmer. Ne relancez pas le test immédiatement.' };
  }
  if (data.skipped === true) {
    return { etat: 'non-envoye', detail: 'Aucun SMS envoyé : le service a ignoré cette demande.' };
  }
  if (data.success === false) {
    return { etat: 'non-envoye', detail: typeof data.error === 'string' && data.error
      ? data.error : 'Le service SMS a refusé la demande.' };
  }
  if (data.success === true && typeof data.sid === 'string' && data.sid.trim()) {
    return { etat: 'accepte', detail: `Demande acceptée par le fournisseur · référence ${data.sid}. La réception sur le téléphone reste à confirmer.` };
  }
  return { etat: 'incertain', detail: 'Réponse du service non reconnue : aucun envoi confirmé.' };
}
