/**
 * Saisie en cours du formulaire « Compléter mes informations », gardée en
 * mémoire de l'onglet.
 *
 * Une page ouverte depuis le formulaire (CGU, aide, confidentialité) le
 * démonte : sans cette mémoire, le retour arrière affichait un formulaire vide
 * (identité, profession, déclaration étudiant perdues ; CI iPad du 17/11/2026).
 *
 * La saisie n'est qu'une couche posée sur le dernier brouillon serveur connu
 * de l'onglet : celui chargé à l'ouverture du formulaire, ou celui que
 * l'onglet vient lui-même d'enregistrer (`enregistrerParcours`, par exemple
 * juste avant un envoi refusé ; revue B8 n°2 #1137, m1). Si le brouillon
 * serveur a changé depuis sur l'un des champs du formulaire (correction faite
 * ailleurs, autre appareil), la saisie est obsolète : elle est ignorée et
 * oubliée, le brouillon serveur l'emporte (revue B8 #1137, B1).
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
/** Dernier brouillon serveur connu de l'onglet, par compte et type de compte. */
const brouillonsConnus = new Map<string, Record<string, unknown>>();
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
  brouillonsConnus.set(cle(compte), serveur);
  const memoire = saisies.get(cle(compte));
  if (!memoire) return { donnees: serveur, depuisOnglet: false };
  if (empreinte(compte.donnees, Object.keys(memoire.saisie)) !== memoire.base) {
    saisies.delete(cle(compte));
    return { donnees: serveur, depuisOnglet: false };
  }
  return { donnees: { ...serveur, ...memoire.saisie }, depuisOnglet: true };
}

/**
 * `saisie` doit déjà être filtrée (sans secrets) par `donneesFormulaire`. Sa
 * base est le dernier brouillon serveur connu de l'onglet ; `compte.donnees`
 * (le brouillon d'ouverture) ne sert que si l'onglet n'en connaît aucun.
 */
export function memoriserSaisie(compte: CompteSaisie & { donnees?: Brouillon }, saisie: Record<string, unknown>) {
  const base = brouillonsConnus.get(cle(compte)) ?? compte.donnees;
  saisies.set(cle(compte), { base: empreinte(base, Object.keys(saisie)), saisie: { ...saisie } });
}

/**
 * L'onglet vient d'écrire `envoye` dans le brouillon serveur. Seuls ces champs
 * avancent dans la base : la ligne renvoyée par le serveur peut contenir une
 * correction faite ailleurs (autre appareil) que la saisie de l'onglet ne doit
 * pas absorber, par exemple quand l'onglet n'enregistre qu'un brouillon de
 * mission.
 */
export function brouillonEnregistre(compte: CompteSaisie, envoye: Record<string, unknown>) {
  const connu = { ...(brouillonsConnus.get(cle(compte)) ?? {}), ...envoye };
  brouillonsConnus.set(cle(compte), connu);
  const memoire = saisies.get(cle(compte));
  if (memoire) memoire.base = empreinte(connu, Object.keys(memoire.saisie));
}

export function oublierSaisie(compte: CompteSaisie) {
  saisies.delete(cle(compte));
  brouillonsConnus.delete(cle(compte));
}

export function oublierToutesLesSaisies() {
  saisies.clear();
  brouillonsConnus.clear();
}
