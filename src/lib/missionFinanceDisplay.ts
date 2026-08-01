export interface MissionFinanceAffichee {
  profession_requise?: string | null;
  type_contrat_recherche?: string | null;
  type_contrat_applique?: string | null;
  soignant_assigne_id?: string | null;
  taux_horaire_base?: number | null;
  taux_rist_plafonne?: number | null;
  rist_plafond_applique?: boolean | null;
  net_estime?: number | null;
  net_a_payer?: number | null;
  total_brut?: number | null;
}

export type NatureMontantMissionAffiche =
  | 'HONORAIRES_LIBERAUX'
  | 'NET_SALARIE_ESTIME'
  | 'BRUT_INDICATIF';

export interface MontantMissionAffiche {
  montant: number;
  nature: NatureMontantMissionAffiche;
  libelle: string;
  libelleCourt: string;
  approximatif: boolean;
}

function nombreFini(value: unknown): number | null {
  if (value == null || value === '') return null;
  const nombre = typeof value === 'number' ? value : Number(value);
  return Number.isFinite(nombre) ? nombre : null;
}

/**
 * Montant indicatif à afficher pendant la transition des anciennes missions.
 *
 * Le moteur supprimé en juillet 2026 a pu plafonner à tort une mission avant
 * assignation, ou une mission explicitement libérale. Dans ces deux cas un
 * plafond Rist est impossible selon le moteur canonique : on rétablit le même
 * montant proportionnellement au taux publié, sans modifier la donnée stockée.
 */
function corrigerAncienPlafondImpossible(
  mission: MissionFinanceAffichee,
  montant: number,
): number {

  const tauxPublie = nombreFini(mission.taux_horaire_base);
  const tauxPlafonne = nombreFini(mission.taux_rist_plafonne);
  const contrat = mission.type_contrat_applique ?? mission.type_contrat_recherche;
  const plafondImpossible = contrat === 'LIBERAL' || !mission.soignant_assigne_id;

  if (!mission.rist_plafond_applique
      || !plafondImpossible
      || tauxPublie == null
      || tauxPlafonne == null
      || tauxPlafonne <= 0
      || tauxPublie <= tauxPlafonne) {
    return montant;
  }

  return Math.round(montant * (tauxPublie / tauxPlafonne) * 100) / 100;
}

function contratEffectif(mission: MissionFinanceAffichee): string | null {
  if (mission.type_contrat_applique === 'LIBERAL' || mission.type_contrat_applique === 'SALARIE') {
    return mission.type_contrat_applique;
  }
  if (mission.type_contrat_recherche === 'LIBERAL' || mission.type_contrat_recherche === 'SALARIE') {
    return mission.type_contrat_recherche;
  }
  return null;
}

/**
 * Net salarié affichable.
 *
 * `net_a_payer` est historiquement le brut augmenté des IFM/ICP dans le moteur
 * de paie. Il ne doit donc jamais servir de repli pour un libellé « net ».
 */
export function netEstimeAfficheMission(mission: MissionFinanceAffichee): number | null {
  const netStocke = nombreFini(mission.net_estime);
  if (netStocke == null) return null;
  return corrigerAncienPlafondImpossible(mission, netStocke);
}

/**
 * Montant financier cohérent avec le régime de LA mission.
 *
 * - libéral : honoraires bruts dus au soignant, sans abattement forfaitaire ;
 * - salarié : estimation nette fournie explicitement par le moteur ;
 * - contrat non choisi : brut indicatif, jamais présenté comme un net.
 */
export function montantFinanceAfficheMission(
  mission: MissionFinanceAffichee,
): MontantMissionAffiche | null {
  const contrat = contratEffectif(mission);

  if (contrat === 'LIBERAL') {
    const honoraires = nombreFini(mission.net_a_payer) ?? nombreFini(mission.total_brut);
    if (honoraires == null) return null;
    return {
      montant: corrigerAncienPlafondImpossible(mission, honoraires),
      nature: 'HONORAIRES_LIBERAUX',
      libelle: 'Honoraires bruts',
      libelleCourt: 'honoraires',
      approximatif: false,
    };
  }

  if (contrat === 'SALARIE') {
    const net = netEstimeAfficheMission(mission);
    if (net == null) return null;
    return {
      montant: net,
      nature: 'NET_SALARIE_ESTIME',
      libelle: 'Net salarié estimé*',
      libelleCourt: 'net estimé*',
      approximatif: true,
    };
  }

  const brut = nombreFini(mission.total_brut) ?? nombreFini(mission.net_a_payer);
  if (brut == null) return null;
  return {
    montant: corrigerAncienPlafondImpossible(mission, brut),
    nature: 'BRUT_INDICATIF',
    libelle: 'Rémunération brute indicative',
    libelleCourt: 'brut indicatif',
    approximatif: true,
  };
}
