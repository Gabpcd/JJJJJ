import React, { useCallback, useEffect, useState } from 'react';
import { EmbeddedCheckoutProvider, EmbeddedCheckout } from '@stripe/react-stripe-js';
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';
import { Loader2 } from 'lucide-react';
import { stripePromise } from '@/lib/stripe';

interface Props {
  factureId: string;
  open: boolean;
  onClose: () => void;
  onComplete?: () => void | Promise<void>;
  preparedClientSecret?: string | null;
}

interface FunctionPayload {
  client_secret?: string | null;
  confirmed?: boolean;
  error?: string;
  status?: string;
}

async function readFunctionErrorPayload(fnError: unknown): Promise<FunctionPayload | null> {
  if (!fnError || typeof fnError !== 'object' || !("context" in fnError)) {
    return null;
  }

  const response = (fnError as { context?: Response }).context;
  if (!(response instanceof Response)) {
    return null;
  }

  try {
    return await response.clone().json();
  } catch {
    try {
      const text = await response.clone().text();
      return text ? { error: text } : null;
    } catch {
      return null;
    }
  }
}

export function StripeEmbeddedCheckout({
  factureId,
  open,
  onClose,
  onComplete,
  preparedClientSecret,
}: Props) {
  const [clientSecret, setClientSecret] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [confirming, setConfirming] = useState(false);
  const [loadingCheckout, setLoadingCheckout] = useState(false);

  const handleAlreadyPaid = useCallback(async () => {
    toast.success('Cette facture est déjà payée !');
    await onComplete?.();
    onClose();
  }, [onClose, onComplete]);

  const confirmExistingPayment = useCallback(async () => {
    const { data, error: fnError } = await supabase.functions.invoke('confirm-invoice-payment', {
      body: { facture_id: factureId },
    });

    if (!fnError && (data?.confirmed || data?.status === 'PAYEE')) {
      await handleAlreadyPaid();
      return true;
    }

    return false;
  }, [factureId, handleAlreadyPaid]);

  useEffect(() => {
    if (!open) {
      setClientSecret(null);
      setError(null);
      setConfirming(false);
      setLoadingCheckout(false);
      return;
    }

    let cancelled = false;

    const initializeCheckout = async () => {
      setLoadingCheckout(true);
      setClientSecret(null);
      setError(null);

      if (preparedClientSecret) {
        setClientSecret(preparedClientSecret);
        setLoadingCheckout(false);
        return;
      }

      const { data, error: fnError } = await supabase.functions.invoke('create-invoice-payment', {
        body: { facture_id: factureId, embedded: Boolean(stripePromise) },
      });

      const payload = data ?? await readFunctionErrorPayload(fnError);

      if (cancelled) return;

      if (!fnError && !stripePromise && data?.url) {
        toast.info('Redirection vers le paiement sécurisé…');
        window.location.assign(data.url);
        return;
      }

      if (!fnError && data?.client_secret) {
        setClientSecret(data.client_secret);
        setLoadingCheckout(false);
        return;
      }

      if (payload?.status === 'PAYEE' || payload?.error === 'Facture déjà payée') {
        const synced = await confirmExistingPayment();
        if (cancelled) return;
        setLoadingCheckout(false);
        if (!synced) {
          await handleAlreadyPaid();
        }
        return;
      }

      setError(payload?.error || 'Erreur lors de la création de la session de paiement');
      setLoadingCheckout(false);
    };

    void initializeCheckout();

    return () => {
      cancelled = true;
    };
  }, [confirmExistingPayment, factureId, handleAlreadyPaid, open, preparedClientSecret]);

  const handleComplete = useCallback(() => {
    const confirmPayment = async () => {
      setConfirming(true);
      setError(null);

      try {
        if (preparedClientSecret) {
          await onComplete?.();
          onClose();
          return;
        }

        // Poll up to 8 times with increasing delays (total ~25s) to wait for webhook
        const delays = [1500, 2000, 2500, 3000, 3000, 3500, 4000, 5000];
        for (let attempt = 0; attempt < delays.length; attempt += 1) {
          const { data, error: fnError } = await supabase.functions.invoke('confirm-invoice-payment', {
            body: { facture_id: factureId },
          });

          if (!fnError && (data?.confirmed || data?.status === 'PAYEE')) {
            toast.success('Paiement effectué avec succès !');
            await onComplete?.();
            onClose();
            return;
          }

          if (attempt < delays.length - 1) {
            await new Promise((resolve) => window.setTimeout(resolve, delays[attempt]));
          }
        }

        // Payment went through on Stripe but webhook hasn't synced yet
        toast.info('Paiement envoyé ! La confirmation peut prendre quelques instants.');
        await onComplete?.();
        onClose();
      } catch {
        setError('Impossible de finaliser la confirmation du paiement pour le moment.');
      } finally {
        setConfirming(false);
      }
    };

    void confirmPayment();
  }, [factureId, onComplete, onClose, preparedClientSecret]);

  return (
    <Dialog open={open} onOpenChange={(o) => { if (!o && !confirming) onClose(); }}>
      <DialogContent className="max-w-[calc(100%-1rem)] sm:max-w-2xl max-h-[90vh] overflow-y-auto p-0 gap-0">
        <DialogHeader className="p-4 border-b border-border space-y-1">
          <DialogTitle className="text-lg font-bold text-foreground">Paiement sécurisé</DialogTitle>
          <DialogDescription className="text-sm text-muted-foreground">
            Payez votre facture par carte bancaire
          </DialogDescription>
        </DialogHeader>

        {loadingCheckout ? (
          <div className="p-6 text-center">
            <Loader2 className="h-5 w-5 animate-spin mx-auto mb-3 text-primary" />
            <p className="text-sm text-foreground">Initialisation du paiement…</p>
          </div>
        ) : confirming ? (
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
                clientSecret,
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
