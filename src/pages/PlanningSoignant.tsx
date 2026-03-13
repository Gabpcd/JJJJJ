import React, { useEffect } from 'react';
import { LayoutApp } from '@/components/LayoutApp';
import { PlanningHebdomadaire } from '@/components/PlanningHebdomadaire';
import { CompteurHebdomadaire } from '@/components/CompteurHebdomadaire';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';

export default function PlanningSoignant() {
  const { user } = useAuth();

  useEffect(() => {
    if (!user) return;
    supabase.rpc('fn_ecrire_audit_safe', {
      p_acteur_id: user.id, p_type_acteur: 'SOIGNANT',
      p_action: 'DONNEES_PERSO_CONSULTATION',
      p_type_ressource: 'soignant', p_id_ressource: user.id,
      p_cle_s3: null,
      p_details: { page: 'planning' },
      p_ip: null, p_navigateur: navigator.userAgent,
    });
  }, [user]);

  return (
    <LayoutApp role="SOIGNANT">
      <h1 className="text-xl font-bold text-foreground mb-4">📅 Mon planning</h1>

      <div className="space-y-4">
        <CompteurHebdomadaire />
        <PlanningHebdomadaire />
      </div>
    </LayoutApp>
  );
}
