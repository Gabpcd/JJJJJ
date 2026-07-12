import { Turnstile } from '@marsidev/react-turnstile';
import { useEffect, useRef } from 'react';

const SITE_KEY = import.meta.env.VITE_TURNSTILE_SITE_KEY as string | undefined;

/**
 * `true` quand un site key Turnstile est configuré (prod). Utilisez ce flag
 * pour conditionner l'activation du bouton submit : en prod le user doit avoir
 * un token, en dev sans clé le composant fournit un token "skip" automatique.
 */
export const TURNSTILE_REQUIRED = !!SITE_KEY;

interface Props {
  onVerify: (token: string) => void;
  onError?: () => void;
  onExpire?: () => void;
  /** Cache le widget visuellement mais conserve la mécanique de vérification. */
  invisible?: boolean;
  className?: string;
}

/**
 * Wrapper Cloudflare Turnstile avec fallback no-op en dev.
 *
 * Si `VITE_TURNSTILE_SITE_KEY` n'est pas définie en développement local, le
 * composant fournit un marqueur de développement et ne rend rien. Les Edge
 * Functions publiques restent fail-closed : leur éventuel bypass exige
 * explicitement TURNSTILE_ALLOW_DEV_BYPASS=true et une origine HTTP locale.
 *
 * En production, dès que les clés sont présentes des deux côtés, le widget
 * apparaît et bloque la soumission tant que l'utilisateur n'a pas validé.
 */
export function CaptchaTurnstile({ onVerify, onError, onExpire, invisible, className }: Props) {
  const verifiedRef = useRef(false);

  useEffect(() => {
    if (!SITE_KEY && !verifiedRef.current) {
      verifiedRef.current = true;
      // Marqueur non vide pour les parcours locaux. Il n'est jamais accepte
      // automatiquement par une Edge Function de production.
      onVerify('dev-no-key');
    }
  }, [onVerify]);

  if (!SITE_KEY) return null;

  return (
    <div className={className}>
      <Turnstile
        siteKey={SITE_KEY}
        onSuccess={onVerify}
        onError={onError}
        onExpire={onExpire}
        options={{
          theme: 'light',
          size: invisible ? 'invisible' : 'normal',
          language: 'fr',
        }}
      />
    </div>
  );
}
