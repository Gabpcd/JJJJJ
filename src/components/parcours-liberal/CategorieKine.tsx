import { useState, useMemo } from 'react';
import { ExternalLink, Info, Plus, MapPin, Clock, RotateCcw } from 'lucide-react';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle } from '@/components/ui/alert-dialog';
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
  choisirParcoursKine: (p: 'HEURES_2240' | 'ZONE_SOUS_DOTEE' | null) => Promise<unknown>;
  ajouterHeuresExternes: (payload: {
    etablissement_nom: string;
    etablissement_type?: string;
    date_debut: string;
    date_fin: string;
    heures_declarees: number;
    attestation_file?: File;
  }) => Promise<unknown>;
  supprimerHeuresExternes: (id: string) => Promise<unknown>;
}

const ETAPES_KINE_COMMUNES: Etape[] = [
  {
    cle: 'inscription_ordre',
    label: "Inscription à l'Ordre des Masseurs-Kinésithérapeutes",
    description: 'Obtiens ton numéro RPPS et ta carte CPS.',
    lienExterne: 'https://www.ordremk.fr',
    lienLabel: 'Ordre MK',
  },
  {
    cle: 'inscription_cpam',
    label: 'Conventionnement CPAM',
    description: 'Démarche en ligne disponible.',
    lienExterne: 'https://installation-kine.ameli.fr',
    lienLabel: 'Ameli installation kiné',
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
    description: 'Caisse de retraite obligatoire.',
    lienExterne: 'https://www.carpimko.com',
    lienLabel: 'CARPIMKO',
  },
  {
    cle: 'souscription_rcp',
    label: 'Souscription RC Pro',
    description: "La Responsabilité Civile Professionnelle est obligatoire.",
  },
];

const ETAPES_KINE_ZONE: Etape[] = [
  {
    cle: 'zone_verifiee',
    label: 'Zone sous-dotée vérifiée sur CartoSanté',
    description: "Valide avec ta CPAM que la zone ciblée est bien sous-dotée selon le dernier arrêté ARS.",
    lienExterne: 'https://cartosante.atlasante.fr',
    lienLabel: 'CartoSanté',
  },
  ...ETAPES_KINE_COMMUNES,
  {
    cle: 'engagement_signe',
    label: 'Engagement signé auprès de la CPAM',
    description: 'Durée minimum de 2 ans dans la zone identifiée sous-dotée.',
  },
];

function CarteChoix({
  titre,
  description,
  badge,
  Icone,
  onClick,
}: {
  titre: string;
  description: string;
  badge: string;
  Icone: typeof Clock;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className="card-base text-left hover:shadow-md hover:border-primary/40 transition-all cursor-pointer group"
    >
      <div className="flex items-start gap-3 mb-2">
        <div className="p-2 rounded-xl bg-primary/10">
          <Icone className="h-5 w-5 text-primary" />
        </div>
        <div className="flex-1 min-w-0">
          <h4 className="font-bold text-foreground">{titre}</h4>
          <span className="inline-block mt-1 text-[10px] font-semibold px-2 py-0.5 rounded-full bg-primary/10 text-primary">{badge}</span>
        </div>
      </div>
      <p className="text-sm text-muted-foreground">{description}</p>
      <p className="text-xs text-primary font-medium mt-3 group-hover:underline">Choisir cette voie →</p>
    </button>
  );
}

export function CategorieKine({
  parcours,
  compteurHeures,
  heuresExternes,
  majEtape,
  choisirParcoursKine,
  ajouterHeuresExternes,
  supprimerHeuresExternes,
}: Props) {
  const [showFormHeures, setShowFormHeures] = useState(false);
  const [confirmReset, setConfirmReset] = useState(false);

  const etapesActives = useMemo(
    () => (parcours.parcours_kine === 'ZONE_SOUS_DOTEE' ? ETAPES_KINE_ZONE : ETAPES_KINE_COMMUNES),
    [parcours.parcours_kine],
  );
  const etapesValidees = useMemo(
    () => etapesActives.filter(e => Boolean(parcours.etapes[e.cle])).length,
    [etapesActives, parcours.etapes],
  );

  const handleMajEtape = async (cle: string, valeur: boolean) => {
    await majEtape(cle, valeur);
  };

  const handleAjouter = async (payload: Parameters<Props['ajouterHeuresExternes']>[0]) => {
    const res = await ajouterHeuresExternes(payload);
    setShowFormHeures(false);
    return res as ResultatVerifHeures | null;
  };

  const handleChangerParcours = async () => {
    await choisirParcoursKine(null);
    setConfirmReset(false);
  };

  // Case 1: choix du parcours
  if (!parcours.parcours_kine) {
    return (
      <div className="space-y-4">
        <div>
          <h1 className="text-xl font-bold text-foreground">Ton parcours kiné libéral</h1>
          <p className="text-sm text-muted-foreground mt-1">
            La convention kiné (avenant 7, 2023) propose 2 voies d'accès au conventionnement.
          </p>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
          <CarteChoix
            titre="Voie des heures d'expérience"
            description="2 240h (équivalent 70% d'un temps plein sur 2 ans) en établissement de santé."
            badge="La plus courante"
            Icone={Clock}
            onClick={() => choisirParcoursKine('HEURES_2240')}
          />
          <CarteChoix
            titre="Voie de la zone sous-dotée"
            description="Engagement à exercer 2 ans en zone identifiée sous-dotée par l'ARS."
            badge="Installation directe possible"
            Icone={MapPin}
            onClick={() => choisirParcoursKine('ZONE_SOUS_DOTEE')}
          />
        </div>
      </div>
    );
  }

  // Case 2 & 3: parcours choisi
  const estParcoursHeures = parcours.parcours_kine === 'HEURES_2240';

  return (
    <div className="space-y-4">
      <div className="flex items-start justify-between gap-2 flex-wrap">
        <div>
          <h1 className="text-xl font-bold text-foreground">Ton parcours kiné libéral</h1>
          <p className="text-sm text-muted-foreground mt-1">
            {estParcoursHeures
              ? 'Voie des heures d\'expérience (2 240h en 2 ans)'
              : "Voie de la zone sous-dotée (engagement 2 ans)"}
          </p>
        </div>
        <BoutonY2K variant="ghost" size="sm" onClick={() => setConfirmReset(true)} className="gap-1.5 text-xs" iconeGauche={<RotateCcw className="h-3.5 w-3.5" />}>
          Changer de parcours
        </BoutonY2K>
      </div>

      <ProgressBarParcours
        etapesTotales={etapesActives.length}
        etapesValidees={etapesValidees}
        parcoursDemarre={parcours.demarre_le}
        parcoursTermine={parcours.termine_le}
      />

      {estParcoursHeures && (
        <>
          <JaugeHeures
        demarreLe={parcours.demarre_le}
            heuresJolene={compteurHeures?.heures_jolene ?? 0}
            heuresExternesValidees={compteurHeures?.heures_externes_validees ?? 0}
            heuresExternesEnAttente={compteurHeures?.heures_externes_en_attente ?? 0}
            seuilRequis={2240}
            titre="Ton expérience professionnelle kiné"
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
              Si tu as déjà travaillé en établissement hors Jolene, déclare ces heures avec l'attestation de ton employeur.
            </p>

            <ListeHeuresExternes heures={heuresExternes} onSupprimer={supprimerHeuresExternes as (id: string) => Promise<void>} />

            {showFormHeures && (
              <div className="mt-3">
                <FormulaireHeuresExternes
                  onSubmit={handleAjouter}
                  onCancel={() => setShowFormHeures(false)}
                />
              </div>
            )}
          </div>
        </>
      )}

      {!estParcoursHeures && (
        <div className="card-base space-y-3">
          <h3 className="text-base font-bold text-foreground flex items-center gap-2">
            <MapPin className="h-5 w-5 text-primary" />
            Ton engagement en zone sous-dotée
          </h3>
          <p className="text-sm text-muted-foreground">
            Tu t'engages à exercer pendant <strong>2 ans minimum</strong> dans une zone identifiée sous-dotée par l'ARS. Consulte le zonage kiné en ligne.
          </p>
          <a
            href="https://cartosante.atlasante.fr"
            target="_blank"
            rel="noopener noreferrer"
            className="inline-flex items-center gap-1.5 text-sm text-primary font-medium hover:underline"
          >
            Voir le zonage kiné
            <ExternalLink className="h-3.5 w-3.5" />
          </a>
        </div>
      )}

      <div className="card-base">
        <h3 className="text-base font-bold text-foreground mb-3">Tes démarches d'installation</h3>
        <ChecklistEtapes
          etapes={etapesActives}
          etapesValidees={parcours.etapes}
          onToggle={handleMajEtape}
        />
      </div>

      <div className="rounded-xl border border-info/30 bg-info/5 p-3 flex gap-2">
        <Info className="h-5 w-5 text-info shrink-0 mt-0.5" />
        <div>
          <p className="text-sm font-semibold text-foreground">Règle officielle</p>
          <p className="text-xs text-muted-foreground mt-1">
            La convention kiné (avenant 7, 2023) propose 2 voies : soit 2 240h d'expérience (70% d'un temps plein sur 2 ans), soit engagement en zone sous-dotée pendant 2 ans minimum.
          </p>
        </div>
      </div>

      <AlertDialog open={confirmReset} onOpenChange={setConfirmReset}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Changer de parcours ?</AlertDialogTitle>
            <AlertDialogDescription>
              Ta progression sera conservée mais tu seras renvoyé à l'écran de choix. Tu pourras sélectionner l'autre voie.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Annuler</AlertDialogCancel>
            <AlertDialogAction onClick={handleChangerParcours}>Changer</AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}
