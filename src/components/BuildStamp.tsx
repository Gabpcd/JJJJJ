/**
 * BuildStamp — tampon de build visible en bas de « Mon compte ».
 *
 * Répond en 2 secondes à « mon merge est-il sur mon téléphone ? » : affiche le
 * SHA court du commit déployé (injecté à la compilation via __APP_VERSION__ =
 * VERCEL_GIT_COMMIT_SHA). Si le SHA affiché ≠ le dernier commit de main, le
 * device sert un build périmé (cache index.html) — cf. vercel.json no-store.
 */
declare const __APP_VERSION__: string;
import { Capacitor } from '@capacitor/core';
import { useEffect, useState } from 'react';
import { RESULTAT_MISE_A_JOUR, VERIFIER_MISE_A_JOUR, type ResultatMiseAJour } from '@/lib/nativeStoreUpdateEvents';

export function BuildStamp() {
  const version = typeof __APP_VERSION__ !== 'undefined' ? __APP_VERSION__ : 'dev-unknown';
  const [verification, setVerification] = useState<ResultatMiseAJour>({ enCours: false, message: '' });
  useEffect(() => {
    const recevoir = (event: Event) => setVerification((event as CustomEvent<ResultatMiseAJour>).detail);
    window.addEventListener(RESULTAT_MISE_A_JOUR, recevoir);
    return () => window.removeEventListener(RESULTAT_MISE_A_JOUR, recevoir);
  }, []);
  return (
    <div className="text-center mt-8 mb-2">
    {Capacitor.isNativePlatform() && <>
      <button type="button" disabled={verification.enCours} className="min-h-11 text-sm text-primary underline disabled:opacity-60" onClick={() => window.dispatchEvent(new Event(VERIFIER_MISE_A_JOUR))}>
        {verification.enCours ? 'Vérification en cours…' : 'Vérifier les mises à jour'}
      </button>
      <p role="status" className="mx-auto max-w-sm text-sm text-muted-foreground">{verification.message}</p>
    </>}
    <p className="text-[10px] text-muted-foreground select-all">
      Jolene · build <span className="font-mono">{version}</span>
    </p>
    </div>
  );
}
