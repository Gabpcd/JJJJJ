import { useMemo, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  addDays, addMonths, endOfMonth, endOfWeek, format, isSameMonth,
  isToday, isTomorrow, startOfDay, startOfMonth, startOfWeek, subMonths,
} from 'date-fns';
import { fr } from 'date-fns/locale';
import { Tabs, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { AlertTriangle, CalendarDays, ChevronLeft, ChevronRight, RefreshCw, User } from 'lucide-react';
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from '@/components/ui/tooltip';
import {
  ajouterRepliMissionPonctuelle,
  creneauxPrevisionnels,
  type CreneauPointage,
} from '@/lib/disponibilite-pointage';

export interface MissionPlanningSource {
  id: string;
  intitule: string;
  debut_le: string;
  fin_le: string;
  statut: 'OUVERTE' | 'ASSIGNEE' | 'EN_COURS' | string;
  duree_heures?: number | null;
  profession_requise?: string | null;
  soignant_assigne_id?: string | null;
  soignant_nom?: string | null;
}

export interface CreneauPlanning extends CreneauPointage {
  mission_id: string;
}

export interface MissionPlanning extends MissionPlanningSource {
  occurrence_id: string;
  creneau_debut: string;
  creneau_fin: string;
  duree_creneau_heures: number;
}

/**
 * Transforme une mission contractuelle en occurrences réellement travaillées.
 * `debut_le` / `fin_le` décrivent la période globale de la mission ; ils ne
 * doivent jamais être étalés sur chaque jour du calendrier. Les anciennes
 * missions ponctuelles sans PREVISIONNEL gardent un repli strict à 24 h.
 */
// Le helper reste ici pour garantir que le chargement et les trois vues
// partagent exactement la même notion d'occurrence de planning.
// eslint-disable-next-line react-refresh/only-export-components
export function construireOccurrencesPlanning(
  missions: MissionPlanningSource[],
  creneaux: CreneauPlanning[],
  debutPeriode: Date,
  finPeriode: Date,
): MissionPlanning[] {
  const creneauxParMission = new Map<string, CreneauPointage[]>();
  for (const creneau of creneaux) {
    const liste = creneauxParMission.get(creneau.mission_id) ?? [];
    liste.push(creneau);
    creneauxParMission.set(creneau.mission_id, liste);
  }

  const debutMs = debutPeriode.getTime();
  const finMs = finPeriode.getTime();

  return missions
    .flatMap((mission) => {
      const planifies = creneauxPrevisionnels(ajouterRepliMissionPonctuelle(
        creneauxParMission.get(mission.id) ?? [],
        mission,
      ));

      return planifies
        .filter((creneau) => {
          if (!creneau.fin) return false;
          return new Date(creneau.fin).getTime() >= debutMs
            && new Date(creneau.debut).getTime() <= finMs;
        })
        .map((creneau) => ({
          ...mission,
          occurrence_id: `${mission.id}:${creneau.id ?? creneau.debut}`,
          creneau_debut: creneau.debut,
          creneau_fin: creneau.fin!,
          duree_creneau_heures: Math.max(
            0,
            (new Date(creneau.fin!).getTime() - new Date(creneau.debut).getTime()) / 3_600_000,
          ),
        }));
    })
    .sort((a, b) => new Date(a.creneau_debut).getTime() - new Date(b.creneau_debut).getTime());
}

interface Props {
  missions: MissionPlanning[];
  erreur?: string | null;
  onRetry?: () => void;
}

type View = 'mois' | 'semaine' | 'liste';

const STATUT_STYLE: Record<string, { dot: string; bg: string; text: string; label: string }> = {
  OUVERTE: { dot: 'bg-warning', bg: 'bg-warning/10 hover:bg-warning/20 border-warning/30', text: 'text-warning', label: 'Ouverte' },
  ASSIGNEE: { dot: 'bg-info', bg: 'bg-info/10 hover:bg-info/20 border-info/30', text: 'text-info', label: 'Assignée' },
  EN_COURS: { dot: 'bg-success', bg: 'bg-success/10 hover:bg-success/20 border-success/30', text: 'text-success', label: 'Active' },
};

const styleFor = (statut: string) => STATUT_STYLE[statut] ?? STATUT_STYLE.OUVERTE;

const fmtHeure = (iso: string) =>
  new Date(iso).toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' });

function bucketFor(date: Date, now: Date): 'today' | 'tomorrow' | 'thisWeek' | 'nextWeek' | 'later' {
  if (isToday(date)) return 'today';
  if (isTomorrow(date)) return 'tomorrow';
  const endThisWeek = endOfWeek(now, { weekStartsOn: 1 });
  if (date <= endThisWeek) return 'thisWeek';
  const endNextWeek = endOfWeek(addDays(endThisWeek, 1), { weekStartsOn: 1 });
  if (date <= endNextWeek) return 'nextWeek';
  return 'later';
}

const BUCKET_LABEL: Record<string, string> = {
  today: "Aujourd'hui",
  tomorrow: 'Demain',
  thisWeek: 'Cette semaine',
  nextWeek: 'Semaine prochaine',
  later: 'Plus tard',
};

export function SectionPlanning({ missions, erreur, onRetry }: Props) {
  const navigate = useNavigate();
  const initialView: View = typeof window !== 'undefined' && window.matchMedia('(min-width: 768px)').matches ? 'mois' : 'liste';
  const [view, setView] = useState<View>(initialView);
  const [moisCourant, setMoisCourant] = useState(() => startOfMonth(new Date()));
  const [semaineCourante, setSemaineCourante] = useState(() => startOfWeek(new Date(), { weekStartsOn: 1 }));

  const ouvrir = (id: string) => navigate(`/etablissement/missions/${id}`);

  return (
    <div className="card-base mb-6">
      <div className="flex items-center justify-between gap-3 mb-4 flex-wrap">
        <div className="flex items-center gap-2">
          <CalendarDays className="h-5 w-5 text-primary" />
          <h2 className="text-lg font-bold text-foreground">Planning missions à venir</h2>
          <span className="text-xs text-muted-foreground">
            ({missions.length} créneau{missions.length > 1 ? 'x' : ''})
          </span>
        </div>

        <Tabs value={view} onValueChange={(v) => setView(v as View)}>
          <TabsList className="h-8">
            <TabsTrigger value="mois" className="text-xs px-3 hidden md:flex">Mois</TabsTrigger>
            <TabsTrigger value="semaine" className="text-xs px-3">Semaine</TabsTrigger>
            <TabsTrigger value="liste" className="text-xs px-3">Liste</TabsTrigger>
          </TabsList>
        </Tabs>
      </div>

      {erreur ? (
        <div className="rounded-xl border border-destructive/30 bg-destructive/5 p-4 text-sm" role="alert">
          <p className="flex items-center gap-2 font-medium text-destructive">
            <AlertTriangle className="h-4 w-4 shrink-0" />
            {erreur}
          </p>
          {onRetry && (
            <button
              type="button"
              onClick={onRetry}
              className="mt-3 inline-flex items-center gap-1.5 text-xs font-semibold text-primary hover:underline"
            >
              <RefreshCw className="h-3.5 w-3.5" /> Réessayer
            </button>
          )}
        </div>
      ) : missions.length === 0 ? (
        <p className="text-sm text-muted-foreground text-center py-8">
          Aucun créneau planifié dans les 31 prochains jours.
        </p>
      ) : view === 'mois' ? (
        <VueMois
          mois={moisCourant}
          missions={missions}
          onPrev={() => setMoisCourant(subMonths(moisCourant, 1))}
          onNext={() => setMoisCourant(addMonths(moisCourant, 1))}
          onClickMission={ouvrir}
        />
      ) : view === 'semaine' ? (
        <VueSemaine
          debutSemaine={semaineCourante}
          missions={missions}
          onPrev={() => setSemaineCourante(addDays(semaineCourante, -7))}
          onNext={() => setSemaineCourante(addDays(semaineCourante, 7))}
          onClickMission={ouvrir}
        />
      ) : (
        <VueListe missions={missions} onClickMission={ouvrir} />
      )}
    </div>
  );
}

/* ───────────── Vue Mois (desktop) ───────────── */
function VueMois({
  mois, missions, onPrev, onNext, onClickMission,
}: {
  mois: Date; missions: MissionPlanning[];
  onPrev: () => void; onNext: () => void;
  onClickMission: (id: string) => void;
}) {
  const debutGrille = startOfWeek(startOfMonth(mois), { weekStartsOn: 1 });
  const finGrille = endOfWeek(endOfMonth(mois), { weekStartsOn: 1 });
  const jours: Date[] = [];
  for (let d = debutGrille; d <= finGrille; d = addDays(d, 1)) jours.push(d);

  const missionsParJour = useMemo(() => {
    const map = new Map<string, MissionPlanning[]>();
    for (const m of missions) {
      const key = format(startOfDay(new Date(m.creneau_debut)), 'yyyy-MM-dd');
      const arr = map.get(key) ?? [];
      arr.push(m);
      map.set(key, arr);
    }
    return map;
  }, [missions]);

  return (
    <div className="hidden md:block">
      <div className="flex items-center justify-between mb-3">
        <button onClick={onPrev} className="p-1.5 hover:bg-muted rounded" aria-label="Mois précédent">
          <ChevronLeft className="h-4 w-4" />
        </button>
        <p className="text-sm font-semibold text-foreground capitalize">
          {format(mois, 'MMMM yyyy', { locale: fr })}
        </p>
        <button onClick={onNext} className="p-1.5 hover:bg-muted rounded" aria-label="Mois suivant">
          <ChevronRight className="h-4 w-4" />
        </button>
      </div>

      <div className="grid grid-cols-7 gap-px bg-border rounded-lg overflow-hidden text-xs">
        {['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'].map(j => (
          <div key={j} className="bg-muted/50 px-2 py-1.5 font-medium text-muted-foreground text-center">{j}</div>
        ))}
        {jours.map(jour => {
          const key = format(jour, 'yyyy-MM-dd');
          const items = missionsParJour.get(key) ?? [];
          const horsMois = !isSameMonth(jour, mois);
          return (
            <div
              key={key}
              className={`bg-card min-h-[80px] p-1.5 ${horsMois ? 'opacity-40' : ''} ${isToday(jour) ? 'ring-2 ring-primary ring-inset' : ''}`}
            >
              <p className={`text-[11px] font-medium ${isToday(jour) ? 'text-primary' : 'text-foreground'}`}>
                {format(jour, 'd')}
              </p>
              <TooltipProvider delayDuration={200}>
                <div className="space-y-0.5 mt-1">
                  {items.slice(0, 3).map(m => {
                    const cfg = styleFor(m.statut);
                    return (
                      <Tooltip key={m.occurrence_id}>
                        <TooltipTrigger asChild>
                          <button
                            onClick={() => onClickMission(m.id)}
                            className={`w-full text-left px-1.5 py-0.5 rounded border ${cfg.bg} ${cfg.text} truncate text-[10px] font-medium`}
                          >
                            {fmtHeure(m.creneau_debut)} {m.intitule}
                          </button>
                        </TooltipTrigger>
                        <TooltipContent side="top" className="text-xs">
                          <p className="font-semibold">{m.intitule}</p>
                          <p>{fmtHeure(m.creneau_debut)} → {fmtHeure(m.creneau_fin)} · {m.duree_creneau_heures.toLocaleString('fr-FR', { maximumFractionDigits: 2 })}h</p>
                          <p className="text-muted-foreground">
                            {m.soignant_nom ?? 'Non assignée'} · {cfg.label}
                          </p>
                        </TooltipContent>
                      </Tooltip>
                    );
                  })}
                  {items.length > 3 && (
                    <p className="text-[10px] text-muted-foreground px-1.5">+{items.length - 3}</p>
                  )}
                </div>
              </TooltipProvider>
            </div>
          );
        })}
      </div>

      <LegendeStatuts />
    </div>
  );
}

/* ───────────── Vue Semaine (desktop + mobile) ───────────── */
function VueSemaine({
  debutSemaine, missions, onPrev, onNext, onClickMission,
}: {
  debutSemaine: Date; missions: MissionPlanning[];
  onPrev: () => void; onNext: () => void;
  onClickMission: (id: string) => void;
}) {
  const jours = useMemo(() => Array.from({ length: 7 }, (_, i) => addDays(debutSemaine, i)), [debutSemaine]);
  const missionsParJour = useMemo(() => {
    const map = new Map<string, MissionPlanning[]>();
    for (const m of missions) {
      const d = new Date(m.creneau_debut);
      if (d < debutSemaine || d >= addDays(debutSemaine, 7)) continue;
      const key = format(startOfDay(d), 'yyyy-MM-dd');
      const arr = map.get(key) ?? [];
      arr.push(m);
      map.set(key, arr);
    }
    return map;
  }, [missions, debutSemaine]);

  const finSemaine = addDays(debutSemaine, 6);

  return (
    <div>
      <div className="flex items-center justify-between mb-3">
        <button onClick={onPrev} className="p-1.5 hover:bg-muted rounded" aria-label="Semaine précédente">
          <ChevronLeft className="h-4 w-4" />
        </button>
        <p className="text-sm font-semibold text-foreground">
          {format(debutSemaine, 'd MMM', { locale: fr })} → {format(finSemaine, 'd MMM yyyy', { locale: fr })}
        </p>
        <button onClick={onNext} className="p-1.5 hover:bg-muted rounded" aria-label="Semaine suivante">
          <ChevronRight className="h-4 w-4" />
        </button>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-7 gap-2">
        {jours.map(jour => {
          const key = format(jour, 'yyyy-MM-dd');
          const items = missionsParJour.get(key) ?? [];
          return (
            <div key={key} className={`border border-border rounded-lg p-2 ${isToday(jour) ? 'border-primary' : ''}`}>
              <p className={`text-xs font-semibold mb-2 ${isToday(jour) ? 'text-primary' : 'text-foreground'}`}>
                <span className="capitalize">{format(jour, 'EEE', { locale: fr })}</span> {format(jour, 'd MMM', { locale: fr })}
              </p>
              {items.length === 0 ? (
                <p className="text-[10px] text-muted-foreground italic">—</p>
              ) : (
                <div className="space-y-1.5">
                  {items.map(m => {
                    const cfg = styleFor(m.statut);
                    return (
                      <button
                        key={m.occurrence_id}
                        onClick={() => onClickMission(m.id)}
                        className={`w-full text-left p-2 rounded border ${cfg.bg} text-xs space-y-0.5`}
                      >
                        <p className="font-semibold text-foreground truncate">{m.intitule}</p>
                        <p className={`${cfg.text} text-[10px]`}>
                          {fmtHeure(m.creneau_debut)} → {fmtHeure(m.creneau_fin)}
                        </p>
                        {m.soignant_nom && (
                          <p className="text-[10px] text-muted-foreground flex items-center gap-1 truncate">
                            <User className="h-2.5 w-2.5" /> {m.soignant_nom}
                          </p>
                        )}
                      </button>
                    );
                  })}
                </div>
              )}
            </div>
          );
        })}
      </div>

      <LegendeStatuts />
    </div>
  );
}

/* ───────────── Vue Liste (mobile + desktop) ───────────── */
function VueListe({ missions, onClickMission }: { missions: MissionPlanning[]; onClickMission: (id: string) => void }) {
  const groupes = useMemo(() => {
    const now = new Date();
    const map = new Map<string, MissionPlanning[]>();
    for (const m of missions) {
      const b = bucketFor(new Date(m.creneau_debut), now);
      const arr = map.get(b) ?? [];
      arr.push(m);
      map.set(b, arr);
    }
    return map;
  }, [missions]);

  const ordreBuckets: Array<keyof typeof BUCKET_LABEL> = ['today', 'tomorrow', 'thisWeek', 'nextWeek', 'later'];

  return (
    <div className="space-y-4">
      {ordreBuckets.map(b => {
        const items = groupes.get(b);
        if (!items || items.length === 0) return null;
        return (
          <div key={b}>
            <h3 className="text-xs font-semibold text-muted-foreground uppercase tracking-wide mb-2">
              {BUCKET_LABEL[b]} ({items.length})
            </h3>
            <div className="space-y-2">
              {items.map(m => {
                const cfg = styleFor(m.statut);
                const date = new Date(m.creneau_debut);
                return (
                  <button
                    key={m.occurrence_id}
                    onClick={() => onClickMission(m.id)}
                    className="w-full text-left border border-border rounded-lg p-3 hover:bg-muted/50 transition-colors flex items-start gap-3"
                  >
                    <span className={`mt-1.5 w-2 h-2 rounded-full shrink-0 ${cfg.dot}`} aria-hidden />
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center justify-between gap-2 flex-wrap">
                        <p className="text-sm font-semibold text-foreground truncate">{m.intitule}</p>
                        <span className={`text-[10px] font-medium ${cfg.text} shrink-0`}>{cfg.label}</span>
                      </div>
                      <p className="text-xs text-muted-foreground mt-0.5">
                        {format(date, 'EEE d MMM', { locale: fr })} · {fmtHeure(m.creneau_debut)} → {fmtHeure(m.creneau_fin)}
                        {` · ${m.duree_creneau_heures.toLocaleString('fr-FR', { maximumFractionDigits: 2 })}h`}
                      </p>
                      <p className="text-[11px] text-muted-foreground mt-0.5 flex items-center gap-1">
                        <User className="h-3 w-3" />
                        {m.soignant_nom ?? <span className="text-warning font-medium">En attente d'assignation</span>}
                      </p>
                    </div>
                  </button>
                );
              })}
            </div>
          </div>
        );
      })}
    </div>
  );
}

function LegendeStatuts() {
  return (
    <div className="flex items-center gap-3 mt-3 flex-wrap text-[10px] text-muted-foreground">
      {Object.entries(STATUT_STYLE).map(([k, cfg]) => (
        <span key={k} className="flex items-center gap-1">
          <span className={`h-2 w-2 rounded-full ${cfg.dot}`} aria-hidden />
          {cfg.label}
        </span>
      ))}
    </div>
  );
}
