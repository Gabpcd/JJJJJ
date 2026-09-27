/** Transport des lots immuables préparés par fn_evaluer_alertes_filtres.
 * Aucun aperçu recalculé depuis 1970 : une reprise conserve la même fenêtre,
 * le même contenu et la même identité que la première tentative.
 */
export const TYPES_ALERTES_FILTRES = ['NOUVELLES_MISSIONS_FILTRE', 'NOUVEAUX_SOIGNANTS_FILTRE'];

/** Distingue un acquittement idempotent d'un refus de préférence/test. */
export function resultatEnvoiEmail(data: { success?: unknown; pending?: unknown; skipped?: unknown; reason?: unknown } | null): 'sent' | 'skipped' | 'pending' {
  if (data?.success !== true) throw new Error('Réponse envoi email invalide');
  if (data.pending === true) return 'pending';
  if (data.skipped === true) return data.reason === 'idempotency_already_sent' ? 'sent' : 'skipped';
  return 'sent';
}

interface EmailAlerte {
  id: string;
  type: string;
  destinataire_id: string | null;
  destinataire_email?: string | null;
  data: Record<string, unknown>;
}
export async function traiterAlerteFiltres(
  sb: any,
  email: EmailAlerte,
  envoyer: (body: Record<string, unknown>) => Promise<'sent' | 'skipped' | 'pending'>,
): Promise<'envoye' | 'annule' | 'pending' | 'erreur'> {
  const { data: valide, error: validationError } = await sb.rpc('fn_verifier_livraison_alerte_filtre', { p_email_id: email.id });
  // Une panne de validation ne doit ni envoyer ni annuler une livraison.
  if (validationError || typeof valide !== 'boolean') throw new Error('Validation de la livraison indisponible');
  if (!valide) {
    const { data, error } = await sb.from('email_queue').update({ statut: 'ANNULE', erreur: 'Recherche désactivée, modifiée ou résultat indisponible' })
      .eq('id', email.id).eq('statut', 'EN_ATTENTE').select('id').maybeSingle();
    if (error || !data) throw new Error('Annulation de la livraison non enregistrée');
    return 'annule';
  }
  let outcome: 'sent' | 'skipped' | 'pending';
  try {
    outcome = await envoyer({ type: email.type, destinataire_id: email.destinataire_id,
      destinataire_email: email.destinataire_email, data: email.data });
  } catch (error) {
    const { error: markError } = await sb.from('email_queue').update({ statut: 'ERREUR', erreur: error instanceof Error ? error.message : 'Erreur envoi' })
      .eq('id', email.id).eq('statut', 'EN_ATTENTE');
    if (markError) throw new Error('Erreur transport et marquage impossibles');
    const { error: retryError } = await sb.rpc('fn_reporter_echec_alerte_filtre', { p_email_id: email.id });
    if (retryError) throw new Error('Reprise de la livraison non planifiée');
    return 'erreur';
  }
  if (outcome === 'pending') return 'pending';
  if (outcome === 'skipped') {
    const { data, error } = await sb.from('email_queue').update({ statut: 'ANNULE', envoye: false, envoye_le: null, erreur: 'Envoi ignoré par les préférences ou les garde-fous du transport' })
      .eq('id', email.id).eq('statut', 'EN_ATTENTE').select('id').maybeSingle();
    if (error || !data) throw new Error('Envoi ignoré ; état de la file à reprendre');
    return 'annule';
  }
  const { data, error } = await sb.from('email_queue').update({ statut: 'ENVOYE', envoye: true, envoye_le: new Date().toISOString(), erreur: null })
    .eq('id', email.id).eq('statut', 'EN_ATTENTE').select('id').maybeSingle();
  // Si le marquage échoue après transport, garder EN_ATTENTE. La même clé sera
  // rejouée et send-email ne délivrera pas une deuxième fois.
  if (error || !data) throw new Error('Envoi confirmé ; marquage à reprendre avec la même identité');
  return 'envoye';
}
