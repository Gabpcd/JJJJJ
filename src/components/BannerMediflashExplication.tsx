import { useState } from 'react';
import { Info, X, ExternalLink } from 'lucide-react';

const STORAGE_KEY = 'mediflash_banner_dismissed';

/**
 * Banner pédagogique pour soignant sur la jurisprudence Mediflash.
 *
 * Sprint 7 PR 4 — Cosmétique P2 §5 audit.
 *
 * Explique la distinction entre la décision CE sur les aides-soignants et la
 * matrice mission × établissement. Dismissible (localStorage).
 */
export function BannerMediflashExplication() {
  const [ouvert, setOuvert] = useState(false);
  const [dismissed, setDismissed] = useState(() => {
    if (typeof window === 'undefined') return false;
    return localStorage.getItem(STORAGE_KEY) === 'true';
  });

  if (dismissed) return null;

  function dismiss() {
    localStorage.setItem(STORAGE_KEY, 'true');
    setDismissed(true);
  }

  return (
    <>
      <div className="w-full rounded-xl border border-info/40 bg-info/5 p-3 mb-4 flex items-start gap-3">
        <Info className="h-4 w-4 text-info shrink-0 mt-0.5" />
        <div className="flex-1 min-w-0">
          <p className="text-xs text-foreground">
            Le mode d'exercice est défini pour chaque mission selon la profession demandée
            et l'établissement.{' '}
            <button
              type="button"
              onClick={() => setOuvert(true)}
              className="text-info underline hover:no-underline"
            >
              En savoir plus
            </button>
          </p>
        </div>
        <button
          type="button"
          onClick={dismiss}
          className="text-muted-foreground hover:text-foreground"
          aria-label="Masquer définitivement"
        >
          <X className="h-3 w-3" />
        </button>
      </div>

      {ouvert && (
        <div className="fixed inset-0 z-50 bg-black/50 flex items-center justify-center p-4" onClick={() => setOuvert(false)}>
          <div
            className="bg-card border border-border rounded-2xl max-w-lg w-full p-6 space-y-3"
            onClick={(e) => e.stopPropagation()}
            role="dialog"
            aria-labelledby="mediflash-titre"
          >
            <div className="flex items-center justify-between">
              <h2 id="mediflash-titre" className="text-lg font-bold text-foreground">
                Comment le mode contractuel est-il déterminé ?
              </h2>
              <button onClick={() => setOuvert(false)} className="p-1 hover:bg-muted rounded-lg" aria-label="Fermer">
                <X className="h-5 w-5" />
              </button>
            </div>

            <div className="space-y-3 text-sm text-muted-foreground">
              <p>
                Le <strong>Conseil d'État</strong> a tranché le <strong>11 février 2025</strong>
                {' '}(arrêt <strong>n°491128</strong>) le cas des aides-soignants exerçant en
                établissement sanitaire, social ou médico-social : ils sont placés sous l'autorité
                et le contrôle de l'établissement. L'arrêt ne juge pas les autres professions.
              </p>
              <p className="text-xs">
                Jolene applique une matrice sourcée à la <strong>profession demandée par la mission</strong>,
                jamais aux seuls diplômes du profil. Une IADE peut donc candidater à une mission IDE,
                qui suit les règles IDE. Pour chaque restriction, la source exacte est affichée dans
                le formulaire de publication.
              </p>
              <p className="text-xs font-medium text-foreground">
                Pour les infirmiers, l'expérience salariée éligible peut compter dans les conditions
                conventionnelles d'installation ou de remplacement en libéral. La CPAM vérifie la
                nature, la durée et la période de cette expérience.
              </p>
              <a
                href="https://www.legifrance.gouv.fr/ceta/id/CETATEXT000051156546"
                target="_blank"
                rel="noopener noreferrer"
                className="text-info hover:underline inline-flex items-center gap-1 text-xs"
              >
                Lire l'arrêt n°491128 sur Légifrance <ExternalLink className="h-3 w-3" />
              </a>
            </div>

            <div className="flex gap-2 pt-2">
              <button onClick={() => setOuvert(false)} className="btn-secondary flex-1">Fermer</button>
              <button onClick={() => { setOuvert(false); dismiss(); }} className="btn-primary flex-1">
                Compris, ne plus afficher
              </button>
            </div>
          </div>
        </div>
      )}
    </>
  );
}
