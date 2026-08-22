import { usePageTitle } from '@/hooks/usePageTitle';
import React, { useState, useEffect } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { Mail, Lock, Eye, EyeOff, Fingerprint } from 'lucide-react';
import { LogoJolene } from '@/components/LogoJolene';
import { useAuth } from '@/contexts/AuthContext';
import { useNotification } from '@/contexts/NotificationContext';
import { urlCallbackPublique } from '@/lib/nativeLinks';
import { extraireMessageErreur } from '@/lib/erreurs';
import { gererErreurSupabase } from '@/lib/supabaseErrorHandler';
import { FooterLegal } from '@/components/FooterLegal';
import { AuthLayout } from '@/components/AuthLayout';
import { Loader2 } from 'lucide-react';
import { logger } from '@/lib/logger';
import { avecDelai } from '@/lib/avecDelai';
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

export default function PageConnexion() {
  usePageTitle('Connexion');
  const navigate = useNavigate();
  const [searchParams, setSearchParams] = useSearchParams();
  const { connexion } = useAuth();
  const { afficherNotification } = useNotification();
  const [email, setEmail] = useState('');
  const [motDePasse, setMotDePasse] = useState('');
  const [afficherMdp, setAfficherMdp] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [bioAvailable, setBioAvailable] = useState(false);
  const [bioLoading, setBioLoading] = useState(false);
  const [resetMode, setResetMode] = useState(false);
  const [resetSubmitting, setResetSubmitting] = useState(false);
  const [resetEnvoyeA, setResetEnvoyeA] = useState<string | null>(null);
  const [resetDisponibleDans, setResetDisponibleDans] = useState(0);

  useEffect(() => {
    if (isNative()) {
      isBiometricAvailable().then((ok) => {
        setBioAvailable(ok && isBiometricEnabled());
      }).then(undefined, () => {});
    }
  }, []);

  useEffect(() => {
    if (resetDisponibleDans <= 0) return;
    const minuteur = window.setTimeout(
      () => setResetDisponibleDans((secondes) => Math.max(0, secondes - 1)),
      1_000,
    );
    return () => window.clearTimeout(minuteur);
  }, [resetDisponibleDans]);

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

  const navigateToRole = async (): Promise<boolean> => {
    const { supabase } = await import('@/integrations/supabase/client');
    // app_metadata est émis et signé par Supabase Auth (contrairement à
    // user_metadata, modifiable par l'utilisateur). Il suffit donc pour choisir
    // une route d'interface ; chaque donnée/action reste protégée par RLS/RPC.
    // Cela évite qu'une base momentanément chargée bloque une authentification
    // déjà réussie, comme lors de la review Apple du 27/07/2026.
    const { data: sessionData } = await supabase.auth.getSession();
    const roleSigne = sessionData.session?.user.app_metadata?.role;
    let destination = destinationPourRole(roleSigne);
    let roleData: unknown = roleSigne;

    // Compatibilité avec les anciens comptes qui n'ont pas encore de rôle
    // signé dans app_metadata.
    if (!destination) {
      let roleResponse: Awaited<ReturnType<typeof supabase.rpc>>;
      try {
        roleResponse = await avecDelai(
          supabase.rpc('fn_get_my_role'),
          10_000,
          'La résolution de votre espace a pris trop de temps',
        );
      } catch (roleRequestError) {
        logger.error('[CONNEXION] Résolution du rôle expirée, session conservée', roleRequestError);
        afficherNotification({
          type: 'erreur',
          message: 'Votre session est active, mais votre espace ne répond pas. Veuillez réessayer.',
        });
        return false;
      }
      const { data, error: roleError } = roleResponse;
      roleData = data;
      logger.debug('[CONNEXION] fn_get_my_role result:', JSON.stringify(data), 'error:', roleError);

      // Une erreur réseau/serveur ne signifie jamais que le profil est absent.
      if (roleError) {
        logger.error('[CONNEXION] Résolution du rôle indisponible, session conservée', roleError);
        afficherNotification({
          type: 'erreur',
          message: 'Votre session est active, mais votre espace est momentanément indisponible. Veuillez réessayer.',
        });
        return false;
      }

      const role = typeof data === 'string' ? data : (data as any)?.role;
      destination = destinationPourRole(role);
    }

    // Ici seulement, la RPC a répondu avec succès mais aucun rôle n'existe :
    // il s'agit bien d'une inscription incomplète, pas d'un incident transitoire.
    if (!destination) {
      if (import.meta.env.DEV) console.warn('[CONNEXION] Rôle non reconnu, roleData brut:', roleData);
      afficherNotification({ type: 'erreur', message: 'Votre inscription n\'est pas complète. Veuillez vous réinscrire.' });
      await supabase.auth.signOut();
      navigate('/inscription/soignant');
      return false;
    }

    // Propose biometric on first login (native only)
    try {
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
    } catch (biometricError) {
      // La biométrie est un confort optionnel : une panne du plugin ou du
      // trousseau ne doit jamais bloquer une session déjà authentifiée.
      logger.warn('[CONNEXION] Activation biométrique ignorée', biometricError);
    }

    navigate(destination);
    return true;
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
      if (await navigateToRole()) {
        hapticNotification('success');
        afficherNotification({ type: 'succes', message: 'Connexion réussie !' });
      }
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
    setSubmitting(true);
    try {
      await connexion(email, motDePasse);
      if (await navigateToRole()) {
        afficherNotification({ type: 'succes', message: 'Connexion réussie !' });
      }
    } catch (err) {
      if (!gererErreurSupabase(err, () => handleSubmit(e))) {
        afficherNotification({ type: 'erreur', message: extraireMessageErreur(err) });
      }
    } finally {
      setSubmitting(false);
    }
  };

  const demanderReinitialisation = async () => {
    const emailNormalise = email.trim().toLowerCase();
    if (!EMAIL_REGEX.test(emailNormalise)) {
      afficherNotification({ type: 'erreur', message: 'Saisissez une adresse email valide.' });
      return;
    }

    setResetSubmitting(true);
    try {
      const { supabase } = await import('@/integrations/supabase/client');
      const resultat = await supabase.auth.resetPasswordForEmail(emailNormalise, {
        redirectTo: urlCallbackPublique('/reset-password'),
      });
      if (resultat.error) throw resultat.error;

      setEmail(emailNormalise);
      setResetEnvoyeA(emailNormalise);
      setResetDisponibleDans(60);
      afficherNotification({
        type: 'succes',
        message: 'Demande envoyée. Vérifiez votre boîte mail et les courriers indésirables.',
      });
    } catch (err) {
      afficherNotification({ type: 'erreur', message: extraireMessageErreur(err) });
    } finally {
      setResetSubmitting(false);
    }
  };

  return (
    <AuthLayout showBack={false}>
        <section className="auth-login auth-card max-w-md w-full" aria-labelledby="connexion-title">
          <LogoJolene
            className="auth-brand mx-auto flex w-fit"
            imageClassName="h-9 w-9"
            nomClassName="text-[28px] tracking-[-0.03em] text-rose"
          />

          <h1 id="connexion-title" className="auth-title">Connexion</h1>

          <form onSubmit={handleSubmit} className="auth-primary-form space-y-4">
            <div>
              <label htmlFor="connexion-email" className="text-sm font-medium text-foreground mb-1.5 block">Email</label>
              <div className="relative">
                <Mail className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
                <input id="connexion-email" type="email" inputMode="email" autoCapitalize="none" autoCorrect="off" autoComplete="email" value={email} onChange={(e) => setEmail(e.target.value)} placeholder="votre@email.com" className="input-base auth-input pl-11" required />
              </div>
            </div>

            <div>
              <label htmlFor="connexion-mot-de-passe" className="text-sm font-medium text-foreground mb-1.5 block">Mot de passe</label>
              <div className="relative">
                <Lock className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
                <input id="connexion-mot-de-passe" type={afficherMdp ? "text" : "password"} autoComplete="current-password" value={motDePasse} onChange={(e) => setMotDePasse(e.target.value)} placeholder="••••••••" className="input-base auth-input pl-11 pr-11" required />
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

            <button type="submit" disabled={submitting} className="btn-primary auth-submit w-full disabled:opacity-50 disabled:cursor-not-allowed inline-flex items-center justify-center gap-2" data-testid="login-submit">
              {submitting && <Loader2 className="h-4 w-4 animate-spin" />}
              {submitting ? 'Connexion…' : 'Se connecter'}
            </button>
          </form>

          <div className="auth-secondary-actions">
          {bioAvailable && (
            <button onClick={handleBiometricLogin} disabled={bioLoading} className="btn-secondary w-full inline-flex items-center justify-center gap-2 min-h-[44px]">
              {bioLoading ? <Loader2 className="h-4 w-4 animate-spin" /> : <Fingerprint className="h-5 w-5" />}
              {bioLoading ? 'Vérification…' : `Se connecter avec ${getBiometricLabel()}`}
            </button>
          )}

          <div className="auth-divider flex items-center gap-3">
            <div className="flex-1 h-px bg-border" />
            <span className="text-xs text-muted-foreground">ou</span>
            <div className="flex-1 h-px bg-border" />
          </div>

          <div className="mb-4">
            <BoutonProSanteConnect
              intention="login"
              onSwitchToEmail={() => {
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
              <div className="space-y-3 text-left">
                <label className="block">
                  <span className="text-xs font-medium text-foreground mb-1 block">Email de votre compte</span>
                  <input
                    type="email"
                    autoComplete="email"
                    value={email}
                    onChange={(e) => {
                      setEmail(e.target.value);
                      setResetEnvoyeA(null);
                    }}
                    placeholder="votre@email.com"
                    className="input-base text-sm"
                    required
                  />
                </label>

                {resetEnvoyeA && (
                  <p className="text-xs text-muted-foreground" role="status">
                    Si un compte existe pour <strong>{resetEnvoyeA}</strong>, le lien vient d’être envoyé.
                    Vérifiez aussi les courriers indésirables.
                  </p>
                )}

                <button
                  type="button"
                  disabled={resetSubmitting || !email.trim() || resetDisponibleDans > 0}
                  onClick={() => void demanderReinitialisation()}
                  className="btn-primary w-full text-sm disabled:opacity-50 disabled:cursor-not-allowed inline-flex items-center justify-center gap-2"
                >
                  {resetSubmitting && <Loader2 className="h-4 w-4 animate-spin" aria-hidden="true" />}
                  {resetSubmitting
                    ? 'Envoi…'
                    : resetDisponibleDans > 0
                      ? `Renvoyer dans ${resetDisponibleDans} s`
                      : resetEnvoyeA
                        ? 'Renvoyer le lien'
                        : 'Envoyer le lien'}
                </button>

                <div className="text-center">
                  <button
                    type="button"
                    onClick={() => {
                      setResetMode(false);
                      setResetEnvoyeA(null);
                    }}
                    className="text-xs text-muted-foreground hover:underline"
                  >
                    Retour à la connexion
                  </button>
                </div>
              </div>
            )}
          </div>
          </div>
        </section>
      <FooterLegal />
    </AuthLayout>
  );
}

const EMAIL_REGEX = /^[^\s@]{1,64}@[^\s@]{1,255}\.[a-z]{2,}$/i;

function destinationPourRole(role: unknown): string | null {
  if (role === 'ADMIN_PLATEFORME' || role === 'ADMIN') return '/admin';
  if (role === 'ADMIN_ETABLISSEMENT' || role === 'ETABLISSEMENT') {
    return '/etablissement/tableau-de-bord';
  }
  if (role === 'ADMIN_GROUPE') return '/groupe/tableau-de-bord';
  if (role === 'SOIGNANT') return '/soignant/tableau-de-bord';
  return null;
}
