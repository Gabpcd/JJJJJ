/**
 * BoutonsActionSwipe — barre d'action du deck de swipe.
 *
 * Sémantique des gestes (décision produit D1/D2, Lot 6c) :
 * - ✕  DISLIKE : passer (la mission ne réapparaît pas dans le deck)
 * - ⭐ FAVORI  : sauvegarder la mission pour y revenir — ILLIMITÉ, aucune
 *   candidature envoyée. (L'ex super-like « candidature prioritaire 5/jour »
 *   est reporté v2 : trigger = médiane candidatures/mission > 3 sur 30 j.)
 * - ❤️ LIKE   : candidature IMMÉDIATE et ferme (undo 5 s côté parent)
 *
 * Haptic feedback web (navigator.vibrate) + natif (Capacitor).
 * Touch targets 56px (au-dessus du minimum 44px pour confort tactile).
 */
import { Heart, Star, X } from 'lucide-react';
import { cn } from '@/lib/utils';
import { hapticImpact } from '@/lib/haptics';

interface Props {
  onDislike: () => void;
  onLike: () => void;
  /** ⭐ Sauvegarder la mission (favoris illimités). */
  onFavori: () => void;
  disabled?: boolean;
}

function vibrate(pattern: number | number[]) {
  if (typeof window === 'undefined') return;
  if ('vibrate' in navigator && typeof navigator.vibrate === 'function') {
    try {
      navigator.vibrate(pattern);
    } catch { /* ignore */ }
  }
}

export function BoutonsActionSwipe({
  onDislike,
  onLike,
  onFavori,
  disabled,
}: Props) {
  const handleDislike = () => {
    vibrate(15);
    void hapticImpact('light');
    onDislike();
  };

  const handleLike = () => {
    vibrate([10, 30, 10]);
    void hapticImpact('medium');
    onLike();
  };

  const handleFavori = () => {
    vibrate(20);
    void hapticImpact('light');
    onFavori();
  };

  return (
    <div className="flex items-center justify-center gap-4 sm:gap-6 px-4 py-3">
      {/* DISLIKE */}
      <button
        type="button"
        onClick={handleDislike}
        disabled={disabled}
        aria-label="Passer cette mission"
        className={cn(
          'group h-14 w-14 sm:h-16 sm:w-16 rounded-full transition-bouncy',
          'bg-jolene-cloud border-2 border-jolene-rose-200',
          'hover:scale-110 hover:border-jolene-rose-400 active:scale-95',
          'motion-reduce:hover:scale-100 motion-reduce:active:scale-100',
          'shadow-md hover:shadow-lg',
          'focus-visible:outline-none focus-visible:ring-4 focus-visible:ring-jolene-rose-300',
          'disabled:opacity-40 disabled:cursor-not-allowed',
          'flex items-center justify-center',
        )}
      >
        <X className="h-7 w-7 sm:h-8 sm:w-8 text-jolene-bubblegum group-hover:text-jolene-rose-700" aria-hidden="true" />
      </button>

      {/* FAVORI — sauvegarder pour y revenir (illimité, pas de badge quota) */}
      <button
        type="button"
        onClick={handleFavori}
        disabled={disabled}
        aria-label="Sauvegarder cette mission pour y revenir"
        className={cn(
          'h-14 w-14 sm:h-16 sm:w-16 rounded-full transition-bouncy',
          'bg-jolene-cloud border-2 border-jolene-butter-400',
          'hover:scale-110 hover:border-jolene-butter-600 active:scale-95',
          'motion-reduce:hover:scale-100 motion-reduce:active:scale-100',
          'shadow-md hover:shadow-lg',
          'focus-visible:outline-none focus-visible:ring-4 focus-visible:ring-jolene-butter-400',
          'disabled:opacity-40 disabled:cursor-not-allowed disabled:hover:scale-100',
          'flex items-center justify-center',
        )}
      >
        <Star className="h-7 w-7 sm:h-8 sm:w-8 text-jolene-butter-600 fill-jolene-butter-400" aria-hidden="true" />
      </button>

      {/* LIKE — candidature immédiate */}
      <button
        type="button"
        onClick={handleLike}
        disabled={disabled}
        aria-label="Postuler à cette mission"
        className={cn(
          'group h-16 w-16 sm:h-20 sm:w-20 rounded-full transition-bouncy',
          'bg-gradient-hero shadow-holographic',
          'hover:scale-110 active:scale-95',
          'motion-reduce:hover:scale-100 motion-reduce:active:scale-100',
          'focus-visible:outline-none focus-visible:ring-4 focus-visible:ring-jolene-rose-400',
          'disabled:opacity-40 disabled:cursor-not-allowed disabled:hover:scale-100',
          'flex items-center justify-center',
        )}
      >
        <Heart className="h-8 w-8 sm:h-10 sm:w-10 text-white fill-white" aria-hidden="true" />
      </button>
    </div>
  );
}

export default BoutonsActionSwipe;
