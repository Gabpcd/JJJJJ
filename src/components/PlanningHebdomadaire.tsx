import React, { useState, useEffect } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { ChevronLeft, ChevronRight } from 'lucide-react';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { extraireSerieId } from '@/components/CarteSerie';
import { format, addDays, startOfWeek, isSameDay } from 'date-fns';
import { fr } from 'date-fns/locale';

const HEURE_MIN = 6;
const HEURE_MAX = 30;
const TOTAL_HEURES = HEURE_MAX - HEURE_MIN;

function getStatutCouleur(statut: string) {
  switch (statut) {
    case 'ASSIGNEE': return 'bg-primary/80 border-primary text-primary-foreground';
    case 'EN_COURS': return 'bg-info/80 border-info text-info-foreground';
    case 'TERMINEE': return 'bg-success/80 border-success text-success-foreground';
    default: return 'bg-muted border-border text-foreground';
  }
}

interface PlanningHebdomadaireProps {
  missionCandidate?: any;
}

export function PlanningHebdomadaire({ missionCandidate }: PlanningHebdomadaireProps) {
  const navigate = useNavigate();
  const { user } = useAuth();
  const [searchParams] = useSearchParams();
  const highlightId = searchParams.get('highlight');
  const serieParam = searchParams.get('serie');
  const [semaine, setSemaine] = useState(() => startOfWeek(new Date(), { weekStartsOn: 1 }));
  const [missions, setMissions] = useState<any[]>([]);
  const [serieCandidates, setSerieCandidates] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);

  const jours = Array.from({ length: 7 }, (_, i) => addDays(semaine, i));
  const finSemaine = addDays(semaine, 7);

  useEffect(() => {
    if (!user) return;
    setLoading(true);
    supabase
      .from('missions')
      .select('id, intitule, debut_le, fin_le, duree_heures, statut, etablissements(nom)')
      .eq('soignant_assigne_id', user.id)
      .in('statut', ['ASSIGNEE', 'EN_COURS', 'TERMINEE'])
      .gte('fin_le', semaine.toISOString())
      .lt('debut_le', finSemaine.toISOString())
      .order('debut_le', { ascending: true })
      .then(({ data }) => {
        setMissions(data || []);
        setLoading(false);
      });
  }, [user, semaine]);

  // Load serie candidates
  useEffect(() => {
    if (!serieParam) { setSerieCandidates([]); return; }
    const decoded = decodeURIComponent(serieParam);
    supabase
      .from('missions')
      .select('id, intitule, debut_le, fin_le, duree_heures, statut, etablissements(nom)')
      .ilike('description', `%[SERIE_ID:${decoded}]%`)
      .eq('statut', 'OUVERTE')
      .order('debut_le')
      .then(({ data }) => {
        setSerieCandidates(data || []);
        // Navigate to first week of serie
        if (data && data.length > 0) {
          setSemaine(startOfWeek(new Date(data[0].debut_le), { weekStartsOn: 1 }));
        }
      });
  }, [serieParam]);

  const heuresParJour = jours.map(jour => {
    const msDuJour = missions.filter(m => isSameDay(new Date(m.debut_le), jour));
    return msDuJour.reduce((t, m) => t + (m.duree_heures || 0), 0);
  });
  const totalSemaine = heuresParJour.reduce((a, b) => a + b, 0);

  function getMissionBlocs(jour: Date) {
    const blocs: any[] = [];
    const msDuJour = missions.filter(m => isSameDay(new Date(m.debut_le), jour));

    for (const m of msDuJour) {
      const debut = new Date(m.debut_le);
      let heureDebut = debut.getHours() + debut.getMinutes() / 60;
      const fin = new Date(m.fin_le);
      let heureFin = fin.getHours() + fin.getMinutes() / 60;
      if (heureFin <= heureDebut) heureFin += 24;
      if (heureDebut < HEURE_MIN) heureDebut = HEURE_MIN;
      if (heureFin > HEURE_MAX) heureFin = HEURE_MAX;

      const top = ((heureDebut - HEURE_MIN) / TOTAL_HEURES) * 100;
      const height = ((heureFin - heureDebut) / TOTAL_HEURES) * 100;

      blocs.push({ ...m, top: `${top}%`, height: `${Math.max(height, 2)}%`, isHighlight: m.id === highlightId });
    }

    // Single mission candidate
    if (missionCandidate && isSameDay(new Date(missionCandidate.debut_le), jour)) {
      const debut = new Date(missionCandidate.debut_le);
      let heureDebut = debut.getHours() + debut.getMinutes() / 60;
      const fin = new Date(missionCandidate.fin_le);
      let heureFin = fin.getHours() + fin.getMinutes() / 60;
      if (heureFin <= heureDebut) heureFin += 24;
      if (heureDebut < HEURE_MIN) heureDebut = HEURE_MIN;
      if (heureFin > HEURE_MAX) heureFin = HEURE_MAX;

      blocs.push({
        ...missionCandidate,
        top: `${((heureDebut - HEURE_MIN) / TOTAL_HEURES) * 100}%`,
        height: `${Math.max(((heureFin - heureDebut) / TOTAL_HEURES) * 100, 2)}%`,
        isCandidate: true,
      });
    }

    // Serie candidates
    for (const sc of serieCandidates) {
      if (isSameDay(new Date(sc.debut_le), jour)) {
        const debut = new Date(sc.debut_le);
        let heureDebut = debut.getHours() + debut.getMinutes() / 60;
        const fin = new Date(sc.fin_le);
        let heureFin = fin.getHours() + fin.getMinutes() / 60;
        if (heureFin <= heureDebut) heureFin += 24;
        if (heureDebut < HEURE_MIN) heureDebut = HEURE_MIN;
        if (heureFin > HEURE_MAX) heureFin = HEURE_MAX;

        blocs.push({
          ...sc,
          top: `${((heureDebut - HEURE_MIN) / TOTAL_HEURES) * 100}%`,
          height: `${Math.max(((heureFin - heureDebut) / TOTAL_HEURES) * 100, 2)}%`,
          isCandidate: true,
        });
      }
    }

    return blocs;
  }

  return (
    <div className="card-base">
      <div className="flex items-center justify-between mb-4">
        <button onClick={() => setSemaine(addDays(semaine, -7))} className="p-1.5 hover:bg-muted rounded-lg transition-colors">
          <ChevronLeft className="h-5 w-5 text-muted-foreground" />
        </button>
        <div className="text-center">
          <h3 className="text-sm font-bold text-foreground">
            {format(jours[0], 'd MMM', { locale: fr })} — {format(jours[6], 'd MMM yyyy', { locale: fr })}
          </h3>
          <p className="text-xs text-muted-foreground">Total : <strong>{totalSemaine.toFixed(0)}h</strong> / 48h</p>
        </div>
        <button onClick={() => setSemaine(addDays(semaine, 7))} className="p-1.5 hover:bg-muted rounded-lg transition-colors">
          <ChevronRight className="h-5 w-5 text-muted-foreground" />
        </button>
      </div>

      <button onClick={() => setSemaine(startOfWeek(new Date(), { weekStartsOn: 1 }))}
        className="text-xs text-primary font-medium hover:underline mb-3 block mx-auto">
        Aujourd'hui
      </button>

      <div className="overflow-x-auto -mx-4 md:-mx-6 px-4 md:px-6">
        <div className="min-w-[600px]">
          <div className="grid grid-cols-8 gap-px mb-1">
            <div className="text-[10px] text-muted-foreground" />
            {jours.map((j, i) => (
              <div key={i} className={`text-center text-[10px] font-semibold p-1 rounded ${isSameDay(j, new Date()) ? 'bg-primary/10 text-primary' : 'text-muted-foreground'}`}>
                {format(j, 'EEE d', { locale: fr })}
              </div>
            ))}
          </div>

          <div className="grid grid-cols-8 gap-px" style={{ height: '500px' }}>
            <div className="relative">
              {Array.from({ length: TOTAL_HEURES }, (_, i) => (
                <div key={i} className="absolute text-[9px] text-muted-foreground right-1"
                  style={{ top: `${(i / TOTAL_HEURES) * 100}%` }}>
                  {((HEURE_MIN + i) % 24).toString().padStart(2, '0')}h
                </div>
              ))}
            </div>

            {jours.map((jour, i) => {
              const blocs = getMissionBlocs(jour);
              return (
                <div key={i} className="relative bg-muted/20 border-l border-border">
                  {Array.from({ length: TOTAL_HEURES }, (_, h) => (
                    <div key={h} className="absolute w-full border-t border-border/30"
                      style={{ top: `${(h / TOTAL_HEURES) * 100}%` }} />
                  ))}

                  {blocs.map((b, bi) => (
                    <button key={bi}
                      onClick={() => !b.isCandidate && navigate(`/soignant/missions/${b.id}`)}
                      className={`absolute left-0.5 right-0.5 rounded-md px-1 py-0.5 text-[9px] leading-tight overflow-hidden transition-all
                        ${b.isCandidate
                          ? 'border-2 border-dashed border-primary bg-primary/10 text-primary'
                          : b.isHighlight
                            ? 'ring-2 ring-primary ring-offset-1 ' + getStatutCouleur(b.statut)
                            : getStatutCouleur(b.statut)
                        }`}
                      style={{ top: b.top, height: b.height }}
                      title={b.intitule}>
                      <span className="font-semibold block truncate">{b.intitule}</span>
                      {b.etablissements?.nom && <span className="block truncate opacity-80">{b.etablissements.nom}</span>}
                    </button>
                  ))}
                </div>
              );
            })}
          </div>

          <div className="grid grid-cols-8 gap-px mt-1">
            <div />
            {heuresParJour.map((h, i) => (
              <div key={i} className={`text-center text-[10px] font-semibold ${h > 0 ? 'text-foreground' : 'text-muted-foreground/30'}`}>
                {h > 0 ? `${h.toFixed(0)}h` : '—'}
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}
