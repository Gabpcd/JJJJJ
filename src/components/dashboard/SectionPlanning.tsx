import { useMemo, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Tabs, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { AlertTriangle, CalendarDays, ChevronLeft, ChevronRight, RefreshCw, User } from 'lucide-react';
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from '@/components/ui/tooltip';
import {
  ajouterRepliMissionPonctuelle,
  creneauxPrevisionnels,
  type CreneauPointage,
} from '@/lib/disponibilite-pointage';
import {
  ajouterJoursCivilsParis,
  ajouterMoisCivilsParis,
  cleJourParis,
  debutMoisParis,
  debutSemaineParis,
  finMoisParis,
  formatParis,
  instantJolene,
  memeJourParis,
  memeMoisParis,
  semaineSuivanteParis,
} from '@/lib/date-heure-paris';
import { decouperOccurrencesParJour } from '@/lib/occurrences-planning';

export interface MissionPlanningSource {
  id: string;
  intitule: string;
  debut_le: string;
  fin_le: string;
  statut: 'OUVERTE' | 'ASSIGNEE' | 'EN_COURS' | string;
  duree_heures?: number | null;
  profession_requise?: string | null;
  nb_creneaux?: number | null;
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

/** Dernière milliseconde du jour civil Paris situé `jours` jours plus loin. */
// eslint-disable-next-line react-refresh/only-export-components
export function finFenetrePlanningParis(debut: Date, jours = 31): Date {
  return new Date(ajouterJoursCivilsParis(debut, jours + 1).getTime() - 1);
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
          return instantJolene(creneau.fin).getTime() >= debutMs
            && instantJolene(creneau.debut).getTime() <= finMs;
        })
        .map((creneau) => ({
          ...mission,
          occurrence_id: `${mission.id}:${creneau.id ?? creneau.debut}`,
          creneau_debut: creneau.debut,
          creneau_fin: creneau.fin!,
          duree_creneau_heures: Math.max(
            0,
            (instantJolene(creneau.fin!).getTime() - instantJolene(creneau.debut).getTime()) / 3_600_000,
          ),
        }));
    })
    .sort((a, b) => instantJolene(a.creneau_debut).getTime() - instantJolene(b.creneau_debut).getTime());
}

interface Props {
  missions: MissionPlanning[];
  missionsSansPlanning?: MissionPlanningSource[];
  erreur?: string | null;
  onRetry?: () => void;
  debutFenetre?: Date | string;
  finFenetre?: Date | string;
}

type View = 'mois' | 'semaine' | 'liste';

const STATUT_STYLE: Record<string, { dot: string; bg: string; text: string; label: string }> = {
  OUVERTE: { dot: 'bg-warning', bg: 'bg-warning/10 hover:bg-warning/20 border-warning/30', text: 'text-warning', label: 'Ouverte' },
  ASSIGNEE: { dot: 'bg-info', bg: 'bg-info/10 hover:bg-info/20 border-info/30', text: 'text-info', label: 'Assignée' },
  EN_COURS: { dot: 'bg-success', bg: 'bg-success/10 hover:bg-success/20 border-success/30', text: 'text-success', label: 'Active' },
};

const styleFor = (statut: string) => STATUT_STYLE[statut] ?? STATUT_STYLE.OUVERTE;

const fmtHeure = (iso: string) => formatParis(iso, 'HH:mm');

function formatFinAvecDate(debut: string, fin: string): string {
  if (memeJourParis(debut, fin)) return fmtHeure(fin);
  const estLendemain = memeJourParis(ajouterJoursCivilsParis(instantJolene(debut), 1), fin);
  return `${formatParis(fin, 'EEE d MMM · HH:mm')}${estLendemain ? ' (lendemain)' : ''}`;
}

function decouperMissionsPlanningParJour(missions: MissionPlanning[]): MissionPlanning[] {
  return decouperOccurrencesParJour(missions.map((mission) => ({
    ...mission,
    debut_le: mission.creneau_debut,
    fin_le: mission.creneau_fin,
    duree_heures: mission.duree_creneau_heures,
  }))).map((segment) => ({
    ...segment,
    occurrence_id: segment.segment_id,
    creneau_debut: segment.debut_le,
    creneau_fin: segment.fin_le,
    duree_creneau_heures: segment.duree_heures,
  }));
}

function bucketFor(date: Date, now: Date): 'today' | 'tomorrow' | 'thisWeek' | 'nextWeek' | 'later' {
  if (memeJourParis(date, now)) return 'today';
  if (memeJourParis(date, ajouterJoursCivilsParis(now, 1))) return 'tomorrow';
  const debutSemaineSuivante = semaineSuivanteParis(now);
  if (date < debutSemaineSuivante) return 'thisWeek';
  if (date < ajouterJoursCivilsParis(debutSemaineSuivante, 7)) return 'nextWeek';
  return 'later';
}

const BUCKET_LABEL: Record<string, string> = {
  today: "Aujourd'hui",
  tomorrow: 'Demain',
  thisWeek: 'Cette semaine',
  nextWeek: 'Semaine prochaine',
  later: 'Plus tard',
};

export function SectionPlanning({
  missions,
  missionsSansPlanning = [],
  erreur,
  onRetry,
  debutFenetre,
  finFenetre,
}: Props) {
  const navigate = useNavigate();
  const initialView: View = typeof window !== 'undefined' && window.matchMedia('(min-width: 768px)').matches ? 'mois' : 'liste';
  const [view, setView] = useState<View>(initialView);
  const [moisCourant, setMoisCourant] = useState(() => debutMoisParis(new Date()));
  const [semaineCourante, setSemaineCourante] = useState(() => debutSemaineParis(new Date()));

  const bornes = useMemo(() => {
    try {
      return {
        debut: debutFenetre == null ? null : instantJolene(debutFenetre),
        fin: finFenetre == null ? null : instantJolene(finFenetre),
      };
    } catch {
      return { debut: null, fin: null };
    }
  }, [debutFenetre, finFenetre]);

  const intersecteFenetreChargee = (debut: Date, finExclusive: Date): boolean => (
    (!bornes.debut || finExclusive.getTime() > bornes.debut.getTime())
    && (!bornes.fin || debut.getTime() <= bornes.fin.getTime())
  );
  const moisPrecedent = ajouterMoisCivilsParis(moisCourant, -1);
  const moisSuivant = ajouterMoisCivilsParis(moisCourant, 1);
  const peutMoisPrecedent = intersecteFenetreChargee(
    moisPrecedent,
    ajouterMoisCivilsParis(moisPrecedent, 1),
  );
  const peutMoisSuivant = intersecteFenetreChargee(
    moisSuivant,
    ajouterMoisCivilsParis(moisSuivant, 1),
  );
  const semainePrecedente = ajouterJoursCivilsParis(semaineCourante, -7);
  const semaineSuivante = ajouterJoursCivilsParis(semaineCourante, 7);
  const peutSemainePrecedente = intersecteFenetreChargee(
    semainePrecedente,
    ajouterJoursCivilsParis(semainePrecedente, 7),
  );
  const peutSemaineSuivante = intersecteFenetreChargee(
    semaineSuivante,
    ajouterJoursCivilsParis(semaineSuivante, 7),
  );

  const ouvrir = (id: string) => navigate(`/etablissement/missions/${id}`);

  return (
    <div className="card-base mb-6">
      <div className="flex items-center justify-between gap-3 mb-4 flex-wrap">
        <div className="flex items-center gap-2">
          <CalendarDays className="h-5 w-5 text-primary" />
          <h2 className="text-lg font-bold text-foreground">Planning missions à venir</h2>
          <span className="text-xs text-muted-foreground">
            ({missions.length} créneau{missions.length > 1 ? 'x' : ''}
            {missionsSansPlanning.length > 0 ? ` · ${missionsSansPlanning.length} à confirmer` : ''})
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
      ) : (
        <>
          {missionsSansPlanning.length > 0 && (
            <div className="mb-4 rounded-xl border border-warning/30 bg-warning/5 p-4" role="alert">
              <p className="flex items-center gap-2 text-sm font-semibold text-warning">
                <AlertTriangle className="h-4 w-4 shrink-0" aria-hidden="true" />
                Planning détaillé à confirmer
              </p>
              <p className="mt-1 text-xs text-muted-foreground">
                Ces missions restent visibles mais aucun créneau prévisionnel complet n’est enregistré.
              </p>
              <div className="mt-3 space-y-2">
                {missionsSansPlanning.map((mission) => (
                  <button
                    key={mission.id}
                    type="button"
                    onClick={() => ouvrir(mission.id)}
                    className="w-full rounded-lg border border-warning/20 bg-card px-3 py-2 text-left hover:bg-warning/5"
                  >
                    <span className="block text-sm font-medium text-foreground">{mission.intitule}</span>
                    <span className="block text-xs text-muted-foreground">
                      Période prévue : {formatParis(mission.debut_le, 'd MMM yyyy')} → {formatParis(mission.fin_le, 'd MMM yyyy')}
                    </span>
                  </button>
                ))}
              </div>
            </div>
          )}

          {missions.length === 0 ? (
            missionsSansPlanning.length === 0 ? (
              <p className="text-sm text-muted-foreground text-center py-8">
                Aucun créneau planifié dans les 31 prochains jours.
              </p>
            ) : null
          ) : view === 'mois' ? (
            <VueMois
              mois={moisCourant}
              missions={missions}
              onPrev={() => setMoisCourant(ajouterMoisCivilsParis(moisCourant, -1))}
              onNext={() => setMoisCourant(ajouterMoisCivilsParis(moisCourant, 1))}
              peutPrecedent={peutMoisPrecedent}
              peutSuivant={peutMoisSuivant}
              onClickMission={ouvrir}
            />
          ) : view === 'semaine' ? (
            <VueSemaine
              debutSemaine={semaineCourante}
              missions={missions}
              onPrev={() => setSemaineCourante(ajouterJoursCivilsParis(semaineCourante, -7))}
              onNext={() => setSemaineCourante(ajouterJoursCivilsParis(semaineCourante, 7))}
              peutPrecedent={peutSemainePrecedente}
              peutSuivant={peutSemaineSuivante}
              onClickMission={ouvrir}
            />
          ) : (
            <VueListe missions={missions} onClickMission={ouvrir} />
          )}
        </>
      )}
    </div>
  );
}

/* ───────────── Vue Mois (desktop) ───────────── */
function VueMois({
  mois, missions, onPrev, onNext, peutPrecedent, peutSuivant, onClickMission,
}: {
  mois: Date; missions: MissionPlanning[];
  onPrev: () => void; onNext: () => void;
  peutPrecedent: boolean; peutSuivant: boolean;
  onClickMission: (id: string) => void;
}) {
  const debutGrille = debutSemaineParis(debutMoisParis(mois));
  const finGrilleExclusive = ajouterJoursCivilsParis(debutSemaineParis(finMoisParis(mois)), 7);
  const jours: Date[] = [];
  for (let d = debutGrille; d < finGrilleExclusive; d = ajouterJoursCivilsParis(d, 1)) jours.push(d);

  const missionsParJour = useMemo(() => {
    const map = new Map<string, MissionPlanning[]>();
    for (const m of decouperMissionsPlanningParJour(missions)) {
      const key = cleJourParis(m.creneau_debut);
      const arr = map.get(key) ?? [];
      arr.push(m);
      map.set(key, arr);
    }
    return map;
  }, [missions]);

  return (
    <div className="hidden md:block">
      <div className="flex items-center justify-between mb-3">
        <button disabled={!peutPrecedent} onClick={onPrev} className="p-1.5 hover:bg-muted rounded disabled:cursor-not-allowed disabled:opacity-30" aria-label="Mois précédent">
          <ChevronLeft className="h-4 w-4" />
        </button>
        <p className="text-sm font-semibold text-foreground capitalize">
          {formatParis(mois, 'MMMM yyyy')}
        </p>
        <button disabled={!peutSuivant} onClick={onNext} className="p-1.5 hover:bg-muted rounded disabled:cursor-not-allowed disabled:opacity-30" aria-label="Mois suivant">
          <ChevronRight className="h-4 w-4" />
        </button>
      </div>

      <div className="grid grid-cols-7 gap-px bg-border rounded-lg overflow-hidden text-xs">
        {['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'].map(j => (
          <div key={j} className="bg-muted/50 px-2 py-1.5 font-medium text-muted-foreground text-center">{j}</div>
        ))}
        {jours.map(jour => {
          const key = cleJourParis(jour);
          const items = missionsParJour.get(key) ?? [];
          const horsMois = !memeMoisParis(jour, mois);
          const estAujourdhui = memeJourParis(jour, new Date());
          return (
            <div
              key={key}
              className={`bg-card min-h-[80px] p-1.5 ${horsMois ? 'opacity-40' : ''} ${estAujourdhui ? 'ring-2 ring-primary ring-inset' : ''}`}
            >
              <p className={`text-[11px] font-medium ${estAujourdhui ? 'text-primary' : 'text-foreground'}`}>
                {formatParis(jour, 'd')}
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
  debutSemaine, missions, onPrev, onNext, peutPrecedent, peutSuivant, onClickMission,
}: {
  debutSemaine: Date; missions: MissionPlanning[];
  onPrev: () => void; onNext: () => void;
  peutPrecedent: boolean; peutSuivant: boolean;
  onClickMission: (id: string) => void;
}) {
  const jours = useMemo(() => Array.from({ length: 7 }, (_, i) => ajouterJoursCivilsParis(debutSemaine, i)), [debutSemaine]);
  const missionsParJour = useMemo(() => {
    const map = new Map<string, MissionPlanning[]>();
    for (const m of decouperMissionsPlanningParJour(missions)) {
      const d = instantJolene(m.creneau_debut);
      if (d < debutSemaine || d >= ajouterJoursCivilsParis(debutSemaine, 7)) continue;
      const key = cleJourParis(d);
      const arr = map.get(key) ?? [];
      arr.push(m);
      map.set(key, arr);
    }
    return map;
  }, [missions, debutSemaine]);

  const finSemaine = ajouterJoursCivilsParis(debutSemaine, 6);

  return (
    <div>
      <div className="flex items-center justify-between mb-3">
        <button disabled={!peutPrecedent} onClick={onPrev} className="p-1.5 hover:bg-muted rounded disabled:cursor-not-allowed disabled:opacity-30" aria-label="Semaine précédente">
          <ChevronLeft className="h-4 w-4" />
        </button>
        <p className="text-sm font-semibold text-foreground">
          {formatParis(debutSemaine, 'd MMM')} → {formatParis(finSemaine, 'd MMM yyyy')}
        </p>
        <button disabled={!peutSuivant} onClick={onNext} className="p-1.5 hover:bg-muted rounded disabled:cursor-not-allowed disabled:opacity-30" aria-label="Semaine suivante">
          <ChevronRight className="h-4 w-4" />
        </button>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-7 gap-2">
        {jours.map(jour => {
          const key = cleJourParis(jour);
          const items = missionsParJour.get(key) ?? [];
          const estAujourdhui = memeJourParis(jour, new Date());
          return (
            <div key={key} className={`border border-border rounded-lg p-2 ${estAujourdhui ? 'border-primary' : ''}`}>
              <p className={`text-xs font-semibold mb-2 ${estAujourdhui ? 'text-primary' : 'text-foreground'}`}>
                <span className="capitalize">{formatParis(jour, 'EEE')}</span> {formatParis(jour, 'd MMM')}
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
      const b = bucketFor(instantJolene(m.creneau_debut), now);
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
                const date = instantJolene(m.creneau_debut);
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
                        {formatParis(date, 'EEE d MMM')} · {fmtHeure(m.creneau_debut)} → {formatFinAvecDate(m.creneau_debut, m.creneau_fin)}
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
