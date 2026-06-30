/**
 * ChecklistActivation — rampe d'activation soignant (refonte Accueil PR-E)
 *
 * Carte persistante en tête de dashboard : LA rampe d'activation unique, tant
 * que le soignant n'est pas « prêt à postuler ».
 *
 * 2 étapes seulement (le paiement est sorti de la rampe : il devient un nudge
 * contextuel just-in-time, déclenché après la 1ʳᵉ mission terminée — cf.
 * DashboardSoignant) :
 *  ① Tes documents      (tous_documents_valides — pour être accepté·e)
 *  ② Ta présentation    (bio renseignée — +chances d'être sélectionné·e)
 *
 * UN SEUL CTA primaire = la prochaine étape non faite.
 * Quand les 2 étapes sont faites, le composant ne rend RIEN.
 *
 * Usage (DashboardSoignant) :
 *   const activation = useActivationSoignant({ soignant, documents });
 *   <ChecklistActivation state={activation} />
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
  rpps_verifie?: boolean | null;
  tous_documents_valides: boolean | null;
}

/** Sous-ensemble des documents retournés par fn_dashboard_soignant_complet. */
export interface DocumentActivation {
  type_document: string;
  statut_verification: string | null;
  valide_jusqua: string | null;
}

export interface EtapeActivation {
  id: 'documents' | 'presentation';
  numero: 1 | 2;
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
}

/** Longueur minimale d'une bio considérée « renseignée ». */
const BIO_MIN = 30;

export function useActivationSoignant({ soignant, documents }: UseActivationParams): ActivationState {
  const { user } = useAuth();

  const docsFaits = !!soignant?.tous_documents_valides;
  const besoinFetch = !!soignant && !!user;

  const { data: extra } = useQuery({
    queryKey: ['activation-soignant', user?.id],
    queryFn: async () => {
      const [drRes, sgRes] = await Promise.all([
        supabase
          .from('documents_requis_par_profession')
          .select('profession, type_document, est_critique, type_exercice_requis'),
        supabase.from('soignants').select('adeli_verifie, bio').eq('id', user!.id).maybeSingle(),
      ]);
      return {
        docsRequisRows: (drRes.data ?? []) as any[],
        adeliVerifie: !!(sgRes.data as any)?.adeli_verifie,
        bio: ((sgRes.data as any)?.bio ?? '') as string,
      };
    },
    enabled: besoinFetch,
    staleTime: 60_000,
  });

  // Nombre de documents critiques encore manquants (même filtrage que DocumentsSoignant).
  const docsRestants = useMemo<number | null>(() => {
    if (!soignant?.profession || docsFaits || !extra) return null;
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
  }, [soignant, documents, extra, docsFaits]);

  return useMemo<ActivationState>(() => {
    const presentationFaite = (extra?.bio?.trim().length ?? 0) >= BIO_MIN;

    let detailDocuments: string | undefined;
    if (!docsFaits) {
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
        id: 'documents',
        numero: 1,
        label: 'Tes documents',
        detail: docsFaits ? undefined : detailDocuments,
        faite: docsFaits,
      },
      {
        id: 'presentation',
        numero: 2,
        label: 'Ta présentation',
        detail: presentationFaite ? undefined : 'Une bio = jusqu’à 3× plus de chances d’être sélectionné·e',
        faite: presentationFaite,
      },
    ];

    const nbFaites = etapes.filter((e) => e.faite).length;
    const prochaineEtape = etapes.find((e) => !e.faite) ?? null;

    let ctaLabel = '';
    let ctaDestination = '/soignant/mes-documents';
    if (prochaineEtape?.id === 'documents') {
      ctaLabel = 'Téléverse tes documents — ~3 min';
      ctaDestination = '/soignant/mes-documents';
    } else if (prochaineEtape?.id === 'presentation') {
      ctaLabel = 'Ajoute ta présentation — ~1 min';
      ctaDestination = '/soignant/profil';
    }

    // Anti-flash : l'étape « présentation » dépend du fetch (bio). Tant qu'il
    // n'est pas résolu, on n'affiche la carte que si l'étape documents suffit
    // déjà à la rendre visible (évite d'afficher puis cacher pour un profil prêt).
    const extraResolu = extra !== undefined || !besoinFetch;
    const visible =
      !!soignant && prochaineEtape !== null && (extraResolu || !docsFaits);

    return { visible, etapes, nbFaites, prochaineEtape, ctaLabel, ctaDestination };
  }, [soignant, docsFaits, extra, docsRestants, besoinFetch]);
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
  // ni repousser les missions sous la ligne de flottaison.
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
      <Mascotte etat={nbFaites >= 1 ? 'happy' : 'thinking'} taille="sm" className="shrink-0" />
      <div className="flex-1 min-w-0">
        <div className="flex items-center justify-between gap-2">
          <p className="text-sm font-semibold text-foreground truncate">{state.ctaLabel}</p>
          <span className="text-xs font-semibold text-primary shrink-0 tabular-nums">{nbFaites}/2</span>
        </div>
        {prochaineEtape.detail && (
          <p className="text-xs text-muted-foreground truncate mt-0.5">{prochaineEtape.detail}</p>
        )}
        <div className="mt-1.5">
          <JaugeProgression valeur={nbFaites} max={2} />
        </div>
      </div>
      <ChevronRight className="h-5 w-5 text-primary shrink-0" aria-hidden="true" />
    </button>
  );
}

export default ChecklistActivation;
