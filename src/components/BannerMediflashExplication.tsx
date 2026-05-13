import { useState } from 'react';
import { Info, X, ExternalLink } from 'lucide-react';

const STORAGE_KEY = 'mediflash_banner_dismissed';

/**
 * Banner pédagogique pour soignant sur la jurisprudence Mediflash.
 *
 * Sprint 7 PR 4 — Cosmétique P2 §5 audit.
 *
 * Explique pourquoi certaines missions sont en CDD obligatoire selon la
 * jurisprudence (CE 11/02/2025). Dismissible (localStorage).
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
            Certaines missions ne peuvent être proposées qu'en <strong>CDD</strong> selon la
            jurisprudence Mediflash (CE 11/02/2025).{' '}
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
                Jurisprudence Mediflash — pourquoi CDD obligatoire ?
              </h2>
              <button onClick={() => setOuvert(false)} className="p-1 hover:bg-muted rounded-lg" aria-label="Fermer">
                <X className="h-5 w-5" />
              </button>
            </div>

            <div className="space-y-3 text-sm text-muted-foreground">
              <p>
                Le <strong>Conseil d'État</strong> a tranché le <strong>11 février 2025</strong>
                {' '}(arrêt n°488367) que certaines missions intérimaires en hôpital public
                relèvent du <strong>salariat déguisé</strong> et ne peuvent donc pas être
                proposées en mode libéral.
              </p>
              <p className="font-medium text-foreground">Critères concernés :</p>
              <ul className="list-disc list-inside space-y-1 text-xs">
                <li>Hôpital public (HOPITAL_PUBLIC, CENTRE_SANTE)</li>
                <li>Mission ponctuelle avec lien de subordination caractérisé</li>
                <li>Profession permettant le CDD (la plupart)</li>
              </ul>
              <p className="text-xs">
                Jolene applique cette matrice automatiquement : si vous voyez certaines missions
                disparaître quand vous filtrez par "Libéral uniquement", c'est probablement à cause
                de cette règle. Pour ces missions, sélectionnez "CDD" ou "Tous" dans vos préférences.
              </p>
              <a
                href="https://www.conseil-etat.fr/decisions-de-justice"
                target="_blank"
                rel="noopener noreferrer"
                className="text-info hover:underline inline-flex items-center gap-1 text-xs"
              >
                Décisions Conseil d'État <ExternalLink className="h-3 w-3" />
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
