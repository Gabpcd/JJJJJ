/**
 * ChecklistActivation — Session E-3 « activation soignant »
 *
 * Carte persistante en tête de dashboard : LA rampe d'activation unique
 * (standard Doctolib pro / Airbnb host onboarding — une seule rampe de
 * progression, jamais 5 bannières concurrentes).
 *
 * 3 étapes :
 *  ① Identité vérifiée   (identite_verifiee / rpps_verifie)
 *  ② Documents validés   (tous_documents_valides + compte des documents restants)
 *  ③ Première candidature (candidature envoyée, mission assignée ou terminée)
 *
 * UN SEUL CTA primaire = la prochaine étape non faite.
 * Quand les 3 étapes sont faites, le composant ne rend RIEN.
 *
 * Données : profil + documents déjà chargés par fn_dashboard_soignant_complet
 * (passés en props via le hook), complétées par un fetch léger
 * (documents_requis_par_profession + count candidatures + adeli_verifie).
 *
 * Usage (DashboardSoignant) :
 *   const activation = useActivationSoignant({ soignant, documents, missionsActives });
 *   <ChecklistActivation state={activation} />
 *   {!activation.visible && <BandeauGraceDocuments ... />}  // bannières absorbées
 */
import { useMemo } from 'react';
import { useNavigate } from 'react-router-dom';
import { useQuery } from '@tanstack/react-query';
import { CheckCircle2, Circle } from 'lucide-react';
import { cn } from '@/lib/utils';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { TYPES_DOCUMENTS_EXCLUS_UPLOAD } from '@/lib/documents';
import { CardY2K } from '@/components/y2k/CardY2K';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { Mascotte } from '@/components/mascotte/Mascotte';
import { JaugeProgression } from '@/components/JaugeProgression';

/* ─── Types ──────────────────────────────────────────────────────────────── */

/** Sous-ensemble du profil retourné par fn_dashboard_soignant_complet. */
export interface SoignantActivation {
  profession: string | null;
  type_exercice: string | null;
  identite_verifiee: boolean | null;
  rpps_verifie?: boolean | null;
  tous_documents_valides: boolean | null;
  total_missions_terminees: number | null;
}

/** Sous-ensemble des documents retournés par fn_dashboard_soignant_complet. */
export interface DocumentActivation {
  type_document: string;
  statut_verification: string | null;
  valide_jusqua: string | null;
}

export interface EtapeActivation {
  id: 'identite' | 'documents' | 'candidature';
  numero: 1 | 2 | 3;
  label: string;
  /** Sous-texte affiché sous le label quand l'étape n'est pas faite. */
  detail?: string;
  faite: boolean;
}

export interface ActivationState {
  /** true tant qu'au moins une étape n'est pas faite (la carte est affichée). */
  visible: boolean;
  etapes: EtapeActivation[];
  nbFaites: number;
  prochaineEtape: EtapeActivation | null;
  ctaLabel: string;
  ctaDestination: string;
}

/* ─── Hook ───────────────────────────────────────────────────────────────── */

interface UseActivationParams {
  soignant: SoignantActivation | null;
  documents: DocumentActivation[];
  /** Missions ASSIGNEE/EN_COURS connues du dashboard (mes_missions.length). */
  missionsActives: number;
}

export function useActivationSoignant({ soignant, documents, missionsActives }: UseActivationParams): ActivationState {
  const { user } = useAuth();

  const etape1Faite = !!(soignant?.identite_verifiee || soignant?.rpps_verifie);
  const etape2Faite = !!soignant?.tous_documents_valides;
  // Étape 3 déjà déductible des données dashboard : mission assignée/en cours ou terminée.
  const etape3Connue = missionsActives > 0 || (soignant?.total_missions_terminees ?? 0) > 0;

  const besoinFetch = !!soignant && !!user && (!etape2Faite || !etape3Connue);

  const { data: extra } = useQuery({
    queryKey: ['activation-soignant', user?.id],
    queryFn: async () => {
      const [drRes, candRes, sgRes] = await Promise.all([
        supabase
          .from('documents_requis_par_profession')
          .select('profession, type_document, est_critique, type_exercice_requis'),
        // Candidatures initiées (ou acceptées) par le soignant — on exclut les
        // propositions système du pool d'urgence (statut PROPOSEE).
        supabase
          .from('candidatures')
          .select('id', { count: 'exact', head: true })
          .eq('soignant_id', user!.id)
          .neq('statut', 'PROPOSEE'),
        supabase.from('soignants').select('adeli_verifie').eq('id', user!.id).maybeSingle(),
      ]);
      return {
        docsRequisRows: (drRes.data ?? []) as any[],
        aPostule: (candRes.count ?? 0) > 0,
        adeliVerifie: !!(sgRes.data as any)?.adeli_verifie,
      };
    },
    enabled: besoinFetch,
    staleTime: 60_000,
  });

  // Nombre de documents critiques encore manquants (même filtrage que DocumentsSoignant).
  const docsRestants = useMemo<number | null>(() => {
    if (!soignant?.profession || etape2Faite || !extra) return null;
    const estLiberal = soignant.type_exercice === 'LIBERAL' || soignant.type_exercice === 'MIXTE';
    const estSalarie = soignant.type_exercice !== 'LIBERAL';
    const identiteVerifiee = !!(soignant.rpps_verifie || extra.adeliVerifie);
    const requis = extra.docsRequisRows.filter((d: any) => {
      if (d.profession !== soignant.profession) return false;
      if (!d.est_critique) return false;
      if (TYPES_DOCUMENTS_EXCLUS_UPLOAD.includes(d.type_document)) return false;
      if (identiteVerifiee && (d.type_document === 'DIPLOME' || d.type_document === 'RPPS_ADELI')) return false;
      const exReq = d.type_exercice_requis || 'TOUS';
      if (exReq === 'LIBERAL_ONLY') return estLiberal;
      if (exReq === 'SALARIE_ONLY') return estSalarie;
      return true;
    });
    const manquants = requis.filter(
      (r: any) =>
        !documents.some(
          (doc) =>
            doc.type_document === r.type_document &&
            doc.statut_verification === 'VERIFIE' &&
            (!doc.valide_jusqua || new Date(doc.valide_jusqua) > new Date()),
        ),
    );
    return manquants.length;
  }, [soignant, documents, extra, etape2Faite]);

  return useMemo<ActivationState>(() => {
    const etape3Faite = etape3Connue || !!extra?.aPostule;

    let detailDocuments: string | undefined;
    if (!etape2Faite) {
      if (docsRestants != null && docsRestants > 0) {
        detailDocuments = `Il vous reste ${docsRestants} document${docsRestants > 1 ? 's' : ''} — ~3 min, une photo suffit`;
      } else if (docsRestants === 0) {
        detailDocuments = 'Tout est téléversé — vérification en cours';
      } else {
        detailDocuments = '~3 min, une photo suffit';
      }
    }

    const etapes: EtapeActivation[] = [
      {
        id: 'identite',
        numero: 1,
        label: 'Identité vérifiée',
        detail: etape1Faite ? undefined : 'Votre pièce d’identité ou votre n° RPPS suffit',
        faite: etape1Faite,
      },
      {
        id: 'documents',
        numero: 2,
        label: 'Documents validés',
        detail: detailDocuments,
        faite: etape2Faite,
      },
      {
        id: 'candidature',
        numero: 3,
        label: 'Première candidature',
        detail: etape3Faite ? undefined : 'Postulez en un clic, sans engagement',
        faite: etape3Faite,
      },
    ];

    const nbFaites = etapes.filter((e) => e.faite).length;
    const prochaineEtape = etapes.find((e) => !e.faite) ?? null;

    let ctaLabel = '';
    let ctaDestination = '/soignant/recherche-missions';
    if (prochaineEtape?.id === 'identite') {
      ctaLabel = 'Vérifier mon identité — 2 min';
      ctaDestination = '/soignant/mes-documents';
    } else if (prochaineEtape?.id === 'documents') {
      ctaLabel = 'Téléverser mes documents — ~3 min';
      ctaDestination = '/soignant/mes-documents';
    } else if (prochaineEtape?.id === 'candidature') {
      ctaLabel = 'Voir les missions';
      ctaDestination = '/soignant/recherche-missions';
    }

    // Anti-flash : si seules les 2 premières étapes sont faites et que le statut
    // candidature n'est pas encore chargé, on attend la réponse avant d'afficher
    // (évite d'afficher puis cacher la carte pour un soignant déjà activé).
    const etape3Resolue = etape3Connue || !besoinFetch || extra !== undefined;
    const visible =
      !!soignant && prochaineEtape !== null && (etape3Resolue || !etape1Faite || !etape2Faite);

    return { visible, etapes, nbFaites, prochaineEtape, ctaLabel, ctaDestination };
  }, [soignant, etape1Faite, etape2Faite, etape3Connue, extra, docsRestants, besoinFetch]);
}

/* ─── Composant ──────────────────────────────────────────────────────────── */

interface ChecklistActivationProps {
  state: ActivationState;
  className?: string;
}

export function ChecklistActivation({ state, className }: ChecklistActivationProps) {
  const navigate = useNavigate();

  const prochaineEtape = state.prochaineEtape;
  if (!state.visible || !prochaineEtape) return null;

  const { etapes, nbFaites } = state;
  const restantes = etapes.length - nbFaites;

  return (
    <CardY2K hoverLift={false} className={cn('mb-6', className)} data-testid="checklist-activation">
      <div className="flex items-start gap-3 mb-4">
        <Mascotte etat={nbFaites >= 2 ? 'happy' : 'thinking'} taille="sm" className="shrink-0" />
        <div className="flex-1 min-w-0">
          <h2 className="text-base font-bold text-foreground">À faire maintenant</h2>
          <p className="text-xs text-muted-foreground mt-0.5">
            {restantes === 1
              ? 'Plus qu’une étape avant vos premières missions'
              : `Encore ${restantes} étapes avant vos premières missions`}
          </p>
        </div>
        <span className="text-xs font-semibold text-primary shrink-0 tabular-nums">{nbFaites}/3</span>
      </div>

      <JaugeProgression valeur={nbFaites} max={3} />

      <ol className="mt-4 space-y-3" aria-label="Étapes d'activation">
        {etapes.map((etape) => (
          <li key={etape.id} className="flex items-start gap-2.5">
            {etape.faite ? (
              <CheckCircle2 className="h-5 w-5 text-success shrink-0" aria-hidden="true" />
            ) : (
              <Circle
                className={cn(
                  'h-5 w-5 shrink-0',
                  etape.id === prochaineEtape.id ? 'text-primary' : 'text-muted-foreground/40',
                )}
                aria-hidden="true"
              />
            )}
            <div className="min-w-0">
              <p
                className={cn(
                  'text-sm leading-5',
                  etape.faite
                    ? 'text-muted-foreground line-through'
                    : etape.id === prochaineEtape.id
                      ? 'font-semibold text-foreground'
                      : 'text-foreground',
                )}
              >
                {etape.numero === 1 ? '①' : etape.numero === 2 ? '②' : '③'} {etape.label}
              </p>
              {!etape.faite && etape.detail && (
                <p className="text-xs text-muted-foreground mt-0.5">{etape.detail}</p>
              )}
            </div>
          </li>
        ))}
      </ol>

      <BoutonY2K
        variant="primary"
        size="md"
        className="mt-5 w-full sm:w-auto"
        onClick={() => navigate(state.ctaDestination)}
      >
        {state.ctaLabel}
      </BoutonY2K>
    </CardY2K>
  );
}

export default ChecklistActivation;
