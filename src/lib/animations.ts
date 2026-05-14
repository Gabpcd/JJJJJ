/**
 * Animations Y2K Jolene — Sprint 9-D PR 1
 *
 * Presets de timing functions cubic-bezier reproduisant le "spring physics"
 * sans dépendance framer-motion (bundle léger préservé).
 *
 * Pure CSS via Tailwind arbitrary values + classes utilitaires définies
 * dans src/index.css (`.transition-bouncy`, `.transition-soft`, `.transition-snap`).
 *
 * `prefers-reduced-motion: reduce` → transitions désactivées (RGAA AA).
 *
 * Usage :
 *   import { TRANSITIONS, EASINGS } from '@/lib/animations';
 *
 *   <button className="transition-bouncy hover:scale-110">
 *     Click me
 *   </button>
 *
 *   // Ou inline :
 *   <div style={{ transition: `transform ${TRANSITIONS.bouncy}` }}>...</div>
 */

/**
 * Easings cubic-bezier reproduisant des comportements spring.
 * - bouncy : overshoot léger puis stabilisation (animations interactives clés)
 * - soft : lente accélération + décélération (transitions de contexte)
 * - snap : démarrage immédiat, fin nette (toggles, switches)
 */
export const EASINGS = {
  bouncy: 'cubic-bezier(0.34, 1.56, 0.64, 1)',
  soft: 'cubic-bezier(0.4, 0, 0.2, 1)',
  snap: 'cubic-bezier(0.2, 0, 0.13, 1.5)',
} as const;

/**
 * Durations standardisées (en ms).
 */
export const DURATIONS = {
  instant: 100,
  fast: 200,
  base: 300,
  slow: 500,
  slower: 800,
} as const;

/**
 * Compositions prêtes à l'emploi (duration + easing).
 */
export const TRANSITIONS = {
  bouncy: `${DURATIONS.base}ms ${EASINGS.bouncy}`,
  soft: `${DURATIONS.base}ms ${EASINGS.soft}`,
  snap: `${DURATIONS.fast}ms ${EASINGS.snap}`,
  /** Pour animations qui doivent rester subtiles (badges, hover) */
  microInteraction: `${DURATIONS.fast}ms ${EASINGS.soft}`,
} as const;

export type Transition = keyof typeof TRANSITIONS;
