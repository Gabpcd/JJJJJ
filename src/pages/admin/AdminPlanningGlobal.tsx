import React, { useState } from 'react';
import { Link } from 'react-router-dom';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { BreadcrumbAdmin } from '@/components/BreadcrumbAdmin';
import { usePageTitle } from '@/hooks/usePageTitle';
import { supabase } from '@/integrations/supabase/client';
import {
  CardY2K,
  CardY2KHeader,
  CardY2KTitle,
  CardY2KContent,
} from '@/components/y2k/CardY2K';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { BadgeY2K } from '@/components/y2k/BadgeY2K';
import { Input } from '@/components/ui/input';
import { toast } from 'sonner';
import { getLabelProfession } from '@/lib/constantes';
import { extraireMessageErreur } from '@/lib/erreurs';
import {
  ajouterRepliMissionPonctuelle,
  creneauxPrevisionnels,
  type CreneauPointage,
} from '@/lib/disponibilite-pointage';
import { addDays, format, startOfWeek, endOfWeek, parseISO } from 'date-fns';
import { fr } from 'date-fns/locale';
import {
  CalendarDays,
  Zap,
  User,
  AlertTriangle,
  CheckCircle2,
  ChevronRight,
  RefreshCw,
} from 'lucide-react';

type MissionSource = {
  id: string;
  intitule: string;
  statut: string;
  profession_requise: string;
  service: string | null;
  debut_le: string;
  fin_le: string;
  est_urgente: boolean;
  etablissement_id: string;
  soignant_assigne_id: string | null;
};

type CreneauPlanning = CreneauPointage & {
  mission_id: string;
};

type MissionPlanning = MissionSource & {
  occurrence_id: string;
  creneau_debut: string;
  creneau_fin: string;
  etablissement_nom: string;
  etablissement_ville: string | null;
  soignant_nom: string | null;
};

const getMonday = (d: Date) => startOfWeek(d, { weekStartsOn: 1 });
const getSunday = (d: Date) => endOfWeek(d, { weekStartsOn: 1 });
const toInputDate = (d: Date) => format(d, 'yyyy-MM-dd');

const STATUT_LABEL: Record<string, string> = {
  OUVERTE: 'Ouverte',
  ASSIGNEE: 'Assignée',
  EN_COURS: 'Active',
  TERMINEE: 'Terminée',
  ANNULEE: 'Annulée',
};

function statutBadge(statut: string) {
  const map: Record<string, 'success' | 'warning' | 'error' | 'info'> = {
    OUVERTE: 'warning',
    ASSIGNEE: 'info',
    EN_COURS: 'success',
    TERMINEE: 'success',
    ANNULEE: 'error',
  };
  return <BadgeY2K variant={map[statut] ?? 'info'} size="sm">{STATUT_LABEL[statut] ?? statut}</BadgeY2K>;
}

function formatHeure(iso: string) {
  return format(parseISO(iso), 'HH:mm');
}

function groupByDay(missions: MissionPlanning[]): Map<string, MissionPlanning[]> {
  const map = new Map<string, MissionPlanning[]>();
  for (const m of missions) {
    const day = format(parseISO(m.creneau_debut), 'yyyy-MM-dd');
    if (!map.has(day)) map.set(day, []);
    map.get(day)!.push(m);
  }
  return map;
}

export default function AdminPlanningGlobal() {
  usePageTitle('Planning global');

  const today = new Date();
  const [debut, setDebut] = useState(toInputDate(getMonday(today)));
  const [fin, setFin] = useState(toInputDate(getSunday(today)));
  const [missions, setMissions] = useState<MissionPlanning[]>([]);
  const [loading, setLoading] = useState(false);
  const [charged, setCharged] = useState(false);
  const [erreurChargement, setErreurChargement] = useState<string | null>(null);

  const charger = async () => {
    setLoading(true);
    setErreurChargement(null);
    try {
      const debutPeriode = parseISO(debut);
      const finPeriodeExclusive = addDays(parseISO(fin), 1);
      if (!Number.isFinite(debutPeriode.getTime())
        || !Number.isFinite(finPeriodeExclusive.getTime())
        || debutPeriode >= finPeriodeExclusive) {
        throw new Error('La période sélectionnée est invalide.');
      }

      // La plage globale sert uniquement à trouver les missions candidates.
      // Les jours et horaires affichés proviennent ensuite exclusivement des
      // créneaux PREVISIONNEL, sauf repli legacy d'une mission <= 24 h.
      const { data: missionsData, error: missionsError } = await supabase
        .from('missions')
        .select('id, intitule, statut, profession_requise, service, debut_le, fin_le, est_urgente, etablissement_id, soignant_assigne_id')
        .gt('fin_le', debutPeriode.toISOString())
        .lt('debut_le', finPeriodeExclusive.toISOString())
        .order('debut_le');
      if (missionsError) throw missionsError;

      const sources = (missionsData ?? []) as MissionSource[];
      if (sources.length === 0) {
        setMissions([]);
        setCharged(true);
        return;
      }

      const missionIds = sources.map((mission) => mission.id);
      const etablissementIds = [...new Set(sources.map((mission) => mission.etablissement_id))];
      const soignantIds = [...new Set(
        sources
          .map((mission) => mission.soignant_assigne_id)
          .filter((id): id is string => Boolean(id)),
      )];

      const [resCreneaux, resEtablissements, resSoignants] = await Promise.all([
        supabase
          .from('mission_creneaux')
          .select('id, mission_id, debut, fin, est_pause, type_creneau')
          .in('mission_id', missionIds)
          .eq('type_creneau', 'PREVISIONNEL')
          .eq('est_pause', false)
          .not('fin', 'is', null)
          .order('debut'),
        supabase
          .from('etablissements')
          .select('id, nom, adresse_ville')
          .in('id', etablissementIds),
        soignantIds.length > 0
          ? supabase.from('soignants').select('id, prenom, nom').in('id', soignantIds)
          : Promise.resolve({ data: [], error: null }),
      ]);

      const erreurDependance = resCreneaux.error
        || resEtablissements.error
        || resSoignants.error;
      if (erreurDependance) throw erreurDependance;

      const creneauxParMission = new Map<string, CreneauPointage[]>();
      for (const creneau of (resCreneaux.data ?? []) as CreneauPlanning[]) {
        const liste = creneauxParMission.get(creneau.mission_id) ?? [];
        liste.push(creneau);
        creneauxParMission.set(creneau.mission_id, liste);
      }
      const etablissements = new Map(
        (resEtablissements.data ?? []).map((etablissement) => [etablissement.id, etablissement]),
      );
      const soignants = new Map(
        (resSoignants.data ?? []).map((soignant) => [soignant.id, soignant]),
      );

      const occurrences = sources
        .flatMap((mission) => {
          const creneaux = creneauxPrevisionnels(ajouterRepliMissionPonctuelle(
            creneauxParMission.get(mission.id) ?? [],
            mission,
          ));
          const etablissement = etablissements.get(mission.etablissement_id);
          const soignant = mission.soignant_assigne_id
            ? soignants.get(mission.soignant_assigne_id)
            : null;

          return creneaux
            .filter((creneau) => (
              Boolean(creneau.fin)
              && new Date(creneau.debut) < finPeriodeExclusive
              && new Date(creneau.fin!) > debutPeriode
            ))
            .map((creneau) => ({
              ...mission,
              occurrence_id: `${mission.id}:${creneau.id ?? creneau.debut}`,
              creneau_debut: creneau.debut,
              creneau_fin: creneau.fin!,
              etablissement_nom: etablissement?.nom ?? 'Établissement inconnu',
              etablissement_ville: etablissement?.adresse_ville ?? null,
              soignant_nom: soignant
                ? `${soignant.prenom ?? ''} ${soignant.nom ?? ''}`.trim()
                : null,
            }));
        })
        .sort((a, b) => a.creneau_debut.localeCompare(b.creneau_debut));

      setMissions(occurrences);
      setCharged(true);
    } catch (err: unknown) {
      const message = extraireMessageErreur(err);
      setMissions([]);
      setCharged(true);
      setErreurChargement(message);
      toast.error(message);
    } finally {
      setLoading(false);
    }
  };

  const grouped = groupByDay(missions);
  const sortedDays = Array.from(grouped.keys()).sort();

  // Bandeau « À pourvoir » : missions ouvertes sans soignant, urgentes en premier puis par date de début.
  const aPourvoir = missions
    .filter((m) => m.statut === 'OUVERTE' && !m.soignant_nom)
    .sort((a, b) => {
      if (a.est_urgente !== b.est_urgente) return a.est_urgente ? -1 : 1;
      return a.creneau_debut.localeCompare(b.creneau_debut);
    });

  return (
    <LayoutAdmin>
      <BreadcrumbAdmin pageName="Planning global" />
      <div className="space-y-6">
        <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4">
          <h1 className="text-2xl font-bold text-foreground flex items-center gap-2">
            <CalendarDays className="h-6 w-6 text-primary" />
            Planning global
          </h1>
        </div>

        {/* Filtres */}
        <CardY2K noPadding>
          <CardY2KContent className="pt-4">
            <div className="flex flex-col sm:flex-row items-end gap-3">
              <div className="flex flex-col gap-1 flex-1">
                <label htmlFor="admin-planning-debut" className="text-xs text-muted-foreground font-medium">Début</label>
                <Input
                  id="admin-planning-debut"
                  type="date"
                  value={debut}
                  onChange={(e) => setDebut(e.target.value)}
                  className="text-base md:text-sm"
                />
              </div>
              <div className="flex flex-col gap-1 flex-1">
                <label htmlFor="admin-planning-fin" className="text-xs text-muted-foreground font-medium">Fin</label>
                <Input
                  id="admin-planning-fin"
                  type="date"
                  value={fin}
                  onChange={(e) => setFin(e.target.value)}
                  className="text-base md:text-sm"
                />
              </div>
              <BoutonY2K onClick={charger} disabled={loading} className="min-w-[120px]">
                {loading ? 'Chargement…' : 'Charger'}
              </BoutonY2K>
            </div>
          </CardY2KContent>
        </CardY2K>

        {erreurChargement && (
          <CardY2K noPadding className="border-destructive/40" data-testid="erreur-planning">
            <CardY2KContent className="py-5" role="alert">
              <div className="flex items-start gap-3">
                <AlertTriangle className="h-5 w-5 shrink-0 text-destructive" />
                <div className="flex-1">
                  <p className="font-semibold text-foreground">Impossible de charger le planning</p>
                  <p className="mt-1 text-sm text-muted-foreground">{erreurChargement}</p>
                  <BoutonY2K onClick={charger} disabled={loading} className="mt-3">
                    <RefreshCw className="h-4 w-4" /> Réessayer
                  </BoutonY2K>
                </div>
              </div>
            </CardY2KContent>
          </CardY2K>
        )}

        {/* Bandeau « À pourvoir sur la période » */}
        {charged && !erreurChargement && aPourvoir.length > 0 && (
          <CardY2K noPadding className="border-warning/60" data-testid="bandeau-a-pourvoir">
            <CardY2KHeader>
              <CardY2KTitle className="text-base flex items-center gap-2">
                <AlertTriangle className="h-4 w-4 text-warning shrink-0" />
                À pourvoir sur la période
              </CardY2KTitle>
              <span className="text-xs text-muted-foreground ml-2">
                {aPourvoir.length} créneau{aPourvoir.length > 1 ? 'x' : ''} sans soignant
              </span>
            </CardY2KHeader>
            <CardY2KContent className="p-0">
              <div className="divide-y divide-border">
                {aPourvoir.map((m) => (
                  <Link
                    key={m.occurrence_id}
                    to={`/admin/missions/${m.id}`}
                    className="flex flex-col sm:flex-row sm:items-center gap-2 px-4 py-3 hover:bg-muted/50 transition-colors"
                  >
                    {/* Date + horaires */}
                    <div className="text-xs font-mono text-muted-foreground min-w-[150px] shrink-0 capitalize">
                      {format(parseISO(m.creneau_debut), 'EEE dd MMM', { locale: fr })} · {formatHeure(m.creneau_debut)} → {formatHeure(m.creneau_fin)}
                    </div>
                    {/* Intitulé + établissement */}
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-1.5 flex-wrap">
                        <span className="font-medium text-sm text-foreground truncate">{m.intitule}</span>
                        {m.est_urgente && (
                          <BadgeY2K variant="error" size="sm" icone={<Zap className="h-3 w-3" />}>Urgent</BadgeY2K>
                        )}
                      </div>
                      <div className="text-xs text-muted-foreground truncate">
                        {m.etablissement_nom}{m.etablissement_ville ? ` · ${m.etablissement_ville}` : ''}
                        {m.service ? ` · ${m.service}` : ''}
                      </div>
                    </div>
                    {/* Profession */}
                    <div className="shrink-0">
                      <BadgeY2K variant="info" size="sm">{getLabelProfession(m.profession_requise)}</BadgeY2K>
                    </div>
                    {/* Lien vers la mission */}
                    <span className="flex items-center gap-0.5 text-xs font-medium text-primary shrink-0">
                      Voir la mission <ChevronRight className="h-3.5 w-3.5" />
                    </span>
                  </Link>
                ))}
              </div>
            </CardY2KContent>
          </CardY2K>
        )}

        {/* Mini état succès discret : tout est pourvu sur la période */}
        {charged && !erreurChargement && missions.length > 0 && aPourvoir.length === 0 && (
          <p className="flex items-center gap-1.5 text-sm text-muted-foreground" data-testid="tout-pourvu">
            <CheckCircle2 className="h-4 w-4 text-success shrink-0" />
            Tous les créneaux de la période sont pourvus.
          </p>
        )}

        {/* Résultats */}
        {charged && !erreurChargement && missions.length === 0 && (
          <CardY2K noPadding>
            <CardY2KContent className="py-10 text-center text-muted-foreground">
              Aucun créneau planifié sur cette période.
            </CardY2KContent>
          </CardY2K>
        )}

        {sortedDays.map((day) => {
          const dayMissions = grouped.get(day)!;
          const label = format(parseISO(day), 'EEEE dd MMMM yyyy', { locale: fr });
          return (
            <CardY2K key={day} noPadding>
              <CardY2KHeader>
                <CardY2KTitle className="text-base capitalize">{label}</CardY2KTitle>
                <span className="text-xs text-muted-foreground ml-2">
                  {dayMissions.length} créneau{dayMissions.length > 1 ? 'x' : ''}
                </span>
              </CardY2KHeader>
              <CardY2KContent className="p-0">
                <div className="divide-y divide-border">
                  {dayMissions.map((m) => (
                    <div key={m.occurrence_id} className="flex flex-col sm:flex-row sm:items-center gap-2 px-4 py-3">
                      {/* Horaires */}
                      <div className="text-xs font-mono text-muted-foreground min-w-[80px] shrink-0">
                        {formatHeure(m.creneau_debut)} → {formatHeure(m.creneau_fin)}
                      </div>
                      {/* Intitulé + service */}
                      <div className="flex-1 min-w-0">
                        <div className="flex items-center gap-1.5 flex-wrap">
                          <span className="font-medium text-sm text-foreground truncate">{m.intitule}</span>
                          {m.est_urgente && (
                            <BadgeY2K variant="error" size="sm" icone={<Zap className="h-3 w-3" />}>Urgent</BadgeY2K>
                          )}
                        </div>
                        <div className="text-xs text-muted-foreground truncate">
                          {m.etablissement_nom}{m.etablissement_ville ? ` · ${m.etablissement_ville}` : ''}
                          {m.service ? ` · ${m.service}` : ''}
                        </div>
                      </div>
                      {/* Profession */}
                      <div className="shrink-0">
                        <BadgeY2K variant="info" size="sm">{getLabelProfession(m.profession_requise)}</BadgeY2K>
                      </div>
                      {/* Statut */}
                      <div className="shrink-0">{statutBadge(m.statut)}</div>
                      {/* Soignant */}
                      <div className="flex items-center gap-1 text-xs text-muted-foreground shrink-0 min-w-[120px]">
                        <User className="h-3.5 w-3.5 shrink-0" />
                        {m.soignant_nom || <span className="italic">Non pourvu</span>}
                      </div>
                    </div>
                  ))}
                </div>
              </CardY2KContent>
            </CardY2K>
          );
        })}
      </div>
    </LayoutAdmin>
  );
}
