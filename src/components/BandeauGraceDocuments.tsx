import React from 'react';
import { AlertTriangle } from 'lucide-react';
import { useNavigate } from 'react-router-dom';

interface BandeauGraceDocumentsProps {
  premiereMissionLe: string | null;
  tousDocumentsValides: boolean | null;
  documentsManquants?: string[];
}

export function BandeauGraceDocuments({ premiereMissionLe, tousDocumentsValides, documentsManquants = [] }: BandeauGraceDocumentsProps) {
  const navigate = useNavigate();

  if (!premiereMissionLe || tousDocumentsValides) return null;

  const dateGrace = new Date(premiereMissionLe);
  dateGrace.setDate(dateGrace.getDate() + 7);
  const maintenant = new Date();
  const joursRestants = Math.ceil((dateGrace.getTime() - maintenant.getTime()) / (1000 * 60 * 60 * 24));

  if (joursRestants <= 0) return null; // Grace period expired → blocking handled elsewhere

  const listeManquants = documentsManquants.length > 0
    ? documentsManquants.join(', ')
    : 'RCP, Diplôme';

  return (
    <div className="bg-warning/10 border border-warning/30 rounded-xl p-4 flex items-start gap-3">
      <AlertTriangle className="h-5 w-5 text-warning shrink-0 mt-0.5" />
      <div className="flex-1">
        <p className="text-sm font-semibold text-warning">
          ⚠️ Tu as {joursRestants} jour{joursRestants > 1 ? 's' : ''} pour compléter ton dossier
        </p>
        <p className="text-xs text-warning/80 mt-1">
          Documents manquants : {listeManquants}. Passé ce délai, tes futures missions seront bloquées.
        </p>
        <button
          onClick={() => navigate('/soignant/documents')}
          className="text-xs text-warning font-semibold underline mt-2 hover:text-warning/70"
        >
          Compléter mes documents →
        </button>
      </div>
    </div>
  );
}
