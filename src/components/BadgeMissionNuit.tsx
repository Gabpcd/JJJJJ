import { Moon } from 'lucide-react';

/**
 * Détermine si une mission est "de nuit" au sens de l'art. L3122-2 Code
 * travail (au moins 3h de travail entre 21h et 06h).
 *
 * Mirror exact de la RPC SQL public.fn_mission_est_de_nuit (migration
 * 20260512_pr3_temps_travail_44h_35h.sql).
 */
export function missionEstDeNuit(debut: Date | string | null | undefined, fin: Date | string | null | undefined): boolean {
  if (!debut || !fin) return false;
  const d = typeof debut === 'string' ? new Date(debut) : debut;
  const f = typeof fin === 'string' ? new Date(fin) : fin;
  if (isNaN(d.getTime()) || isNaN(f.getTime())) return false;
  let heuresNuit = 0;
  let cursor = new Date(d);
  while (cursor < f) {
    const cursorEnd = new Date(Math.min(cursor.getTime() + 30 * 60 * 1000, f.getTime()));
    const hour = cursor.getHours();
    if (hour >= 21 || hour < 6) {
      heuresNuit += (cursorEnd.getTime() - cursor.getTime()) / (1000 * 60 * 60);
    }
    cursor = cursorEnd;
  }
  return heuresNuit >= 3;
}

interface Props {
  debut: string | Date | null | undefined;
  fin: string | Date | null | undefined;
  /** Convention collective de l'établissement (texte libre, ex: "CCN FHP IDCC 2264"). */
  conventionCollective?: string | null;
  /** Taille compacte (juste un badge) ou bandeau complet. */
  variant?: 'badge' | 'bandeau';
}

/**
 * Affiche un badge ou bandeau "Mission de nuit" avec rappel des majorations
 * conventionnelles (CCN). Pour info uniquement — le calcul exact de la
 * majoration est fait à la paie par l'établissement.
 *
 * Art. L3122-2 Code travail : tout travail effectué entre 21h et 06h est
 * du travail de nuit. La majoration légale est fixée par la convention
 * collective (souvent 15-25%, parfois plus la nuit profonde).
 */
export function BadgeMissionNuit({ debut, fin, conventionCollective, variant = 'badge' }: Props) {
  if (!missionEstDeNuit(debut, fin)) return null;

  if (variant === 'badge') {
    return (
      <span className="inline-flex items-center gap-1 rounded-full bg-indigo-100 dark:bg-indigo-950/40 text-indigo-700 dark:text-indigo-300 px-2 py-0.5 text-xs font-medium">
        <Moon className="h-3 w-3" aria-hidden="true" />
        Mission de nuit
      </span>
    );
  }

  return (
    <div className="rounded-xl border border-indigo-200 dark:border-indigo-800 bg-indigo-50/60 dark:bg-indigo-950/30 p-3 flex items-start gap-3">
      <Moon className="h-5 w-5 text-indigo-600 dark:text-indigo-400 mt-0.5 shrink-0" />
      <div className="text-sm">
        <p className="font-semibold text-indigo-900 dark:text-indigo-200">Mission de nuit</p>
        <p className="text-xs text-indigo-800 dark:text-indigo-300 mt-1">
          Cette mission comporte au moins 3h de travail entre 21h et 06h
          (art. L3122-2 Code du travail).
          {conventionCollective ? (
            <> Une majoration conventionnelle s'applique selon la <strong>{conventionCollective}</strong> de l'établissement (souvent 15-25 %, parfois plus la nuit profonde).</>
          ) : (
            <> Une majoration conventionnelle s'applique selon la convention collective de l'établissement.</>
          )}
        </p>
      </div>
    </div>
  );
}
