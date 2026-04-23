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
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
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
  const [declarerForm, setDeclarerForm] = useState({ montant: '', methode: 'VIREMENT', reference: '', date: new Date().toISOString().split('T')[0], attestation: false });
  const [declarerLoading, setDeclarerLoading] = useState(false);
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
          <div
            className="card-base cursor-pointer hover:shadow-md transition-shadow border-destructive/20"
            onClick={() => { toggleSection(SECTIONS.payer); scrollTo(SECTIONS.payer); }}
          >
            <p className="text-2xl font-bold text-foreground">{fmt(data?.total_du)}</p>
            <p className="text-xs text-muted-foreground">Total à régler</p>
          </div>
          <div
            className="card-base cursor-pointer hover:shadow-md transition-shadow"
            onClick={() => { toggleSection(SECTIONS.payer); scrollTo(SECTIONS.payer); }}
          >
            <p className="text-2xl font-bold text-foreground">{fmt(data?.total_soignants_du)}</p>
            <p className="text-xs text-muted-foreground">Soignants à régler · {data?.nb_missions_non_payees || 0} mission(s)</p>
          </div>
          <div
            className="card-base cursor-pointer hover:shadow-md transition-shadow"
            onClick={() => { toggleSection(SECTIONS.commissions); scrollTo(SECTIONS.commissions); }}
          >
            <p className="text-2xl font-bold text-foreground">{fmt(data?.total_commissions_du)}</p>
            <p className="text-xs text-muted-foreground">Commissions Jolene · {data?.nb_factures_impayees || 0} facture(s)</p>
          </div>
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
            onClick={() => { setSectionsOpen(prev => ({ ...prev, [s.id]: true })); scrollTo(s.id); }}
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
              {/* B.3.3.a — contenu migré depuis OF-3 */}
              <p className="text-sm text-muted-foreground p-4 card-base">Contenu migré en B.3.3.a</p>
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

      {/* Dialog Déclaration paiement soignant (fullscreen mobile) */}
      {declarerDialogMission && (
        <Dialog open={!!declarerDialogMission} onOpenChange={(open) => { if (!open) { setDeclarerDialogMission(null); } }}>
          <DialogContent className="sm:max-w-lg max-h-[90vh] overflow-y-auto">
            <DialogHeader>
              <DialogTitle>Déclarer un paiement</DialogTitle>
              <DialogDescription>Mission : {declarerDialogMission?.intitule}</DialogDescription>
            </DialogHeader>
            {/* B.3.3.a — formulaire complet migré depuis OF-11 */}
            <p className="text-sm text-muted-foreground">Formulaire migré en B.3.3.a</p>
          </DialogContent>
        </Dialog>
      )}
    </LayoutApp>
  );
}
