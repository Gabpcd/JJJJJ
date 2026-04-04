import React, { useCallback, useEffect, useId, useMemo, useRef, useState } from 'react';
import { Camera, X } from 'lucide-react';
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
  const processingRef = useRef(false);
  const reactId = useId();
  const containerId = useMemo(() => `qr-reader-${type}-${reactId.replace(/[:]/g, '')}`, [reactId, type]);

  const stopScanner = useCallback(async () => {
    if (!scannerRef.current) return;
    try {
      if (scannerRef.current.getState() === 2) {
        await scannerRef.current.stop();
      }
      await scannerRef.current.clear();
    } catch {
      // ignore cleanup errors
    } finally {
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

    const verifierAccesCamera = async () => {
      if (!navigator.mediaDevices?.getUserMedia) {
        throw new Error('getUserMedia indisponible');
      }

      const stream = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: { ideal: 'environment' } },
        audio: false,
      });
      stream.getTracks().forEach((track) => track.stop());
    };

    const demarrer = async () => {
      if (cancelled) return;
      setScanning(true);
      setErreurCamera(null);
      setResultat(null);

      try {
        await verifierAccesCamera();
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

            const code = decodedText.trim();
            if (!/^\d{6}$/.test(code)) return;

            processingRef.current = true;
            setScanning(false);
            await stopScanner();

            const result = await onCodeScanne(code);
            setResultat(result);

            if (result.success) {
              setTimeout(() => {
                void fermer();
              }, 1200);
              return;
            }

            processingRef.current = false;
          },
          () => {
            // ignore frame misses
          }
        );
      } catch (err: any) {
        if (!cancelled) {
          const message = err?.message || '';
          setErreurCamera(
            message.includes('NotAllowedError')
              ? 'Accès à la caméra refusé. Autorisez l’accès à la caméra puis réessayez.'
              : message.includes('NotFoundError')
                ? 'Aucune caméra détectée sur cet appareil.'
                : 'Impossible d’ouvrir la caméra pour scanner le QR code.'
          );
          setScanning(false);
        }
      }
    };

    const timer = window.setTimeout(() => {
      void demarrer();
    }, 150);

    return () => {
      cancelled = true;
      window.clearTimeout(timer);
      void stopScanner();
    };
  }, [containerId, fermer, onCodeScanne, ouvert, stopScanner]);

  const isArrivee = type === 'arrivee';

  if (!ouvert) {
    return (
      <button
        onClick={() => setOuvert(true)}
        className={`flex w-full items-center justify-center gap-2 rounded-xl border py-3 text-sm font-semibold transition-all ${
          isArrivee
            ? 'border-primary/30 bg-primary/5 text-primary hover:bg-primary/10'
            : 'border-muted-foreground/30 bg-muted/30 text-muted-foreground hover:bg-muted/50'
        }`}
      >
        <Camera className="h-4 w-4" />
        📷 Scanner le QR code
      </button>
    );
  }

  return (
    <div className="overflow-hidden rounded-xl border border-primary/30 bg-background">
      <div className="flex items-center justify-between border-b border-primary/20 bg-primary/5 px-3 py-2">
        <p className="text-xs font-semibold text-primary">
          {isArrivee ? '📷 Scanner QR arrivée' : '📷 Scanner QR départ'}
        </p>
        <button onClick={() => void fermer()} className="p-1 text-muted-foreground hover:text-foreground">
          <X className="h-4 w-4" />
        </button>
      </div>

      <div className="relative">
        <div id={containerId} className="w-full" style={{ minHeight: 280 }} />

        {scanning && !erreurCamera && !resultat && (
          <div className="absolute bottom-2 left-0 right-0 flex justify-center">
            <span className="rounded-full border border-border bg-background/85 px-3 py-1 text-xs text-muted-foreground backdrop-blur-sm">
              Placez le QR code dans le cadre
            </span>
          </div>
        )}

        {erreurCamera && (
          <div className="p-4 text-center">
            <p className="text-sm text-destructive">{erreurCamera}</p>
            <button onClick={() => void fermer()} className="mt-2 text-xs text-primary hover:underline">
              Fermer
            </button>
          </div>
        )}

        {resultat && (
          <div className={`absolute inset-0 flex items-center justify-center backdrop-blur-sm ${resultat.success ? 'bg-success/20' : 'bg-destructive/20'}`}>
            <div className="rounded-xl border border-border bg-background p-4 text-center shadow-lg">
              <p className="mb-1 text-2xl">{resultat.success ? '✅' : '❌'}</p>
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
