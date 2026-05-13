import { useEffect, useState } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { Loader2, CheckCircle, AlertCircle, Users } from 'lucide-react';
import { LayoutApp } from '@/components/LayoutApp';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { useNotification } from '@/contexts/NotificationContext';
import { usePageTitle } from '@/hooks/usePageTitle';

type Etape = 'verification' | 'connecter' | 'confirmer' | 'succes' | 'erreur';

/**
 * Page acceptation d'invitation équipe étab (Sprint 5.7 PR 2).
 *
 * URL : /etab/invitation/:token
 *
 * Workflow :
 *  - Si user pas connecté → redirige vers /connexion?return=/etab/invitation/:token
 *  - Si user connecté → affiche détail + bouton "Accepter"
 *  - Au clic : fn_accepter_invitation_membre
 *  - Success → redirige /etablissement/tableau-de-bord
 *  - Erreur → message explicite
 */
export default function AccepterInvitationEtab() {
  usePageTitle('Invitation équipe');
  const { token } = useParams<{ token: string }>();
  const navigate = useNavigate();
  const { user } = useAuth();
  const { afficherNotification } = useNotification();
  const [etape, setEtape] = useState<Etape>('verification');
  const [erreurMessage, setErreurMessage] = useState<string>('');
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    if (!token) {
      setEtape('erreur');
      setErreurMessage('Token d\'invitation manquant.');
      return;
    }
    if (!user) {
      // Sauve le retour pour post-login
      sessionStorage.setItem('post_login_redirect', `/etab/invitation/${token}`);
      navigate(`/connexion?return=${encodeURIComponent(`/etab/invitation/${token}`)}`);
      return;
    }
    setEtape('confirmer');
  }, [token, user, navigate]);

  async function accepter() {
    if (!token) return;
    setLoading(true);
    const { data, error } = await supabase.rpc('fn_accepter_invitation_membre' as any, { p_token: token });
    setLoading(false);
    if (error) {
      setEtape('erreur');
      setErreurMessage(error.message);
      return;
    }
    const result = data as any;
    if (!result?.success) {
      setEtape('erreur');
      setErreurMessage(codeErreurFr(result?.error_code) || result?.error || 'Erreur acceptation.');
      return;
    }
    afficherNotification({ type: 'succes', message: 'Invitation acceptée. Bienvenue dans l\'équipe !' });
    setEtape('succes');
    setTimeout(() => navigate('/etablissement/tableau-de-bord'), 1500);
  }

  return (
    <LayoutApp role="ADMIN_ETABLISSEMENT">
      <div className="max-w-md mx-auto py-12 px-4">
        <div className="text-center mb-6">
          <Users className="h-12 w-12 text-primary mx-auto mb-3" />
          <h1 className="text-2xl font-bold text-foreground">Invitation à rejoindre une équipe</h1>
        </div>

        {etape === 'verification' && (
          <div className="card-base text-center py-8">
            <Loader2 className="h-6 w-6 animate-spin text-muted-foreground mx-auto" />
          </div>
        )}

        {etape === 'confirmer' && (
          <div className="card-base space-y-4">
            <p className="text-sm text-foreground">
              Vous êtes connecté(e) en tant que <strong>{user?.email}</strong>.
            </p>
            <p className="text-sm text-muted-foreground">
              En acceptant cette invitation, vous rejoindrez l'équipe de l'établissement avec le rôle qui vous a été proposé.
            </p>
            <div className="rounded-lg bg-amber-50 dark:bg-amber-950/40 border border-amber-200 dark:border-amber-800 p-3 text-xs text-amber-800 dark:text-amber-300 flex gap-2">
              <AlertCircle className="h-4 w-4 shrink-0" />
              <p>L'invitation doit correspondre à votre adresse e-mail. Si ce n'est pas le cas, déconnectez-vous et reconnectez-vous avec le bon compte.</p>
            </div>
            <button
              onClick={accepter}
              disabled={loading}
              className="btn-primary w-full disabled:opacity-50 inline-flex items-center justify-center gap-2"
            >
              {loading && <Loader2 className="h-4 w-4 animate-spin" />}
              Accepter l'invitation
            </button>
          </div>
        )}

        {etape === 'succes' && (
          <div className="card-base text-center py-8 border-success/30 bg-success/5">
            <CheckCircle className="h-12 w-12 text-success mx-auto mb-3" />
            <p className="text-lg font-semibold text-success">Bienvenue dans l'équipe !</p>
            <p className="text-xs text-muted-foreground mt-2">Redirection en cours…</p>
          </div>
        )}

        {etape === 'erreur' && (
          <div className="card-base text-center py-8 border-destructive/30 bg-destructive/5">
            <AlertCircle className="h-12 w-12 text-destructive mx-auto mb-3" />
            <p className="text-base font-semibold text-destructive mb-2">Impossible d'accepter l'invitation</p>
            <p className="text-xs text-muted-foreground">{erreurMessage}</p>
            <button onClick={() => navigate('/')} className="btn-secondary text-sm mt-4">
              Retour à l'accueil
            </button>
          </div>
        )}
      </div>
    </LayoutApp>
  );
}

function codeErreurFr(code?: string): string | null {
  if (!code) return null;
  switch (code) {
    case 'NON_AUTHENTIFIE': return 'Vous devez être connecté(e).';
    case 'TOKEN_INVALIDE': return 'Le lien d\'invitation est invalide.';
    case 'INVITATION_TRAITEE': return 'Cette invitation a déjà été traitée.';
    case 'INVITATION_EXPIREE': return 'Cette invitation a expiré (>7 jours).';
    case 'EMAIL_INCORRECT': return 'Cette invitation est pour une autre adresse e-mail. Reconnectez-vous avec le bon compte.';
    default: return null;
  }
}
