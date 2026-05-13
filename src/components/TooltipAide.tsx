import { useState, useRef, useEffect } from 'react';
import { HelpCircle } from 'lucide-react';

interface Props {
  /** Texte d'aide affiché au survol/clic */
  contenu: string;
  /** Position du tooltip relativement à l'icône (default 'top') */
  position?: 'top' | 'bottom' | 'left' | 'right';
  /** Taille de l'icône (default 14) */
  size?: number;
  /** Classe CSS additionnelle pour l'icône */
  className?: string;
}

/**
 * Tooltip contextuel d'aide affiché au clic / focus.
 *
 * Sprint 6 PR 5 — Fix P1-1 audit Sprint 5 (tooltips sur champs critiques).
 *
 * Accessible : clic ou focus clavier, fermeture via Escape ou clic extérieur.
 * Mobile-friendly : tap au lieu de hover.
 */
export function TooltipAide({ contenu, position = 'top', size = 14, className = '' }: Props) {
  const [ouvert, setOuvert] = useState(false);
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!ouvert) return;
    function onClick(e: MouseEvent) {
      if (ref.current && !ref.current.contains(e.target as Node)) {
        setOuvert(false);
      }
    }
    function onEscape(e: KeyboardEvent) {
      if (e.key === 'Escape') setOuvert(false);
    }
    document.addEventListener('mousedown', onClick);
    document.addEventListener('keydown', onEscape);
    return () => {
      document.removeEventListener('mousedown', onClick);
      document.removeEventListener('keydown', onEscape);
    };
  }, [ouvert]);

  const positionClasses = {
    top: 'bottom-full mb-2 left-1/2 -translate-x-1/2',
    bottom: 'top-full mt-2 left-1/2 -translate-x-1/2',
    left: 'right-full mr-2 top-1/2 -translate-y-1/2',
    right: 'left-full ml-2 top-1/2 -translate-y-1/2',
  };

  return (
    <div ref={ref} className="relative inline-block">
      <button
        type="button"
        onClick={() => setOuvert((o) => !o)}
        onFocus={() => setOuvert(true)}
        onBlur={() => setTimeout(() => setOuvert(false), 200)}
        className={`text-muted-foreground hover:text-primary transition-colors ${className}`}
        aria-label="Afficher l'aide"
        aria-expanded={ouvert}
      >
        <HelpCircle style={{ width: size, height: size }} />
      </button>
      {ouvert && (
        <div
          role="tooltip"
          className={`absolute z-50 ${positionClasses[position]} w-64 rounded-lg bg-foreground text-background text-xs p-3 shadow-lg leading-relaxed`}
        >
          {contenu}
        </div>
      )}
    </div>
  );
}
