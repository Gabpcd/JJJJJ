export interface ArticleLoi {
  code: string;
  titre: string;
  texteOfficiel: string;
  explicationSimple: string;
  conseil: string;
  sanction: string;
}

export const ARTICLES_CODE_TRAVAIL: Record<string, ArticleLoi> = {
  'L3131-1': {
    code: 'L3131-1',
    titre: 'Repos quotidien obligatoire de 11 heures',
    texteOfficiel: "Tout salarié bénéficie d'un repos quotidien d'une durée minimale de onze heures consécutives, sauf dans les cas prévus aux articles L. 3131-2 et L. 3131-3 ou en cas d'urgence, dans des conditions déterminées par décret.",
    explicationSimple: "Entre la fin d'une mission et le début de la suivante, le soignant doit disposer d'au moins 11 heures de repos consécutives. Cette règle protège la santé du soignant et la sécurité des patients.",
    conseil: "Vérifiez les horaires de fin de la mission précédente et de début de la mission suivante du soignant. Il faut au minimum 11h d'écart entre les deux. Décalez le début de la mission ou choisissez un autre soignant disponible.",
    sanction: "Amende de 750 € par salarié concerné (contravention de 4ème classe). En cas de récidive ou de mise en danger, la responsabilité pénale de l'établissement peut être engagée.",
  },
  'L3121-20': {
    code: 'L3121-20',
    titre: 'Durée maximale hebdomadaire de 48 heures',
    texteOfficiel: "Au cours d'une même semaine, la durée maximale hebdomadaire de travail est de quarante-huit heures.",
    explicationSimple: "Un soignant ne peut pas travailler plus de 48 heures sur une même semaine civile (du lundi au dimanche), toutes missions confondues sur la plateforme.",
    conseil: "Le soignant a déjà trop d'heures planifiées cette semaine. Deux solutions : décalez la mission à la semaine suivante, ou assignez-la à un autre soignant dont le compteur hebdomadaire le permet.",
    sanction: "Amende de 750 € par salarié concerné. L'inspection du travail (DREETS) peut ordonner l'arrêt immédiat de l'activité.",
  },
  'L3121-18': {
    code: 'L3121-18',
    titre: 'Durée maximale quotidienne de 10 heures',
    texteOfficiel: "La durée quotidienne de travail effectif par salarié ne peut excéder dix heures, sauf dérogation accordée dans des conditions déterminées par décret.",
    explicationSimple: "Une mission ne peut pas durer plus de 10 heures dans une même journée, sauf dérogation spécifique pour les établissements de santé.",
    conseil: "Réduisez la durée de la mission ou scindez-la en deux missions distinctes avec un repos intermédiaire.",
    sanction: "Amende de 750 € par salarié concerné.",
  },
  'L3122-6': {
    code: 'L3122-6',
    titre: 'Durée maximale du travail de nuit',
    texteOfficiel: "La durée quotidienne de travail accomplie par un travailleur de nuit ne peut excéder huit heures.",
    explicationSimple: "Un soignant travaillant de nuit (entre 21h et 6h) ne peut pas effectuer plus de 8 heures de travail nocturne par période de 24 heures.",
    conseil: "Ajustez les horaires de la mission pour que la partie nocturne ne dépasse pas 8 heures.",
    sanction: "Amende de 750 € par salarié concerné.",
  },
};

export const PLAFONDS_RIST: Record<string, number> = {
  'IDE': 24.05,
  'AS': 18.20,
  'IBODE': 26.65,
  'IADE': 28.60,
  'SAGE_FEMME': 27.30,
  'AES': 17.55,
  'KINE': 24.70,
  'MEDECIN': 347.60,
  'PHARMACIEN': 186.20,
  'MANIPULATEUR_RADIO': 78.40,
  'PREPARATEUR_PHARMA': 56.30,
  'DIETETICIEN': 62.50,
  'ERGOTHERAPEUTE': 72.80,
  'PSYCHOMOTRICIEN': 72.80,
  'ORTHOPHONISTE': 78.40,
};

export function extraireCodeArticle(messageErreur: string): string | null {
  const match = messageErreur.match(/\(Art\.\s*([^)]+)\)/);
  return match ? match[1].trim() : null;
}

export function obtenirExplicationArticle(messageErreur: string): ArticleLoi | null {
  const code = extraireCodeArticle(messageErreur);
  if (!code) return null;
  return ARTICLES_CODE_TRAVAIL[code] || null;
}
