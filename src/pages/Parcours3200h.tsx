import { useState, useEffect } from 'react';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { ProgressionJalons3200h } from '@/components/ProgressionJalons3200h';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';

export default function Parcours3200h() {
  const { user } = useAuth();
  const [soignant, setSoignant] = useState<any>(null);
  const [suivi, setSuivi] = useState<any>(null);
  const [missions, setMissions] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!user) return;
    Promise.all([
      supabase.from('soignants').select('heures_cumulees, eligible_conversion_3200h').eq('id', user.id).single(),
      supabase.from('suivi_conversion_3200h').select('id, soignant_id, heures_actuelles, jalon_800h_atteint, jalon_1600h_atteint, jalon_2400h_atteint, jalon_3200h_atteint').eq('soignant_id', user.id).maybeSingle(),
      supabase.from('missions').select('debut_le, duree_heures').eq('soignant_assigne_id', user.id).eq('statut', 'TERMINEE').order('debut_le', { ascending: true }),
    ]).then(([{ data: sg }, { data: sv }, { data: ms }]) => {
      setSoignant(sg);
      setSuivi(sv);
      setMissions((ms as any[]) || []);
      setLoading(false);
      // Audit HDS
      supabase.rpc('fn_ecrire_audit_safe', {
        p_acteur_id: user.id, p_type_acteur: 'SOIGNANT',
        p_action: 'DONNEES_PERSO_CONSULTATION',
        p_type_ressource: 'soignant', p_id_ressource: user.id,
        p_cle_s3: null,
        p_details: { page: 'parcours_3200h' },
        p_ip: null, p_navigateur: navigator.userAgent,
      });
    });
  }, [user]);

  if (loading || !soignant) return <LayoutApp role="SOIGNANT"><ChargementPage /></LayoutApp>;

  // Calcul réel des heures depuis les missions terminées (fallback si heures_cumulees pas à jour)
  const heuresDepuisMissions = missions.reduce((acc, m) => acc + (m.duree_heures || 0), 0);
  const heures = Math.max(suivi?.heures_actuelles || 0, soignant.heures_cumulees || 0, heuresDepuisMissions);

  return (
    <LayoutApp role="SOIGNANT">
      <div className="mb-6">
        <h1 className="text-xl font-bold text-foreground">🎯 Parcours 3 200h</h1>
        <p className="text-sm text-muted-foreground mt-1">Votre chemin vers l'installation en libéral</p>
      </div>
      <ProgressionJalons3200h heures={heures} suivi={suivi} missions={missions} />
    </LayoutApp>
  );
}
