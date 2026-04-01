import React, { useState, useEffect } from 'react';
import { capturerErreurSentry } from '@/lib/sentry';
import { usePageTitle } from '@/hooks/usePageTitle';
import { SkeletonDashboard } from '@/components/SkeletonCard';
import { FadeInView } from '@/components/FadeInView';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { CreditCard, Clock, CheckCircle, FileText, Loader2, Trophy, RefreshCw, Building2, AlertTriangle, Download, Banknote } from 'lucide-react';
import { LayoutApp } from '@/components/LayoutApp';
import { CarteKPI } from '@/components/CarteKPI';
import { EtatVide, IllustrationCalculatrice } from '@/components/EtatVide';
import { BadgePalier } from '@/components/BadgePalier';
import { FactureChorus, ChorusStatutBadge } from '@/components/FactureChorus';
import { PaiementVirement } from '@/components/PaiementVirement';
import { StripeEmbeddedCheckout } from '@/components/StripeEmbeddedCheckout';
import { useAuth } from '@/contexts/AuthContext';
import { useNotification } from '@/contexts/NotificationContext';
import { supabase } from '@/integrations/supabase/client';
import { extraireMessageErreur } from '@/lib/erreurs';
import { Tabs, TabsList, TabsTrigger, TabsContent } from '@/components/ui/tabs';
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

    const enAttente = (resMNF.data ?? []).reduce((s: number, m: any) => s + (m.montant_commission_ttc ?? 0), 0);
    const enCours = facturesRpc.filter((f: any) => f.statut === 'EMISE' || f.statut === 'EN_RETARD').reduce((s: number, f: any) => s + (f.montant_ttc ?? 0), 0);
    const totalPaye = facturesRpc.filter((f: any) => f.statut === 'PAYEE').reduce((s: number, f: any) => s + (f.montant_ttc ?? 0), 0);
    setKpiCommissions({ enAttente, enCours, totalPaye });

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
    if (!ref) {
      toast.error('Veuillez saisir une référence de paiement');
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

  const lancerPaiementStripeConnect = async (missionId: string) => {
    setConnectPayingId(missionId);
    try {
      const { data, error } = await supabase.functions.invoke('stripe-connect-pay-mission', {
        body: { mission_id: missionId },
      });
      if (error) throw error;
      if (data?.error) throw new Error(data.error);
      if (data?.client_secret) {
        toast.success('Session de paiement créée — redirection…');
        // The StripeEmbeddedCheckout or redirect would be handled here
        // For now we use the return_url from the edge function
      }
      charger();
    } catch (e: any) {
      toast.error(e?.message || 'Erreur lors du paiement Stripe Connect');
    } finally {
      setConnectPayingId(null);
    }
  };

  if (loading) return <LayoutApp role="ADMIN_ETABLISSEMENT"><SkeletonDashboard /></LayoutApp>;

  const missionsAPayer = paiementsData?.missions_a_payer ?? [];
  const paiementsRecents = paiementsData?.paiements_recents ?? [];

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
        </div>
        {etab?.paliers_commission && (
          <BadgePalier palierNom={etab.paliers_commission.nom} taux={etab.taux_commission_negocie ?? 15} />
        )}
      </div>

      <Tabs defaultValue="paiements" className="w-full">
        <TabsList className="w-full grid grid-cols-3 mb-6">
          <TabsTrigger value="paiements">💰 Paiements soignants</TabsTrigger>
          <TabsTrigger value="commissions">📄 Commissions Jolene</TabsTrigger>
          <TabsTrigger value="export">📊 Export comptable</TabsTrigger>
        </TabsList>

        {/* ===== ONGLET 1 : PAIEMENTS SOIGNANTS ===== */}
        <TabsContent value="paiements">
          {/* KPI */}
          <div className="grid grid-cols-1 sm:grid-cols-3 gap-3 mb-6">
            <FadeInView delay={0}>
              <CarteKPI icone={Banknote} valeur={fmt(paiementsData?.total_paye ?? 0)} label="Total payé" couleurIcone="text-success" couleurFond="bg-success/10" />
            </FadeInView>
            <FadeInView delay={100}>
              <CarteKPI icone={Clock} valeur={fmt(paiementsData?.total_en_attente ?? 0)} label="En attente de confirmation" couleurIcone="text-warning" couleurFond="bg-warning/10" />
            </FadeInView>
            <FadeInView delay={200}>
              <CarteKPI icone={AlertTriangle} valeur={fmt(paiementsData?.total_conteste ?? 0)} label="Contesté" couleurIcone="text-destructive" couleurFond="bg-destructive/10" />
            </FadeInView>
          </div>

          {/* Missions à payer */}
          <div className="card-base mb-6">
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

                  return (
                    <div key={m.mission_id} className="flex flex-col gap-3 p-3 rounded-lg border border-border/50 bg-background">
                      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
                        <div className="flex-1">
                          <p className="text-sm font-semibold text-foreground">{m.soignant_nom}</p>
                          <p className="text-xs text-muted-foreground">{m.intitule}</p>
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
                      ) : (
                        <div className="flex flex-col sm:flex-row items-end sm:items-center gap-2">
                          <div className="flex-1 w-full sm:w-auto">
                            <input
                              type="text"
                              placeholder="Référence de paiement (obligatoire)"
                              value={declaringRef[m.mission_id] || ''}
                              onChange={e => setDeclaringRef(prev => ({ ...prev, [m.mission_id]: e.target.value }))}
                              className="flex h-9 w-full rounded-md border border-input bg-background px-3 py-1 text-sm ring-offset-background placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                            />
                          </div>
                          <Button
                            size="sm"
                            variant="outline"
                            onClick={() => declarerPaiementSoignant(m.mission_id, m.net_a_payer ?? m.total_brut ?? 0)}
                            disabled={declaringId === m.mission_id || !(declaringRef[m.mission_id]?.trim())}
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

          {/* Historique paiements */}
          <div className="card-base">
            <h2 className="font-bold text-foreground mb-4">Historique des paiements</h2>
            {paiementsRecents.length > 0 ? (
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
                    {paiementsRecents.map((p: any) => (
                      <React.Fragment key={p.paiement_id}>
                        <tr className="border-b border-border/50">
                          <td className="py-2 text-muted-foreground">{p.date_paiement ? format(new Date(p.date_paiement), 'dd/MM/yyyy', { locale: fr }) : '—'}</td>
                          <td className="py-2 text-foreground">{p.soignant_nom || '—'}</td>
                          <td className="py-2 text-foreground truncate max-w-[180px]">{p.mission_intitule || '—'}</td>
                          <td className="py-2 text-xs text-muted-foreground">{p.reference_virement || '—'}</td>
                          <td className="py-2 text-muted-foreground">{p.methode || '—'}</td>
                          <td className="py-2 text-right font-medium">{fmt(p.montant_net ?? 0)}</td>
                          <td className="py-2 text-right">
                            <span className={`text-[10px] font-bold px-2 py-0.5 rounded-full ${PAIEMENT_STATUT_COLORS[p.statut] ?? 'bg-muted text-muted-foreground'}`}>
                              {PAIEMENT_STATUT_LABELS[p.statut] ?? p.statut}
                            </span>
                            {p.confirme_par_soignant && (
                              <span className="ml-1 text-[10px] text-success">✅</span>
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
                      </React.Fragment>
                    ))}
                  </tbody>
                </table>
              </div>
            ) : (
              <p className="text-sm text-muted-foreground text-center py-4">Aucun paiement enregistré.</p>
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
                <p className="text-sm font-semibold text-foreground">Prélèvement automatique activé 🏦</p>
                <p className="text-xs text-muted-foreground">Les commissions sont prélevées automatiquement après chaque mission terminée.</p>
              </div>
            </div>
          )}

          {/* KPI commissions */}
          <div className="grid grid-cols-1 sm:grid-cols-3 gap-3 mb-6">
            <FadeInView delay={0}>
              <CarteKPI icone={Clock} valeur={fmt(kpiCommissions.enAttente)} label="Commissions en attente" couleurIcone="text-warning" couleurFond="bg-warning/10" />
            </FadeInView>
            <FadeInView delay={100}>
              <CarteKPI icone={FileText} valeur={fmt(kpiCommissions.enCours)} label="Factures en cours" couleurIcone="text-primary" couleurFond="bg-primary/10" />
            </FadeInView>
            <FadeInView delay={200}>
              <CarteKPI icone={CheckCircle} valeur={fmt(kpiCommissions.totalPaye)} label="Total payé" couleurIcone="text-success" couleurFond="bg-success/10" />
            </FadeInView>
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
                          <td className="py-2 text-foreground">{m.intitule}</td>
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
                              <FactureChorus facture={f} onUpdate={charger} />
                            ) : (
                              <>
                                <button onClick={() => payerParCarte(f)} disabled={payingId === f.id} className="btn-primary text-xs flex items-center gap-1 disabled:opacity-50">
                                  {payingId === f.id ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <CreditCard className="h-3.5 w-3.5" />}
                                  Payer par carte
                                </button>
                                <PaiementVirement facture={f} onUpdate={charger} />
                              </>
                            )}
                            <button onClick={() => rafraichirStatut(f.id)} disabled={refreshingId === f.id} className="btn-secondary text-xs flex items-center gap-1 disabled:opacity-50" title="Rafraîchir">
                              <RefreshCw className={`h-3.5 w-3.5 ${refreshingId === f.id ? 'animate-spin' : ''}`} />
                            </button>
                          </>
                        )}
                        {f.statut === 'PAYEE' && f.stripe_hosted_url && (
                          <a href={f.stripe_hosted_url} target="_blank" rel="noopener noreferrer" className="btn-secondary text-xs flex items-center gap-1">
                            <CheckCircle className="h-3.5 w-3.5" /> Reçu
                          </a>
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
                  if (f.stripe_hosted_url) window.open(f.stripe_hosted_url, '_blank');
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
    </LayoutApp>
  );
}
