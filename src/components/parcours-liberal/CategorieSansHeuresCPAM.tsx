import { useMemo } from 'react';
import { Info, MapPin, ExternalLink } from 'lucide-react';
import type { RegleInstallation } from '@/lib/regles-installation-liberal';
import type { ParcoursLiberal } from '@/hooks/useParcoursLiberal';
import { ProgressBarParcours } from './ProgressBarParcours';
import { ChecklistEtapes, type Etape } from './ChecklistEtapes';
import { QuizSecteurMedecin } from './QuizSecteurMedecin';

interface Props {
  parcours: ParcoursLiberal;
  regle: RegleInstallation;
  majEtape: (cle: string, valeur: boolean) => Promise<unknown>;
  soignantProfession: string;
}

const ETAPES_MEDECIN: Etape[] = [
  {
    cle: 'inscription_ordre_medecins',
    label: "Inscription au Conseil Départemental de l'Ordre des Médecins",
    description: 'Demande à adresser au président du Conseil Départemental de ta résidence professionnelle.',
    lienExterne: 'https://www.conseil-national.medecin.fr',
    lienLabel: 'Ordre des Médecins',
  },
  {
    cle: 'choix_secteur_conventionnel',
    label: 'Choix du secteur conventionnel',
    description: "Secteur 1 (honoraires opposables — irrévocable), 2 (honoraires libres si éligible) ou 3 (hors convention). Se fait lors de l'enregistrement CPAM.",
    informatif: true,
  },
  {
    cle: 'inscription_cpam',
    label: 'Enregistrement à la CPAM',
    description: 'La CPAM te remet la convention médicale à signer selon le secteur choisi.',
    lienExterne: 'https://www.ameli.fr/medecin',
    lienLabel: 'Ameli médecin',
  },
  {
    cle: 'immatriculation_urssaf',
    label: 'Immatriculation URSSAF',
    description: "Déclaration de début d'activité via le guichet unique INPI.",
    lienExterne: 'https://formalites.entreprises.gouv.fr',
    lienLabel: 'Guichet unique',
  },
  {
    cle: 'affiliation_carmf',
    label: 'Affiliation CARMF',
    description: 'Caisse Autonome de Retraite des Médecins de France.',
    lienExterne: 'https://www.carmf.fr',
    lienLabel: 'CARMF',
  },
  {
    cle: 'souscription_rcp',
    label: 'Souscription RC Pro médicale',
    description: 'Obligatoire. Principaux assureurs : MACSF, Le Sou Médical, SHAM, Branchet.',
  },
];

const ETAPES_SAGE_FEMME: Etape[] = [
  {
    cle: 'inscription_ordre_sages_femmes',
    label: "Inscription à l'Ordre des Sages-Femmes",
    description: 'Inscription obligatoire au Conseil départemental.',
    lienExterne: 'https://www.ordre-sages-femmes.fr',
    lienLabel: 'Ordre SF',
  },
  {
    cle: 'inscription_cpam',
    label: 'Enregistrement CPAM',
    description: 'Convention nationale des sages-femmes signée avec la CPAM.',
    lienExterne: 'https://www.ameli.fr/sage-femme',
    lienLabel: 'Ameli sage-femme',
  },
  {
    cle: 'immatriculation_urssaf',
    label: 'Immatriculation URSSAF',
    lienExterne: 'https://formalites.entreprises.gouv.fr',
    lienLabel: 'Guichet unique',
  },
  {
    cle: 'affiliation_carcdsf',
    label: 'Affiliation CARCDSF',
    description: 'Caisse des Chirurgiens-Dentistes et Sages-Femmes.',
    lienExterne: 'https://www.carcdsf.fr',
    lienLabel: 'CARCDSF',
  },
  {
    cle: 'souscription_rcp',
    label: 'Souscription RC Pro sage-femme',
  },
];

const ETAPES_ORTHOPHONISTE: Etape[] = [
  {
    cle: 'inscription_ars_ortho',
    label: "Enregistrement du Certificat de Capacité auprès de l'ARS",
    description: "Dans le mois suivant l'installation. Obtention du numéro RPPS et de la carte CPS.",
  },
  {
    cle: 'inscription_cpam',
    label: 'Conventionnement CPAM',
    description: "Signature de la convention nationale orthophonistes (avenant 20 — 2,60 € l'AMO).",
    lienExterne: 'https://www.ameli.fr/orthophoniste',
    lienLabel: 'Ameli orthophoniste',
  },
  {
    cle: 'immatriculation_urssaf',
    label: 'Immatriculation URSSAF via guichet unique',
    lienExterne: 'https://formalites.entreprises.gouv.fr',
    lienLabel: 'Guichet unique',
  },
  {
    cle: 'affiliation_carpimko',
    label: 'Affiliation CARPIMKO',
    lienExterne: 'https://www.carpimko.com',
    lienLabel: 'CARPIMKO',
  },
  {
    cle: 'choix_pamc',
    label: 'Choix régime PAMC',
    description: "Affiliation au régime Praticiens et Auxiliaires Médicaux Conventionnés (recommandé) ou au régime général. Choix définitif à l'installation.",
    informatif: true,
  },
  {
    cle: 'souscription_rcp',
    label: 'Souscription RC Pro',
  },
];

const ETAPES_ORTHOPTISTE: Etape[] = [
  {
    cle: 'inscription_ars',
    label: "Enregistrement du diplôme auprès de l'ARS",
  },
  {
    cle: 'inscription_cpam',
    label: 'Conventionnement CPAM',
    description: 'Installation libre, pas de zonage restrictif.',
    lienExterne: 'https://www.ameli.fr/orthoptiste',
    lienLabel: 'Ameli orthoptiste',
  },
  {
    cle: 'immatriculation_urssaf',
    label: 'Immatriculation URSSAF',
    lienExterne: 'https://formalites.entreprises.gouv.fr',
    lienLabel: 'Guichet unique',
  },
  {
    cle: 'affiliation_carpimko',
    label: 'Affiliation CARPIMKO',
    lienExterne: 'https://www.carpimko.com',
    lienLabel: 'CARPIMKO',
  },
  {
    cle: 'souscription_rcp',
    label: 'Souscription RC Pro',
  },
];

const ETAPES_PEDICURE_PODOLOGUE: Etape[] = [
  {
    cle: 'inscription_onpp',
    label: "Inscription au tableau de l'ONPP",
    description: 'Ordre National des Pédicures-Podologues. Obligatoire.',
    lienExterne: 'https://www.onpp.fr',
    lienLabel: 'ONPP',
  },
  {
    cle: 'inscription_cpam',
    label: 'Conventionnement CPAM',
    lienExterne: 'https://www.ameli.fr/pedicure-podologue',
    lienLabel: 'Ameli pédicure-podologue',
  },
  {
    cle: 'immatriculation_urssaf',
    label: 'Immatriculation URSSAF',
    lienExterne: 'https://formalites.entreprises.gouv.fr',
    lienLabel: 'Guichet unique',
  },
  {
    cle: 'affiliation_carpimko',
    label: 'Affiliation CARPIMKO',
    lienExterne: 'https://www.carpimko.com',
    lienLabel: 'CARPIMKO',
  },
  {
    cle: 'choix_regime_pamc',
    label: 'Choix PAMC ou régime général',
    description: "Choix définitif à l'installation.",
    informatif: true,
  },
  {
    cle: 'local_fixe_obligatoire',
    label: 'Local professionnel fixe',
    description: "Art. R4322-71 CSP : l'exercice exclusif au domicile des patients est INTERDIT. Un local fixe est obligatoire.",
    informatif: true,
  },
  {
    cle: 'souscription_rcp',
    label: 'Souscription RC Pro',
  },
];

const ETAPES_PAR_PROFESSION: Record<string, Etape[]> = {
  MEDECIN: ETAPES_MEDECIN,
  SAGE_FEMME: ETAPES_SAGE_FEMME,
  ORTHOPHONISTE: ETAPES_ORTHOPHONISTE,
  ORTHOPTISTE: ETAPES_ORTHOPTISTE,
  PEDICURE_PODOLOGUE: ETAPES_PEDICURE_PODOLOGUE,
};

export function CategorieSansHeuresCPAM({ parcours, majEtape, soignantProfession }: Props) {
  const etapes = useMemo(
    () => ETAPES_PAR_PROFESSION[soignantProfession] ?? [],
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
          Profession conventionnée — installation directe, pas d'expérience requise.
        </p>
      </div>

      <ProgressBarParcours
        etapesTotales={etapes.length}
        etapesValidees={etapesValidees}
        parcoursDemarre={parcours.demarre_le}
        parcoursTermine={parcours.termine_le}
      />

      <div className="rounded-xl border border-info/30 bg-info/5 p-3 flex gap-2">
        <Info className="h-5 w-5 text-info shrink-0 mt-0.5" />
        <div>
          <p className="text-sm font-semibold text-foreground">Parcours libéral conventionné</p>
          <p className="text-xs text-muted-foreground mt-1">
            Ta profession ne requiert pas d'expérience préalable pour s'installer en libéral. Tu peux démarrer dès l'obtention de ton diplôme. Ta profession est conventionnée avec l'Assurance Maladie, tes patients seront remboursés selon les tarifs de la convention.
          </p>
        </div>
      </div>

      {soignantProfession === 'MEDECIN' && <QuizSecteurMedecin />}

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

      <div className="card-base space-y-3">
        <h3 className="text-base font-bold text-foreground flex items-center gap-2">
          <MapPin className="h-5 w-5 text-primary" />
          Vérifier ta zone d'installation
        </h3>
        <p className="text-sm text-muted-foreground">
          Certaines zones sur-dotées ont un accès restreint au conventionnement. Consulte ta zone avant de t'installer.
        </p>
        <a
          href="https://cartosante.atlasante.fr"
          target="_blank"
          rel="noopener noreferrer"
          className="inline-flex items-center gap-1.5 text-sm text-primary font-medium hover:underline"
        >
          Consulter CartoSanté
          <ExternalLink className="h-3.5 w-3.5" />
        </a>
      </div>

      {soignantProfession === 'ORTHOPHONISTE' && (
        <div className="rounded-xl border border-info/30 bg-info/5 p-3 flex gap-2">
          <Info className="h-5 w-5 text-info shrink-0 mt-0.5" />
          <div>
            <p className="text-sm font-semibold text-foreground">Contrats incitatifs</p>
            <p className="text-xs text-muted-foreground mt-1">
              En zone sous-dense, tu peux adhérer à un des 3 contrats : CAIOP (aide à l'installation), CAPIOP (aide à la 1ère installation), CAMOP (aide au maintien). Durée 3 ou 5 ans avec primes forfaitaires.
            </p>
          </div>
        </div>
      )}
    </div>
  );
}
