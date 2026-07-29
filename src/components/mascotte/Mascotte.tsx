/**
 * Illustration de marque Jolene.
 *
 * L'API historique `Mascotte` est conservée pour ne pas casser les écrans qui
 * utilisent ses états. Le visuel est désormais toujours l'icône canonique
 * Jolene ; les états ne changent que son mouvement ou son traitement.
 */
import { cn } from '@/lib/utils';
import { LogoJolene } from '@/components/LogoJolene';

export type EtatMascotte = 'idle' | 'happy' | 'thinking' | 'celebrating' | 'empty';
export type TailleMascotte = 'sm' | 'md' | 'lg' | 'xl';

interface Props {
  etat?: EtatMascotte;
  taille?: TailleMascotte;
  /** Si true (défaut), applique les animations d'état. */
  animated?: boolean;
  className?: string;
  /** Texte alternatif pour les technologies d'assistance. */
  ariaLabel?: string;
}

const TAILLES: Record<TailleMascotte, { box: string; image: string }> = {
  sm: { box: 'h-12 w-12', image: 'h-12 w-12' },
  md: { box: 'h-20 w-20', image: 'h-20 w-20' },
  lg: { box: 'h-32 w-32', image: 'h-32 w-32' },
  xl: { box: 'h-48 w-48', image: 'h-48 w-48' },
};

const LABELS_ETAT: Record<EtatMascotte, string> = {
  idle: 'Logo Jolene',
  happy: 'Logo Jolene, succès',
  thinking: 'Logo Jolene, traitement en cours',
  celebrating: 'Logo Jolene, célébration',
  empty: 'Logo Jolene, aucun élément',
};

export function Mascotte({
  etat = 'idle',
  taille = 'md',
  animated = true,
  className,
  ariaLabel,
}: Props) {
  const { box, image } = TAILLES[taille];

  return (
    <div
      role="img"
      aria-label={ariaLabel ?? LABELS_ETAT[etat]}
      className={cn(
        'relative inline-flex items-center justify-center',
        box,
        animated && etat === 'celebrating' && 'animate-bounce-y2k',
        animated && etat === 'happy' && 'animate-wiggle-y2k',
        animated && etat === 'idle' && 'animate-float-y2k',
        className,
      )}
    >
      <LogoJolene
        afficherNom={false}
        decoratif
        imageClassName={cn(
          image,
          'shadow-lg transition-[filter,opacity,transform] duration-300',
          etat === 'happy' && 'saturate-125',
          etat === 'thinking' && '-rotate-2',
          etat === 'empty' && 'grayscale opacity-60',
        )}
      />

      {etat === 'celebrating' && (
        <svg
          viewBox="0 0 100 100"
          aria-hidden="true"
          className={cn(
            'pointer-events-none absolute -inset-2 h-[calc(100%+1rem)] w-[calc(100%+1rem)] overflow-visible',
            animated && 'animate-spin-slow-y2k',
          )}
        >
          <Star cx={8} cy={16} size={3} color="#FFE066" />
          <Star cx={92} cy={24} size={4} color="#6FE5FF" />
          <Star cx={17} cy={88} size={3.5} color="#B57EFF" />
          <Star cx={89} cy={84} size={3} color="#FF6BBE" />
        </svg>
      )}
    </div>
  );
}

function Star({
  cx,
  cy,
  size,
  color,
}: {
  cx: number;
  cy: number;
  size: number;
  color: string;
}) {
  const path = [
    `M${cx} ${cy - size}`,
    `L${cx + size * 0.3} ${cy - size * 0.3}`,
    `L${cx + size} ${cy}`,
    `L${cx + size * 0.3} ${cy + size * 0.3}`,
    `L${cx} ${cy + size}`,
    `L${cx - size * 0.3} ${cy + size * 0.3}`,
    `L${cx - size} ${cy}`,
    `L${cx - size * 0.3} ${cy - size * 0.3}`,
    'Z',
  ].join(' ');

  return <path d={path} fill={color} />;
}

export default Mascotte;
