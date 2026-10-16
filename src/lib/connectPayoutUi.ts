export interface ConnectPayoutRow {
  id: string;
  mission_id: string;
  statut: 'CHARGE_REUSSI' | 'TRANSFERE' | 'PAYE';
  montant_soignant: number;
  stripe_payout_id: string | null;
  standard_payout_state: 'WAITING' | 'SUBMITTED' | 'PAID' | 'FAILED' | 'REVIEW' | null;
  paye_le: string | null;
}

export function lireVersementsConnect(value: unknown): ConnectPayoutRow[] {
  if (!Array.isArray(value) || value.length > 20) throw new Error('Versements indisponibles');
  if (new Set(value.map(row => row?.id)).size !== value.length) throw new Error('Versements indisponibles');
  return value.map(row => {
    const amount = typeof row?.montant_soignant === 'number' || typeof row?.montant_soignant === 'string'
      ? Number(row.montant_soignant) : NaN;
    const payoutState = row && !Object.prototype.hasOwnProperty.call(row, 'standard_payout_state')
      ? 'REVIEW' : row?.standard_payout_state;
    if (!row || typeof row.id !== 'string' || !row.id || typeof row.mission_id !== 'string' || !row.mission_id
      || !['CHARGE_REUSSI', 'TRANSFERE', 'PAYE'].includes(row.statut)
      || !Number.isFinite(amount) || amount <= 0
      || (row.stripe_payout_id !== null && (typeof row.stripe_payout_id !== 'string' || !/^po_[A-Za-z0-9]+$/.test(row.stripe_payout_id)))
      || ![null, 'WAITING', 'SUBMITTED', 'PAID', 'FAILED', 'REVIEW'].includes(payoutState)
      || (row.paye_le !== null && (typeof row.paye_le !== 'string' || !Number.isFinite(Date.parse(row.paye_le))))) {
      throw new Error('Versements indisponibles');
    }
    return { id: row.id, mission_id: row.mission_id, statut: row.statut, montant_soignant: amount,
      stripe_payout_id: row.stripe_payout_id, standard_payout_state: payoutState, paye_le: row.paye_le };
  });
}

export function etatVersementConnect(row: ConnectPayoutRow) {
  const review = { label: 'Versement bancaire à vérifier', detail: 'Le règlement de l’établissement est enregistré. Le versement bancaire nécessite une vérification.', paid: false };
  if (row.statut === 'PAYE' && row.standard_payout_state === 'PAID' && row.stripe_payout_id && row.paye_le) {
    return { label: 'Versement bancaire confirmé', detail: 'Stripe a confirmé le versement vers le compte bancaire.', paid: true };
  }
  if (row.statut === 'PAYE' || row.standard_payout_state === 'PAID') return review;
  if (row.statut === 'CHARGE_REUSSI') {
    return { label: 'Paiement acquis par Stripe', detail: 'Le transfert vers le solde Stripe du soignant est en cours. Aucun versement bancaire n’est encore confirmé.', paid: false };
  }
  if (row.standard_payout_state === 'REVIEW') return review;
  if (row.standard_payout_state === 'FAILED') {
    return { label: 'Versement bancaire échoué', detail: 'Le règlement de l’établissement reste enregistré. L’échec bancaire nécessite un suivi.', paid: false };
  }
  if (row.standard_payout_state === 'SUBMITTED') {
    return row.stripe_payout_id
      ? { label: 'Versement bancaire en cours', detail: 'Le virement a été demandé à Stripe. Son arrivée en banque n’est pas encore confirmée.', paid: false }
      : review;
  }
  return { label: 'Transféré sur Stripe', detail: 'Les honoraires ont été transférés vers le solde Stripe. Le versement bancaire n’est pas encore confirmé.', paid: false };
}
