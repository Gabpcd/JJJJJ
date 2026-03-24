import { useNavigate } from 'react-router-dom';
import { FileText, ShieldAlert } from 'lucide-react';

interface BandeauDocumentsManquantsProps {
  tousDocumentsValides: boolean;
  rcpExpiree?: boolean;
}

export function BandeauDocumentsManquants({ tousDocumentsValides, rcpExpiree }: BandeauDocumentsManquantsProps) {
  const navigate = useNavigate();

  if (tousDocumentsValides && !rcpExpiree) return null;

  return (
    <div className="space-y-2 mb-4">
      {rcpExpiree && (
        <div className="bg-destructive/5 border border-destructive/30 rounded-xl p-3 flex items-start gap-3">
          <ShieldAlert className="h-5 w-5 text-destructive shrink-0 mt-0.5" />
          <div>
            <p className="text-sm font-semibold text-destructive">⚠️ Votre assurance RCP est expirée</p>
            <p className="text-xs text-muted-foreground mt-1">
              L'assurance Responsabilité Civile Professionnelle est obligatoire pour postuler. Mettez-la à jour pour débloquer les candidatures.
            </p>
            <button onClick={() => navigate('/soignant/documents')} className="text-xs text-primary font-medium mt-2 hover:underline">
              Mettre à jour mes documents →
            </button>
          </div>
        </div>
      )}
      {!tousDocumentsValides && !rcpExpiree && (
        <div className="bg-warning/5 border border-warning/30 rounded-xl p-3 flex items-start gap-3">
          <FileText className="h-5 w-5 text-warning shrink-0 mt-0.5" />
          <div>
            <p className="text-sm font-semibold text-foreground">⚠️ Complétez vos documents obligatoires pour postuler</p>
            <p className="text-xs text-muted-foreground mt-1">
              Certains documents sont manquants ou expirés. Vous ne pourrez pas postuler tant qu'ils ne sont pas à jour.
            </p>
            <button onClick={() => navigate('/soignant/documents')} className="text-xs text-primary font-medium mt-2 hover:underline">
              Gérer mes documents →
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
