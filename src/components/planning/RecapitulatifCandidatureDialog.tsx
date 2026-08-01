import {
  DialogResponsive,
  DialogResponsiveBody,
  DialogResponsiveContent,
  DialogResponsiveDescription,
  DialogResponsiveFooter,
  DialogResponsiveHeader,
  DialogResponsiveTitle,
} from '@/components/ui/DialogResponsive';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { PlanningMissionCandidat } from './PlanningMissionCandidat';
import {
  construirePlanningCandidat,
  type MissionPlanningCandidat,
} from './planning-candidat';

interface RecapitulatifCandidatureDialogProps {
  mission: (MissionPlanningCandidat & { intitule?: string | null }) | null;
  ouvert: boolean;
  onFermer: () => void;
  onConfirmer: () => void;
  chargement?: boolean;
  actionLabel?: string;
  retraitPossible?: boolean;
}

export function RecapitulatifCandidatureDialog({
  mission,
  ouvert,
  onFermer,
  onConfirmer,
  chargement = false,
  actionLabel = 'Envoyer ma candidature',
  retraitPossible = true,
}: RecapitulatifCandidatureDialogProps) {
  if (!mission) return null;
  const planning = construirePlanningCandidat(mission);

  return (
    <DialogResponsive open={ouvert} onOpenChange={(open) => { if (!open && !chargement) onFermer(); }}>
      <DialogResponsiveContent maxWidth="lg">
        <DialogResponsiveHeader>
          <DialogResponsiveTitle>Vérifie ton engagement</DialogResponsiveTitle>
          <DialogResponsiveDescription>
            {mission.intitule ?? 'Mission'} — confirme uniquement si tu peux assurer tous les créneaux ci-dessous.
          </DialogResponsiveDescription>
        </DialogResponsiveHeader>
        <DialogResponsiveBody>
          <PlanningMissionCandidat mission={mission} />
          {planning.exact && (
            <p className="mt-4 text-xs text-muted-foreground">
              {retraitPossible
                ? 'En confirmant, tu t’engages sur ces dates et horaires exacts. Une candidature peut être retirée tant qu’elle n’est pas acceptée.'
                : 'En confirmant, tu acceptes immédiatement tous ces créneaux. Après attribution, toute annulation suit les règles de la mission.'}
            </p>
          )}
        </DialogResponsiveBody>
        <DialogResponsiveFooter>
          <BoutonY2K variant="ghost" onClick={onFermer} disabled={chargement}>Annuler</BoutonY2K>
          <BoutonY2K
            variant="primary"
            onClick={onConfirmer}
            loading={chargement}
            disabled={chargement || !planning.exact}
          >
            {actionLabel}
          </BoutonY2K>
        </DialogResponsiveFooter>
      </DialogResponsiveContent>
    </DialogResponsive>
  );
}

export default RecapitulatifCandidatureDialog;
