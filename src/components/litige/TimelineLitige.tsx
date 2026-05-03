import React from 'react';
import { CheckCircle2, Circle, Gavel, Users, MessageSquare, Scale } from 'lucide-react';
import type { StatutLitige } from '@/lib/statutLitige';

interface Props {
  statut: string;
}

interface Etape {
  cle: string;
  label: string;
  icon: typeof CheckCircle2;
}

const ETAPES_BASE: Etape[] = [
  { cle: 'OUVERT', label: 'Ouvert', icon: Scale },
  { cle: 'EN_DISCUSSION', label: 'Discussion', icon: MessageSquare },
  { cle: 'MEDIATION', label: 'Médiation', icon: Users },
  { cle: 'RESOLUTION', label: 'Résolution', icon: CheckCircle2 },
];

/** Mappe le statut courant vers une étape de la timeline (0-3) */
function etapeActuelle(statut: string): { idx: number; viaAdmin: boolean } {
  const s = statut as StatutLitige;
  if (s === 'OUVERT') return { idx: 0, viaAdmin: false };
  if (s === 'EN_DISCUSSION') return { idx: 1, viaAdmin: false };
  if (s === 'EN_MEDIATION' || s === 'MEDIATION_EN_COURS') return { idx: 2, viaAdmin: false };
  if (s === 'REVUE_ADMIN') return { idx: 2, viaAdmin: true };
  if (s === 'RESOLU_ACCORD_PARTIES') return { idx: 3, viaAdmin: false };
  if (s === 'RESOLU_FAVEUR_SOIGNANT' || s === 'RESOLU_FAVEUR_ETAB' || s === 'RESOLU_PARTAGE'
      || s === 'RESOLU_ADMIN' || s === 'FERME' || s === 'RESOLU_SOIGNANT' || s === 'RESOLU_ETABLISSEMENT') {
    return { idx: 3, viaAdmin: true };
  }
  return { idx: 0, viaAdmin: false };
}

export function TimelineLitige({ statut }: Props) {
  const { idx: current, viaAdmin } = etapeActuelle(statut);

  return (
    <div className="rounded-xl border border-border bg-muted/30 p-3">
      <div className="flex items-start justify-between gap-2 relative">
        {ETAPES_BASE.map((e, i) => {
          const reached = i <= current;
          const isCurrent = i === current;
          const Icon = e.icon;
          return (
            <div key={e.cle} className="flex-1 flex flex-col items-center text-center relative">
              {i > 0 && (
                <div
                  className={`absolute top-3 -left-1/2 right-1/2 h-0.5 ${i <= current ? 'bg-primary' : 'bg-border'}`}
                  style={{ width: '100%' }}
                />
              )}
              <div className={`relative z-10 h-7 w-7 rounded-full flex items-center justify-center border-2 ${reached ? 'bg-primary text-primary-foreground border-primary' : 'bg-background text-muted-foreground border-border'} ${isCurrent ? 'ring-2 ring-primary/30 ring-offset-2' : ''}`}>
                {reached ? <Icon className="h-3.5 w-3.5" /> : <Circle className="h-2.5 w-2.5" />}
              </div>
              <p className={`text-[11px] font-medium mt-1 ${reached ? 'text-foreground' : 'text-muted-foreground'}`}>
                {e.label}
                {isCurrent && i === 2 && viaAdmin && ' (admin)'}
                {i === 3 && reached && (viaAdmin ? ' (décision)' : ' (accord)')}
              </p>
            </div>
          );
        })}
      </div>
    </div>
  );
}
