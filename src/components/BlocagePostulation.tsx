import { useNavigate } from 'react-router-dom';
import { AlertTriangle, FileText, CheckCircle, Clock } from 'lucide-react';

interface BlocagePostulationProps {
  completionProfil: number;
  documentsValides: boolean;
  premiereMissionLe?: string | null;
  missionDebutLe?: string | null;
}

const SEPT_JOURS_MS = 7 * 24 * 60 * 60 * 1000;

/**
 * Soft-gating documents (Lot 1 launch blockers) : la candidature est toujours
 * possible — seule l'ACCEPTATION par l'établissement exige les documents validés
 * pour les missions démarrant sous 7 jours. Ce composant informe, il ne bloque plus.
 */
export function BlocagePostulation({ completionProfil, documentsValides, missionDebutLe }: BlocagePostulationProps) {
  const navigate = useNavigate();

  const missionSous7Jours = !!missionDebutLe && (new Date(missionDebutLe).getTime() - Date.now() < SEPT_JOURS_MS);

  if (completionProfil >= 100 && documentsValides) {
    return (
      <div className="space-y-2 mb-4">
        <div className="flex items-center gap-2 text-sm text-success">
          <CheckCircle className="h-4 w-4" /> Ton profil est complet
        </div>
        <div className="flex items-center gap-2 text-sm text-success">
          <CheckCircle className="h-4 w-4" /> Tes documents sont à jour
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
                Complète tes informations essentielles (identité, téléphone, adresse) pour pouvoir postuler.
              </p>
              <button onClick={() => navigate('/soignant/profil')} className="text-xs text-primary font-medium mt-2 hover:underline">
                Compléter mon profil →
              </button>
            </div>
          </div>
        </div>
      )}
      {!documentsValides && (
        <div className="bg-warning/5 border border-warning/20 rounded-xl p-4">
          <div className="flex items-start gap-3">
            <FileText className="h-5 w-5 text-warning shrink-0 mt-0.5" />
            <div>
              <p className="text-sm font-semibold text-foreground">
                Documents en cours — tu peux postuler dès maintenant
              </p>
              <p className="text-xs text-muted-foreground mt-1">
                {missionSous7Jours
                  ? 'Cette mission démarre bientôt : l\'établissement ne pourra t\'accepter qu\'une fois tes documents validés (vérification automatique en quelques minutes). Prends 2 minutes maintenant.'
                  : 'Ta candidature partira normalement. Valide tes documents pour pouvoir être accepté (vérification automatique en quelques minutes).'}
              </p>
              <button onClick={() => navigate('/soignant/mes-documents')} className="text-xs text-primary font-medium mt-2 hover:underline">
                Valider mes documents →
              </button>
            </div>
          </div>
        </div>
      )}
      {!documentsValides && (
        <div className="flex items-center gap-2 text-xs text-muted-foreground">
          <Clock className="h-3.5 w-3.5" /> Les profils complets sont acceptés en priorité par les établissements.
        </div>
      )}
    </div>
  );
}
