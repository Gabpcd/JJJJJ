/**
 * promptParrainage — 7f (Lot 7 v2 §5, niveau 3) : prompts parrainage aux
 * PICS D'ÉMOTION uniquement (après un paiement reçu, après une note 4-5★
 * donnée) — jamais de banner permanent. Throttle global 30 jours : quel que
 * soit le déclencheur, on ne sollicite pas plus d'une fois par mois.
 */
import { toast } from 'sonner';

const CLE = 'jolene_prompt_parrainage_le';
const THROTTLE_JOURS = 30;

export function promptParrainage(message: string): void {
  try {
    const dernier = localStorage.getItem(CLE);
    if (dernier && Date.now() - Number(dernier) < THROTTLE_JOURS * 86_400_000) return;
    localStorage.setItem(CLE, String(Date.now()));
  } catch { /* noop */ }

  toast(message, {
    duration: 8000,
    action: {
      label: 'Parrainer 🎁',
      onClick: () => { window.location.href = '/soignant/parrainage'; },
    },
  });
}
