/**
 * CelebrationMatch — Sprint 13-C PR 3
 *
 * Modal célébration plein écran déclenchée quand une candidature swipe
 * est acceptée par l'établissement. Mascotte celebrating + confettis +
 * gradient holographique.
 *
 * Style Y2K : gradient hero rose-mauve-cyan, glassmorphism modal.
 * Auto-close 8s si pas d'interaction.
 */
import { useEffect } from 'react';
import { Heart, MessageCircle, Sparkles } from 'lucide-react';
import { Mascotte } from '@/components/mascotte/Mascotte';
import { ConfettiSwipe } from './ConfettiSwipe';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { cn } from '@/lib/utils';

interface Props {
  open: boolean;
  missionTitre: string;
  etablissementNom: string;
  onClose: () => void;
  onVoirConversation?: () => void;
  onSigner?: () => void;
}

export function CelebrationMatch({
  open,
  missionTitre,
  etablissementNom,
  onClose,
  onVoirConversation,
  onSigner,
}: Props) {
  // Auto-close 8s si pas d'interaction
  useEffect(() => {
    if (!open) return;
    const t = setTimeout(onClose, 8000);
    return () => clearTimeout(t);
  }, [open, onClose]);

  if (!open) return null;

  return (
    <div
      className={cn(
        'fixed inset-0 z-50 flex items-center justify-center p-4',
        'bg-jolene-midnight/60 backdrop-blur-md',
        'animate-in fade-in duration-300',
      )}
      role="dialog"
      aria-modal="true"
      aria-labelledby="celebration-match-title"
    >
      <ConfettiSwipe count={60} />

      <div
        className={cn(
          'relative w-full max-w-md rounded-3xl overflow-hidden',
          'bg-gradient-hero shadow-holographic',
          'border-4 border-white/40',
          'animate-in zoom-in-95 duration-500',
        )}
      >
        <div
          className="absolute inset-0 pointer-events-none opacity-60"
          style={{
            background:
              'radial-gradient(circle at 50% 30%, hsla(0, 0%, 100%, 0.4) 0%, transparent 60%)',
          }}
          aria-hidden="true"
        />

        <div className="relative px-6 pt-8 pb-6 flex flex-col items-center text-center text-white">
          <Mascotte etat="celebrating" taille="xl" className="mb-4" />

          <p className="flex items-center gap-2 text-sm font-semibold uppercase tracking-wider text-white/90">
            <Sparkles className="h-4 w-4 fill-current" aria-hidden="true" />
            C'est un match !
            <Sparkles className="h-4 w-4 fill-current" aria-hidden="true" />
          </p>

          <h2 id="celebration-match-title" className="text-3xl font-extrabold mt-2 leading-tight">
            Bravo, tu es pris·e !
          </h2>

          <p className="mt-3 text-white/95">
            <strong className="font-semibold">{etablissementNom}</strong> a accepté ta
            candidature pour
          </p>
          <p className="mt-1 font-semibold text-lg">{missionTitre}</p>

          <div className="mt-6 w-full flex flex-col gap-2">
            {onSigner && (
              <BoutonY2K
                variant="secondary"
                onClick={onSigner}
                iconeGauche={<Heart className="h-4 w-4 fill-current" />}
                className="w-full"
              >
                Signer le contrat
              </BoutonY2K>
            )}
            {onVoirConversation && (
              <BoutonY2K
                variant="ghost"
                onClick={onVoirConversation}
                iconeGauche={<MessageCircle className="h-4 w-4" />}
                className="w-full text-white hover:bg-white/20"
              >
                Voir la conversation
              </BoutonY2K>
            )}
            <button
              type="button"
              onClick={onClose}
              className="mt-2 text-sm text-white/80 hover:text-white underline"
              aria-label="Fermer la célébration"
            >
              Plus tard
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

export default CelebrationMatch;
