import React, { useState, useEffect, useRef } from 'react';
import { capturerErreurSentry } from '@/lib/sentry';
import { logger } from '@/lib/logger';
import { usePageTitle } from '@/hooks/usePageTitle';
import { SkeletonDashboard } from '@/components/SkeletonCard';
import { FadeInView } from '@/components/FadeInView';
import { useNavigate, useSearchParams } from 'react-router-dom';
import {
  CreditCard, Clock, CheckCircle, FileText, Loader2, Trophy, RefreshCw,
  Building2, AlertTriangle, Download, Banknote, Info, Eye, ChevronDown,
  Edit2, X, Scale, ChevronRight, ExternalLink,
} from 'lucide-react';
import { LayoutApp } from '@/components/LayoutApp';
import { CarteKPI } from '@/components/CarteKPI';
import { EtatVide, IllustrationCalculatrice } from '@/components/EtatVide';
import { BadgePalier } from '@/components/BadgePalier';
import { FactureChorus, ChorusStatutBadge } from '@/components/FactureChorus';
import { PaiementVirement } from '@/components/PaiementVirement';
import { StripeEmbeddedCheckout } from '@/components/StripeEmbeddedCheckout';
import { EmbeddedCheckoutProvider, EmbeddedCheckout } from '@stripe/react-stripe-js';
import { stripePromise } from '@/lib/stripe';
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Collapsible, CollapsibleTrigger, CollapsibleContent } from '@/components/ui/collapsible';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Checkbox } from '@/components/ui/checkbox';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { DialogFooter } from '@/components/ui/dialog';
import { ENTREPRISE } from '@/constantes/entreprise';
import { useAuth } from '@/contexts/AuthContext';
import { useNotification } from '@/contexts/NotificationContext';
import { supabase } from '@/integrations/supabase/client';
import { extraireMessageErreur } from '@/lib/erreurs';
import { payerMissionStripeConnectAvecGenerationAuto } from '@/lib/stripeMissionPay';
import { telechargerFactureCommissionPDF } from '@/lib/facture-commission-pdf';
import { telechargerFactureHonorairesPDF } from '@/lib/facture-honoraires-pdf';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import { toast } from 'sonner';
import { useEtablissementScope } from '@/hooks/useEtablissementScope';

const fmt = (v: number | null | undefined) =>
  v != null ? new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(v) : '—';

type MethodePaiement = 'VIREMENT' | 'CHEQUE' | 'BULLETIN_PAIE' | 'NOTE_HONORAIRES';

const isRefValid = (ref: string) => {
  const t = ref.trim();
  return t.length >= 6 && /\d{2,}/.test(t) && /[A-Za-z]/.test(t);
};

const METHODE_LABELS: Record<MethodePaiement, string> = {
  VIREMENT: 'Virement bancaire',
  CHEQUE: 'Chèque',
  BULLETIN_PAIE: 'Bulletin de paie',
  NOTE_HONORAIRES: 'Note d\'honoraires',
};

// ─── Helpers cards missions ───
function RetardBadge({ jours }: { jours: number }) {
  if (jours < 15) return null;
  if (jours < 30) return <Badge className="bg-amber-100 text-amber-700 dark:bg-amber-900/30 dark:text-amber-400">⏳ {jours}j</Badge>;
  if (jours < 60) return <Badge className="bg-destructive/10 text-destructive">🔴 {jours}j de retard</Badge>;
  return <Badge className="bg-destructive text-destructive-foreground">⛔ {jours}j — risque de suspension</Badge>;
}

function TypeExerciceBadge({ type }: { type: string }) {
  const map: Record<string, { label: string; cls: string }> = {
    SALARIE: { label: 'Salarié', cls: 'bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-400' },
    LIBERAL: { label: 'Libéral', cls: 'bg-emerald-100 text-emerald-700 dark:bg-emerald-900/30 dark:text-emerald-400' },
    MIXTE: { label: 'Mixte', cls: 'bg-violet-100 text-violet-700 dark:bg-violet-900/30 dark:text-violet-400' },
  };
  const info = map[type] || { label: type, cls: 'bg-muted text-muted-foreground' };
  return <Badge className={info.cls}>{info.label}</Badge>;
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
  const { user, etablissementId } = useEtablissementScope();
  const { afficherNotification } = useNotification();
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();

  // ── Data ──
  const [loading, setLoading] = useState(true);
  const [etab, setEtab] = useState<any>(null);
  const [data, setData] = useState<any>(null);        // fn_obligations_financieres
  const [paiementsData, setPaiementsData] = useState<any>(null); // fn_paiements_etablissement
  const [factures, setFactures] = useState<any[]>([]); // fn_mes_factures
  const [missionsNonFacturees, setMissionsNonFacturees] = useState<any[]>([]);
  const [prelevements, setPrelevements] = useState<any[]>([]);
  const [missionsPaidByStripe, setMissionsPaidByStripe] = useState<Set<string>>(new Set());

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
  const [connectPayLoading, setConnectPayLoading] = useState(false);
  const [checkoutFactureId, setCheckoutFactureId] = useState<string | null>(null);
  const [showCheckout, setShowCheckout] = useState(false);
  const [declarerDialogMission, setDeclarerDialogMission] = useState<any>(null);
  const [declarerMontant, setDeclarerMontant] = useState<string>('');
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
  }, []);

  // ── Data loading ──
  const charger = async () => {
    if (!user) return;
    setLoading(true);
    try {
      const [resEtab, resObligations, resPaiements, resFactures, resMNF, resTransfers, resPrelev] = await Promise.all([
        supabase.rpc('fn_mon_etablissement_complet' as any),
        supabase.rpc('fn_obligations_financieres' as any),
        supabase.rpc('fn_paiements_etablissement' as any),
        supabase.rpc('fn_mes_factures' as any),
        supabase.from('missions')
          .select('id, intitule, fin_le, montant_commission_ht, montant_commission_ttc')
          .eq('etablissement_id', user.id)
          .eq('statut', 'TERMINEE')
          .eq('commission_facturee', false)
          .order('fin_le', { ascending: false }),
        supabase.from('stripe_transfers')
          .select('mission_id, statut')
          .eq('etablissement_id', user.id)
          .in('statut', ['TRANSFERE']),
        supabase.from('paiements_mission')
          .select('id, mission_id, montant_ttc, statut, capture_le, missions(intitule)')
          .eq('etablissement_id', user.id)
          .order('capture_le', { ascending: false })
          .limit(20),
      ]);

      if (resEtab.data) setEtab(resEtab.data);
      if (resObligations.data && !(resObligations.data as any).error) setData(resObligations.data);
      if (resPaiements.data && !(resPaiements.data as any).error) setPaiementsData(resPaiements.data);
      setFactures(Array.isArray(resFactures.data) ? resFactures.data : []);
      if (resMNF.data) setMissionsNonFacturees(resMNF.data);
      if (resTransfers.data) setMissionsPaidByStripe(new Set(resTransfers.data.map((t: any) => t.mission_id)));
      if (resPrelev.data) setPrelevements(resPrelev.data);
    } catch (err) {
      logger.error('Facturation charger error', err);
    }
    setLoading(false);
  };

  useEffect(() => { charger(); }, [user]);

  // ── Handlers dialogs paiement ──
  const ouvrirDialogDeclarer = (mission: any) => {
    setDeclarerDialogMission(mission);
    setDeclarerMontant(String(Number(mission.net_a_payer || 0).toFixed(2)));
    setDeclarerMethode('VIREMENT');
    setDeclarerReference('');
    setDeclarerDatePaiement(new Date().toISOString().split('T')[0]);
    setDeclarerAttestation(false);
  };

  const fermerDialogDeclarer = () => {
    setDeclarerDialogMission(null);
    setDeclaringId(null);
  };

  const validerDeclarationPaiement = async () => {
    if (!declarerDialogMission) return;
    const missionId = declarerDialogMission.mission_id;
    const montantNum = Number(declarerMontant);
    if (!montantNum || montantNum <= 0) {
      toast.error('Montant invalide');
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

    setDeclaringId(missionId);
    try {
      const { data, error } = await supabase.rpc('fn_declarer_paiement_soignant' as any, {
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
        // eslint-disable-next-line no-console
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

  const payerStripeConnect = async (missionId: string) => {
    setConnectPayingId(missionId);
    const loadingToastId = toast.loading('Préparation du paiement…');
    try {
      const { data: sessionData } = await supabase.auth.getSession();
      const accessToken = sessionData?.session?.access_token;
      if (!accessToken) {
        toast.error('Session expirée, veuillez vous reconnecter', { id: loadingToastId });
        return;
      }

      const { result, error, code, message, factureGenereeAuto } =
        await payerMissionStripeConnectAvecGenerationAuto(missionId, accessToken, (msg) => toast.loading(msg, { id: loadingToastId }));

      if (code === 'CONTRAT_SALARIE_NON_STRIPE') {
        toast.error(message || 'Les missions salariées doivent être payées par virement SEPA (bulletin de paie).', { id: loadingToastId, duration: 8000 });
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
        setShowConnectCheckout(true);
        setConnectDecomposition({
          commission_ttc: result.commission_ttc,
          salaire_brut: result.salaire_brut,
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

  // ── Loading ──
  if (loading) return <LayoutApp role="ADMIN_ETABLISSEMENT"><SkeletonDashboard /></LayoutApp>;

  // Derived data
  const missionsNonPayees = data?.missions_non_payees || [];
  const paiementsEnAttente = data?.paiements_soignants_en_attente || [];
  const paiementsConfirmes = data?.paiements_soignants_confirmes || [];
  const facturesImpayees = data?.factures_impayees || [];
  const facturesCommissionHistorique = data?.factures_commission_historique || [];
  const nbFacturesHistorique = data?.nb_factures_commission_historique || 0;
  const missionsNonFactureesObligs = data?.missions_non_facturees || [];

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
            <Badge className="bg-info/10 text-info border-info/20">🏛️ Secteur public</Badge>
          )}
        </div>
      </div>

      {/* ── SECTION 0 : État vide si rien à payer ── */}
      {data && data.total_du === 0 && missionsNonPayees.length === 0 && facturesImpayees.length === 0 && (
        <FadeInView>
          <div className="card-base p-8 text-center mb-6">
            <CheckCircle className="h-12 w-12 text-success mx-auto mb-3" />
            <p className="text-lg font-semibold text-foreground">Tout est à jour ✅</p>
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
            <p className="text-xs text-muted-foreground">Total à régler</p>
          </div>

          {/* KPI "Soignants" — cliquable → section Missions à payer */}
          <button
            type="button"
            onClick={() => openAndScrollTo(SECTIONS.payer)}
            className="card-base text-left cursor-pointer hover:shadow-md transition-shadow flex items-start justify-between gap-2"
          >
            <div>
              <p className="text-2xl font-bold text-foreground">{fmt(data?.total_soignants_du)}</p>
              <p className="text-xs text-muted-foreground">Soignants à régler · {data?.nb_missions_non_payees || 0} mission(s)</p>
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
              <p className="text-xs text-muted-foreground">Commissions Jolene · {data?.nb_factures_impayees || 0} facture(s)</p>
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
          { id: SECTIONS.commissions, label: 'Commissions', count: facturesImpayees.length },
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
            <Card>
              <CardHeader className="py-3">
                <div className="flex items-center justify-between">
                  <CardTitle className="flex items-center gap-2 text-base">
                    <AlertTriangle className="h-5 w-5 text-destructive" />
                    Missions à payer aux soignants ({missionsNonPayees.length})
                  </CardTitle>
                  <ChevronDown className={`h-5 w-5 text-muted-foreground transition-transform ${sectionsOpen[SECTIONS.payer] ? 'rotate-180' : ''}`} />
                </div>
              </CardHeader>
            </Card>
          </CollapsibleTrigger>
          <CollapsibleContent>
            <div className="mt-2 space-y-3">
              {missionsNonPayees.length === 0 ? (
                <Card>
                  <CardContent className="py-6 text-center text-sm text-muted-foreground">
                    Aucune mission en attente de paiement soignant.
                  </CardContent>
                </Card>
              ) : (
                missionsNonPayees.map((m: any) => {
                  const typeContratMission = m.type_contrat_applique as 'SALARIE' | 'LIBERAL' | null | undefined;
                  const isSalarie = typeContratMission === 'SALARIE';
                  const isLiberal = typeContratMission === 'LIBERAL';
                  const modePaiementLabel = isSalarie
                    ? 'Bulletin de paie (virement SEPA)'
                    : isLiberal
                    ? (m.mode_paiement_soignant === 'STRIPE_CONNECT' ? 'Note d\'honoraires (Stripe Connect)' : 'Note d\'honoraires (virement)')
                    : null;
                  const peutPayerStripeBase =
                    isLiberal
                    && m.mode_paiement_soignant === 'STRIPE_CONNECT'
                    && m.soignant_stripe_connect;
                  const enLitige = Boolean(m.a_paiement_conteste);
                  const peutPayerStripe = peutPayerStripeBase && !enLitige;
                  return (
                    <div key={m.mission_id} className="card-base space-y-3">
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
                            <TypeExerciceBadge type={m.soignant_type_exercice} />
                            <RetardBadge jours={m.jours_depuis_fin} />
                          </div>
                          <p className="text-xs text-muted-foreground mt-1">
                            {m.soignant_profession} · {Math.round(m.heures || 0)}h pointées
                          </p>
                          <p className="text-xs text-muted-foreground">
                            {m.debut_le && new Date(m.debut_le).toLocaleDateString('fr-FR')} → {m.fin_le && new Date(m.fin_le).toLocaleDateString('fr-FR')}
                          </p>
                          {typeContratMission && (
                            <div className="flex items-center gap-2 mt-2 flex-wrap">
                              <Badge className={isSalarie
                                ? 'bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-400'
                                : 'bg-emerald-100 text-emerald-700 dark:bg-emerald-900/30 dark:text-emerald-400'}
                              >
                                Contrat {isSalarie ? 'salarié (CDDU)' : 'libéral'}
                              </Badge>
                              {modePaiementLabel && (
                                <span className="text-xs text-muted-foreground">→ {modePaiementLabel}</span>
                              )}
                            </div>
                          )}
                          {enLitige && (
                            <div className="mt-2 flex items-center gap-2 flex-wrap rounded-md border border-destructive/40 bg-destructive/10 px-3 py-2">
                              <Scale className="h-4 w-4 text-destructive shrink-0" />
                              <div className="flex-1 min-w-0">
                                <p className="text-sm font-semibold text-destructive">⚠️ Litige en cours sur un paiement</p>
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
                          ) : (
                            <p className="font-bold">{fmt(m.net_a_payer)}</p>
                          )}
                        </div>
                      </div>

                      {peutPayerStripe ? (
                        <Button
                          size="sm"
                          onClick={() => payerStripeConnect(m.mission_id)}
                          disabled={connectPayingId === m.mission_id || enLitige}
                          className="w-full"
                        >
                          <CreditCard className="w-4 h-4 mr-2" />
                          {connectPayingId === m.mission_id ? 'Redirection…' : '💳 Payer via Stripe'}
                        </Button>
                      ) : (
                        <Button
                          size="sm"
                          onClick={() => ouvrirDialogDeclarer(m)}
                          disabled={declaringId === m.mission_id || enLitige}
                          className="w-full"
                        >
                          <Banknote className="w-4 h-4 mr-2" />
                          {enLitige ? 'Paiement bloqué (litige)' : 'Déclarer un paiement'}
                        </Button>
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
            <Card>
              <CardHeader className="py-3">
                <div className="flex items-center justify-between">
                  <CardTitle className="flex items-center gap-2 text-base">
                    <Clock className="h-5 w-5 text-warning" />
                    Paiements en attente ({paiementsEnAttente.length})
                  </CardTitle>
                  <ChevronDown className={`h-5 w-5 text-muted-foreground transition-transform ${sectionsOpen[SECTIONS.attente] ? 'rotate-180' : ''}`} />
                </div>
              </CardHeader>
            </Card>
          </CollapsibleTrigger>
          <CollapsibleContent>
            <div className="mt-2 space-y-3">
              {/* B.3.3.b — contenu migré depuis OF-5 */}
              <p className="text-sm text-muted-foreground p-4 card-base">Contenu migré en B.3.3.b</p>
            </div>
          </CollapsibleContent>
        </Collapsible>
      </div>

      {/* ── SECTION 4 : Commissions Jolene ── */}
      <div id={SECTIONS.commissions} className="mb-4">
        <Collapsible open={sectionsOpen[SECTIONS.commissions]} onOpenChange={() => toggleSection(SECTIONS.commissions)}>
          <CollapsibleTrigger className="w-full">
            <Card>
              <CardHeader className="py-3">
                <div className="flex items-center justify-between">
                  <CardTitle className="flex items-center gap-2 text-base">
                    <FileText className="h-5 w-5 text-primary" />
                    Commissions Jolene ({facturesImpayees.length} impayée{facturesImpayees.length > 1 ? 's' : ''})
                  </CardTitle>
                  <ChevronDown className={`h-5 w-5 text-muted-foreground transition-transform ${sectionsOpen[SECTIONS.commissions] ? 'rotate-180' : ''}`} />
                </div>
              </CardHeader>
            </Card>
          </CollapsibleTrigger>
          <CollapsibleContent>
            <div className="mt-2 space-y-4">
              {/* B.3.3.b — contenu migré depuis OF-6/OF-7 + FE-11/14/17/18/19 */}
              <p className="text-sm text-muted-foreground p-4 card-base">Contenu migré en B.3.3.b</p>
            </div>
          </CollapsibleContent>
        </Collapsible>
      </div>

      {/* ── SECTION 5 : Historique paiements confirmés ── */}
      <div id={SECTIONS.historique} className="mb-4">
        <Collapsible open={sectionsOpen[SECTIONS.historique]} onOpenChange={() => toggleSection(SECTIONS.historique)}>
          <CollapsibleTrigger className="w-full">
            <Card>
              <CardHeader className="py-3">
                <div className="flex items-center justify-between">
                  <CardTitle className="flex items-center gap-2 text-base">
                    <CheckCircle className="h-5 w-5 text-success" />
                    Historique paiements ({paiementsConfirmes.length} confirmé{paiementsConfirmes.length > 1 ? 's' : ''})
                  </CardTitle>
                  <ChevronDown className={`h-5 w-5 text-muted-foreground transition-transform ${sectionsOpen[SECTIONS.historique] ? 'rotate-180' : ''}`} />
                </div>
              </CardHeader>
            </Card>
          </CollapsibleTrigger>
          <CollapsibleContent>
            <div className="mt-2 space-y-3">
              {/* B.3.3.c — contenu migré depuis OF-8 + FE-6/FE-7 */}
              <p className="text-sm text-muted-foreground p-4 card-base">Contenu migré en B.3.3.c</p>
            </div>
          </CollapsibleContent>
        </Collapsible>
      </div>

      {/* ── SECTION 6 : Exports comptables ── */}
      <div id={SECTIONS.exports} className="mb-4">
        <Collapsible open={sectionsOpen[SECTIONS.exports]} onOpenChange={() => toggleSection(SECTIONS.exports)}>
          <CollapsibleTrigger className="w-full">
            <Card>
              <CardHeader className="py-3">
                <div className="flex items-center justify-between">
                  <CardTitle className="flex items-center gap-2 text-base">
                    <Download className="h-5 w-5 text-info" />
                    Exports comptables
                  </CardTitle>
                  <ChevronDown className={`h-5 w-5 text-muted-foreground transition-transform ${sectionsOpen[SECTIONS.exports] ? 'rotate-180' : ''}`} />
                </div>
              </CardHeader>
            </Card>
          </CollapsibleTrigger>
          <CollapsibleContent>
            <div className="mt-2 space-y-3">
              {/* B.3.3.c — contenu migré depuis FE-20 */}
              <p className="text-sm text-muted-foreground p-4 card-base">Contenu migré en B.3.3.c</p>
            </div>
          </CollapsibleContent>
        </Collapsible>
      </div>

      {/* ── DIALOGS GLOBAUX ── */}

      {/* Dialog Stripe Checkout (paiement facture commission) */}
      {showCheckout && checkoutFactureId && (
        <StripeEmbeddedCheckout
          factureId={checkoutFactureId}
          open={showCheckout}
          onClose={() => { setShowCheckout(false); setCheckoutFactureId(null); charger(); }}
        />
      )}

      {/* Dialog Stripe Connect (paiement mission soignant) */}
      {showConnectCheckout && connectClientSecret && (
        <Dialog open={showConnectCheckout} onOpenChange={(open) => { if (!open) { setShowConnectCheckout(false); charger(); } }}>
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
            <EmbeddedCheckoutProvider stripe={stripePromise} options={{ clientSecret: connectClientSecret }}>
              <EmbeddedCheckout />
            </EmbeddedCheckoutProvider>
          </DialogContent>
        </Dialog>
      )}

      {/* Dialog Déclaration paiement soignant (form complet OF-11, fullscreen mobile) */}
      {declarerDialogMission && (
        <Dialog open={!!declarerDialogMission} onOpenChange={(open) => { if (!open) fermerDialogDeclarer(); }}>
          <DialogContent className="max-w-[calc(100%-1rem)] sm:max-w-lg max-h-[90vh] overflow-y-auto">
            <DialogHeader>
              <DialogTitle>Déclarer un paiement au soignant</DialogTitle>
              <DialogDescription>
                {declarerDialogMission.intitule || 'Mission'} — {declarerDialogMission.soignant_nom || ''}
              </DialogDescription>
            </DialogHeader>

            <div className="space-y-4 py-2">
              <div>
                <Label htmlFor="declarer-montant">Montant payé (€ net)</Label>
                <Input
                  id="declarer-montant"
                  type="number"
                  step="0.01"
                  value={declarerMontant}
                  onChange={(e) => setDeclarerMontant(e.target.value)}
                  placeholder="0.00"
                />
                <p className="text-xs text-muted-foreground mt-1">
                  Montant estimé : {fmt(Number(declarerDialogMission.net_a_payer || 0))}
                </p>
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
                    <SelectItem value="BULLETIN_PAIE">Bulletin de paie</SelectItem>
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
            </div>

            <DialogFooter className="gap-2">
              <Button variant="outline" onClick={fermerDialogDeclarer}>
                Annuler
              </Button>
              <Button
                onClick={validerDeclarationPaiement}
                disabled={
                  !declarerAttestation ||
                  declaringId === declarerDialogMission.mission_id ||
                  !declarerMontant ||
                  Number(declarerMontant) <= 0 ||
                  (declarerMethode !== 'BULLETIN_PAIE' && !isRefValid(declarerReference))
                }
              >
                {declaringId === declarerDialogMission.mission_id ? 'Envoi…' : 'Valider la déclaration'}
              </Button>
            </DialogFooter>
          </DialogContent>
        </Dialog>
      )}
    </LayoutApp>
  );
}
