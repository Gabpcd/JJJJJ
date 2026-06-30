import { AlertCircle } from 'lucide-react';
import { useNavigate } from 'react-router-dom';

export function BandeauProfilIncomplet() {
  const navigate = useNavigate();
  return (
    <div className="rounded-xl border border-info/30 bg-info/5 p-3 mb-4 flex items-start gap-3">
      <AlertCircle className="h-5 w-5 text-info shrink-0 mt-0.5" />
      <div className="flex-1">
        <p className="text-sm font-medium text-foreground">
          Profil incomplet — tu vois toutes les missions
        </p>
        <p className="text-xs text-muted-foreground mt-0.5">
          Vérifie ton numéro RPPS pour voir uniquement les missions qui correspondent à ta profession et candidater aux offres.
        </p>
      </div>
      <button
        onClick={() => navigate('/soignant/profil')}
        className="btn-primary text-xs shrink-0 whitespace-nowrap"
      >
        Compléter mon profil
      </button>
    </div>
  );
}
