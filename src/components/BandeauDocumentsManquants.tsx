import { useNavigate } from 'react-router-dom';
import { FileText, ShieldAlert, CalendarClock } from 'lucide-react';

interface BandeauDocumentsManquantsProps {
  tousDocumentsValides: boolean;
  rcpExpiree?: boolean;
  /** RCP encore valide mais expirant sous 30 jours (date ISO) — alerte préventive. */
  rcpExpireLe?: string | null;
}

export function BandeauDocumentsManquants({ tousDocumentsValides, rcpExpiree, rcpExpireLe }: BandeauDocumentsManquantsProps) {
  const navigate = useNavigate();

  if (tousDocumentsValides && !rcpExpiree && !rcpExpireLe) return null;

  return (
    <div className="space-y-2 mb-4">
      {rcpExpiree && (
        <div className="bg-destructive/5 border border-destructive/30 rounded-xl p-3 flex items-start gap-3">
          <ShieldAlert className="h-5 w-5 text-destructive shrink-0 mt-0.5" />
          <div>
            <p className="text-sm font-semibold text-destructive">⚠️ Ton assurance RCP est expirée ou manquante</p>
            <p className="text-xs text-muted-foreground mt-1">
              L'assurance Responsabilité Civile Professionnelle est obligatoire pour candidater en libéral.
              Mets-la à jour pour débloquer ces candidatures (tu peux toujours candidater en salarié).
            </p>
            <button onClick={() => navigate('/soignant/documents')} className="text-xs text-primary font-medium mt-2 hover:underline">
              Mettre à jour mes documents →
            </button>
          </div>
        </div>
      )}
      {!rcpExpiree && rcpExpireLe && (
        <div className="bg-warning/5 border border-warning/30 rounded-xl p-3 flex items-start gap-3">
          <CalendarClock className="h-5 w-5 text-warning shrink-0 mt-0.5" />
          <div>
            <p className="text-sm font-semibold text-foreground">
              ⏳ Ta RCP expire le {new Date(rcpExpireLe).toLocaleDateString('fr-FR')}
            </p>
            <p className="text-xs text-muted-foreground mt-1">
              Renouvelle-la dès maintenant pour ne pas être bloqué(e) sur les missions libérales le moment venu.
            </p>
            <button onClick={() => navigate('/soignant/documents')} className="text-xs text-primary font-medium mt-2 hover:underline">
              Téléverser ma nouvelle RCP →
            </button>
          </div>
        </div>
      )}
      {!tousDocumentsValides && !rcpExpiree && (
        <div className="bg-warning/5 border border-warning/30 rounded-xl p-3 flex items-start gap-3">
          <FileText className="h-5 w-5 text-warning shrink-0 mt-0.5" />
          <div>
            <p className="text-sm font-semibold text-foreground">📄 Valide tes documents pour pouvoir être accepté(e)</p>
            <p className="text-xs text-muted-foreground mt-1">
              Tu peux postuler dès maintenant — mais les établissements ne peuvent accepter que les
              profils aux documents validés (vérification automatique en quelques minutes).
            </p>
            <button onClick={() => navigate('/soignant/documents')} className="text-xs text-primary font-medium mt-2 hover:underline">
              Valider mes documents →
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
