import React from 'react';
import { LayoutApp } from '@/components/LayoutApp';
import { PlanningHebdomadaire } from '@/components/PlanningHebdomadaire';
import { CompteurHebdomadaire } from '@/components/CompteurHebdomadaire';

export default function PlanningSoignant() {
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
