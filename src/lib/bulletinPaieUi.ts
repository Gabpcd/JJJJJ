export const MENTION_SIMULATION_PAIE =
  'Simulation de paie — document non officiel. Le prélèvement à la source n’est pas intégré ; seul le bulletin remis par l’employeur fait foi.';

export interface BulletinPaiePourTotal {
  statut?: string | null;
  salaire_brut?: number | string | null;
  net_avant_impot?: number | string | null;
  total_cotisations_salariales?: number | string | null;
}

export interface MontantsPaieComparables {
  statut?: string | null;
  salaire_brut?: number | string | null;
  net_avant_impot?: number | string | null;
}

export function simulationPaieIncoherente(
  bulletin: MontantsPaieComparables,
  cotisations: MontantsPaieComparables | undefined,
): boolean {
  // Un document annulé reste l'archive fidèle de l'ancien calcul. Il ne doit
  // pas être comparé au calcul courant, qui appartient au rectificatif actif.
  if (bulletin.statut === 'ANNULE' || !cotisations) return false;

  const brutBulletin = Number(bulletin.salaire_brut);
  const netBulletin = Number(bulletin.net_avant_impot);
  const brutCalcule = Number(cotisations.salaire_brut);
  const netCalcule = Number(cotisations.net_avant_impot);

  return (
    (Number.isFinite(brutCalcule) && Math.abs(brutCalcule - brutBulletin) > 0.01)
    || (Number.isFinite(netCalcule) && Math.abs(netCalcule - netBulletin) > 0.01)
  );
}

export function totauxBulletinsPayes(bulletins: BulletinPaiePourTotal[]) {
  return bulletins.reduce((totaux, bulletin) => {
    if (bulletin.statut !== 'PAYE') return totaux;
    totaux.brut += Number(bulletin.salaire_brut) || 0;
    totaux.netAvantImpot += Number(bulletin.net_avant_impot) || 0;
    totaux.cotisations += Number(bulletin.total_cotisations_salariales) || 0;
    return totaux;
  }, { brut: 0, netAvantImpot: 0, cotisations: 0 });
}
