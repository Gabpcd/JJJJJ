import React, { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { format, differenceInSeconds, startOfWeek } from 'date-fns';
import { fr } from 'date-fns/locale';
import { toast } from '@/hooks/use-toast';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { ModalAttestationHebdo } from '@/components/ModalAttestationHebdo';

const EXPIRATION_MINUTES = 120; // 2h

interface MissionProposee {
  id?: string;
  intitule?: string;
  debut_le?: string;
  fin_le?: string;
  duree_heures?: number | null;
  taux_horaire_base?: number | null;
  net_estime?: number | null;
  type_contrat_recherche?: string | null;
  etablissement_id?: string;
  est_urgente?: boolean | null;
  etab_nom?: string | null;
}

export interface PropositionMission extends MissionProposee {
  id: string;
  mission_id: string;
  cree_le: string;
  type_contrat_choisi?: string | null;
  missions?: MissionProposee | null;
}

interface ReponseProposition {
  success?: boolean;
  error?: string;
}

interface Props {
  proposition: PropositionMission;
  onTraitee: (id: string) => void;
}

export function CarteProposition({ proposition, onTraitee }: Props) {
  const navigate = useNavigate();
  const { user } = useAuth();
  const [loading, setLoading] = useState<'accept' | 'refuse' | null>(null);
  const [restant, setRestant] = useState('');
  const [expiree, setExpiree] = useState(false);
  const [showAttestation, setShowAttestation] = useState(false);
  const [heuresJoleneSemaine, setHeuresJoleneSemaine] = useState(0);

  // Le dashboard canonique renvoie la relation dans `missions`. Le repli sur
  // l'objet lui-même garde la carte compatible avec une réponse mise en cache
  // produite par l'ancienne version aplatie du RPC pendant le déploiement.
  const mission = proposition.missions ?? proposition;
  const contratPropose = proposition.type_contrat_choisi ?? mission?.type_contrat_recherche;
  const expirationMs = new Date(proposition.cree_le).getTime() + EXPIRATION_MINUTES * 60 * 1000;

  useEffect(() => {
    const tick = () => {
      const now = new Date();
      const diffSec = differenceInSeconds(new Date(expirationMs), now);
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
  }, [expirationMs, onTraitee, proposition.id]);

  if (expiree || !mission.intitule || !mission.debut_le || !mission.fin_le) return null;

  const netEstime = mission.taux_horaire_base && mission.debut_le && mission.fin_le
    ? (() => {
        const heures = (new Date(mission.fin_le).getTime() - new Date(mission.debut_le).getTime()) / 3600000;
        return (mission.taux_horaire_base * heures * 0.78);
      })()
    : null;

  const checkAttestationNeeded = async (): Promise<boolean> => {
    // Lot 21 D4 : l'attestation de temps de travail dépend du contrat de la
    // MISSION proposée, jamais du statut déclaré sur le profil.
    if (!user || contratPropose === 'LIBERAL') return false;
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

    const h = (msSemaine || []).reduce((t, m) => t + (Number(m.duree_heures) || 0), 0);
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
      const { data, error } = await supabase.rpc('fn_repondre_proposition', {
        p_candidature_id: proposition.id,
        p_accepter: action === 'ACCEPTEE',
      });
      if (error) throw error;
      const reponse = data as ReponseProposition | null;

      if (reponse?.error === 'E16_CANDIDATURE_ORPHELINE') {
        toast({
          title: 'Proposition obsolète',
          description: 'Cette proposition date d\'avant une mise à jour. Merci de postuler directement depuis la mission dans votre espace.',
        });
        onTraitee(proposition.id);
        return;
      }

      if (reponse?.error === 'Cette proposition a expiré') {
        toast({
          title: 'Proposition expirée',
          description: 'La fenêtre de réponse de 2 heures est terminée.',
        });
        onTraitee(proposition.id);
        return;
      }

      if (reponse?.error) throw new Error(reponse.error);

      if (action === 'ACCEPTEE') {
        toast({ title: 'Mission acceptée ✅', description: 'Signez le contrat pour confirmer.' });
        onTraitee(proposition.id);
        navigate(`/soignant/missions/${proposition.mission_id}`);
      } else {
        toast({ title: 'Mission déclinée', description: 'La proposition a été refusée.' });
        onTraitee(proposition.id);
      }
    } catch {
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
          <BoutonY2K size="sm" className="flex-1" disabled={!!loading} loading={loading === 'accept'} onClick={() => handleAction('ACCEPTEE')}>
            {loading === 'accept' ? '...' : '✅ Accepter'}
          </BoutonY2K>
          <BoutonY2K size="sm" variant="secondary" className="flex-1" disabled={!!loading} loading={loading === 'refuse'} onClick={() => handleAction('REFUSEE')}>
            {loading === 'refuse' ? '...' : '❌ Refuser'}
          </BoutonY2K>
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
