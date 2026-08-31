import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { ArrowLeft, Star, ClipboardCheck, Loader2 } from 'lucide-react';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { usePageTitle } from '@/hooks/usePageTitle';
import { supabase } from '@/integrations/supabase/client';
import { useNotification } from '@/contexts/NotificationContext';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import { ModaleEvaluerSoignant } from '@/components/etablissement/ModaleEvaluerSoignant';

interface MissionANoter {
  mission_id: string;
  intitule: string;
  debut_le: string;
  fin_le: string;
  soignant_id: string;
  soignant_prenom: string;
  soignant_nom: string;
  soignant_profession: string;
  duree_heures: number;
  taux_horaire_base: number;
  jours_depuis_fin: number;
}

/**
 * Page évaluations à faire côté étab (Sprint 5.7 PR 5).
 *
 * Fix P0-8 audit Sprint 5 : pas de page côté étab pour évaluer un soignant.
 *
 * Liste les missions TERMINEE assignées (60 derniers jours) sans notation
 * ETAB_VERS_SOIGNANT. Permet à l'étab de noter le soignant via 4 critères :
 * - Ponctualité
 * - Qualité technique
 * - Relationnel équipe
 * - Conformité protocole
 *
 * + commentaire libre + note globale dérivée.
 *
 * Appelle fn_lister_missions_a_noter_etab + fn_creer_notation_mission (Sprint 3.5).
 */
export default function EvaluationsAFaireEtab() {
  usePageTitle('Évaluations à faire');
  const navigate = useNavigate();
  const { afficherNotification } = useNotification();
  const [loading, setLoading] = useState(true);
  const [missions, setMissions] = useState<MissionANoter[]>([]);
  const [missionSelectionnee, setMissionSelectionnee] = useState<MissionANoter | null>(null);

  async function charger() {
    setLoading(true);
    const { data, error } = await supabase.rpc('fn_lister_missions_a_noter_etab' as any);
    if (error) {
      afficherNotification({ type: 'erreur', message: error.message });
      setLoading(false);
      return;
    }
    const result = data as any;
    if (!result?.success) {
      afficherNotification({ type: 'erreur', message: result?.error || 'Erreur chargement.' });
      setLoading(false);
      return;
    }
    setMissions(result.missions as MissionANoter[]);
    setLoading(false);
  }

  useEffect(() => { charger(); }, []);

  if (loading) return <LayoutApp role="ADMIN_ETABLISSEMENT"><ChargementPage /></LayoutApp>;

  return (
    <LayoutApp role="ADMIN_ETABLISSEMENT">
      <button onClick={() => navigate(-1)} className="app-inline-back flex items-center gap-1 text-sm text-primary hover:underline mb-2">
        <ArrowLeft className="h-4 w-4" /> Retour
      </button>

      <div className="mb-6">
        <h1 className="text-2xl font-bold text-foreground inline-flex items-center gap-2">
          <ClipboardCheck className="h-6 w-6 text-primary" /> Évaluations à faire
        </h1>
        <p className="text-sm text-muted-foreground mt-1">
          Notez les soignants ayant terminé une mission chez vous (60 derniers jours).
          Vos évaluations alimentent leur score de fiabilité.
        </p>
      </div>

      <div className="rounded-2xl border-2 border-primary/30 bg-primary/5 p-4 mb-6">
        <div className="flex items-center gap-3">
          <Star className="h-6 w-6 text-primary" />
          <div>
            <p className="text-sm font-semibold text-foreground">{missions.length} mission{missions.length > 1 ? 's' : ''} à évaluer</p>
            <p className="text-xs text-muted-foreground">Les évaluations sont publiques par défaut (autres établissements peuvent les voir).</p>
          </div>
        </div>
      </div>

      {missions.length === 0 ? (
        <div className="rounded-xl bg-muted/30 border border-border p-8 text-center text-sm text-muted-foreground">
          <ClipboardCheck className="h-10 w-10 text-muted-foreground/40 mx-auto mb-3" />
          <p className="font-medium text-foreground">Aucune évaluation en attente</p>
          <p className="text-xs mt-1">Toutes vos missions terminées récentes ont été notées. Merci !</p>
        </div>
      ) : (
        <ul className="space-y-2">
          {missions.map((m) => (
            <li key={m.mission_id} className="card-base flex flex-col sm:flex-row sm:items-center gap-3 sm:justify-between">
              <div className="min-w-0 flex-1">
                <p className="text-sm font-medium text-foreground truncate">{m.intitule}</p>
                <p className="text-xs text-muted-foreground">
                  {m.soignant_prenom} {m.soignant_nom} · {m.soignant_profession}
                </p>
                <p className="text-[11px] text-muted-foreground mt-0.5">
                  Du {format(new Date(m.debut_le), 'dd MMM', { locale: fr })} au {format(new Date(m.fin_le), 'dd MMM yyyy', { locale: fr })}
                  {' · '}
                  Terminée il y a {m.jours_depuis_fin} jour{m.jours_depuis_fin > 1 ? 's' : ''}
                </p>
              </div>
              <button
                onClick={() => setMissionSelectionnee(m)}
                className="btn-primary text-sm py-2 px-4 inline-flex items-center gap-1 shrink-0"
              >
                <Star className="h-4 w-4" /> Évaluer
              </button>
            </li>
          ))}
        </ul>
      )}

      {missionSelectionnee && (
        <ModaleEvaluerSoignant
          mission={missionSelectionnee}
          onFermer={() => setMissionSelectionnee(null)}
          onEvaluee={() => {
            setMissionSelectionnee(null);
            charger();
          }}
        />
      )}
    </LayoutApp>
  );
}
