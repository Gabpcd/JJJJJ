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
