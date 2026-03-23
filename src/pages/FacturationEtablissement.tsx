import React, { useState, useEffect } from 'react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { ENTREPRISE } from '@/constantes/entreprise';
import { SkeletonDashboard } from '@/components/SkeletonCard';
import { FadeInView } from '@/components/FadeInView';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { CreditCard, Clock, CheckCircle, FileText, Loader2, Trophy, RefreshCw, Building2 } from 'lucide-react';
import { LayoutApp } from '@/components/LayoutApp';
import { CarteKPI } from '@/components/CarteKPI';
import { ChargementPage } from '@/components/ChargementPage';
import { EtatVide, IllustrationCalculatrice } from '@/components/EtatVide';
import { BadgePalier } from '@/components/BadgePalier';
import { FactureChorus, ChorusStatutBadge } from '@/components/FactureChorus';
import { PaiementVirement } from '@/components/PaiementVirement';
import { useAuth } from '@/contexts/AuthContext';
import { useNotification } from '@/contexts/NotificationContext';
import { supabase } from '@/integrations/supabase/client';
import { extraireMessageErreur } from '@/lib/erreurs';

import { format } from 'date-fns';
import { fr } from 'date-fns/locale';

const STATUT_COLORS: Record<string, string> = {
  BROUILLON: 'bg-muted text-muted-foreground',
  EMISE: 'bg-primary/10 text-primary',
  PAYEE: 'bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-400',
  EN_RETARD: 'bg-destructive/10 text-destructive',
  ANNULEE: 'bg-muted text-muted-foreground line-through',
};

const STATUT_LABELS: Record<string, string> = {
  BROUILLON: 'Brouillon',
  EMISE: 'Émise',
  PAYEE: 'Payée',
  EN_RETARD: 'En retard',
  ANNULEE: 'Annulée',
};



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
  const [factures, setFactures] = useState<any[]>([]);
  const [missionsNonFacturees, setMissionsNonFacturees] = useState<any[]>([]);
  const [etab, setEtab] = useState<any>(null);
  const [kpi, setKpi] = useState({ enAttente: 0, enCours: 0, totalPaye: 0 });
  const [prelevements, setPrelevements] = useState<any[]>([]);
  const [showSuccessBanner, setShowSuccessBanner] = useState(false);

  // Detect payment success from URL
  useEffect(() => {
    if (searchParams.get('paiement') === 'succes') {
      setShowSuccessBanner(true);
      // Clean URL
      searchParams.delete('paiement');
      setSearchParams(searchParams, { replace: true });
      // Auto-hide after 8s
      const timer = setTimeout(() => setShowSuccessBanner(false), 8000);
      return () => clearTimeout(timer);
    }
  }, []);

  const charger = async () => {
    if (!user) return;

    const [resEtab, resFact, resMNF, resPrelev] = await Promise.all([
      supabase.from('etablissements').select('id, nom, type, taux_commission_negocie, palier_commission_id, groupe_sante_id, paliers_commission(nom), mode_paiement_commission').eq('id', user.id).single(),
      supabase.from('factures').select('id, numero_facture, statut, montant_ht, montant_tva, montant_ttc, taux_tva, nombre_missions, date_emission, date_echeance, date_paiement, est_secteur_public, mode_paiement, stripe_hosted_url, chorus_pro_statut, cree_le').eq('etablissement_id', user.id).order('cree_le', { ascending: false }),
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
    ]);

    if (resEtab.data) setEtab(resEtab.data);
    if (resFact.data) setFactures(resFact.data);
    if (resMNF.data) setMissionsNonFacturees(resMNF.data);
    if (resPrelev.data) setPrelevements(resPrelev.data);

    const facturesData = resFact.data ?? [];
    const enAttente = (resMNF.data ?? []).reduce((s: number, m: any) => s + (m.montant_commission_ttc ?? 0), 0);
    const enCours = facturesData.filter((f: any) => f.statut === 'EMISE' || f.statut === 'EN_RETARD').reduce((s: number, f: any) => s + (f.montant_ttc ?? 0), 0);
    const totalPaye = facturesData.filter((f: any) => f.statut === 'PAYEE').reduce((s: number, f: any) => s + (f.montant_ttc ?? 0), 0);
    setKpi({ enAttente, enCours, totalPaye });

    setLoading(false);
  };

  useEffect(() => { charger(); }, [user]);

  const genererFactureMois = async () => {
    if (!user || missionsNonFacturees.length === 0) return;
    setGenerating(true);

    try {
      const { data, error } = await supabase.rpc('fn_generer_facture_mensuelle');

      if (error) throw error;
      const result = data as any;
      if (!result?.success) throw new Error(result?.error || 'Erreur de génération');

      // Send email notification (non-blocking)
      supabase.functions.invoke('send-email', {
        body: {
          type: 'FACTURE_EMISE',
          data: {
            numero: result.numero_facture,
            montant_ttc: Number(result.montant_ttc).toFixed(2),
            facture_id: result.facture_id,
          },
          destinataire_id: user!.id,
        },
      }).catch(() => {});

      afficherNotification({ type: 'succes', message: `Facture ${result.numero_facture} générée avec succès !` });
      charger();
    } catch (err: any) {
      afficherNotification({ type: 'erreur', message: extraireMessageErreur(err) });
    } finally {
      setGenerating(false);
    }
  };

  const payerParCarte = async (facture: any) => {
    setPayingId(facture.id);
    try {
      const { data, error } = await supabase.functions.invoke('create-invoice-payment', {
        body: { facture_id: facture.id },
      });
      if (error) {
        // Try to extract the message from the error body
        const msg = typeof error === 'object' && error.message ? error.message : 'Erreur lors du paiement';
        throw new Error(msg);
      }
      if (data?.error) {
        throw new Error(data.error);
      }
      if (data?.url) {
        window.open(data.url, '_blank');
      } else {
        throw new Error('URL de paiement non reçue');
      }
    } catch (err: any) {
      afficherNotification({ type: 'erreur', message: extraireMessageErreur(err) });
    } finally {
      setPayingId(null);
    }
  };

  const rafraichirStatut = async (factureId: string) => {
    setRefreshingId(factureId);
    try {
      const { data, error } = await supabase
        .from('factures')
        .select('statut, date_paiement')
        .eq('id', factureId)
        .single();
      if (error) throw error;
      if (data) {
        setFactures(prev => prev.map(f => f.id === factureId ? { ...f, ...data } : f));
        if (data.statut === 'PAYEE') {
          afficherNotification({ type: 'succes', message: 'Statut mis à jour : Payée ✅' });
        } else {
          afficherNotification({ type: 'info', message: `Statut actuel : ${STATUT_LABELS[data.statut] ?? data.statut}` });
        }
      }
    } catch (err: any) {
      afficherNotification({ type: 'erreur', message: extraireMessageErreur(err) });
    } finally {
      setRefreshingId(null);
    }
  };

  if (loading) return <LayoutApp role="ADMIN_ETABLISSEMENT"><SkeletonDashboard /></LayoutApp>;

  return (
    <LayoutApp role="ADMIN_ETABLISSEMENT">
      {/* Success banner */}
      {showSuccessBanner && (
        <div className="mb-4 flex items-center gap-2 bg-success/10 border border-success/20 rounded-xl p-4 animate-in fade-in slide-in-from-top-2">
          <CheckCircle className="h-5 w-5 text-success shrink-0" />
          <div className="flex-1">
            <p className="text-sm font-semibold text-success">Paiement confirmé !</p>
            <p className="text-xs text-success/80">Votre paiement a été reçu. Le statut sera mis à jour sous quelques instants.</p>
          </div>
          <button onClick={() => { setShowSuccessBanner(false); charger(); }} className="text-xs text-success underline hover:no-underline">
            Rafraîchir
          </button>
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

      {/* SEPA banner */}
      {etab?.mode_paiement_commission === 'SEPA_DEBIT' && (
        <div className="mb-6 flex items-center gap-3 p-4 rounded-xl bg-primary/5 border border-primary/20">
          <Building2 className="h-5 w-5 text-primary shrink-0" />
          <div>
            <p className="text-sm font-semibold text-foreground">Prélèvement automatique activé 🏦</p>
            <p className="text-xs text-muted-foreground">Les commissions sont prélevées automatiquement après chaque mission terminée. Aucune action requise.</p>
          </div>
        </div>
      )}

      {/* KPI */}
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-3 mb-6">
        <FadeInView delay={0}>
          <div className="cursor-pointer" onClick={() => { const el = document.getElementById('missions-non-facturees'); el?.scrollIntoView({ behavior: 'smooth' }); }}>
            <CarteKPI icone={Clock} valeur={new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR', maximumFractionDigits: 0 }).format(kpi.enAttente)} label="Commissions en attente" couleurIcone="text-warning" couleurFond="bg-warning/10" />
          </div>
        </FadeInView>
        <FadeInView delay={100}>
          <div className="cursor-pointer" onClick={() => { const el = document.getElementById('liste-factures'); el?.scrollIntoView({ behavior: 'smooth' }); }}>
            <CarteKPI icone={FileText} valeur={new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR', maximumFractionDigits: 0 }).format(kpi.enCours)} label="Factures en cours" couleurIcone="text-primary" couleurFond="bg-primary/10" />
          </div>
        </FadeInView>
        <FadeInView delay={200}>
          <div className="cursor-pointer" onClick={() => { const el = document.getElementById('liste-factures'); el?.scrollIntoView({ behavior: 'smooth' }); }}>
            <CarteKPI icone={CheckCircle} valeur={new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR', maximumFractionDigits: 0 }).format(kpi.totalPaye)} label="Total payé" couleurIcone="text-success" couleurFond="bg-success/10" />
          </div>
        </FadeInView>
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

            <button
              onClick={genererFactureMois}
              disabled={generating}
              className="btn-primary w-full flex items-center justify-center gap-2 disabled:opacity-50"
            >
              {generating ? <Loader2 className="h-4 w-4 animate-spin" /> : <FileText className="h-4 w-4" />}
              Générer la facture du mois
            </button>
          </>
        ) : (
          <p className="text-sm text-muted-foreground text-center py-4">
            ✅ Toutes les missions terminées ont été facturées.
          </p>
        )}
      </div>

      {/* Liste des factures */}
      <div id="liste-factures">
        <h2 className="font-bold text-foreground mb-3">Factures</h2>

        {factures.length > 0 ? (
          <div className="space-y-3">
            {factures.map(f => (
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
                    {etab?.paliers_commission?.nom && (
                      <span>Palier : {etab.paliers_commission.nom}</span>
                    )}
                  </div>
                  {f.date_echeance && (
                    <p className="text-[10px] text-muted-foreground mt-1">
                      Échéance : {format(new Date(f.date_echeance), 'dd/MM/yyyy', { locale: fr })}
                    </p>
                  )}
                </div>

                <div className="flex flex-wrap gap-2 shrink-0">
                  <button
                    onClick={() => navigate(`/etablissement/facturation/${f.id}`)}
                    className="btn-secondary text-xs flex items-center gap-1"
                  >
                    <FileText className="h-3.5 w-3.5" /> Détail
                  </button>

                  {(f.statut === 'EMISE' || f.statut === 'EN_RETARD') && (
                    <>
                      {/* Chorus Pro for public sector */}
                      {f.est_secteur_public ? (
                        <FactureChorus facture={f} onUpdate={charger} />
                      ) : (
                        <>
                          <button
                            onClick={() => payerParCarte(f)}
                            disabled={payingId === f.id}
                            className="btn-primary text-xs flex items-center gap-1 disabled:opacity-50"
                          >
                            {payingId === f.id ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <CreditCard className="h-3.5 w-3.5" />}
                            Payer par carte
                          </button>

                          <PaiementVirement facture={f} onUpdate={charger} />
                        </>
                      )}

                      <button
                        onClick={() => rafraichirStatut(f.id)}
                        disabled={refreshingId === f.id}
                        className="btn-secondary text-xs flex items-center gap-1 disabled:opacity-50"
                        title="Rafraîchir le statut de paiement"
                      >
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
          <EtatVide illustration={<IllustrationCalculatrice />} titre="Aucune facture" sousTitre="Les factures seront générées automatiquement après vos premières missions." />
        )}
      </div>

      {/* Historique des prélèvements SEPA */}
      {etab?.mode_paiement_commission === 'SEPA_DEBIT' && prelevements.length > 0 && (
        <div className="mt-6">
          <h2 className="font-bold text-foreground mb-3">🏦 Historique des prélèvements</h2>
          <div className="space-y-2">
            {prelevements.map((p: any) => (
              <div key={p.id} className="card-base flex items-center justify-between">
                <div>
                  <p className="text-sm font-medium text-foreground">{(p.missions as any)?.intitule || 'Mission'}</p>
                  <p className="text-xs text-muted-foreground">
                    {p.capture_le ? format(new Date(p.capture_le), 'dd/MM/yyyy', { locale: fr }) : '—'}
                  </p>
                </div>
                <div className="text-right">
                  <p className="text-sm font-semibold text-foreground">{(p.montant_ttc ?? 0).toFixed(2)} €</p>
                  <span className={`text-[10px] font-bold px-2 py-0.5 rounded-full ${
                    p.statut === 'CAPTURE' ? 'bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-400' : 'bg-muted text-muted-foreground'
                  }`}>
                    {p.statut === 'CAPTURE' ? 'Prélevé' : p.statut}
                  </span>
                </div>
              </div>
            ))}
          </div>
        </div>
      )}
    </LayoutApp>
  );
}
