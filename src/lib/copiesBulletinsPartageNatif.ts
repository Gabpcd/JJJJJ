import { Directory, Filesystem } from '@capacitor/filesystem';
import { Share } from '@capacitor/share';
import { creerUuidV4 } from '@/lib/uuid';

const DOSSIER = 'copies-bulletins-partage';
const GARDE_APRES_PARTAGE_MS = 60 * 60 * 1_000;
const GARDE_ORPHELIN_MS = 24 * 60 * 60 * 1_000;
const MAX_FICHIERS = 100;
const MAX_OCTETS = 50 * 1024 * 1024;
const TAILLE_INCONNUE = 10 * 1024 * 1024;
const NOM_FICHIER = /^(\d{13})-[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.pdf$/;
type Conservation = { actif: boolean; jusqua: number; minuteur?: ReturnType<typeof setTimeout> };
const conservations = new Map<string, Conservation>();
let operations: Promise<unknown> = Promise.resolve();

// Serialize cache inspection/writes/deletions, never the native chooser itself.
function dansCache<T>(operation: () => Promise<T>): Promise<T> {
  const resultat = operations.then(operation);
  operations = resultat.catch(() => undefined);
  return resultat;
}

async function supprimer(path: string): Promise<boolean> {
  try {
    await Filesystem.deleteFile({ path, directory: Directory.Cache });
    const conservation = conservations.get(path);
    if (conservation?.minuteur) clearTimeout(conservation.minuteur);
    conservations.delete(path);
    return true;
  } catch { return false; } // Retry at the next share; failed cleanup still consumes a slot.
}

function conserverApresPartage(path: string) {
  const conservation: Conservation = { actif: false, jusqua: Date.now() + GARDE_APRES_PARTAGE_MS };
  conservations.set(path, conservation);
  conservation.minuteur = setTimeout(() => {
    void dansCache(async () => {
      if (!conservation.actif && Date.now() >= conservation.jusqua) await supprimer(path);
    });
  }, GARDE_APRES_PARTAGE_MS);
}

async function preparer(data: string): Promise<string> {
  const taille = atob(data).length;
  // mkdir may reject when the directory already exists. readdir must still
  // succeed, so an inaccessible cache never bypasses the capacity check.
  await Filesystem.mkdir({ path: DOSSIER, directory: Directory.Cache, recursive: true }).catch(() => undefined);
  const { files } = await Filesystem.readdir({ path: DOSSIER, directory: Directory.Cache });
  let nombre = 0;
  let octets = 0;
  for (const file of files) {
    const nom = NOM_FICHIER.exec(file.name);
    if (file.type !== 'file' || !nom) continue;
    const path = `${DOSSIER}/${file.name}`;
    const conservation = conservations.get(path);
    const expire = conservation
      ? !conservation.actif && Date.now() >= conservation.jusqua
      : Date.now() - Number(nom[1]) > GARDE_ORPHELIN_MS;
    if (!expire || !await supprimer(path)) {
      nombre++;
      octets += Number.isSafeInteger(file.size) && file.size >= 0 ? file.size : TAILLE_INCONNUE;
    }
  }
  if (nombre >= MAX_FICHIERS || octets + taille > MAX_OCTETS) throw new Error('L’espace temporaire des PDF partagés est plein. Réessayez plus tard pour ouvrir une autre copie.');
  const path = `${DOSSIER}/${Date.now()}-${creerUuidV4()}.pdf`;
  conservations.set(path, { actif: true, jusqua: Infinity });
  try {
    await Filesystem.writeFile({ path, data, directory: Directory.Cache });
    return path;
  } catch (error) {
    conservations.delete(path);
    await supprimer(path); // No URI was shared: a partial write is safe to remove.
    throw error;
  }
}

/** The chooser result is not a FileProvider read acknowledgement on Android. */
export async function partagerPdfCopieNatif(data: string): Promise<void> {
  const path = await dansCache(() => preparer(data));
  let proposeAuPartage = false;
  try {
    const { uri } = await Filesystem.getUri({ path, directory: Directory.Cache });
    proposeAuPartage = true;
    await Share.share({ url: uri, title: 'Copie du bulletin de paie' });
  } finally {
    if (proposeAuPartage) conserverApresPartage(path);
    else await dansCache(async () => {
      conservations.delete(path);
      await supprimer(path);
    });
  }
}
