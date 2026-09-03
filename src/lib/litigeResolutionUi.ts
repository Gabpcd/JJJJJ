export type AccordReference = {
  type: string;
  modifications: Record<string, string | number | boolean | null>;
  justification: string;
} | null | undefined;

export const LABELS_TYPE_ACCORD: Record<string, string> = {
  MODIFICATION_HORAIRES: 'Correction des horaires',
  MODIFICATION_MONTANT: 'Ajustement du montant total',
  MIXTE: 'Correction des horaires et du montant',
  ANNULATION_TOTALE: 'Annulation totale',
  COMPENSATION_PARTIELLE: 'Compensation partielle',
};

export const TYPES_ACCORD_VALIDATION_DEDIEE = new Set([
  'ANNULATION_TOTALE',
  'COMPENSATION_PARTIELLE',
]);

export function decrireAccordAccepte(accord: AccordReference): string[] {
  if (!accord) return [];
  const modifications = accord.modifications ?? {};
  const type = LABELS_TYPE_ACCORD[accord.type] ?? accord.type;

  switch (accord.type) {
    case 'COMPENSATION_PARTIELLE':
      return [
        `Accord accepté : compensation de ${modifications.pourcentage_compensation ?? '—'} % à appliquer à la mission et à ses documents financiers.`,
      ];
    case 'ANNULATION_TOTALE':
      return [
        `Accord accepté : annulation totale de la mission${typeof modifications.motif_annulation === 'string' ? ` — ${modifications.motif_annulation}` : ''}.`,
      ];
    case 'MODIFICATION_MONTANT':
      return [
        `Accord accepté : montant final convenu à ${modifications.montant_total_corrige ?? '—'} € TTC.`,
      ];
    case 'MODIFICATION_HORAIRES':
      return ['Accord accepté : horaires convenus à appliquer au pointage, puis aux calculs financiers associés.'];
    case 'MIXTE':
      return [
        `Accord accepté : horaires convenus et montant final de ${modifications.montant_total_corrige ?? '—'} € TTC à appliquer.`,
      ];
    default:
      return [`Accord accepté : ${type}.`];
  }
}

export function enrichirMissionsLitigeAvecEtablissements<
  T extends { id: string; etablissement_id?: string | null; etablissements?: { nom?: string | null } | null },
>(
  missions: T[],
  etablissements: Record<string, { nom?: string | null }>,
  missionIdsDejaEnLitige: Set<string>,
): T[] {
  return missions
    .filter((mission) => !missionIdsDejaEnLitige.has(mission.id))
    .map((mission) => ({
      ...mission,
      etablissements: (mission.etablissement_id && etablissements[mission.etablissement_id])
        || mission.etablissements
        || null,
    }));
}

export function tauxContractuelMission(litige: {
  mission?: {
    taux_horaire_base_fige?: number | null;
    taux_horaire_base?: number | null;
  } | null;
} | null | undefined): number | null {
  const taux = Number(
    litige?.mission?.taux_horaire_base_fige
      ?? litige?.mission?.taux_horaire_base,
  );
  return Number.isFinite(taux) && taux > 0 ? taux : null;
}

export function tauxEffectifCalculMission(litige: {
  mission?: {
    rist_plafond_applique?: boolean | null;
    taux_rist_plafonne?: number | null;
    taux_horaire_base_fige?: number | null;
    taux_horaire_base?: number | null;
  } | null;
} | null | undefined): number | null {
  const tauxPlafonne = Number(litige?.mission?.taux_rist_plafonne);
  if (
    litige?.mission?.rist_plafond_applique === true
    && Number.isFinite(tauxPlafonne)
    && tauxPlafonne > 0
  ) {
    return tauxPlafonne;
  }
  return tauxContractuelMission(litige);
}

export function formatHeuresArbitrage(heures: number): string {
  const valeur = new Intl.NumberFormat('fr-FR', { maximumFractionDigits: 2 }).format(heures);
  if (heures >= 1 && Number.isInteger(heures)) return `${valeur} h`;
  return `${valeur} h (≈ ${Math.round(heures * 60)} min)`;
}

export function heuresContractuellesMission(litige: {
  mission?: { duree_heures?: number | null } | null;
} | null | undefined): number | null {
  const heures = Number(litige?.mission?.duree_heures);
  return Number.isFinite(heures) && heures > 0 ? heures : null;
}

export function estMissionSalariee(litige: {
  mission?: { type_contrat_applique?: string | null } | null;
} | null | undefined): boolean {
  return litige?.mission?.type_contrat_applique === 'SALARIE';
}
