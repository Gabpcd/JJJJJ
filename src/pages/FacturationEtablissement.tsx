import React, { useState, useEffect } from 'react';
import { capturerErreurSentry } from '@/lib/sentry';
import { usePageTitle } from '@/hooks/usePageTitle';
import { SkeletonDashboard } from '@/components/SkeletonCard';
import { FadeInView } from '@/components/FadeInView';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { CreditCard, Clock, CheckCircle, FileText, Loader2, Trophy, RefreshCw, Building2, AlertTriangle, Download, Banknote, Info, Eye, ChevronDown } from 'lucide-react';
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
import { ENTREPRISE } from '@/constantes/entreprise';
import { useAuth } from '@/contexts/AuthContext';
import { useNotification } from '@/contexts/NotificationContext';
import { supabase } from '@/integrations/supabase/client';
import { extraireMessageErreur } from '@/lib/erreurs';
import { Tabs, TabsList, TabsTrigger, TabsContent } from '@/components/ui/tabs';
import { Collapsible, CollapsibleTrigger, CollapsibleContent } from '@/components/ui/collapsible';
import { Button } from '@/components/ui/button';
import { toast } from 'sonner';

import { format } from 'date-fns';
import { fr } from 'date-fns/locale';

const STATUT_COLORS: Record<string, string> = {
  BROUILLON: 'bg-muted text-muted-foreground',
  EMISE: 'bg-primary/10 text-primary',
  VIREMENT_DECLARE: 'bg-amber-100 text-amber-700 dark:bg-amber-900/30 dark:text-amber-400',
  PAYEE: 'bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-400',
  EN_RETARD: 'bg-destructive/10 text-destructive',
  ANNULEE: 'bg-muted text-muted-foreground line-through',
};

const STATUT_LABELS: Record<string, string> = {
  BROUILLON: 'Brouillon',
  EMISE: 'Émise',
  VIREMENT_DECLARE: 'Virement déclaré 🔍',
  PAYEE: 'Payée',
  EN_RETARD: 'En retard',
  ANNULEE: 'Annulée',
};

const PAIEMENT_STATUT_COLORS: Record<string, string> = {
  DECLARE: 'bg-amber-100 text-amber-700 dark:bg-amber-900/30 dark:text-amber-400',
  CONFIRME: 'bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-400',
  CONTESTE: 'bg-destructive/10 text-destructive',
};

const PAIEMENT_STATUT_LABELS: Record<string, string> = {
  DECLARE: 'Déclaré',
  CONFIRME: 'Confirmé',
  CONTESTE: 'Contesté',
};

const fmt = (v: number) => new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(v);

const isRefValid = (ref: string) => ref.trim().length >= 5 && /\d/.test(ref);

export default function FacturationEtablissement() {
  usePageTitle('Facturation');
  const navigate = useNavigate();
  const [searchParams, setSearchParams] = useSearchParams();
  const { user } = useAuth();
  const { afficherNotification } = useNotification();
  const [loading, setLoading] = useState(true);
  const [generating, setGenerating] = useState(false);
  const [payingId, setPayingId] = useState<string | null>(null);
  const [refreshingId, setRefreshingId] = useState<string | null>(null);
  const [declaringId, setDeclaringId] = useState<string | null>(null);
  const [declaringRef, setDeclaringRef] = useState<Record<string, string>>({});
  const [connectPayingId, setConnectPayingId] = useState<string | null>(null);
  const [factures, setFactures] = useState<any[]>([]);
  const [missionsNonFacturees, setMissionsNonFacturees] = useState<any[]>([]);
  const [etab, setEtab] = useState<any>(null);
  const [kpiCommissions, setKpiCommissions] = useState({ enAttente: 0, enCours: 0, totalPaye: 0 });
  const [prelevements, setPrelevements] = useState<any[]>([]);
  const [showSuccessBanner, setShowSuccessBanner] = useState(false);
  const [filtreStatut, setFiltreStatut] = useState<string | null>(searchParams.get('filtre'));
  const [checkoutFactureId, setCheckoutFactureId] = useState<string | null>(null);
  const [ribCache, setRibCache] = useState<Record<string, string>>({});
  const [ribLoadingId, setRibLoadingId] = useState<string | null>(null);
  const [filtreStatutPaiement, setFiltreStatutPaiement] = useState<string | null>(null);

  // Paiements soignants state
  const [paiementsData, setPaiementsData] = useState<any>(null);

  useEffect(() => {
    if (searchParams.get('paiement') === 'succes') {
      setShowSuccessBanner(true);
      searchParams.delete('paiement');
      setSearchParams(searchParams, { replace: true });
      const timer = setTimeout(() => setShowSuccessBanner(false), 8000);
      return () => clearTimeout(timer);
    }
  }, []);

  const charger = async () => {
    if (!user) return;

    const [resEtab, resFact, resMNF, resPrelev, resPaiements] = await Promise.all([
      supabase.rpc('fn_mon_etablissement_complet' as any),
      supabase.rpc('fn_mes_factures' as any),
      supabase.from('missions')
        .select('id, intitule, debut_le, fin_le, montant_commission_ht, montant_commission_ttc, statut')
        .eq('etablissement_id', user.id)
        .eq('statut', 'TERMINEE')
        .eq('commission_facturee', false)
        .order('fin_le', { ascending: false }),
      supabase.from('paiements_mission')
        .select('id, mission_id, montant_ttc, statut, capture_le, missions(intitule)')
        .eq('etablissement_id', user.id)
        .order('capture_le', { ascending: false })
        .limit(20),
      supabase.rpc('fn_paiements_etablissement' as any),
    ]);

    if (resEtab.data) setEtab(resEtab.data);
    const facturesRpc = Array.isArray(resFact.data) ? resFact.data : [];
    setFactures(facturesRpc);
    if (resMNF.data) setMissionsNonFacturees(resMNF.data);
    if (resPrelev.data) setPrelevements(resPrelev.data);
    if (resPaiements.data && !(resPaiements.data as any).error) {
      setPaiementsData(resPaiements.data);
    }

    const nonFacture = (resMNF.data ?? []).reduce((s: number, m: any) => s + (m.montant_commission_ttc ?? 0), 0);
    const enCours = facturesRpc.filter((f: any) => f.statut === 'EMISE' || f.statut === 'EN_RETARD' || f.statut === 'VIREMENT_DECLARE').reduce((s: number, f: any) => s + (f.montant_ttc ?? 0), 0);
    const totalPaye = facturesRpc.filter((f: any) => f.statut === 'PAYEE').reduce((s: number, f: any) => s + (f.montant_ttc ?? 0), 0);
    setKpiCommissions({ enAttente: nonFacture + enCours, enCours, totalPaye });

    setLoading(false);
  };

  useEffect(() => { charger(); }, [user]);

  const genererFactureMois = async () => {
    if (!user || missionsNonFacturees.length === 0) return;
    setGenerating(true);
    try {
      const { data, error } = await supabase.rpc('fn_generer_facture_rate_limited' as any);
      if (error) throw error;
      const result = data as any;
      if (!result?.success) throw new Error(result?.error || 'Erreur de génération');
      supabase.functions.invoke('send-email', {
        body: { type: 'FACTURE_EMISE', data: { numero: result.numero_facture, montant_ttc: Number(result.montant_ttc).toFixed(2), facture_id: result.facture_id }, destinataire_id: user!.id },
      }).catch(() => {});
      afficherNotification({ type: 'succes', message: `Facture ${result.numero_facture} générée avec succès !` });
      charger();
    } catch (err: any) {
      capturerErreurSentry(err, 'FacturationEtablissement', 'generer_facture');
      afficherNotification({ type: 'erreur', message: extraireMessageErreur(err) });
    } finally {
      setGenerating(false);
    }
  };

  const payerParCarte = (facture: any) => setCheckoutFactureId(facture.id);

  const rafraichirStatut = async (factureId: string) => {
    setRefreshingId(factureId);
    try {
      await supabase.functions.invoke('confirm-invoice-payment', { body: { facture_id: factureId } });
      const { data, error } = await supabase.from('factures').select('statut, date_paiement').eq('id', factureId).single();
      if (error) throw error;
      if (data) {
        setFactures(prev => prev.map(f => f.id === factureId ? { ...f, ...data } : f));
        if (data.statut === 'PAYEE') afficherNotification({ type: 'succes', message: 'Statut mis à jour : Payée ✅' });
        else afficherNotification({ type: 'info', message: `Statut actuel : ${STATUT_LABELS[data.statut] ?? data.statut}` });
      }
    } catch (err: any) {
      capturerErreurSentry(err, 'FacturationEtablissement', 'rafraichir_paiement');
      afficherNotification({ type: 'erreur', message: extraireMessageErreur(err) });
    } finally {
      setRefreshingId(null);
    }
  };

  const declarerPaiementSoignant = async (missionId: string, montant: number) => {
    const ref = declaringRef[missionId]?.trim();
    if (!ref || !isRefValid(ref)) {
      toast.error('La référence doit contenir au moins 5 caractères dont 1 chiffre');
      return;
    }
    setDeclaringId(missionId);
    try {
      const { data, error } = await supabase.rpc('fn_declarer_paiement_soignant' as any, {
        p_mission_id: missionId,
        p_montant: montant,
        p_reference: ref,
      });
      if (error) throw error;
      const result = data as any;
      if (result?.error) {
        if (result?.use_stripe_connect) {
          toast.info('Ce soignant utilise Stripe Connect — lancement du paiement par carte');
          lancerPaiementStripeConnect(missionId);
          return;
        }
        throw new Error(result.error);
      }
      toast.success('Paiement déclaré — le soignant sera notifié');
      setDeclaringRef(prev => ({ ...prev, [missionId]: '' }));
      charger();
    } catch (e: any) {
      toast.error(e?.message || 'Erreur lors de la déclaration');
    } finally {
      setDeclaringId(null);
    }
  };

  const [connectClientSecret, setConnectClientSecret] = useState<string | null>(null);

  const lancerPaiementStripeConnect = async (missionId: string) => {
    setConnectPayingId(missionId);
    try {
      const { data, error } = await supabase.functions.invoke('stripe-connect-pay-mission', {
        body: { mission_id: missionId },
      });
      if (error) throw error;
      if (data?.error) throw new Error(data.error);
      if (data?.url) {
        window.location.href = data.url;
        return;
      }
      if (data?.client_secret) {
        setConnectClientSecret(data.client_secret);
        return;
      }
      toast.error('Aucune URL de paiement reçue');
    } catch (e: any) {
      toast.error(e?.message || 'Erreur lors du paiement Stripe Connect');
    } finally {
      setConnectPayingId(null);
    }
  };

  const consulterRib = async (missionId: string) => {
    setRibLoadingId(missionId);
    try {
      const { data, error } = await supabase.rpc('fn_consulter_rib_soignant' as any, { p_mission_id: missionId });
      if (error) throw error;
      const result = data as any;
      if (result?.error) throw new Error(result.error);
      if (result?.s3_cle && result?.s3_bucket) {
        const { data: signedData } = await supabase.storage.from(result.s3_bucket).createSignedUrl(result.s3_cle, 300);
        if (signedData?.signedUrl) {
          window.open(signedData.signedUrl, '_blank');
          setRibCache(prev => ({ ...prev, [missionId]: result.nom_fichier || 'RIB consulté' }));
        } else {
          toast.error('Impossible de générer le lien de téléchargement');
        }
      } else {
        setRibCache(prev => ({ ...prev, [missionId]: result?.iban || String(result) }));
      }
    } catch (e: any) {
      toast.error(e?.message || 'Impossible de consulter le RIB');
    }
    setRibLoadingId(null);
  };

  if (loading) return <LayoutApp role="ADMIN_ETABLISSEMENT"><SkeletonDashboard /></LayoutApp>;

  const missionsAPayer = paiementsData?.missions_a_payer ?? [];
  const paiementsRecents = paiementsData?.paiements_recents ?? [];
  const paiementsFiltres = filtreStatutPaiement === 'PAYE'
    ? paiementsRecents.filter((p: any) => p.statut === 'DECLARE' || p.statut === 'CONFIRME')
    : filtreStatutPaiement === 'DECLARE'
    ? paiementsRecents.filter((p: any) => p.statut === 'DECLARE')
    : filtreStatutPaiement === 'CONTESTE'
    ? paiementsRecents.filter((p: any) => p.statut === 'CONTESTE')
    : paiementsRecents;

  const scrollToHistorique = () => {
    setTimeout(() => document.getElementById('historique-paiements')?.scrollIntoView({ behavior: 'smooth', block: 'start' }), 100);
  };

  const titreHistorique = filtreStatutPaiement === 'PAYE'
    ? 'Paiements déclarés / confirmés'
    : filtreStatutPaiement === 'DECLARE'
    ? 'Paiements en attente de confirmation'
    : filtreStatutPaiement === 'CONTESTE'
    ? 'Paiements contestés'
    : 'Historique des paiements';

  return (
    <LayoutApp role="ADMIN_ETABLISSEMENT">
      {showSuccessBanner && (
        <div className="mb-4 flex items-center gap-2 bg-success/10 border border-success/20 rounded-xl p-4 animate-in fade-in slide-in-from-top-2">
          <CheckCircle className="h-5 w-5 text-success shrink-0" />
          <div className="flex-1">
            <p className="text-sm font-semibold text-success">Paiement confirmé !</p>
            <p className="text-xs text-success/80">Votre paiement a été reçu. Le statut sera mis à jour sous quelques instants.</p>
          </div>
          <button onClick={() => { setShowSuccessBanner(false); charger(); }} className="text-xs text-success underline hover:no-underline">Rafraîchir</button>
        </div>
      )}

      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-xl font-bold text-foreground">💳 Facturation</h1>
          {etab?.paliers_commission && (
            <div className="flex items-center gap-2 mt-1">
              <Trophy className="h-4 w-4 text-primary" />
              <span className="text-sm text-muted-foreground">
                Palier <span className="font-semibold text-foreground">{etab.paliers_commission.nom}</span> — Commission : {etab.taux_commission_negocie ?? 15}%
              </span>
            </div>
          )}
          {etab?.est_secteur_public && (
            <span className="inline-flex items-center gap-1 text-xs font-semibold px-2 py-0.5 rounded-full bg-primary/10 text-primary mt-1">
              🏛️ Secteur public — Chorus Pro
            </span>
          )}
        </div>
        {etab?.paliers_commission && (
          <BadgePalier palierNom={etab.paliers_commission.nom} taux={etab.taux_commission_negocie ?? 15} />
        )}
      </div>

      <Tabs defaultValue={searchParams.get('tab') || 'paiements'} className="w-full">
        <TabsList className="w-full grid grid-cols-3 mb-6">
          <TabsTrigger value="paiements">💰 Paiements soignants</TabsTrigger>
          <TabsTrigger value="commissions">📄 Commissions Jolene</TabsTrigger>
          <TabsTrigger value="export">📊 Export comptable</TabsTrigger>
        </TabsList>

        {/* ===== ONGLET 1 : PAIEMENTS SOIGNANTS ===== */}
        <TabsContent value="paiements" className="flex flex-col">
          {/* Encart informatif collapsible */}
          <Collapsible className="mb-6 order-0">
            <CollapsibleTrigger className="flex items-center gap-2 text-sm font-medium text-primary hover:underline w-full">
              <Info className="h-4 w-4" />
              <span>Comment fonctionne le paiement ?</span>
              <ChevronDown className="h-4 w-4 ml-auto transition-transform [[data-state=open]>&]:rotate-180" />
            </CollapsibleTrigger>
            <CollapsibleContent>
              <div className="mt-3 rounded-xl border border-border bg-muted/30 p-4 text-xs text-muted-foreground space-y-3">
                <div>
                  <p className="font-semibold text-foreground mb-1">• Mission salariée (CDDU)</p>
                  <p>Vous payez le soignant directement (bulletin de paie). Déclarez le paiement ici avec la référence de virement. Le soignant confirme la réception. La commission Jolene est facturée séparément chaque mois.</p>
                </div>
                <div>
                  <p className="font-semibold text-foreground mb-1">• Mission libérale avec Stripe Connect</p>
                  <p>Cliquez sur « Payer via Stripe ». Le paiement est automatiquement réparti : le soignant reçoit ses honoraires, Jolene retient sa commission. Rien d'autre à faire.</p>
                </div>
                <div>
                  <p className="font-semibold text-foreground mb-1">• Mission libérale sans Stripe</p>
                  <p>Vous payez le soignant par virement sur base de sa note d'honoraires. Déclarez le paiement avec la référence. La commission Jolene est facturée séparément.</p>
                </div>
                <div className="border-t border-border pt-3 text-destructive font-medium">
                  ⚠️ Délai de paiement : 30 jours maximum après la fin de la mission. Au-delà de 60 jours d'impayé, la publication de nouvelles missions est suspendue.
                </div>
              </div>
            </CollapsibleContent>
          </Collapsible>

          {/* KPI — total à payer en priorité */}
          <div className="grid grid-cols-2 md:grid-cols-4 gap-3 mb-6">
            {missionsAPayer.length > 0 && (
              <div className="p-4 rounded-xl border-2 border-destructive/40 bg-destructive/5">
                <p className="text-2xl font-bold text-destructive">{fmt(missionsAPayer.reduce((s: number, m: any) => s + (m.net_a_payer || 0), 0))}</p>
                <p className="text-sm font-medium text-destructive">À payer</p>
                <p className="text-xs text-destructive/70 mt-1">{missionsAPayer.length} mission{missionsAPayer.length > 1 ? 's' : ''}</p>
              </div>
            )}
          </div>
          <div className="grid grid-cols-3 gap-3 mb-6">
            <button
              onClick={() => { setFiltreStatutPaiement(filtreStatutPaiement === 'PAYE' ? null : 'PAYE'); scrollToHistorique(); }}
              className={`text-left p-4 rounded-xl border-2 transition-all hover:shadow-md bg-card ${
                filtreStatutPaiement === 'PAYE' ? 'border-primary ring-2 ring-primary/20' : 'border-border'
              }`}
            >
              <p className="text-2xl font-bold text-foreground">{fmt(paiementsData?.total_paye ?? 0)}</p>
              <p className="text-sm text-muted-foreground">Total payé</p>
              <p className="text-xs mt-1 text-muted-foreground">{filtreStatutPaiement === 'PAYE' ? '🔍 Filtre actif' : 'Cliquez pour filtrer'}</p>
            </button>
            <button
              onClick={() => { setFiltreStatutPaiement(filtreStatutPaiement === 'DECLARE' ? null : 'DECLARE'); scrollToHistorique(); }}
              className={`text-left p-4 rounded-xl border-2 transition-all hover:shadow-md bg-card ${
                filtreStatutPaiement === 'DECLARE' ? 'border-warning ring-2 ring-warning/20' : 'border-border'
              }`}
            >
              <p className="text-2xl font-bold text-foreground">{fmt(paiementsData?.total_en_attente ?? 0)}</p>
              <p className="text-sm text-muted-foreground">En attente de confirmation</p>
              <p className="text-xs mt-1 text-muted-foreground">{filtreStatutPaiement === 'DECLARE' ? '🔍 Filtre actif' : 'Cliquez pour filtrer'}</p>
            </button>
            <button
              onClick={() => { setFiltreStatutPaiement(filtreStatutPaiement === 'CONTESTE' ? null : 'CONTESTE'); scrollToHistorique(); }}
              className={`text-left p-4 rounded-xl border-2 transition-all hover:shadow-md bg-card ${
                filtreStatutPaiement === 'CONTESTE' ? 'border-destructive ring-2 ring-destructive/20' : 'border-border'
              }`}
            >
              <p className="text-2xl font-bold text-foreground">{fmt(paiementsData?.total_conteste ?? 0)}</p>
              <p className="text-sm text-muted-foreground">Contesté</p>
              <p className="text-xs mt-1 text-muted-foreground">{filtreStatutPaiement === 'CONTESTE' ? '🔍 Filtre actif' : 'Cliquez pour filtrer'}</p>
            </button>
          </div>

          {/* Historique paiements */}
          <div className="card-base mb-6 order-2" id="historique-paiements">
            <div className="flex items-center justify-between mb-4">
              <h2 className="font-bold text-foreground">{titreHistorique}</h2>
              {filtreStatutPaiement && (
                <button onClick={() => setFiltreStatutPaiement(null)} className="text-xs text-primary hover:underline">
                  Voir tout ({paiementsRecents.length})
                </button>
              )}
            </div>
            {filtreStatutPaiement && paiementsFiltres.length === 0 ? (
              <div className="p-6 rounded-xl bg-success/10 text-center">
                <p className="text-lg font-semibold text-success">
                  {filtreStatutPaiement === 'CONTESTE' ? '✅ Aucun paiement contesté' :
                   filtreStatutPaiement === 'PAYE' ? 'Aucun paiement déclaré ou confirmé' :
                   'Aucun paiement en attente'}
                </p>
                <button onClick={() => setFiltreStatutPaiement(null)} className="text-sm text-primary hover:underline mt-2">
                  Voir tous les paiements
                </button>
              </div>
            ) : paiementsFiltres.length > 0 ? (
              <>
                {filtreStatutPaiement && (
                  <p className="text-xs text-muted-foreground mb-3">
                    {paiementsFiltres.length} résultat{paiementsFiltres.length > 1 ? 's' : ''}
                  </p>
                )}
                <div className="overflow-x-auto">
                  <table className="w-full text-sm">
                    <thead>
                      <tr className="border-b border-border text-left text-muted-foreground">
                        <th className="pb-2 font-medium">Date</th>
                        <th className="pb-2 font-medium">Soignant</th>
                        <th className="pb-2 font-medium">Mission</th>
                        <th className="pb-2 font-medium">Référence</th>
                        <th className="pb-2 font-medium">Méthode</th>
                        <th className="pb-2 font-medium text-right">Montant</th>
                        <th className="pb-2 font-medium text-right">Statut</th>
                      </tr>
                    </thead>
                    <tbody>
                      {paiementsFiltres.map((p: any) => (
                        <React.Fragment key={p.paiement_id}>
                          <tr className="border-b border-border/50">
                            <td className="py-2 text-muted-foreground">{p.date_paiement ? format(new Date(p.date_paiement), 'dd/MM/yyyy', { locale: fr }) : '—'}</td>
                            <td className="py-2 text-foreground">{p.soignant_nom || '—'}</td>
                            <td className="py-2">
                              {p.mission_id ? (
                                <button onClick={() => navigate(`/etablissement/missions/${p.mission_id}`)} className="text-primary hover:underline truncate max-w-[180px] block text-left">
                                  {p.mission_intitule || '—'}
                                </button>
                              ) : (
                                <span className="text-foreground truncate max-w-[180px] block">{p.mission_intitule || '—'}</span>
                              )}
                            </td>
                            <td className="py-2 text-xs text-muted-foreground">{p.reference_virement || '—'}</td>
                            <td className="py-2 text-muted-foreground">{p.methode || '—'}</td>
                            <td className="py-2 text-right font-medium">{fmt(p.montant_net ?? 0)}</td>
                            <td className="py-2 text-right">
                              <span className={`text-[10px] font-bold px-2 py-0.5 rounded-full ${PAIEMENT_STATUT_COLORS[p.statut] ?? 'bg-muted text-muted-foreground'}`}>
                                {PAIEMENT_STATUT_LABELS[p.statut] ?? p.statut}
                              </span>
                              {p.confirme_par_soignant && (
                                <span className="ml-1 text-[10px] text-success">✅ {p.confirme_par_soignant_le ? format(new Date(p.confirme_par_soignant_le), 'dd/MM', { locale: fr }) : ''}</span>
                              )}
                            </td>
                          </tr>
                          {p.statut === 'CONTESTE' && p.motif_contestation && (
                            <tr>
                              <td colSpan={7} className="py-1 px-2 text-xs text-destructive">
                                ⚠️ Motif : {p.motif_contestation}
                              </td>
                            </tr>
                          )}
                          {p.echeance_le && p.statut !== 'CONFIRME' && p.statut !== 'CONTESTE' && (
                            <tr>
                              <td colSpan={7} className="py-0.5 px-2 text-[10px] text-muted-foreground">
                                Échéance : {format(new Date(p.echeance_le), 'dd/MM/yyyy', { locale: fr })}
                              </td>
                            </tr>
                          )}
                        </React.Fragment>
                      ))}
                    </tbody>
                  </table>
                </div>
              </>
            ) : (
              <p className="text-sm text-muted-foreground text-center py-4">Aucun paiement enregistré.</p>
            )}
          </div>

          {/* Missions à payer — PRIORITÉ : en haut */}
          <div className="card-base mb-6 order-1">
            <div className="flex items-center justify-between mb-4">
              <h2 className="font-bold text-foreground flex items-center gap-2">
                <AlertTriangle className="h-4 w-4 text-warning" /> Missions à payer
              </h2>
              <span className="badge-base bg-warning/10 text-warning">{missionsAPayer.length}</span>
            </div>

            {missionsAPayer.length > 0 ? (
              <div className="space-y-3">
                {missionsAPayer.map((m: any) => {
                  const joursSinceFin = m.fin_le ? Math.floor((Date.now() - new Date(m.fin_le).getTime()) / 86400000) : 0;
                  const isStripeConnect = m.soignant_stripe_connect === true && m.type_paiement_soignant === 'NOTE_HONORAIRES';
                  const currentRef = declaringRef[m.mission_id] || '';
                  const trimmedRef = currentRef.trim();
                  const refTooShort = trimmedRef.length > 0 && trimmedRef.length < 5;
                  const refNoDigit = trimmedRef.length >= 5 && !/\d/.test(trimmedRef);

                  return (
                    <div key={m.mission_id} className="flex flex-col gap-3 p-3 rounded-lg border border-border/50 bg-background">
                      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
                        <div className="flex-1">
                          <p className="text-sm font-semibold text-foreground">{m.soignant_nom}</p>
                          <button
                            onClick={() => navigate(`/etablissement/missions/${m.mission_id}`)}
                            className="text-xs text-primary hover:underline text-left"
                          >
                            {m.intitule}
                          </button>
                          <div className="flex flex-wrap items-center gap-2 mt-1">
                            <span className="text-xs text-muted-foreground">
                              Fin : {m.fin_le ? format(new Date(m.fin_le), 'dd/MM/yyyy', { locale: fr }) : '—'}
                            </span>
                            <span className={`text-[10px] font-bold px-2 py-0.5 rounded-full ${
                              m.type_paiement_soignant === 'NOTE_HONORAIRES' ? 'bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-400' : 'bg-muted text-muted-foreground'
                            }`}>
                              {m.type_paiement_soignant === 'NOTE_HONORAIRES' ? "Note d'honoraires" : 'Bulletin de paie'}
                            </span>
                            {joursSinceFin >= 60 && (
                              <span className="text-[10px] font-bold px-2 py-0.5 rounded-full bg-destructive/10 text-destructive">🚫 Publication suspendue — Régularisez vos paiements</span>
                            )}
                            {joursSinceFin >= 30 && joursSinceFin < 60 && (
                              <span className="text-[10px] font-bold px-2 py-0.5 rounded-full bg-destructive/10 text-destructive">🔴 Retard de paiement ({joursSinceFin}j)</span>
                            )}
                            {joursSinceFin >= 15 && joursSinceFin < 30 && (
                              <span className="text-[10px] font-bold px-2 py-0.5 rounded-full bg-amber-100 text-amber-700 dark:bg-amber-900/30 dark:text-amber-400">⚠️ {joursSinceFin}j depuis fin de mission</span>
                            )}
                          </div>
                          {/* RIB soignant */}
                          {!isStripeConnect && m.type_paiement_soignant !== 'NOTE_HONORAIRES' && (
                            <div className="mt-1">
                              {ribCache[m.mission_id] ? (
                                <p className="text-[10px] text-success flex items-center gap-1">✅ {ribCache[m.mission_id]}</p>
                              ) : (
                                <button
                                  onClick={() => consulterRib(m.mission_id)}
                                  disabled={ribLoadingId === m.mission_id}
                                  className="text-[10px] text-primary hover:underline flex items-center gap-1"
                                >
                                  {ribLoadingId === m.mission_id ? <Loader2 className="h-3 w-3 animate-spin" /> : <FileText className="h-3 w-3" />}
                                  📄 Voir le RIB (PDF)
                                </button>
                              )}
                            </div>
                          )}
                        </div>
                        <span className="text-sm font-bold text-foreground">{fmt(m.net_a_payer ?? m.total_brut ?? 0)}</span>
                      </div>

                      {isStripeConnect ? (
                        <Button
                          size="sm"
                          onClick={() => lancerPaiementStripeConnect(m.mission_id)}
                          disabled={connectPayingId === m.mission_id}
                          className="gap-2 self-end"
                        >
                          {connectPayingId === m.mission_id ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <CreditCard className="h-3.5 w-3.5" />}
                          💳 Payer via Stripe
                        </Button>
                      ) : m.type_paiement_soignant === 'NOTE_HONORAIRES' && m.soignant_stripe_connect === false ? (
                        <>
                          <div className="rounded-lg border border-warning/30 bg-warning/5 p-3 text-xs text-muted-foreground space-y-1 w-full">
                            <p className="font-semibold text-warning flex items-center gap-1">
                              <AlertTriangle className="h-3.5 w-3.5" /> Ce soignant n'a pas encore finalisé son compte Stripe Connect.
                            </p>
                            <p>En attendant, vous pouvez le payer par virement et déclarer le paiement avec une référence.</p>
                            <p className="text-muted-foreground/70">Le soignant sera invité à finaliser son compte Stripe pour les prochaines missions.</p>
                          </div>
                          <div className="flex flex-col sm:flex-row items-end sm:items-center gap-2 w-full">
                            <div className="flex-1 w-full sm:w-auto space-y-1">
                              <input
                                type="text"
                                placeholder="Ex: VIR-2026-03-001"
                                value={currentRef}
                                onChange={e => setDeclaringRef(prev => ({ ...prev, [m.mission_id]: e.target.value }))}
                                className="flex h-9 w-full rounded-md border border-input bg-background px-3 py-1 text-sm ring-offset-background placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                              />
                              <p className="text-[10px] text-muted-foreground">Numéro de virement bancaire, référence de chèque ou numéro de facture</p>
                              {refTooShort && <p className="text-[10px] text-destructive">Minimum 5 caractères</p>}
                              {refNoDigit && <p className="text-[10px] text-destructive">La référence doit contenir au moins 1 chiffre</p>}
                            </div>
                            <Button
                              size="sm"
                              variant="outline"
                              onClick={() => declarerPaiementSoignant(m.mission_id, m.net_a_payer ?? m.total_brut ?? 0)}
                              disabled={declaringId === m.mission_id || !isRefValid(currentRef)}
                              className="gap-1 shrink-0"
                            >
                              {declaringId === m.mission_id ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Banknote className="h-3.5 w-3.5" />}
                              Déclarer le paiement
                            </Button>
                          </div>
                        </>
                      ) : (
                        <div className="flex flex-col sm:flex-row items-end sm:items-center gap-2">
                          <div className="flex-1 w-full sm:w-auto space-y-1">
                            <input
                              type="text"
                              placeholder="Ex: VIR-2026-03-001"
                              value={currentRef}
                              onChange={e => setDeclaringRef(prev => ({ ...prev, [m.mission_id]: e.target.value }))}
                              className="flex h-9 w-full rounded-md border border-input bg-background px-3 py-1 text-sm ring-offset-background placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                            />
                            <p className="text-[10px] text-muted-foreground">Numéro de virement bancaire, référence de chèque ou numéro de facture</p>
                            {refTooShort && (
                              <p className="text-[10px] text-destructive">Minimum 5 caractères</p>
                            )}
                            {refNoDigit && (
                              <p className="text-[10px] text-destructive">La référence doit contenir au moins 1 chiffre</p>
                            )}
                          </div>
                          <Button
                            size="sm"
                            variant="outline"
                            onClick={() => declarerPaiementSoignant(m.mission_id, m.net_a_payer ?? m.total_brut ?? 0)}
                            disabled={declaringId === m.mission_id || !isRefValid(currentRef)}
                            className="gap-1 shrink-0"
                          >
                            {declaringId === m.mission_id ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Banknote className="h-3.5 w-3.5" />}
                            Déclarer le paiement
                          </Button>
                        </div>
                      )}
                    </div>
                  );
                })}
              </div>
            ) : (
              <p className="text-sm text-muted-foreground text-center py-4">✅ Aucune mission en attente de paiement.</p>
            )}
          </div>
        </TabsContent>

        {/* ===== ONGLET 2 : COMMISSIONS JOLENE ===== */}
        <TabsContent value="commissions">
          {/* SEPA banner */}
          {etab?.mode_paiement_commission === 'SEPA_DEBIT' && (
            <div className="mb-6 flex items-center gap-3 p-4 rounded-xl bg-primary/5 border border-primary/20">
              <Building2 className="h-5 w-5 text-primary shrink-0" />
              <div>
                <p className="text-sm font-semibold text-foreground">Mandat SEPA enregistré 🏦</p>
                <p className="text-xs text-muted-foreground">Votre mandat SEPA est actif. Les commissions seront prélevées automatiquement lors de la facturation mensuelle.</p>
              </div>
            </div>
          )}

          {/* KPI commissions */}
          <div className="grid grid-cols-3 gap-3 mb-6">
            <button
              onClick={() => {
                setFiltreStatut(filtreStatut === 'EN_ATTENTE' ? null : 'EN_ATTENTE');
                document.getElementById('missions-non-facturees')?.scrollIntoView({ behavior: 'smooth' });
              }}
              className={`text-left p-4 rounded-xl border-2 transition-all hover:shadow-md bg-card ${
                filtreStatut === 'EN_ATTENTE' ? 'border-primary ring-2 ring-primary/20' : 'border-border'
              }`}
            >
              <p className="text-2xl font-bold text-foreground">{fmt(kpiCommissions.enAttente)}</p>
              <p className="text-sm text-muted-foreground">Total dû</p>
            </button>
            <button
              onClick={() => setFiltreStatut(filtreStatut === 'EN_COURS' ? null : 'EN_COURS')}
              className={`text-left p-4 rounded-xl border-2 transition-all hover:shadow-md bg-card ${
                filtreStatut === 'EN_COURS' ? 'border-warning ring-2 ring-warning/20' : 'border-border'
              }`}
            >
              <p className="text-2xl font-bold text-foreground">{fmt(kpiCommissions.enCours)}</p>
              <p className="text-sm text-muted-foreground">Factures en cours</p>
            </button>
            <button
              onClick={() => setFiltreStatut(filtreStatut === 'PAYEE' ? null : 'PAYEE')}
              className={`text-left p-4 rounded-xl border-2 transition-all hover:shadow-md bg-card ${
                filtreStatut === 'PAYEE' ? 'border-success ring-2 ring-success/20' : 'border-border'
              }`}
            >
              <p className="text-2xl font-bold text-foreground">{fmt(kpiCommissions.totalPaye)}</p>
              <p className="text-sm text-muted-foreground">Total payé</p>
            </button>
          </div>

          {paiementsData && (
            <div className="card-base mb-6 flex items-center gap-4">
              <div className="text-sm">
                <span className="text-muted-foreground">Total commissions HT : </span>
                <span className="font-semibold text-foreground">{fmt(paiementsData.commissions_ht ?? 0)}</span>
              </div>
              <div className="text-sm">
                <span className="text-muted-foreground">Total commissions TTC : </span>
                <span className="font-semibold text-foreground">{fmt(paiementsData.commissions_ttc ?? 0)}</span>
              </div>
            </div>
          )}

          {/* RIB Jolene pour paiement par virement */}
          <div className="card-base mb-6 bg-muted/30">
            <div className="flex items-start gap-3">
              <Building2 className="h-5 w-5 text-primary shrink-0 mt-0.5" />
              <div className="space-y-1">
                <p className="text-sm font-semibold text-foreground">🏦 Coordonnées bancaires Jolene SASU</p>
                {ENTREPRISE.iban && ENTREPRISE.iban !== 'FR76 XXXX XXXX XXXX XXXX XXXX XXX' ? (
                  <>
                    <p className="text-xs text-muted-foreground"><strong>IBAN :</strong> {ENTREPRISE.iban}</p>
                    <p className="text-xs text-muted-foreground"><strong>BIC :</strong> {ENTREPRISE.bic}</p>
                  </>
                ) : (
                  <p className="text-xs text-muted-foreground italic">Coordonnées bancaires disponibles prochainement</p>
                )}
                <p className="text-xs text-muted-foreground"><strong>Référence à indiquer :</strong> le numéro de facture</p>
              </div>
            </div>
          </div>

          {/* Missions non facturées */}
          <div id="missions-non-facturees" className="card-base mb-6">
            <div className="flex items-center justify-between mb-4">
              <h2 className="font-bold text-foreground">Missions terminées non facturées</h2>
              <span className="badge-base bg-warning/10 text-warning">{missionsNonFacturees.length} mission{missionsNonFacturees.length > 1 ? 's' : ''}</span>
            </div>

            {missionsNonFacturees.length > 0 ? (
              <>
                <div className="overflow-x-auto mb-4">
                  <table className="w-full text-sm">
                    <thead>
                      <tr className="border-b border-border text-left text-muted-foreground">
                        <th className="pb-2 font-medium">Date</th>
                        <th className="pb-2 font-medium">Intitulé</th>
                        <th className="pb-2 font-medium text-right">Commission HT</th>
                      </tr>
                    </thead>
                    <tbody>
                      {missionsNonFacturees.map(m => (
                        <tr key={m.id} className="border-b border-border/50">
                          <td className="py-2 text-muted-foreground">{m.fin_le ? format(new Date(m.fin_le), 'dd/MM/yyyy', { locale: fr }) : '—'}</td>
                          <td className="py-2">
                            <button onClick={() => navigate(`/etablissement/missions/${m.id}`)} className="text-primary hover:underline text-left">
                              {m.intitule}
                            </button>
                          </td>
                          <td className="py-2 text-right font-medium">{(m.montant_commission_ht ?? 0).toFixed(2)} €</td>
                        </tr>
                      ))}
                    </tbody>
                    <tfoot>
                      <tr className="font-bold">
                        <td colSpan={2} className="pt-3 text-right text-foreground">Total TTC</td>
                        <td className="pt-3 text-right text-primary">
                          {missionsNonFacturees.reduce((s, m) => s + (m.montant_commission_ttc ?? 0), 0).toFixed(2)} €
                        </td>
                      </tr>
                    </tfoot>
                  </table>
                </div>
                <button onClick={genererFactureMois} disabled={generating} className="btn-primary w-full flex items-center justify-center gap-2 disabled:opacity-50">
                  {generating ? <Loader2 className="h-4 w-4 animate-spin" /> : <FileText className="h-4 w-4" />}
                  Générer la facture du mois
                </button>
              </>
            ) : (
              <p className="text-sm text-muted-foreground text-center py-4">✅ Toutes les missions terminées ont été facturées.</p>
            )}
          </div>

          {/* Liste des factures */}
          <div id="liste-factures">
            <div className="flex items-center justify-between mb-3">
              <h2 className="font-bold text-foreground">
                {filtreStatut === 'EN_COURS' ? 'Factures en cours' : filtreStatut === 'PAYEE' ? 'Factures payées' : 'Factures'}
              </h2>
              {filtreStatut && (
                <button onClick={() => setFiltreStatut(null)} className="text-xs text-primary hover:underline">Voir toutes</button>
              )}
            </div>

            {(() => {
              const facturesFiltrees = filtreStatut === 'EN_COURS'
                ? factures.filter(f => f.statut === 'EMISE' || f.statut === 'EN_RETARD')
                : filtreStatut === 'PAYEE'
                ? factures.filter(f => f.statut === 'PAYEE')
                : factures;
              return facturesFiltrees.length > 0 ? (
                <div className="space-y-3">
                  {facturesFiltrees.map(f => (
                    <div key={f.id} className="card-base flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
                      <div className="flex-1">
                        <div className="flex items-center gap-2 mb-1">
                          <span className="font-semibold text-foreground">{f.numero_facture}</span>
                          <span className={`px-2 py-0.5 rounded-full text-[10px] font-bold ${STATUT_COLORS[f.statut] ?? STATUT_COLORS.BROUILLON}`}>
                            {STATUT_LABELS[f.statut] ?? f.statut}
                          </span>
                          {f.est_secteur_public && f.chorus_pro_statut && f.chorus_pro_statut !== 'NON_APPLICABLE' && (
                            <ChorusStatutBadge statut={f.chorus_pro_statut} />
                          )}
                        </div>
                        <div className="flex flex-wrap gap-3 text-xs text-muted-foreground">
                          <span>{f.nombre_missions ?? 0} mission{(f.nombre_missions ?? 0) > 1 ? 's' : ''}</span>
                          <span>HT: {(f.montant_ht ?? 0).toFixed(2)} €</span>
                          <span>TVA: {(f.montant_tva ?? 0).toFixed(2)} €</span>
                          <span className="font-semibold text-foreground">TTC: {(f.montant_ttc ?? 0).toFixed(2)} €</span>
                        </div>
                        {f.date_echeance && (
                          <p className="text-[10px] text-muted-foreground mt-1">
                            Échéance : {format(new Date(f.date_echeance), 'dd/MM/yyyy', { locale: fr })}
                          </p>
                        )}
                      </div>
                        <div className="flex flex-wrap gap-2 shrink-0">
                        <button onClick={() => navigate(`/etablissement/facturation/${f.id}`)} className="btn-secondary text-xs flex items-center gap-1">
                          <FileText className="h-3.5 w-3.5" /> Détail
                        </button>
                        {f.statut === 'VIREMENT_DECLARE' && (
                          <span className="text-xs text-amber-600 dark:text-amber-400 flex items-center gap-1">
                            <Clock className="h-3.5 w-3.5" /> En attente de vérification
                          </span>
                        )}
                        {(f.statut === 'EMISE' || f.statut === 'EN_RETARD') && (
                          <>
                            {f.est_secteur_public ? (
                              <div className="w-full mt-2 rounded-xl border border-primary/20 bg-primary/5 p-4 space-y-3">
                                <p className="text-sm font-semibold text-foreground flex items-center gap-2">
                                  🏛️ Paiement secteur public
                                </p>
                                <p className="text-xs text-muted-foreground">Cette facture sera déposée sur Chorus Pro.</p>
                                <FactureChorus facture={f} onUpdate={charger} />
                                {f.chorus_pro_numero_flux && (
                                  <p className="text-xs text-muted-foreground">Référence Chorus : {f.chorus_pro_numero_flux}</p>
                                )}
                              </div>
                            ) : (
                              <div className="w-full mt-2 space-y-4">
                                <p className="text-sm font-semibold text-foreground">Comment payer cette facture ?</p>
                                {/* Option 1 : Carte */}
                                <div className="rounded-xl border border-border p-4 space-y-2">
                                  <p className="text-sm font-semibold text-foreground">Option 1 : 💳 Payer par carte bancaire</p>
                                  <p className="text-xs text-muted-foreground">Paiement sécurisé par Stripe. Confirmation immédiate.</p>
                                  <button onClick={() => payerParCarte(f)} disabled={payingId === f.id} className="btn-primary text-xs flex items-center gap-1 disabled:opacity-50">
                                    {payingId === f.id ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <CreditCard className="h-3.5 w-3.5" />}
                                    Payer maintenant
                                  </button>
                                </div>
                                {/* Option 2 : Virement */}
                                <div className="rounded-xl border border-border p-4 space-y-2">
                                  <p className="text-sm font-semibold text-foreground">Option 2 : 🏦 Payer par virement bancaire</p>
                                  <div className="text-xs text-muted-foreground space-y-0.5 bg-muted/50 rounded-lg p-3">
                                    <p><strong>Bénéficiaire :</strong> {ENTREPRISE.nom}</p>
                                    {ENTREPRISE.iban && ENTREPRISE.iban !== 'FR76 XXXX XXXX XXXX XXXX XXXX XXX' ? (
                                      <>
                                        <p><strong>IBAN :</strong> {ENTREPRISE.iban}</p>
                                        <p><strong>BIC :</strong> {ENTREPRISE.bic}</p>
                                      </>
                                    ) : (
                                      <p className="italic">Coordonnées bancaires disponibles prochainement</p>
                                    )}
                                    <p><strong>Référence obligatoire :</strong> {f.numero_facture}</p>
                                  </div>
                                  <p className="text-[10px] text-muted-foreground">Délai de traitement : 2-3 jours ouvrés.</p>
                                  <PaiementVirement facture={f} onUpdate={charger} />
                                </div>
                              </div>
                            )}
                            <button onClick={() => rafraichirStatut(f.id)} disabled={refreshingId === f.id} className="btn-secondary text-xs flex items-center gap-1 disabled:opacity-50" title="Rafraîchir">
                              <RefreshCw className={`h-3.5 w-3.5 ${refreshingId === f.id ? 'animate-spin' : ''}`} />
                            </button>
                          </>
                        )}
                        {f.statut === 'PAYEE' && (
                          <button onClick={() => navigate(`/etablissement/facturation/${f.id}`)} className="btn-secondary text-xs flex items-center gap-1">
                            <Download className="h-3.5 w-3.5" /> PDF
                          </button>
                        )}
                      </div>
                    </div>
                  ))}
                </div>
              ) : (
                <EtatVide illustration={<IllustrationCalculatrice />} titre={filtreStatut ? 'Aucune facture dans cette catégorie' : 'Aucune facture'} sousTitre="Les factures seront générées après vos premières missions." />
              );
            })()}
          </div>

          {/* Historique SEPA */}
          {etab?.mode_paiement_commission === 'SEPA_DEBIT' && prelevements.length > 0 && (
            <div className="mt-6">
              <h2 className="font-bold text-foreground mb-3">🏦 Historique des prélèvements</h2>
              <div className="space-y-2">
                {prelevements.map((p: any) => (
                  <div key={p.id} className="card-base flex items-center justify-between">
                    <div>
                      <p className="text-sm font-medium text-foreground">{(p.missions as any)?.intitule || 'Mission'}</p>
                      <p className="text-xs text-muted-foreground">{p.capture_le ? format(new Date(p.capture_le), 'dd/MM/yyyy', { locale: fr }) : '—'}</p>
                    </div>
                    <div className="text-right">
                      <p className="text-sm font-semibold text-foreground">{(p.montant_ttc ?? 0).toFixed(2)} €</p>
                      <span className={`text-[10px] font-bold px-2 py-0.5 rounded-full ${p.statut === 'CAPTURE' ? 'bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-400' : 'bg-muted text-muted-foreground'}`}>
                        {p.statut === 'CAPTURE' ? 'Prélevé' : p.statut}
                      </span>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          )}
        </TabsContent>

        {/* ===== ONGLET 3 : EXPORT COMPTABLE ===== */}
        <TabsContent value="export">
          <div className="card-base space-y-4">
            <h2 className="font-bold text-foreground">Export comptable</h2>
            <p className="text-sm text-muted-foreground">Téléchargez vos données financières pour votre comptabilité.</p>
            <div className="flex flex-wrap gap-3">
              <Button variant="outline" className="gap-2" onClick={() => navigate('/etablissement/export-paie')}>
                <Download className="h-4 w-4" /> Export FEC / Paie
              </Button>
              <Button variant="outline" className="gap-2" onClick={() => {
                if (factures.length === 0) {
                  toast.info('Aucune facture à télécharger');
                  return;
                }
                factures.forEach(f => {
                  window.open(`/etablissement/facturation/${f.id}`, '_blank');
                });
              }}>
                <FileText className="h-4 w-4" /> Télécharger toutes les factures
              </Button>
            </div>
          </div>
        </TabsContent>
      </Tabs>

      {checkoutFactureId && (
        <StripeEmbeddedCheckout
          factureId={checkoutFactureId}
          open={!!checkoutFactureId}
          onClose={() => setCheckoutFactureId(null)}
          onComplete={() => { setCheckoutFactureId(null); charger(); }}
        />
      )}

      {/* Stripe Connect embedded checkout for mission payments */}
      {connectClientSecret && (
        <Dialog open={!!connectClientSecret} onOpenChange={(v) => { if (!v) { setConnectClientSecret(null); charger(); } }}>
          <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
            <DialogHeader>
              <DialogTitle>Paiement mission</DialogTitle>
              <DialogDescription>Réglez les honoraires du soignant et la commission Jolene.</DialogDescription>
            </DialogHeader>
            <EmbeddedCheckoutProvider stripe={stripePromise} options={{ clientSecret: connectClientSecret }}>
              <EmbeddedCheckout />
            </EmbeddedCheckoutProvider>
          </DialogContent>
        </Dialog>
      )}
    </LayoutApp>
  );
}
