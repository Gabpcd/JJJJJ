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
import { format, startOfWeek, endOfWeek, parseISO } from 'date-fns';
import { fr } from 'date-fns/locale';
import { CalendarDays, Zap, User, AlertTriangle, CheckCircle2, ChevronRight } from 'lucide-react';

type MissionPlanning = {
  id: string;
  intitule: string;
  statut: string;
  profession_requise: string;
  service: string | null;
  debut_le: string;
  fin_le: string;
  est_urgente: boolean;
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
  EN_COURS: 'En cours',
  TERMINEE: 'Terminée',
  ANNULEE: 'Annulée',
};

function statutBadge(statut: string) {
  const map: Record<string, 'success' | 'warning' | 'error' | 'info'> = {
    OUVERTE: 'warning',
    ASSIGNEE: 'info',
    EN_COURS: 'info',
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
    const day = m.debut_le.slice(0, 10);
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

  const charger = async () => {
    setLoading(true);
    try {
      const { data, error } = await supabase.rpc('fn_admin_planning_global' as any, {
        p_debut: debut,
        p_fin: fin,
      });
      if (error) throw error;
      const result = (data as any);
      if (!result?.success) {
        toast.error(result?.error || 'Erreur lors du chargement du planning');
        return;
      }
      setMissions(result.missions || []);
      setCharged(true);
    } catch (err: any) {
      toast.error(err?.message || 'Erreur lors du chargement du planning');
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
      return a.debut_le.localeCompare(b.debut_le);
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

        {/* Bandeau « À pourvoir sur la période » */}
        {charged && aPourvoir.length > 0 && (
          <CardY2K noPadding className="border-warning/60" data-testid="bandeau-a-pourvoir">
            <CardY2KHeader>
              <CardY2KTitle className="text-base flex items-center gap-2">
                <AlertTriangle className="h-4 w-4 text-warning shrink-0" />
                À pourvoir sur la période
              </CardY2KTitle>
              <span className="text-xs text-muted-foreground ml-2">
                {aPourvoir.length} mission{aPourvoir.length > 1 ? 's' : ''} sans soignant
              </span>
            </CardY2KHeader>
            <CardY2KContent className="p-0">
              <div className="divide-y divide-border">
                {aPourvoir.map((m) => (
                  <Link
                    key={m.id}
                    to={`/admin/missions/${m.id}`}
                    className="flex flex-col sm:flex-row sm:items-center gap-2 px-4 py-3 hover:bg-muted/50 transition-colors"
                  >
                    {/* Date + horaires */}
                    <div className="text-xs font-mono text-muted-foreground min-w-[150px] shrink-0 capitalize">
                      {format(parseISO(m.debut_le), 'EEE dd MMM', { locale: fr })} · {formatHeure(m.debut_le)} → {formatHeure(m.fin_le)}
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
        {charged && missions.length > 0 && aPourvoir.length === 0 && (
          <p className="flex items-center gap-1.5 text-sm text-muted-foreground" data-testid="tout-pourvu">
            <CheckCircle2 className="h-4 w-4 text-success shrink-0" />
            Toutes les missions de la période sont pourvues.
          </p>
        )}

        {/* Résultats */}
        {charged && missions.length === 0 && (
          <CardY2K noPadding>
            <CardY2KContent className="py-10 text-center text-muted-foreground">
              Aucune mission sur cette période.
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
                <span className="text-xs text-muted-foreground ml-2">{dayMissions.length} mission{dayMissions.length > 1 ? 's' : ''}</span>
              </CardY2KHeader>
              <CardY2KContent className="p-0">
                <div className="divide-y divide-border">
                  {dayMissions.map((m) => (
                    <div key={m.id} className="flex flex-col sm:flex-row sm:items-center gap-2 px-4 py-3">
                      {/* Horaires */}
                      <div className="text-xs font-mono text-muted-foreground min-w-[80px] shrink-0">
                        {formatHeure(m.debut_le)} → {formatHeure(m.fin_le)}
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
