import React, { useState, useEffect, useCallback } from 'react';
import { capturerErreurSentry } from '@/lib/sentry';
import { usePageTitle } from '@/hooks/usePageTitle';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { LayoutApp } from '@/components/LayoutApp';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { ChargementPage } from '@/components/ChargementPage';
import { CarteKPI } from '@/components/CarteKPI';
import { Button } from '@/components/ui/button';
import { CreditCard, ExternalLink, RefreshCw, Loader2, CheckCircle, Clock, AlertTriangle, Banknote, Building2, FileText, ArrowRight, Shield, Info } from 'lucide-react';
import { toast } from 'sonner';

const formatEur = (v: number) =>
  new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(v);

type ConnectStatut = 'NON_DEMANDE' | 'EN_COURS' | 'COMPLET' | 'SUSPENDU' | 'SUPPRIME';
type TypeExercice = 'SALARIE' | 'LIBERAL' | 'MIXTE' | null;

export default function PageStripeConnect() {
  usePageTitle('Paiements');
  const navigate = useNavigate();
  const { user } = useAuth();
  const [searchParams] = useSearchParams();
  const [loading, setLoading] = useState(true);
  const [statut, setStatut] = useState<ConnectStatut>('NON_DEMANDE');
  const [ibanLast4, setIbanLast4] = useState<string | null>(null);
  const [revenus, setRevenus] = useState<{ mois_en_cours: number; total: number; en_attente: number } | null>(null);
  const [actionLoading, setActionLoading] = useState(false);
  const [typeExercice, setTypeExercice] = useState<TypeExercice>(null);
  const [soignantNom, setSoignantNom] = useState('');

  const chargerStatut = useCallback(async (forceRefresh = false) => {
    try {
      // [CP-STRIPE-6 H10] `?force=true` bypass le cache 5 min côté edge function
      const { data } = await supabase.functions.invoke(
        forceRefresh ? 'stripe-connect-status?force=true' : 'stripe-connect-status'
      );
      if (data) {
        setStatut(data.statut || 'NON_DEMANDE');
        setIbanLast4(data.iban_last4 || null);
      }
    } catch {
      // Not LIBERAL or function unavailable — OK
    }
  }, []);

  const chargerRevenus = useCallback(async () => {
    try {
      const { data } = await supabase.rpc('fn_mes_revenus_connect' as any);
      if (data) setRevenus(data as any);
    } catch {
      // Function may not exist
    }
  }, []);

  useEffect(() => {
    if (!user) return;
    const init = async () => {
      setLoading(true);
      // Load soignant type first
      const { data: sg } = await supabase.from('soignants')
        .select('prenom, nom, type_exercice, statut_liberal')
        .eq('id', user.id).maybeSingle();

      if (sg) {
        setTypeExercice((sg.type_exercice as TypeExercice) || 'SALARIE');
        setSoignantNom(`${sg.prenom} ${sg.nom}`);

        // Only load Stripe data if LIBERAL or MIXTE
        if (sg.type_exercice === 'LIBERAL' || sg.type_exercice === 'MIXTE' || sg.statut_liberal === 'ACTIF') {
          await chargerStatut();
          await chargerRevenus();
        }
      }
      setLoading(false);
    };
    init();
  }, [user, chargerStatut, chargerRevenus]);

  useEffect(() => {
    if (searchParams.get('success') === 'true') {
      chargerStatut().then(() => {
        toast.success('Statut mis à jour !');
      });
    }
  }, [searchParams, chargerStatut]);

  const lancerOnboarding = async () => {
    if (!isLiberal) {
      toast.info('Stripe Connect est disponible pour les soignants en exercice libéral.');
      return;
    }
    setActionLoading(true);
    try {
      const { data, error } = await supabase.functions.invoke('stripe-connect-onboard');
      if (error || !data?.url) {
        // 403 = not LIBERAL — show friendly message
        if (error?.message?.includes('403') || data?.error?.includes('libéral')) {
          toast.info('Passez en exercice libéral pour activer Stripe Connect.');
        } else {
          capturerErreurSentry(error || new Error('No onboard URL'), 'PageStripeConnect', 'stripe_onboard');
          toast.error('Erreur lors de la connexion à Stripe. Veuillez réessayer.');
        }
        return;
      }
      import('@/lib/platform').then(m => m.ouvrirLienExterne(data.url));
    } finally {
      setActionLoading(false);
    }
  };

  const rafraichirStatut = async () => {
    setActionLoading(true);
    // [CP-STRIPE-6 H10] Bouton "Actualiser" → force=true (bypass cache)
    await chargerStatut(true);
    await chargerRevenus();
    setActionLoading(false);
    toast.success('Statut actualisé');
  };

  if (loading) return <LayoutApp role="SOIGNANT"><ChargementPage /></LayoutApp>;

  const isLiberal = typeExercice === 'LIBERAL' || typeExercice === 'MIXTE';

  return (
    <LayoutApp role="SOIGNANT">
      <div className="mb-6">
        <h1 className="text-xl font-bold text-foreground flex items-center gap-2">
          <CreditCard className="h-6 w-6 text-primary" /> Paiements
        </h1>
        <p className="text-sm text-muted-foreground mt-1">Gérez la réception de vos paiements</p>
      </div>

      <div className="max-w-2xl space-y-6">

        {/* ── SALARIÉ : pas de Stripe Connect ── */}
        {!isLiberal && (
          <>
            <div className="card-base space-y-4 min-h-[200px]">
              <div className="flex items-start gap-3">
                <Building2 className="h-6 w-6 text-primary shrink-0 mt-0.5" />
                <div>
                  <h2 className="font-bold text-foreground">Mode salarié</h2>
                  <p className="text-sm text-muted-foreground mt-1">
                    En tant que salarié(e), vos paiements sont gérés directement par l'établissement employeur via bulletin de paie ou virement.
                  </p>
                </div>
              </div>

              <div className="bg-muted/30 rounded-xl p-4 space-y-3">
                <h3 className="text-sm font-semibold text-foreground">Comment ça fonctionne :</h3>
                <div className="space-y-2 text-sm text-muted-foreground">
                  <div className="flex items-start gap-2">
                    <CheckCircle className="h-4 w-4 text-success shrink-0 mt-0.5" />
                    <span>Vous effectuez votre mission et pointez vos présences</span>
                  </div>
                  <div className="flex items-start gap-2">
                    <CheckCircle className="h-4 w-4 text-success shrink-0 mt-0.5" />
                    <span>L'établissement valide vos heures et déclare le paiement</span>
                  </div>
                  <div className="flex items-start gap-2">
                    <CheckCircle className="h-4 w-4 text-success shrink-0 mt-0.5" />
                    <span>Vous confirmez la réception dans <strong>Mes gains</strong></span>
                  </div>
                  <div className="flex items-start gap-2">
                    <CheckCircle className="h-4 w-4 text-success shrink-0 mt-0.5" />
                    <span>Le bulletin de paie est généré par l'établissement</span>
                  </div>
                </div>
              </div>
            </div>

            {/* Quick links */}
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
              <div
                className="card-base cursor-pointer hover:border-primary/30 transition-colors flex items-center gap-3"
                onClick={() => navigate('/soignant/mes-gains')}
              >
                <Banknote className="h-5 w-5 text-primary shrink-0" />
                <div className="flex-1">
                  <p className="text-sm font-semibold text-foreground">Mes gains</p>
                  <p className="text-xs text-muted-foreground">Voir le détail de vos revenus</p>
                </div>
                <ArrowRight className="h-4 w-4 text-muted-foreground" />
              </div>
              <div
                className="card-base cursor-pointer hover:border-primary/30 transition-colors flex items-center gap-3"
                onClick={() => navigate('/soignant/presences')}
              >
                <Clock className="h-5 w-5 text-info shrink-0" />
                <div className="flex-1">
                  <p className="text-sm font-semibold text-foreground">Mes présences</p>
                  <p className="text-xs text-muted-foreground">Pointages et validations</p>
                </div>
                <ArrowRight className="h-4 w-4 text-muted-foreground" />
              </div>
              <div
                className="card-base cursor-pointer hover:border-primary/30 transition-colors flex items-center gap-3"
                onClick={() => navigate('/soignant/contrats')}
              >
                <FileText className="h-5 w-5 text-foreground shrink-0" />
                <div className="flex-1">
                  <p className="text-sm font-semibold text-foreground">Mes contrats</p>
                  <p className="text-xs text-muted-foreground">CDD et contrats de mission</p>
                </div>
                <ArrowRight className="h-4 w-4 text-muted-foreground" />
              </div>
              <div
                className="card-base cursor-pointer hover:border-primary/30 transition-colors flex items-center gap-3"
                onClick={() => navigate('/soignant/passer-en-liberal')}
              >
                <Shield className="h-5 w-5 text-purple-600 shrink-0" />
                <div className="flex-1">
                  <p className="text-sm font-semibold text-foreground">Passer en libéral</p>
                  <p className="text-xs text-muted-foreground">Recevez vos paiements directement</p>
                </div>
                <ArrowRight className="h-4 w-4 text-muted-foreground" />
              </div>
            </div>

            <div className="rounded-xl bg-info/5 border border-info/20 p-4 flex items-start gap-3">
              <Info className="h-5 w-5 text-info shrink-0 mt-0.5" />
              <div>
                <p className="text-sm font-medium text-foreground">Paiement direct via Stripe Connect</p>
                <p className="text-xs text-muted-foreground mt-1">
                  Les soignants en exercice libéral peuvent recevoir leurs honoraires directement sur leur compte bancaire via Stripe Connect.
                  Passez en libéral pour débloquer cette fonctionnalité.
                </p>
              </div>
            </div>
          </>
        )}

        {/* ── LIBÉRAL : Stripe Connect ── */}
        {isLiberal && (
          <>
            {/* NON_DEMANDE */}
            {statut === 'NON_DEMANDE' && (
              <div className="card-base text-center space-y-4 py-8">
                <CreditCard className="h-12 w-12 text-primary mx-auto" />
                <h2 className="text-lg font-bold text-foreground">Recevez vos honoraires directement</h2>
                <p className="text-sm text-muted-foreground max-w-md mx-auto">
                  Connectez votre compte bancaire via Stripe pour recevoir vos paiements de missions directement, sans délai.
                </p>
                <div className="bg-muted/30 rounded-xl p-3 max-w-sm mx-auto space-y-1.5 text-left">
                  <p className="text-xs text-muted-foreground flex items-center gap-2"><CheckCircle className="h-3.5 w-3.5 text-success" /> Virements automatiques après chaque mission</p>
                  <p className="text-xs text-muted-foreground flex items-center gap-2"><CheckCircle className="h-3.5 w-3.5 text-success" /> Sécurisé par Stripe (certifié PCI DSS)</p>
                  <p className="text-xs text-muted-foreground flex items-center gap-2"><CheckCircle className="h-3.5 w-3.5 text-success" /> Aucun frais pour le soignant</p>
                </div>
                <Button onClick={lancerOnboarding} disabled={actionLoading} className="gap-2">
                  {actionLoading ? <Loader2 className="h-4 w-4 animate-spin" /> : <ExternalLink className="h-4 w-4" />}
                  Connecter mon compte bancaire
                </Button>
              </div>
            )}

            {/* EN_COURS */}
            {statut === 'EN_COURS' && (
              <div className="card-base space-y-4">
                <div className="flex items-start gap-3">
                  <Clock className="h-5 w-5 text-warning shrink-0 mt-0.5" />
                  <div>
                    <p className="font-semibold text-foreground">Inscription en cours</p>
                    <p className="text-sm text-muted-foreground mt-1">
                      Complétez votre profil Stripe pour activer les paiements directs. C'est rapide et sécurisé.
                    </p>
                  </div>
                </div>
                <Button onClick={lancerOnboarding} disabled={actionLoading} variant="outline" className="gap-2">
                  {actionLoading ? <Loader2 className="h-4 w-4 animate-spin" /> : <ExternalLink className="h-4 w-4" />}
                  Reprendre l'inscription Stripe
                </Button>
                <Button onClick={rafraichirStatut} disabled={actionLoading} variant="ghost" size="sm" className="gap-2">
                  <RefreshCw className="h-4 w-4" /> Actualiser le statut
                </Button>
              </div>
            )}

            {/* COMPLET */}
            {statut === 'COMPLET' && (
              <>
                <div className="card-base space-y-3">
                  <div className="flex items-center justify-between">
                    <div className="flex items-center gap-3">
                      <CheckCircle className="h-5 w-5 text-success" />
                      <div>
                        <p className="font-semibold text-foreground">Compte connecté</p>
                        {ibanLast4 && (
                          <p className="text-sm text-muted-foreground">IBAN ****{ibanLast4}</p>
                        )}
                      </div>
                    </div>
                    <Button onClick={rafraichirStatut} disabled={actionLoading} variant="ghost" size="sm" className="gap-1.5">
                      {actionLoading ? <Loader2 className="h-4 w-4 animate-spin" /> : <RefreshCw className="h-4 w-4" />}
                      Actualiser
                    </Button>
                  </div>
                </div>

                {revenus && (
                  <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
                    <CarteKPI icone={Banknote} valeur={formatEur(revenus.mois_en_cours)} label="Ce mois" couleurIcone="text-success" couleurFond="bg-success/10" lien="/soignant/mes-gains" />
                    <CarteKPI icone={Banknote} valeur={formatEur(revenus.total)} label="Total reçu" couleurIcone="text-primary" couleurFond="bg-primary/10" lien="/soignant/mes-factures-honoraires" />
                    <CarteKPI icone={Clock} valeur={formatEur(revenus.en_attente)} label="En attente" couleurIcone="text-warning" couleurFond="bg-warning/10" lien="/soignant/mes-avances" />
                  </div>
                )}

                {/* Quick links for liberal */}
                <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                  <div className="card-base cursor-pointer hover:border-primary/30 transition-colors flex items-center gap-3" onClick={() => navigate('/soignant/mes-gains')}>
                    <Banknote className="h-5 w-5 text-primary shrink-0" />
                    <div className="flex-1">
                      <p className="text-sm font-semibold text-foreground">Mes gains</p>
                      <p className="text-xs text-muted-foreground">Détail des revenus</p>
                    </div>
                    <ArrowRight className="h-4 w-4 text-muted-foreground" />
                  </div>
                  <div className="card-base cursor-pointer hover:border-primary/30 transition-colors flex items-center gap-3" onClick={() => navigate('/soignant/charges')}>
                    <FileText className="h-5 w-5 text-foreground shrink-0" />
                    <div className="flex-1">
                      <p className="text-sm font-semibold text-foreground">Mes charges</p>
                      <p className="text-xs text-muted-foreground">URSSAF, CARPIMKO, CFE</p>
                    </div>
                    <ArrowRight className="h-4 w-4 text-muted-foreground" />
                  </div>
                </div>
              </>
            )}

            {/* SUSPENDU */}
            {statut === 'SUSPENDU' && (
              <div className="card-base border-destructive/30 bg-destructive/5 space-y-4">
                <div className="flex items-start gap-3">
                  <AlertTriangle className="h-5 w-5 text-destructive shrink-0 mt-0.5" />
                  <div>
                    <p className="font-semibold text-destructive">Compte suspendu</p>
                    <p className="text-sm text-muted-foreground mt-1">
                      Des informations sont requises pour réactiver votre compte. Complétez votre profil Stripe ci-dessous.
                    </p>
                  </div>
                </div>
                <Button onClick={lancerOnboarding} disabled={actionLoading} variant="destructive" className="gap-2">
                  {actionLoading ? <Loader2 className="h-4 w-4 animate-spin" /> : <ExternalLink className="h-4 w-4" />}
                  Compléter mon profil Stripe
                </Button>
              </div>
            )}

            {/* [CP-STRIPE-6 H11] SUPPRIME : compte Stripe Connect inexistant côté Stripe */}
            {statut === 'SUPPRIME' && (
              <div className="card-base border-destructive/30 bg-destructive/5 space-y-4">
                <div className="flex items-start gap-3">
                  <AlertTriangle className="h-5 w-5 text-destructive shrink-0 mt-0.5" />
                  <div>
                    <p className="font-semibold text-destructive">Compte Stripe supprimé</p>
                    <p className="text-sm text-muted-foreground mt-1">
                      Votre compte Stripe Connect a été supprimé (clôture manuelle, fraude détectée par Stripe,
                      ou décision admin plateforme). Vous ne pouvez plus recevoir de paiements Connect jusqu'à
                      la création d'un nouveau compte.
                    </p>
                  </div>
                </div>
                <div className="flex flex-wrap gap-2">
                  <Button onClick={lancerOnboarding} disabled={actionLoading} variant="destructive" className="gap-2">
                    {actionLoading ? <Loader2 className="h-4 w-4 animate-spin" /> : <ExternalLink className="h-4 w-4" />}
                    Recommencer l'onboarding
                  </Button>
                  <Button
                    onClick={() => navigate('/soignant/support')}
                    variant="outline"
                    className="gap-2"
                  >
                    <Info className="h-4 w-4" />
                    Contacter le support
                  </Button>
                </div>
              </div>
            )}
          </>
        )}
      </div>
    </LayoutApp>
  );
}
