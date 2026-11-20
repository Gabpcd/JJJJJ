/** Types des textes partagés entre les composants React et le HTML statique. */
export interface QuestionSEO { q: string; r: string }

/** Lien vers une source officielle citée sous une section (ouvert dans un nouvel onglet). */
export interface SourceSEO { href: string; label: string }

/** Tableau de données : une légende (obligatoire, lue par les lecteurs d'écran), des en-têtes, des lignes. */
export interface TableauSEO { legende: string; entetes: string[]; lignes: string[][] }

/**
 * Bloc de contenu : un titre de niveau 2, puis, dans cet ordre, des paragraphes, des
 * points titrés, une liste (numérotée si `ordonnee`), un tableau, des liens internes et des sources. Rendu à l'identique par le
 * HTML statique (`contenuRacine`) et par le composant `ContenuSEO`.
 */
export interface SectionSEO {
  titre: string;
  paragraphes?: string[];
  /** Points titrés (titre de niveau 3 + texte), avec un lien interne facultatif sur le titre. */
  points?: PointSEO[];
  liste?: string[];
  ordonnee?: boolean;
  tableau?: TableauSEO;
  /** Liens internes propres à la section (pages citées par son texte). */
  liens?: { href: string; label: string }[];
  sources?: SourceSEO[];
}

export interface PointSEO { titre: string; texte: string; href?: string }
