// Constantes cotisations sociales 2026 — Source de vérité côté client.
//
// IMPORTANT : ces valeurs DOIVENT rester strictement alignées avec celles
// utilisées par la RPC SQL `public.fn_calculer_cotisations(p_mission_id)`
// (cf. migration originale du module paie). Tout désaccord entre les
// taux DB et les taux frontend produirait des bulletins incohérents avec
// la table `cotisations_sociales`.
//
// Le DB reste la SEULE source autoritaire pour les calculs ; ces
// constantes ne servent QUE :
//   1. à afficher les taux dans le PDF du bulletin (mention "CSG 6.80%"
//      à côté du montant calculé en DB),
//   2. comme référence documentaire pour les revues annuelles.

/** Plafond mensuel de la Sécurité sociale 2026 (€). */
export const PMSS_2026 = 3864;

/** Plafond annuel = PMSS × 12. */
export const PASS_2026 = PMSS_2026 * 12;

// ───────────────────────────────────────────────────────────────────────
// CSG / CRDS — Base 98.25 % du brut (pour rémunérations < 4 PMSS).

/** Assiette CSG/CRDS en pourcentage du brut (abattement 1.75%). */
export const TAUX_CSG_BASE = 0.9825;

/** CSG déductible du revenu imposable. */
export const TAUX_CSG_DEDUCTIBLE = 0.0680;

/** CSG non déductible. */
export const TAUX_CSG_NON_DEDUCTIBLE = 0.0240;

/** CRDS (Contribution au Remboursement de la Dette Sociale). */
export const TAUX_CRDS = 0.0050;

// ───────────────────────────────────────────────────────────────────────
// Sécurité sociale — Cotisations salariales

/**
 * Maladie part salariale = 0% depuis 2018 (suppression dans la loi
 * de financement de la SS 2018, compensée par hausse CSG).
 */
export const TAUX_SS_MALADIE = 0;

/** Vieillesse plafonnée — assiette = MIN(brut, PMSS). */
export const TAUX_SS_VIEILLESSE_PLAFONNEE = 0.0690;

/** Vieillesse déplafonnée — assiette = brut total. */
export const TAUX_SS_VIEILLESSE_DEPLAFONNEE = 0.0040;

// ───────────────────────────────────────────────────────────────────────
// Retraite complémentaire AGIRC-ARRCO

/** Tranche 1 : assiette = MIN(brut, PMSS). */
export const TAUX_RETRAITE_T1 = 0.0386;

/** Tranche 2 : assiette = MAX(0, brut - PMSS). Plafond T2 = 8 PMSS. */
export const TAUX_RETRAITE_T2 = 0.1021;

/** CEG — Contribution d'Équilibre Général. Assiette = MIN(brut, PMSS). */
export const TAUX_CEG = 0.0086;

// ───────────────────────────────────────────────────────────────────────
// Chômage

/** Part salariale chômage = 0% depuis 2018. */
export const TAUX_CHOMAGE_SALARIAL = 0;

// ───────────────────────────────────────────────────────────────────────
// Cotisations patronales (à titre informatif sur le bulletin)

export const TAUX_PATRONAL_SECURITE_SOCIALE = 0.1305;
export const TAUX_PATRONAL_ALLOCATIONS_FAMILIALES = 0.0525;
export const TAUX_PATRONAL_ACCIDENT_TRAVAIL = 0.0100;
export const TAUX_PATRONAL_RETRAITE = 0.0601;
export const TAUX_PATRONAL_CHOMAGE = 0.0405;
export const TAUX_PATRONAL_FNAL = 0.0050;
export const TAUX_PATRONAL_FORMATION = 0.0055;
export const TAUX_PATRONAL_TRANSPORT = 0.0175;

// ───────────────────────────────────────────────────────────────────────
// CDD — Indemnités de fin de contrat (art. L1243-8 et L3141-22 CTW)

/** Indemnité de Fin de Mission (10% du brut hors IFM/ICP). */
export const TAUX_IFM = 0.10;

/** Indemnité Compensatrice de Congés Payés (10% sur brut + IFM). */
export const TAUX_ICP = 0.10;

// ───────────────────────────────────────────────────────────────────────
// Helpers de formatage

export const formatTaux = (taux: number): string =>
  `${(taux * 100).toFixed(2).replace(/\.?0+$/, '')} %`;
