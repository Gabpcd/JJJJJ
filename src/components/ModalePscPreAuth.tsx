import { Smartphone, CreditCard, ExternalLink, Mail, Loader2 } from 'lucide-react';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';

interface Props {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onContinue: () => void;
  onSwitchToEmail?: () => void;
  loading?: boolean;
}

const LIEN_ACTIVATION_ECPS = 'https://esante.gouv.fr/produits-services/e-cps';

export function ModalePscPreAuth({
  open,
  onOpenChange,
  onContinue,
  onSwitchToEmail,
  loading = false,
}: Props) {
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-lg p-0 gap-0">
        <DialogHeader className="px-6 pt-6 pb-4 border-b border-border">
          <div className="flex items-center gap-3">
            <svg
              viewBox="0 0 32 32"
              className="h-8 w-8 shrink-0"
              aria-hidden="true"
              focusable="false"
            >
              <rect width="32" height="32" rx="6" fill="#0078D7" />
              <path d="M13.5 7h5v6h6v5h-6v6h-5v-6h-6v-5h6V7z" fill="#FFFFFF" />
            </svg>
            <DialogTitle className="text-lg font-semibold text-left">
              Authentification Pro Santé Connect
            </DialogTitle>
          </div>
          <DialogDescription className="text-sm text-muted-foreground text-left pt-3 leading-relaxed">
            Pro Santé Connect est le système officiel d'authentification de l'Agence du Numérique
            en Santé (ANS) pour les professionnels de santé en France.
          </DialogDescription>
        </DialogHeader>

        <div className="px-6 py-4 space-y-4">
          <p className="text-sm font-medium text-foreground">
            Pour vous authentifier, vous aurez besoin de l'un de ces moyens :
          </p>

          <div className="rounded-lg border border-border p-4 space-y-2">
            <div className="flex items-start gap-3">
              <Smartphone className="h-5 w-5 text-primary shrink-0 mt-0.5" aria-hidden="true" />
              <div className="flex-1 min-w-0">
                <p className="text-sm font-semibold">App e-CPS sur votre téléphone</p>
                <p className="text-xs text-muted-foreground mt-1">
                  Si vous avez déjà activé votre e-CPS sur votre smartphone, vous êtes prêt.
                </p>
                <a
                  href={LIEN_ACTIVATION_ECPS}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="inline-flex items-center gap-1 text-xs text-primary hover:underline mt-2"
                >
                  Pas encore activé ? Comment activer mon e-CPS (5 min)
                  <ExternalLink className="h-3 w-3" aria-hidden="true" />
                </a>
              </div>
            </div>
          </div>

          <div className="rounded-lg border border-border p-4">
            <div className="flex items-start gap-3">
              <CreditCard className="h-5 w-5 text-primary shrink-0 mt-0.5" aria-hidden="true" />
              <div className="flex-1 min-w-0">
                <p className="text-sm font-semibold">Carte CPS physique</p>
                <p className="text-xs text-muted-foreground mt-1">
                  Si vous avez votre carte CPS et un lecteur de carte connecté à votre ordinateur
                  (logiciel CryptoLib requis).
                </p>
              </div>
            </div>
          </div>

          <div className="rounded-lg bg-muted/40 p-4">
            <div className="flex items-start gap-3">
              <Mail className="h-5 w-5 text-muted-foreground shrink-0 mt-0.5" aria-hidden="true" />
              <div className="flex-1 min-w-0">
                <p className="text-sm font-medium">Vous n'avez ni l'un ni l'autre ?</p>
                <p className="text-xs text-muted-foreground mt-1">
                  Inscrivez-vous avec votre email, c'est plus simple. Vous pourrez activer Pro
                  Santé Connect plus tard.
                </p>
              </div>
            </div>
          </div>
        </div>

        <DialogFooter className="px-6 py-4 border-t border-border flex flex-col sm:flex-col gap-2 sm:gap-2">
          <Button
            type="button"
            onClick={onContinue}
            disabled={loading}
            className="w-full"
            style={{ backgroundColor: '#0078D7' }}
          >
            {loading ? (
              <>
                <Loader2 className="h-4 w-4 animate-spin mr-2" />
                Redirection…
              </>
            ) : (
              'Continuer vers Pro Santé Connect'
            )}
          </Button>
          <Button
            type="button"
            variant="outline"
            asChild
            className="w-full"
          >
            <a href={LIEN_ACTIVATION_ECPS} target="_blank" rel="noopener noreferrer">
              Activer mon e-CPS d'abord
              <ExternalLink className="h-4 w-4 ml-2" aria-hidden="true" />
            </a>
          </Button>
          <Button
            type="button"
            variant="ghost"
            onClick={() => {
              onOpenChange(false);
              onSwitchToEmail?.();
            }}
            className="w-full"
          >
            S'inscrire par email à la place
          </Button>
          <a
            href="/aide/pro-sante-connect"
            className="text-xs text-center text-muted-foreground hover:text-primary hover:underline pt-1"
          >
            En savoir plus sur Pro Santé Connect
          </a>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
