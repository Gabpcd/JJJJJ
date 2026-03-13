import React, { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { ChevronLeft, ChevronRight } from 'lucide-react';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { fetchEtablissementsSafe } from '@/lib/etablissements';
import {
  format, startOfMonth, endOfMonth, startOfWeek, endOfWeek,
  addMonths, addDays, isSameMonth, isSameDay, isToday
} from 'date-fns';
import { fr } from 'date-fns/locale';

const JOURS_SEMAINE = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];

function getStatutClasses(statut: string) {
  switch (statut) {
    case 'ASSIGNEE': return 'bg-info text-info-foreground';
    case 'EN_COURS': return 'bg-success text-success-foreground';
    case 'TERMINEE': return 'bg-muted-foreground/40 text-foreground';
    case 'ANNULEE': return 'bg-destructive text-destructive-foreground';
    default: return 'bg-muted text-muted-foreground';
  }
}

export function CalendrierMensuel() {
  const navigate = useNavigate();
  const { user } = useAuth();
  const [moisCourant, setMoisCourant] = useState(new Date());
  const [missions, setMissions] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);

  const debutMois = startOfMonth(moisCourant);
  const finMois = endOfMonth(moisCourant);
  const debutGrille = startOfWeek(debutMois, { weekStartsOn: 1 });
  const finGrille = endOfWeek(finMois, { weekStartsOn: 1 });

  // Build array of days for the grid
  const jours: Date[] = [];
  let jour = debutGrille;
  while (jour <= finGrille) {
    jours.push(jour);
    jour = addDays(jour, 1);
  }

  useEffect(() => {
    if (!user) return;
    setLoading(true);
    supabase
      .from('missions')
      .select('id, intitule, debut_le, fin_le, statut, etablissement_id, service')
      .eq('soignant_assigne_id', user.id)
      .in('statut', ['ASSIGNEE', 'EN_COURS', 'TERMINEE', 'ANNULEE_PAR_ETABLISSEMENT', 'ANNULEE_PAR_SOIGNANT'])
      .gte('fin_le', debutGrille.toISOString())
      .lte('debut_le', finGrille.toISOString())
      .order('debut_le')
      .then(async ({ data }) => {
        const items = data || [];
        if (items.length > 0) {
          const etabMap = await fetchEtablissementsSafe(items.map((m: any) => m.etablissement_id));
          items.forEach((m: any) => { m.etablissements = etabMap[m.etablissement_id] || null; });
        }
        setMissions(items);
        setLoading(false);
      });
  }, [user, moisCourant]);

  function getMissionsDuJour(d: Date) {
    return missions.filter(m => isSameDay(new Date(m.debut_le), d));
  }

  return (
    <div className="card-base">
      {/* Header navigation */}
      <div className="flex items-center justify-between mb-4">
        <button onClick={() => setMoisCourant(addMonths(moisCourant, -1))} className="p-1.5 hover:bg-muted rounded-lg transition-colors">
          <ChevronLeft className="h-5 w-5 text-muted-foreground" />
        </button>
        <div className="text-center">
          <h3 className="text-base font-bold text-foreground capitalize">
            {format(moisCourant, 'MMMM yyyy', { locale: fr })}
          </h3>
        </div>
        <button onClick={() => setMoisCourant(addMonths(moisCourant, 1))} className="p-1.5 hover:bg-muted rounded-lg transition-colors">
          <ChevronRight className="h-5 w-5 text-muted-foreground" />
        </button>
      </div>

      <button onClick={() => setMoisCourant(new Date())}
        className="text-xs text-primary font-medium hover:underline mb-3 block mx-auto">
        Aujourd'hui
      </button>

      {/* Légende */}
      <div className="flex flex-wrap gap-3 mb-4 justify-center">
        {[
          { label: 'Assignée', cls: 'bg-info' },
          { label: 'En cours', cls: 'bg-success' },
          { label: 'Terminée', cls: 'bg-muted-foreground/40' },
          { label: 'Annulée', cls: 'bg-destructive' },
        ].map(l => (
          <div key={l.label} className="flex items-center gap-1.5 text-[10px] text-muted-foreground">
            <span className={`w-2.5 h-2.5 rounded-full ${l.cls}`} />
            {l.label}
          </div>
        ))}
      </div>

      {/* Days header */}
      <div className="grid grid-cols-7 gap-px mb-1">
        {JOURS_SEMAINE.map(j => (
          <div key={j} className="text-center text-[11px] font-semibold text-muted-foreground py-1">
            {j}
          </div>
        ))}
      </div>

      {/* Calendar grid */}
      <div className="grid grid-cols-7 gap-px">
        {jours.map((d, i) => {
          const dansLeMois = isSameMonth(d, moisCourant);
          const estAujourdhui = isToday(d);
          const msDuJour = getMissionsDuJour(d);

          return (
            <div key={i} className={`min-h-[72px] p-1 rounded-md border transition-colors
              ${dansLeMois ? 'bg-card border-border/50' : 'bg-muted/30 border-transparent'}
              ${estAujourdhui ? 'ring-2 ring-primary/40' : ''}
            `}>
              <span className={`text-[11px] font-medium block text-center mb-0.5
                ${estAujourdhui ? 'text-primary font-bold' : dansLeMois ? 'text-foreground' : 'text-muted-foreground/40'}
              `}>
                {format(d, 'd')}
              </span>

              <div className="space-y-0.5">
                {msDuJour.slice(0, 3).map(m => (
                  <button key={m.id}
                    onClick={() => navigate(`/soignant/missions/${m.id}`)}
                    className={`w-full rounded px-1 py-0.5 text-[8px] leading-tight truncate block text-left transition-opacity hover:opacity-80 ${getStatutClasses(m.statut)}`}
                    title={`${m.intitule} — ${m.etablissements?.nom || ''}`}
                  >
                    {m.intitule}
                  </button>
                ))}
                {msDuJour.length > 3 && (
                  <span className="text-[8px] text-muted-foreground block text-center">+{msDuJour.length - 3}</span>
                )}
              </div>
            </div>
          );
        })}
      </div>

      {loading && (
        <div className="text-center text-xs text-muted-foreground mt-2">Chargement…</div>
      )}
    </div>
  );
}
