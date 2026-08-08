import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';
import { isNative } from './platform';

const DOCUMENTS_BUCKET = 'jolene-documents';
const SIGNED_URL_TTL_SECONDS = 5 * 60;

function arrayBufferToBase64(buffer: ArrayBuffer): string {
  const bytes = new Uint8Array(buffer);
  const chunkSize = 0x8000;
  let binary = '';
  for (let offset = 0; offset < bytes.length; offset += chunkSize) {
    binary += String.fromCharCode(...bytes.subarray(offset, offset + chunkSize));
  }
  return btoa(binary);
}

async function telechargerPdfOfficiel(url: string, nomFichier: string): Promise<void> {
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`Téléchargement indisponible (${response.status}).`);
  }

  if (!isNative()) {
    const blobUrl = URL.createObjectURL(await response.blob());
    try {
      const anchor = document.createElement('a');
      anchor.href = blobUrl;
      anchor.download = nomFichier;
      anchor.rel = 'noopener';
      document.body.appendChild(anchor);
      anchor.click();
      anchor.remove();
    } finally {
      // Safari peut annuler le téléchargement si l'URL est révoquée dans le
      // même tour d'événement que le clic synthétique.
      window.setTimeout(() => URL.revokeObjectURL(blobUrl), 60_000);
    }
    return;
  }

  try {
    const [{ Filesystem, Directory }, { Share }] = await Promise.all([
      import('@capacitor/filesystem'),
      import('@capacitor/share'),
    ]);
    await Filesystem.writeFile({
      path: nomFichier,
      data: arrayBufferToBase64(await response.arrayBuffer()),
      directory: Directory.Cache,
    });
    const { uri } = await Filesystem.getUri({
      path: nomFichier,
      directory: Directory.Cache,
    });
    await Share.share({ url: uri, title: nomFichier });
  } catch {
    window.open(url, '_blank', 'noopener,noreferrer');
  }
}

/**
 * Télécharge la version PDF immuable effectivement émise et archivée.
 *
 * Une facture déjà émise ne doit jamais être reconstruite depuis les données
 * courantes de la mission : les corrections passent par un avoir, un document
 * de remplacement, un complément ou une rectification liée à l'original.
 */
export async function telechargerFactureHonorairesPDF(factureId: string): Promise<void> {
  try {
    const { data: facture, error: factureError } = await supabase
      .from('factures_honoraires')
      .select('numero_facture, pdf_s3_key')
      .eq('id', factureId)
      .maybeSingle();

    if (factureError) throw factureError;
    if (!facture) throw new Error('Facture introuvable.');
    if (!facture.pdf_s3_key) {
      throw new Error("Le document officiel n'est pas encore émis. Réessaie dans quelques instants.");
    }

    const { data: signed, error: signedError } = await supabase.storage
      .from(DOCUMENTS_BUCKET)
      .createSignedUrl(facture.pdf_s3_key, SIGNED_URL_TTL_SECONDS);
    if (signedError || !signed?.signedUrl) {
      throw signedError || new Error('Lien de téléchargement indisponible.');
    }

    const numero = String(facture.numero_facture || 'facture-honoraires')
      .replace(/[^a-zA-Z0-9._-]+/g, '-');
    await telechargerPdfOfficiel(signed.signedUrl, `${numero}.pdf`);
  } catch (error) {
    const message = error instanceof Error
      ? error.message
      : 'Impossible de télécharger le document officiel.';
    toast.error(message);
  }
}
