import { PROFESSIONS } from '@/lib/constantes';

export interface FiltresRechercheSoignants {
  profession: string;
  type_exercice: string;
  ville: string;
  distance_max_km: string;
  note_min: string;
  score_min: string;
  experience_min: string;
  disponible_urgence: boolean;
  documents_valides: boolean;
  recherche_texte: string;
}

const texte = (valeur: unknown) => typeof valeur === 'string' ? valeur : '';
const nombre = (valeur: unknown, maximum: number, entier = true) => {
  if ((typeof valeur !== 'number' && typeof valeur !== 'string') || String(valeur).trim() === '') return '';
  const n = Number(valeur);
  return Number.isFinite(n) && n >= 0 && n <= maximum && (!entier || Number.isInteger(n)) ? String(n) : '';
};

/** Une recherche stockée n'impose ni clés inconnues ni valeurs hors des limites du formulaire. */
export function normaliserFiltresRechercheSoignants(valeur: unknown): FiltresRechercheSoignants {
  const f = valeur && typeof valeur === 'object' && !Array.isArray(valeur) ? valeur as Record<string, unknown> : {};
  return {
    profession: PROFESSIONS.some(p => p.valeur === f.profession) ? String(f.profession) : '',
    type_exercice: ['LIBERAL', 'SALARIE', 'MIXTE'].includes(texte(f.type_exercice)) ? String(f.type_exercice) : '',
    ville: texte(f.ville),
    distance_max_km: nombre(f.distance_max_km, 500),
    note_min: nombre(f.note_min, 5, false),
    score_min: nombre(f.score_min, 100),
    experience_min: nombre(f.experience_min, 50),
    disponible_urgence: f.disponible_urgence === true,
    documents_valides: f.documents_valides === true,
    recherche_texte: texte(f.recherche_texte),
  };
}
