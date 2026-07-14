import React from 'react';
import { LayoutApp } from '@/components/LayoutApp';
import { FormulaireMission } from '@/components/FormulaireMission';
import { usePageTitle } from '@/hooks/usePageTitle';

export default function CreerMission() {
  usePageTitle('Publier une mission');

  return (
    <LayoutApp role="ADMIN_ETABLISSEMENT">
      <div className="max-w-2xl mx-auto">
        <h1 className="text-xl font-bold text-foreground mb-6">📝 Publier une mission</h1>
        <div className="card-base">
          <FormulaireMission />
        </div>
      </div>
    </LayoutApp>
  );
}
