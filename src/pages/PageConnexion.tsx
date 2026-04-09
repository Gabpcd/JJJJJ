import { usePageTitle } from '@/hooks/usePageTitle';
import React, { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { HeartPulse, Mail, Lock, Eye, EyeOff, Fingerprint } from 'lucide-react';
import { useAuth } from '@/contexts/AuthContext';
import { useNotification } from '@/contexts/NotificationContext';
import { extraireMessageErreur } from '@/lib/erreurs';
import { gererErreurSupabase } from '@/lib/supabaseErrorHandler';
import { FooterLegal } from '@/components/FooterLegal';
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

export default function PageConnexion() {
  usePageTitle('Connexion');
  const navigate = useNavigate();
  const { connexion, loading } = useAuth();
  const { afficherNotification } = useNotification();
  const [email, setEmail] = useState('');
  const [motDePasse, setMotDePasse] = useState('');
  const [afficherMdp, setAfficherMdp] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [bioAvailable, setBioAvailable] = useState(false);
  const [bioLoading, setBioLoading] = useState(false);

  useEffect(() => {
    if (isNative()) {
      isBiometricAvailable().then((ok) => {
        setBioAvailable(ok && isBiometricEnabled());
      })
      .catch(() => {});
    }
  }, []);

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

    // Init native push
    if (isNative()) {
      const { data: { user: u } } = await supabase.auth.getUser();
      if (u) {
        import('@/lib/pushNative').then(m => m.initNativePush(u.id));
      }
    }

    if (role === 'ADMIN_PLATEFORME' || role === 'ADMIN') navigate('/admin');
    else if (role === 'ADMIN_ETABLISSEMENT' || role === 'ETABLISSEMENT') navigate('/etablissement/tableau-de-bord');
    else if (role === 'ADMIN_GROUPE') navigate('/groupe/tableau-de-bord');
    else if (role === 'SOIGNANT') navigate('/soignant/tableau-de-bord');
    else {
      console.warn('[CONNEXION] Rôle non reconnu, roleData brut:', roleData);
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
    setSubmitting(true);
    try {
      await connexion(email, motDePasse);
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
    <div className="min-h-screen gradient-hero flex flex-col">
      <div className="flex-1 flex items-center justify-center px-4 py-8">
        <div className="card-base max-w-md w-full">
          <div className="flex items-center justify-center gap-2 mb-8">
            <HeartPulse className="h-8 w-8 text-rose" />
            <span className="text-2xl font-bold text-rose">Jolene</span>
          </div>

          <h1 className="text-xl font-bold text-foreground text-center mb-6">Connexion</h1>

          <form onSubmit={handleSubmit} className="space-y-4">
            <div>
              <label className="text-sm font-medium text-foreground mb-1.5 block">Email</label>
              <div className="relative">
                <Mail className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
                <input type="email" autoComplete="email" value={email} onChange={(e) => setEmail(e.target.value)} placeholder="votre@email.com" className="input-base pl-10" required />
              </div>
            </div>

            <div>
              <label className="text-sm font-medium text-foreground mb-1.5 block">Mot de passe</label>
              <div className="relative">
                <Lock className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
                <input type={afficherMdp ? "text" : "password"} autoComplete="current-password" value={motDePasse} onChange={(e) => setMotDePasse(e.target.value)} placeholder="••••••••" className="input-base pl-10 pr-10" required />
                <button type="button" onClick={() => setAfficherMdp(!afficherMdp)} className="absolute right-3 top-1/2 -translate-y-1/2 text-muted-foreground hover:text-foreground">
                  {afficherMdp ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
                </button>
              </div>
            </div>

            <button type="submit" disabled={submitting} className="btn-primary w-full disabled:opacity-50 disabled:cursor-not-allowed inline-flex items-center justify-center gap-2">
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

          {/* Pro Santé Connect — soignants avec carte CPS/e-CPS */}
          <div className="mb-4">
            <BoutonProSanteConnect intention="login" />
            <p className="text-[10px] text-muted-foreground text-center mt-1.5">
              Réservé aux professionnels de santé disposant d'une carte CPS ou e-CPS
            </p>
          </div>

          <div className="space-y-3">
            <button onClick={() => navigate('/inscription/soignant')} className="btn-secondary w-full text-sm">Créer un compte soignant</button>
            <button onClick={() => navigate('/inscription/etablissement')} className="btn-secondary w-full text-sm">Créer un compte établissement</button>
          </div>

          <p className="text-center mt-4">
            <button
              type="button"
              onClick={async () => {
                if (!email) {
                  afficherNotification({ type: 'erreur', message: 'Saisissez votre email avant de demander une réinitialisation.' });
                  return;
                }
                const { supabase } = await import('@/integrations/supabase/client');
                const { error } = await supabase.auth.resetPasswordForEmail(email, {
                  redirectTo: 'https://app.jolene.app/connexion',
                });
                if (error) {
                  afficherNotification({ type: 'erreur', message: 'Erreur lors de l\'envoi. Vérifiez votre email.' });
                } else {
                  afficherNotification({ type: 'succes', message: 'Email de réinitialisation envoyé. Vérifiez votre boîte mail.' });
                }
              }}
              className="text-sm text-primary hover:underline"
            >
              Mot de passe oublié ?
            </button>
          </p>
        </div>
      </div>
      <FooterLegal />
    </div>
  );
}
