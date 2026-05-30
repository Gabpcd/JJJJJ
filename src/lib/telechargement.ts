import { isNative } from './platform';

/**
 * Télécharge (web) ou partage (natif) un fichier généré côté client.
 *
 * En WebView native iOS/Android, `<a download>` + click() ne déclenche AUCUN
 * téléchargement (pas de gestionnaire de fichiers navigateur). On passe donc
 * par la feuille de partage native (@capacitor/share) avec un fichier écrit
 * dans le cache, ce qui permet "Enregistrer dans Fichiers", "Ouvrir dans
 * Calendrier", etc.
 *
 * @param contenu  contenu texte du fichier
 * @param nomFichier  nom (avec extension, ex: "export.csv", "mission.ics")
 * @param mime  type MIME (ex: "text/csv", "text/calendar")
 */
export async function telechargerOuPartager(
  contenu: string,
  nomFichier: string,
  mime: string,
): Promise<void> {
  if (!isNative()) {
    // Web : téléchargement classique
    const blob = new Blob([contenu], { type: `${mime};charset=utf-8` });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = nomFichier;
    a.click();
    URL.revokeObjectURL(url);
    return;
  }

  // Natif : écrire dans le cache puis ouvrir la feuille de partage
  try {
    const { Filesystem, Directory, Encoding } = await import('@capacitor/filesystem');
    const { Share } = await import('@capacitor/share');
    await Filesystem.writeFile({
      path: nomFichier,
      data: contenu,
      directory: Directory.Cache,
      encoding: Encoding.UTF8,
    });
    const { uri } = await Filesystem.getUri({ path: nomFichier, directory: Directory.Cache });
    await Share.share({ url: uri, title: nomFichier });
  } catch (e) {
    // Filesystem indisponible → fallback partage texte brut
    try {
      const { Share } = await import('@capacitor/share');
      await Share.share({ text: contenu, title: nomFichier });
    } catch {
      // dernier recours : data URL (iOS sait ouvrir text/calendar)
      const dataUrl = `data:${mime};charset=utf-8,${encodeURIComponent(contenu)}`;
      window.open(dataUrl, '_blank');
    }
  }
}
