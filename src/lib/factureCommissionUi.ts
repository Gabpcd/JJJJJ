export type FactureCommissionTotaux = {
  montant_ht?: number | null;
  montant_tva?: number | null;
  montant_ttc?: number | null;
};

export type LigneMissionCommission = {
  montant_commission_ht?: number | null;
  montant_commission_tva?: number | null;
  montant_commission_ttc?: number | null;
  [cle: string]: unknown;
};

const enCentimes = (montant: unknown) => Math.round(Number(montant ?? 0) * 100);

/**
 * La facture émise est le document comptable faisant foi. Si une mission a été
 * recalculée ensuite, sa valeur courante ne doit jamais remplacer les montants
 * figés du document dans l'interface.
 */
export function normaliserLignesFactureCommission<T extends LigneMissionCommission>(
  missions: T[],
  facture: FactureCommissionTotaux,
): Array<T & {
  montant_commission_ht: number;
  montant_commission_tva: number;
  montant_commission_ttc: number;
  ecart_avec_mission_courante: boolean;
}> {
  if (missions.length === 0) return [];

  const totalHt = enCentimes(facture.montant_ht);
  const totalTva = enCentimes(facture.montant_tva);
  const poids = missions.map((mission) => Math.max(0, enCentimes(mission.montant_commission_ht)));
  const sommePoids = poids.reduce((somme, montant) => somme + montant, 0);

  let htDistribue = 0;
  let tvaDistribuee = 0;
  return missions.map((mission, index) => {
    const dernier = index === missions.length - 1;
    const ratio = sommePoids > 0 ? poids[index] / sommePoids : 1 / missions.length;
    const ht = dernier ? totalHt - htDistribue : Math.round(totalHt * ratio);
    const tva = dernier ? totalTva - tvaDistribuee : Math.round(totalTva * ratio);
    htDistribue += ht;
    tvaDistribuee += tva;

    const htCourant = enCentimes(mission.montant_commission_ht);
    const tvaCourante = enCentimes(mission.montant_commission_tva);
    const ttcCourant = enCentimes(mission.montant_commission_ttc);
    return {
      ...mission,
      montant_commission_ht: ht / 100,
      montant_commission_tva: tva / 100,
      montant_commission_ttc: (ht + tva) / 100,
      ecart_avec_mission_courante:
        htCourant !== ht || tvaCourante !== tva || ttcCourant !== ht + tva,
    };
  });
}
