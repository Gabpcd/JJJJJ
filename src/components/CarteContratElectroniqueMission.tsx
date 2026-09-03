import { CheckCircle, Clock, FileText } from 'lucide-react';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';

export interface ContratElectroniqueMissionResume {
  id: string;
  numero_contrat: string;
  statut: string | null;
  signature_soignant: boolean | null;
  signature_etablissement: boolean | null;
}

interface Props {
  contrat: ContratElectroniqueMissionResume | null;
  viewerRole: 'ETABLISSEMENT' | 'ADMIN';
  onOpen: (contratId: string) => void;
}

export function CarteContratElectroniqueMission({ contrat, viewerRole, onOpen }: Props) {
  if (!contrat) {
    return (
      <div className="rounded-xl border border-warning/35 bg-warning/5 p-4" role="status">
        <div className="flex items-start gap-3">
          <Clock className="mt-0.5 h-5 w-5 shrink-0 text-warning" aria-hidden="true" />
          <div>
            <p className="font-semibold text-foreground">Contrat électronique en préparation</p>
            <p className="mt-1 text-sm text-muted-foreground">
              Le document Jolene n’est pas encore disponible. Actualisez dans quelques instants avant le début de la mission.
            </p>
          </div>
        </div>
      </div>
    );
  }

  const signeComplet = contrat.statut === 'SIGNE_COMPLET'
    || (contrat.signature_soignant === true && contrat.signature_etablissement === true);
  const etablissementDoitSigner = contrat.signature_etablissement !== true && !signeComplet;
  const soignantDejaSigne = contrat.signature_soignant === true;

  return (
    <div className={`rounded-xl border p-4 ${signeComplet ? 'border-success/35 bg-success/5' : 'border-primary/35 bg-primary/5'}`}>
      <div className="flex items-start gap-3">
        {signeComplet ? (
          <CheckCircle className="mt-0.5 h-5 w-5 shrink-0 text-success" aria-hidden="true" />
        ) : (
          <FileText className="mt-0.5 h-5 w-5 shrink-0 text-primary" aria-hidden="true" />
        )}
        <div className="min-w-0 flex-1">
          <p className="font-semibold text-foreground">
            {signeComplet ? 'Contrat électronique signé' : 'Contrat électronique Jolene'}
          </p>
          <p className="mt-1 text-sm text-muted-foreground">
            {signeComplet
              ? `Le contrat ${contrat.numero_contrat} est signé par les deux parties.`
              : etablissementDoitSigner
                ? `${soignantDejaSigne ? 'Le soignant a signé. ' : ''}La signature de l’établissement est requise avant le début de la mission.`
                : 'La signature du soignant est encore attendue.'}
          </p>
          {viewerRole === 'ADMIN' && !signeComplet && (
            <p className="mt-1 text-xs text-muted-foreground">
              Supervision admin : contrôlez l’état du document et intervenez si une partie est bloquée.
            </p>
          )}
        </div>
      </div>

      <BoutonY2K
        type="button"
        size="sm"
        variant={etablissementDoitSigner && viewerRole === 'ETABLISSEMENT' ? 'primary' : 'secondary'}
        className="mt-4 w-full justify-center sm:w-auto"
        onClick={() => onOpen(contrat.id)}
        iconeGauche={<FileText className="h-4 w-4" aria-hidden="true" />}
      >
        {viewerRole === 'ADMIN'
          ? 'Superviser le contrat'
          : etablissementDoitSigner
            ? 'Ouvrir et signer le contrat'
            : 'Consulter le contrat'}
      </BoutonY2K>
    </div>
  );
}
