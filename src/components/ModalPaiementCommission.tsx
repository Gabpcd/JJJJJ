import React, { useState, useEffect } from 'react';
import { Elements, PaymentElement, useStripe, useElements } from '@stripe/react-stripe-js';
import { Loader2, CreditCard, X } from 'lucide-react';
import { stripePromise } from '@/lib/stripe';

interface ModalPaiementCommissionProps {
  clientSecret: string;
  montant: number;
  onSuccess: () => Promise<void> | void;
  onCancel: () => void;
}

function FormPaiement({ montant, onSuccess, onCancel }: {
  montant: number;
  onSuccess: () => Promise<void> | void;
  onCancel: () => void;
}) {
  const stripe = useStripe();
  const elements = useElements();
  const [loading, setLoading] = useState(false);
  const [erreur, setErreur] = useState<string | null>(null);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!stripe || !elements) return;
    setLoading(true);
    setErreur(null);

    const { error } = await stripe.confirmPayment({
      elements,
      confirmParams: {
        return_url: window.location.href,
      },
      redirect: 'if_required',
    });

    if (error) {
      setErreur('Erreur de paiement. Veuillez réessayer.');
      setLoading(false);
    } else {
      try {
        // L'autorisation Stripe est revérifiée côté serveur par le parent
        // avant toute attribution de mission.
        await onSuccess();
      } catch (verificationError) {
        setErreur(
          verificationError instanceof Error
            ? verificationError.message
            : "L’autorisation n’a pas pu être vérifiée. Veuillez réessayer.",
        );
        setLoading(false);
      }
    }
  };

  return (
    <form onSubmit={handleSubmit} className="space-y-4">
      <div className="flex items-center justify-between mb-2">
        <div className="flex items-center gap-2">
          <CreditCard className="h-5 w-5 text-primary" />
          <h3 className="font-semibold text-foreground">Paiement de la commission</h3>
        </div>
        <button type="button" onClick={onCancel} className="text-muted-foreground hover:text-foreground">
          <X className="h-5 w-5" />
        </button>
      </div>
      <p className="text-sm text-muted-foreground">
        Commission : <span className="font-bold text-foreground">{montant.toFixed(2)} € TTC</span>
      </p>
      <p className="text-xs text-muted-foreground">
        Le montant sera autorisé maintenant et prélevé uniquement à la fin de la mission. En cas d'annulation, aucun prélèvement.
      </p>
      <PaymentElement />
      {erreur && <p className="text-sm text-destructive">{erreur}</p>}
      <div className="flex gap-3">
        <button
          type="button"
          onClick={onCancel}
          className="flex-1 px-4 py-2.5 text-sm rounded-xl border border-border text-foreground hover:bg-muted transition"
        >
          Annuler
        </button>
        <button
          type="submit"
          disabled={!stripe || loading}
          className="flex-1 btn-primary text-sm py-2.5 disabled:opacity-50 flex items-center justify-center gap-2"
        >
          {loading ? <Loader2 className="h-4 w-4 animate-spin" /> : null}
          {loading ? 'Autorisation…' : `Autoriser ${montant.toFixed(2)} €`}
        </button>
      </div>
    </form>
  );
}

export function ModalPaiementCommission({ clientSecret, montant, onSuccess, onCancel }: ModalPaiementCommissionProps) {
  if (!stripePromise) {
    return (
      <div className="fixed inset-0 z-[9999] flex items-center justify-center bg-black/50 p-4">
        <div className="bg-background rounded-2xl p-6 max-w-md w-full shadow-xl">
          <p className="text-sm text-destructive">Stripe non configuré. Contactez le support.</p>
          <button onClick={onCancel} className="btn-secondary mt-4 w-full">Fermer</button>
        </div>
      </div>
    );
  }

  return (
    <div className="fixed inset-0 z-[9999] flex items-center justify-center bg-black/50 p-4">
      <div className="bg-background rounded-2xl p-6 max-w-md w-full shadow-xl">
        <Elements
          stripe={stripePromise}
          options={{
            clientSecret,
            appearance: {
              theme: 'stripe',
              variables: { colorPrimary: 'hsl(171, 76%, 40%)' },
            },
          }}
        >
          <FormPaiement montant={montant} onSuccess={onSuccess} onCancel={onCancel} />
        </Elements>
      </div>
    </div>
  );
}
