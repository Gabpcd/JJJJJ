import { useMemo } from 'react';
import { AlertTriangle, Info, Shield } from 'lucide-react';
import type { RegleInstallation } from '@/lib/regles-installation-liberal';
import type { ParcoursLiberal } from '@/hooks/useParcoursLiberal';
import { ProgressBarParcours } from './ProgressBarParcours';
import { ChecklistEtapes, type Etape } from './ChecklistEtapes';

interface Props {
  parcours: ParcoursLiberal;
  regle: RegleInstallation;
  majEtape: (cle: string, valeur: boolean) => Promise<unknown>;
  soignantProfession: string;
}

const ETAPES_CIPAV_COMMUNES: Etape[] = [
  {
    cle: 'inscription_ars',
    label: "Enregistrement du diplôme auprès de l'ARS",
    description: "Obtention du numéro ADELI/RPPS dans le mois suivant l'installation.",
  },
  {
    cle: 'immatriculation_urssaf',
    label: 'Immatriculation via guichet unique INPI',
    description: "Dans les 8 jours suivant le début d'activité. Tu seras rattaché au régime général de la Sécurité Sociale.",
    lienExterne: 'https://formalites.entreprises.gouv.fr',
    lienLabel: 'Guichet unique',
  },
  {
    cle: 'affiliation_cipav',
    label: 'Affiliation CIPAV (automatique)',
    description: "Rattachement automatique via ton code APE lors de l'immatriculation INPI. Tu recevras un courrier d'accès à l'espace personnel.",
    lienExterne: 'https://www.lacipav.fr',
    lienLabel: 'CIPAV',
  },
  {
    cle: 'souscription_rcp',
    label: 'Souscription RC Pro',
    description: "Obligatoire pour l'exercice libéral.",
  },
  {
    cle: 'prevoyance_complementaire',
    label: 'Prévoyance complémentaire (fortement recommandée)',
    description: "La protection CIPAV est limitée. Une prévoyance Loi Madelin permet de compléter les indemnités en cas d'arrêt de travail long.",
    informatif: true,
  },
];

const ETAPES_ERGO: Etape[] = [
  {
    cle: 'inscription_ars',
    label: 'Enregistrement ARS / Portail eRPPS',
    description: 'Depuis mars 2024, enregistrement via la plateforme eRPPS et FranceConnect.',
  },
  ...ETAPES_CIPAV_COMMUNES.slice(1),
];

const ETAPES_PSYCHOMOT: Etape[] = [...ETAPES_CIPAV_COMMUNES];
const ETAPES_DIETETICIEN: Etape[] = [...ETAPES_CIPAV_COMMUNES];

const ETAPES_CIPAV_PAR_PROFESSION: Record<string, Etape[]> = {
  ERGOTHERAPEUTE: ETAPES_ERGO,
  PSYCHOMOTRICIEN: ETAPES_PSYCHOMOT,
  DIETETICIEN: ETAPES_DIETETICIEN,
};

export function CategorieSansHeuresCIPAV({ parcours, majEtape, soignantProfession }: Props) {
  const etapes = useMemo(
    () => ETAPES_CIPAV_PAR_PROFESSION[soignantProfession] ?? [],
    [soignantProfession],
  );

  const etapesValidees = useMemo(
    () => etapes.filter(e => Boolean(parcours.etapes[e.cle])).length,
    [etapes, parcours.etapes],
  );

  const handleMajEtape = async (cle: string, valeur: boolean) => {
    await majEtape(cle, valeur);
  };

  return (
    <div className="space-y-4">
      <div>
        <h1 className="text-xl font-bold text-foreground">Ton parcours libéral</h1>
        <p className="text-sm text-muted-foreground mt-1">
          Profession libérale non conventionnée — affiliation CIPAV.
        </p>
      </div>

      <ProgressBarParcours
        etapesTotales={etapes.length}
        etapesValidees={etapesValidees}
        parcoursDemarre={parcours.demarre_le}
        parcoursTermine={parcours.termine_le}
      />

      <div className="rounded-xl border-2 border-warning/40 bg-warning/5 p-3 flex gap-2">
        <AlertTriangle className="h-5 w-5 text-warning shrink-0 mt-0.5" />
        <div>
          <p className="text-sm font-semibold text-foreground">Profession non conventionnée CPAM</p>
          <p className="text-xs text-muted-foreground mt-1">
            Attention : ta profession n'est pas conventionnée avec l'Assurance Maladie. Tes séances en libéral ne sont généralement PAS remboursées par la CPAM (sauf structures spécifiques comme CAMSP, CMPP, hospitalisation à domicile). Tes patients peuvent être remboursés par leur mutuelle selon le contrat.
          </p>
        </div>
      </div>

      <div className="card-base">
        <h3 className="text-base font-bold text-foreground mb-3">Démarches d'installation</h3>
        {etapes.length === 0 ? (
          <p className="text-sm text-muted-foreground">Les étapes pour ta profession seront bientôt disponibles.</p>
        ) : (
          <ChecklistEtapes
            etapes={etapes}
            etapesValidees={parcours.etapes}
            onToggle={handleMajEtape}
          />
        )}
      </div>

      <div className="rounded-xl border border-info/30 bg-info/5 p-3 flex gap-2">
        <Shield className="h-5 w-5 text-info shrink-0 mt-0.5" />
        <div>
          <p className="text-sm font-semibold text-foreground">Ta protection sociale</p>
          <p className="text-xs text-muted-foreground mt-1">
            En tant que profession libérale non conventionnée, tu es affilié à la <strong>CIPAV</strong> pour ta retraite et au <strong>régime général</strong> de la Sécurité Sociale pour ton assurance maladie. Indemnités journalières possibles depuis juillet 2021 (après 1 an d'affiliation). Protection limitée — prévoyance complémentaire vivement recommandée.
          </p>
        </div>
      </div>

      <div className="rounded-xl border border-info/30 bg-info/5 p-3 flex gap-2">
        <Info className="h-5 w-5 text-info shrink-0 mt-0.5" />
        <div>
          <p className="text-sm font-semibold text-foreground">Honoraires libres</p>
          <p className="text-xs text-muted-foreground mt-1">
            Tu fixes librement tes tarifs. Transparence recommandée : affiche tes tarifs en salle d'attente. Pense à communiquer aux patients le montant avant la séance.
          </p>
        </div>
      </div>
    </div>
  );
}
