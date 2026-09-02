import { isNative } from './platform';

function partageAnnule(erreur: unknown): boolean {
  return erreur instanceof Error && /share cancel(?:ed|led)|partage annul/i.test(erreur.message);
}

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
    // Fermer volontairement la feuille de partage ne doit surtout pas ouvrir
    // une seconde feuille contenant le texte brut du fichier.
    if (partageAnnule(e)) return;
    // Filesystem indisponible → fallback partage texte brut
    try {
      const { Share } = await import('@capacitor/share');
      await Share.share({ text: contenu, title: nomFichier });
    } catch (shareError) {
      if (partageAnnule(shareError)) return;
      // dernier recours : data URL (iOS sait ouvrir text/calendar)
      const dataUrl = `data:${mime};charset=utf-8,${encodeURIComponent(contenu)}`;
      window.open(dataUrl, '_blank');
    }
  }
}

/**
 * Télécharge (web) ou partage (natif) un PDF généré par jsPDF.
 * Web : doc.save() classique. Natif : écrit le PDF (base64) dans le cache
 * et ouvre la feuille de partage ("Enregistrer dans Fichiers", AirDrop…).
 *
 * @param doc  instance jsPDF
 * @param nomFichier  nom avec extension .pdf
 */
export async function telechargerOuPartagerPdf(
  doc: { save: (n: string) => void; output: (type: string) => string },
  nomFichier: string,
): Promise<void> {
  if (!isNative()) {
    doc.save(nomFichier);
    return;
  }
  try {
    const base64 = doc.output('datauristring').split(',')[1]; // PDF en base64
    const { Filesystem, Directory } = await import('@capacitor/filesystem');
    const { Share } = await import('@capacitor/share');
    await Filesystem.writeFile({ path: nomFichier, data: base64, directory: Directory.Cache });
    const { uri } = await Filesystem.getUri({ path: nomFichier, directory: Directory.Cache });
    await Share.share({ url: uri, title: nomFichier });
  } catch (erreur) {
    if (partageAnnule(erreur)) return;
    // Fallback : ouvrir le data URL (le WebView affiche le PDF)
    try { window.open(doc.output('dataurlnewwindow') as any, '_blank'); } catch { doc.save(nomFichier); }
  }
}
