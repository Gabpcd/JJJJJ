import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { CheckCircle, AlertTriangle, ExternalLink, CreditCard, Loader2, FileSignature, Banknote, Info } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { Button } from '@/components/ui/button';
import { toast } from 'sonner';

interface Props {
  userId: string;
  typeExercice: string | null;
  mandatFacturationSigne: boolean | null;
  mandatFacturationSigneLe: string | null;
}

function StripeConnectStatus({ userId }: { userId: string }) {
  const [status, setStatus] = useState<any>(null);
  const [loading, setLoading] = useState(true);
  const [actionLoading, setActionLoading] = useState(false);

  useEffect(() => {
    if (!userId) return;
    supabase.functions.invoke('stripe-connect-status').then(({ data }) => {
      setStatus(data);
      setLoading(false);
    }).then(undefined, () => setLoading(false));
  }, [userId]);

  const lancerOnboarding = async () => {
    setActionLoading(true);
    const { data, error } = await supabase.functions.invoke('stripe-connect-onboard');
    if (error || !(data as any)?.url) {
      const is403 = (data as any)?.error?.includes('libéral') || (error as any)?.message?.includes('403') || (error as any)?.status === 403;
      if (is403) {
        toast('La connexion Stripe sera disponible au lancement.', { icon: 'ℹ️' });
      } else {
        toast.error('Erreur lors de la connexion à Stripe.');
      }
      setActionLoading(false);
      return;
    }
    import('@/lib/platform').then((m) => m.ouvrirLienExterne((data as any).url));
    setActionLoading(false);
  };

  if (loading) return <div className="text-sm text-muted-foreground">Chargement…</div>;
  if (!status) return null;

  if (status.statut === 'COMPLET' && status.charges_enabled && status.payouts_enabled) {
    return (
      <div className="p-3 rounded-xl border border-success/30 bg-success/5 flex items-center gap-3">
        <CheckCircle className="h-5 w-5 text-success shrink-0" />
        <div>
          <p className="text-sm font-semibold text-success">Stripe Connect actif</p>
          <p className="text-xs text-muted-foreground">Vos honoraires sont versés automatiquement.</p>
        </div>
      </div>
    );
  }

  if (status.statut === 'EN_COURS' || status.statut === 'SUSPENDU') {
    return (
      <div className="p-3 rounded-xl border border-warning/30 bg-warning/5 space-y-2">
        <div className="flex items-start gap-3">
          <AlertTriangle className="h-5 w-5 text-warning shrink-0 mt-0.5" />
          <div>
            <p className="text-sm font-semibold text-warning">Compte Stripe Connect non finalisé</p>
            <p className="text-xs text-muted-foreground mt-0.5">Finalisez-le pour recevoir vos honoraires automatiquement.</p>
          </div>
        </div>
        <Button size="sm" variant="outline" onClick={lancerOnboarding} disabled={actionLoading} className="gap-2">
          {actionLoading ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <ExternalLink className="h-3.5 w-3.5" />}
          Finaliser mon compte Stripe
        </Button>
      </div>
    );
  }

  if (status.statut === 'SUPPRIME') {
    return (
      <div className="p-3 rounded-xl border border-destructive/30 bg-destructive/5 space-y-2">
        <div className="flex items-start gap-3">
          <AlertTriangle className="h-5 w-5 text-destructive shrink-0 mt-0.5" />
          <div>
            <p className="text-sm font-semibold text-destructive">Compte Stripe supprimé</p>
            <p className="text-xs text-muted-foreground mt-0.5">Recommencez l'onboarding pour recevoir vos paiements.</p>
          </div>
        </div>
        <Button size="sm" variant="destructive" onClick={lancerOnboarding} disabled={actionLoading} className="gap-2">
          {actionLoading ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <ExternalLink className="h-3.5 w-3.5" />}
          Recommencer l'onboarding
        </Button>
      </div>
    );
  }

  return (
    <div className="p-3 rounded-xl border border-border bg-muted/30 space-y-2">
      <div className="flex items-start gap-3">
        <CreditCard className="h-5 w-5 text-primary shrink-0 mt-0.5" />
        <div>
          <p className="text-sm font-semibold text-foreground">Activez Stripe Connect</p>
          <p className="text-xs text-muted-foreground mt-0.5">
            Pour recevoir vos honoraires automatiquement. Sans Stripe Connect, les établissements vous paieront par virement.
          </p>
        </div>
      </div>
      <Button size="sm" onClick={lancerOnboarding} disabled={actionLoading} className="gap-2">
        {actionLoading ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <ExternalLink className="h-3.5 w-3.5" />}
        Activer Stripe Connect
      </Button>
    </div>
  );
}

export function SectionPaiements({ userId, typeExercice, mandatFacturationSigne, mandatFacturationSigneLe }: Props) {
  const navigate = useNavigate();
  const estLiberalOuMixte = typeExercice === 'LIBERAL' || typeExercice === 'MIXTE';
  const estSalarie = typeExercice === 'SALARIE';

  if (!typeExercice) {
    return (
      <div className="card-base">
        <div className="flex items-start gap-3">
          <Info className="h-5 w-5 text-primary shrink-0 mt-0.5" />
          <div>
            <h2 className="text-base font-semibold text-foreground mb-1">Type d'exercice à définir</h2>
            <p className="text-sm text-muted-foreground">
              Veuillez d'abord définir votre type d'exercice dans l'onglet <strong>Profil principal</strong>.
            </p>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-4">
      {estLiberalOuMixte && (
        <>
          <div className="card-base">
            <h2 className="text-base font-semibold text-foreground mb-2 flex items-center gap-2">
              <CreditCard className="h-4 w-4 text-primary" /> Stripe Connect
            </h2>
            <p className="text-xs text-muted-foreground mb-3">
              Reçoit vos honoraires libéraux directement sur votre compte bancaire.
            </p>
            <StripeConnectStatus userId={userId} />
          </div>

          <div className="card-base">
            <h2 className="text-base font-semibold text-foreground mb-2 flex items-center gap-2">
              <FileSignature className="h-4 w-4 text-primary" /> Mandat de facturation
            </h2>
            {mandatFacturationSigne ? (
              <div className="p-3 rounded-xl border border-success/30 bg-success/5">
                <p className="text-sm font-semibold text-success flex items-center gap-2">
                  <CheckCircle className="h-4 w-4" /> Mandat signé
                </p>
                {mandatFacturationSigneLe && (
                  <p className="text-xs text-muted-foreground mt-1">
                    Le {new Date(mandatFacturationSigneLe).toLocaleDateString('fr-FR')}
                  </p>
                )}
              </div>
            ) : (
              <div className="space-y-2">
                <p className="text-sm text-muted-foreground">
                  Le mandat de facturation autorise Jolene à émettre les factures à votre nom.
                </p>
                <button
                  onClick={() => navigate('/soignant/mandat-facturation')}
                  className="btn-primary text-sm py-2 px-3"
                >
                  Signer le mandat →
                </button>
              </div>
            )}
          </div>
        </>
      )}

      {estSalarie && (
        <div className="card-base">
          <h2 className="text-base font-semibold text-foreground mb-2 flex items-center gap-2">
            <Banknote className="h-4 w-4 text-primary" /> Paiements salariés
          </h2>
          <div className="p-3 rounded-xl border border-primary/20 bg-primary/5 flex items-start gap-3">
            <Info className="h-5 w-5 text-primary shrink-0 mt-0.5" />
            <div>
              <p className="text-sm text-foreground">
                Vos paiements sont versés directement par l'établissement employeur sur votre compte bancaire (IBAN renseigné dans votre contrat).
              </p>
              <p className="text-xs text-muted-foreground mt-2">
                Aucune action requise depuis Jolene. Pour modifier votre IBAN, contactez votre établissement.
              </p>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
