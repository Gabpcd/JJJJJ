import React, { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { supabase } from '@/integrations/supabase/client';
import { format, differenceInMinutes, differenceInSeconds } from 'date-fns';
import { fr } from 'date-fns/locale';
import { toast } from '@/hooks/use-toast';
import { Button } from '@/components/ui/button';

const EXPIRATION_MINUTES = 120; // 2h

interface Props {
  proposition: any;
  onTraitee: (id: string) => void;
}

export function CarteProposition({ proposition, onTraitee }: Props) {
  const navigate = useNavigate();
  const [loading, setLoading] = useState<'accept' | 'refuse' | null>(null);
  const [restant, setRestant] = useState('');
  const [expiree, setExpiree] = useState(false);

  const mission = proposition.missions;
  const creeLe = new Date(proposition.cree_le);
  const expiration = new Date(creeLe.getTime() + EXPIRATION_MINUTES * 60 * 1000);

  useEffect(() => {
    const tick = () => {
      const now = new Date();
      const diffSec = differenceInSeconds(expiration, now);
      if (diffSec <= 0) {
        setExpiree(true);
        setRestant('Expirée');
        onTraitee(proposition.id);
        return;
      }
      const h = Math.floor(diffSec / 3600);
      const m = Math.floor((diffSec % 3600) / 60);
      setRestant(`${h}h ${m.toString().padStart(2, '0')}min`);
    };
    tick();
    const interval = setInterval(tick, 30000);
    return () => clearInterval(interval);
  }, [proposition.cree_le]);

  if (expiree || !mission) return null;

  const netEstime = mission.taux_horaire_base && mission.debut_le && mission.fin_le
    ? (() => {
        const heures = (new Date(mission.fin_le).getTime() - new Date(mission.debut_le).getTime()) / 3600000;
        return (mission.taux_horaire_base * heures * 0.78);
      })()
    : null;

  const handleAction = async (action: 'ACCEPTEE' | 'REFUSEE') => {
    setLoading(action === 'ACCEPTEE' ? 'accept' : 'refuse');
    try {
      console.log('traiter proposition:', { id: proposition.id, mission_id: proposition.mission_id, action });

      if (action === 'ACCEPTEE') {
        // Use fn_accepter_mission to properly assign
        const { data, error } = await supabase.rpc('fn_accepter_mission', {
          p_mission_id: proposition.mission_id,
        });
        console.log('fn_accepter_mission result:', data, error);
        if (error) throw error;

        // Update candidature status
        await supabase.from('candidatures').update({ statut: 'ACCEPTEE', traite_le: new Date().toISOString() }).eq('id', proposition.id);

        toast({ title: 'Mission acceptée ✅', description: 'Signez le contrat pour confirmer.' });
        onTraitee(proposition.id);
        navigate(`/soignant/missions/${proposition.mission_id}`);
      } else {
        // For refusal, update candidature directly
        const { error } = await supabase.from('candidatures').update({ statut: 'REFUSEE', traite_le: new Date().toISOString() }).eq('id', proposition.id);
        console.log('refus result:', error);
        if (error) throw error;

        toast({ title: 'Mission déclinée', description: 'La proposition a été refusée.' });
        onTraitee(proposition.id);
      }
    } catch (err: any) {
      console.error('proposition action error:', err);
      toast({ title: 'Erreur', description: err.message || 'Impossible de traiter la proposition', variant: 'destructive' });
    } finally {
      setLoading(null);
    }
  };

  return (
    <div className="rounded-xl border-2 border-orange-400 bg-orange-50 dark:bg-orange-950/20 dark:border-orange-600 p-4 space-y-2">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          {mission.est_urgente && (
            <span className="inline-flex items-center rounded-full bg-destructive px-2 py-0.5 text-[10px] font-semibold text-destructive-foreground">🚨 URGENT</span>
          )}
          <h3 className="font-semibold text-sm text-foreground">{mission.intitule}</h3>
        </div>
        <span className="text-xs font-medium text-orange-600 dark:text-orange-400 whitespace-nowrap">⏳ {restant}</span>
      </div>

      <p className="text-xs text-muted-foreground">
        📅 {format(new Date(mission.debut_le), "EEE d MMM · HH'h'mm", { locale: fr })} → {format(new Date(mission.fin_le), "HH'h'mm", { locale: fr })}
      </p>

      <div className="flex items-center justify-between">
        <span className="text-sm font-bold text-primary">{mission.taux_horaire_base} €/h</span>
        {netEstime && (
          <span className="text-xs text-muted-foreground">
            Net estimé* : {new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(netEstime)}
          </span>
        )}
      </div>

      <div className="flex gap-2 pt-1">
        <Button
          size="sm"
          className="flex-1"
          disabled={!!loading}
          onClick={() => handleAction('ACCEPTEE')}
        >
          {loading === 'accept' ? '...' : '✅ Accepter'}
        </Button>
        <Button
          size="sm"
          variant="outline"
          className="flex-1"
          disabled={!!loading}
          onClick={() => handleAction('REFUSEE')}
        >
          {loading === 'refuse' ? '...' : '❌ Refuser'}
        </Button>
      </div>
    </div>
  );
}
