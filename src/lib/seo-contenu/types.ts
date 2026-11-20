/** Types des textes partagés entre les composants React et le HTML statique. */
export interface QuestionSEO { q: string; r: string }

/** Bloc de contenu statique : un titre de niveau 2, des paragraphes et, au besoin, une liste. */
export interface SectionSEO { titre: string; paragraphes?: string[]; liste?: string[] }
