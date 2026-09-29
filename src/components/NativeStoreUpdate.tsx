import { useEffect, useLayoutEffect, useRef, useState } from 'react';
import { Capacitor } from '@capacitor/core';
import { App } from '@capacitor/app';
import { AppUpdate, AppUpdateAvailability } from '@capawesome/capacitor-app-update';
import { Download, X } from 'lucide-react';
import { toast } from 'sonner';
import { Button } from '@/components/ui/button';
import { avecDelai } from '@/lib/avecDelai';
import { signalerVerification, VERIFIER_MISE_A_JOUR } from '@/lib/nativeStoreUpdateEvents';

export { VERIFIER_MISE_A_JOUR } from '@/lib/nativeStoreUpdateEvents';
const APPLE_ID = '6774672845';

/** Native store availability comes from the store, never from a Git commit. */
export function NativeStoreUpdate() {
  const [version, setVersion] = useState<string | null>(null);
  const [ferme, setFerme] = useState(false);
  const [ouverture, setOuverture] = useState(false);
  const panneau = useRef<HTMLElement>(null);
  useLayoutEffect(() => {
    if (version === null || ferme || !panneau.current) return;
    const element = panneau.current;
    const style = document.documentElement.style;
    const espacer = () => style.setProperty('--native-store-toast-bottom', `calc(5.5rem + env(safe-area-inset-bottom) + ${Math.ceil(element.getBoundingClientRect().height) + 12}px)`);
    espacer();
    const observer = typeof ResizeObserver === 'undefined' ? null : new ResizeObserver(espacer);
    observer?.observe(element);
    return () => { observer?.disconnect(); style.removeProperty('--native-store-toast-bottom'); };
  }, [version, ferme]);
  useEffect(() => {
    if (!Capacitor.isNativePlatform()) return;
    let disposed = false;
    let enCours = false;
    let retourManuel = false;
    let derniereVerification = 0;
    const verifier = async (manuel = false) => {
      if (manuel) {
        retourManuel = true;
        signalerVerification(true);
      }
      if (enCours || (!manuel && Date.now() - derniereVerification < 60 * 60_000)) return;
      if (!Capacitor.isPluginAvailable('AppUpdate')) {
        if (retourManuel) signalerVerification(false, 'Consultez le store pour vérifier la version disponible.');
        retourManuel = false;
        return;
      }
      enCours = true;
      derniereVerification = Date.now();
      try {
        const info = await avecDelai(AppUpdate.getAppUpdateInfo({ country: 'FR' }), 8_000);
        if (disposed) return;
        const disponible = info.updateAvailability === AppUpdateAvailability.UPDATE_AVAILABLE;
        setVersion(disponible ? info.availableVersionName || info.availableVersionCode || '' : null);
        if (disponible && retourManuel) setFerme(false);
        if (retourManuel) {
          const message = disponible ? '' : info.updateAvailability === AppUpdateAvailability.UPDATE_NOT_AVAILABLE
            ? 'Jolene est à jour sur cet appareil.'
            : 'La disponibilité de la mise à jour n’a pas pu être confirmée. Réessayez plus tard.';
          signalerVerification(false, message);
        }
      } catch {
        // Failure is not evidence that the installed app is current.
        derniereVerification = Date.now() - 55 * 60_000;
        if (retourManuel && !disposed) signalerVerification(false, 'Impossible de vérifier les mises à jour. Vérifiez votre connexion puis réessayez.');
      } finally { enCours = false; retourManuel = false; }
    };
    const manuel = () => { void verifier(true); };
    window.addEventListener(VERIFIER_MISE_A_JOUR, manuel);
    const listener = App.addListener('appStateChange', ({ isActive }) => { if (isActive) void verifier(); });
    void verifier();
    return () => {
      disposed = true;
      window.removeEventListener(VERIFIER_MISE_A_JOUR, manuel);
      void listener.then(handle => handle.remove()).catch(() => undefined);
    };
  }, []);

  if (version === null || ferme) return null;
  const ouvrirStore = async () => {
    setOuverture(true);
    try { await AppUpdate.openAppStore({ appId: APPLE_ID, androidPackageName: 'app.jolene' }); }
    catch { toast.error('Impossible d’ouvrir le store. Réessayez dans quelques instants.'); }
    finally { setOuverture(false); }
  };
  return (
    <aside ref={panneau} aria-label="Mise à jour de Jolene" className="fixed z-40 left-3 right-3 bottom-[calc(5.5rem+env(safe-area-inset-bottom))] mx-auto max-w-md rounded-2xl border border-primary/20 bg-background p-4 shadow-lg">
      <button type="button" aria-label="Me le rappeler plus tard" onClick={() => setFerme(true)} className="absolute right-1 top-1 flex h-11 w-11 items-center justify-center rounded-full"><X className="h-5 w-5" /></button>
      <p className="pr-10 font-semibold">Une mise à jour est disponible</p>
      <p className="mt-1 pr-5 text-sm text-muted-foreground">Installez la dernière version de Jolene pour profiter des améliorations.</p>
      <Button className="mt-3 min-h-11" disabled={ouverture} onClick={() => { void ouvrirStore(); }}><Download className="mr-2 h-4 w-4" />Mettre à jour</Button>
    </aside>
  );
}
