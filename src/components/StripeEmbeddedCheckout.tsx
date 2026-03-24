import React, { useCallback, useState } from 'react';
import { loadStripe } from '@stripe/stripe-js';
import { EmbeddedCheckoutProvider, EmbeddedCheckout } from '@stripe/react-stripe-js';
import { Dialog, DialogContent } from '@/components/ui/dialog';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';
import { Loader2 } from 'lucide-react';

const stripePromise = loadStripe(import.meta.env.VITE_STRIPE_PUBLISHABLE_KEY || '');

interface Props {
  factureId: string;
  open: boolean;
  onClose: () => void;
  onComplete?: () => void;
}

export function StripeEmbeddedCheckout({ factureId, open, onClose, onComplete }: Props) {
  const [error, setError] = useState<string | null>(null);
  const [confirming, setConfirming] = useState(false);

  const fetchClientSecret = useCallback(async () => {
    setError(null);
    const { data, error: fnError } = await supabase.functions.invoke('create-invoice-payment', {
      body: { facture_id: factureId, embedded: true },
    });

    if (fnError || data?.error) {
      const msg = data?.error || 'Erreur lors de la création de la session de paiement';
      setError(msg);
      throw new Error(msg);
    }

    if (!data?.client_secret) {
      const msg = 'Session de paiement invalide';
      setError(msg);
      throw new Error(msg);
    }

    return data.client_secret;
  }, [factureId]);

  const handleComplete = useCallback(() => {
    const confirmPayment = async () => {
      setConfirming(true);
      setError(null);

      for (let attempt = 0; attempt < 4; attempt += 1) {
        const { data, error: fnError } = await supabase.functions.invoke('confirm-invoice-payment', {
          body: { facture_id: factureId },
        });

        if (!fnError && (data?.confirmed || data?.status === 'PAYEE')) {
          toast.success('Paiement effectué avec succès !');
          onComplete?.();
          onClose();
          setConfirming(false);
          return;
        }

        if (attempt < 3) {
          await new Promise((resolve) => window.setTimeout(resolve, 1500));
        }
      }

      setConfirming(false);
      setError('Le paiement est bien parti, mais la synchronisation est encore en cours. Réessayez dans quelques secondes.');
    };

    void confirmPayment();
  }, [factureId, onComplete, onClose]);

  return (
    <Dialog open={open} onOpenChange={(o) => { if (!o) onClose(); }}>
      <DialogContent className="max-w-2xl max-h-[90vh] overflow-y-auto p-0 gap-0">
        <div className="p-4 border-b border-border">
          <h2 className="text-lg font-bold text-foreground">Paiement sécurisé</h2>
          <p className="text-sm text-muted-foreground">Payez votre facture par carte bancaire</p>
        </div>

        {confirming ? (
          <div className="p-6 text-center">
            <Loader2 className="h-5 w-5 animate-spin mx-auto mb-3 text-primary" />
            <p className="text-sm text-foreground">Confirmation du paiement en cours…</p>
          </div>
        ) : error ? (
          <div className="p-6 text-center">
            <p className="text-destructive text-sm mb-4">{error}</p>
            <button onClick={onClose} className="btn-secondary text-sm">Fermer</button>
          </div>
        ) : (
          <div className="p-4" id="stripe-checkout-container">
            <EmbeddedCheckoutProvider
              stripe={stripePromise}
              options={{
                fetchClientSecret,
                onComplete: handleComplete,
              }}
            >
              <EmbeddedCheckout />
            </EmbeddedCheckoutProvider>
          </div>
        )}
      </DialogContent>
    </Dialog>
  );
}
