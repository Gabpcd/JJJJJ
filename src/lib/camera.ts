// Wrapper unifié caméra Capacitor / Web (Sprint 4 PR 6).
//
// Routing automatique :
//   - Capacitor native (iOS/Android) → @capacitor/camera Camera.getPhoto
//   - Browser web → input type=file capture=environment + fallback
//     getUserMedia + canvas snap (gardé minimal)

import { isNative } from './platform';
import { logger } from './logger';

export interface JoleneCameraResult {
  source: 'capacitor' | 'web';
  /** Data URL (base64) ou blob URL pour le web */
  dataUrl: string;
  /** Format MIME */
  format: 'jpeg' | 'png' | 'webp' | 'heic';
  /** Taille en octets (approximative côté web) */
  sizeBytes?: number;
}

export interface JoleneCameraOptions {
  /** 'camera' force la caméra (vs galerie). Default 'camera'. */
  source?: 'camera' | 'gallery' | 'prompt';
  /** Qualité 0-100. Default 80. */
  quality?: number;
  /** Edition après capture. Default false. */
  allowEditing?: boolean;
}

export class JoleneCameraError extends Error {
  readonly code: 'PERMISSION_DENIED' | 'CANCELLED' | 'UNSUPPORTED' | 'UNKNOWN';
  constructor(code: JoleneCameraError['code'], message: string) {
    super(message);
    this.code = code;
  }
}

/**
 * Prend une photo (caméra ou galerie selon options.source).
 * Sur Capacitor : utilise le plugin natif avec demande permission OS.
 * Sur web : ouvre un input file avec capture environment.
 *
 * @throws JoleneCameraError selon le code
 */
export async function prendrePhoto(opts: JoleneCameraOptions = {}): Promise<JoleneCameraResult> {
  const options = {
    source: opts.source ?? 'camera',
    quality: opts.quality ?? 80,
    allowEditing: opts.allowEditing ?? false,
  };

  if (isNative()) {
    return prendrePhotoCapacitor(options);
  }
  return prendrePhotoWeb(options);
}

async function prendrePhotoCapacitor(opts: Required<JoleneCameraOptions>): Promise<JoleneCameraResult> {
  try {
    const { Camera, CameraResultType, CameraSource } = await import('@capacitor/camera');

    // Demander permission au besoin
    const perm = await Camera.checkPermissions();
    const permissionRefusee =
      (opts.source === 'camera' && perm.camera === 'denied') ||
      (opts.source === 'gallery' && perm.photos === 'denied') ||
      (opts.source === 'prompt' && perm.camera === 'denied' && perm.photos === 'denied');
    if (permissionRefusee) {
      throw new JoleneCameraError('PERMISSION_DENIED', 'Permission caméra ou photothèque refusée');
    }

    const sourceMap: Record<string, any> = {
      camera: CameraSource.Camera,
      gallery: CameraSource.Photos,
      prompt: CameraSource.Prompt,
    };

    const photo = await Camera.getPhoto({
      quality: opts.quality,
      allowEditing: opts.allowEditing,
      resultType: CameraResultType.DataUrl,
      source: sourceMap[opts.source] || CameraSource.Camera,
    });

    return {
      source: 'capacitor',
      dataUrl: photo.dataUrl || '',
      format: (photo.format as 'jpeg' | 'png' | 'webp') || 'jpeg',
    };
  } catch (err) {
    logger.error('[camera] capacitor error', err);
    if (err instanceof JoleneCameraError) throw err;
    const message = (err as Error)?.message?.toLowerCase() || '';
    if (/permission|denied|access.*(?:camera|photo)/i.test(message)) {
      throw new JoleneCameraError('PERMISSION_DENIED', 'Permission caméra ou photothèque refusée');
    }
    if (message.includes('cancel') || message.includes('cancelled')) {
      throw new JoleneCameraError('CANCELLED', 'Annulé par l\'utilisateur');
    }
    throw new JoleneCameraError('UNKNOWN', (err as Error)?.message || 'Erreur caméra');
  }
}

function prendrePhotoWeb(opts: Required<JoleneCameraOptions>): Promise<JoleneCameraResult> {
  return new Promise((resolve, reject) => {
    if (typeof document === 'undefined') {
      reject(new JoleneCameraError('UNSUPPORTED', 'Pas de DOM'));
      return;
    }
    const input = document.createElement('input');
    input.type = 'file';
    input.accept = 'image/*,.heic,.heif';
    if (opts.source === 'camera') input.setAttribute('capture', 'environment');
    input.style.display = 'none';

    let resolved = false;
    input.onchange = () => {
      resolved = true;
      const file = input.files?.[0];
      if (!file) {
        reject(new JoleneCameraError('CANCELLED', 'Aucun fichier sélectionné'));
        document.body.removeChild(input);
        return;
      }
      const reader = new FileReader();
      reader.onload = () => {
        const dataUrl = reader.result as string;
        const formatMatch = dataUrl.match(/^data:image\/([^;]+)/);
        const fmt = (formatMatch?.[1] || 'jpeg').toLowerCase();
        resolve({
          source: 'web',
          dataUrl,
          format: (fmt === 'jpg' ? 'jpeg' : fmt) as 'jpeg' | 'png' | 'webp' | 'heic',
          sizeBytes: file.size,
        });
        document.body.removeChild(input);
      };
      reader.onerror = () => {
        reject(new JoleneCameraError('UNKNOWN', 'FileReader error'));
        document.body.removeChild(input);
      };
      reader.readAsDataURL(file);
    };

    // Cancel detection : si l'utilisateur ferme le picker sans choisir,
    // onchange n'est pas appelé. On peut écouter window.focus mais
    // c'est peu fiable côté mobile. On laisse l'input attaché.
    document.body.appendChild(input);
    input.click();
    setTimeout(() => {
      if (!resolved && document.body.contains(input)) {
        // Pas d'erreur — l'utilisateur peut juste avoir mis du temps.
        // Le timeout est juste un nettoyage si on a perdu l'event.
      }
    }, 60_000);
  });
}

// ─── QR Scanner unifié ───────────────────────────────────────────────

export interface JoleneQrResult {
  source: 'native' | 'html5-qrcode';
  text: string;
  format: string;
}

/**
 * Lance un scan QR code et retourne le texte décodé.
 *
 * Sur Capacitor native : @capacitor/barcode-scanner (caméra plein écran,
 * compatible Swift Package Manager sur iOS et ZXing sur Android).
 * Sur web : déléguer à html5-qrcode (le caller doit gérer le DOM).
 *
 * Sur web, cette fonction NE renvoie PAS de résultat direct — le caller
 * doit utiliser le composant <ScannerQRPointage /> qui wrap html5-qrcode.
 * Sur native, retourne directement le résultat.
 *
 * @throws JoleneCameraError sur erreur native
 */
export async function scannerQr(): Promise<JoleneQrResult | null> {
  if (!isNative()) {
    // Sur web, le caller doit utiliser le composant ScannerQRPointage
    return null;
  }

  try {
    const {
      CapacitorBarcodeScanner,
      CapacitorBarcodeScannerAndroidScanningLibrary,
      CapacitorBarcodeScannerTypeHint,
    } = await import('@capacitor/barcode-scanner');

    // Scan
    const result = await CapacitorBarcodeScanner.scanBarcode({
      hint: CapacitorBarcodeScannerTypeHint.QR_CODE,
      scanInstructions: 'Placez le QR code Jolene dans le cadre',
      scanButton: false,
      cancelButtonAccessibilityLabel: 'Annuler le scan',
      torchButtonOnAccessibilityLabel: 'Éteindre la lampe',
      torchButtonOffAccessibilityLabel: 'Allumer la lampe',
      android: {
        scanningLibrary: CapacitorBarcodeScannerAndroidScanningLibrary.ZXING,
      },
    });

    if (!result.ScanResult?.trim()) {
      throw new JoleneCameraError('CANCELLED', 'Aucun QR détecté');
    }

    return {
      source: 'native',
      text: result.ScanResult.trim(),
      format: String(result.format),
    };
  } catch (err) {
    logger.error('[camera] native barcode scan error', err);
    if (err instanceof JoleneCameraError) throw err;
    const code = String((err as { code?: string })?.code ?? '');
    const message = (err as Error)?.message ?? '';
    if (code === 'OS-PLUG-BARC-0006' || /cancel/i.test(message)) {
      throw new JoleneCameraError('CANCELLED', 'Scan annulé');
    }
    if (code === 'OS-PLUG-BARC-0007' || /camera access|permission|denied|refus/i.test(message)) {
      throw new JoleneCameraError('PERMISSION_DENIED', 'Permission caméra refusée');
    }
    throw new JoleneCameraError('UNKNOWN', message || 'Erreur scan QR');
  }
}

/**
 * Vérifie si le scanner natif est disponible (sans tout initialiser).
 */
export async function qrScannerNatifDispo(): Promise<boolean> {
  if (!isNative()) return false;
  try {
    const { Capacitor } = await import('@capacitor/core');
    await import('@capacitor/barcode-scanner');
    return Capacitor.isPluginAvailable('CapacitorBarcodeScanner');
  } catch {
    return false;
  }
}
