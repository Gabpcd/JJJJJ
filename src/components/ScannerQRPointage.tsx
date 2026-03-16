import React, { useState, useEffect, useRef, useCallback } from 'react';
import { Camera, X, Loader2 } from 'lucide-react';
import { Html5Qrcode } from 'html5-qrcode';

interface ScannerQRPointageProps {
  type: 'arrivee' | 'depart';
  onCodeScanne: (code: string) => Promise<{ success: boolean; message?: string }>;
}

export function ScannerQRPointage({ type, onCodeScanne }: ScannerQRPointageProps) {
  const [ouvert, setOuvert] = useState(false);
  const [scanning, setScanning] = useState(false);
  const [resultat, setResultat] = useState<{ success: boolean; message?: string } | null>(null);
  const [erreurCamera, setErreurCamera] = useState<string | null>(null);
  const scannerRef = useRef<Html5Qrcode | null>(null);
  const containerId = `qr-reader-${type}`;
  const processingRef = useRef(false);

  const stopScanner = useCallback(async () => {
    if (scannerRef.current) {
      try {
        const state = scannerRef.current.getState();
        if (state === 2) { // SCANNING
          await scannerRef.current.stop();
        }
      } catch {
        // ignore
      }
      scannerRef.current = null;
    }
  }, []);

  const fermer = useCallback(async () => {
    await stopScanner();
    setOuvert(false);
    setScanning(false);
    setErreurCamera(null);
    setResultat(null);
    processingRef.current = false;
  }, [stopScanner]);

  useEffect(() => {
    if (!ouvert) return;

    let cancelled = false;

    const demarrer = async () => {
      setScanning(true);
      setErreurCamera(null);

      try {
        const scanner = new Html5Qrcode(containerId);
        scannerRef.current = scanner;

        await scanner.start(
          { facingMode: 'environment' },
          {
            fps: 10,
            qrbox: { width: 250, height: 250 },
            aspectRatio: 1,
          },
          async (decodedText) => {
            if (cancelled || processingRef.current) return;

            // Validate: must be exactly 6 digits
            const code = decodedText.trim();
            if (!/^\d{6}$/.test(code)) return;

            processingRef.current = true;

            try {
              await stopScanner();
            } catch {
              // ignore
            }

            const result = await onCodeScanne(code);
            setResultat(result);

            if (result.success) {
              setTimeout(() => fermer(), 1500);
            } else {
              processingRef.current = false;
              // Restart scanner after error
              setTimeout(() => {
                if (!cancelled && scannerRef.current === null) {
                  setOuvert(false);
                  setTimeout(() => setOuvert(true), 100);
                }
              }, 2000);
            }
          },
          () => {
            // QR not found in frame — ignore
          }
        );
      } catch (err: any) {
        if (!cancelled) {
          setErreurCamera(
            err?.message?.includes('NotAllowedError')
              ? 'Accès à la caméra refusé. Autorisez l\'accès dans les paramètres de votre navigateur.'
              : err?.message?.includes('NotFoundError')
                ? 'Aucune caméra détectée sur cet appareil.'
                : `Erreur caméra : ${err?.message || 'inconnue'}`
          );
          setScanning(false);
        }
      }
    };

    // Small delay for DOM to be ready
    const timer = setTimeout(demarrer, 200);

    return () => {
      cancelled = true;
      clearTimeout(timer);
      stopScanner();
    };
  }, [ouvert, containerId, onCodeScanne, stopScanner, fermer]);

  const isArrivee = type === 'arrivee';

  if (!ouvert) {
    return (
      <button
        onClick={() => setOuvert(true)}
        className={`w-full py-3 rounded-xl text-sm font-semibold transition-all flex items-center justify-center gap-2 border ${
          isArrivee
            ? 'border-primary/30 text-primary bg-primary/5 hover:bg-primary/10'
            : 'border-muted-foreground/30 text-muted-foreground bg-muted/30 hover:bg-muted/50'
        }`}
      >
        <Camera className="h-4 w-4" />
        📷 Scanner le QR code
      </button>
    );
  }

  return (
    <div className="rounded-xl border border-primary/30 bg-background overflow-hidden">
      {/* Header */}
      <div className="flex items-center justify-between px-3 py-2 bg-primary/5 border-b border-primary/20">
        <p className="text-xs font-semibold text-primary">
          {isArrivee ? '📷 Scanner QR arrivée' : '📷 Scanner QR départ'}
        </p>
        <button onClick={fermer} className="text-muted-foreground hover:text-foreground p-1">
          <X className="h-4 w-4" />
        </button>
      </div>

      {/* Scanner area */}
      <div className="relative">
        <div id={containerId} className="w-full" style={{ minHeight: 280 }} />

        {scanning && !erreurCamera && !resultat && (
          <div className="absolute bottom-2 left-0 right-0 flex justify-center">
            <span className="text-xs bg-background/80 backdrop-blur-sm text-muted-foreground px-3 py-1 rounded-full border border-border">
              Placez le QR code dans le cadre
            </span>
          </div>
        )}

        {erreurCamera && (
          <div className="p-4 text-center">
            <p className="text-sm text-destructive">{erreurCamera}</p>
            <button
              onClick={fermer}
              className="mt-2 text-xs text-primary hover:underline"
            >
              Fermer
            </button>
          </div>
        )}

        {resultat && (
          <div className={`absolute inset-0 flex items-center justify-center ${resultat.success ? 'bg-success/20' : 'bg-destructive/20'} backdrop-blur-sm`}>
            <div className="bg-background rounded-xl p-4 text-center shadow-lg border border-border">
              <p className={`text-2xl mb-1 ${resultat.success ? '' : ''}`}>{resultat.success ? '✅' : '❌'}</p>
              <p className={`text-sm font-semibold ${resultat.success ? 'text-success' : 'text-destructive'}`}>
                {resultat.message || (resultat.success ? 'Pointage réussi !' : 'Échec')}
              </p>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
