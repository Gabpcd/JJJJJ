import React, { useState, useEffect, useCallback } from 'react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { useSearchParams } from 'react-router-dom';
import { LayoutApp } from '@/components/LayoutApp';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { ChargementPage } from '@/components/ChargementPage';
import { CarteKPI } from '@/components/CarteKPI';
import { Button } from '@/components/ui/button';
import { CreditCard, ExternalLink, RefreshCw, Loader2, CheckCircle, Clock, AlertTriangle, Banknote } from 'lucide-react';
import { toast } from 'sonner';

const formatEur = (v: number) =>
  new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(v);

type ConnectStatut = 'NON_DEMANDE' | 'EN_COURS' | 'COMPLET' | 'SUSPENDU';

export default function PageStripeConnect() {
  usePageTitle('Mon compte de paiement');
  const { user } = useAuth();
  const [searchParams] = useSearchParams();
  const [loading, setLoading] = useState(true);
  const [statut, setStatut] = useState<ConnectStatut>('NON_DEMANDE');
  const [ibanLast4, setIbanLast4] = useState<string | null>(null);
  const [revenus, setRevenus] = useState<{ mois_en_cours: number; total: number; en_attente: number } | null>(null);
  const [actionLoading, setActionLoading] = useState(false);

  const chargerStatut = useCallback(async () => {
    const { data } = await supabase.functions.invoke('stripe-connect-status');
    if (data) {
      setStatut(data.statut || 'NON_DEMANDE');
      setIbanLast4(data.iban_last4 || null);
    }
  }, []);

  const chargerRevenus = useCallback(async () => {
    const { data } = await supabase.rpc('fn_mes_revenus_connect' as any);
    if (data) setRevenus(data as any);
  }, []);

  useEffect(() => {
    if (!user) return;
    const init = async () => {
      setLoading(true);
      await chargerStatut();
      await chargerRevenus();
      setLoading(false);
    };
    init();
  }, [user, chargerStatut, chargerRevenus]);

  // Auto-refresh on ?success=true
  useEffect(() => {
    if (searchParams.get('success') === 'true') {
      chargerStatut().then(() => {
        toast.success('Statut mis à jour !');
      });
    }
  }, [searchParams, chargerStatut]);

  const lancerOnboarding = async () => {
    setActionLoading(true);
    const { data, error } = await supabase.functions.invoke('stripe-connect-onboard');
    if (error || !data?.url) {
      toast.error('Erreur lors de la connexion à Stripe');
      setActionLoading(false);
      return;
    }
    window.open(data.url, '_blank');
    setActionLoading(false);
  };

  const rafraichirStatut = async () => {
    setActionLoading(true);
    await chargerStatut();
    await chargerRevenus();
    setActionLoading(false);
    toast.success('Statut actualisé');
  };

  if (loading) return <ChargementPage />;

  return (
    <LayoutApp role="SOIGNANT">
      <div className="max-w-2xl mx-auto space-y-6">
        {/* NON_DEMANDE */}
        {statut === 'NON_DEMANDE' && (
          <div className="card-base text-center space-y-4 py-8">
            <CreditCard className="h-12 w-12 text-primary mx-auto" />
            <h2 className="text-lg font-bold text-foreground">Recevez vos paiements directement</h2>
            <p className="text-sm text-muted-foreground max-w-md mx-auto">
              Connectez votre compte bancaire via Stripe pour recevoir vos paiements de missions directement, sans délai.
            </p>
            <Button onClick={lancerOnboarding} disabled={actionLoading} className="gap-2">
              {actionLoading ? <Loader2 className="h-4 w-4 animate-spin" /> : <ExternalLink className="h-4 w-4" />}
              Connecter mon compte
            </Button>
          </div>
        )}

        {/* EN_COURS */}
        {statut === 'EN_COURS' && (
          <div className="card-base space-y-4">
            <div className="flex items-start gap-3">
              <Clock className="h-5 w-5 text-warning shrink-0 mt-0.5" />
              <div>
                <p className="font-semibold text-foreground">⏳ Onboarding en cours</p>
                <p className="text-sm text-muted-foreground mt-1">
                  Complétez votre profil Stripe pour activer les paiements directs.
                </p>
              </div>
            </div>
            <Button onClick={lancerOnboarding} disabled={actionLoading} variant="outline" className="gap-2">
              {actionLoading ? <Loader2 className="h-4 w-4 animate-spin" /> : <ExternalLink className="h-4 w-4" />}
              Reprendre l'inscription
            </Button>
          </div>
        )}

        {/* COMPLET */}
        {statut === 'COMPLET' && (
          <>
            <div className="card-base space-y-3">
              <div className="flex items-center gap-3">
                <CheckCircle className="h-5 w-5 text-success" />
                <div>
                  <p className="font-semibold text-foreground">✅ Compte connecté</p>
                  {ibanLast4 && (
                    <p className="text-sm text-muted-foreground">IBAN ****{ibanLast4}</p>
                  )}
                </div>
              </div>
              <Button onClick={rafraichirStatut} disabled={actionLoading} variant="outline" size="sm" className="gap-2">
                {actionLoading ? <Loader2 className="h-4 w-4 animate-spin" /> : <RefreshCw className="h-4 w-4" />}
                Actualiser le statut
              </Button>
            </div>

            {revenus && (
              <div className="grid grid-cols-3 gap-3">
                <CarteKPI
                  icone={Banknote}
                  valeur={formatEur(revenus.mois_en_cours)}
                  label="Ce mois"
                  couleurIcone="text-success"
                  couleurFond="bg-success/10"
                />
                <CarteKPI
                  icone={Banknote}
                  valeur={formatEur(revenus.total)}
                  label="Total reçu"
                  couleurIcone="text-primary"
                  couleurFond="bg-primary/10"
                />
                <CarteKPI
                  icone={Clock}
                  valeur={formatEur(revenus.en_attente)}
                  label="En attente"
                  couleurIcone="text-warning"
                  couleurFond="bg-warning/10"
                />
              </div>
            )}
          </>
        )}

        {/* SUSPENDU */}
        {statut === 'SUSPENDU' && (
          <div className="card-base border-destructive/30 bg-destructive/5 space-y-4">
            <div className="flex items-start gap-3">
              <AlertTriangle className="h-5 w-5 text-destructive shrink-0 mt-0.5" />
              <div>
                <p className="font-semibold text-destructive">⚠️ Compte suspendu</p>
                <p className="text-sm text-muted-foreground mt-1">
                  Des informations sont requises pour réactiver votre compte. Cliquez ci-dessous pour compléter votre profil Stripe.
                </p>
              </div>
            </div>
            <Button onClick={lancerOnboarding} disabled={actionLoading} variant="destructive" className="gap-2">
              {actionLoading ? <Loader2 className="h-4 w-4 animate-spin" /> : <ExternalLink className="h-4 w-4" />}
              Compléter mon profil
            </Button>
          </div>
        )}
      </div>
    </LayoutApp>
  );
}
