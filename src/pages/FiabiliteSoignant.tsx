import { useState, useEffect } from 'react';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { JaugeScoreFiabilite } from '@/components/JaugeScoreFiabilite';
import { DecompositionScore } from '@/components/DecompositionScore';
import { ConseilsScore } from '@/components/ConseilsScore';
import { BadgeNiveau } from '@/components/BadgeNiveau';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';

export default function FiabiliteSoignant() {
  const { user } = useAuth();
  const [soignant, setSoignant] = useState<any>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!user) return;
    supabase.from('soignants')
      .select('score_fiabilite, total_missions_terminees, total_missions_annulees, total_absences, total_retards_pointage, prevoyance_inscrit')
      .eq('id', user.id).single()
      .then(({ data }) => {
        setSoignant(data); setLoading(false);
        // Audit HDS
        supabase.rpc('fn_ecrire_audit', {
          p_acteur_id: user.id, p_type_acteur: 'SOIGNANT',
          p_action: 'DONNEES_PERSO_CONSULTATION',
          p_type_ressource: 'soignant', p_id_ressource: user.id,
          p_cle_s3: null,
          p_details: { page: 'fiabilite' },
          p_ip: null, p_navigateur: navigator.userAgent,
        });
      });
  }, [user]);

  if (loading || !soignant) return <LayoutApp role="SOIGNANT"><ChargementPage /></LayoutApp>;

  const score = soignant.score_fiabilite ?? 50;

  return (
    <LayoutApp role="SOIGNANT">
      <div className="mb-6">
        <h1 className="text-xl font-bold text-foreground">⭐ Score de fiabilité</h1>
        <div className="mt-2"><BadgeNiveau score={score} /></div>
      </div>

      <div className="mb-6">
        <JaugeScoreFiabilite score={score} />
      </div>

      <div className="space-y-4">
        <DecompositionScore soignant={soignant} />
        <ConseilsScore soignant={soignant} />
      </div>
    </LayoutApp>
  );
}
