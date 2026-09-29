export interface PaiementSoignantPourUi {
  id: string;
  mission_id?: string | null;
  date_paiement?: string | null;
  modifie_le?: string | null;
  cree_le?: string | null;
}

export interface RepartitionPaiementConfirme {
  montantPaye: number;
  montantRestant: number;
  estPartiel: boolean;
}

/**
 * Répartit un règlement confirmé sans faire disparaître un reste à payer.
 * Un paiement partiel doit être visible à la fois dans « Payé » pour la somme
 * réellement reçue et dans « En attente » pour le solde encore dû.
 */
export function repartirPaiementConfirme(
  montantDuBrut: unknown,
  montantRegleBrut: unknown,
): RepartitionPaiementConfirme {
  const montantDu = Number(montantDuBrut);
  const montantRegle = Number(montantRegleBrut);
  const du = Number.isFinite(montantDu) ? Math.max(0, montantDu) : 0;
  const paye = Number.isFinite(montantRegle) ? Math.max(0, montantRegle) : 0;
  const restant = Math.max(0, Number((du - paye).toFixed(2)));

  return {
    montantPaye: Number(paye.toFixed(2)),
    montantRestant: restant,
    estPartiel: paye > 0 && restant > 0,
  };
}

function instantPaiement(paiement: PaiementSoignantPourUi): number {
  const valeur = paiement.modifie_le ?? paiement.cree_le ?? paiement.date_paiement;
  const instant = valeur ? new Date(valeur).getTime() : 0;
  return Number.isFinite(instant) ? instant : 0;
}

/**
 * Indexe explicitement le dernier état de paiement de chaque mission. L'ordre
 * de retour de PostgREST n'est jamais utilisé implicitement.
 */
export function indexerDernierPaiementParMission<T extends PaiementSoignantPourUi>(
  paiements: T[],
): Record<string, T> {
  const resultat: Record<string, T> = {};
  paiements.forEach((paiement) => {
    const missionId = paiement.mission_id;
    if (!missionId) return;
    const courant = resultat[missionId];
    if (
      !courant
      || instantPaiement(paiement) > instantPaiement(courant)
      || (instantPaiement(paiement) === instantPaiement(courant) && paiement.id.localeCompare(courant.id) > 0)
    ) {
      resultat[missionId] = paiement;
    }
  });
  return resultat;
}

export interface PaiementSalairePourUi {
  statut?: string | null;
  montant_net?: unknown;
  confirme_par_soignant?: boolean | null;
  conteste?: boolean | null;
  montant_du_reference?: unknown;
  source_montant_du?: string | null;
}

export interface EtatPaiementSalaire {
  etat: 'absent' | 'declare' | 'confirme' | 'conteste' | 'resolu' | 'a_verifier';
  libelle: string;
  montantDeclare: number | null;
  montantReferenceEmployeur: number | null;
}

function montantPositifFini(valeur: unknown): number | null {
  if (typeof valeur !== 'number' && typeof valeur !== 'string') return null;
  if (typeof valeur === 'string' && valeur.trim() === '') return null;
  const montant = Number(valeur);
  return Number.isFinite(montant) && montant > 0 ? montant : null;
}

/**
 * État de la dernière déclaration par mission, jamais un total de virements.
 * Une résolution de litige ne vaut pas réception ; la contestation prime sur
 * une ancienne confirmation. Aucun montant ni solde n'est déduit d'une estimation.
 */
export function classerPaiementSalaire(paiement?: PaiementSalairePourUi | null): EtatPaiementSalaire {
  const montants = {
    montantDeclare: montantPositifFini(paiement?.montant_net),
    // Cette source est déclarée par l'employeur : ce n'est pas une vérification
    // du bulletin. Les anciennes références estimées ne constituent pas un dû.
    montantReferenceEmployeur: paiement?.source_montant_du === 'BULLETIN_OFFICIEL_ETABLISSEMENT'
      ? montantPositifFini(paiement.montant_du_reference)
      : null,
  };
  if (!paiement) return { ...montants, etat: 'absent', libelle: 'Aucun versement déclaré' };
  if (paiement.conteste === true || paiement.statut === 'CONTESTE') {
    return { ...montants, etat: 'conteste', libelle: 'Paiement contesté' };
  }
  if (paiement.statut === 'RESOLU') {
    return { ...montants, etat: 'resolu', libelle: 'Litige résolu · réception à vérifier' };
  }
  if (paiement.statut === 'CONFIRME' && paiement.confirme_par_soignant === true && montants.montantDeclare !== null) {
    return { ...montants, etat: 'confirme', libelle: 'Réception confirmée' };
  }
  if (paiement.statut === 'DECLARE') return { ...montants, etat: 'declare', libelle: 'Réception à confirmer' };
  return { ...montants, etat: 'a_verifier', libelle: 'Réception à vérifier' };
}
