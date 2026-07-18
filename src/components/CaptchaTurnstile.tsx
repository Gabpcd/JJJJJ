import { Turnstile } from '@marsidev/react-turnstile';
import { useEffect, useRef } from 'react';
import { isNative } from '@/lib/platform';

const SITE_KEY = import.meta.env.VITE_TURNSTILE_SITE_KEY as string | undefined;
const NATIVE_BUILD = import.meta.env.VITE_NATIVE_BUILD === 'true';

/**
 * `true` uniquement sur le Web lorsqu'une site key Turnstile est configurée.
 * Les formulaires peuvent ainsi exiger un jeton Web sans bloquer Capacitor.
 */
export const TURNSTILE_REQUIRED = !!SITE_KEY && !NATIVE_BUILD && !isNative();

interface Props {
  onVerify: (token: string) => void;
  onError?: () => void;
  onExpire?: () => void;
  /** Cache le widget visuellement mais conserve la mécanique de vérification. */
  invisible?: boolean;
  className?: string;
}

/**
 * Wrapper Cloudflare Turnstile réservé au site Web public.
 *
 * Dans les apps Capacitor iOS/Android, le composant ne charge jamais l'iframe
 * Cloudflare. Une WebView native ne doit pas dépendre d'un challenge Web tiers
 * pour permettre à un utilisateur déjà inscrit de se connecter.
 *
 * Sur le Web, le widget apparaît uniquement lorsqu'une site key est configurée.
 */
export function CaptchaTurnstile({ onVerify, onError, onExpire, invisible, className }: Props) {
  const verifiedRef = useRef(false);

  useEffect(() => {
    if (!TURNSTILE_REQUIRED && !verifiedRef.current) {
      verifiedRef.current = true;
      onVerify('');
    }
  }, [onVerify]);

  if (!TURNSTILE_REQUIRED || !SITE_KEY) return null;

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
