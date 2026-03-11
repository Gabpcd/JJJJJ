import React from 'react';

interface BarreProgressionBulkProps {
  progression: number;
  total: number;
  actuel: number;
}

export function BarreProgressionBulk({ progression, total, actuel }: BarreProgressionBulkProps) {
  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50">
      <div className="bg-card rounded-2xl p-6 shadow-xl max-w-sm w-full mx-4">
        <p className="text-sm font-semibold text-foreground mb-3">Création des missions en cours...</p>
        <div className="relative h-3 rounded-full bg-muted overflow-hidden mb-2">
          <div
            className="absolute inset-y-0 left-0 rounded-full bg-primary transition-all duration-300"
            style={{ width: `${progression}%` }}
          />
        </div>
        <p className="text-xs text-muted-foreground text-center">
          {actuel}/{total} ({progression}%)
        </p>
      </div>
    </div>
  );
}
