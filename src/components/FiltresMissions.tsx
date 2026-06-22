import { useState } from 'react';
import { ChevronDown, ChevronUp, Flame } from 'lucide-react';

interface FiltresMissionsProps {
  rayonDefaut: number;
  onFiltreChange: (filtres: FiltresMissionsState) => void;
}

export interface FiltresMissionsState {
  urgentesD_abord: boolean;
  dateDebut: string;
  dateFin: string;
  tauxMin: number;
  rayonKm: number;
  tri: 'date' | 'taux' | 'duree' | 'proximite';
}

export function FiltresMissions({ rayonDefaut, onFiltreChange }: FiltresMissionsProps) {
  const [ouvert, setOuvert] = useState(false);
  const [filtres, setFiltres] = useState<FiltresMissionsState>({
    urgentesD_abord: false,
    dateDebut: '',
    dateFin: '',
    tauxMin: 0,
    rayonKm: rayonDefaut || 30,
    tri: 'date',
  });

  const maj = (patch: Partial<FiltresMissionsState>) => {
    const next = { ...filtres, ...patch };
    setFiltres(next);
    onFiltreChange(next);
  };

  return (
    <div className="mb-4">
      {/* Filtre rapide toujours visible : « Urgentes » en 1 tap, sans ouvrir le
          panneau détaillé (parité avec la recherche avancée). */}
      <div className="flex items-center gap-2 mb-2">
        <button
          type="button"
          onClick={() => maj({ urgentesD_abord: !filtres.urgentesD_abord })}
          aria-pressed={filtres.urgentesD_abord}
          className={`shrink-0 inline-flex items-center gap-1.5 rounded-full px-3.5 py-1.5 text-xs font-semibold transition-snap border ${
            filtres.urgentesD_abord
              ? 'bg-gradient-hero text-white border-transparent shadow-md'
              : 'bg-card text-jolene-bubblegum border-jolene-rose-200 hover:border-jolene-rose-300'
          }`}
        >
          <Flame className="h-3.5 w-3.5" /> Urgentes d'abord
        </button>
        <button
          onClick={() => setOuvert(!ouvert)}
          className="flex items-center gap-1 text-xs text-primary font-medium ml-auto"
        >
          Filtres {ouvert ? <ChevronUp className="h-3.5 w-3.5" /> : <ChevronDown className="h-3.5 w-3.5" />}
        </button>
      </div>

      {ouvert && (
        <div className="card-base p-3 space-y-3">
          {/* Date range */}
          <div className="grid grid-cols-2 gap-2">
            <div>
              <label htmlFor="filtres-missions-date-debut" className="text-[10px] text-muted-foreground">Du</label>
              <input
                id="filtres-missions-date-debut"
                type="date"
                value={filtres.dateDebut}
                onChange={e => maj({ dateDebut: e.target.value })}
                className="input-base text-xs py-1.5"
              />
            </div>
            <div>
              <label htmlFor="filtres-missions-date-fin" className="text-[10px] text-muted-foreground">Au</label>
              <input
                id="filtres-missions-date-fin"
                type="date"
                value={filtres.dateFin}
                onChange={e => maj({ dateFin: e.target.value })}
                className="input-base text-xs py-1.5"
              />
            </div>
          </div>

          {/* Taux min */}
          <div>
            <label htmlFor="filtres-missions-taux-min" className="text-[10px] text-muted-foreground">À partir de {filtres.tauxMin || '—'} €/h</label>
            <input
              id="filtres-missions-taux-min"
              type="range" min={0} max={80} step={5} value={filtres.tauxMin}
              onChange={e => maj({ tauxMin: Number(e.target.value) })}
              className="w-full accent-primary"
            />
          </div>

          {/* Rayon */}
          <div>
            <label htmlFor="filtres-missions-rayon-km" className="text-[10px] text-muted-foreground">Dans un rayon de {filtres.rayonKm} km</label>
            <input
              id="filtres-missions-rayon-km"
              type="range" min={5} max={100} step={5} value={filtres.rayonKm}
              onChange={e => maj({ rayonKm: Number(e.target.value) })}
              className="w-full accent-primary"
            />
          </div>

          {/* Tri */}
          <div>
            <label className="text-[10px] text-muted-foreground">Trier par</label>
            <select value={filtres.tri} onChange={e => maj({ tri: e.target.value as any })} className="input-base text-xs py-1.5">
              <option value="date">Date (prochaines d'abord)</option>
              <option value="taux">Taux horaire (+ élevé)</option>
              <option value="duree">Durée (+ courte)</option>
              <option value="proximite">Proximité (+ proche)</option>
            </select>
          </div>
        </div>
      )}
    </div>
  );
}
