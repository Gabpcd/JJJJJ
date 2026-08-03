import React, { useState, useEffect, useRef, useCallback } from 'react';
import { capturerErreurSentry } from '@/lib/sentry';
import { logger } from '@/lib/logger';
import { usePageTitle } from '@/hooks/usePageTitle';
import { SkeletonDashboard } from '@/components/SkeletonCard';
import { FadeInView } from '@/components/FadeInView';
import { Link, useNavigate, useSearchParams } from 'react-router-dom';
import {
  CreditCard, Clock, CheckCircle, FileText, Loader2, Trophy, RefreshCw,
  Building2, AlertTriangle, Download, Banknote, Info, Eye, ChevronDown,
  Edit2, X, Scale, ChevronRight, ExternalLink, Landmark,
  AlertCircle, CheckCircle2, Lightbulb,
} from 'lucide-react';
import { LayoutApp } from '@/components/LayoutApp';
import { getChorusStatutBadge } from '@/lib/chorus-helpers';
import { EmptyState, IllustrationCalculatrice } from '@/components/ui/EmptyState';
import { BadgePalier } from '@/components/BadgePalier';
import { PaiementVirement } from '@/components/PaiementVirement';
import { StripeEmbeddedCheckout } from '@/components/StripeEmbeddedCheckout';
import { EmbeddedCheckoutProvider, EmbeddedCheckout } from '@stripe/react-stripe-js';
import { stripePromise } from '@/lib/stripe';
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import {
  DialogResponsive,
  DialogResponsiveContent,
  DialogResponsiveHeader,
  DialogResponsiveTitle,
  DialogResponsiveDescription,
  DialogResponsiveBody,
  DialogResponsiveFooter,
} from '@/components/ui/DialogResponsive';
import { Collapsible, CollapsibleTrigger, CollapsibleContent } from '@/components/ui/collapsible';
import { BadgeY2K } from '@/components/y2k/BadgeY2K';
import { Button } from '@/components/ui/button';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Checkbox } from '@/components/ui/checkbox';
import {
  CardY2K,
  CardY2KHeader,
  CardY2KTitle,
  CardY2KContent,
} from '@/components/y2k/CardY2K';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { ENTREPRISE } from '@/constantes/entreprise';
import { useAuth } from '@/contexts/AuthContext';
import { useNotification } from '@/contexts/NotificationContext';
import { supabase } from '@/integrations/supabase/client';
import { extraireMessageErreur } from '@/lib/erreurs';
import { estFactureRelancable } from '@/lib/adminInvoiceAccounting';
import { payerMissionStripeConnectAvecGenerationAuto } from '@/lib/stripeMissionPay';
import { telechargerFactureCommissionPDF } from '@/lib/facture-commission-pdf';
import { telechargerFactureHonorairesPDF } from '@/lib/facture-honoraires-pdf';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import { toast } from 'sonner';
import { useEtablissementScope } from '@/hooks/useEtablissementScope';
import { useEtabPermissions } from '@/hooks/useEtabPermissions';

const fmt = (v: number | null | undefined) =>
  v != null ? new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(v) : '—';

const formatDateMetier = (value: unknown): string | null => {
  if (typeof value !== 'string' || value.length === 0) return null;
  const jourIso = value.match(/^\d{4}-\d{2}-\d{2}/)?.[0];
  const date = jourIso ? new Date(`${jourIso}T12:00:00`) : new Date(value);
  if (Number.isNaN(date.getTime())) return null;
  return format(date, 'd MMMM yyyy', { locale: fr });
};

type MethodePaiement = 'VIREMENT' | 'CHEQUE' | 'BULLETIN_PAIE' | 'NOTE_HONORAIRES';

const isRefValid = (ref: string) => {
  const t = ref.trim();
  return t.length >= 6 && /\d{2,}/.test(t) && /[A-Za-z]/.test(t);
};

type ReponseChargement = {
  data: unknown;
  error: unknown;
};

const estObjet = (value: unknown): value is Record<string, unknown> =>
  value !== null && typeof value === 'object' && !Array.isArray(value);
const estTableau = (value: unknown) => Array.isArray(value);

function verifierReponseChargement(
  nom: string,
  response: ReponseChargement,
  formatValide: (data: unknown) => boolean,
) {
  if (response.error) {
    const message = estObjet(response.error) && 'message' in response.error
      ? String(response.error.message)
      : String(response.error);
    throw new Error(`${nom}: ${message}`);
  }

  const payloadError = estObjet(response.data) && 'error' in response.data
    ? response.data.error
    : null;
  if (payloadError) {
    throw new Error(`${nom}: ${String(payloadError)}`);
  }
  if (!formatValide(response.data)) {
    throw new Error(`${nom}: réponse incomplète ou invalide`);
  }
}

const METHODE_LABELS: Record<MethodePaiement, string> = {
  VIREMENT: 'Virement bancaire',
  CHEQUE: 'Chèque',
  BULLETIN_PAIE: 'Virement de salaire (bulletin employeur)',
  NOTE_HONORAIRES: 'Note d\'honoraires',
};

// ─── Helpers cards missions ───
// Lot 11 : sévérité graduée par ancienneté du dû. Un dû récent (< 7 j) est un
// état NORMAL → badge neutre (muted), jamais rouge. Le rouge est réservé au
// vrai retard (> 14 j).
function RetardBadge({ jours }: { jours: number }) {
  if (jours == null || Number.isNaN(jours)) return null;
  if (jours < 7) {
    return (
      <BadgeY2K variant="info" className="bg-muted text-muted-foreground border-border" icone={<Clock className="h-3 w-3" />}>
        {jours}j
      </BadgeY2K>
    );
  }
  if (jours <= 14) {
    return <BadgeY2K variant="warning" icone={<Clock className="h-3 w-3" />}>{jours}j de retard</BadgeY2K>;
  }
  return <BadgeY2K variant="error" icone={<AlertCircle className="h-3 w-3" />}>En retard de {jours} j</BadgeY2K>;
}

// Section IDs pour navigation rapide
const SECTIONS = {
  payer: 'section-a-payer',
  attente: 'section-attente',
  commissions: 'section-commissions',
  historique: 'section-historique',
  exports: 'section-exports',
} as const;

function scrollTo(id: string) {
  document.getElementById(id)?.scrollIntoView({ behavior: 'smooth', block: 'start' });
}

export default function FacturationEtablissement() {
  usePageTitle('Facturation');
  const {
    user,
    etablissementId,
    loading: scopeLoading,
    resolved: scopeResolved,
    error: scopeError,
    retry: retryScope,
  } = useEtablissementScope();
  const { afficherNotification } = useNotification();
  const navigate = useNavigate();
  const [searchParams, setSearchParams] = useSearchParams();
  const permissionCheckEnabled = Boolean(
    !scopeLoading && scopeResolved && !scopeError && user && etablissementId,
  );
  const {
    loading: permissionsLoading,
    permissions,
    error: permissionsError,
    recharger: rechargerPermissions,
  } = useEtabPermissions(etablissementId ?? undefined, permissionCheckEnabled);
  const canReadFinance = permissions.lecture_paiement || permissions.paiement;
  const canManagePayments = permissions.paiement;
  // Session F (F7) : l'onglet « Obligations » a été retiré car il dupliquait à
  // l'identique le contenu de cette page (même RPC fn_obligations_financieres,
  // mêmes missions à payer / commissions, actions renvoyant vers ces sections).
  // Les anciens deep-links ?tab=obligations / ?tab=commissions / ?tab=missions-a-payer
  // ouvrent et défilent désormais vers la section correspondante (cf. effet plus bas).

  // ── Data ──
  const [loading, setLoading] = useState(true);
  const [etab, setEtab] = useState<any>(null);
  const [data, setData] = useState<any>(null);        // fn_obligations_financieres
  const [paiementsData, setPaiementsData] = useState<any>(null); // fn_paiements_etablissement
  const [factures, setFactures] = useState<any[]>([]); // fn_mes_factures
  const [missionsNonFacturees, setMissionsNonFacturees] = useState<any[]>([]);
  const [prelevements, setPrelevements] = useState<any[]>([]);
  const [missionsPaidByStripe, setMissionsPaidByStripe] = useState<Set<string>>(new Set());
  const [erreurChargement, setErreurChargement] = useState<string | null>(null);

  // ── UI state ──
  const [sectionsOpen, setSectionsOpen] = useState<Record<string, boolean>>({
    [SECTIONS.payer]: true,
    [SECTIONS.attente]: false,
    [SECTIONS.commissions]: false,
    [SECTIONS.historique]: false,
    [SECTIONS.exports]: false,
  });

  // Dialog states
  const [connectClientSecret, setConnectClientSecret] = useState<string | null>(null);
  const [connectDecomposition, setConnectDecomposition] = useState<any>(null);
  const [showConnectCheckout, setShowConnectCheckout] = useState(false);
  const [connectConfirming, setConnectConfirming] = useState(false);
  const [connectPaymentContext, setConnectPaymentContext] = useState<{
    missionId: string;
    factureHonoraireId?: string;
  } | null>(null);
  const [checkoutFactureId, setCheckoutFactureId] = useState<string | null>(null);
  const [showCheckout, setShowCheckout] = useState(false);
  const [declarerDialogMission, setDeclarerDialogMission] = useState<any>(null);
  const [declarerMontant, setDeclarerMontant] = useState<string>('');
  const [declarerMontantDu, setDeclarerMontantDu] = useState<string>('');
  const [declarerMethode, setDeclarerMethode] = useState<MethodePaiement>('VIREMENT');
  const [declarerReference, setDeclarerReference] = useState<string>('');
  const [declarerDatePaiement, setDeclarerDatePaiement] = useState<string>('');
  const [declarerAttestation, setDeclarerAttestation] = useState<boolean>(false);
  const [declaringId, setDeclaringId] = useState<string | null>(null);
  const [connectPayingId, setConnectPayingId] = useState<string | null>(null);
  const [generatingFacture, setGeneratingFacture] = useState(false);
  const [historiqueOuvert, setHistoriqueOuvert] = useState(false);

  // ── Responsive: detect mobile ──
  const isMobile = typeof window !== 'undefined' && window.innerWidth < 768;

  // Initialize sections: on desktop all open, on mobile only "à payer"
  useEffect(() => {
    if (!isMobile) {
      setSectionsOpen({
        [SECTIONS.payer]: true,
        [SECTIONS.attente]: true,
        [SECTIONS.commissions]: true,
        [SECTIONS.historique]: true,
        [SECTIONS.exports]: true,
      });
    }
  }, [isMobile]);

  // Deep-link ?tab= vers une section de l'onglet facturation : ouvre la section
  // ciblée puis scroll smooth (une fois les données chargées, sinon scrollIntoView
  // calcule une position incorrecte sur une section repliée). 'obligations' change
  // d'onglet (géré au-dessus) ; les autres valeurs ciblent une section.
  useEffect(() => {
    if (loading) return;
    const tab = searchParams.get('tab');
    const cibleSection: Record<string, string> = {
      'missions-a-payer': SECTIONS.payer,
      soignants: SECTIONS.payer,
      attente: SECTIONS.attente,
      commissions: SECTIONS.commissions,
      historique: SECTIONS.historique,
      exports: SECTIONS.exports,
    };
    const sectionId = tab ? cibleSection[tab] : undefined;
    if (!sectionId) return;
    setSectionsOpen(prev => ({ ...prev, [sectionId]: true }));
    const t = setTimeout(() => scrollTo(sectionId), 100);
    return () => clearTimeout(t);
  }, [loading, searchParams]);

  // ── Data loading ──
  const charger = useCallback(async () => {
    if (scopeLoading || !scopeResolved || scopeError || permissionsLoading) return;
    if (!user || !etablissementId) {
      setLoading(false);
      return;
    }
    if (!canReadFinance) {
      setEtab(null);
      setData(null);
      setPaiementsData(null);
      setFactures([]);
      setMissionsNonFacturees([]);
      setMissionsPaidByStripe(new Set());
      setPrelevements([]);
      setLoading(false);
      return;
    }
    setLoading(true);
    setErreurChargement(null);
    try {
      const [resEtab, resObligations, resPaiements, resFactures, resMNF, resTransfers, resPrelev] = await Promise.all([
        supabase.rpc('fn_mon_etablissement_complet' as any),
        supabase.rpc('fn_obligations_financieres' as any),
        supabase.rpc('fn_paiements_etablissement' as any),
        supabase.rpc('fn_mes_factures' as any),
        supabase.from('missions')
          .select('id, intitule, fin_le, montant_commission_ht, montant_commission_ttc')
          .eq('etablissement_id', etablissementId)
          .eq('statut', 'TERMINEE')
          .eq('commission_facturee', false)
          .order('fin_le', { ascending: false }),
        supabase.from('stripe_transfers')
          .select('mission_id, statut')
          .eq('etablissement_id', etablissementId)
          .in('statut', ['CHARGE_REUSSI', 'TRANSFERE', 'PAYE']),
        supabase.from('paiements_mission')
          .select('id, mission_id, montant_ttc, statut, capture_le, missions(intitule)')
          .eq('etablissement_id', etablissementId)
          .order('capture_le', { ascending: false })
          .limit(20),
      ]);

      // Valider l'ensemble avant le moindre rendu : une seule erreur transport,
      // RLS ou payload interdit d'afficher un agrégat financier partiel.
      verifierReponseChargement('Profil établissement', resEtab, estObjet);
      verifierReponseChargement('Obligations financières', resObligations, estObjet);
      verifierReponseChargement('Paiements établissement', resPaiements, estObjet);
      verifierReponseChargement('Factures', resFactures, estTableau);
      verifierReponseChargement('Missions non facturées', resMNF, estTableau);
      verifierReponseChargement('Transferts Stripe', resTransfers, estTableau);
      verifierReponseChargement('Prélèvements', resPrelev, estTableau);

      setEtab(resEtab.data);
      setData(resObligations.data);
      setPaiementsData(resPaiements.data);
      setFactures(resFactures.data as any[]);
      setMissionsNonFacturees(resMNF.data as any[]);
      setMissionsPaidByStripe(new Set((resTransfers.data as any[]).map((t: any) => t.mission_id)));
      setPrelevements(resPrelev.data as any[]);
    } catch (err) {
      logger.error('Facturation charger error', err);
      setEtab(null);
      setData(null);
      setPaiementsData(null);
      setFactures([]);
      setMissionsNonFacturees([]);
      setMissionsPaidByStripe(new Set());
      setPrelevements([]);
      setErreurChargement('Impossible de charger les données de facturation en toute sécurité.');
    } finally {
      setLoading(false);
    }
  }, [
    user,
    etablissementId,
    scopeLoading,
    scopeResolved,
    scopeError,
    permissionsLoading,
    canReadFinance,
  ]);

  useEffect(() => { void charger(); }, [charger]);

  // ── Handler : générer facture commission mensuelle ──
  const genererFactureMensuelle = async () => {
    if (!canManagePayments) {
      toast.error('Votre rôle ne permet pas de générer une facture.');
      return;
    }
    setGeneratingFacture(true);
    try {
      const { data, error } = await supabase.rpc('fn_generer_facture_rate_limited' as any);
      if (error) throw error;
      const res = data as any;
      if (res?.error) {
        toast.error(res.message || res.error);
      } else {
        toast.success('Facture commission générée');
        charger();
      }
    } catch (e: any) {
      toast.error(extraireMessageErreur(e));
    } finally {
      setGeneratingFacture(false);
    }
  };

  // ── Handlers dialogs paiement ──
  const ouvrirDialogDeclarer = (mission: any) => {
    if (!canManagePayments) return;
    setDeclarerDialogMission(mission);
    // Un montant salarié remonté par la plateforme reste une estimation
    // avant paie/PAS. Ne jamais le préremplir comme s'il s'agissait du net
    // officiel : l'employeur doit recopier le bulletin qu'il a établi.
    const montantInitial = mission.type_contrat_applique === 'SALARIE'
      ? ''
      : String(Number(mission.net_a_payer || 0).toFixed(2));
    setDeclarerMontant(montantInitial);
    setDeclarerMontantDu(mission.type_contrat_applique === 'SALARIE' ? '' : montantInitial);
    setDeclarerMethode('VIREMENT');
    setDeclarerReference('');
    setDeclarerDatePaiement(new Date().toISOString().split('T')[0]);
    setDeclarerAttestation(false);
  };

  const fermerDialogDeclarer = () => {
    setDeclarerDialogMission(null);
    setDeclarerMontant('');
    setDeclarerMontantDu('');
    setDeclaringId(null);
  };

  const validerDeclarationPaiement = async () => {
    if (!declarerDialogMission || !canManagePayments) return;
    const missionId = declarerDialogMission.mission_id;
    const montantNum = Number(declarerMontant);
    const estSalarie = declarerDialogMission.type_contrat_applique === 'SALARIE';
    const montantDuNum = estSalarie ? Number(declarerMontantDu) : montantNum;
    if (!montantNum || montantNum <= 0) {
      toast.error('Montant invalide');
      return;
    }
    if (!montantDuNum || montantDuNum <= 0) {
      toast.error('Indiquez le total net dû selon le bulletin officiel.');
      return;
    }
    if (estSalarie && Math.abs(montantNum - montantDuNum) > 0.005) {
      toast.error('Le montant versé doit correspondre exactement au total net dû. Les paiements partiels ne sont pas acceptés.');
      return;
    }
    const refRequired = declarerMethode !== 'BULLETIN_PAIE';
    if (refRequired && !isRefValid(declarerReference)) {
      toast.error('La référence doit contenir au moins 5 caractères dont un chiffre.');
      return;
    }
    if (!declarerAttestation) {
      toast.error('Vous devez cocher l\'attestation sur l\'honneur.');
      return;
    }

    const factureHonorairesId = declarerDialogMission.facture_honoraires_id || null;
    const declarationKey = factureHonorairesId || missionId;
    setDeclaringId(declarationKey);
    try {
      const { data, error } = factureHonorairesId
        ? await supabase.rpc('fn_declarer_paiement_facture_soignant' as any, {
            p_facture_honoraire_id: factureHonorairesId,
            p_montant: montantNum,
            p_methode: declarerMethode,
            p_reference: declarerReference.trim(),
            p_date_paiement: declarerDatePaiement,
            p_attestation_sur_l_honneur: true,
          })
        : estSalarie
          ? await supabase.rpc('fn_declarer_paiement_soignant_v2' as any, {
              p_mission_id: missionId,
              p_montant_verse: montantNum,
              p_montant_total_du: montantDuNum,
              p_methode: declarerMethode,
              p_reference: declarerReference.trim(),
              p_date_paiement: declarerDatePaiement,
              p_attestation_sur_l_honneur: true,
            })
          : await supabase.rpc('fn_declarer_paiement_soignant' as any, {
              p_mission_id: missionId,
              p_montant: montantNum,
              p_methode: declarerMethode,
              p_reference: declarerReference.trim(),
              p_date_paiement: declarerDatePaiement,
              p_attestation_sur_l_honneur: true,
            });
      if (error) throw error;
      const res = data as any;
      if (res?.error === 'ATTESTATION_REQUISE') {
        toast.error('Attestation sur l\'honneur obligatoire');
        return;
      }
      if (res?.error === 'use_stripe_connect') {
        toast.info('Ce soignant a Stripe Connect actif — utilisez le paiement Stripe');
        fermerDialogDeclarer();
        return;
      }
      if (res?.error) throw new Error(res.message || res.error);

      // Invoke send-email PAIEMENT_SOIGNANT_DECLARE (non-bloquant)
      try {
        await supabase.functions.invoke('send-email', {
          body: {
            type: 'PAIEMENT_SOIGNANT_DECLARE',
            destinataire_id: res.soignant_id,
            data: {
              soignant_prenom: declarerDialogMission.soignant_prenom || declarerDialogMission.soignant_nom?.split(' ')[0] || '',
              montant_formatte: montantNum.toFixed(2),
              montant_total_du_formatte: montantDuNum.toFixed(2),
              solde_restant_formatte: Math.max(montantDuNum - montantNum, 0).toFixed(2),
              methode: declarerMethode,
              methode_libelle: METHODE_LABELS[declarerMethode],
              reference_virement: declarerReference || '',
              date_paiement: declarerDatePaiement,
              date_paiement_fr: new Date(declarerDatePaiement).toLocaleDateString('fr-FR'),
              etablissement_nom: (data as any)?.etablissement_nom || '',
              mission_intitule: res.mission_intitule || declarerDialogMission.intitule || '',
              deep_link: '/soignant/mes-gains',
            },
          },
        });
      } catch (emailErr) {
        console.error('send-email PAIEMENT_SOIGNANT_DECLARE failed:', emailErr);
      }

      toast.success('Paiement déclaré — le soignant a été notifié pour confirmation');
      fermerDialogDeclarer();
      charger();
    } catch (e: any) {
      toast.error(extraireMessageErreur(e));
    } finally {
      setDeclaringId(null);
    }
  };

  const payerStripeConnect = async (missionId: string, factureHonoraireId?: string) => {
    if (!canManagePayments) {
      toast.error('Votre rôle ne permet pas d’effectuer un paiement.');
      return;
    }
    const paymentKey = factureHonoraireId || missionId;
    setConnectPayingId(paymentKey);
    const loadingToastId = toast.loading('Préparation du paiement…');
    try {
      const { data: sessionData } = await supabase.auth.getSession();
      const accessToken = sessionData?.session?.access_token;
      if (!accessToken) {
        toast.error('Session expirée, veuillez vous reconnecter', { id: loadingToastId });
        return;
      }

      const { result, error, code, message, factureGenereeAuto } =
        await payerMissionStripeConnectAvecGenerationAuto(
          missionId,
          accessToken,
          (msg) => toast.loading(msg, { id: loadingToastId }),
          factureHonoraireId,
        );

      if (code === 'CONTRAT_SALARIE_NON_STRIPE') {
        toast.error(message || 'Les missions salariées doivent être payées par virement SEPA selon le bulletin établi par l’employeur.', { id: loadingToastId, duration: 8000 });
        return;
      }

      if (result?.already_paid) {
        toast.info(result.message || 'Ce paiement a déjà été effectué', { id: loadingToastId });
        charger();
        return;
      }

      if (error || code) {
        toast.error(message || code || error?.message || 'Erreur lors du paiement', { id: loadingToastId });
        return;
      }

      toast.dismiss(loadingToastId);
      if (factureGenereeAuto) {
        toast.success('Facture honoraires générée automatiquement');
      }
      if (result?.url) { window.location.href = result.url; return; }
      if (result?.client_secret) {
        setConnectClientSecret(result.client_secret);
        setConnectPaymentContext({ missionId, factureHonoraireId });
        setShowConnectCheckout(true);
        setConnectDecomposition({
          commission_ttc: result.commission_ttc ?? result.commission,
          salaire_brut: result.salaire_brut ?? result.montant_soignant ?? result.soignant,
          total: result.total,
        });
        return;
      }
      toast.error('Aucune URL de paiement reçue');
    } catch (e: any) {
      toast.error(extraireMessageErreur(e), { id: loadingToastId });
    } finally {
      setConnectPayingId(null);
    }
  };

  const verifierStatutConnect = useCallback(async (
    missionId?: string,
    factureHonoraireId?: string,
  ): Promise<'CONFIRME' | 'ECHEC' | 'EN_ATTENTE'> => {
    if (!etablissementId || (!missionId && !factureHonoraireId)) return 'EN_ATTENTE';

    let requete = supabase
      .from('stripe_transfers')
      .select('statut')
      .eq('etablissement_id', etablissementId)
      .order('cree_le', { ascending: false })
      .limit(1);
    if (missionId) requete = requete.eq('mission_id', missionId);
    if (factureHonoraireId) requete = requete.eq('facture_honoraire_id', factureHonoraireId);

    const { data, error } = await requete.maybeSingle();
    if (error) throw error;
    const statut = data?.statut;
    if (statut && ['CHARGE_REUSSI', 'TRANSFERE', 'PAYE'].includes(statut)) return 'CONFIRME';
    if (statut === 'ECHOUE') return 'ECHEC';
    return 'EN_ATTENTE';
  }, [etablissementId]);

  const finaliserRetourConnect = useCallback(async (
    context?: { missionId?: string; factureHonoraireId?: string },
  ) => {
    setConnectConfirming(true);
    const delais = [0, 1000, 1500, 2000, 2500, 3000, 4000, 5000];
    try {
      if (!context?.missionId && !context?.factureHonoraireId) {
        toast.info('Retour Stripe reçu. Le paiement reste en attente tant que sa référence serveur ne peut pas être vérifiée.');
        await charger();
        return;
      }
      for (const delai of delais) {
        if (delai > 0) {
          await new Promise((resolve) => window.setTimeout(resolve, delai));
        }
        const statut = await verifierStatutConnect(context?.missionId, context?.factureHonoraireId);
        if (statut === 'CONFIRME') {
          toast.success('Paiement confirmé et enregistré.');
          await charger();
          return;
        }
        if (statut === 'ECHEC') {
          toast.error('Le paiement Stripe a échoué. Aucun paiement n’a été enregistré.');
          await charger();
          return;
        }
      }
      toast.info('Paiement transmis à Stripe. La confirmation est encore en cours ; la page sera actualisée automatiquement au prochain chargement.');
      await charger();
    } catch (error) {
      capturerErreurSentry(error, 'FacturationEtablissement', 'confirmation_stripe_connect');
      toast.error('Impossible de confirmer le paiement pour le moment. Son statut reste en attente, sans le déclarer payé.');
    } finally {
      setConnectConfirming(false);
      setShowConnectCheckout(false);
      setConnectClientSecret(null);
      setConnectPaymentContext(null);
    }
  }, [charger, verifierStatutConnect]);

  useEffect(() => {
    if (
      searchParams.get('paiement') !== 'succes'
      || !canReadFinance
      || permissionsLoading
      || !etablissementId
    ) return;

    const missionId = searchParams.get('mission') || undefined;
    const factureHonoraireId = searchParams.get('facture_honoraire') || undefined;
    const nettoyes = new URLSearchParams(searchParams);
    nettoyes.delete('paiement');
    nettoyes.delete('mission');
    nettoyes.delete('facture_honoraire');
    setSearchParams(nettoyes, { replace: true });
    void finaliserRetourConnect({ missionId, factureHonoraireId });
  }, [
    canReadFinance,
    etablissementId,
    finaliserRetourConnect,
    permissionsLoading,
    searchParams,
    setSearchParams,
  ]);

  const erreurScope = scopeError
    ? 'Impossible de vérifier votre établissement pour le moment.'
    : scopeResolved && (!user || !etablissementId)
      ? 'Aucun établissement autorisé n’est associé à cette session.'
      : null;

  const reessayerChargement = () => {
    if (scopeError || !scopeResolved || !user || !etablissementId) {
      retryScope();
      return;
    }
    if (permissionsError || !canReadFinance) {
      void rechargerPermissions();
      return;
    }
    void charger();
  };

  // ── Loading / erreur fail-closed ──
  if (scopeLoading || (!scopeResolved && !scopeError) || (permissionCheckEnabled && permissionsLoading)) {
    return <LayoutApp role="ADMIN_ETABLISSEMENT"><SkeletonDashboard /></LayoutApp>;
  }

  if (erreurScope) {
    return (
      <LayoutApp role="ADMIN_ETABLISSEMENT">
        <div className="card-base max-w-xl mx-auto text-center space-y-4" role="alert" aria-live="assertive">
          <AlertTriangle className="h-10 w-10 text-destructive mx-auto" aria-hidden="true" />
          <div>
            <h1 className="text-xl font-bold text-foreground">Facturation indisponible</h1>
            <p className="text-sm text-muted-foreground mt-1">{erreurScope}</p>
          </div>
          <Button type="button" onClick={reessayerChargement}>
            <RefreshCw className="h-4 w-4 mr-2" aria-hidden="true" />
            Réessayer
          </Button>
        </div>
      </LayoutApp>
    );
  }

  if (permissionsError || !canReadFinance) {
    return (
      <LayoutApp role="ADMIN_ETABLISSEMENT">
        <div className="card-base max-w-xl mx-auto text-center space-y-4" role="alert" aria-live="assertive">
          <AlertTriangle className="h-10 w-10 text-destructive mx-auto" aria-hidden="true" />
          <div>
            <h1 className="text-xl font-bold text-foreground">Accès à la facturation refusé</h1>
            <p className="text-sm text-muted-foreground mt-1">
              Votre rôle ne dispose pas de la permission de lecture des paiements de cet établissement.
            </p>
          </div>
          {permissionsError && (
            <Button type="button" onClick={() => void rechargerPermissions()}>
              <RefreshCw className="h-4 w-4 mr-2" aria-hidden="true" />
              Réessayer
            </Button>
          )}
        </div>
      </LayoutApp>
    );
  }

  if (loading) return <LayoutApp role="ADMIN_ETABLISSEMENT"><SkeletonDashboard /></LayoutApp>;

  if (erreurChargement) {
    return (
      <LayoutApp role="ADMIN_ETABLISSEMENT">
        <div className="card-base max-w-xl mx-auto text-center space-y-4" role="alert" aria-live="assertive">
          <AlertTriangle className="h-10 w-10 text-destructive mx-auto" aria-hidden="true" />
          <div>
            <h1 className="text-xl font-bold text-foreground">Facturation indisponible</h1>
            <p className="text-sm text-muted-foreground mt-1">{erreurChargement}</p>
          </div>
          <Button type="button" onClick={reessayerChargement}>
            <RefreshCw className="h-4 w-4 mr-2" aria-hidden="true" />
            Réessayer
          </Button>
        </div>
      </LayoutApp>
    );
  }

  // Derived data
  const missionsNonPayees = data?.missions_non_payees || [];
  const paiementsEnAttente = data?.paiements_soignants_en_attente || [];
  const paiementsConfirmes = data?.paiements_soignants_confirmes || [];
  // Le RPC conserve sa clé historique `factures_impayees`, mais la liste
  // contient aussi des factures non échues et des virements déjà déclarés.
  // L'interface les présente donc comme des dossiers ouverts et qualifie
  // chaque état individuellement, sans appeler une facture future « impayée ».
  const facturesCommissionOuvertes = data?.factures_impayees || [];
  const facturesCommissionARegler = facturesCommissionOuvertes.filter(
    (facture: any) => facture.statut === 'EMISE' || facture.statut === 'EN_RETARD',
  );
  const detailsFacturesCommission = new Map<string, any>(
    factures.map((facture: any) => [facture.id, facture]),
  );
  const facturesCommissionHistorique = data?.factures_commission_historique || [];
  const nbFacturesHistorique = data?.nb_factures_commission_historique || 0;
  const missionsNonFactureesObligs = data?.missions_non_facturees || [];
  const contientMissionSalarieeNonPayee = missionsNonPayees.some(
    (mission: any) => mission.type_contrat_applique === 'SALARIE',
  );

  const toggleSection = (id: string) =>
    setSectionsOpen(prev => ({ ...prev, [id]: !prev[id] }));

  /**
   * Ouvre l'accordéon cible puis scroll smooth.
   * Timeout pour laisser React render l'accordéon avant que scrollIntoView
   * calcule la position (sinon saut incorrect si section initialement fermée).
   */
  const openAndScrollTo = (id: string) => {
    setSectionsOpen(prev => ({ ...prev, [id]: true }));
    setTimeout(() => scrollTo(id), 50);
  };

  return (
    <LayoutApp role="ADMIN_ETABLISSEMENT">
      {/* ── HEADER : titre + badge palier ── */}
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between mb-6 gap-3">
        <div>
          <h1 className="text-xl font-bold text-foreground flex items-center gap-2">
            <CreditCard className="h-6 w-6 text-primary" /> Facturation
          </h1>
          <p className="text-sm text-muted-foreground mt-1">Paiements soignants, commissions Jolene et exports comptables</p>
        </div>
        <div className="flex items-center gap-2 flex-wrap">
          {etab?.paliers_commission && (
            <BadgePalier palierNom={etab.paliers_commission.nom || 'Standard'} taux={etab.taux_commission_negocie ?? 15} />
          )}
          {etab?.est_secteur_public && (
            <BadgeY2K variant="info" icone={<Landmark className="h-3 w-3" />}>Secteur public</BadgeY2K>
          )}
        </div>
      </div>

      {/* Session F (F7) : onglet « Obligations » retiré — cette page consolide déjà
          toutes les obligations financières (missions à payer, commissions, historique). */}
      {/* ── SECTION 0 : État vide si rien à payer ── */}
      {data && data.total_du === 0 && missionsNonPayees.length === 0 && facturesCommissionOuvertes.length === 0 && (
        <FadeInView>
          <div className="card-base p-8 text-center mb-6">
            <CheckCircle className="h-12 w-12 text-success mx-auto mb-3" />
            <p className="text-lg font-semibold text-foreground">Tout est à jour <CheckCircle2 className="inline-block h-5 w-5 text-success align-text-bottom" aria-hidden="true" /></p>
            <p className="text-sm text-muted-foreground mt-1">Aucune obligation financière en cours</p>
          </div>
        </FadeInView>
      )}

      {/* ── SECTION 1 : KPIs toujours visibles ── */}
      <FadeInView>
        <div className="grid grid-cols-1 sm:grid-cols-3 gap-3 mb-6">
          {/* KPI "Total à régler" — informatif uniquement (somme des 2 autres) */}
          <div className="card-base border-destructive/20">
            <p className="text-2xl font-bold text-foreground">{fmt(data?.total_du)}</p>
            <p className="text-xs text-muted-foreground">
              {contientMissionSalarieeNonPayee ? 'Total indicatif à régler' : 'Total à régler'}
            </p>
            {contientMissionSalarieeNonPayee && (
              <p className="text-[10px] text-muted-foreground mt-1">Inclut des estimations salariées avant paie et PAS.</p>
            )}
          </div>

          {/* KPI "Soignants" — cliquable → section Missions à payer */}
          <button
            type="button"
            onClick={() => openAndScrollTo(SECTIONS.payer)}
            className="card-base text-left cursor-pointer hover:shadow-md transition-shadow flex items-start justify-between gap-2"
          >
            <div>
              <p className="text-2xl font-bold text-foreground">{fmt(data?.total_soignants_du)}</p>
              <p className="text-xs text-muted-foreground">Soignants à régler · {data?.nb_missions_non_payees || 0} mission{(data?.nb_missions_non_payees || 0) > 1 ? 's' : ''}</p>
              {contientMissionSalarieeNonPayee && (
                <p className="text-[10px] text-muted-foreground mt-1">Salariés : estimation avant paie/PAS, à confirmer sur le bulletin employeur.</p>
              )}
            </div>
            <ChevronRight className="h-4 w-4 text-muted-foreground/60 shrink-0 mt-1" />
          </button>

          {/* KPI "Commissions" — cliquable → section Commissions Jolene */}
          <button
            type="button"
            onClick={() => openAndScrollTo(SECTIONS.commissions)}
            className="card-base text-left cursor-pointer hover:shadow-md transition-shadow flex items-start justify-between gap-2"
          >
            <div>
              <p className="text-2xl font-bold text-foreground">{fmt(data?.total_commissions_du)}</p>
              <p className="text-xs text-muted-foreground">Commissions Jolene · {facturesCommissionARegler.length} facture{facturesCommissionARegler.length > 1 ? 's' : ''} à régler</p>
            </div>
            <ChevronRight className="h-4 w-4 text-muted-foreground/60 shrink-0 mt-1" />
          </button>
        </div>
      </FadeInView>

      {/* ── MOBILE NAV : barre navigation rapide (mobile only) ── */}
      <div className="flex gap-2 overflow-x-auto pb-2 mb-4 md:hidden">
        {[
          { id: SECTIONS.payer, label: 'À payer', count: missionsNonPayees.length },
          { id: SECTIONS.attente, label: 'En attente', count: paiementsEnAttente.length },
          { id: SECTIONS.commissions, label: 'Commissions', count: facturesCommissionOuvertes.length },
          { id: SECTIONS.historique, label: 'Historique', count: paiementsConfirmes.length },
          { id: SECTIONS.exports, label: 'Exports', count: 0 },
        ].map(s => (
          <button
            key={s.id}
            onClick={() => openAndScrollTo(s.id)}
            className="shrink-0 px-3 py-1.5 rounded-full text-xs font-medium bg-muted text-muted-foreground hover:bg-primary/10 hover:text-primary transition-colors"
          >
            {s.label}{s.count > 0 && ` (${s.count})`}
          </button>
        ))}
      </div>

      {/* ── SECTION 2 : Missions à payer aux soignants ── */}
      <div id={SECTIONS.payer} className="mb-4">
        <Collapsible open={sectionsOpen[SECTIONS.payer]} onOpenChange={() => toggleSection(SECTIONS.payer)}>
          <CollapsibleTrigger className="w-full">
            {/* Lot 11 : dé-emphase de l'en-tête quand la section est vide */}
            <CardY2K noPadding className={missionsNonPayees.length === 0 ? 'opacity-60' : undefined}>
              <CardY2KHeader className="py-3">
                <div className="flex items-center justify-between">
                  <CardY2KTitle className="flex items-center gap-2 text-base">
                    <AlertTriangle className="h-5 w-5 text-destructive" />
                    Échéances à payer aux soignants ({missionsNonPayees.length})
                  </CardY2KTitle>
                  <ChevronDown className={`h-5 w-5 text-muted-foreground transition-transform ${sectionsOpen[SECTIONS.payer] ? 'rotate-180' : ''}`} />
                </div>
              </CardY2KHeader>
            </CardY2K>
          </CollapsibleTrigger>
          <CollapsibleContent>
            <div className="mt-2 space-y-3">
              {missionsNonPayees.length === 0 ? (
                <CardY2K noPadding>
                  <CardY2KContent className="py-6 text-center text-sm text-muted-foreground">
                    Aucune échéance en attente de paiement soignant.
                  </CardY2KContent>
                </CardY2K>
              ) : (
                missionsNonPayees.map((m: any) => {
                  const typeContratMission = m.type_contrat_applique as 'SALARIE' | 'LIBERAL' | null | undefined;
                  const isSalarie = typeContratMission === 'SALARIE';
                  const isLiberal = typeContratMission === 'LIBERAL';
                  const modePaiementLabel = isSalarie
                    ? 'Virement SEPA selon bulletin employeur'
                    : isLiberal
                    ? (m.soignant_stripe_connect ? 'Note d\'honoraires (Stripe Connect)' : 'Note d\'honoraires (virement)')
                    : null;
                  const peutPayerStripeBase = isLiberal && m.soignant_stripe_connect;
                  const enLitige = Boolean(m.a_paiement_conteste);
                  const peutPayerStripe = peutPayerStripeBase && !enLitige;
                  return (
                    <div key={m.payment_key || m.facture_honoraires_id || m.mission_id} className="card-base space-y-3">
                      <div className="flex items-start justify-between gap-3">
                        <div className="flex-1 min-w-0">
                          <div className="flex items-center gap-2 flex-wrap">
                            <button onClick={() => navigate(`/etablissement/missions/${m.mission_id}`)} className="font-semibold text-sm text-primary hover:underline text-left">
                              {m.intitule}
                            </button>
                            {m.soignant_id ? (
                              <button onClick={() => navigate(`/etablissement/soignants/${m.soignant_id}`)} className="text-xs text-muted-foreground hover:text-primary hover:underline text-left">
                                {m.soignant_nom}
                              </button>
                            ) : (
                              <span className="text-xs text-muted-foreground">{m.soignant_nom}</span>
                            )}
                            {/* Lot 14 (bug documenté Lot 11) : le chip régime affichait le
                                type_exercice du PROFIL soignant — contradictoire avec le
                                contrat de la MISSION (chip « Contrat … » ci-dessous, seul
                                à faire foi via type_contrat_applique). On n'affiche JAMAIS
                                le régime du profil sur une ligne de facturation. */}
                            <RetardBadge jours={m.jours_depuis_fin} />
                          </div>
                          <p className="text-xs text-muted-foreground mt-1">
                            {m.soignant_profession} · {Math.round(m.heures || 0)}h pointées
                          </p>
                          <p className="text-xs text-muted-foreground">
                            {(m.periode_debut || m.debut_le) && new Date(m.periode_debut || m.debut_le).toLocaleDateString('fr-FR')} → {(m.periode_fin || m.fin_le) && new Date(m.periode_fin || m.fin_le).toLocaleDateString('fr-FR')}
                          </p>
                          {m.facture_honoraires_id && !m.est_facture_finale_mission && (
                            <p className="mt-1 text-xs font-medium text-primary">Paiement hebdomadaire — période close</p>
                          )}
                          {typeContratMission && (
                            <div className="flex items-center gap-2 mt-2 flex-wrap">
                              <BadgeY2K variant="info" className={isSalarie
                                ? 'bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-400'
                                : 'bg-emerald-100 text-emerald-700 dark:bg-emerald-900/30 dark:text-emerald-400'}
                              >
                                Contrat {isSalarie ? 'salarié (CDD)' : 'libéral'}
                              </BadgeY2K>
                              {modePaiementLabel && (
                                <span className="text-xs text-muted-foreground">→ {modePaiementLabel}</span>
                              )}
                            </div>
                          )}
                          {enLitige && (
                            <div className="mt-2 flex items-center gap-2 flex-wrap rounded-md border border-destructive/40 bg-destructive/10 px-3 py-2">
                              <Scale className="h-4 w-4 text-destructive shrink-0" />
                              <div className="flex-1 min-w-0">
                                <p className="text-sm font-semibold text-destructive"><AlertTriangle className="inline-block h-4 w-4 mr-1 align-text-bottom" aria-hidden="true" />Litige en cours sur un paiement</p>
                                <p className="text-xs text-destructive/80">
                                  Les paiements sont désactivés tant que le litige n'est pas résolu.
                                </p>
                              </div>
                              <button
                                onClick={() => navigate(`/etablissement/missions/${m.mission_id}`)}
                                className="text-xs font-medium text-destructive hover:underline shrink-0"
                              >
                                Voir le litige →
                              </button>
                            </div>
                          )}
                        </div>
                        <div className="text-right shrink-0">
                          {peutPayerStripe ? (
                            <>
                              <p className="font-bold">{fmt((m.net_a_payer || 0) + (m.montant_commission_ttc || 0))}</p>
                              {m.montant_commission_ttc > 0 && (
                                <p className="text-[10px] text-muted-foreground">
                                  dont {fmt(m.montant_commission_ttc)} commission Jolene
                                </p>
                              )}
                            </>
                          ) : isSalarie ? (
                            <div>
                              <p className="font-bold">{fmt(m.net_estime ?? m.net_a_payer)}</p>
                              <p className="text-[10px] text-muted-foreground max-w-[12rem]">
                                Estimation avant paie/PAS — le bulletin employeur fait foi
                              </p>
                            </div>
                          ) : (
                            <p className="font-bold">{fmt(m.net_a_payer)}</p>
                          )}
                        </div>
                      </div>

                      {!canManagePayments ? (
                        <p className="text-xs text-muted-foreground text-center py-1">
                          Consultation uniquement — votre rôle ne permet pas d’effectuer un paiement.
                        </p>
                      ) : peutPayerStripe ? (
                        <BoutonY2K
                          size="sm"
                          onClick={() => payerStripeConnect(m.mission_id, m.facture_honoraires_id)}
                          disabled={connectPayingId === (m.facture_honoraires_id || m.mission_id) || enLitige}
                          className="w-full"
                        >
                          <CreditCard className="w-4 h-4 mr-2" />
                          {connectPayingId === (m.facture_honoraires_id || m.mission_id) ? 'Préparation…' : 'Payer via Stripe'}
                        </BoutonY2K>
                      ) : (
                        <BoutonY2K
                          size="sm"
                          onClick={() => ouvrirDialogDeclarer(m)}
                          disabled={declaringId === (m.facture_honoraires_id || m.mission_id) || enLitige}
                          className="w-full"
                        >
                          <Banknote className="w-4 h-4 mr-2" />
                          {enLitige ? 'Paiement bloqué (litige)' : 'Déclarer un paiement'}
                        </BoutonY2K>
                      )}
                    </div>
                  );
                })
              )}
            </div>
          </CollapsibleContent>
        </Collapsible>
      </div>

      {/* ── SECTION 3 : Paiements en attente de confirmation ── */}
      <div id={SECTIONS.attente} className="mb-4">
        <Collapsible open={sectionsOpen[SECTIONS.attente]} onOpenChange={() => toggleSection(SECTIONS.attente)}>
          <CollapsibleTrigger className="w-full">
            <CardY2K noPadding className={paiementsEnAttente.length === 0 ? 'opacity-60' : undefined}>
              <CardY2KHeader className="py-3">
                <div className="flex items-center justify-between">
                  <CardY2KTitle className="flex items-center gap-2 text-base">
                    <Clock className="h-5 w-5 text-warning" />
                    Paiements en attente ({paiementsEnAttente.length})
                  </CardY2KTitle>
                  <ChevronDown className={`h-5 w-5 text-muted-foreground transition-transform ${sectionsOpen[SECTIONS.attente] ? 'rotate-180' : ''}`} />
                </div>
              </CardY2KHeader>
            </CardY2K>
          </CollapsibleTrigger>
          <CollapsibleContent>
            <div className="mt-2 space-y-3">
              {paiementsEnAttente.length === 0 ? (
                <CardY2K noPadding>
                  <CardY2KContent className="py-6 text-center text-sm text-muted-foreground">
                    Aucun paiement en attente de confirmation soignant.
                  </CardY2KContent>
                </CardY2K>
              ) : (
                paiementsEnAttente.map((p: any) => (
                  <button
                    type="button"
                    key={p.paiement_id}
                    onClick={() => navigate(`/etablissement/missions/${p.mission_id}`)}
                    className="w-full flex items-center justify-between gap-3 p-3 rounded-lg border hover:border-primary/50 hover:bg-muted/30 transition-colors cursor-pointer text-left"
                  >
                    <div className="min-w-0 flex-1">
                      <p className="font-medium text-sm text-primary">{p.mission_intitule}</p>
                      <p className="text-xs text-muted-foreground">
                        {p.soignant_nom} · {p.soignant_profession} · {p.methode} · Réf : {p.reference_virement}
                      </p>
                      <p className="text-xs text-muted-foreground">
                        Déclaré le {p.date_paiement && new Date(p.date_paiement).toLocaleDateString('fr-FR')}
                      </p>
                      {p.montant_du_reference != null && (
                        <p className="text-xs text-muted-foreground">
                          Versé : {fmt(Number(p.montant_net))} sur {fmt(Number(p.montant_du_reference))}
                          {Number(p.solde_restant || 0) > 0 ? ` · Reste dû : ${fmt(Number(p.solde_restant))}` : ' · Soldé'}
                        </p>
                      )}
                    </div>
                    <div className="text-right shrink-0 flex items-center gap-2">
                      <div>
                        <p className="font-bold">{fmt(p.montant_net)}</p>
                        <BadgeY2K variant="warning">En attente</BadgeY2K>
                      </div>
                      <ChevronRight className="h-4 w-4 text-muted-foreground" />
                    </div>
                  </button>
                ))
              )}
            </div>
          </CollapsibleContent>
        </Collapsible>
      </div>

      {/* ── SECTION 4 : Commissions Jolene ── */}
      <div id={SECTIONS.commissions} className="mb-4">
        <Collapsible open={sectionsOpen[SECTIONS.commissions]} onOpenChange={() => toggleSection(SECTIONS.commissions)}>
          <CollapsibleTrigger className="w-full">
            <CardY2K noPadding className={facturesCommissionOuvertes.length === 0 ? 'opacity-60' : undefined}>
              <CardY2KHeader className="py-3">
                <div className="flex items-center justify-between">
                  <CardY2KTitle className="flex items-center gap-2 text-base">
                    <FileText className="h-5 w-5 text-primary" />
                    Commissions Jolene ({facturesCommissionOuvertes.length})
                  </CardY2KTitle>
                  <ChevronDown className={`h-5 w-5 text-muted-foreground transition-transform ${sectionsOpen[SECTIONS.commissions] ? 'rotate-180' : ''}`} />
                </div>
              </CardY2KHeader>
            </CardY2K>
          </CollapsibleTrigger>
          <CollapsibleContent>
            <div className="mt-2 space-y-4">
              {/* 4.1 — Factures Jolene à régler ou en cours de vérification */}
              {facturesCommissionOuvertes.length > 0 ? (
                <div>
                  <h3 className="text-sm font-semibold text-foreground mb-2 flex items-center gap-2">
                    <FileText className="h-4 w-4 text-primary" /> Factures et règlements en cours ({facturesCommissionOuvertes.length})
                  </h3>
                  <div className="space-y-2">
                    {facturesCommissionOuvertes.map((f: any) => {
                      const chorusBadge = f.est_secteur_public && f.chorus_pro_statut ? getChorusStatutBadge(f.chorus_pro_statut) : null;
                      const virementDeclare = f.statut === 'VIREMENT_DECLARE';
                      const estEnRetard = estFactureRelancable({
                        ...f,
                        type_document: 'FACTURE',
                      });
                      const echeanceLisible = formatDateMetier(f.date_echeance);
                      const factureComplete = detailsFacturesCommission.get(f.facture_id);
                      const periodeDebutLisible = formatDateMetier(factureComplete?.periode_debut);
                      const periodeFinLisible = formatDateMetier(factureComplete?.periode_fin);
                      return (
                      <div key={f.facture_id} className="p-4 rounded-lg border space-y-3">
                        <div className="flex items-center justify-between gap-3">
                          <div>
                            <div className="flex items-center gap-2 flex-wrap">
                              <p className="font-semibold text-sm">{f.numero_facture}</p>
                              {chorusBadge && (
                                <span className={`inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[10px] font-bold ${chorusBadge.classes}`}>
                                  <Landmark className="h-3 w-3" />
                                  {chorusBadge.label}
                                </span>
                              )}
                              {virementDeclare ? (
                                <BadgeY2K variant="info" icone={<Clock className="h-3 w-3" />}>
                                  Virement déclaré · vérification en cours
                                </BadgeY2K>
                              ) : estEnRetard ? (
                                <BadgeY2K variant="error" icone={<AlertTriangle className="h-3 w-3" />}>
                                  {echeanceLisible ? `En retard depuis le ${echeanceLisible}` : 'En retard'}
                                </BadgeY2K>
                              ) : (
                                <BadgeY2K variant="warning" icone={<Clock className="h-3 w-3" />}>
                                  {echeanceLisible ? `À régler avant le ${echeanceLisible}` : 'À régler'}
                                </BadgeY2K>
                              )}
                            </div>
                            <p className="text-xs text-muted-foreground">
                              {f.nombre_missions} mission{(f.nombre_missions ?? 0) > 1 ? 's' : ''}{echeanceLisible ? ` · Échéance : ${echeanceLisible}` : ''}
                              {f.est_secteur_public && f.chorus_pro_numero_flux && ` · Flux ${f.chorus_pro_numero_flux}`}
                            </p>
                            {periodeDebutLisible && periodeFinLisible && (
                              <p className="text-xs text-muted-foreground mt-1">
                                Période facturée : {periodeDebutLisible} → {periodeFinLisible}. Le montant correspond à cette période, pas nécessairement à toute la mission.
                              </p>
                            )}
                          </div>
                          <div className="text-right shrink-0">
                            <p className="font-bold">{fmt(f.montant_ttc)}</p>
                            <p className="text-[10px] text-muted-foreground">{fmt(f.montant_ht)} HT + {fmt(f.montant_tva)} TVA</p>
                          </div>
                        </div>
                        {f.est_secteur_public && (
                          <p className="text-[10px] text-primary flex items-center gap-1">
                            <Landmark className="h-3 w-3" />
                            Secteur public — paiement via Chorus Pro (30 à 60 jours après acceptation)
                          </p>
                        )}
                        {!f.est_secteur_public && (
                        <div className="flex gap-2 flex-wrap">
                          {canManagePayments && !virementDeclare && etab?.mode_paiement_commission !== 'SEPA_DEBIT' && (
                            <BoutonY2K
                              size="sm"
                              onClick={() => { setCheckoutFactureId(f.facture_id); setShowCheckout(true); }}
                            >
                              <CreditCard className="w-4 h-4 mr-1" /> Payer par carte
                            </BoutonY2K>
                          )}
                          {!virementDeclare && etab?.mode_paiement_commission === 'SEPA_DEBIT' && (
                            <p className="w-full text-xs text-muted-foreground">
                              Prélèvement SEPA automatique programmé — aucun paiement par carte requis.
                            </p>
                          )}
                          {canManagePayments && !virementDeclare && etab?.mode_paiement_commission !== 'SEPA_DEBIT' && (
                            <BoutonY2K
                              size="sm"
                              variant="secondary"
                              onClick={() => navigate(`/etablissement/facturation/${f.facture_id}`)}
                            >
                              <Banknote className="w-4 h-4 mr-1" /> Virement
                            </BoutonY2K>
                          )}
                          <BoutonY2K size="sm" variant="secondary" onClick={() => telechargerFactureCommissionPDF(f.facture_id)}>
                            <Download className="w-4 h-4 mr-1" /> PDF
                          </BoutonY2K>
                        </div>
                        )}
                        {f.est_secteur_public && (
                        <div className="flex gap-2 flex-wrap">
                          <BoutonY2K size="sm" variant="secondary" onClick={() => telechargerFactureCommissionPDF(f.facture_id)}>
                            <Download className="w-4 h-4 mr-1" /> PDF
                          </BoutonY2K>
                        </div>
                        )}
                      </div>
                      );
                    })}
                  </div>
                </div>
              ) : (
                <CardY2K noPadding>
                  <CardY2KContent className="py-6 text-center text-sm text-muted-foreground">
                    Aucune facture de commission à régler ou en cours.
                  </CardY2KContent>
                </CardY2K>
              )}
              {/* 4.2 — Historique factures commission (collapsible) */}
              {nbFacturesHistorique > 0 && (
                <div>
                  <button
                    type="button"
                    onClick={() => setHistoriqueOuvert(v => !v)}
                    className="w-full flex items-center justify-between text-left py-2"
                    aria-expanded={historiqueOuvert}
                  >
                    <h3 className="text-sm font-semibold text-foreground flex items-center gap-2">
                      <CheckCircle className="h-4 w-4 text-success" />
                      Historique factures commission ({nbFacturesHistorique} payée{nbFacturesHistorique > 1 ? 's' : ''})
                    </h3>
                    {historiqueOuvert ? <ChevronDown className="h-4 w-4 text-muted-foreground" /> : <ChevronRight className="h-4 w-4 text-muted-foreground" />}
                  </button>
                  {historiqueOuvert && (
                    <div className="mt-2">
                      {/* Desktop table */}
                      <div className="hidden md:block overflow-x-auto">
                        <table className="w-full text-sm">
                          <thead>
                            <tr className="border-b text-left text-muted-foreground">
                              <th className="pb-2 pr-3">Numéro</th>
                              <th className="pb-2 pr-3">Émise le</th>
                              <th className="pb-2 pr-3">Payée le</th>
                              <th className="pb-2 pr-3">Missions</th>
                              <th className="pb-2 pr-3">Montant</th>
                              <th className="pb-2 pr-3">Mode paiement</th>
                              <th className="pb-2 pr-3">Statut</th>
                              <th className="pb-2"></th>
                            </tr>
                          </thead>
                          <tbody>
                            {facturesCommissionHistorique.map((f: any) => {
                              const ModeIcone =
                                f.mode_paiement === 'STRIPE'
                                  ? CreditCard
                                  : f.mode_paiement === 'VIREMENT'
                                  ? Banknote
                                  : f.mode_paiement === 'CHORUS_PRO'
                                  ? Landmark
                                  : null;
                              const modeLabel =
                                f.mode_paiement === 'STRIPE' && f.stripe_payment_intent_id
                                  ? 'Stripe (à la source)'
                                  : f.mode_paiement === 'STRIPE'
                                  ? 'Stripe'
                                  : f.mode_paiement === 'VIREMENT'
                                  ? 'Virement'
                                  : f.mode_paiement === 'CHORUS_PRO'
                                  ? 'Chorus Pro'
                                  : '—';
                              return (
                                <tr
                                  key={f.facture_id}
                                  className="border-b last:border-0"
                                >
                                  <td className="py-2 pr-3 font-medium">
                                    <Link
                                      to={`/etablissement/facturation/${f.facture_id}`}
                                      className="text-primary hover:underline focus-visible:underline"
                                    >
                                      {f.numero_facture}
                                    </Link>
                                  </td>
                                  <td className="py-2 pr-3 text-xs">{f.date_emission && new Date(f.date_emission).toLocaleDateString('fr-FR')}</td>
                                  <td className="py-2 pr-3 text-xs">{f.date_paiement ? new Date(f.date_paiement).toLocaleDateString('fr-FR') : '—'}</td>
                                  <td className="py-2 pr-3 text-xs">{f.nombre_missions ?? '—'}</td>
                                  <td className="py-2 pr-3 font-medium">{fmt(f.montant_ttc)}</td>
                                  <td className="py-2 pr-3 text-xs">{ModeIcone && <ModeIcone className="inline-block h-3.5 w-3.5 mr-1 align-text-bottom" aria-hidden="true" />}{modeLabel}</td>
                                  <td className="py-2 pr-3">
                                    {f.statut === 'PAYEE' ? (
                                      <BadgeY2K variant="success">Payée</BadgeY2K>
                                    ) : (
                                      <BadgeY2K variant="info" className="bg-muted text-muted-foreground border-muted">{f.statut}</BadgeY2K>
                                    )}
                                  </td>
                                  <td className="py-2">
                                    <div className="flex items-center gap-1 justify-end">
                                      <Button
                                        size="icon"
                                        variant="ghost"
                                        className="h-9 w-9"
                                        title="Télécharger la facture PDF"
                                        onClick={() => telechargerFactureCommissionPDF(f.facture_id)}
                                      >
                                        <Download className="h-4 w-4 text-muted-foreground" />
                                      </Button>
                                      <ChevronRight className="h-4 w-4 text-muted-foreground" />
                                    </div>
                                  </td>
                                </tr>
                              );
                            })}
                          </tbody>
                        </table>
                      </div>
                      {/* Mobile cards */}
                      <div className="md:hidden space-y-2">
                        {facturesCommissionHistorique.map((f: any) => (
                          <div
                            key={f.facture_id}
                            className="rounded-lg border bg-card p-3"
                          >
                            <div className="flex items-center justify-between mb-2">
                              <Link
                                to={`/etablissement/facturation/${f.facture_id}`}
                                className="text-sm font-medium text-primary hover:underline focus-visible:underline"
                              >
                                {f.numero_facture}
                              </Link>
                              {f.statut === 'PAYEE' ? (
                                <BadgeY2K variant="success">Payée</BadgeY2K>
                              ) : (
                                <BadgeY2K variant="info" className="bg-muted text-muted-foreground border-muted">{f.statut}</BadgeY2K>
                              )}
                            </div>
                            <div className="flex items-center justify-between mb-2">
                              <span className="text-lg font-semibold">{fmt(f.montant_ttc)}</span>
                              <Button
                                size="icon"
                                variant="ghost"
                                className="h-9 w-9"
                                title="Télécharger la facture PDF"
                                onClick={() => telechargerFactureCommissionPDF(f.facture_id)}
                              >
                                <Download className="h-4 w-4 text-muted-foreground" />
                              </Button>
                            </div>
                            <div className="flex items-center gap-3 text-xs text-muted-foreground">
                              <span>{f.date_emission && new Date(f.date_emission).toLocaleDateString('fr-FR')}</span>
                              <span>{f.nombre_missions ?? '—'} mission{(f.nombre_missions ?? 0) > 1 ? 's' : ''}</span>
                            </div>
                          </div>
                        ))}
                      </div>
                      <p className="text-xs text-muted-foreground mt-3">
                        Affiche les 10 dernières factures payées.
                      </p>
                    </div>
                  )}
                </div>
              )}
              {/* 4.3 — Missions à regrouper sur une facture de commission */}
              {missionsNonFacturees.length > 0 && (
                <div className="pt-4 border-t border-border">
                  <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-2 mb-3">
                    <h3 className="text-sm font-semibold text-foreground flex items-center gap-2">
                      <Clock className="h-4 w-4 text-warning" />
                      Missions à facturer ({missionsNonFacturees.length})
                    </h3>
                    {canManagePayments && (
                      <BoutonY2K
                        size="sm"
                        onClick={genererFactureMensuelle}
                        disabled={generatingFacture}
                        className="gap-1.5"
                      >
                        {generatingFacture ? <Loader2 className="h-4 w-4 animate-spin" /> : <FileText className="h-4 w-4" />}
                        {generatingFacture ? 'Génération…' : 'Générer une facture groupée'}
                      </BoutonY2K>
                    )}
                  </div>
                  {/* Desktop table */}
                  <div className="hidden md:block overflow-x-auto">
                    <table className="w-full text-sm">
                      <thead>
                        <tr className="border-b text-left text-muted-foreground">
                          <th className="pb-2 pr-3">Fin</th>
                          <th className="pb-2 pr-3">Mission</th>
                          <th className="pb-2 pr-3 text-right">Commission HT</th>
                        </tr>
                      </thead>
                      <tbody>
                        {missionsNonFacturees.map((m: any) => (
                          <tr
                            key={m.id}
                            className="border-b last:border-0"
                          >
                            <td className="py-2 pr-3 text-xs">{m.fin_le && new Date(m.fin_le).toLocaleDateString('fr-FR')}</td>
                            <td className="py-2 pr-3">
                              <Link
                                to={`/etablissement/missions/${m.id}`}
                                className="text-primary hover:underline focus-visible:underline"
                              >
                                {m.intitule}
                              </Link>
                            </td>
                            <td className="py-2 pr-3 text-right font-medium">{fmt(m.montant_commission_ht)}</td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                  {/* Mobile cards */}
                  <div className="md:hidden space-y-2">
                    {missionsNonFacturees.map((m: any) => (
                      <Link
                        key={m.id}
                        to={`/etablissement/missions/${m.id}`}
                        className="block rounded-lg border bg-card p-3 active:bg-muted/40 transition-colors focus-visible:ring-2 focus-visible:ring-ring"
                      >
                        <div className="flex items-center justify-between mb-1">
                          <span className="text-sm font-medium text-primary">{m.intitule}</span>
                          <span className="text-sm font-semibold">{fmt(m.montant_commission_ht)}</span>
                        </div>
                        <p className="text-xs text-muted-foreground">
                          Fin : {m.fin_le && new Date(m.fin_le).toLocaleDateString('fr-FR')}
                        </p>
                      </Link>
                    ))}
                  </div>
                  <p className="text-xs text-muted-foreground mt-2">
                    Commissions non encore facturées à votre établissement. Le bouton génère une facture groupée
                    pour toutes les missions terminées sans facture (hors LIBERAL+Stripe qui sont facturées à la source).
                  </p>
                </div>
              )}
              {/* 4.4 — Bandeau SEPA + IBAN Jolene + Chorus Pro + Prélèvements SEPA */}

              {/* 4.4.a — Bandeau SEPA actif */}
              {etab?.mode_paiement_commission === 'SEPA_DEBIT' && (
                <div className="rounded-lg border border-info/30 bg-info/5 p-3 flex items-start gap-2">
                  <Info className="h-4 w-4 text-info shrink-0 mt-0.5" />
                  <div className="text-xs text-muted-foreground">
                    <p className="font-semibold text-info mb-0.5"><Banknote className="inline-block h-3.5 w-3.5 mr-1 align-text-bottom" aria-hidden="true" />Mandat SEPA actif</p>
                    <p>Les factures éligibles sont présentées au prélèvement sur le compte bancaire enregistré après leur émission, lors du prochain traitement automatique.</p>
                  </div>
                </div>
              )}

              {/* 4.4.b — Prélèvement automatique SEPA + IBAN Jolene (virements classiques) */}
              {etab?.mode_paiement_commission !== 'SEPA_DEBIT' && (
                <div className="space-y-3">
                  {/* CTA prélèvement automatique — pointe vers le mandat SEPA existant
                      (sélection « Prélèvement SEPA » dans Paramètres → Profil, qui affiche
                      SepaSetupSection → edge function setup-sepa). */}
                  <div className="rounded-lg border border-primary/30 bg-primary/5 p-4">
                    <div className="flex items-start gap-2 mb-3">
                      <Landmark className="h-5 w-5 text-primary shrink-0 mt-0.5" />
                      <div>
                        <p className="text-sm font-semibold text-foreground">Activez le prélèvement automatique</p>
                        <p className="text-xs text-muted-foreground mt-0.5">
                          Plus de virement à effectuer manuellement : les factures éligibles sont
                          présentées au prélèvement après leur émission, lors du prochain traitement automatique.
                        </p>
                      </div>
                    </div>
                    <BoutonY2K
                      size="sm"
                      className="w-full sm:w-auto"
                      onClick={() => navigate('/etablissement/parametres?tab=profil')}
                    >
                      <Landmark className="w-4 h-4 mr-2" /> Activer le prélèvement automatique
                    </BoutonY2K>
                  </div>

                  {/* IBAN Jolene (virement manuel) */}
                  <div className="rounded-lg border bg-muted/20 p-3">
                    <p className="text-sm font-semibold text-foreground flex items-center gap-2 mb-2">
                      <Building2 className="h-4 w-4 text-primary" /> Virement manuel — coordonnées bancaires Jolene
                    </p>
                    <div className="text-xs text-muted-foreground space-y-1 font-mono">
                      <p>IBAN : {ENTREPRISE.iban}</p>
                      <p>BIC : {ENTREPRISE.bic}</p>
                      <p className="text-[10px] text-muted-foreground/70 font-sans italic">
                        Référence obligatoire : numéro de la facture commission (ex: FACT-2026-04-0001)
                      </p>
                    </div>
                  </div>
                </div>
              )}

              {/* 4.4.c — Chorus Pro (si établissement secteur public) */}
              {etab?.est_secteur_public && (
                <div className="rounded-lg border border-primary/30 bg-primary/5 p-3 flex items-start gap-2">
                  <Building2 className="h-4 w-4 text-primary shrink-0 mt-0.5" />
                  <div className="text-xs text-muted-foreground">
                    <p className="font-semibold text-primary mb-0.5"><Landmark className="inline-block h-3.5 w-3.5 mr-1 align-text-bottom" aria-hidden="true" />Secteur public — Chorus Pro</p>
                    <p>Vos factures commission sont déposées sur Chorus Pro. Le paiement suit le cycle de mandatement habituel (30 à 60 jours).</p>
                    <button
                      onClick={() => navigate('/etablissement/chorus-config')}
                      className="mt-1 text-primary hover:underline font-medium"
                    >
                      Configurer Chorus Pro →
                    </button>
                  </div>
                </div>
              )}

              {/* 4.4.d — Historique prélèvements SEPA */}
              {etab?.mode_paiement_commission === 'SEPA_DEBIT' && prelevements.length > 0 && (
                <div className="pt-4 border-t border-border">
                  <h3 className="text-sm font-semibold text-foreground flex items-center gap-2 mb-2">
                    <Banknote className="h-4 w-4 text-info" />
                    Historique des prélèvements ({prelevements.length})
                  </h3>
                  {/* Desktop table */}
                  <div className="hidden md:block overflow-x-auto">
                    <table className="w-full text-sm">
                      <thead>
                        <tr className="border-b text-left text-muted-foreground">
                          <th className="pb-2 pr-3">Date</th>
                          <th className="pb-2 pr-3">Mission</th>
                          <th className="pb-2 pr-3 text-right">Montant</th>
                          <th className="pb-2 pr-3">Statut</th>
                        </tr>
                      </thead>
                      <tbody>
                        {prelevements.map((p: any) => (
                          <tr
                            key={p.id}
                            className="border-b last:border-0"
                          >
                            <td className="py-2 pr-3 text-xs">{p.capture_le && new Date(p.capture_le).toLocaleDateString('fr-FR')}</td>
                            <td className="py-2 pr-3">
                              {p.mission_id ? (
                                <Link
                                  to={`/etablissement/missions/${p.mission_id}`}
                                  className="text-primary hover:underline focus-visible:underline"
                                >
                                  {(p.missions as any)?.intitule || 'Voir la mission'}
                                </Link>
                              ) : (
                                <span>—</span>
                              )}
                            </td>
                            <td className="py-2 pr-3 text-right font-medium">{fmt(p.montant_ttc)}</td>
                            <td className="py-2 pr-3">
                              {p.statut === 'PRELEVE' ? (
                                <BadgeY2K variant="success">Prélevé</BadgeY2K>
                              ) : (
                                <BadgeY2K variant="info" className="bg-muted text-muted-foreground border-muted">{p.statut}</BadgeY2K>
                              )}
                            </td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                  {/* Mobile cards */}
                  <div className="md:hidden space-y-2">
                    {prelevements.map((p: any) => (
                      <div
                        key={p.id}
                        className="rounded-lg border bg-card p-3"
                      >
                        <div className="flex items-center justify-between mb-1">
                          {p.mission_id ? (
                            <Link
                              to={`/etablissement/missions/${p.mission_id}`}
                              className="text-sm font-medium text-primary hover:underline focus-visible:underline"
                            >
                              {(p.missions as any)?.intitule || 'Voir la mission'}
                            </Link>
                          ) : (
                            <span className="text-sm font-medium">—</span>
                          )}
                          {p.statut === 'PRELEVE' ? (
                            <BadgeY2K variant="success">Prélevé</BadgeY2K>
                          ) : (
                            <BadgeY2K variant="info" className="bg-muted text-muted-foreground border-muted">{p.statut}</BadgeY2K>
                          )}
                        </div>
                        <div className="flex items-center justify-between">
                          <span className="text-xs text-muted-foreground">{p.capture_le && new Date(p.capture_le).toLocaleDateString('fr-FR')}</span>
                          <span className="text-sm font-semibold">{fmt(p.montant_ttc)}</span>
                        </div>
                      </div>
                    ))}
                  </div>
                </div>
              )}
            </div>
          </CollapsibleContent>
        </Collapsible>
      </div>

      {/* ── SECTION 5 : Historique paiements confirmés ── */}
      <div id={SECTIONS.historique} className="mb-4">
        <Collapsible open={sectionsOpen[SECTIONS.historique]} onOpenChange={() => toggleSection(SECTIONS.historique)}>
          <CollapsibleTrigger className="w-full">
            <CardY2K noPadding className={paiementsConfirmes.length === 0 ? 'opacity-60' : undefined}>
              <CardY2KHeader className="py-3">
                <div className="flex items-center justify-between">
                  <CardY2KTitle className="flex items-center gap-2 text-base">
                    <CheckCircle className="h-5 w-5 text-success" />
                    Historique paiements ({paiementsConfirmes.length} confirmé{paiementsConfirmes.length > 1 ? 's' : ''})
                  </CardY2KTitle>
                  <ChevronDown className={`h-5 w-5 text-muted-foreground transition-transform ${sectionsOpen[SECTIONS.historique] ? 'rotate-180' : ''}`} />
                </div>
              </CardY2KHeader>
            </CardY2K>
          </CollapsibleTrigger>
          <CollapsibleContent>
            <div className="mt-2">
              {paiementsConfirmes.length === 0 ? (
                <CardY2K noPadding>
                  <CardY2KContent className="py-6 text-center text-sm text-muted-foreground">
                    Aucun paiement confirmé pour l'instant.
                  </CardY2KContent>
                </CardY2K>
              ) : (
                <CardY2K noPadding>
                  <CardY2KContent className="pt-4">
                    {/* Desktop table */}
                    <div className="hidden md:block overflow-x-auto">
                      <table className="w-full text-sm">
                        <thead>
                          <tr className="border-b text-left text-muted-foreground">
                            <th className="pb-2 pr-3">Date</th>
                            <th className="pb-2 pr-3">Soignant</th>
                            <th className="pb-2 pr-3">Mission</th>
                            <th className="pb-2 pr-3 text-right">Montant</th>
                            <th className="pb-2 pr-3">Réf.</th>
                            <th className="pb-2">Confirmé</th>
                            <th className="pb-2"></th>
                          </tr>
                        </thead>
                        <tbody>
                          {paiementsConfirmes.map((p: any) => (
                            <tr
                              key={p.paiement_id}
                              className="border-b last:border-0"
                            >
                              <td className="py-2 pr-3 text-xs">{p.confirme_par_soignant_le && new Date(p.confirme_par_soignant_le).toLocaleDateString('fr-FR')}</td>
                              <td className="py-2 pr-3">{p.soignant_nom}</td>
                              <td className="py-2 pr-3">
                                {p.mission_id ? (
                                  <Link
                                    to={`/etablissement/missions/${p.mission_id}`}
                                    className="text-primary hover:underline focus-visible:underline"
                                  >
                                    {p.mission_intitule}
                                  </Link>
                                ) : (
                                  <span>{p.mission_intitule}</span>
                                )}
                              </td>
                              <td className="py-2 pr-3 text-right font-medium">{fmt(p.montant_net)}</td>
                              <td className="py-2 pr-3 text-xs text-muted-foreground">{p.reference_virement}</td>
                              <td className="py-2"><BadgeY2K variant="success" aria-label="Confirmé"><CheckCircle2 className="h-3.5 w-3.5" aria-hidden="true" /></BadgeY2K></td>
                              <td className="py-2">
                                <div className="flex items-center gap-1 justify-end">
                                  {p.facture_honoraires_id && (
                                    <Button
                                      size="icon"
                                      variant="ghost"
                                      className="h-9 w-9"
                                      title="Télécharger la facture honoraires PDF"
                                      onClick={() => telechargerFactureHonorairesPDF(p.facture_honoraires_id)}
                                    >
                                      <Download className="h-4 w-4 text-muted-foreground" />
                                    </Button>
                                  )}
                                  <ChevronRight className="h-4 w-4 text-muted-foreground" />
                                </div>
                              </td>
                            </tr>
                          ))}
                        </tbody>
                      </table>
                    </div>
                    {/* Mobile cards */}
                    <div className="md:hidden space-y-2">
                      {paiementsConfirmes.map((p: any) => (
                        <div
                          key={p.paiement_id}
                          className="rounded-lg border bg-card p-3"
                        >
                          <div className="flex items-center justify-between mb-1">
                            <div className="min-w-0">
                              <p className="text-sm font-medium truncate" title={p.soignant_nom}>{p.soignant_nom}</p>
                              {p.mission_id ? (
                                <Link
                                  to={`/etablissement/missions/${p.mission_id}`}
                                  className="block text-xs text-primary truncate hover:underline focus-visible:underline"
                                  title={p.mission_intitule}
                                >
                                  {p.mission_intitule}
                                </Link>
                              ) : (
                                <p className="text-xs truncate" title={p.mission_intitule}>{p.mission_intitule}</p>
                              )}
                            </div>
                            <div className="flex items-center gap-2 shrink-0 ml-2">
                              <span className="text-sm font-semibold">{fmt(p.montant_net)}</span>
                              <BadgeY2K variant="success" aria-label="Confirmé"><CheckCircle2 className="h-3.5 w-3.5" aria-hidden="true" /></BadgeY2K>
                            </div>
                          </div>
                          <div className="flex items-center justify-between text-xs text-muted-foreground">
                            <div className="flex items-center gap-2">
                              <span>{p.confirme_par_soignant_le && new Date(p.confirme_par_soignant_le).toLocaleDateString('fr-FR')}</span>
                              {p.reference_virement && <span>{p.reference_virement}</span>}
                            </div>
                            {p.facture_honoraires_id && (
                              <Button
                                size="icon"
                                variant="ghost"
                                className="h-8 w-8"
                                title="Télécharger la facture honoraires PDF"
                                onClick={() => telechargerFactureHonorairesPDF(p.facture_honoraires_id)}
                              >
                                <Download className="h-4 w-4 text-muted-foreground" />
                              </Button>
                            )}
                          </div>
                        </div>
                      ))}
                    </div>
                    <p className="text-[11px] text-muted-foreground mt-3">
                      Les 10 derniers paiements confirmés par le soignant. Cliquez sur une ligne pour voir le détail mission.
                    </p>
                  </CardY2KContent>
                </CardY2K>
              )}
              {/* Note : les paiements CONTESTE ne sont pas exposés par fn_obligations_financieres
                  (seulement DECLARE et CONFIRME). Pour voir les contestations en cours :
                  navigate vers /etablissement/litiges ou fiche mission concernée. */}
            </div>
          </CollapsibleContent>
        </Collapsible>
      </div>

      {/* ── SECTION 6 : Exports comptables ── */}
      <div id={SECTIONS.exports} className="mb-4">
        <Collapsible open={sectionsOpen[SECTIONS.exports]} onOpenChange={() => toggleSection(SECTIONS.exports)}>
          <CollapsibleTrigger className="w-full">
            <CardY2K noPadding>
              <CardY2KHeader className="py-3">
                <div className="flex items-center justify-between">
                  <CardY2KTitle className="flex items-center gap-2 text-base">
                    <Download className="h-5 w-5 text-info" />
                    Exports comptables
                  </CardY2KTitle>
                  <ChevronDown className={`h-5 w-5 text-muted-foreground transition-transform ${sectionsOpen[SECTIONS.exports] ? 'rotate-180' : ''}`} />
                </div>
              </CardY2KHeader>
            </CardY2K>
          </CollapsibleTrigger>
          <CollapsibleContent>
            <div className="mt-2 space-y-3">
              <CardY2K noPadding>
                <CardY2KContent className="pt-4 space-y-3">
                  <p className="text-sm text-muted-foreground">
                    Téléchargez vos données financières pour votre comptabilité.
                  </p>

                  <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                    <BoutonY2K
                      variant="secondary"
                      className="h-auto py-3 justify-start gap-2"
                      onClick={() => navigate('/etablissement/export-paie')}
                    >
                      <FileText className="h-5 w-5 text-primary shrink-0" />
                      <div className="text-left">
                        <p className="font-medium text-sm">Export comptable / Paie</p>
                        <p className="text-xs text-muted-foreground">
                          Formats Standard, Silae et Sage
                        </p>
                      </div>
                    </BoutonY2K>

                    <BoutonY2K
                      variant="secondary"
                      className="h-auto py-3 justify-start gap-2"
                      onClick={() => {
                        // Ouvre un onglet par facture commission PAYEE (historique)
                        if (facturesCommissionHistorique.length === 0) {
                          toast.info('Aucune facture à télécharger.');
                          return;
                        }
                        facturesCommissionHistorique.forEach((f: any, i: number) => {
                          setTimeout(() => telechargerFactureCommissionPDF(f.facture_id), i * 200);
                        });
                        toast.success(`Téléchargement de ${facturesCommissionHistorique.length} facture${facturesCommissionHistorique.length > 1 ? 's' : ''}…`);
                      }}
                    >
                      <Download className="h-5 w-5 text-primary shrink-0" />
                      <div className="text-left">
                        <p className="font-medium text-sm">Toutes les factures commission</p>
                        <p className="text-xs text-muted-foreground">
                          Télécharge les {facturesCommissionHistorique.length} dernières payées
                        </p>
                      </div>
                    </BoutonY2K>
                  </div>

                  <div className="rounded-lg border bg-muted/20 p-3 text-xs text-muted-foreground">
                    <p className="font-semibold text-foreground mb-1"><Lightbulb className="inline-block h-3.5 w-3.5 mr-1 align-text-bottom" aria-hidden="true" />À savoir</p>
                    <p>
                      Les factures honoraires soignants (mandat art. 289 I-2 CGI) sont accessibles
                      individuellement depuis la section 5 (historique paiements).
                    </p>
                  </div>
                </CardY2KContent>
              </CardY2K>
            </div>
          </CollapsibleContent>
        </Collapsible>
      </div>

      {/* ── DIALOGS GLOBAUX ── */}

      {/* Dialog Stripe Checkout (paiement facture commission) */}
      {canManagePayments && showCheckout && checkoutFactureId && (
        <StripeEmbeddedCheckout
          factureId={checkoutFactureId}
          open={showCheckout}
          onClose={() => { setShowCheckout(false); setCheckoutFactureId(null); charger(); }}
        />
      )}

      {/* Dialog Stripe Connect (paiement mission soignant) */}
      {canManagePayments && showConnectCheckout && connectClientSecret && (
        <Dialog
          open={showConnectCheckout}
          onOpenChange={(open) => {
            if (!open && !connectConfirming) {
              setShowConnectCheckout(false);
              setConnectClientSecret(null);
              setConnectPaymentContext(null);
              void charger();
            }
          }}
        >
          <DialogContent className="sm:max-w-lg max-h-[90vh] overflow-y-auto">
            <DialogHeader>
              <DialogTitle>Paiement Stripe Connect</DialogTitle>
              <DialogDescription>Paiement sécurisé par carte — commission + honoraires en un seul débit</DialogDescription>
            </DialogHeader>
            {connectDecomposition && (
              <div className="text-xs text-muted-foreground space-y-1 mb-3">
                <p>Honoraires soignant : {fmt(connectDecomposition.salaire_brut)}</p>
                <p>Commission Jolene : {fmt(connectDecomposition.commission_ttc)}</p>
                <p className="font-semibold text-foreground">Total : {fmt(connectDecomposition.total)}</p>
              </div>
            )}
            {connectConfirming ? (
              <div className="py-8 text-center" role="status" aria-live="polite">
                <Loader2 className="h-5 w-5 animate-spin mx-auto mb-3 text-primary" />
                <p className="text-sm text-foreground">Confirmation du paiement en cours…</p>
              </div>
            ) : (
              <EmbeddedCheckoutProvider
                stripe={stripePromise}
                options={{
                  clientSecret: connectClientSecret,
                  onComplete: () => void finaliserRetourConnect(connectPaymentContext ?? undefined),
                }}
              >
                <EmbeddedCheckout />
              </EmbeddedCheckoutProvider>
            )}
          </DialogContent>
        </Dialog>
      )}

      {/* Dialog Déclaration paiement soignant (form complet OF-11, fullscreen mobile) */}
      {canManagePayments && declarerDialogMission && (
        <DialogResponsive open={!!declarerDialogMission} onOpenChange={(open) => { if (!open) fermerDialogDeclarer(); }}>
          <DialogResponsiveContent>
            <DialogResponsiveHeader>
              <DialogResponsiveTitle>Déclarer un paiement au soignant</DialogResponsiveTitle>
              <DialogResponsiveDescription>
                {declarerDialogMission.intitule || 'Mission'} — {declarerDialogMission.soignant_nom || ''}
              </DialogResponsiveDescription>
            </DialogResponsiveHeader>

            <DialogResponsiveBody className="space-y-4">
              {declarerDialogMission.type_contrat_applique === 'SALARIE' && (
                <div>
                  <Label htmlFor="declarer-montant-du">Total net dû selon le bulletin officiel</Label>
                  <Input
                    id="declarer-montant-du"
                    type="number"
                    step="0.01"
                    min="0.01"
                    value={declarerMontantDu}
                    onChange={(e) => setDeclarerMontantDu(e.target.value)}
                    placeholder="0.00"
                  />
                  <p className="text-xs text-muted-foreground mt-1">
                    Ce total sert à calculer le reliquat. Il n'est jamais remplacé par l'estimation Jolene.
                  </p>
                </div>
              )}
              <div>
                <Label htmlFor="declarer-montant">
                  {declarerDialogMission.type_contrat_applique === 'SALARIE'
                    ? 'Montant réellement versé aujourd’hui'
                    : 'Montant des honoraires versés'}
                </Label>
                <Input
                  id="declarer-montant"
                  type="number"
                  step="0.01"
                  value={declarerMontant}
                  onChange={(e) => setDeclarerMontant(e.target.value)}
                  placeholder="0.00"
                />
                {declarerDialogMission.type_contrat_applique === 'SALARIE' ? (
                  <div className="text-xs text-muted-foreground mt-1 space-y-1">
                    <p>
                      Estimation indicative avant paie/PAS : {fmt(Number(
                        declarerDialogMission.net_estime ?? declarerDialogMission.net_a_payer ?? 0,
                      ))}
                    </p>
                    <p>Recopiez le net à payer du bulletin officiel établi par votre établissement. L'estimation n'est pas utilisée automatiquement.</p>
                  </div>
                ) : (
                  <p className="text-xs text-muted-foreground mt-1">
                    Honoraires attendus : {fmt(Number(declarerDialogMission.net_a_payer ?? 0))}
                  </p>
                )}
              </div>

              <div>
                <Label htmlFor="declarer-methode">Méthode de paiement</Label>
                <Select
                  value={declarerMethode}
                  onValueChange={(v) => setDeclarerMethode(v as MethodePaiement)}
                >
                  <SelectTrigger id="declarer-methode">
                    <SelectValue placeholder="Choisir une méthode" />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="VIREMENT">Virement bancaire</SelectItem>
                    <SelectItem value="CHEQUE">Chèque</SelectItem>
                    <SelectItem value="BULLETIN_PAIE">Virement de salaire (bulletin employeur)</SelectItem>
                    <SelectItem value="NOTE_HONORAIRES">Note d'honoraires</SelectItem>
                  </SelectContent>
                </Select>
              </div>

              <div>
                <Label htmlFor="declarer-reference">
                  Référence {declarerMethode === 'BULLETIN_PAIE' ? '(optionnelle)' : '(obligatoire, min. 5 car. + 1 chiffre)'}
                </Label>
                <Input
                  id="declarer-reference"
                  value={declarerReference}
                  onChange={(e) => setDeclarerReference(e.target.value)}
                  placeholder={
                    declarerMethode === 'VIREMENT' ? 'Réf. virement bancaire'
                      : declarerMethode === 'CHEQUE' ? 'N° chèque'
                      : declarerMethode === 'BULLETIN_PAIE' ? 'N° bulletin (facultatif)'
                      : 'Réf. note d\'honoraires'
                  }
                />
              </div>

              <div>
                <Label htmlFor="declarer-date">Date du paiement</Label>
                <Input
                  id="declarer-date"
                  type="date"
                  value={declarerDatePaiement}
                  max={new Date().toISOString().split('T')[0]}
                  onChange={(e) => setDeclarerDatePaiement(e.target.value)}
                />
              </div>

              <div className="rounded-lg border border-warning/40 bg-warning/5 p-3">
                <div className="flex items-start gap-2">
                  <Checkbox
                    id="declarer-attestation"
                    checked={declarerAttestation}
                    onCheckedChange={(c) => setDeclarerAttestation(c === true)}
                    className="mt-0.5"
                  />
                  <Label
                    htmlFor="declarer-attestation"
                    className="text-xs text-foreground leading-relaxed cursor-pointer"
                  >
                    <strong>J'atteste sur l'honneur</strong> avoir effectivement payé ce soignant conformément au
                    Code du travail (pour un salarié) ou au Code de commerce (pour un libéral) en contrepartie
                    de la prestation effectuée dans le cadre de cette mission. Cette déclaration m'engage au
                    regard de l'URSSAF et de l'administration fiscale. Une déclaration frauduleuse m'expose à
                    des sanctions pénales (article 441-1 du Code pénal).
                  </Label>
                </div>
              </div>
            </DialogResponsiveBody>

            <DialogResponsiveFooter className="gap-2">
              <BoutonY2K variant="secondary" onClick={fermerDialogDeclarer}>
                Annuler
              </BoutonY2K>
              <BoutonY2K
                onClick={validerDeclarationPaiement}
                disabled={
                  !declarerAttestation ||
                  declaringId === declarerDialogMission.mission_id ||
                  !declarerMontant ||
                  Number(declarerMontant) <= 0 ||
                  (declarerDialogMission.type_contrat_applique === 'SALARIE' && (
                    !declarerMontantDu ||
                    Number(declarerMontantDu) <= 0 ||
                    Number(declarerMontant) > Number(declarerMontantDu)
                  )) ||
                  (declarerMethode !== 'BULLETIN_PAIE' && !isRefValid(declarerReference))
                }
              >
                {declaringId === declarerDialogMission.mission_id ? 'Envoi…' : 'Valider la déclaration'}
              </BoutonY2K>
            </DialogResponsiveFooter>
          </DialogResponsiveContent>
        </DialogResponsive>
      )}
    </LayoutApp>
  );
}
