export const STATUTS_EXTERNALISATION = [
  'PENDING',
  'PROCESSING',
  'DONE',
  'ERROR',
  'PENDING_AIFE',
  'CANCELLED',
  'TOUS',
] as const;

export type StatutExternalisation = (typeof STATUTS_EXTERNALISATION)[number];

const LIBELLES_STATUT: Record<StatutExternalisation, string> = {
  PENDING: 'En attente',
  PROCESSING: 'En cours',
  DONE: 'Terminée',
  ERROR: 'En échec',
  PENDING_AIFE: 'En attente AIFE',
  CANCELLED: 'Annulée',
  TOUS: 'Tous les statuts',
};

const LIBELLES_TYPE_ACTION: Record<string, string> = {
  TOUS: 'Tous les types',
  STRIPE_REFUND_TOTAL: 'Remboursement Stripe total',
  STRIPE_REFUND_PARTIEL: 'Remboursement Stripe partiel',
  STRIPE_PAYMENT: 'Paiement Stripe',
  CHORUS_RECYCLER_FACTURE: 'Recyclage de facture Chorus Pro',
  DPAE_ANNULATION: 'Annulation DPAE',
  EMAIL_NOTIF: 'Notification par e-mail',
  PUSH_NOTIF: 'Notification push',
  AVOIR_PDF_GENERATION: 'Génération d’un avoir PDF',
};

export function libelleStatutExternalisation(statut: StatutExternalisation): string {
  return LIBELLES_STATUT[statut];
}

export function libelleTypeExternalisation(type: string): string {
  return LIBELLES_TYPE_ACTION[type] ?? type.split('_').join(' ').toLowerCase();
}
