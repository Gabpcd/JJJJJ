import React, { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { format, differenceInSeconds, startOfWeek } from 'date-fns';
import { fr } from 'date-fns/locale';
import { toast } from '@/hooks/use-toast';
import { Button } from '@/components/ui/button';
import { ModalAttestationHebdo } from '@/components/ModalAttestationHebdo';

const EXPIRATION_MINUTES = 120; // 2h

interface Props {
  proposition: any;
  onTraitee: (id: string) => void;
}

export function CarteProposition({ proposition, onTraitee }: Props) {
  const navigate = useNavigate();
  const { user } = useAuth();
  const [loading, setLoading] = useState<'accept' | 'refuse' | null>(null);
  const [restant, setRestant] = useState('');
  const [expiree, setExpiree] = useState(false);
  const [showAttestation, setShowAttestation] = useState(false);
  const [typeExercice, setTypeExercice] = useState<string>('SALARIE');
  const [heuresJoleneSemaine, setHeuresJoleneSemaine] = useState(0);

  const mission = proposition.missions;
  const creeLe = new Date(proposition.cree_le);
  const expiration = new Date(creeLe.getTime() + EXPIRATION_MINUTES * 60 * 1000);

  useEffect(() => {
    if (!user) return;
    // Load type_exercice
    supabase.from('soignants').select('type_exercice').eq('id', user.id).single().then(({ data }) => {
      if (data) setTypeExercice((data as any).type_exercice || 'SALARIE');
    });
  }, [user]);

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

  const checkAttestationNeeded = async (): Promise<boolean> => {
    if (!user || typeExercice === 'LIBERAL') return false;
    if (!mission.debut_le) return false;

    const missionDate = new Date(mission.debut_le);
    const lundi = startOfWeek(missionDate, { weekStartsOn: 1 });
    const lundiISO = lundi.toISOString().split('T')[0];

    // Check if attestation already exists for this week
    const { data } = await supabase.from('attestations_heures_externes')
      .select('id')
      .eq('soignant_id', user.id)
      .eq('semaine_du', lundiISO)
      .limit(1);

    if (data && data.length > 0) return false; // Already filled

    // Get Jolene hours this week
    const dimanche = new Date(lundi);
    dimanche.setDate(lundi.getDate() + 7);
    const { data: msSemaine } = await supabase.from('missions')
      .select('duree_heures')
      .eq('soignant_assigne_id', user.id)
      .in('statut', ['ASSIGNEE', 'EN_COURS', 'TERMINEE'])
      .gte('debut_le', lundi.toISOString())
      .lt('debut_le', dimanche.toISOString());

    const h = (msSemaine || []).reduce((t: number, m: any) => t + (m.duree_heures || 0), 0);
    setHeuresJoleneSemaine(h);
    return true; // Need attestation
  };

  const handleAction = async (action: 'ACCEPTEE' | 'REFUSEE') => {
    if (action === 'ACCEPTEE') {
      // Check if attestation needed for SALARIE/MIXTE
      const needAttestation = await checkAttestationNeeded();
      if (needAttestation) {
        setShowAttestation(true);
        return;
      }
    }
    await executeAction(action);
  };

  const executeAction = async (action: 'ACCEPTEE' | 'REFUSEE') => {
    setLoading(action === 'ACCEPTEE' ? 'accept' : 'refuse');
    try {
      const { data, error } = await supabase.rpc('fn_repondre_proposition' as any, {
        p_candidature_id: proposition.id,
        p_accepter: action === 'ACCEPTEE',
      });
      if (error) throw error;

      if ((data as any)?.error === 'E16_CANDIDATURE_ORPHELINE') {
        toast({
          title: 'Proposition obsolète',
          description: 'Cette proposition date d\'avant une mise à jour. Merci de postuler directement depuis la mission dans votre espace.',
        });
        onTraitee(proposition.id);
        return;
      }

      if ((data as any)?.error) throw new Error((data as any).error);

      if (action === 'ACCEPTEE') {
        toast({ title: 'Mission acceptée ✅', description: 'Signez le contrat pour confirmer.' });
        onTraitee(proposition.id);
        navigate(`/soignant/missions/${proposition.mission_id}`);
      } else {
        toast({ title: 'Mission déclinée', description: 'La proposition a été refusée.' });
        onTraitee(proposition.id);
      }
    } catch (err: any) {
      toast({ title: 'Erreur', description: 'Impossible de traiter la proposition. Veuillez réessayer.', variant: 'destructive' });
    } finally {
      setLoading(null);
    }
  };

  const semaineISO = mission.debut_le
    ? startOfWeek(new Date(mission.debut_le), { weekStartsOn: 1 }).toISOString().split('T')[0]
    : '';

  return (
    <>
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
          <Button size="sm" className="flex-1" disabled={!!loading} onClick={() => handleAction('ACCEPTEE')}>
            {loading === 'accept' ? '...' : '✅ Accepter'}
          </Button>
          <Button size="sm" variant="outline" className="flex-1" disabled={!!loading} onClick={() => handleAction('REFUSEE')}>
            {loading === 'refuse' ? '...' : '❌ Refuser'}
          </Button>
        </div>
      </div>

      {showAttestation && (
        <ModalAttestationHebdo
          semaineISO={semaineISO}
          heuresJoleneSemaine={heuresJoleneSemaine}
          onValidated={() => {
            setShowAttestation(false);
            executeAction('ACCEPTEE');
          }}
          onCancel={() => setShowAttestation(false)}
        />
      )}
    </>
  );
}
