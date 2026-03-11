import React, { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { CalendarDays, ChevronRight } from 'lucide-react';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { JaugeProgression } from '@/components/JaugeProgression';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';

function getSemaineActuelle() {
  const now = new Date();
  const jour = now.getDay();
  const lundi = new Date(now);
  lundi.setDate(now.getDate() - (jour === 0 ? 6 : jour - 1));
  lundi.setHours(0, 0, 0, 0);
  const dimanche = new Date(lundi);
  dimanche.setDate(lundi.getDate() + 7);
  return { lundi, dimanche };
}

function getCouleurBarre(heures: number) {
  if (heures >= 44) return 'bg-destructive';
  if (heures >= 36) return 'bg-warning';
  return 'bg-primary';
}

function getMessageHeures(heures: number) {
  const restant = Math.max(0, 48 - heures);
  if (heures >= 48) return { texte: '🛑 Plafond de 48h atteint — vous ne pouvez plus accepter de mission cette semaine', classe: 'text-destructive font-bold' };
  if (heures >= 44) return { texte: `🚨 Quasi plein : seulement ${restant.toFixed(0)}h disponibles`, classe: 'text-destructive' };
  if (heures >= 36) return { texte: `⚠️ Attention : il ne vous reste que ${restant.toFixed(0)}h`, classe: 'text-warning' };
  return { texte: `✅ Il vous reste ${restant.toFixed(0)}h de disponibilité cette semaine`, classe: 'text-primary' };
}

interface CompteurHebdomadaireProps {
  compact?: boolean;
  missionCandidateHeures?: number;
}

export function CompteurHebdomadaire({ compact = false, missionCandidateHeures }: CompteurHebdomadaireProps) {
  const navigate = useNavigate();
  const { user } = useAuth();
  const [missions, setMissions] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const { lundi, dimanche } = getSemaineActuelle();

  useEffect(() => {
    if (!user) return;
    supabase
      .from('missions')
      .select('id, intitule, debut_le, fin_le, duree_heures, statut, etablissements(nom)')
      .eq('soignant_assigne_id', user.id)
      .in('statut', ['ASSIGNEE', 'EN_COURS', 'TERMINEE'])
      .gte('debut_le', lundi.toISOString())
      .lt('debut_le', dimanche.toISOString())
      .order('debut_le', { ascending: true })
      .then(({ data }) => {
        setMissions(data || []);
        setLoading(false);
      });
  }, [user]);

  if (loading) return null;

  const heuresSemaine = missions.reduce((t, m) => t + (m.duree_heures || 0), 0);
  const heuresAffichees = missionCandidateHeures ? heuresSemaine + missionCandidateHeures : heuresSemaine;
  const msg = getMessageHeures(heuresAffichees);

  if (compact) {
    return (
      <div className="card-base">
        <div className="flex items-center justify-between mb-2">
          <span className="text-xs font-semibold text-foreground">📊 Cette semaine</span>
          <span className="text-xs font-bold text-foreground">{heuresAffichees.toFixed(0)}h / 48h</span>
        </div>
        <div className="relative h-2.5 rounded-full bg-muted overflow-hidden">
          <div
            className={`absolute inset-y-0 left-0 rounded-full ${getCouleurBarre(heuresAffichees)} transition-all duration-500`}
            style={{ width: `${Math.min((heuresAffichees / 48) * 100, 100)}%` }}
          />
          {missionCandidateHeures && (
            <div
              className="absolute inset-y-0 rounded-full bg-primary/30 border-r-2 border-dashed border-primary transition-all duration-500"
              style={{
                left: `${Math.min((heuresSemaine / 48) * 100, 100)}%`,
                width: `${Math.min((missionCandidateHeures / 48) * 100, 100 - (heuresSemaine / 48) * 100)}%`,
              }}
            />
          )}
        </div>
        {missionCandidateHeures && (
          <p className="text-[10px] text-muted-foreground mt-1">
            Avec cette mission : {heuresAffichees.toFixed(0)}h / 48h
          </p>
        )}
        <p className={`text-xs mt-1.5 ${msg.classe}`}>{msg.texte}</p>
      </div>
    );
  }

  return (
    <div className="card-base">
      <div className="flex items-center justify-between mb-3">
        <h3 className="text-sm font-bold text-foreground flex items-center gap-2">
          <CalendarDays className="h-4 w-4 text-primary" />
          Ma semaine ({format(lundi, "EEE d", { locale: fr })} → {format(new Date(dimanche.getTime() - 86400000), "EEE d MMM", { locale: fr })})
        </h3>
        <button onClick={() => navigate('/soignant/planning')} className="text-xs text-primary hover:underline flex items-center gap-0.5">
          Planning <ChevronRight className="h-3 w-3" />
        </button>
      </div>

      <div className="flex items-center gap-3 mb-2">
        <div className="flex-1 relative h-3 rounded-full bg-muted overflow-hidden">
          <div
            className={`absolute inset-y-0 left-0 rounded-full ${getCouleurBarre(heuresSemaine)} transition-all duration-700`}
            style={{ width: `${Math.min((heuresSemaine / 48) * 100, 100)}%` }}
          />
        </div>
        <span className="text-sm font-bold text-foreground whitespace-nowrap">{heuresSemaine.toFixed(0)}h / 48h</span>
      </div>

      <p className={`text-xs mb-3 ${msg.classe}`}>{msg.texte}</p>

      {missions.length > 0 && (
        <div className="border-t border-border pt-3 space-y-1.5">
          <p className="text-[10px] font-semibold text-muted-foreground uppercase tracking-wider mb-1">Missions planifiées</p>
          {missions.map(m => (
            <button
              key={m.id}
              onClick={() => navigate(`/soignant/missions/${m.id}`)}
              className="w-full text-left flex items-center gap-2 text-xs text-foreground hover:bg-muted/50 rounded-lg px-2 py-1.5 transition-colors"
            >
              <span className="text-muted-foreground font-medium w-16 shrink-0">
                {format(new Date(m.debut_le), 'EEE d', { locale: fr })}
              </span>
              <span className="truncate flex-1">{m.intitule} ({m.etablissements?.nom})</span>
              <span className="text-muted-foreground shrink-0">
                {format(new Date(m.debut_le), "HH'h'mm", { locale: fr })}→{format(new Date(m.fin_le), "HH'h'mm", { locale: fr })} ({m.duree_heures || 0}h)
              </span>
            </button>
          ))}
        </div>
      )}
    </div>
  );
}
