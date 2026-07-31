import React, { useState, useEffect } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { AlertTriangle, ChevronLeft, ChevronRight, RefreshCw } from 'lucide-react';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { fetchEtablissementsSafe } from '@/lib/etablissements';
import { extraireSerieId } from '@/components/CarteSerie';
import {
  construireOccurrencesPlanning,
  decouperOccurrencesParJour,
  missionsLonguesSansPlanning,
  type CreneauMissionPlanifiable,
} from '@/lib/occurrences-planning';
import {
  ajouterJoursCivilsParis,
  debutSemaineParis,
  formatParis,
  heureDecimaleParis,
  memeJourParis,
} from '@/lib/date-heure-paris';

const HEURE_MIN = 0;
const HEURE_MAX = 24;
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
  const [semaine, setSemaine] = useState(() => debutSemaineParis(new Date()));
  const [missions, setMissions] = useState<any[]>([]);
  const [serieCandidates, setSerieCandidates] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [erreur, setErreur] = useState<string | null>(null);
  const [nbPlanningsManquants, setNbPlanningsManquants] = useState(0);
  const [tentative, setTentative] = useState(0);

  const jours = Array.from({ length: 7 }, (_, i) => ajouterJoursCivilsParis(semaine, i));
  const finSemaine = ajouterJoursCivilsParis(semaine, 7);
  const semaineIso = semaine.toISOString();
  const finSemaineIso = finSemaine.toISOString();
  const semaineMs = semaine.getTime();
  const finSemaineMs = finSemaine.getTime();
  const segmentsMissionCandidate = missionCandidate
    ? decouperOccurrencesParJour(construireOccurrencesPlanning([missionCandidate], []))
    : [];

  useEffect(() => {
    if (!user) return;
    let actif = true;

    const charger = async () => {
      setLoading(true);
      setErreur(null);
      const { data, error: missionsError } = await supabase
        .from('missions')
        .select('id, intitule, debut_le, fin_le, duree_heures, statut, etablissement_id')
        .eq('soignant_assigne_id', user.id)
        .in('statut', ['ASSIGNEE', 'EN_COURS', 'TERMINEE'])
        .gte('fin_le', semaineIso)
        .lt('debut_le', finSemaineIso)
        .order('debut_le', { ascending: true });

      if (!actif) return;
      if (missionsError) {
        setMissions([]);
        setErreur('Impossible de charger cette semaine.');
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
      setMissions(
        decouperOccurrencesParJour(
          construireOccurrencesPlanning(missionsAvecEtablissement, creneaux),
        )
          .filter((occurrence) => (
            new Date(occurrence.debut_le).getTime() < finSemaineMs
            && new Date(occurrence.fin_le).getTime() > semaineMs
          )),
      );
      setNbPlanningsManquants(
        missionsLonguesSansPlanning(missionsAvecEtablissement, creneaux).length,
      );
      setLoading(false);
    };

    void charger();
    return () => { actif = false; };
  }, [user, semaine, tentative, semaineIso, finSemaineIso, semaineMs, finSemaineMs]);

  // Load serie candidates
  useEffect(() => {
    if (!serieParam) { setSerieCandidates([]); return; }
    let actif = true;
    const decoded = decodeURIComponent(serieParam);

    const chargerSerie = async () => {
      const { data, error: missionsError } = await supabase
        .from('missions')
        .select('id, intitule, debut_le, fin_le, duree_heures, statut, etablissement_id')
        .ilike('description', `%[SERIE_ID:${decoded}]%`)
        .eq('statut', 'OUVERTE')
        .order('debut_le');
      if (!actif) return;
      if (missionsError) {
        setSerieCandidates([]);
        setErreur('Impossible de charger la série de missions.');
        return;
      }

      const items = data || [];
      if (items.length === 0) {
        setSerieCandidates([]);
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
        setSerieCandidates([]);
        setErreur('Impossible de charger les horaires de la série.');
        return;
      }

      const avecEtablissements = items.map((mission: any) => ({
        ...mission,
        etablissements: etabMap[mission.etablissement_id] || null,
      }));
      const occurrences = construireOccurrencesPlanning(
        avecEtablissements,
        (creneauxResult.data || []) as CreneauMissionPlanifiable[],
      );
      setSerieCandidates(decouperOccurrencesParJour(occurrences));
      if (occurrences.length > 0) {
        setSemaine(debutSemaineParis(occurrences[0].debut_le));
      }
    };

    void chargerSerie();
    return () => { actif = false; };
  }, [serieParam, tentative]);

  const heuresParJour = jours.map(jour => {
    const msDuJour = missions.filter(m => memeJourParis(m.debut_le, jour));
    return msDuJour.reduce((t, m) => t + (m.duree_heures || 0), 0);
  });
  const totalSemaine = heuresParJour.reduce((a, b) => a + b, 0);

  function getMissionBlocs(jour: Date) {
    const blocs: any[] = [];
    const msDuJour = missions.filter(m => memeJourParis(m.debut_le, jour));

    for (const m of msDuJour) {
      const debut = new Date(m.debut_le);
      let heureDebut = heureDecimaleParis(debut);
      const fin = new Date(m.fin_le);
      let heureFin = memeJourParis(debut, fin)
        ? heureDecimaleParis(fin)
        : HEURE_MAX;
      if (heureDebut < HEURE_MIN) heureDebut = HEURE_MIN;
      if (heureFin > HEURE_MAX) heureFin = HEURE_MAX;

      const top = ((heureDebut - HEURE_MIN) / TOTAL_HEURES) * 100;
      const height = ((heureFin - heureDebut) / TOTAL_HEURES) * 100;

      blocs.push({ ...m, top: `${top}%`, height: `${Math.max(height, 2)}%`, isHighlight: m.id === highlightId });
    }

    // Mission candidate ponctuelle, découpée si elle traverse minuit.
    for (const candidate of segmentsMissionCandidate) {
      if (!memeJourParis(candidate.debut_le, jour)) continue;
      const debut = new Date(candidate.debut_le);
      let heureDebut = heureDecimaleParis(debut);
      const fin = new Date(candidate.fin_le);
      let heureFin = memeJourParis(debut, fin)
        ? heureDecimaleParis(fin)
        : HEURE_MAX;
      if (heureDebut < HEURE_MIN) heureDebut = HEURE_MIN;
      if (heureFin > HEURE_MAX) heureFin = HEURE_MAX;

      blocs.push({
        ...candidate,
        top: `${((heureDebut - HEURE_MIN) / TOTAL_HEURES) * 100}%`,
        height: `${Math.max(((heureFin - heureDebut) / TOTAL_HEURES) * 100, 2)}%`,
        isCandidate: true,
      });
    }

    // Serie candidates
    for (const sc of serieCandidates) {
      if (memeJourParis(sc.debut_le, jour)) {
        const debut = new Date(sc.debut_le);
        let heureDebut = heureDecimaleParis(debut);
        const fin = new Date(sc.fin_le);
        let heureFin = memeJourParis(debut, fin)
          ? heureDecimaleParis(fin)
          : HEURE_MAX;
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
        <button aria-label="Semaine précédente" onClick={() => setSemaine(ajouterJoursCivilsParis(semaine, -7))} className="p-1.5 hover:bg-muted rounded-lg transition-colors">
          <ChevronLeft className="h-5 w-5 text-muted-foreground" />
        </button>
        <div className="text-center">
          <h3 className="text-sm font-bold text-foreground">
            {formatParis(jours[0], 'd MMM')} — {formatParis(jours[6], 'd MMM yyyy')}
          </h3>
          <p className="text-xs text-muted-foreground">Total : <strong>{totalSemaine.toFixed(0)}h</strong> / 48h</p>
        </div>
        <button aria-label="Semaine suivante" onClick={() => setSemaine(ajouterJoursCivilsParis(semaine, 7))} className="p-1.5 hover:bg-muted rounded-lg transition-colors">
          <ChevronRight className="h-5 w-5 text-muted-foreground" />
        </button>
      </div>

      <button onClick={() => setSemaine(debutSemaineParis(new Date()))}
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

      <div className="overflow-x-auto -mx-4 md:-mx-6 px-4 md:px-6">
        <div className="min-w-[600px]">
          <div className="grid grid-cols-8 gap-px mb-1">
            <div className="text-[10px] text-muted-foreground" />
            {jours.map((j, i) => (
              <div key={i} className={`text-center text-[10px] font-semibold p-1 rounded ${memeJourParis(j, new Date()) ? 'bg-primary/10 text-primary' : 'text-muted-foreground'}`}>
                {formatParis(j, 'EEE d')}
              </div>
            ))}
          </div>

          <div className="grid grid-cols-8 gap-px" style={{ height: 'min(500px, 70vh)' }}>
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
                    <button key={b.occurrence_id ?? `${b.id}:${bi}`}
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
