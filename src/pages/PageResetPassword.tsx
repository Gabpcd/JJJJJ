import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { HeartPulse, Eye, EyeOff, Loader2, CheckCircle, AlertCircle } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { useNotification } from '@/contexts/NotificationContext';
import { extraireMessageErreur } from '@/lib/erreurs';
import { FooterLegal } from '@/components/FooterLegal';
import { usePageTitle } from '@/hooks/usePageTitle';
import { extraireRecoveryCredentials, nettoyerCallbackRecovery } from '@/lib/nativeLinks';
import { logger } from '@/lib/logger';

export default function PageResetPassword() {
  usePageTitle('Réinitialiser le mot de passe');
  const navigate = useNavigate();
  const { afficherNotification } = useNotification();

  const [recoverySession, setRecoverySession] = useState<boolean | null>(null);
  const [motDePasse, setMotDePasse] = useState('');
  const [confirmMdp, setConfirmMdp] = useState('');
  const [afficherMdp, setAfficherMdp] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [success, setSuccess] = useState(false);

  // Cette page est l'unique propriétaire du callback recovery. Une session
  // ordinaire déjà ouverte ne constitue jamais une preuve de récupération.
  useEffect(() => {
    let actif = true;
    const { data: subscription } = supabase.auth.onAuthStateChange((event, session) => {
      if (actif && event === 'PASSWORD_RECOVERY' && session) {
        setRecoverySession(true);
      }
    });

    const finaliserCallback = async () => {
      const credentials = extraireRecoveryCredentials(window.location);
      let error: { message?: string } | null = null;

      if (credentials?.kind === 'implicit') {
        ({ error } = await supabase.auth.setSession({
          access_token: credentials.accessToken,
          refresh_token: credentials.refreshToken,
        }));
      } else if (credentials?.kind === 'pkce') {
        const resultat = await supabase.auth.exchangeCodeForSession(credentials.code);
        error = resultat.error;
        const redirectType = 'redirectType' in resultat.data
          ? resultat.data.redirectType
          : null;
        if (!error && redirectType !== 'recovery') {
          error = { message: 'Ce code ne correspond pas à une récupération de mot de passe.' };
        }
      } else if (credentials?.kind === 'token_hash') {
        ({ error } = await supabase.auth.verifyOtp({
          token_hash: credentials.tokenHash,
          type: 'recovery',
        }));
      }

      if (!actif) return;
      if (credentials) {
        // Même invalide/expiré, un token de récupération ne doit jamais rester
        // dans l'historique ou la barre d'adresse du WebView.
        nettoyerCallbackRecovery();
        if (error) {
          setRecoverySession(false);
          return;
        }
        setRecoverySession(true);
        return;
      }

      // Sans preuve recovery explicite, même une session connectée doit être
      // refusée : sinon visiter cette URL permettrait de modifier le mot de
      // passe du compte actuellement ouvert.
      setRecoverySession(false);
    };

    void finaliserCallback();
    return () => {
      actif = false;
      subscription.subscription.unsubscribe();
    };
  }, []);

  const valide = motDePasse.length >= 8 && motDePasse === confirmMdp;

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!valide || submitting) return;
    setSubmitting(true);
    try {
      const { error } = await supabase.auth.updateUser({ password: motDePasse });
      if (error) {
        afficherNotification({ type: 'erreur', message: extraireMessageErreur(error) });
        return;
      }
      const { error: signOutError } = await supabase.auth.signOut();
      if (signOutError) {
        logger.warn('[RESET_PASSWORD] Déconnexion post-récupération incomplète', signOutError);
        afficherNotification({
          type: 'erreur',
          message: 'Le mot de passe est modifié, mais la session n’a pas pu être fermée. Fermez l’application puis reconnectez-vous.',
        });
        return;
      }
      setSuccess(true);
      afficherNotification({ type: 'succes', message: 'Mot de passe modifié avec succès.' });
      setTimeout(() => navigate('/connexion'), 2000);
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div className="min-h-[100dvh] flex flex-col bg-background">
      <div className="flex-1 flex items-center justify-center p-4">
        <div className="w-full max-w-md">
          <div className="text-center mb-6">
            <HeartPulse className="h-10 w-10 text-primary mx-auto mb-2" />
            <h1 className="text-xl font-bold text-foreground">Réinitialiser le mot de passe</h1>
          </div>

          {recoverySession === null && (
            <div className="card-base text-center py-8">
              <Loader2 className="h-6 w-6 animate-spin text-primary mx-auto" />
              <p className="text-sm text-muted-foreground mt-2">Vérification du lien…</p>
            </div>
          )}

          {recoverySession === false && (
            <div className="card-base">
              <div className="flex items-start gap-3">
                <AlertCircle className="h-5 w-5 text-destructive shrink-0 mt-0.5" />
                <div>
                  <p className="font-semibold text-destructive">Lien invalide ou expiré</p>
                  <p className="text-sm text-muted-foreground mt-1">
                    Le lien de réinitialisation n'est plus valable. Demandez un nouveau lien depuis la page de connexion.
                  </p>
                  <button onClick={() => navigate('/connexion')} className="btn-primary mt-4 w-full">
                    Retour à la connexion
                  </button>
                </div>
              </div>
            </div>
          )}

          {recoverySession && success && (
            <div className="card-base text-center">
              <CheckCircle className="h-8 w-8 text-success mx-auto mb-2" />
              <p className="font-semibold text-foreground">Mot de passe modifié</p>
              <p className="text-sm text-muted-foreground mt-1">Redirection vers la connexion…</p>
            </div>
          )}

          {recoverySession && !success && (
            <form onSubmit={handleSubmit} className="card-base space-y-4">
              <p className="text-sm text-muted-foreground">
                Choisissez un nouveau mot de passe (minimum 8 caractères).
              </p>

              <label className="block">
                <span className="text-sm font-medium text-foreground mb-1.5 block">Nouveau mot de passe *</span>
                <div className="relative">
                  <input
                    type={afficherMdp ? 'text' : 'password'}
                    autoComplete="new-password"
                    value={motDePasse}
                    onChange={(e) => setMotDePasse(e.target.value)}
                    placeholder="Minimum 8 caractères"
                    className="input-base pr-10"
                    required
                    minLength={8}
                  />
                  <button
                    type="button"
                    onClick={() => setAfficherMdp(!afficherMdp)}
                    className="absolute right-3 top-1/2 -translate-y-1/2 text-muted-foreground"
                    aria-label={afficherMdp ? 'Masquer le mot de passe' : 'Afficher le mot de passe'}
                  >
                    {afficherMdp ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
                  </button>
                </div>
              </label>

              <label className="block">
                <span className="text-sm font-medium text-foreground mb-1.5 block">Confirmer le mot de passe *</span>
                <input
                  type="password"
                  autoComplete="new-password"
                  value={confirmMdp}
                  onChange={(e) => setConfirmMdp(e.target.value)}
                  className="input-base"
                  required
                  minLength={8}
                />
                {confirmMdp && confirmMdp !== motDePasse && (
                  <p className="text-xs text-destructive mt-1" role="alert">Les mots de passe ne correspondent pas</p>
                )}
              </label>

              <button
                type="submit"
                disabled={!valide || submitting}
                className="btn-primary w-full disabled:opacity-50 disabled:cursor-not-allowed inline-flex items-center justify-center gap-2"
                aria-busy={submitting}
              >
                {submitting && <Loader2 className="h-5 w-5 animate-spin" aria-hidden="true" />}
                {submitting ? 'Mise à jour…' : 'Modifier mon mot de passe'}
              </button>
            </form>
          )}
        </div>
      </div>
      <FooterLegal />
    </div>
  );
}
