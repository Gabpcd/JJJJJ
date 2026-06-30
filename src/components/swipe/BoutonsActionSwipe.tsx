/**
 * BoutonsActionSwipe — Sprint 13-B PR 3
 *
 * Boutons d'action fixed-bottom : DISLIKE, LIKE, SUPER_LIKE.
 *
 * - LIKE : icône cœur, gradient rose-mauve primaire
 * - DISLIKE : icône X, ghost variant
 * - SUPER_LIKE : icône étoile, gradient celebrate + compteur quota
 * - Haptic feedback mobile (vibration courte API)
 * - Confetti CSS déclenché sur SUPER_LIKE (animation .animate-confetti-pop)
 *
 * Touch targets 56px (au-dessus du minimum 44px pour confort tactile).
 */
import { Heart, Star, X } from 'lucide-react';
import { cn } from '@/lib/utils';

interface Props {
  onDislike: () => void;
  onLike: () => void;
  onSuperLike: () => void;
  quotaSuperLikeRestant: number | null;
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
  onSuperLike,
  quotaSuperLikeRestant,
  disabled,
}: Props) {
  const superLikeDisabled = disabled || (quotaSuperLikeRestant != null && quotaSuperLikeRestant <= 0);

  const handleDislike = () => {
    vibrate(15);
    onDislike();
  };

  const handleLike = () => {
    vibrate([10, 30, 10]);
    onLike();
  };

  const handleSuperLike = () => {
    if (superLikeDisabled) return;
    vibrate([20, 40, 20, 40, 60]);
    onSuperLike();
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

      {/* SUPER_LIKE */}
      <button
        type="button"
        onClick={handleSuperLike}
        disabled={superLikeDisabled}
        aria-label={
          superLikeDisabled
            ? `Super like indisponible (quota épuisé)`
            : `Super like (${quotaSuperLikeRestant ?? 5} restant${(quotaSuperLikeRestant ?? 5) > 1 ? 's' : ''} aujourd'hui)`
        }
        className={cn(
          'relative h-14 w-14 sm:h-16 sm:w-16 rounded-full transition-bouncy',
          'bg-gradient-celebrate shadow-holographic',
          'hover:scale-110 active:scale-95',
          'motion-reduce:hover:scale-100 motion-reduce:active:scale-100',
          'focus-visible:outline-none focus-visible:ring-4 focus-visible:ring-jolene-butter-400',
          'disabled:opacity-40 disabled:cursor-not-allowed disabled:hover:scale-100',
          'flex items-center justify-center',
        )}
      >
        <Star className="h-7 w-7 sm:h-8 sm:w-8 text-white fill-white" aria-hidden="true" />
        {quotaSuperLikeRestant != null && (
          <span
            className="absolute -top-1 -right-1 bg-jolene-midnight text-white text-[10px] font-bold rounded-full h-5 w-5 flex items-center justify-center border-2 border-jolene-cloud"
            aria-hidden="true"
          >
            {quotaSuperLikeRestant}
          </span>
        )}
      </button>

      {/* LIKE */}
      <button
        type="button"
        onClick={handleLike}
        disabled={disabled}
        aria-label="J'aime cette mission"
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
