import React, { useEffect, useState } from 'react';
import { CalendarDays, Calendar } from 'lucide-react';
import { CalendrierMiniSemaine } from '@/components/CalendrierMiniSemaine';
import { CalendrierMensuel } from '@/components/CalendrierMensuel';

interface Props {
  missionsSemaine: { debut_le: string; statut: string }[];
}

const STORAGE_KEY = 'jolene.dashboard.calendrier_mode';

export function CalendrierTogglable({ missionsSemaine }: Props) {
  const [mode, setMode] = useState<'semaine' | 'mois'>(() => {
    try {
      const v = localStorage.getItem(STORAGE_KEY);
      return v === 'mois' ? 'mois' : 'semaine';
    } catch {
      return 'semaine';
    }
  });

  useEffect(() => {
    try { localStorage.setItem(STORAGE_KEY, mode); } catch { /* noop */ }
  }, [mode]);

  return (
    <div className="mb-6">
      <div className="flex items-center justify-end gap-1 mb-2">
        <button
          type="button"
          onClick={() => setMode('semaine')}
          className={`text-xs px-3 py-1.5 rounded-lg border inline-flex items-center gap-1.5 transition-colors ${mode === 'semaine' ? 'border-primary bg-primary/10 text-primary' : 'border-border text-muted-foreground hover:bg-muted/50'}`}
          aria-pressed={mode === 'semaine'}
        >
          <CalendarDays className="h-3.5 w-3.5" /> Semaine
        </button>
        <button
          type="button"
          onClick={() => setMode('mois')}
          className={`text-xs px-3 py-1.5 rounded-lg border inline-flex items-center gap-1.5 transition-colors ${mode === 'mois' ? 'border-primary bg-primary/10 text-primary' : 'border-border text-muted-foreground hover:bg-muted/50'}`}
          aria-pressed={mode === 'mois'}
        >
          <Calendar className="h-3.5 w-3.5" /> Mois
        </button>
      </div>
      {mode === 'semaine' ? (
        <CalendrierMiniSemaine missions={missionsSemaine} />
      ) : (
        <CalendrierMensuel />
      )}
    </div>
  );
}
