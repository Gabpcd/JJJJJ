import { useState, useEffect, useRef } from 'react';
import { Camera, X, Loader2, CheckCircle, AlertCircle } from 'lucide-react';
import { Html5Qrcode } from 'html5-qrcode';
import { supabase } from '@/integrations/supabase/client';
import { useNotification } from '@/contexts/NotificationContext';
import { isNative } from '@/lib/platform';
import { scannerQr, qrScannerNatifDispo } from '@/lib/camera';
import { getCurrentPosition } from '@/lib/geoloc';
import { genererIdTerminal } from '@/lib/terminal';
import { logger } from '@/lib/logger';

interface Props {
  missionId: string;
  /** Callback après pointage validé : methode_detectee = 'ARRIVEE' | 'DEPART' */
  onValide?: (params: { methode_detectee: string; presence_id?: string; horodatage: string }) => void;
  /** Callback si l'utilisateur annule */
  onAnnuler?: () => void;
  /** Callback fallback si caméra indisponible — propose le code de secours */
  onFallbackCode?: () => void;
}

const MESSAGES_ERREUR: Record<string, string> = {
  NON_AUTHENTIFIE: 'Session expirée. Reconnectez-vous puis réessayez.',
  QR_INVALIDE: 'QR non valide ou désactivé. Demandez à l\'établissement de régénérer.',
  QR_EXPIRE: 'Ce QR a expiré. Demandez à l\'établissement de régénérer.',
  QR_MISSION_AUTRE: 'Ce QR ne correspond pas à votre mission active.',
  HEURE_TROP_TOT: 'Trop tôt pour pointer.',
  HEURE_TROP_TARD: 'Trop tard pour pointer. Mission terminée depuis plus de 2 heures.',
  DEJA_POINTE: 'Vous avez déjà pointé votre arrivée.',
  DEPART_SANS_ARRIVEE: 'Vous devez d\'abord pointer votre arrivée.',
  DEPART_DEJA_POINTE: 'Vous avez déjà pointé votre départ.',
  DEPART_TROP_RAPIDE: 'Vous ne pouvez pointer votre départ moins de 30 minutes après l\'arrivée.',
};

/**
 * Composant scan QR pointage Sprint 4.5 PR 6.
 *
 * Flow :
 *  1. Demande permission caméra (scanner Capacitor natif ou html5-qrcode web)
 *  2. Ouvre vue caméra avec overlay
 *  3. Au scan : récupère GPS coords en background (non bloquant)
 *  4. Appelle fn_valider_scan_qr(token, lat, lng, precision, terminal_id)
 *  5. Affiche succès ou erreur avec mapping FR des codes
 */
export function ScannerQRPointageSoignant({ missionId, onValide, onAnnuler, onFallbackCode }: Props) {
  const { afficherNotification } = useNotification();
  const [ouvert, setOuvert] = useState(true);
  const [scanning, setScanning] = useState(false);
  const [validating, setValidating] = useState(false);
  const [resultat, setResultat] = useState<{ success: boolean; methode?: string; horodatage?: string; message?: string } | null>(null);
  const [erreurCamera, setErreurCamera] = useState<string | null>(null);
  const scannerWebRef = useRef<Html5Qrcode | null>(null);
  const processingRef = useRef(false);
  const containerId = 'scanner-qr-soignant-container';

  // Lancement scan natif Capacitor
  useEffect(() => {
    if (!isNative()) return;
    let cancelled = false;
    (async () => {
      const dispo = await qrScannerNatifDispo();
      if (!dispo) {
        setErreurCamera('Scanner natif indisponible. Utilisez le code de secours.');
        return;
      }
      try {
        const result = await scannerQr();
        if (cancelled || !result) return;
        await traiterToken(result.text);
      } catch (err: any) {
        const msg = err?.message || 'Erreur scan';
        if (err?.code === 'PERMISSION_DENIED') {
          setErreurCamera('Permission caméra refusée. Utilisez le code de secours.');
        } else if (err?.code === 'CANCELLED') {
          fermer();
        } else {
          setErreurCamera(msg);
        }
      }
    })();
    return () => { cancelled = true; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Lancement scan web html5-qrcode
  useEffect(() => {
    if (isNative()) return; // déjà géré par useEffect natif ci-dessus
    if (!ouvert) return;
    let cancelled = false;

    (async () => {
      try {
        if (!navigator.mediaDevices?.getUserMedia) {
          setErreurCamera('getUserMedia indisponible sur ce navigateur.');
          return;
        }

        await new Promise(r => setTimeout(r, 100));
        if (cancelled) return;

        const scanner = new Html5Qrcode(containerId);
        scannerWebRef.current = scanner;
        setScanning(true);

        await scanner.start(
          { facingMode: 'environment' },
          { fps: 10, qrbox: { width: 250, height: 250 } },
          async (decodedText) => {
            if (processingRef.current) return;
            processingRef.current = true;
            await stopScannerWeb();
            await traiterToken(decodedText);
          },
          () => { /* QR scan errors ignored (continuous) */ },
        );
      } catch (err: any) {
        logger.error('[scan-qr-soignant] init failed', err);
        setErreurCamera(err?.message || 'Caméra indisponible');
      }
    })();

    return () => {
      cancelled = true;
      stopScannerWeb();
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [ouvert]);

  async function stopScannerWeb() {
    if (!scannerWebRef.current) return;
    try {
      if (scannerWebRef.current.getState() === 2) {
        await scannerWebRef.current.stop();
      }
      await scannerWebRef.current.clear();
    } catch { /* ignore */ }
    scannerWebRef.current = null;
  }

  async function fermer() {
    await stopScannerWeb();
    setOuvert(false);
    setScanning(false);
    onAnnuler?.();
  }

  async function traiterToken(token: string) {
    setValidating(true);
    // Position demandée au premier plan pendant le scan, facultative et non bloquante.
    let lat: number | undefined, lng: number | undefined, precision: number | undefined;
    try {
      const pos = await Promise.race([
        getCurrentPosition({ enableHighAccuracy: true, timeout: 5000 }),
        new Promise<null>((resolve) => setTimeout(() => resolve(null), 5000)),
      ]);
      if (pos) {
        lat = pos.coords.latitude;
        lng = pos.coords.longitude;
        precision = pos.coords.accuracy;
      }
    } catch { /* GPS optionnel, on continue sans */ }

    try {
      const { data, error } = await supabase.rpc('fn_valider_scan_qr' as any, {
        p_token: token,
        p_lat: lat ?? null,
        p_lng: lng ?? null,
        p_precision: precision ?? null,
        p_terminal_id: genererIdTerminal(),
      });
      if (error) throw error;
      const result = data as any;
      if (!result?.success) {
        const msg = MESSAGES_ERREUR[result?.error_code] || result?.error || 'Erreur de validation';
        setResultat({ success: false, message: msg });
        return;
      }
      setResultat({
        success: true,
        methode: result.methode_detectee,
        horodatage: result.horodatage,
        message: result.methode_detectee === 'ARRIVEE'
          ? 'Arrivée validée'
          : 'Départ validé',
      });
      afficherNotification({ type: 'succes', message: result.methode_detectee === 'ARRIVEE' ? 'Arrivée pointée ✅' : 'Départ pointé ✅' });
      // Auto-close après 2s
      setTimeout(() => {
        onValide?.({
          methode_detectee: result.methode_detectee,
          presence_id: result.presence_id,
          horodatage: result.horodatage,
        });
        setOuvert(false);
      }, 2000);
    } catch (err: any) {
      setResultat({ success: false, message: err?.message || 'Erreur réseau' });
    } finally {
      setValidating(false);
    }
  }

  if (!ouvert) return null;

  return (
    <div className="fixed inset-0 z-50 bg-black/90 flex flex-col items-center justify-center p-4">
      <button onClick={fermer} className="absolute top-4 right-4 text-white p-2 rounded-full bg-white/10 hover:bg-white/20">
        <X className="h-6 w-6" />
      </button>

      <div className="w-full max-w-md">
        {!resultat && !erreurCamera && (
          <>
            <div className="text-center mb-4">
              <p className="text-white text-lg font-semibold">📲 Scannez le QR de l'établissement</p>
              <p className="text-white/70 text-sm mt-1">Pointez votre caméra vers le QR code Jolene affiché à l'accueil</p>
            </div>

            {!isNative() && (
              <div id={containerId} className="rounded-xl overflow-hidden bg-white aspect-square" />
            )}

            {isNative() && (
              <div className="flex flex-col items-center justify-center bg-white/10 rounded-xl aspect-square">
                <Camera className="h-16 w-16 text-white/40 animate-pulse" />
                <p className="text-white/70 text-sm mt-4">Ouverture caméra native...</p>
              </div>
            )}

            {validating && (
              <div className="mt-4 flex items-center justify-center gap-2 text-white">
                <Loader2 className="h-5 w-5 animate-spin" />
                <span className="text-sm">Validation en cours...</span>
              </div>
            )}
          </>
        )}

        {resultat?.success && (
          <div className="bg-emerald-50 dark:bg-emerald-950/60 border-2 border-emerald-500 rounded-2xl p-8 text-center animate-in zoom-in duration-300">
            <CheckCircle className="h-20 w-20 text-emerald-600 mx-auto mb-4" />
            <p className="text-2xl font-bold text-emerald-900 dark:text-emerald-100">{resultat.message}</p>
            {resultat.horodatage && (
              <p className="text-sm text-emerald-700 dark:text-emerald-300 mt-2 font-mono">
                {new Date(resultat.horodatage).toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' })}
              </p>
            )}
          </div>
        )}

        {resultat && !resultat.success && (
          <div className="bg-destructive/10 border-2 border-destructive rounded-2xl p-6 text-center">
            <AlertCircle className="h-12 w-12 text-destructive mx-auto mb-3" />
            <p className="text-sm font-semibold text-destructive">{resultat.message}</p>
            <div className="flex gap-2 mt-4 justify-center">
              <button onClick={() => { setResultat(null); setOuvert(true); processingRef.current = false; }}
                className="btn-secondary text-sm">
                Réessayer
              </button>
              {onFallbackCode && (
                <button onClick={() => { fermer(); onFallbackCode(); }} className="btn-primary text-sm">
                  Saisir un code de secours
                </button>
              )}
            </div>
          </div>
        )}

        {erreurCamera && (
          <div className="bg-amber-50 dark:bg-amber-950/60 border-2 border-amber-500 rounded-2xl p-6 text-center">
            <Camera className="h-12 w-12 text-amber-600 mx-auto mb-3" />
            <p className="text-sm font-semibold text-amber-900 dark:text-amber-100">{erreurCamera}</p>
            <p className="text-xs text-amber-800 dark:text-amber-300 mt-2">
              Sans la caméra, vous pouvez saisir un code numérique de secours fourni par l'établissement.
            </p>
            <div className="flex gap-2 mt-4 justify-center">
              <button onClick={fermer} className="btn-secondary text-sm">Annuler</button>
              {onFallbackCode && (
                <button onClick={() => { fermer(); onFallbackCode(); }} className="btn-primary text-sm">
                  Saisir un code
                </button>
              )}
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
