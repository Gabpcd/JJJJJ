import React, { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { AlertTriangle, ChevronLeft, ChevronRight, RefreshCw } from 'lucide-react';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { fetchEtablissementsSafe } from '@/lib/etablissements';
import {
  construireOccurrencesPlanning,
  decouperOccurrencesParJour,
  missionsLonguesSansPlanning,
  type CreneauMissionPlanifiable,
} from '@/lib/occurrences-planning';
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
    case 'ANNULEE_PAR_ETABLISSEMENT':
    case 'ANNULEE_PAR_SOIGNANT': return 'bg-destructive text-destructive-foreground';
    default: return 'bg-muted text-muted-foreground';
  }
}

export function CalendrierMensuel() {
  const navigate = useNavigate();
  const { user } = useAuth();
  const [moisCourant, setMoisCourant] = useState(new Date());
  const [missions, setMissions] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [erreur, setErreur] = useState<string | null>(null);
  const [nbPlanningsManquants, setNbPlanningsManquants] = useState(0);
  const [tentative, setTentative] = useState(0);

  const debutMois = startOfMonth(moisCourant);
  const finMois = endOfMonth(moisCourant);
  const debutGrille = startOfWeek(debutMois, { weekStartsOn: 1 });
  const finGrille = endOfWeek(finMois, { weekStartsOn: 1 });
  const debutGrilleIso = debutGrille.toISOString();
  const finGrilleIso = finGrille.toISOString();
  const debutGrilleMs = debutGrille.getTime();
  const finGrilleMs = finGrille.getTime();

  // Build array of days for the grid
  const jours: Date[] = [];
  let jour = debutGrille;
  while (jour <= finGrille) {
    jours.push(jour);
    jour = addDays(jour, 1);
  }

  useEffect(() => {
    if (!user) return;
    let actif = true;

    const charger = async () => {
      setLoading(true);
      setErreur(null);

      const { data, error: missionsError } = await supabase
        .from('missions')
        .select('id, intitule, debut_le, fin_le, duree_heures, statut, etablissement_id, service')
        .eq('soignant_assigne_id', user.id)
        .in('statut', ['ASSIGNEE', 'EN_COURS', 'TERMINEE', 'ANNULEE_PAR_ETABLISSEMENT', 'ANNULEE_PAR_SOIGNANT'])
        .gte('fin_le', debutGrilleIso)
        .lte('debut_le', finGrilleIso)
        .order('debut_le');

      if (!actif) return;
      if (missionsError) {
        setMissions([]);
        setErreur('Impossible de charger le planning.');
        setLoading(false);
        return;
      }

      const items = data || [];
      if (items.length === 0) {
        setMissions([]);
        setNbPlanningsManquants(0);
        setLoading(false);
        return;
      }

      const [etabMap, creneauxResult] = await Promise.all([
        fetchEtablissementsSafe(items.map((mission: any) => mission.etablissement_id)),
        supabase
          .from('mission_creneaux')
          .select('id, mission_id, debut, fin, est_pause, type_creneau')
          .in('mission_id', items.map((mission: any) => mission.id)),
      ]);

      if (!actif) return;
      if (creneauxResult.error) {
        setMissions([]);
        setErreur('Impossible de charger les jours et horaires travaillés.');
        setLoading(false);
        return;
      }

      const missionsAvecEtablissement = items.map((mission: any) => ({
        ...mission,
        etablissements: etabMap[mission.etablissement_id] || null,
      }));
      const creneaux = (creneauxResult.data || []) as CreneauMissionPlanifiable[];
      const occurrences = decouperOccurrencesParJour(
        construireOccurrencesPlanning(missionsAvecEtablissement, creneaux),
      )
        .filter((occurrence) => (
          new Date(occurrence.debut_le).getTime() <= finGrilleMs
          && new Date(occurrence.fin_le).getTime() >= debutGrilleMs
        ));

      setMissions(occurrences);
      setNbPlanningsManquants(
        missionsLonguesSansPlanning(missionsAvecEtablissement, creneaux).length,
      );
      setLoading(false);
    };

    void charger();
    return () => { actif = false; };
  }, [user, moisCourant, tentative, debutGrilleIso, finGrilleIso, debutGrilleMs, finGrilleMs]);

  function getMissionsDuJour(d: Date) {
    return missions.filter(m => isSameDay(new Date(m.debut_le), d));
  }

  return (
    <div className="card-base">
      {/* Header navigation */}
      <div className="flex items-center justify-between mb-4">
        <button aria-label="Mois précédent" onClick={() => setMoisCourant(addMonths(moisCourant, -1))} className="p-1.5 hover:bg-muted rounded-lg transition-colors">
          <ChevronLeft className="h-5 w-5 text-muted-foreground" />
        </button>
        <div className="text-center">
          <h3 className="text-base font-bold text-foreground capitalize">
            {format(moisCourant, 'MMMM yyyy', { locale: fr })}
          </h3>
        </div>
        <button aria-label="Mois suivant" onClick={() => setMoisCourant(addMonths(moisCourant, 1))} className="p-1.5 hover:bg-muted rounded-lg transition-colors">
          <ChevronRight className="h-5 w-5 text-muted-foreground" />
        </button>
      </div>

      <button onClick={() => setMoisCourant(new Date())}
        className="text-xs text-primary font-medium hover:underline mb-3 block mx-auto">
        Aujourd'hui
      </button>

      {erreur && (
        <div className="mb-4 rounded-xl border border-destructive/30 bg-destructive/5 p-3 text-sm text-destructive" role="alert">
          <p>{erreur}</p>
          <button
            type="button"
            onClick={() => setTentative((valeur) => valeur + 1)}
            className="mt-2 inline-flex items-center gap-1.5 font-semibold hover:underline"
          >
            <RefreshCw className="h-3.5 w-3.5" /> Réessayer
          </button>
        </div>
      )}

      {nbPlanningsManquants > 0 && !erreur && (
        <div className="mb-4 flex items-start gap-2 rounded-xl border border-warning/30 bg-warning/5 p-3 text-xs text-warning" role="status">
          <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" />
          <span>
            {nbPlanningsManquants} mission{nbPlanningsManquants > 1 ? 's actives ont' : ' active a'} un planning détaillé à confirmer.
          </span>
        </div>
      )}

      {/* Légende */}
      <div className="flex flex-wrap gap-3 mb-4 justify-center">
        {[
          { label: 'Assignée', cls: 'bg-info' },
          { label: 'Active', cls: 'bg-success' },
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
      <div className="grid grid-cols-7 gap-px min-w-[320px] mb-1">
        {JOURS_SEMAINE.map(j => (
          <div key={j} className="text-center text-[11px] font-semibold text-muted-foreground py-1">
            {j}
          </div>
        ))}
      </div>

      {/* Calendar grid */}
      <div className="grid grid-cols-7 gap-px min-w-[320px]">
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
                  <button key={m.segment_id ?? m.occurrence_id}
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
