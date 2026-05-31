/**
 * Règles d'installation en libéral par profession (France, 2026).
 *
 * Sources : conventions nationales CPAM par profession, ameli.fr,
 * Ordres professionnels concernés. Voir docs/regles-installation-liberal.md
 * pour la synthèse et les liens.
 *
 * v1 — Phase C Session 1 (avril 2026)
 */

export type CategorieInstallation =
  | 'NON_ELIGIBLE'
  | 'AVEC_HEURES_IDE'
  | 'AVEC_HEURES_KINE'
  | 'AVEC_HEURES_IPA'
  | 'SANS_HEURES_CPAM'
  | 'SANS_HEURES_CIPAV';

export interface RegleInstallation {
  categorie: CategorieInstallation;
  heures_requises?: number;
  periode_annees?: number;
  caisse_retraite?: 'CARPIMKO' | 'CARCDSF' | 'CARMF' | 'CIPAV';
  conventionne_cpam?: boolean;
  option_zone_sous_dotee?: boolean;
  secteur_choix?: boolean;
  label_ordre?: string;
  lien_ordre?: string;
  lien_cpam?: string;
  lien_caisse_retraite?: string;
}

export const REGLES_INSTALLATION_LIBERAL: Record<string, RegleInstallation> = {
  IDE: {
    categorie: 'AVEC_HEURES_IDE',
    heures_requises: 3200,
    periode_annees: 6,
    caisse_retraite: 'CARPIMKO',
    conventionne_cpam: true,
    label_ordre: 'Ordre National des Infirmiers',
    lien_ordre: 'https://www.ordre-infirmiers.fr',
    lien_cpam: 'https://installation-idel.ameli.fr',
    lien_caisse_retraite: 'https://www.carpimko.com',
  },

  IBODE: {
    categorie: 'AVEC_HEURES_IDE',
    heures_requises: 3200,
    periode_annees: 6,
    caisse_retraite: 'CARPIMKO',
    conventionne_cpam: true,
    label_ordre: 'Ordre National des Infirmiers',
    lien_ordre: 'https://www.ordre-infirmiers.fr',
    lien_cpam: 'https://installation-idel.ameli.fr',
    lien_caisse_retraite: 'https://www.carpimko.com',
  },

  IADE: {
    categorie: 'AVEC_HEURES_IDE',
    heures_requises: 3200,
    periode_annees: 6,
    caisse_retraite: 'CARPIMKO',
    conventionne_cpam: true,
    label_ordre: 'Ordre National des Infirmiers',
    lien_ordre: 'https://www.ordre-infirmiers.fr',
    lien_cpam: 'https://installation-idel.ameli.fr',
    lien_caisse_retraite: 'https://www.carpimko.com',
  },

  KINE: {
    categorie: 'AVEC_HEURES_KINE',
    heures_requises: 2240,
    periode_annees: 2,
    caisse_retraite: 'CARPIMKO',
    conventionne_cpam: true,
    option_zone_sous_dotee: true,
    label_ordre: 'Ordre des Masseurs-Kinésithérapeutes',
    lien_ordre: 'https://www.ordremk.fr',
    lien_cpam: 'https://installation-kine.ameli.fr',
    lien_caisse_retraite: 'https://www.carpimko.com',
  },

  SAGE_FEMME: {
    categorie: 'SANS_HEURES_CPAM',
    caisse_retraite: 'CARCDSF',
    conventionne_cpam: true,
    label_ordre: 'Ordre des Sages-Femmes',
    lien_ordre: 'https://www.ordre-sages-femmes.fr',
    lien_cpam: 'https://www.ameli.fr/sage-femme',
    lien_caisse_retraite: 'https://www.carcdsf.fr',
  },

  MEDECIN: {
    categorie: 'SANS_HEURES_CPAM',
    caisse_retraite: 'CARMF',
    conventionne_cpam: true,
    secteur_choix: true,
    label_ordre: "Conseil National de l'Ordre des Médecins",
    lien_ordre: 'https://www.conseil-national.medecin.fr',
    lien_cpam: 'https://www.ameli.fr/medecin',
    lien_caisse_retraite: 'https://www.carmf.fr',
  },

  // Chirurgien-dentiste : installation directe après diplôme (pas d'heures
  // préalables). Caisse de retraite CARCDSF, conventionné CPAM. Art. L4141-1 CSP.
  DENTISTE: {
    categorie: 'SANS_HEURES_CPAM',
    caisse_retraite: 'CARCDSF',
    conventionne_cpam: true,
    secteur_choix: true,
    label_ordre: 'Ordre National des Chirurgiens-Dentistes',
    lien_ordre: 'https://www.ordre-chirurgiens-dentistes.fr',
    lien_cpam: 'https://www.ameli.fr/chirurgien-dentiste',
    lien_caisse_retraite: 'https://www.carcdsf.fr',
  },

  ORTHOPHONISTE: {
    categorie: 'SANS_HEURES_CPAM',
    caisse_retraite: 'CARPIMKO',
    conventionne_cpam: true,
    label_ordre: 'Fédération Nationale des Orthophonistes',
    lien_ordre: 'https://fno.fr',
    lien_cpam: 'https://www.ameli.fr/orthophoniste',
    lien_caisse_retraite: 'https://www.carpimko.com',
  },

  ORTHOPTISTE: {
    categorie: 'SANS_HEURES_CPAM',
    caisse_retraite: 'CARPIMKO',
    conventionne_cpam: true,
    label_ordre: 'Syndicat National Autonome des Orthoptistes',
    lien_ordre: 'https://www.orthoptistes.org',
    lien_cpam: 'https://www.ameli.fr/orthoptiste',
    lien_caisse_retraite: 'https://www.carpimko.com',
  },

  PEDICURE_PODOLOGUE: {
    categorie: 'SANS_HEURES_CPAM',
    caisse_retraite: 'CARPIMKO',
    conventionne_cpam: true,
    label_ordre: 'Ordre des Pédicures-Podologues',
    lien_ordre: 'https://www.onpp.fr',
    lien_cpam: 'https://www.ameli.fr/pedicure-podologue',
    lien_caisse_retraite: 'https://www.carpimko.com',
  },

  ERGOTHERAPEUTE: {
    categorie: 'SANS_HEURES_CIPAV',
    caisse_retraite: 'CIPAV',
    conventionne_cpam: false,
    label_ordre: 'ANFE',
    lien_ordre: 'https://anfe.fr',
    lien_caisse_retraite: 'https://www.lacipav.fr',
  },

  PSYCHOMOTRICIEN: {
    categorie: 'SANS_HEURES_CIPAV',
    caisse_retraite: 'CIPAV',
    conventionne_cpam: false,
    lien_caisse_retraite: 'https://www.lacipav.fr',
  },

  DIETETICIEN: {
    categorie: 'SANS_HEURES_CIPAV',
    caisse_retraite: 'CIPAV',
    conventionne_cpam: false,
    lien_caisse_retraite: 'https://www.lacipav.fr',
  },

  // Non éligibles libéral Jolene
  AS: { categorie: 'NON_ELIGIBLE' },
  AES: { categorie: 'NON_ELIGIBLE' },
  AUXILIAIRE_PUERICULTURE: { categorie: 'NON_ELIGIBLE' },
  MANIPULATEUR_RADIO: { categorie: 'NON_ELIGIBLE' },
  PHARMACIEN: { categorie: 'NON_ELIGIBLE' },
  PREPARATEUR_PHARMA: { categorie: 'NON_ELIGIBLE' },
};

export function estEligibleLiberal(profession: string): boolean {
  const regle = REGLES_INSTALLATION_LIBERAL[profession];
  return Boolean(regle) && regle.categorie !== 'NON_ELIGIBLE';
}

export function getRegleInstallation(profession: string): RegleInstallation | null {
  return REGLES_INSTALLATION_LIBERAL[profession] || null;
}
