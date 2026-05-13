import { Lock, Unlock } from 'lucide-react';

interface Props {
  /** Mode 'modifiable' ou 'verrouille' */
  mode: 'modifiable' | 'verrouille';
  /** Raison du verrouillage (tooltip si verrouillé) */
  raison?: string;
}

/**
 * Badge indiquant si un champ est modifiable ou verrouillé.
 *
 * Sprint 7 PR 8 — Follow-up §3.2.
 *
 * Affiché à côté du label des champs sensibles dans ModifierMission.
 * Verrouillés selon état mission (candidatures reçues, signature contrat, etc.).
 */
export function BadgeChampImmutable({ mode, raison }: Props) {
  if (mode === 'modifiable') {
    return (
      <span
        className="inline-flex items-center gap-1 text-[10px] px-1.5 py-0.5 rounded-full bg-success/10 text-success font-medium"
        title="Ce champ peut être modifié librement."
      >
        <Unlock className="h-2.5 w-2.5" />
        Modifiable
      </span>
    );
  }

  return (
    <span
      className="inline-flex items-center gap-1 text-[10px] px-1.5 py-0.5 rounded-full bg-warning/10 text-warning font-medium"
      title={raison || 'Ce champ est verrouillé pour préserver les engagements pris (candidatures, contrats signés).'}
    >
      <Lock className="h-2.5 w-2.5" />
      Verrouillé
    </span>
  );
}
