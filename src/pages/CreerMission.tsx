import React from 'react';
import { LayoutApp } from '@/components/LayoutApp';
import { FormulaireMission } from '@/components/FormulaireMission';

export default function CreerMission() {
  return (
    <LayoutApp role="ETABLISSEMENT">
      <div className="max-w-2xl mx-auto">
        <h1 className="text-xl font-bold text-foreground mb-6">📝 Publier une mission</h1>
        <div className="card-base">
          <FormulaireMission />
        </div>
      </div>
    </LayoutApp>
  );
}
