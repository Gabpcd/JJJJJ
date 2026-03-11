import { useNavigate } from 'react-router-dom';
import { AlertTriangle, FileText, CheckCircle } from 'lucide-react';

interface BlocagePostulationProps {
  completionProfil: number;
  documentsValides: boolean;
}

export function BlocagePostulation({ completionProfil, documentsValides }: BlocagePostulationProps) {
  const navigate = useNavigate();

  if (completionProfil >= 100 && documentsValides) {
    return (
      <div className="space-y-2 mb-4">
        <div className="flex items-center gap-2 text-sm text-success">
          <CheckCircle className="h-4 w-4" /> Votre profil est complet
        </div>
        <div className="flex items-center gap-2 text-sm text-success">
          <CheckCircle className="h-4 w-4" /> Vos documents sont à jour
        </div>
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
      {!documentsValides && (
        <div className="bg-destructive/5 border border-destructive/20 rounded-xl p-4">
          <div className="flex items-start gap-3">
            <FileText className="h-5 w-5 text-destructive shrink-0 mt-0.5" />
            <div>
              <p className="text-sm font-semibold text-foreground">Documents manquants ou expirés</p>
              <p className="text-xs text-muted-foreground mt-1">
                Vos documents ne sont pas tous à jour.
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
