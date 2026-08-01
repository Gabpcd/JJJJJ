export const MENTION_SIMULATION_PAIE =
  'Simulation de paie — document non officiel. Le prélèvement à la source n’est pas intégré ; seul le bulletin remis par l’employeur fait foi.';

export interface BulletinPaiePourTotal {
  statut?: string | null;
  salaire_brut?: number | string | null;
  net_avant_impot?: number | string | null;
  total_cotisations_salariales?: number | string | null;
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
