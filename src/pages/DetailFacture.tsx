import React, { useState, useEffect } from 'react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { useNavigate, useParams } from 'react-router-dom';
import { ArrowLeft, Printer, CreditCard, Loader2, CheckCircle } from 'lucide-react';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { useAuth } from '@/contexts/AuthContext';
import { useNotification } from '@/contexts/NotificationContext';
import { supabase } from '@/integrations/supabase/client';
import { extraireMessageErreur } from '@/lib/erreurs';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';

const STATUT_LABELS: Record<string, string> = {
  BROUILLON: 'Brouillon', EMISE: 'Émise', PAYEE: 'Payée', EN_RETARD: 'En retard', ANNULEE: 'Annulée',
};

export default function DetailFacture() {
  usePageTitle('Détail facture');
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const { user } = useAuth();
  const { afficherNotification } = useNotification();
  const [loading, setLoading] = useState(true);
  const [paying, setPaying] = useState(false);
  const [facture, setFacture] = useState<any>(null);
  const [missions, setMissions] = useState<any[]>([]);
  const [etab, setEtab] = useState<any>(null);

  useEffect(() => {
    if (!user || !id) return;
    Promise.all([
      supabase.from('factures').select('id, numero_facture, montant_ht, montant_tva, montant_ttc, taux_tva, nombre_missions, statut, date_emission, date_echeance, date_paiement, periode_debut, periode_fin, mode_paiement, stripe_hosted_url, chorus_pro_statut, est_secteur_public, etablissement_id').eq('id', id).eq('etablissement_id', user.id).single(),
      supabase.from('missions')
        .select('id, intitule, debut_le, fin_le, montant_commission_ht')
        .eq('facture_id', id)
        .order('fin_le', { ascending: true }),
      supabase.from('etablissements').select('nom, siret, adresse_rue, adresse_ville, adresse_code_postal, taux_commission_negocie, paliers_commission(nom)').eq('id', user.id).single(),
    ]).then(([resF, resM, resE]) => {
      if (resF.data) setFacture(resF.data);
      if (resM.data) setMissions(resM.data);
      if (resE.data) setEtab(resE.data);
      setLoading(false);
    });
  }, [user, id]);

  const payerParCarte = async () => {
    if (!facture) return;

    const paymentWindow = window.open('', '_blank');
    if (paymentWindow) {
      paymentWindow.document.write('<p style="font-family: sans-serif; padding: 24px;">Redirection vers le paiement sécurisé…</p>');
      paymentWindow.document.close();
    }

    setPaying(true);
    try {
      const { data, error } = await supabase.functions.invoke('create-invoice-payment', {
        body: { facture_id: facture.id },
      });
      if (error) {
        throw new Error(typeof error === 'object' && error.message ? error.message : 'Erreur lors du paiement');
      }
      if (data?.error) {
        throw new Error(data.error);
      }
      if (!data?.url) {
        throw new Error('URL de paiement non reçue');
      }

      if (paymentWindow) {
        paymentWindow.location.href = data.url;
      } else {
        window.location.href = data.url;
      }
    } catch (err: any) {
      if (paymentWindow && !paymentWindow.closed) paymentWindow.close();
      afficherNotification({ type: 'erreur', message: extraireMessageErreur(err) });
    } finally {
      setPaying(false);
    }
  };

  if (loading) return <LayoutApp role="ADMIN_ETABLISSEMENT"><ChargementPage /></LayoutApp>;
  if (!facture) return <LayoutApp role="ADMIN_ETABLISSEMENT"><p className="text-center text-muted-foreground py-12">Facture introuvable.</p></LayoutApp>;

  return (
    <LayoutApp role="ADMIN_ETABLISSEMENT">
      {/* Print styles */}
      {/* Header */}
      <div className="flex items-center justify-between mb-6 no-print">
        <button onClick={() => navigate('/etablissement/facturation')} className="flex items-center gap-2 text-sm text-muted-foreground hover:text-foreground transition-colors">
          <ArrowLeft className="h-4 w-4" /> Retour
        </button>
        <div className="flex gap-2">
          <button onClick={() => window.print()} className="btn-secondary text-sm flex items-center gap-1.5">
            <Printer className="h-4 w-4" /> Imprimer
          </button>
          {(facture.statut === 'EMISE' || facture.statut === 'EN_RETARD') && (
            <button onClick={payerParCarte} disabled={paying} className="btn-primary text-sm flex items-center gap-1.5 disabled:opacity-50">
              {paying ? <Loader2 className="h-4 w-4 animate-spin" /> : <CreditCard className="h-4 w-4" />}
              Payer par carte
            </button>
          )}
        </div>
      </div>

      {/* Invoice */}
      <div className="card-base print-invoice print-full">
        {/* Header facture */}
        <div className="flex flex-col sm:flex-row justify-between gap-4 mb-8 pb-6 border-b border-border">
          <div>
            <h1 className="text-2xl font-black text-foreground">FACTURE</h1>
            <p className="text-lg font-bold text-primary mt-1">{facture.numero_facture}</p>
            <p className="text-sm text-muted-foreground mt-2">
              Émise le {facture.date_emission ? format(new Date(facture.date_emission), 'dd MMMM yyyy', { locale: fr }) : '—'}
            </p>
            {facture.date_echeance && (
              <p className="text-sm text-muted-foreground">
                Échéance : {format(new Date(facture.date_echeance), 'dd MMMM yyyy', { locale: fr })}
              </p>
            )}
          </div>
          <div className="text-right">
            <p className="text-sm font-bold text-foreground">Jolene SAS</p>
            <p className="text-xs text-muted-foreground">Plateforme de mise en relation</p>
            <p className="text-xs text-muted-foreground mt-2">Facturé à :</p>
            <p className="text-sm font-semibold text-foreground">{etab?.nom}</p>
            <p className="text-xs text-muted-foreground">{etab?.adresse_rue}</p>
            <p className="text-xs text-muted-foreground">{etab?.adresse_code_postal} {etab?.adresse_ville}</p>
            <p className="text-xs text-muted-foreground">SIRET : {etab?.siret}</p>
          </div>
        </div>

        {/* Status badge */}
        <div className="mb-6 flex items-center gap-2">
          <span className="text-sm text-muted-foreground">Statut :</span>
          <span className={`px-3 py-1 rounded-full text-xs font-bold ${
            facture.statut === 'PAYEE' ? 'bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-400' :
            facture.statut === 'EMISE' ? 'bg-primary/10 text-primary' :
            facture.statut === 'EN_RETARD' ? 'bg-destructive/10 text-destructive' :
            'bg-muted text-muted-foreground'
          }`}>
            {STATUT_LABELS[facture.statut] ?? facture.statut}
          </span>
          {etab?.paliers_commission && (
            <span className="text-xs text-muted-foreground ml-2">
              Commission au taux {(etab as any).paliers_commission.nom} ({etab.taux_commission_negocie ?? 15}%)
            </span>
          )}
        </div>

        {/* Missions table */}
        <div className="overflow-x-auto mb-6">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b-2 border-border text-left">
                <th className="pb-2 font-semibold text-foreground">Date</th>
                <th className="pb-2 font-semibold text-foreground">Intitulé</th>
                <th className="pb-2 font-semibold text-foreground text-right">Commission HT</th>
              </tr>
            </thead>
            <tbody>
              {missions.map(m => (
                <tr key={m.id} className="border-b border-border/50">
                  <td className="py-2.5 text-muted-foreground">
                    {m.fin_le ? format(new Date(m.fin_le), 'dd/MM/yyyy', { locale: fr }) : '—'}
                  </td>
                  <td className="py-2.5 text-foreground">{m.intitule}</td>
                  <td className="py-2.5 text-right font-medium">{(m.montant_commission_ht ?? 0).toFixed(2)} €</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>

        {/* Totals */}
        <div className="border-t-2 border-border pt-4 space-y-2 max-w-xs ml-auto">
          <div className="flex justify-between text-sm">
            <span className="text-muted-foreground">Total HT</span>
            <span className="font-medium text-foreground">{(facture.montant_ht ?? 0).toFixed(2)} €</span>
          </div>
          <div className="flex justify-between text-sm">
            <span className="text-muted-foreground">TVA ({facture.taux_tva ?? 20}%)</span>
            <span className="font-medium text-foreground">{(facture.montant_tva ?? 0).toFixed(2)} €</span>
          </div>
          <div className="flex justify-between text-lg font-bold border-t border-border pt-2">
            <span className="text-foreground">Total TTC</span>
            <span className="text-primary">{(facture.montant_ttc ?? 0).toFixed(2)} €</span>
          </div>
        </div>

        {/* Payment info */}
        {facture.statut === 'PAYEE' && facture.date_paiement && (
          <div className="mt-6 flex items-center gap-2 bg-success/10 border border-success/20 rounded-xl p-3">
            <CheckCircle className="h-4 w-4 text-success shrink-0" />
            <p className="text-sm text-success">
              Payée le {format(new Date(facture.date_paiement), 'dd MMMM yyyy', { locale: fr })}
            </p>
          </div>
        )}

        {/* Footer */}
        <div className="mt-8 pt-4 border-t border-border text-[10px] text-muted-foreground text-center">
          <p>Jolene SAS — Plateforme de mise en relation soignants-établissements</p>
          <p>Facture générée automatiquement — Commission sur missions terminées</p>
        </div>
      </div>
    </LayoutApp>
  );
}
