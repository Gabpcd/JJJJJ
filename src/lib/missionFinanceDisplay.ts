interface MissionFinanceAffichee {
  profession_requise?: string | null;
  type_contrat_recherche?: string | null;
  type_contrat_applique?: string | null;
  soignant_assigne_id?: string | null;
  taux_horaire_base?: number | null;
  taux_rist_plafonne?: number | null;
  rist_plafond_applique?: boolean | null;
  net_estime?: number | null;
  net_a_payer?: number | null;
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
export function netEstimeAfficheMission(mission: MissionFinanceAffichee): number | null {
  const netStocke = nombreFini(mission.net_estime)
    ?? (() => {
      const netAPayer = nombreFini(mission.net_a_payer);
      return netAPayer == null ? null : netAPayer * 0.78;
    })();
  if (netStocke == null) return null;

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
    return netStocke;
  }

  return Math.round(netStocke * (tauxPublie / tauxPlafonne) * 100) / 100;
}
