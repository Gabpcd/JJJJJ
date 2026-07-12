import React, { useState, useEffect } from 'react';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { BreadcrumbAdmin } from '@/components/BreadcrumbAdmin';
import { ChargementPage } from '@/components/ChargementPage';
import { supabase } from '@/integrations/supabase/client';
import { usePageTitle } from '@/hooks/usePageTitle';
import { ChevronLeft, ChevronRight } from 'lucide-react';
import { BadgeY2K } from '@/components/y2k/BadgeY2K';
import {
  format, startOfMonth, endOfMonth, startOfWeek, endOfWeek,
  addMonths, addDays, isSameMonth, isSameDay, isToday
} from 'date-fns';
import { fr } from 'date-fns/locale';
import { useNavigate } from 'react-router-dom';
import { BADGES_STATUT } from '@/lib/constantes';

const JOURS_SEMAINE = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];

type MissionCal = {
  id: string;
  intitule: string;
  debut_le: string;
  fin_le: string;
  statut: string;
  soignant_assigne_id: string | null;
  etablissement_id: string;
  profession_requise: string;
  service: string | null;
  est_urgente: boolean;
  etab_nom?: string;
  soignant_nom?: string;
};

function getStatutStyle(m: MissionCal): { bg: string; text: string; label: string } {
  if (m.statut === 'OUVERTE' && !m.soignant_assigne_id) {
    return { bg: 'bg-destructive', text: 'text-destructive-foreground', label: 'Non pourvue' };
  }
  switch (m.statut) {
    case 'OUVERTE': return { bg: 'bg-warning', text: 'text-warning-foreground', label: 'Ouverte' };
    case 'ASSIGNEE': return { bg: 'bg-info', text: 'text-info-foreground', label: 'Assignée' };
    case 'EN_COURS': return { bg: 'bg-success', text: 'text-success-foreground', label: 'En cours' };
    case 'TERMINEE': return { bg: 'bg-muted-foreground/40', text: 'text-foreground', label: 'Terminée' };
    case 'ANNULEE_PAR_ETABLISSEMENT':
    case 'ANNULEE_PAR_SOIGNANT': return { bg: 'bg-destructive/60', text: 'text-destructive-foreground', label: 'Annulée' };
    default: return { bg: 'bg-muted', text: 'text-muted-foreground', label: BADGES_STATUT[m.statut]?.label || 'Autre' };
  }
}

export default function AdminCalendrier() {
  usePageTitle('Calendrier missions');
  const navigate = useNavigate();
  const [moisCourant, setMoisCourant] = useState(new Date());
  const [missions, setMissions] = useState<MissionCal[]>([]);
  const [loading, setLoading] = useState(true);
  const [filtreStatut, setFiltreStatut] = useState<string | null>(null);

  const debutMois = startOfMonth(moisCourant);
  const finMois = endOfMonth(moisCourant);
  const debutGrille = startOfWeek(debutMois, { weekStartsOn: 1 });
  const finGrille = endOfWeek(finMois, { weekStartsOn: 1 });

  const jours: Date[] = [];
  let jour = debutGrille;
  while (jour <= finGrille) {
    jours.push(jour);
    jour = addDays(jour, 1);
  }

  useEffect(() => {
    setLoading(true);
    supabase
      .from('missions')
      .select('id, intitule, debut_le, fin_le, statut, soignant_assigne_id, etablissement_id, profession_requise, service, est_urgente')
      .gte('fin_le', debutGrille.toISOString())
      .lte('debut_le', finGrille.toISOString())
      .order('debut_le')
      .then(async ({ data }) => {
        const items = (data || []) as MissionCal[];
        if (items.length > 0) {
          const etabIds = [...new Set(items.map(m => m.etablissement_id))];
          const soignantIds = [...new Set(items.map(m => m.soignant_assigne_id).filter(Boolean))] as string[];

          const [resEtabs, resSoignants] = await Promise.all([
            etabIds.length ? supabase.from('etablissements').select('id, nom').in('id', etabIds) : Promise.resolve({ data: [] } as any),
            soignantIds.length ? supabase.from('soignants').select('id, prenom, nom').in('id', soignantIds) : Promise.resolve({ data: [] } as any),
          ]);

          const etabMap = new Map<string, string>((resEtabs.data || []).map((e: any) => [e.id, e.nom]));
          const soignantMap = new Map<string, string>((resSoignants.data || []).map((s: any) => [s.id, `${s.prenom || ''} ${s.nom || ''}`.trim()]));

          items.forEach(m => {
            m.etab_nom = etabMap.get(m.etablissement_id) || '';
            m.soignant_nom = m.soignant_assigne_id ? soignantMap.get(m.soignant_assigne_id) || '' : '';
          });
        }
        setMissions(items);
        setLoading(false);
      });
  }, [moisCourant]);

  function getMissionsDuJour(d: Date) {
    return missions.filter(m => {
      const debut = new Date(m.debut_le);
      const fin = new Date(m.fin_le);
      const jourDebut = new Date(d.getFullYear(), d.getMonth(), d.getDate());
      const jourFin = new Date(d.getFullYear(), d.getMonth(), d.getDate(), 23, 59, 59);
      const dansJour = debut <= jourFin && fin >= jourDebut;
      if (!dansJour) return false;
      if (!filtreStatut) return true;
      if (filtreStatut === 'NON_POURVUE') return m.statut === 'OUVERTE' && !m.soignant_assigne_id;
      return m.statut === filtreStatut;
    });
  }

  // Stats
  const nonPourvues = missions.filter(m => m.statut === 'OUVERTE' && !m.soignant_assigne_id).length;
  const assignees = missions.filter(m => m.statut === 'ASSIGNEE').length;
  const enCours = missions.filter(m => m.statut === 'EN_COURS').length;
  const terminees = missions.filter(m => m.statut === 'TERMINEE').length;

  const LEGENDE = [
    { label: 'Non pourvue', cls: 'bg-destructive' },
    { label: 'Ouverte', cls: 'bg-warning' },
    { label: 'Assignée', cls: 'bg-info' },
    { label: 'En cours', cls: 'bg-success' },
    { label: 'Terminée', cls: 'bg-muted-foreground/40' },
    { label: 'Annulée', cls: 'bg-destructive/60' },
  ];

  if (loading) return <LayoutAdmin><ChargementPage /></LayoutAdmin>;

  return (
    <LayoutAdmin>
      <BreadcrumbAdmin pageName="Calendrier" />
      <div className="space-y-4">
        <h1 className="text-2xl font-bold text-foreground">Calendrier des missions</h1>

        {/* Stats bar */}
        <div className="flex flex-wrap gap-3">
          <BadgeY2K
            variant="error"
            className={`cursor-pointer transition-opacity ${filtreStatut && filtreStatut !== 'NON_POURVUE' ? 'opacity-40' : ''}`}
            onClick={() => setFiltreStatut(f => f === 'NON_POURVUE' ? null : 'NON_POURVUE')}
          >
            {nonPourvues} non pourvue{nonPourvues > 1 ? 's' : ''}
          </BadgeY2K>
          <BadgeY2K
            variant="info"
            className={`cursor-pointer transition-opacity ${filtreStatut && filtreStatut !== 'ASSIGNEE' ? 'opacity-40' : ''}`}
            onClick={() => setFiltreStatut(f => f === 'ASSIGNEE' ? null : 'ASSIGNEE')}
          >
            {assignees} assignée{assignees > 1 ? 's' : ''}
          </BadgeY2K>
          <BadgeY2K
            variant="success"
            className={`cursor-pointer transition-opacity ${filtreStatut && filtreStatut !== 'EN_COURS' ? 'opacity-40' : ''}`}
            onClick={() => setFiltreStatut(f => f === 'EN_COURS' ? null : 'EN_COURS')}
          >
            {enCours} en cours
          </BadgeY2K>
          <BadgeY2K
            variant="info"
            className={`cursor-pointer transition-opacity ${filtreStatut && filtreStatut !== 'TERMINEE' ? 'opacity-40' : ''}`}
            onClick={() => setFiltreStatut(f => f === 'TERMINEE' ? null : 'TERMINEE')}
          >
            {terminees} terminée{terminees > 1 ? 's' : ''}
          </BadgeY2K>
          <BadgeY2K
            variant="info"
            className={`cursor-pointer ${filtreStatut ? 'opacity-60' : ''}`}
            onClick={() => setFiltreStatut(null)}
          >
            {missions.length} total
          </BadgeY2K>
        </div>

        {/* Navigation */}
        <div className="flex items-center justify-between">
          <button onClick={() => setMoisCourant(addMonths(moisCourant, -1))} className="p-2 hover:bg-muted rounded-lg transition-colors" aria-label="Mois précédent">
            <ChevronLeft className="h-5 w-5 text-muted-foreground" />
          </button>
          <div className="text-center">
            <h2 className="text-lg font-bold text-foreground capitalize">
              {format(moisCourant, 'MMMM yyyy', { locale: fr })}
            </h2>
            <button onClick={() => setMoisCourant(new Date())} className="text-xs text-primary font-medium hover:underline mt-0.5">
              Aujourd'hui
            </button>
          </div>
          <button onClick={() => setMoisCourant(addMonths(moisCourant, 1))} className="p-2 hover:bg-muted rounded-lg transition-colors" aria-label="Mois suivant">
            <ChevronRight className="h-5 w-5 text-muted-foreground" />
          </button>
        </div>

        {/* Légende */}
        <div className="flex flex-wrap gap-3 justify-center">
          {LEGENDE.map(l => (
            <div key={l.label} className="flex items-center gap-1.5 text-[11px] text-muted-foreground">
              <span className={`w-2.5 h-2.5 rounded-full ${l.cls}`} />
              {l.label}
            </div>
          ))}
        </div>

        {/* Days header */}
        <div className="grid grid-cols-7 gap-px min-w-[320px]">
          {JOURS_SEMAINE.map(j => (
            <div key={j} className="text-center text-xs font-semibold text-muted-foreground py-2">
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
            const hasNonPourvue = msDuJour.some(m => m.statut === 'OUVERTE' && !m.soignant_assigne_id);

            return (
              <div key={i} className={`min-h-[90px] p-1 rounded-md border transition-colors
                ${dansLeMois ? 'bg-card border-border/50' : 'bg-muted/30 border-transparent'}
                ${estAujourdhui ? 'ring-2 ring-primary/40' : ''}
                ${hasNonPourvue && dansLeMois ? 'border-destructive/50' : ''}
              `}>
                <span className={`text-[11px] font-medium block text-center mb-0.5
                  ${estAujourdhui ? 'text-primary font-bold' : dansLeMois ? 'text-foreground' : 'text-muted-foreground/40'}
                `}>
                  {format(d, 'd')}
                </span>

                <div className="space-y-0.5">
                  {msDuJour.slice(0, 4).map(m => {
                    const style = getStatutStyle(m);
                    return (
                      <button key={m.id}
                        onClick={() => navigate(`/admin/missions/${m.id}`)}
                        className={`w-full rounded px-1 py-0.5 text-[8px] leading-tight truncate block text-left transition-opacity hover:opacity-80 ${style.bg} ${style.text}`}
                        title={`${m.intitule} — ${m.etab_nom || ''}${m.soignant_nom ? ` · ${m.soignant_nom}` : ' · NON POURVUE'}`}
                      >
                        {m.est_urgente ? 'Urgente — ' : ''}{m.intitule}
                      </button>
                    );
                  })}
                  {msDuJour.length > 4 && (
                    <span className="text-[8px] text-muted-foreground block text-center">+{msDuJour.length - 4}</span>
                  )}
                </div>
              </div>
            );
          })}
        </div>
      </div>
    </LayoutAdmin>
  );
}
