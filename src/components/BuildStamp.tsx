/**
 * BuildStamp — tampon de build visible en bas de « Mon compte ».
 *
 * Répond en 2 secondes à « mon merge est-il sur mon téléphone ? » : affiche le
 * SHA court du commit déployé (injecté à la compilation via __APP_VERSION__ =
 * VERCEL_GIT_COMMIT_SHA). Si le SHA affiché ≠ le dernier commit de main, le
 * device sert un build périmé (cache index.html) — cf. vercel.json no-store.
 */
declare const __APP_VERSION__: string;

export function BuildStamp() {
  const version = typeof __APP_VERSION__ !== 'undefined' ? __APP_VERSION__ : 'dev-unknown';
  return (
    <p className="text-center text-[10px] text-muted-foreground/60 mt-8 mb-2 select-all">
      Jolene · build <span className="font-mono">{version}</span>
    </p>
  );
}
