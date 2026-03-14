import React, { useEffect, useState } from 'react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { LayoutApp } from '@/components/LayoutApp';
import { PlanningHebdomadaire } from '@/components/PlanningHebdomadaire';
import { CalendrierMensuel } from '@/components/CalendrierMensuel';
import { CompteurHebdomadaire } from '@/components/CompteurHebdomadaire';
import { SyncCalendrier } from '@/components/SyncCalendrier';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';

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
      <div className="flex items-center justify-between mb-4">
        <h1 className="text-xl font-bold text-foreground">📅 Mon planning</h1>
        <SyncCalendrier />
      </div>

      <div className="space-y-4">
        <CompteurHebdomadaire />

        <Tabs defaultValue="mensuel">
          <TabsList className="grid w-full grid-cols-2">
            <TabsTrigger value="mensuel">Vue mensuelle</TabsTrigger>
            <TabsTrigger value="hebdo">Vue hebdomadaire</TabsTrigger>
          </TabsList>
          <TabsContent value="mensuel" className="mt-4">
            <CalendrierMensuel />
          </TabsContent>
          <TabsContent value="hebdo" className="mt-4">
            <PlanningHebdomadaire />
          </TabsContent>
        </Tabs>
      </div>
    </LayoutApp>
  );
}
