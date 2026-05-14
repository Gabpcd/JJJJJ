import { useState } from 'react';
import { format, startOfMonth, endOfMonth, subMonths, startOfYear } from 'date-fns';
import { fr } from 'date-fns/locale';

interface FiltresPeriodeProps {
  onChange: (debut: Date | null, fin: Date | null, label: string) => void;
}

const OPTIONS = [
  { label: 'Ce mois', value: 'ce_mois' },
  { label: 'Le mois dernier', value: 'mois_dernier' },
  { label: '3 derniers mois', value: '3_mois' },
  { label: 'Cette année', value: 'cette_annee' },
  { label: 'Tout', value: 'tout' },
  { label: 'Période personnalisée', value: 'custom' },
];

export function FiltresPeriode({ onChange }: FiltresPeriodeProps) {
  const [selection, setSelection] = useState('ce_mois');
  const [dateDebut, setDateDebut] = useState('');
  const [dateFin, setDateFin] = useState('');

  function appliquer(val: string) {
    setSelection(val);
    const now = new Date();
    switch (val) {
      case 'ce_mois':
        onChange(startOfMonth(now), endOfMonth(now), format(now, 'MMMM yyyy', { locale: fr }));
        break;
      case 'mois_dernier': {
        const m = subMonths(now, 1);
        onChange(startOfMonth(m), endOfMonth(m), format(m, 'MMMM yyyy', { locale: fr }));
        break;
      }
      case '3_mois':
        onChange(startOfMonth(subMonths(now, 2)), endOfMonth(now), '3 derniers mois');
        break;
      case 'cette_annee':
        onChange(startOfYear(now), endOfMonth(now), `Année ${now.getFullYear()}`);
        break;
      case 'tout':
        onChange(null, null, 'Tout');
        break;
      case 'custom':
        break;
    }
  }

  function appliquerCustom() {
    if (dateDebut && dateFin) {
      onChange(new Date(dateDebut), new Date(dateFin), `${dateDebut} → ${dateFin}`);
    }
  }

  return (
    <div className="flex flex-wrap items-center gap-2 mb-4">
      {OPTIONS.map(o => (
        <button
          key={o.value}
          onClick={() => appliquer(o.value)}
          className={`px-3 py-1.5 rounded-full text-xs font-medium transition-colors ${
            selection === o.value ? 'bg-primary text-primary-foreground' : 'bg-muted text-muted-foreground hover:bg-muted/80'
          }`}
        >
          {o.label}
        </button>
      ))}
      {selection === 'custom' && (
        <div className="flex items-center gap-2 mt-2 w-full">
          <label htmlFor="filtres-periode-debut" className="sr-only">Date de début de la période</label>
          <input
            id="filtres-periode-debut"
            type="date"
            value={dateDebut}
            onChange={e => setDateDebut(e.target.value)}
            className="input-base text-xs flex-1"
          />
          <span aria-hidden="true" className="text-muted-foreground text-xs">→</span>
          <label htmlFor="filtres-periode-fin" className="sr-only">Date de fin de la période</label>
          <input
            id="filtres-periode-fin"
            type="date"
            value={dateFin}
            onChange={e => setDateFin(e.target.value)}
            className="input-base text-xs flex-1"
          />
          <button onClick={appliquerCustom} className="btn-primary text-xs px-3 py-2">OK</button>
        </div>
      )}
    </div>
  );
}
