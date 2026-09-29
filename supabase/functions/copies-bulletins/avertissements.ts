const consolesProtegees = new WeakSet<object>();

/**
 * Cette Edge traite des documents privés. pdf-lib 1.17.1 écrit certains
 * diagnostics contenant leurs valeurs dans console.warn avant de lever/revenir.
 * Installer une fois au démarrage, jamais autour d'une requête ou d'un await :
 * tous les appels concurrents conservent la même frontière. Seul le canal warn
 * est expurgé ; les autres niveaux et les erreurs métier restent inchangés.
 */
export function installerAvertissementsCopies(cible: Pick<Console, 'warn'> = console): void {
  if (consolesProtegees.has(cible)) return;
  const avertir = cible.warn.bind(cible);
  cible.warn = () => avertir('COPIE_DOCUMENT_AVERTISSEMENT');
  consolesProtegees.add(cible);
}
