import React, { useState, useEffect } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { LayoutApp } from '@/components/LayoutApp';
import { FormulaireMission } from '@/components/FormulaireMission';
import { ChargementPage } from '@/components/ChargementPage';
import { supabase } from '@/integrations/supabase/client';
import { logger } from '@/lib/logger';

export default function ModifierMission() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const [mission, setMission] = useState<any>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!id) return;
    (async () => {
      const { data, error } = await supabase.from('missions').select(`
        id, intitule, description, service, profession_requise,
        debut_le, fin_le, taux_horaire_base, est_urgente, niveau_urgence,
        mode_attribution, type_contrat_recherche,
        specialite_medicale_requise, accepte_non_specialises,
        nb_creneaux, statut
      `).eq('id', id).single();
      if (error) logger.error('[ModifierMission] Erreur chargement', error);
      setMission(data);
      setLoading(false);
    })();
  }, [id]);

  if (loading) return <LayoutApp role="ADMIN_ETABLISSEMENT"><ChargementPage /></LayoutApp>;

  if (!mission || mission.statut !== 'OUVERTE') {
    return (
      <LayoutApp role="ADMIN_ETABLISSEMENT">
        <div className="text-center py-12">
          <h1 className="text-lg font-semibold text-foreground mb-2">
            {!mission ? 'Mission introuvable' : 'Modification impossible'}
          </h1>
          <p className="text-sm text-muted-foreground mb-4">
            {!mission
              ? 'Cette mission n\'existe pas ou vous n\'avez pas les droits pour y accéder.'
              : `Cette mission ne peut pas être modifiée car elle est au statut actuel. Seules les missions au statut « Ouverte » sont modifiables.`}
          </p>
          <button onClick={() => navigate('/etablissement/missions')} className="btn-primary">Retour aux missions</button>
        </div>
      </LayoutApp>
    );
  }

  return (
    <LayoutApp role="ADMIN_ETABLISSEMENT">
      <div className="max-w-2xl mx-auto">
        <button onClick={() => navigate(`/etablissement/missions/${id}`)} className="text-sm text-primary hover:underline mb-4 inline-block">
          ← Retour au détail
        </button>
        <h1 className="text-xl font-bold text-foreground mb-6">✏️ Modifier la mission</h1>
        <div className="card-base">
          <FormulaireMission missionSource={mission} modeEdition />
        </div>
      </div>
    </LayoutApp>
  );
}
