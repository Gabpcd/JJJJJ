import React, { useState, useEffect } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { LayoutApp } from '@/components/LayoutApp';
import { FormulaireMission } from '@/components/FormulaireMission';
import { ChargementPage } from '@/components/ChargementPage';
import { supabase } from '@/integrations/supabase/client';
import { logger } from '@/lib/logger';
import { usePageTitle } from '@/hooks/usePageTitle';
import { construirePlanningCandidat } from '@/components/planning/planning-candidat';

export default function ModifierMission() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const [mission, setMission] = useState<any>(null);
  const [loading, setLoading] = useState(true);
  const [erreurChargement, setErreurChargement] = useState(false);
  usePageTitle(mission?.intitule ? `Modifier · ${mission.intitule}` : 'Modifier une mission');

  useEffect(() => {
    if (!id) return;
    (async () => {
      const [missionResult, creneauxResult] = await Promise.all([
        supabase.from('missions').select(`
          id, intitule, description, service, profession_requise,
          debut_le, fin_le, taux_horaire_base, est_urgente, niveau_urgence,
          mode_attribution, type_contrat_recherche,
          specialite_medicale_requise, accepte_non_specialises,
          nb_creneaux, statut, nature_tva_prestation
        `).eq('id', id).single(),
        supabase
          .from('mission_creneaux')
          .select('id, mission_id, debut, fin, est_pause, type_creneau, ordre')
          .eq('mission_id', id)
          .eq('est_pause', false)
          .eq('type_creneau', 'PREVISIONNEL')
          .order('ordre', { ascending: true }),
      ]);

      if (missionResult.error || creneauxResult.error) {
        logger.error('[ModifierMission] Erreur chargement planning exact', missionResult.error ?? creneauxResult.error);
        setErreurChargement(true);
        setMission(null);
        setLoading(false);
        return;
      }
      const planning = construirePlanningCandidat(
        missionResult.data,
        (creneauxResult.data ?? []) as any[],
      );
      if (!planning.exact) {
        logger.error('[ModifierMission] Planning contractuel incomplet', {
          missionId: id,
          attendus: missionResult.data.nb_creneaux,
          recus: creneauxResult.data?.length ?? 0,
        });
        setErreurChargement(true);
        setMission(null);
        setLoading(false);
        return;
      }
      setMission({
        ...missionResult.data,
        creneaux: planning.creneaux,
      });
      setLoading(false);
    })();
  }, [id]);

  if (loading) return <LayoutApp role="ADMIN_ETABLISSEMENT"><ChargementPage /></LayoutApp>;

  if (erreurChargement || !mission || mission.statut !== 'OUVERTE') {
    return (
      <LayoutApp role="ADMIN_ETABLISSEMENT">
        <div className="text-center py-12">
          <h1 className="text-lg font-semibold text-foreground mb-2">
            {erreurChargement ? 'Planning indisponible' : !mission ? 'Mission introuvable' : 'Modification impossible'}
          </h1>
          <p className="text-sm text-muted-foreground mb-4">
            {erreurChargement
              ? 'Le planning exact n’a pas pu être chargé. Aucune modification n’est possible afin d’éviter d’écraser des créneaux existants.'
              : !mission
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
        <button onClick={() => navigate(`/etablissement/missions/${id}`)} className="app-inline-back text-sm text-primary hover:underline mb-4 inline-block">
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
