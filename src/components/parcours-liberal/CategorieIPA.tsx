import { useMemo } from 'react';
import { Info, Sparkles } from 'lucide-react';
import type { RegleInstallation } from '@/lib/regles-installation-liberal';
import type { ParcoursLiberal } from '@/hooks/useParcoursLiberal';
import { ProgressBarParcours } from './ProgressBarParcours';
import { ChecklistEtapes, type Etape } from './ChecklistEtapes';

interface Props {
  parcours: ParcoursLiberal;
  regle: RegleInstallation;
  majEtape: (cle: string, valeur: boolean) => Promise<unknown>;
}

const ETAPES_IPA_PREREQUIS: Etape[] = [
  {
    cle: 'experience_3ans_ide',
    label: "3 ans d'exercice IDE validés",
    description: 'Expérience professionnelle infirmière préalable à la formation IPA.',
  },
  {
    cle: 'diplome_ipa_obtenu',
    label: "Diplôme d'État IPA (master) obtenu",
    description: "Diplôme de niveau master délivré par une université avec mention dans l'un des domaines : pathologies chroniques stabilisées, oncologie, maladie rénale chronique, santé mentale, urgences.",
  },
];

const ETAPES_IPA_DEMARCHES: Etape[] = [
  {
    cle: 'inscription_ordre_ipa',
    label: "Déclaration IPA auprès de l'Ordre des Infirmiers",
    description: "Mise à jour de ton inscription à l'Ordre avec mention IPA.",
    lienExterne: 'https://www.ordre-infirmiers.fr',
    lienLabel: 'Ordre des Infirmiers',
  },
  {
    cle: 'inscription_cpam_ipa',
    label: "Enregistrement IPA auprès de la CPAM",
    description: "Transmission du diplôme IPA + N° Ordre + adresse lieu d'exercice. Tu bénéficies d'une aide conventionnelle au démarrage.",
    lienExterne: 'https://www.ameli.fr/infirmier/exercice-liberal/vie-cabinet/installation-liberal/exercice-des-infirmiers-en-pratique-avancee',
    lienLabel: 'Ameli IPA',
  },
  {
    cle: 'immatriculation_urssaf',
    label: 'Immatriculation URSSAF',
    description: "Déclaration de début d'activité libérale via le guichet unique INPI.",
    lienExterne: 'https://formalites.entreprises.gouv.fr',
    lienLabel: 'Guichet unique INPI',
  },
  {
    cle: 'affiliation_carpimko',
    label: 'Affiliation CARPIMKO',
    description: 'Caisse de retraite des auxiliaires médicaux libéraux.',
    lienExterne: 'https://www.carpimko.com',
    lienLabel: 'CARPIMKO',
  },
  {
    cle: 'souscription_rcp',
    label: 'Souscription RC Pro adaptée IPA',
    description: 'Vérifie que ton contrat couvre bien l\'exercice en pratique avancée.',
  },
  {
    cle: 'exercice_coordonne',
    label: "Inscription à une structure d'exercice coordonné",
    description: 'Recommandé en ville : MSP, CPTS, ESP. Non obligatoire mais facilite l\'exercice.',
  },
];

const ETAPES_TOTALES = [...ETAPES_IPA_PREREQUIS, ...ETAPES_IPA_DEMARCHES];

export function CategorieIPA({ parcours, majEtape }: Props) {
  const etapesValidees = useMemo(
    () => ETAPES_TOTALES.filter(e => Boolean(parcours.etapes[e.cle])).length,
    [parcours.etapes],
  );

  const handleMajEtape = async (cle: string, valeur: boolean) => {
    await majEtape(cle, valeur);
  };

  return (
    <div className="space-y-4">
      <div>
        <h1 className="text-xl font-bold text-foreground">Ton parcours IPA libéral</h1>
        <p className="text-sm text-muted-foreground mt-1">
          Infirmier en Pratique Avancée — exercice exclusif non soumis au zonage sur-dotée.
        </p>
      </div>

      <ProgressBarParcours
        etapesTotales={ETAPES_TOTALES.length}
        etapesValidees={etapesValidees}
        parcoursDemarre={parcours.demarre_le}
        parcoursTermine={parcours.termine_le}
      />

      <div className="rounded-xl border border-info/30 bg-info/5 p-3 flex gap-2">
        <Info className="h-5 w-5 text-info shrink-0 mt-0.5" />
        <div>
          <p className="text-sm font-semibold text-foreground">Règle IPA</p>
          <p className="text-xs text-muted-foreground mt-1">
            L'exercice IPA libéral nécessite le diplôme d'État d'Infirmier en Pratique Avancée (master) ET 3 ans d'exercice IDE préalables. Contrairement à l'exercice IDE classique, les IPA en exercice exclusif ne sont pas soumis au dispositif de régulation en zone sur-dotée.
          </p>
        </div>
      </div>

      <div className="card-base">
        <h3 className="text-base font-bold text-foreground mb-3">Prérequis</h3>
        <ChecklistEtapes
          etapes={ETAPES_IPA_PREREQUIS}
          etapesValidees={parcours.etapes}
          onToggle={handleMajEtape}
        />
      </div>

      <div className="card-base">
        <h3 className="text-base font-bold text-foreground mb-3">Démarches d'installation</h3>
        <ChecklistEtapes
          etapes={ETAPES_IPA_DEMARCHES}
          etapesValidees={parcours.etapes}
          onToggle={handleMajEtape}
        />
      </div>

      <div className="rounded-xl border-2 border-primary/40 bg-gradient-to-r from-primary/10 to-info/10 p-3 flex items-start gap-2">
        <Sparkles className="h-5 w-5 text-primary shrink-0 mt-0.5" />
        <div>
          <p className="text-sm font-semibold text-primary">Aides financières IPA</p>
          <p className="text-xs text-muted-foreground mt-1">
            La CPAM propose des aides au démarrage spécifiques IPA : aide à l'installation en zone sous-dotée (jusqu'à 40 000 € via avenant 9), aide conventionnelle au démarrage, revalorisation des forfaits PAI.
          </p>
        </div>
      </div>
    </div>
  );
}
