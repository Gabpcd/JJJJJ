/**
 * ChecklistActivation — LA carte d'activation unique de l'Accueil (Lot 6b.4).
 *
 * Remplace les banners concurrents (documents, mandat, paiement, complétion)
 * par UNE carte « Active ton compte — X/N » avec anneau de progression.
 * Chaque ligne ouvre le flow correspondant. Disparaît quand tout est fait.
 *
 * Étapes (adaptatives — le compteur s'ajuste au régime et à la profession) :
 *  ① Identité professionnelle (RPPS) — sauf professions sans RPPS (AS/AES/AP)
 *  ② Documents                       — tous_documents_valides
 *  ③ Mandat de facturation           — libéral/mixte uniquement
 *  ④ Compte de paiement              — libéral : Stripe OU RIB · salarié : RIB
 *
 * Le même état (`useActivationSoignant`) alimente le gating des autres
 * bandeaux de l'Accueil : au plus UNE carte d'action système visible.
 *
 * Usage (DashboardSoignant) :
 *   const activation = useActivationSoignant({ soignant, documents, hasStripeConnect, aRib });
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
import { PROFESSIONS_SANS_RPPS } from '@/lib/constantes';

/* ─── Types ──────────────────────────────────────────────────────────────── */

/** Sous-ensemble du profil retourné par fn_dashboard_soignant_complet. */
export interface SoignantActivation {
  profession: string | null;
  type_exercice: string | null;
  rpps_verifie?: boolean | null;
  tous_documents_valides: boolean | null;
  mandat_facturation_signe?: boolean | null;
}

/** Sous-ensemble des documents retournés par fn_dashboard_soignant_complet. */
export interface DocumentActivation {
  type_document: string;
  statut_verification: string | null;
  valide_jusqua: string | null;
}

export interface EtapeActivation {
  id: 'rpps' | 'documents' | 'mandat' | 'paiement';
  label: string;
  /** Sous-texte affiché sous le label quand l'étape n'est pas faite. */
  detail?: string;
  faite: boolean;
  destination: string;
}

export interface ActivationState {
  /** true tant qu'au moins une étape n'est pas faite (la carte est affichée). */
  visible: boolean;
  etapes: EtapeActivation[];
  nbFaites: number;
  prochaineEtape: EtapeActivation | null;
}

/* ─── Hook ───────────────────────────────────────────────────────────────── */

interface UseActivationParams {
  soignant: SoignantActivation | null;
  documents: DocumentActivation[];
  /** Stripe Connect COMPLET (calculé par le dashboard). */
  hasStripeConnect: boolean;
  /** Un RIB non rejeté est téléversé. */
  aRib: boolean;
}

export function useActivationSoignant({ soignant, documents, hasStripeConnect, aRib }: UseActivationParams): ActivationState {
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
        supabase.from('soignants').select('adeli_verifie').eq('id', user!.id).maybeSingle(),
      ]);
      return {
        docsRequisRows: (drRes.data ?? []) as any[],
        adeliVerifie: !!(sgRes.data as any)?.adeli_verifie,
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
    const professionAvecRpps = !PROFESSIONS_SANS_RPPS.includes(soignant.profession);
    const rppsVerifie = professionAvecRpps && !!soignant.rpps_verifie;
    const identiteVerifiee = rppsVerifie || extra.adeliVerifie;
    const requis = extra.docsRequisRows.filter((d: any) => {
      if (d.profession !== soignant.profession) return false;
      if (!d.est_critique) return false;
      if (TYPES_DOCUMENTS_EXCLUS_UPLOAD.includes(d.type_document)) return false;
      if (identiteVerifiee && d.type_document === 'RPPS_ADELI') return false;
      // Un RPPS validé par l'API atteste déjà le diplôme enregistré pour les
      // professions concernées. Un ADELI seul ne dispense pas du diplôme.
      if (rppsVerifie && d.type_document === 'DIPLOME') return false;
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
    const estLiberal = soignant?.type_exercice === 'LIBERAL' || soignant?.type_exercice === 'MIXTE';
    const professionAvecRpps = !!soignant?.profession && !PROFESSIONS_SANS_RPPS.includes(soignant.profession);
    const rppsFait = !!(soignant?.rpps_verifie || extra?.adeliVerifie);
    const mandatFait = !!soignant?.mandat_facturation_signe;
    const paiementFait = estLiberal ? (hasStripeConnect || aRib) : aRib;

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
      ...(professionAvecRpps ? [{
        id: 'rpps' as const,
        label: 'Ton identité professionnelle',
        detail: rppsFait ? undefined : 'Vérifie ton n° RPPS — ~30 s, débloque tout le reste',
        faite: rppsFait,
        destination: '/soignant/profil',
      }] : []),
      {
        id: 'documents',
        label: 'Tes documents',
        detail: docsFaits ? undefined : detailDocuments,
        faite: docsFaits,
        destination: '/soignant/mes-documents',
      },
      ...(estLiberal ? [{
        id: 'mandat' as const,
        label: 'Ton mandat de facturation',
        detail: mandatFait ? undefined : 'Signature électronique — ~1 min, indispensable pour être payé·e',
        faite: mandatFait,
        destination: '/soignant/mandat-facturation',
      }] : []),
      {
        id: 'paiement',
        label: estLiberal ? 'Ton compte de paiement' : 'Ton RIB',
        detail: paiementFait ? undefined : (estLiberal
          ? 'Stripe ou RIB — le délai dépend du mode indiqué sur chaque mission'
          : 'Une photo de ton RIB suffit — pour recevoir ta rémunération'),
        faite: paiementFait,
        destination: estLiberal ? '/soignant/stripe-connect' : '/soignant/mes-documents',
      },
    ];

    const nbFaites = etapes.filter((e) => e.faite).length;
    const prochaineEtape = etapes.find((e) => !e.faite) ?? null;

    // Anti-flash : l'étape RPPS dépend du fetch (adeli_verifie). Tant qu'il
    // n'est pas résolu, on n'affiche la carte que si une étape indépendante
    // du fetch est déjà manquante (évite d'afficher puis cacher).
    const extraResolu = extra !== undefined || !besoinFetch;
    const manqueHorsFetch = !docsFaits || (estLiberal && !mandatFait) || !paiementFait;
    const visible = !!soignant && prochaineEtape !== null && (extraResolu || manqueHorsFetch);

    return { visible, etapes, nbFaites, prochaineEtape };
  }, [soignant, docsFaits, extra, docsRestants, besoinFetch, hasStripeConnect, aRib]);
}

/* ─── Anneau de progression ──────────────────────────────────────────────── */

function AnneauProgression({ valeur, max }: { valeur: number; max: number }) {
  const r = 17;
  const c = 2 * Math.PI * r;
  const pct = max > 0 ? valeur / max : 0;
  return (
    <svg width="48" height="48" viewBox="0 0 48 48" aria-hidden="true" className="shrink-0">
      <circle cx="24" cy="24" r={r} fill="none" strokeWidth="4" className="stroke-muted" />
      <circle
        cx="24" cy="24" r={r} fill="none" strokeWidth="4" strokeLinecap="round"
        stroke="hsl(var(--primary))"
        strokeDasharray={c}
        strokeDashoffset={c * (1 - pct)}
        transform="rotate(-90 24 24)"
        className="transition-all duration-500"
      />
      <text x="24" y="28" textAnchor="middle" className="fill-foreground font-bold" fontSize="12">
        {valeur}/{max}
      </text>
    </svg>
  );
}

/* ─── Composant ──────────────────────────────────────────────────────────── */

interface ChecklistActivationProps {
  state: ActivationState;
  className?: string;
}

export function ChecklistActivation({ state, className }: ChecklistActivationProps) {
  const navigate = useNavigate();

  if (!state.visible || !state.prochaineEtape) return null;

  const { etapes, nbFaites, prochaineEtape } = state;
  const restantes = etapes.length - nbFaites;

  // 9.2 — checklist compactée : anneau X/N + PROCHAINE étape seule (une ligne
  // cliquable, ≤ 96px). Les étapes déjà faites ne sont plus listées ; le détail
  // complet reste accessible en tapant sur l'étape (navigation existante).
  return (
    <button
      type="button"
      data-testid="checklist-activation"
      onClick={() => navigate(prochaineEtape.destination)}
      aria-label={`Active ton compte, ${nbFaites} sur ${etapes.length} — prochaine étape : ${prochaineEtape.label}`}
      className={cn(
        'w-full flex items-center gap-3 text-left rounded-2xl border border-jolene-rose-200/60 bg-gradient-soft p-3',
        'transition-colors hover:bg-card/40',
        className,
      )}
    >
      <AnneauProgression valeur={nbFaites} max={etapes.length} />
      <span className="flex-1 min-w-0">
        <span className="block text-[11px] font-semibold uppercase tracking-wide text-primary">
          {restantes === 1 ? 'Dernière étape' : `Active ton compte · ${nbFaites}/${etapes.length}`}
        </span>
        <span className="block text-sm font-bold text-foreground truncate">{prochaineEtape.label}</span>
        {prochaineEtape.detail && (
          <span className="block text-xs text-muted-foreground truncate">{prochaineEtape.detail}</span>
        )}
      </span>
      <ChevronRight className="h-5 w-5 text-primary shrink-0" aria-hidden="true" />
    </button>
  );
}

export default ChecklistActivation;
