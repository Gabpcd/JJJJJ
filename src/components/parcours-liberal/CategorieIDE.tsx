import { useState, useMemo } from 'react';
import { ExternalLink, Info, Plus, MapPin } from 'lucide-react';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import type { RegleInstallation } from '@/lib/regles-installation-liberal';
import type { ParcoursLiberal, CompteurHeures, HeureExterne, ResultatVerifHeures } from '@/hooks/useParcoursLiberal';
import { ProgressBarParcours } from './ProgressBarParcours';
import { JaugeHeures } from './JaugeHeures';
import { ChecklistEtapes, type Etape } from './ChecklistEtapes';
import { FormulaireHeuresExternes } from './FormulaireHeuresExternes';
import { ListeHeuresExternes } from './ListeHeuresExternes';

interface Props {
  parcours: ParcoursLiberal;
  compteurHeures: CompteurHeures | null;
  heuresExternes: HeureExterne[];
  regle: RegleInstallation;
  majEtape: (cle: string, valeur: boolean) => Promise<unknown>;
  ajouterHeuresExternes: (payload: Parameters<typeof Object>[0] & {
    etablissement_nom: string;
    etablissement_type?: string;
    date_debut: string;
    date_fin: string;
    heures_declarees: number;
    attestation_file?: File;
  }) => Promise<unknown>;
  supprimerHeuresExternes: (id: string) => Promise<unknown>;
}

const ETAPES_IDE: Etape[] = [
  {
    cle: 'inscription_ordre',
    label: "Inscription à l'Ordre des Infirmiers",
    description: 'Obtiens ton numéro RPPS et ta carte CPS.',
    lienExterne: 'https://www.ordre-infirmiers.fr',
    lienLabel: "Ordre des Infirmiers",
  },
  {
    cle: 'inscription_cpam',
    label: 'Conventionnement auprès de la CPAM',
    description: "Démarche en ligne disponible. Choix de la zone d'installation + signature de la convention nationale.",
    lienExterne: 'https://installation-idel.ameli.fr',
    lienLabel: 'Démarches Ameli',
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
    description: 'Caisse de retraite obligatoire pour les auxiliaires médicaux libéraux.',
    lienExterne: 'https://www.carpimko.com',
    lienLabel: 'CARPIMKO',
  },
  {
    cle: 'souscription_rcp',
    label: 'Souscription RC Pro',
    description: "La Responsabilité Civile Professionnelle est obligatoire. MACSF, SHAM et Le Sou Médical sont les assureurs principaux.",
  },
  {
    cle: 'local_professionnel',
    label: 'Local professionnel (ou domicile)',
    description: "Respect des normes d'accessibilité PMR et d'hygiène.",
  },
];

export function CategorieIDE({
  parcours,
  compteurHeures,
  heuresExternes,
  majEtape,
  ajouterHeuresExternes,
  supprimerHeuresExternes,
}: Props) {
  const [showFormHeures, setShowFormHeures] = useState(false);

  const etapesValidees = useMemo(
    () => ETAPES_IDE.filter(e => Boolean(parcours.etapes[e.cle])).length,
    [parcours.etapes],
  );

  const handleMajEtape = async (cle: string, valeur: boolean) => {
    await majEtape(cle, valeur);
  };

  const handleAjouter = async (payload: Parameters<Props['ajouterHeuresExternes']>[0]) => {
    const res = await ajouterHeuresExternes(payload);
    setShowFormHeures(false);
    return res as ResultatVerifHeures | null;
  };

  const handleSupprimer = async (id: string) => {
    await supprimerHeuresExternes(id);
  };

  return (
    <div className="space-y-4">
      <div>
        <h1 className="text-xl font-bold text-foreground">Ton parcours libéral IDE</h1>
        <p className="text-sm text-muted-foreground mt-1">
          Convention IDE 2007 — 3 200h d'expérience sur 24 mois dans les 6 dernières années.
        </p>
      </div>

      <ProgressBarParcours
        etapesTotales={ETAPES_IDE.length}
        etapesValidees={etapesValidees}
        parcoursDemarre={parcours.demarre_le}
        parcoursTermine={parcours.termine_le}
      />

      <JaugeHeures
        demarreLe={parcours.demarre_le}
        heuresJolene={compteurHeures?.heures_jolene ?? 0}
        heuresExternesValidees={compteurHeures?.heures_externes_validees ?? 0}
        heuresExternesEnAttente={compteurHeures?.heures_externes_en_attente ?? 0}
        seuilRequis={3200}
        eligibleFreeTransition={compteurHeures?.eligible_free_transition}
        titre="Ton expérience professionnelle IDE"
        legendeJolene="Heures via Jolene (comptées automatiquement)"
        legendeExternes="Heures externes déclarées (attestations fournies)"
      />

      <div className="card-base">
        <div className="flex items-center justify-between gap-2 flex-wrap mb-2">
          <h3 className="text-base font-bold text-foreground">Heures externes (hors Jolene)</h3>
          {!showFormHeures && (
            <BoutonY2K size="sm" onClick={() => setShowFormHeures(true)} className="gap-1.5" iconeGauche={<Plus className="h-4 w-4" />}>
              Déclarer des heures
            </BoutonY2K>
          )}
        </div>
        <p className="text-sm text-muted-foreground mb-3">
          Si tu as déjà travaillé en établissement hors Jolene, déclare ces heures avec l'attestation de ton employeur pour les faire compter.
        </p>

        <ListeHeuresExternes heures={heuresExternes} onSupprimer={handleSupprimer} />

        {showFormHeures && (
          <div className="mt-3">
            <FormulaireHeuresExternes
              onSubmit={handleAjouter}
              onCancel={() => setShowFormHeures(false)}
            />
          </div>
        )}
      </div>

      <div className="card-base">
        <h3 className="text-base font-bold text-foreground mb-3">Tes démarches d'installation</h3>
        <ChecklistEtapes
          etapes={ETAPES_IDE}
          etapesValidees={parcours.etapes}
          onToggle={handleMajEtape}
        />
      </div>

      <div className="card-base space-y-3">
        <h3 className="text-base font-bold text-foreground flex items-center gap-2">
          <MapPin className="h-5 w-5 text-primary" />
          Vérifier ta zone d'installation
        </h3>
        <p className="text-sm text-muted-foreground">
          Les zones sur-dotées ont un accès restreint au conventionnement (règle du 1 pour 1). Consulte ta zone avant de t'installer.
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

      <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
        <div className="rounded-xl border border-info/30 bg-info/5 p-3 flex gap-2">
          <Info className="h-5 w-5 text-info shrink-0 mt-0.5" />
          <div>
            <p className="text-sm font-semibold text-foreground">Règle officielle</p>
            <p className="text-xs text-muted-foreground mt-1">
              La convention IDE 2007 (article 5.2.2) exige 3 200h d'expérience sur 24 mois dans les 6 années précédant l'installation. Alternative : 2 400h + 6 mois de remplacement IDEL.
            </p>
          </div>
        </div>
        <div className="rounded-xl border border-info/30 bg-info/5 p-3 flex gap-2">
          <Info className="h-5 w-5 text-info shrink-0 mt-0.5" />
          <div>
            <p className="text-sm font-semibold text-foreground">Dérogations possibles</p>
            <p className="text-xs text-muted-foreground mt-1">
              En cas de carence démographique ou situation personnelle particulière, la CPAM peut accorder une dérogation (article 7.3.3). Contacte ta CPAM.
            </p>
          </div>
        </div>
      </div>
    </div>
  );
}
