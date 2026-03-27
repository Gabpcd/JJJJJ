import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { Star, X } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { fetchEtablissementsSafe } from '@/lib/etablissements';
import { useAuth } from '@/contexts/AuthContext';
import { EvaluationPostMission } from '@/components/EvaluationPostMission';

interface Props {
  role: 'SOIGNANT' | 'ETABLISSEMENT';
}

interface MissionAEvaluer {
  id: string;
  intitule: string;
  soignant_assigne_id: string | null;
  etablissement_id: string;
  nom_evalue: string;
}

export function BandeauEvaluationsEnAttente({ role }: Props) {
  const { user } = useAuth();
  const [missions, setMissions] = useState<MissionAEvaluer[]>([]);
  const [current, setCurrent] = useState<MissionAEvaluer | null>(null);

  useEffect(() => {
    if (!user) return;
    const load = async () => {
      // Get terminated missions for this user
      let query = supabase
        .from('missions')
        .select('id, intitule, soignant_assigne_id, etablissement_id')
        .eq('statut', 'TERMINEE')
        .limit(50);

      if (role === 'SOIGNANT') {
        query = query.eq('soignant_assigne_id', user.id);
      } else {
        // For establishment, we need their etablissement_id
        const { data: etab } = await supabase
          .from('etablissements')
          .select('id')
          .eq('id', user.id)
          .maybeSingle();
        if (!etab) {
          // Try via admin link
          const { data: adminLink } = await supabase
            .from('admins_groupe_sante')
            .select('groupe_id')
            .eq('utilisateur_id', user.id)
            .maybeSingle();
          // Fallback: use user.id as etablissement_id
          query = query.eq('etablissement_id', user.id);
        } else {
          query = query.eq('etablissement_id', etab.id);
        }
      }

      const { data: ms } = await query;
      if (!ms || ms.length === 0) return;

      // Get already evaluated missions by this user
      const { data: evals } = await supabase
        .from('evaluations')
        .select('mission_id')
        .eq('evaluateur_id', user.id);

      const evalSet = new Set((evals || []).map((e: any) => e.mission_id));
      const nonEvaluees = (ms as any[]).filter(m => !evalSet.has(m.id));

      if (nonEvaluees.length === 0) return;

      // Enrich with names
      if (role === 'SOIGNANT') {
        // Need establishment names
        const etabIds = [...new Set(nonEvaluees.map(m => m.etablissement_id))];
        const { data: etabs } = await supabase
          .from('etablissements')
          .select('id, nom')
          .in('id', etabIds);
        const etabMap: Record<string, string> = {};
        (etabs || []).forEach((e: any) => { etabMap[e.id] = e.nom; });

        setMissions(nonEvaluees.map(m => ({
          ...m,
          nom_evalue: etabMap[m.etablissement_id] || 'Établissement',
        })));
      } else {
        // Need soignant names
        const sgIds = [...new Set(nonEvaluees.map(m => m.soignant_assigne_id).filter(Boolean))];
        if (sgIds.length === 0) return;
        const { data: sgs } = await supabase
          .from('soignants')
          .select('id, prenom, nom')
          .in('id', sgIds);
        const sgMap: Record<string, string> = {};
        (sgs || []).forEach((s: any) => { sgMap[s.id] = `${s.prenom} ${s.nom}`; });

        setMissions(nonEvaluees
          .filter(m => m.soignant_assigne_id)
          .map(m => ({
            ...m,
            nom_evalue: sgMap[m.soignant_assigne_id!] || 'Soignant',
          }))
        );
      }
    };
    load();
  }, [user, role]);

  if (missions.length === 0) return null;

  return (
    <>
      <button
        type="button"
        onClick={() => setCurrent(missions[0])}
        className="w-full mb-4 rounded-xl border border-amber-300 bg-amber-50 dark:bg-amber-950/20 dark:border-amber-700 p-4 text-left transition-colors hover:bg-amber-100 dark:hover:bg-amber-950/30"
      >
        <div className="flex items-center gap-3">
          <Star className="h-5 w-5 text-amber-500 shrink-0" />
          <div className="flex-1 min-w-0">
            <p className="text-sm font-semibold text-foreground">
              ⭐ Vous avez {missions.length} mission{missions.length > 1 ? 's' : ''} à évaluer
            </p>
            <p className="text-xs text-muted-foreground mt-0.5">
              Cliquez pour noter votre expérience
            </p>
          </div>
        </div>
      </button>

      {current && (
        <EvaluationPostMission
          missionId={current.id}
          evalueId={role === 'SOIGNANT' ? current.etablissement_id : current.soignant_assigne_id!}
          typeEvaluateur={role === 'SOIGNANT' ? 'SOIGNANT' : 'ETABLISSEMENT'}
          nomEvalue={current.nom_evalue}
          onTermine={() => {
            setMissions(prev => prev.filter(m => m.id !== current.id));
            setCurrent(null);
          }}
        />
      )}
    </>
  );
}
