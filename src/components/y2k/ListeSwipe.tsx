/**
 * ListeSwipe — Sprint 9-C PR 2
 *
 * Liste horizontale swipeable avec snap natif CSS + indicateurs dots.
 *
 * Implémentation pure CSS scroll-snap (pas de dep externe type embla/swiper)
 * pour rester léger. Détection scroll via IntersectionObserver pour les dots.
 *
 * Usage :
 *   <ListeSwipe titre="Missions ouvertes" voirToutHref="/missions">
 *     {missions.map(m => <CarteMission key={m.id} mission={m} />)}
 *   </ListeSwipe>
 *
 * - Mobile : 1 item visible, snap au swipe
 * - Desktop : layout naturel (scroll horizontal libre, dots visibles si overflow)
 * - A11y : aria-roledescription="carousel" + boutons précédent/suivant accessibles
 */
import { useEffect, useRef, useState, Children, isValidElement } from 'react';
import { ChevronRight, ChevronLeft } from 'lucide-react';
import { Link } from 'react-router-dom';
import { cn } from '@/lib/utils';

interface Props {
  /** Titre optionnel au-dessus de la liste */
  titre?: string;
  /** Lien "Voir tout" optionnel à droite du titre */
  voirToutHref?: string;
  voirToutLabel?: string;
  /** Affiche les boutons prev/next desktop si overflow */
  boutonsNav?: boolean;
  /** Affiche les dots indicateur */
  dots?: boolean;
  className?: string;
  children: React.ReactNode;
}

export function ListeSwipe({
  titre,
  voirToutHref,
  voirToutLabel = 'Voir tout',
  boutonsNav = true,
  dots = true,
  className,
  children,
}: Props) {
  const scrollerRef = useRef<HTMLDivElement>(null);
  const [activeIndex, setActiveIndex] = useState(0);
  const items = Children.toArray(children).filter(isValidElement);

  // Détection de l'item actif via scroll + IntersectionObserver
  useEffect(() => {
    const scroller = scrollerRef.current;
    if (!scroller) return;

    const observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting && entry.intersectionRatio > 0.6) {
            const idx = Number((entry.target as HTMLElement).dataset.idx);
            if (!Number.isNaN(idx)) setActiveIndex(idx);
          }
        });
      },
      { root: scroller, threshold: [0.6, 0.9] },
    );

    const children = Array.from(scroller.children) as HTMLElement[];
    children.forEach((c) => observer.observe(c));
    return () => observer.disconnect();
  }, [items.length]);

  const scrollerTo = (idx: number) => {
    const scroller = scrollerRef.current;
    if (!scroller) return;
    const target = scroller.children[idx] as HTMLElement | undefined;
    if (target) {
      scroller.scrollTo({ left: target.offsetLeft - scroller.offsetLeft, behavior: 'smooth' });
    }
  };

  const prev = () => scrollerTo(Math.max(0, activeIndex - 1));
  const next = () => scrollerTo(Math.min(items.length - 1, activeIndex + 1));

  return (
    <section
      className={cn('space-y-3', className)}
      aria-roledescription="carousel"
    >
      {(titre || voirToutHref) && (
        <header className="flex items-center justify-between gap-3 px-4 sm:px-0">
          {titre && (
            <h3 className="text-base font-semibold text-jolene-midnight">{titre}</h3>
          )}
          <div className="flex items-center gap-2">
            {boutonsNav && items.length > 1 && (
              <div className="hidden sm:flex items-center gap-1">
                <button
                  type="button"
                  onClick={prev}
                  disabled={activeIndex === 0}
                  aria-label="Précédent"
                  className={cn(
                    'inline-flex items-center justify-center rounded-full p-1.5',
                    'bg-jolene-cloud border border-jolene-rose-200',
                    'hover:bg-jolene-rose-50 disabled:opacity-40 disabled:cursor-not-allowed',
                    'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-jolene-rose',
                  )}
                >
                  <ChevronLeft className="h-4 w-4 text-jolene-rose-700" />
                </button>
                <button
                  type="button"
                  onClick={next}
                  disabled={activeIndex >= items.length - 1}
                  aria-label="Suivant"
                  className={cn(
                    'inline-flex items-center justify-center rounded-full p-1.5',
                    'bg-jolene-cloud border border-jolene-rose-200',
                    'hover:bg-jolene-rose-50 disabled:opacity-40 disabled:cursor-not-allowed',
                    'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-jolene-rose',
                  )}
                >
                  <ChevronRight className="h-4 w-4 text-jolene-rose-700" />
                </button>
              </div>
            )}
            {voirToutHref && (
              <Link
                to={voirToutHref}
                className="inline-flex items-center gap-1 text-xs font-medium text-jolene-rose-700 hover:underline"
              >
                {voirToutLabel} <ChevronRight className="h-3.5 w-3.5" />
              </Link>
            )}
          </div>
        </header>
      )}

      <div
        ref={scrollerRef}
        className={cn(
          'flex gap-3 overflow-x-auto snap-x snap-mandatory',
          'scrollbar-hide -mx-4 px-4 sm:mx-0 sm:px-0',
          'pb-2',
        )}
        role="region"
        aria-label={titre ?? 'Liste swipeable'}
      >
        {items.map((child, i) => (
          <div
            key={i}
            data-idx={i}
            className={cn(
              'snap-start shrink-0',
              'w-[calc(100%-2rem)] sm:w-auto',
            )}
          >
            {child}
          </div>
        ))}
      </div>

      {dots && items.length > 1 && (
        <div className="flex items-center justify-center gap-1.5 sm:hidden" aria-hidden="true">
          {items.map((_, i) => (
            <button
              key={i}
              type="button"
              onClick={() => scrollerTo(i)}
              className={cn(
                'rounded-full transition-all duration-200 motion-reduce:transition-none',
                i === activeIndex
                  ? 'w-6 h-2 bg-jolene-rose'
                  : 'w-2 h-2 bg-jolene-rose-200',
              )}
              tabIndex={-1}
            />
          ))}
        </div>
      )}
    </section>
  );
}

export default ListeSwipe;
