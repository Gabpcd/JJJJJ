/**
 * Mascotte cœur Jolene — Sprint 9-B PR 1
 *
 * Cœur arrondi style Y2K Gen Z (charme handmade Tamagotchi/Polly Pocket).
 * Dégradé rose → mauve sur corps, yeux expressifs, blush rose pâle.
 *
 * 5 états émotionnels :
 *  - idle        : neutre, blink subtil
 *  - happy       : sourire, yeux fermés en arc
 *  - thinking    : œil regard de côté, sourire pensif
 *  - celebrating : étoiles autour, bounce
 *  - empty       : yeux fermés tristes, blush effacé
 *
 * Animations : pure CSS via Tailwind + classes définies dans index.css.
 * `prefers-reduced-motion` respecté via @media déjà global (index.css L732).
 *
 * Usage :
 *   <Mascotte etat="celebrating" taille="lg" />
 */
import { useEffect, useState } from 'react';
import { cn } from '@/lib/utils';

export type EtatMascotte = 'idle' | 'happy' | 'thinking' | 'celebrating' | 'empty';
export type TailleMascotte = 'sm' | 'md' | 'lg' | 'xl';

interface Props {
  etat?: EtatMascotte;
  taille?: TailleMascotte;
  /** Si true (défaut), animation au montage + animations d'état. */
  animated?: boolean;
  className?: string;
  /** Texte alternatif pour AT. Default contextualisé selon état. */
  ariaLabel?: string;
}

const TAILLES: Record<TailleMascotte, { box: string; svg: number }> = {
  sm: { box: 'w-12 h-12', svg: 48 },
  md: { box: 'w-20 h-20', svg: 80 },
  lg: { box: 'w-32 h-32', svg: 128 },
  xl: { box: 'w-48 h-48', svg: 192 },
};

const LABELS_ETAT: Record<EtatMascotte, string> = {
  idle: 'Mascotte Jolene',
  happy: 'Mascotte Jolene heureuse',
  thinking: 'Mascotte Jolene réfléchit',
  celebrating: 'Mascotte Jolene célèbre',
  empty: 'Mascotte Jolene état vide',
};

export function Mascotte({
  etat = 'idle',
  taille = 'md',
  animated = true,
  className,
  ariaLabel,
}: Props) {
  const { box, svg } = TAILLES[taille];
  const label = ariaLabel ?? LABELS_ETAT[etat];

  // Blink subtil en idle (toutes les 4s, 150ms fermé)
  const [blinking, setBlinking] = useState(false);
  useEffect(() => {
    if (!animated || etat !== 'idle') return;
    const iv = setInterval(() => {
      setBlinking(true);
      setTimeout(() => setBlinking(false), 150);
    }, 4000);
    return () => clearInterval(iv);
  }, [animated, etat]);

  return (
    <div
      role="img"
      aria-label={label}
      className={cn(
        'relative inline-block',
        box,
        animated && etat === 'celebrating' && 'animate-bounce-y2k',
        animated && etat === 'happy' && 'animate-wiggle-y2k',
        animated && etat === 'idle' && 'animate-float-y2k',
        className,
      )}
    >
      <svg
        viewBox="0 0 100 100"
        width={svg}
        height={svg}
        fill="none"
        xmlns="http://www.w3.org/2000/svg"
        className="overflow-visible"
      >
        <defs>
          <linearGradient id="mascotte-corps" x1="0" y1="0" x2="1" y2="1">
            <stop offset="0%" stopColor="#FF6BBE" />
            <stop offset="100%" stopColor="#B57EFF" />
          </linearGradient>
          <radialGradient id="mascotte-blush" cx="0.5" cy="0.5" r="0.5">
            <stop offset="0%" stopColor="#FF6BBE" stopOpacity="0.55" />
            <stop offset="100%" stopColor="#FF6BBE" stopOpacity="0" />
          </radialGradient>
        </defs>

        {/* Étoiles celebrating */}
        {etat === 'celebrating' && (
          <g className={animated ? 'animate-spin-slow-y2k' : undefined} style={{ transformOrigin: '50px 50px' }}>
            <Star cx={12} cy={20} size={3} color="#FFE066" />
            <Star cx={88} cy={28} size={4} color="#6FE5FF" />
            <Star cx={20} cy={82} size={3.5} color="#B57EFF" />
            <Star cx={85} cy={78} size={3} color="#FF6BBE" />
          </g>
        )}

        {/* Corps en cœur arrondi Y2K */}
        <path
          d="M50 88 C18 65, 8 38, 25 22 C36 12, 48 18, 50 28 C52 18, 64 12, 75 22 C92 38, 82 65, 50 88 Z"
          fill="url(#mascotte-corps)"
          stroke="#2B1B3D"
          strokeWidth="1.5"
          strokeLinejoin="round"
        />

        {/* Blush (joues) — masqué si empty */}
        {etat !== 'empty' && (
          <>
            <circle cx="33" cy="55" r="6" fill="url(#mascotte-blush)" />
            <circle cx="67" cy="55" r="6" fill="url(#mascotte-blush)" />
          </>
        )}

        {/* Yeux selon état */}
        <Yeux etat={etat} blinking={blinking} />

        {/* Bouche selon état */}
        <Bouche etat={etat} />
      </svg>
    </div>
  );
}

// ─── Sous-composants ─────────────────────────────────────────────────────────

function Yeux({ etat, blinking }: { etat: EtatMascotte; blinking: boolean }) {
  // Position de base : œil gauche (40,45) œil droit (60,45)
  if (etat === 'happy' || etat === 'empty' || blinking) {
    // Yeux fermés en arc
    return (
      <>
        <path d="M36 47 Q40 43 44 47" stroke="#2B1B3D" strokeWidth="1.8" strokeLinecap="round" fill="none" />
        <path d="M56 47 Q60 43 64 47" stroke="#2B1B3D" strokeWidth="1.8" strokeLinecap="round" fill="none" />
      </>
    );
  }

  if (etat === 'thinking') {
    // Yeux regardent à droite
    return (
      <>
        <circle cx="40" cy="45" r="3.5" fill="#FFFAFF" stroke="#2B1B3D" strokeWidth="1.2" />
        <circle cx="42" cy="45" r="2" fill="#2B1B3D" />
        <circle cx="60" cy="45" r="3.5" fill="#FFFAFF" stroke="#2B1B3D" strokeWidth="1.2" />
        <circle cx="62" cy="45" r="2" fill="#2B1B3D" />
      </>
    );
  }

  // idle, celebrating — yeux ouverts neutres avec petit highlight
  return (
    <>
      <circle cx="40" cy="45" r="3.5" fill="#FFFAFF" stroke="#2B1B3D" strokeWidth="1.2" />
      <circle cx="40" cy="45.5" r="2" fill="#2B1B3D" />
      <circle cx="40.7" cy="44.5" r="0.6" fill="#FFFAFF" />
      <circle cx="60" cy="45" r="3.5" fill="#FFFAFF" stroke="#2B1B3D" strokeWidth="1.2" />
      <circle cx="60" cy="45.5" r="2" fill="#2B1B3D" />
      <circle cx="60.7" cy="44.5" r="0.6" fill="#FFFAFF" />
    </>
  );
}

function Bouche({ etat }: { etat: EtatMascotte }) {
  if (etat === 'happy' || etat === 'celebrating') {
    return <path d="M44 63 Q50 70 56 63" stroke="#2B1B3D" strokeWidth="1.8" strokeLinecap="round" fill="none" />;
  }
  if (etat === 'thinking') {
    return <path d="M45 65 Q50 63 55 65" stroke="#2B1B3D" strokeWidth="1.8" strokeLinecap="round" fill="none" />;
  }
  if (etat === 'empty') {
    return <path d="M44 67 Q50 63 56 67" stroke="#2B1B3D" strokeWidth="1.8" strokeLinecap="round" fill="none" />;
  }
  // idle
  return <ellipse cx="50" cy="64" rx="3" ry="2" fill="#2B1B3D" />;
}

function Star({ cx, cy, size, color }: { cx: number; cy: number; size: number; color: string }) {
  const p = `M${cx} ${cy - size} L${cx + size * 0.3} ${cy - size * 0.3} L${cx + size} ${cy} L${cx + size * 0.3} ${cy + size * 0.3} L${cx} ${cy + size} L${cx - size * 0.3} ${cy + size * 0.3} L${cx - size} ${cy} L${cx - size * 0.3} ${cy - size * 0.3} Z`;
  return <path d={p} fill={color} />;
}

export default Mascotte;
