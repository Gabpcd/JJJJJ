import React, { useCallback, useEffect, useId, useMemo, useRef, useState } from 'react';
import { Camera, X } from 'lucide-react';
import { Html5Qrcode } from 'html5-qrcode';

interface ScannerQRPointageProps {
  type: 'arrivee' | 'depart';
  onCodeScanne: (code: string) => Promise<{ success: boolean; message?: string }>;
  open?: boolean;
  onOpenChange?: (open: boolean) => void;
}

export function ScannerQRPointage({ type, onCodeScanne, open, onOpenChange }: ScannerQRPointageProps) {
  const [ouvertInterne, setOuvert] = useState(false);
  const ouvert = open ?? ouvertInterne;
  const [scanning, setScanning] = useState(false);
  const [resultat, setResultat] = useState<{ success: boolean; message?: string } | null>(null);
  const [erreurCamera, setErreurCamera] = useState<string | null>(null);
  const [erreurCode, setErreurCode] = useState<string | null>(null);
  const scannerRef = useRef<Html5Qrcode | null>(null);
  const demarrageRef = useRef<Promise<unknown> | null>(null);
  const processingRef = useRef(false);
  const onCodeScanneRef = useRef(onCodeScanne);
  const onOpenChangeRef = useRef(onOpenChange);
  onCodeScanneRef.current = onCodeScanne;
  onOpenChangeRef.current = onOpenChange;
  const reactId = useId();
  // L'arrivée peut devenir un départ pendant la relecture après pointage.
  // Garder le même lecteur et le même callback de scan pendant cette mutation.
  const containerId = useMemo(() => `qr-reader-${reactId.replace(/[:]/g, '')}`, [reactId]);

  const stopScanner = useCallback(async () => {
    const scanner = scannerRef.current;
    if (!scanner) return;
    const demarrage = demarrageRef.current;
    scannerRef.current = null;
    demarrageRef.current = null;
    try {
      await demarrage;
      if (scanner.getState() === 2) {
        await scanner.stop();
      }
      await scanner.clear();
    } catch {
      // ignore cleanup errors
    }
  }, []);

  const fermer = useCallback(() => {
    processingRef.current = true;
    setOuvert(false);
    onOpenChangeRef.current?.(false);
    setScanning(false);
    setErreurCamera(null);
    setErreurCode(null);
    setResultat(null);
    void stopScanner();
  }, [stopScanner]);

  useEffect(() => {
    if (!ouvert) return;

    let cancelled = false;
    let fermetureTimer: number | undefined;
    processingRef.current = false;

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
      setErreurCode(null);
      setResultat(null);

      try {
        await verifierAccesCamera();
        if (cancelled) return;
        const scanner = new Html5Qrcode(containerId);
        scannerRef.current = scanner;

        const demarrage = scanner.start(
          { facingMode: 'environment' },
          {
            fps: 10,
            qrbox: { width: 250, height: 250 },
            aspectRatio: 1,
          },
          async (decodedText) => {
            if (cancelled || processingRef.current) return;

            const code = decodedText.trim();
            if (!/^\d{6}$/.test(code)) {
              setErreurCode('QR non reconnu. Saisissez le code à 6 chiffres.');
              return;
            }

            processingRef.current = true;
            setErreurCode(null);
            setScanning(false);
            await stopScanner();
            if (cancelled) return;

            const result = await onCodeScanneRef.current(code);
            if (cancelled) return;
            setResultat(result);

            if (result.success) {
              fermetureTimer = window.setTimeout(() => {
                fermer();
              }, 1200);
              return;
            }
          },
          () => {
            // ignore frame misses
          }
        );
        demarrageRef.current = demarrage;
        await demarrage;
      } catch (err: any) {
        if (!cancelled) {
          const message = `${err?.name || ''} ${err?.message || ''}`;
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
      window.clearTimeout(fermetureTimer);
      void stopScanner();
    };
  }, [containerId, fermer, ouvert, stopScanner]);

  const isArrivee = type === 'arrivee';

  if (!ouvert) {
    if (open !== undefined) return null;
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
        <button onClick={fermer} aria-label="Annuler le scan QR" className="p-1 text-muted-foreground hover:text-foreground">
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
            <p role="alert" className="text-sm text-destructive">{erreurCamera}</p>
            <button onClick={fermer} className="mt-2 text-xs text-primary hover:underline">
              Fermer
            </button>
          </div>
        )}

        {erreurCode && <p role="alert" className="p-3 text-sm text-destructive">{erreurCode}</p>}

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
