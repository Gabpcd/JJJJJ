import React, { useState, useEffect } from 'react';
import { ENTREPRISE } from '@/constantes/entreprise';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { CreditCard, Clock, CheckCircle, FileText, Loader2, Trophy, RefreshCw, FlaskConical } from 'lucide-react';
import { LayoutApp } from '@/components/LayoutApp';
import { CarteKPI } from '@/components/CarteKPI';
import { ChargementPage } from '@/components/ChargementPage';
import { EtatVide } from '@/components/EtatVide';
import { BadgePalier } from '@/components/BadgePalier';
import { FactureChorus } from '@/components/FactureChorus';
import { PaiementVirement } from '@/components/PaiementVirement';
import { useAuth } from '@/contexts/AuthContext';
import { useNotification } from '@/contexts/NotificationContext';
import { supabase } from '@/integrations/supabase/client';
import { extraireMessageErreur } from '@/lib/erreurs';
import { emailFactureMensuelle } from '@/lib/emailTemplates';
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

const IS_PREVIEW = window.location.hostname.includes('lovable.app') || window.location.hostname === 'localhost';

export default function FacturationEtablissement() {
  const navigate = useNavigate();
  const [searchParams, setSearchParams] = useSearchParams();
  const { user } = useAuth();
  const { afficherNotification } = useNotification();
  const [loading, setLoading] = useState(true);
  const [generating, setGenerating] = useState(false);
  const [payingId, setPayingId] = useState<string | null>(null);
  const [simulatingId, setSimulatingId] = useState<string | null>(null);
  const [refreshingId, setRefreshingId] = useState<string | null>(null);
  const [factures, setFactures] = useState<any[]>([]);
  const [missionsNonFacturees, setMissionsNonFacturees] = useState<any[]>([]);
  const [etab, setEtab] = useState<any>(null);
  const [kpi, setKpi] = useState({ enAttente: 0, enCours: 0, totalPaye: 0 });
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

    const [resEtab, resFact, resMNF] = await Promise.all([
      supabase.from('etablissements').select('*, paliers_commission(nom, taux_commission)').eq('id', user.id).single(),
      supabase.from('factures').select('*').eq('etablissement_id', user.id).order('cree_le', { ascending: false }),
      supabase.from('missions')
        .select('id, intitule, debut_le, fin_le, net_a_payer, montant_commission_ht, montant_commission_tva, montant_commission_ttc, taux_commission, statut')
        .eq('etablissement_id', user.id)
        .eq('statut', 'TERMINEE')
        .eq('commission_facturee', false)
        .order('fin_le', { ascending: false }),
    ]);

    if (resEtab.data) setEtab(resEtab.data);
    if (resFact.data) setFactures(resFact.data);
    if (resMNF.data) setMissionsNonFacturees(resMNF.data);

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
      const { data: numFacture } = await supabase.rpc('fn_generer_numero_facture');

      const totalHT = missionsNonFacturees.reduce((s, m) => s + (m.montant_commission_ht ?? 0), 0);
      const totalTVA = missionsNonFacturees.reduce((s, m) => s + (m.montant_commission_tva ?? 0), 0);
      const totalTTC = missionsNonFacturees.reduce((s, m) => s + (m.montant_commission_ttc ?? 0), 0);

      const now = new Date();
      const debutMois = new Date(now.getFullYear(), now.getMonth(), 1);
      const finMois = new Date(now.getFullYear(), now.getMonth() + 1, 0);

      const { data: facture, error: errFacture } = await supabase
        .from('factures')
        .insert({
          etablissement_id: user.id,
          numero_facture: numFacture ?? `SD-${format(now, 'yyyyMM')}-0001`,
          montant_ht: Math.round(totalHT * 100) / 100,
          montant_tva: Math.round(totalTVA * 100) / 100,
          montant_ttc: Math.round(totalTTC * 100) / 100,
          nombre_missions: missionsNonFacturees.length,
          periode_debut: format(debutMois, 'yyyy-MM-dd'),
          periode_fin: format(finMois, 'yyyy-MM-dd'),
          date_emission: now.toISOString(),
          date_echeance: new Date(now.getTime() + 30 * 86400000).toISOString().split('T')[0],
          statut: 'EMISE',
        } as any)
        .select()
        .single();

      if (errFacture) throw errFacture;

      const missionIds = missionsNonFacturees.map(m => m.id);
      await supabase
        .from('missions')
        .update({ commission_facturee: true, facture_id: facture.id, modifie_le: new Date().toISOString() } as any)
        .in('id', missionIds);

      await supabase.rpc('fn_ecrire_audit', {
        p_acteur_id: user.id, p_type_acteur: 'ADMIN_ETABLISSEMENT', p_action: 'FACTURE_GENEREE',
        p_type_ressource: 'facture', p_id_ressource: facture.id, p_cle_s3: null,
        p_details: { numero: facture.numero_facture, montant_ttc: totalTTC, nb_missions: missionIds.length },
        p_ip: null, p_navigateur: navigator.userAgent,
      });

      // Email facture
      supabase.functions.invoke('send-email', {
        body: {
          to: user!.email,
          subject: `Facture ${facture.numero_facture} — Soin Direct`,
          html: emailFactureMensuelle(etablissement?.nom || '', facture.numero_facture, totalTTC.toFixed(2), facture.id),
          type: 'FACTURE_GENEREE',
          destinataire_id: user!.id,
        },
      }).catch(() => {});

      afficherNotification({ type: 'succes', message: `Facture ${facture.numero_facture} générée avec succès !` });
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
      if (error) throw error;
      if (data?.url) window.open(data.url, '_blank');
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

  const simulerPaiement = async (facture: any) => {
    setSimulatingId(facture.id);
    try {
      const { error } = await supabase
        .from('factures')
        .update({
          statut: 'PAYEE',
          date_paiement: new Date().toISOString(),
          modifie_le: new Date().toISOString(),
        } as any)
        .eq('id', facture.id);
      if (error) throw error;

      await supabase.rpc('fn_ecrire_audit', {
        p_acteur_id: user!.id, p_type_acteur: 'ADMIN_ETABLISSEMENT', p_action: 'FINANCE_FACTURE_PAYEE',
        p_type_ressource: 'facture', p_id_ressource: facture.id, p_cle_s3: null,
        p_details: { numero_facture: facture.numero_facture, montant_ttc: facture.montant_ttc, mode: 'SIMULATION_DEV' },
        p_ip: null, p_navigateur: navigator.userAgent,
      });

      afficherNotification({ type: 'succes', message: `🧪 Paiement simulé pour ${facture.numero_facture}` });
      charger();
    } catch (err: any) {
      afficherNotification({ type: 'erreur', message: extraireMessageErreur(err) });
    } finally {
      setSimulatingId(null);
    }
  };

  if (loading) return <LayoutApp role="ETABLISSEMENT"><ChargementPage /></LayoutApp>;

  return (
    <LayoutApp role="ETABLISSEMENT">
      {/* Success banner */}
      {showSuccessBanner && (
        <div className="mb-4 flex items-center gap-2 bg-green-50 dark:bg-green-950/30 border border-green-200 dark:border-green-800 rounded-xl p-4 animate-in fade-in slide-in-from-top-2">
          <CheckCircle className="h-5 w-5 text-green-600 shrink-0" />
          <div className="flex-1">
            <p className="text-sm font-semibold text-green-700 dark:text-green-400">Paiement confirmé !</p>
            <p className="text-xs text-green-600 dark:text-green-500">Votre paiement a été reçu. Le statut sera mis à jour sous quelques instants.</p>
          </div>
          <button onClick={() => { setShowSuccessBanner(false); charger(); }} className="text-xs text-green-700 dark:text-green-400 underline hover:no-underline">
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

      {/* KPI */}
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-3 mb-6">
        <CarteKPI icone={Clock} valeur={`${kpi.enAttente.toFixed(0)} €`} label="Commissions en attente" couleurIcone="text-warning" couleurFond="bg-warning/10" />
        <CarteKPI icone={FileText} valeur={`${kpi.enCours.toFixed(0)} €`} label="Factures en cours" couleurIcone="text-primary" couleurFond="bg-primary/10" />
        <CarteKPI icone={CheckCircle} valeur={`${kpi.totalPaye.toFixed(0)} €`} label="Total payé" couleurIcone="text-green-600" couleurFond="bg-green-100 dark:bg-green-900/20" />
      </div>

      {/* Missions non facturées */}
      <div className="card-base mb-6">
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
                    <th className="pb-2 font-medium text-right">Net soignant</th>
                    <th className="pb-2 font-medium text-right">Commission HT</th>
                  </tr>
                </thead>
                <tbody>
                  {missionsNonFacturees.map(m => (
                    <tr key={m.id} className="border-b border-border/50">
                      <td className="py-2 text-muted-foreground">{m.fin_le ? format(new Date(m.fin_le), 'dd/MM/yyyy', { locale: fr }) : '—'}</td>
                      <td className="py-2 text-foreground">{m.intitule}</td>
                      <td className="py-2 text-right">{(m.net_a_payer ?? 0).toFixed(2)} €</td>
                      <td className="py-2 text-right font-medium">{(m.montant_commission_ht ?? 0).toFixed(2)} €</td>
                    </tr>
                  ))}
                </tbody>
                <tfoot>
                  <tr className="font-bold">
                    <td colSpan={3} className="pt-3 text-right text-foreground">Total TTC</td>
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
      <div>
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
                  </div>
                  <div className="flex flex-wrap gap-3 text-xs text-muted-foreground">
                    <span>{f.nombre_missions ?? 0} mission{(f.nombre_missions ?? 0) > 1 ? 's' : ''}</span>
                    <span>HT: {(f.montant_ht ?? 0).toFixed(2)} €</span>
                    <span>TVA: {(f.montant_tva ?? 0).toFixed(2)} €</span>
                    <span className="font-semibold text-foreground">TTC: {(f.montant_ttc ?? 0).toFixed(2)} €</span>
                    {f.taux_commission && (
                      <span>Commission au taux {etab?.paliers_commission?.nom ?? 'standard'} ({etab?.taux_commission_negocie ?? 15}%)</span>
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

                      {IS_PREVIEW && (
                        <button
                          onClick={() => simulerPaiement(f)}
                          disabled={simulatingId === f.id}
                          className="text-xs flex items-center gap-1 px-2 py-1 rounded-lg border border-dashed border-yellow-400 text-yellow-700 dark:text-yellow-400 bg-yellow-50 dark:bg-yellow-950/30 hover:bg-yellow-100 dark:hover:bg-yellow-900/40 disabled:opacity-50 transition-colors"
                        >
                          {simulatingId === f.id ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <FlaskConical className="h-3.5 w-3.5" />}
                          Simuler
                        </button>
                      )}
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
          <EtatVide icone={FileText} titre="Aucune facture" sousTitre="Les factures apparaîtront ici une fois générées" />
        )}
      </div>
    </LayoutApp>
  );
}
