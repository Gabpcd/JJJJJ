/** Factures : reçu transactionnel, réservation serveur, reprises bornées. */
export async function traiterEmailFacturation(
  sb: any, emailId: string,
  envoyer: (corps: Record<string, unknown>, cle: string) => Promise<'sent' | 'skipped' | 'pending'>,
): Promise<'envoye' | 'annule' | 'pending' | 'erreur'> {
  const { data: livraison, error } = await sb.rpc('fn_reserver_email_facturation', { p_email_id: emailId });
  if (error || !livraison?.statut) throw new Error('Réservation email facture indisponible');
  if (livraison.statut === 'DEJA_ENVOYE') return 'envoye';
  if (livraison.statut === 'ANNULE' || livraison.statut === 'ABSENT') return 'annule';
  if (livraison.statut === 'ATTENDRE') return 'pending';
  if (livraison.statut === 'ERREUR') return 'erreur';
  if (livraison.statut !== 'RESERVE' || !livraison.reservation || !livraison.corps || !livraison.idempotency_key) {
    throw new Error('Contrat email facture invalide');
  }
  let resultat: 'ENVOYE' | 'ANNULE' | 'ERREUR';
  let erreur: string | null = null;
  try {
    const outcome = await envoyer(livraison.corps, livraison.idempotency_key);
    resultat = outcome === 'sent' ? 'ENVOYE' : outcome === 'skipped' ? 'ANNULE' : 'ERREUR';
    if (outcome === 'pending') erreur = 'Résultat transport indéterminé ; reprise avec la même identité';
  } catch (cause) {
    resultat = 'ERREUR';
    erreur = cause instanceof Error ? cause.message : 'Échec transport facture';
  }
  const { error: acquittement } = await sb.rpc('fn_acquitter_email_facturation', {
    p_email_id: emailId, p_reservation: livraison.reservation, p_resultat: resultat, p_erreur: erreur,
  });
  if (acquittement) throw new Error('Acquittement facture non confirmé ; reprise avec la même identité');
  return resultat === 'ENVOYE' ? 'envoye' : resultat === 'ANNULE' ? 'annule' : 'erreur';
}
