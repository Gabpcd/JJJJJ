import React, { useState, useEffect } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { LayoutApp } from '@/components/LayoutApp';
import { FormulaireMission } from '@/components/FormulaireMission';
import { ChargementPage } from '@/components/ChargementPage';
import { supabase } from '@/integrations/supabase/client';

export default function ModifierMission() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const [mission, setMission] = useState<any>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!id) return;
    supabase.from('missions').select('id, intitule, description, service, profession_requise, debut_le, fin_le, taux_horaire_base, est_urgente, niveau_urgence, statut').eq('id', id).single().then(({ data, error }) => {
      if (error) console.error('[ModifierMission] Erreur chargement:', error.message);
      setMission(data);
      setLoading(false);
    }).catch(() => setLoading(false));
  }, [id]);

  if (loading) return <LayoutApp role="ADMIN_ETABLISSEMENT"><ChargementPage /></LayoutApp>;

  if (!mission || mission.statut !== 'OUVERTE') {
    return (
      <LayoutApp role="ADMIN_ETABLISSEMENT">
        <div className="text-center py-12">
          <p className="text-lg font-semibold text-foreground mb-2">Cette mission ne peut plus être modifiée</p>
          <p className="text-sm text-muted-foreground mb-4">Seules les missions ouvertes peuvent être éditées.</p>
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
