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
        .select('id, intitule, soignant_assigne_id, etablissement_id, etablissements(nom)')
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

      // Get already evaluated missions.
      // Filtre par type_evaluateur : côté ETAB, fn_evaluer_soignant stocke
      // evaluateur_id = etablissement_id (pas auth.uid()), donc un filtre
      // .eq('evaluateur_id', user.id) manquerait les évals déjà faites
      // pour les admins de groupe_sante (auth.uid() ≠ etablissement.id).
      // RLS (pol_eval_select) isole déjà les évaluations accessibles.
      const typeEvaluateur = role === 'SOIGNANT' ? 'SOIGNANT' : 'ETABLISSEMENT';
      const { data: evals } = await supabase
        .from('evaluations')
        .select('mission_id')
        .eq('type_evaluateur', typeEvaluateur)
        .in('mission_id', (ms as any[]).map(m => m.id));

      // F4 (Lot 7b) : la notation 1-tap (check-out soignante / validation étab)
      // écrit dans notations_missions, pas dans evaluations — sans ce croisement,
      // le bandeau redemanderait une note déjà donnée. RLS : le notateur voit
      // ses propres notations, exactement le périmètre voulu.
      const sensNotation = role === 'SOIGNANT' ? 'SOIGNANT_VERS_ETAB' : 'ETAB_VERS_SOIGNANT';
      const { data: notes } = await supabase
        .from('notations_missions' as any)
        .select('mission_id')
        .eq('sens', sensNotation)
        .in('mission_id', (ms as any[]).map(m => m.id));

      const evalSet = new Set([
        ...(evals || []).map((e: any) => e.mission_id),
        ...((notes || []) as any[]).map((n: any) => n.mission_id),
      ]);
      const nonEvaluees = (ms as any[]).filter(m => !evalSet.has(m.id));

      if (nonEvaluees.length === 0) return;

      // Enrich with names
      if (role === 'SOIGNANT') {
        // Get establishment names from joined data first, fallback to fetchEtablissementsSafe
        const etabIds = [...new Set(nonEvaluees.map(m => m.etablissement_id))];
        const safeMap = await fetchEtablissementsSafe(etabIds);
        const etabMap: Record<string, string> = {};
        Object.entries(safeMap).forEach(([id, e]) => { etabMap[id] = e.nom; });

        setMissions(nonEvaluees.map(m => ({
          ...m,
          nom_evalue: (m as any).etablissements?.nom || etabMap[m.etablissement_id] || 'Établissement inconnu',
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

  // Ligne d'action discrète (plus de gros bandeau jaune) — on nomme l'évalué·e.
  const premiere = missions[0];
  const autres = missions.length - 1;
  const libelle = role === 'SOIGNANT'
    ? `Évalue ta mission à ${premiere.nom_evalue}`
    : `Évaluez ${premiere.nom_evalue}`;

  return (
    <>
      <button
        type="button"
        onClick={() => setCurrent(premiere)}
        className="w-full mb-4 flex items-center gap-2 rounded-xl border border-border bg-card px-3.5 py-2.5 text-left hover:border-amber-300 transition-colors"
      >
        <Star className="h-4 w-4 text-amber-500 shrink-0" />
        <span className="flex-1 min-w-0 text-sm text-foreground truncate">
          ⭐ {libelle}{autres > 0 ? ` (+${autres})` : ''}
        </span>
        <span className="text-xs font-semibold text-primary shrink-0">Évaluer →</span>
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
