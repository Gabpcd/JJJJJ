/**
 * Saisie en cours du formulaire « Compléter mes informations », gardée en
 * mémoire de l'onglet.
 *
 * Une page ouverte depuis le formulaire (CGU, aide, confidentialité) le
 * démonte : sans cette mémoire, le retour arrière affichait un formulaire vide
 * (identité, profession, déclaration étudiant perdues ; CI iPad du 17/11/2026).
 *
 * Rien n'est écrit dans le stockage du navigateur : ce sont des données
 * personnelles. Un rechargement repart donc du brouillon enregistré côté
 * serveur. Les entrées sont rangées par compte et par type de compte, et
 * effacées à la déconnexion et après la finalisation du profil.
 */
export interface CompteSaisie {
  user_id: string;
  type_compte: string;
}

const saisies = new Map<string, Record<string, unknown>>();
const cle = (compte: CompteSaisie) => `${compte.user_id}:${compte.type_compte}`;

/** Données à donner au formulaire : brouillon serveur, puis saisie de l'onglet. */
export function donneesAReprendre(
  compte: CompteSaisie & { donnees?: Record<string, unknown> | null },
): Record<string, unknown> {
  return { ...(compte.donnees ?? {}), ...(saisies.get(cle(compte)) ?? {}) };
}

/** `donnees` doit déjà être filtré (sans secrets) par `donneesFormulaire`. */
export function memoriserSaisie(compte: CompteSaisie, donnees: Record<string, unknown>) {
  saisies.set(cle(compte), { ...donnees });
}

export function oublierSaisie(compte: CompteSaisie) {
  saisies.delete(cle(compte));
}

export function oublierToutesLesSaisies() {
  saisies.clear();
}
