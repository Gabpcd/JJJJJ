import { supabase } from '@/integrations/supabase/client';

export const ETATS_REMBOURSEMENT_CONNECT = ['READY', 'PENDING', 'REQUIRES_ACTION', 'SUCCEEDED', 'FAILED', 'CANCELED', 'REVIEW'] as const;
export type EtatRemboursementConnect = typeof ETATS_REMBOURSEMENT_CONNECT[number];
export type OperationRemboursementConnect = {
  id: string;
  checkout_session_id: string;
  statut: EtatRemboursementConnect;
  montant_honoraires_centimes: number;
  montant_commission_centimes: number | null;
  montant_total_centimes: number | null;
  cree_le: string;
  mis_a_jour_le: string | null;
  succeeded_at: string | null;
  review_code: string | null;
};
export type SuiviRemboursementConnect = {
  facture_honoraire_id: string;
  mission_id: string;
  checkout_session_id_filtre: string | null;
  source: 'CONNECT_AVANT_TRANSFERT';
  visibilite_montants: 'HONORAIRES' | 'TOTAL_ETABLISSEMENT';
  paiement_statut: string | null;
  operations: OperationRemboursementConnect[];
  lecture_complete: true;
};

const estObjet = (v: unknown): v is Record<string, unknown> => Boolean(v) && typeof v === 'object' && !Array.isArray(v);
const texte = (v: unknown): v is string => typeof v === 'string' && v.trim().length > 0;
const date = (v: unknown) => texte(v) && Number.isFinite(Date.parse(v));
const centimes = (v: unknown): v is number => typeof v === 'number' && Number.isSafeInteger(v) && v >= 0;
export const estSessionCheckout = (v: unknown): v is string => typeof v === 'string' && /^cs_[A-Za-z0-9_]+$/.test(v) && v.length <= 255;

export function validerSuiviRemboursementConnect(
  value: unknown,
  factureId: string,
  checkoutSessionId?: string,
): SuiviRemboursementConnect {
  const incoherent = () => { throw new Error('Le suivi du remboursement est incomplet ou incohérent.'); };
  if (!estObjet(value) || value.facture_honoraire_id !== factureId || !texte(value.mission_id)
    || value.checkout_session_id_filtre !== (checkoutSessionId ?? null)
    || value.source !== 'CONNECT_AVANT_TRANSFERT' || value.lecture_complete !== true
    || !['HONORAIRES', 'TOTAL_ETABLISSEMENT'].includes(String(value.visibilite_montants))
    || !(value.paiement_statut === null || texte(value.paiement_statut))
    || (!checkoutSessionId && value.paiement_statut !== null)
    || !Array.isArray(value.operations)) return incoherent();
  const ids = new Set<string>();
  const sessions = new Set<string>();
  for (const op of value.operations) {
    if (!estObjet(op) || !texte(op.id) || ids.has(op.id)
      || !estSessionCheckout(op.checkout_session_id) || sessions.has(op.checkout_session_id)
      || (checkoutSessionId && op.checkout_session_id !== checkoutSessionId)
      || !ETATS_REMBOURSEMENT_CONNECT.includes(op.statut as EtatRemboursementConnect)
      || !centimes(op.montant_honoraires_centimes)
      || !date(op.cree_le) || !(op.mis_a_jour_le === null || date(op.mis_a_jour_le))
      || !(op.succeeded_at === null || date(op.succeeded_at))
      || !(op.review_code === null || texte(op.review_code))
      || (op.statut === 'SUCCEEDED' && (!date(op.succeeded_at) || op.review_code !== null))) return incoherent();
    if (value.visibilite_montants === 'HONORAIRES') {
      if (op.montant_commission_centimes !== null || op.montant_total_centimes !== null) return incoherent();
    } else if (!centimes(op.montant_commission_centimes) || !centimes(op.montant_total_centimes)
      || op.montant_total_centimes <= 0
      || op.montant_honoraires_centimes + op.montant_commission_centimes !== op.montant_total_centimes) return incoherent();
    ids.add(op.id);
    sessions.add(op.checkout_session_id);
  }
  return value as SuiviRemboursementConnect;
}

export async function lireSuiviRemboursementConnect(factureId: string, checkoutSessionId?: string, signal?: AbortSignal) {
  if (!texte(factureId) || (checkoutSessionId !== undefined && !estSessionCheckout(checkoutSessionId))) {
    throw new Error('La référence de paiement ne peut pas être vérifiée.');
  }
  let query = supabase.rpc('fn_suivi_remboursements_connect_facture' as any, {
    p_facture_honoraire_id: factureId,
    p_checkout_session_id: checkoutSessionId ?? null,
  });
  if (signal) query = query.abortSignal(signal);
  const { data, error } = await query;
  if (error) throw error;
  if (signal?.aborted) throw new Error('Lecture annulée');
  return validerSuiviRemboursementConnect(data, factureId, checkoutSessionId);
}

export function presentationRemboursementConnect(op: OperationRemboursementConnect) {
  switch (op.statut) {
    case 'READY': return { titre: 'Remboursement en préparation', ton: 'attente', detail: 'Le résultat du remboursement n’est pas encore confirmé.' } as const;
    case 'PENDING': return { titre: 'Remboursement en cours', ton: 'attente', detail: 'La demande a été transmise. Le remboursement n’est pas encore confirmé.' } as const;
    case 'REQUIRES_ACTION': return { titre: 'Remboursement à vérifier', ton: 'incident', detail: 'Une action complémentaire est nécessaire. Jolene doit vérifier le traitement.' } as const;
    case 'SUCCEEDED': return { titre: 'Remboursement confirmé', ton: 'succes', detail: 'Stripe confirme le remboursement du paiement de l’établissement. Son apparition sur le compte dépend de la banque.' } as const;
    case 'FAILED': return { titre: 'Remboursement échoué', ton: 'incident', detail: 'Le remboursement n’a pas abouti. Le paiement initial ne doit pas être considéré comme annulé.' } as const;
    case 'CANCELED': return { titre: 'Remboursement annulé', ton: 'incident', detail: 'La demande de remboursement a été annulée. Cela ne signifie pas que le paiement initial a été annulé.' } as const;
    case 'REVIEW': return { titre: 'Vérification nécessaire', ton: 'incident', detail: op.succeeded_at
      ? 'Un incident a été signalé après une confirmation du remboursement. Jolene doit vérifier sa situation.'
      : 'Le résultat du remboursement nécessite une vérification. Il n’est pas présenté comme confirmé.' } as const;
  }
}

export function etatRetourConnect(suivi: SuiviRemboursementConnect): 'REMBOURSEMENT' | 'CONFIRME' | 'A_VERIFIER' | 'EN_ATTENTE' {
  if (!suivi.checkout_session_id_filtre) return 'A_VERIFIER';
  // Le statut courant de l’opération prime sur un paiement historique et sur
  // une ancienne date de remboursement réussi (retour bancaire tardif).
  if (suivi.operations.length > 0) return 'REMBOURSEMENT';
  if (['CHARGE_REUSSI', 'TRANSFERE', 'PAYE'].includes(suivi.paiement_statut ?? '')) return 'CONFIRME';
  if (['EN_ATTENTE', null].includes(suivi.paiement_statut)) return 'EN_ATTENTE';
  return 'A_VERIFIER';
}
