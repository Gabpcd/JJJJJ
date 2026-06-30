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
import { ChevronRight } from 'lucide-react';
import { cn } from '@/lib/utils';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { TYPES_DOCUMENTS_EXCLUS_UPLOAD } from '@/lib/documents';
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
        detailDocuments = `Il te reste ${docsRestants} document${docsRestants > 1 ? 's' : ''} — ~3 min, une photo suffit`;
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
        detail: etape1Faite ? undefined : 'Ta pièce d’identité ou ton n° RPPS suffit',
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
        detail: etape3Faite ? undefined : 'Postule en un clic, sans engagement — sans documents validés aussi',
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

  const { nbFaites } = state;

  // Bandeau COMPACT (1 ligne) : la rampe d'activation ne doit pas manger l'écran
  // ni repousser les missions sous la ligne de flottaison. Mascotte + prochaine
  // action + progression + chevron, le tout cliquable vers l'étape à faire.
  return (
    <button
      type="button"
      onClick={() => navigate(state.ctaDestination)}
      aria-label={state.ctaLabel}
      data-testid="checklist-activation"
      className={cn(
        'w-full text-left flex items-center gap-3 rounded-2xl px-3.5 py-2.5',
        'border border-jolene-rose-200/60 bg-gradient-soft hover:border-jolene-rose-300 transition-colors',
        className,
      )}
    >
      <Mascotte etat={nbFaites >= 2 ? 'happy' : 'thinking'} taille="sm" className="shrink-0" />
      <div className="flex-1 min-w-0">
        <div className="flex items-center justify-between gap-2">
          <p className="text-sm font-semibold text-foreground truncate">{state.ctaLabel}</p>
          <span className="text-xs font-semibold text-primary shrink-0 tabular-nums">{nbFaites}/3</span>
        </div>
        {prochaineEtape.detail && (
          <p className="text-xs text-muted-foreground truncate mt-0.5">{prochaineEtape.detail}</p>
        )}
        <div className="mt-1.5">
          <JaugeProgression valeur={nbFaites} max={3} />
        </div>
      </div>
      <ChevronRight className="h-5 w-5 text-primary shrink-0" aria-hidden="true" />
    </button>
  );
}

export default ChecklistActivation;
