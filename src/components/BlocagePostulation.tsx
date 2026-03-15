import { useNavigate } from 'react-router-dom';
import { AlertTriangle, FileText, CheckCircle, Clock } from 'lucide-react';

interface BlocagePostulationProps {
  completionProfil: number;
  documentsValides: boolean;
  premiereMissionLe?: string | null;
}

export function BlocagePostulation({ completionProfil, documentsValides, premiereMissionLe }: BlocagePostulationProps) {
  const navigate = useNavigate();

  // Grace period: if no premiere_mission_le or within 7 days, docs not required
  const enPeriodeGrace = !premiereMissionLe || 
    (new Date(premiereMissionLe).getTime() + 7 * 24 * 60 * 60 * 1000 > Date.now());
  const docsOk = documentsValides || enPeriodeGrace;

  if (completionProfil >= 100 && docsOk) {
    return (
      <div className="space-y-2 mb-4">
        <div className="flex items-center gap-2 text-sm text-success">
          <CheckCircle className="h-4 w-4" /> Votre profil est complet
        </div>
        {documentsValides ? (
          <div className="flex items-center gap-2 text-sm text-success">
            <CheckCircle className="h-4 w-4" /> Vos documents sont à jour
          </div>
        ) : (
          <div className="flex items-center gap-2 text-sm text-warning">
            <Clock className="h-4 w-4" /> Documents à compléter sous 7 jours
          </div>
        )}
      </div>
    );
  }

  return (
    <div className="space-y-3 mb-4">
      {completionProfil < 100 && (
        <div className="bg-warning/5 border border-warning/20 rounded-xl p-4">
          <div className="flex items-start gap-3">
            <AlertTriangle className="h-5 w-5 text-warning shrink-0 mt-0.5" />
            <div>
              <p className="text-sm font-semibold text-foreground">Profil incomplet ({completionProfil}%)</p>
              <p className="text-xs text-muted-foreground mt-1">
                Vous devez compléter votre profil à 100% avant de pouvoir postuler à une mission.
              </p>
              <button onClick={() => navigate('/soignant/profil')} className="text-xs text-primary font-medium mt-2 hover:underline">
                Compléter mon profil →
              </button>
            </div>
          </div>
        </div>
      )}
      {!docsOk && (
        <div className="bg-destructive/5 border border-destructive/20 rounded-xl p-4">
          <div className="flex items-start gap-3">
            <FileText className="h-5 w-5 text-destructive shrink-0 mt-0.5" />
            <div>
              <p className="text-sm font-semibold text-foreground">Documents manquants ou expirés</p>
              <p className="text-xs text-muted-foreground mt-1">
                Votre période de grâce de 7 jours est expirée. Vos documents doivent être à jour pour postuler.
              </p>
              <button onClick={() => navigate('/soignant/documents')} className="text-xs text-primary font-medium mt-2 hover:underline">
                Gérer mes documents →
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
