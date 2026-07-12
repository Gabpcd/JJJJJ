import { useState } from 'react';
import { Loader2 } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';
import { ModalePscPreAuth } from '@/components/ModalePscPreAuth';
import { ouvrirUrlPsc } from '@/lib/pscNavigation';

interface Props {
  intention?: 'login' | 'signup';
  fullWidth?: boolean;
  onSwitchToEmail?: () => void;
}

// Logo officiel Pro Santé Connect (ANS)
// Source : https://esante.gouv.fr/produits-services/pro-sante-connect — kit identité visuelle
// Reproduit en SVG inline pour éviter le hotlink et garantir le rendu hors ligne.
function LogoPSC({ className }: { className?: string }) {
  return (
    <svg
      className={className}
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 32 32"
      aria-hidden="true"
      focusable="false"
    >
      {/* Carré bleu ANS (#0078D7) avec croix santé blanche */}
      <rect width="32" height="32" rx="6" fill="#0078D7" />
      <path
        d="M13.5 7h5v6h6v5h-6v6h-5v-6h-6v-5h6V7z"
        fill="#FFFFFF"
      />
    </svg>
  );
}

export function BoutonProSanteConnect({ intention = 'login', fullWidth = true, onSwitchToEmail }: Props) {
  const [loading, setLoading] = useState(false);
  const [modaleOuverte, setModaleOuverte] = useState(false);

  // Le clic sur le bouton ouvre la modale informative AVANT de rediriger vers PSC.
  // Beaucoup de pros de santé n'ont pas encore activé leur e-CPS et l'écran ANS
  // ne l'explique pas. On éduque ici pour réduire l'abandon silencieux.
  const ouvrirModale = () => {
    setModaleOuverte(true);
  };

  const lancerRedirection = async () => {
    setLoading(true);
    try {
      const { data, error } = await supabase.functions.invoke('psc-authorize', {
        body: { intention },
      });

      if (error) {
        toast.error('Pro Santé Connect indisponible. Réessayez plus tard ou utilisez l\'inscription par email.');
        setModaleOuverte(false);
        return;
      }

      if (data?.error) {
        toast.error(data.error);
        setModaleOuverte(false);
        return;
      }

      if (data?.authorization_url) {
        if (await ouvrirUrlPsc(data.authorization_url)) return;
        toast.error('Adresse Pro Santé Connect invalide. Réessayez plus tard.');
        setModaleOuverte(false);
        return;
      }

      // Fallback : `configured: false` ou réponse inattendue côté serveur
      // (credentials ANS pas encore reçus → erreur réelle, pas un blocage UX en amont)
      toast.error('Pro Santé Connect indisponible pour le moment. Réessayez dans quelques minutes ou utilisez l\'inscription par email.');
      setModaleOuverte(false);
    } catch {
      toast.error('Erreur de connexion à Pro Santé Connect. Vérifie ton réseau.');
      setModaleOuverte(false);
    } finally {
      setLoading(false);
    }
  };

  // Charte graphique ANS : libellé exact "S'identifier avec Pro Santé Connect",
  // fond blanc, bordure et texte bleu PSC, logo officiel à gauche.
  // Réf : https://esante.gouv.fr/produits-services/pro-sante-connect (kit identité visuelle)
  return (
    <>
      <button
        type="button"
        onClick={ouvrirModale}
        disabled={loading}
        aria-label="S'identifier avec Pro Santé Connect"
        className={[
          fullWidth ? 'w-full' : '',
          'inline-flex items-center justify-center gap-3',
          'min-h-[48px] px-5 py-3 rounded-xl',
          'bg-white border-2',
          'transition-colors duration-150',
          'disabled:opacity-60 disabled:cursor-not-allowed',
        ].join(' ')}
        style={{
          borderColor: '#0078D7',
          // #0066CC (au lieu de #0078D7) : contraste 5.2:1 sur blanc — le bleu
          // PSC officiel est à 4.49:1, sous le seuil WCAG AA 4.5:1 (axe serious)
          color: '#0066CC',
        }}
        onMouseEnter={(e) => {
          if (!loading) e.currentTarget.style.backgroundColor = '#F0F7FD';
        }}
        onMouseLeave={(e) => {
          e.currentTarget.style.backgroundColor = '#FFFFFF';
        }}
      >
        {loading ? (
          <Loader2 className="h-5 w-5 animate-spin" style={{ color: '#0078D7' }} />
        ) : (
          <LogoPSC className="h-6 w-6 shrink-0" />
        )}
        <span className="text-sm font-semibold tracking-tight">
          S'identifier avec Pro Santé Connect
        </span>
      </button>

      <ModalePscPreAuth
        open={modaleOuverte}
        onOpenChange={setModaleOuverte}
        onContinue={lancerRedirection}
        onSwitchToEmail={onSwitchToEmail}
        loading={loading}
      />
    </>
  );
}
