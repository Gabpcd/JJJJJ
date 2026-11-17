/**
 * Saisie en cours du formulaire « Compléter mes informations », gardée en
 * mémoire de l'onglet.
 *
 * Une page ouverte depuis le formulaire (CGU, aide, confidentialité) le
 * démonte : sans cette mémoire, le retour arrière affichait un formulaire vide
 * (identité, profession, déclaration étudiant perdues ; CI iPad du 17/11/2026).
 *
 * La saisie n'est qu'une couche posée sur le brouillon serveur du moment où
 * elle a été faite. Si ce brouillon a changé depuis sur l'un des champs du
 * formulaire (correction faite ailleurs, autre appareil), la saisie est
 * obsolète : elle est ignorée et oubliée, le brouillon serveur l'emporte
 * (revue B8 #1137, B1).
 *
 * Rien n'est écrit dans le stockage du navigateur : ce sont des données
 * personnelles. Un rechargement repart donc du brouillon serveur. Les entrées
 * sont rangées par compte et par type de compte, et effacées après la
 * finalisation du profil, après « Enregistrer et continuer plus tard », et dès
 * que la session change ou se termine (`AuthContext`).
 */
export interface CompteSaisie {
  user_id: string;
  type_compte: string;
}

type Brouillon = Record<string, unknown> | null | undefined;

interface Saisie {
  /** Empreinte du brouillon serveur, limitée aux champs du formulaire. */
  base: string;
  saisie: Record<string, unknown>;
}

const saisies = new Map<string, Saisie>();
const cle = (compte: CompteSaisie) => `${compte.user_id}:${compte.type_compte}`;
const empreinte = (brouillon: Brouillon, champs: string[]) =>
  JSON.stringify([...champs].sort().map((champ) => [champ, brouillon?.[champ] ?? null]));

/**
 * Données à donner au formulaire : le brouillon serveur, puis la saisie de
 * l'onglet si elle a été faite sur ce même brouillon.
 */
export function reprendreSaisie(compte: CompteSaisie & { donnees?: Brouillon }): {
  donnees: Record<string, unknown>;
  depuisOnglet: boolean;
} {
  const serveur = { ...(compte.donnees ?? {}) };
  const memoire = saisies.get(cle(compte));
  if (!memoire) return { donnees: serveur, depuisOnglet: false };
  if (empreinte(compte.donnees, Object.keys(memoire.saisie)) !== memoire.base) {
    saisies.delete(cle(compte));
    return { donnees: serveur, depuisOnglet: false };
  }
  return { donnees: { ...serveur, ...memoire.saisie }, depuisOnglet: true };
}

/**
 * `compte.donnees` est le brouillon serveur sur lequel le formulaire a été
 * ouvert ; `saisie` doit déjà être filtrée (sans secrets) par `donneesFormulaire`.
 */
export function memoriserSaisie(compte: CompteSaisie & { donnees?: Brouillon }, saisie: Record<string, unknown>) {
  saisies.set(cle(compte), { base: empreinte(compte.donnees, Object.keys(saisie)), saisie: { ...saisie } });
}

export function oublierSaisie(compte: CompteSaisie) {
  saisies.delete(cle(compte));
}

export function oublierToutesLesSaisies() {
  saisies.clear();
}
