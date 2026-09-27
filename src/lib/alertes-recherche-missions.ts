export interface CriteresAlerteMissions {
  profession: string;
  rayonKm: number;
  tauxMin: number;
  typeContrat: string;
  urgentesOnly: boolean;
  horaire: string;
  villeRecherche: string;
}
interface RechercheExistante {
  id: string; nom: string; alerte_active: boolean; filtres: Record<string, unknown>;
}

/** Ne réactive jamais une recherche de même nom avec d'autres critères. */
export function preparerAlerteMissions(criteres: CriteresAlerteMissions, recherches: RechercheExistante[], nomBase: string) {
  const cle = (valeur: Record<string, unknown>) => JSON.stringify(Object.fromEntries(Object.entries(valeur).sort(([a], [b]) => a.localeCompare(b))));
  const deja = recherches.find(recherche => cle(recherche.filtres ?? {}) === cle({ ...criteres }));
  const noms = new Set(recherches.map(recherche => recherche.nom));
  let nom = nomBase.slice(0, 90);
  for (let suffixe = 2; noms.has(nom); suffixe++) nom = `${nomBase.slice(0, 90)} (${suffixe})`;
  return { deja, nom, filtres: { ...criteres } };
}
