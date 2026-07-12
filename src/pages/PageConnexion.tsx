import { usePageTitle } from '@/hooks/usePageTitle';
import React, { useState, useEffect } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { HeartPulse, Mail, Lock, Eye, EyeOff, Fingerprint } from 'lucide-react';
import { useAuth } from '@/contexts/AuthContext';
import { useNotification } from '@/contexts/NotificationContext';
import { urlCallbackPublique } from '@/lib/nativeLinks';
import { extraireMessageErreur } from '@/lib/erreurs';
import { gererErreurSupabase } from '@/lib/supabaseErrorHandler';
import { FooterLegal } from '@/components/FooterLegal';
import { AuthLayout } from '@/components/AuthLayout';
import { Loader2 } from 'lucide-react';
import { logger } from '@/lib/logger';
import { isNative } from '@/lib/platform';
import {
  isBiometricAvailable,
  isBiometricEnabled,
  authenticateWithBiometric,
  enableBiometric,
  getBiometricLabel,
} from '@/lib/biometric';
import { hapticNotification } from '@/lib/haptics';
import { BoutonProSanteConnect } from '@/components/BoutonProSanteConnect';
import { CaptchaTurnstile, TURNSTILE_REQUIRED } from '@/components/CaptchaTurnstile';

export default function PageConnexion() {
  usePageTitle('Connexion');
  const navigate = useNavigate();
  const [searchParams, setSearchParams] = useSearchParams();
  const { connexion, loading } = useAuth();
  const { afficherNotification } = useNotification();
  const [email, setEmail] = useState('');
  const [motDePasse, setMotDePasse] = useState('');
  const [afficherMdp, setAfficherMdp] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [bioAvailable, setBioAvailable] = useState(false);
  const [bioLoading, setBioLoading] = useState(false);
  const [resetMode, setResetMode] = useState(false);
  const [resetTurnstileToken, setResetTurnstileToken] = useState<string | null>(null);
  const [resetSubmitting, setResetSubmitting] = useState(false);
  const [loginTurnstileToken, setLoginTurnstileToken] = useState<string | null>(null);

  useEffect(() => {
    if (isNative()) {
      isBiometricAvailable().then((ok) => {
        setBioAvailable(ok && isBiometricEnabled());
      }).then(undefined, () => {});
    }
  }, []);

  // Retour de PSC end_session : finaliser le signOut Supabase local et notifier
  useEffect(() => {
    if (searchParams.get('logout') !== 'psc') return;
    let cancelled = false;
    (async () => {
      try {
        const { supabase } = await import('@/integrations/supabase/client');
        await supabase.auth.signOut();
      } catch (e) {
        logger.warn('[CONNEXION] signOut local après PSC logout échoué', e);
      }
      if (cancelled) return;
      afficherNotification({ type: 'succes', message: 'Déconnexion Pro Santé Connect réussie.' });
      // Nettoyer l'URL pour éviter de rejouer la déconnexion à un refresh
      const next = new URLSearchParams(searchParams);
      next.delete('logout');
      setSearchParams(next, { replace: true });
    })();
    return () => { cancelled = true; };
  }, [searchParams, setSearchParams, afficherNotification]);

  const navigateToRole = async () => {
    const { supabase } = await import('@/integrations/supabase/client');
    const { data: roleData, error: roleError } = await supabase.rpc('fn_get_my_role');
    logger.debug('[CONNEXION] fn_get_my_role result:', JSON.stringify(roleData), 'error:', roleError);
    const role = typeof roleData === 'string' ? roleData : (roleData as any)?.role;
    logger.debug('[CONNEXION] Resolved role:', role);

    // Propose biometric on first login (native only)
    if (isNative() && !isBiometricEnabled()) {
      const bioOk = await isBiometricAvailable();
      if (bioOk) {
        const { data: { session } } = await supabase.auth.getSession();
        if (session?.refresh_token) {
          const confirm = window.confirm(`Activer ${getBiometricLabel()} pour les prochaines connexions ?`);
          if (confirm) {
            await enableBiometric(session.refresh_token);
            hapticNotification('success');
          }
        }
      }
    }

    if (role === 'ADMIN_PLATEFORME' || role === 'ADMIN') navigate('/admin');
    else if (role === 'ADMIN_ETABLISSEMENT' || role === 'ETABLISSEMENT') navigate('/etablissement/tableau-de-bord');
    else if (role === 'ADMIN_GROUPE') navigate('/groupe/tableau-de-bord');
    else if (role === 'SOIGNANT') navigate('/soignant/tableau-de-bord');
    else {
      if (import.meta.env.DEV) console.warn('[CONNEXION] Rôle non reconnu, roleData brut:', roleData);
      afficherNotification({ type: 'erreur', message: 'Votre inscription n\'est pas complète. Veuillez vous réinscrire.' });
      const { supabase: sb } = await import('@/integrations/supabase/client');
      await sb.auth.signOut();
      navigate('/inscription/soignant');
    }
  };

  const handleBiometricLogin = async () => {
    setBioLoading(true);
    try {
      const refreshToken = await authenticateWithBiometric();
      if (!refreshToken) {
        afficherNotification({ type: 'erreur', message: 'Authentification biométrique échouée.' });
        return;
      }
      const { supabase } = await import('@/integrations/supabase/client');
      const { error } = await supabase.auth.refreshSession({ refresh_token: refreshToken });
      if (error) {
        afficherNotification({ type: 'erreur', message: 'Session expirée. Connectez-vous avec votre mot de passe.' });
        return;
      }
      hapticNotification('success');
      afficherNotification({ type: 'succes', message: 'Connexion réussie !' });
      await navigateToRole();
    } catch (err) {
      afficherNotification({ type: 'erreur', message: extraireMessageErreur(err) });
    } finally {
      setBioLoading(false);
    }
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!email || !motDePasse) {
      afficherNotification({ type: 'erreur', message: 'Veuillez remplir tous les champs.' });
      return;
    }
    if (TURNSTILE_REQUIRED && !loginTurnstileToken) {
      afficherNotification({ type: 'erreur', message: 'Vérification de sécurité en cours, réessayez dans un instant.' });
      return;
    }
    setSubmitting(true);
    try {
      await connexion(email, motDePasse, loginTurnstileToken || undefined);
      afficherNotification({ type: 'succes', message: 'Connexion réussie !' });
      await navigateToRole();
    } catch (err) {
      if (!gererErreurSupabase(err, () => handleSubmit(e))) {
        afficherNotification({ type: 'erreur', message: extraireMessageErreur(err) });
      }
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <AuthLayout showBack={false}>
        <div className="card-base max-w-md w-full">
          <div className="flex items-center justify-center gap-2 mb-8">
            <HeartPulse className="h-8 w-8 text-rose" />
            <span className="text-2xl font-bold text-rose">Jolene</span>
          </div>

          <h1 className="text-xl font-bold text-foreground text-center mb-6">Connexion</h1>

          <form onSubmit={handleSubmit} className="space-y-4">
            <div>
              <label htmlFor="connexion-email" className="text-sm font-medium text-foreground mb-1.5 block">Email</label>
              <div className="relative">
                <Mail className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
                <input id="connexion-email" type="email" autoComplete="email" value={email} onChange={(e) => setEmail(e.target.value)} placeholder="votre@email.com" className="input-base pl-10" required />
              </div>
            </div>

            <div>
              <label htmlFor="connexion-mot-de-passe" className="text-sm font-medium text-foreground mb-1.5 block">Mot de passe</label>
              <div className="relative">
                <Lock className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
                <input id="connexion-mot-de-passe" type={afficherMdp ? "text" : "password"} autoComplete="current-password" value={motDePasse} onChange={(e) => setMotDePasse(e.target.value)} placeholder="••••••••" className="input-base pl-10 pr-10" required />
                <button
                  type="button"
                  onClick={() => setAfficherMdp(!afficherMdp)}
                  className="absolute right-3 top-1/2 -translate-y-1/2 text-muted-foreground hover:text-foreground"
                  aria-label={afficherMdp ? 'Masquer le mot de passe' : 'Afficher le mot de passe'}
                  aria-pressed={afficherMdp}
                >
                  {afficherMdp ? <EyeOff className="h-4 w-4" aria-hidden="true" /> : <Eye className="h-4 w-4" aria-hidden="true" />}
                </button>
              </div>
            </div>

            {/* Widget Turnstile visible (mode `normal`) — le mode `invisible`
                lançait un challenge silencieux qui crée des iframes srcdoc
                nichés, sensibles à la CSP `about:srcdoc` + extensions anti-
                fingerprint + Service Workers. Symptôme : "Blocked a frame with
                origin challenges.cloudflare.com" en mode normal du navigateur
                (OK en incognito sans extensions). Mode visible = iframe direct,
                pas d'imbrication srcdoc, robuste. */}
            <CaptchaTurnstile className="flex justify-center" onVerify={setLoginTurnstileToken} onExpire={() => setLoginTurnstileToken(null)} onError={() => setLoginTurnstileToken(null)} />

            <button type="submit" disabled={submitting} className="btn-primary w-full disabled:opacity-50 disabled:cursor-not-allowed inline-flex items-center justify-center gap-2" data-testid="login-submit">
              {submitting && <Loader2 className="h-4 w-4 animate-spin" />}
              {submitting ? 'Connexion…' : 'Se connecter'}
            </button>
          </form>

          {/* Biometric login button — native only */}
          {bioAvailable && (
            <button
              onClick={handleBiometricLogin}
              disabled={bioLoading}
              className="btn-secondary w-full inline-flex items-center justify-center gap-2 min-h-[44px]"
            >
              {bioLoading ? <Loader2 className="h-4 w-4 animate-spin" /> : <Fingerprint className="h-5 w-5" />}
              {bioLoading ? 'Vérification…' : `Se connecter avec ${getBiometricLabel()}`}
            </button>
          )}

          <div className="my-6 flex items-center gap-3">
            <div className="flex-1 h-px bg-border" />
            <span className="text-xs text-muted-foreground">ou</span>
            <div className="flex-1 h-px bg-border" />
          </div>

          {/* Pro Santé Connect — soignants avec carte CPS/e-CPS
              Double usage explicite : connexion d'un compte existant ET création de compte en 1 clic */}
          <div className="mb-4">
            <BoutonProSanteConnect
              intention="login"
              onSwitchToEmail={() => {
                // Safari iOS scrolle nativement vers l'input focusé.
                // Pas de scrollIntoView smooth ici (créait un saut au focus mobile).
                document.querySelector<HTMLInputElement>('input[type="email"]')?.focus();
              }}
            />
            <p className="text-[11px] text-muted-foreground text-center mt-2 leading-snug">
              <span className="font-medium text-foreground">Déjà inscrit ?</span> Vous serez connecté.
              {' '}<span className="font-medium text-foreground">Premier accès ?</span> Votre compte sera créé en 1 clic.
              <br />
              <span className="text-[10px]">Réservé aux professionnels de santé disposant d'une carte CPS ou e-CPS.</span>
            </p>
          </div>

          <div className="space-y-3">
            <button onClick={() => navigate('/inscription/soignant')} className="btn-secondary w-full text-sm">Créer un compte soignant</button>
            <button onClick={() => navigate('/inscription/etablissement')} className="btn-secondary w-full text-sm">Créer un compte établissement</button>
          </div>

          <div className="text-center mt-4">
            {!resetMode ? (
              <button
                type="button"
                onClick={() => setResetMode(true)}
                className="text-sm text-primary hover:underline"
              >
                Mot de passe oublié ?
              </button>
            ) : (
              <div className="space-y-2">
                {email ? (
                  <p className="text-xs text-muted-foreground">Email de réinitialisation envoyé à <strong>{email}</strong></p>
                ) : (
                  <label className="block text-left">
                    <span className="text-xs font-medium text-foreground mb-1 block">Email de votre compte</span>
                    <input
                      type="email"
                      autoComplete="email"
                      value={email}
                      onChange={(e) => setEmail(e.target.value)}
                      placeholder="votre@email.com"
                      className="input-base text-sm"
                      required
                    />
                  </label>
                )}
                <CaptchaTurnstile className="flex justify-center" onVerify={setResetTurnstileToken} onExpire={() => setResetTurnstileToken(null)} onError={() => setResetTurnstileToken(null)} />
                <div className="flex gap-2 justify-center">
                  <button
                    type="button"
                    onClick={() => { setResetMode(false); setResetTurnstileToken(null); }}
                    className="text-xs text-muted-foreground hover:underline"
                  >
                    Annuler
                  </button>
                  <button
                    type="button"
                    disabled={resetSubmitting || !email}
                    onClick={async () => {
                      if (!email) {
                        afficherNotification({ type: 'erreur', message: 'Saisissez votre email avant de demander une réinitialisation.' });
                        return;
                      }
                      setResetSubmitting(true);
                      try {
                        const { supabase } = await import('@/integrations/supabase/client');
                        const opts: { redirectTo: string; captchaToken?: string } = {
                          redirectTo: urlCallbackPublique('/reset-password'),
                        };
                        if (resetTurnstileToken) opts.captchaToken = resetTurnstileToken;
                        const { error } = await supabase.auth.resetPasswordForEmail(email, opts);
                        if (error) {
                          afficherNotification({ type: 'erreur', message: 'Erreur lors de l\'envoi. Vérifiez votre email.' });
                        } else {
                          afficherNotification({ type: 'succes', message: 'Email de réinitialisation envoyé. Vérifiez votre boîte mail.' });
                          setResetMode(false);
                        }
                      } finally {
                        setResetSubmitting(false);
                        setResetTurnstileToken(null);
                      }
                    }}
                    className="text-xs text-primary hover:underline disabled:opacity-50"
                  >
                    {resetSubmitting ? 'Envoi…' : 'Envoyer'}
                  </button>
                </div>
              </div>
            )}
          </div>
        </div>
      <FooterLegal />
    </AuthLayout>
  );
}
