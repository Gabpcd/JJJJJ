import { usePageTitle } from '@/hooks/usePageTitle';
import { useEffect, useState } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { Loader2, CheckCircle, XCircle, ExternalLink } from 'lucide-react';
import { LogoJolene } from '@/components/LogoJolene';
import { supabase } from '@/integrations/supabase/client';
import { Button } from '@/components/ui/button';
import { ouvrirUrlPsc } from '@/lib/pscNavigation';

const LIEN_ACTIVATION_ECPS = 'https://esante.gouv.fr/produits-services/e-cps';

export default function PscCallback() {
  usePageTitle('Pro Santé Connect');
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const [status, setStatus] = useState<'loading' | 'success' | 'error'>('loading');
  const [message, setMessage] = useState('');
  const [retryLoading, setRetryLoading] = useState(false);

  useEffect(() => {
    const finaliser = async () => {
      const result = searchParams.get('status');
      const tokenHash = searchParams.get('token_hash');
      const isNewUser = searchParams.get('new_user') === '1';
      const errorMessage = searchParams.get('message');

      // Le token magic-link PSC est un secret à usage unique. On le retire de
      // l'URL et de l'historique avant tout appel réseau, succès ou échec.
      if (tokenHash || errorMessage) {
        const paramsNettoyes = new URLSearchParams(searchParams);
        paramsNettoyes.delete('token_hash');
        paramsNettoyes.delete('message');
        const query = paramsNettoyes.toString();
        window.history.replaceState(null, '', `/auth/psc/callback${query ? `?${query}` : ''}`);
      }

      if (result === 'error') {
        setStatus('error');
        setMessage(errorMessage || 'Échec de la connexion Pro Santé Connect');
        return;
      }

      if (result !== 'success' || !tokenHash) {
        setStatus('error');
        setMessage('Paramètres de callback manquants');
        return;
      }

      // Finaliser la session avec le token_hash fourni par l'edge function
      const { error } = await supabase.auth.verifyOtp({
        token_hash: tokenHash,
        type: 'magiclink',
      });

      if (error) {
        setStatus('error');
        setMessage(error.message || 'Impossible de créer la session');
        return;
      }

      setStatus('success');
      setMessage(isNewUser
        ? 'Bienvenue sur Jolene ! Ton compte a été créé via Pro Santé Connect.'
        : 'Connexion réussie via Pro Santé Connect');

      // Vérifier le rôle et rediriger
      setTimeout(async () => {
        const { data: roleData } = await supabase.rpc('fn_get_my_role' as any);
        const role = typeof roleData === 'string' ? roleData : (roleData as any)?.role;
        if (role === 'SOIGNANT') {
          // Nouveau soignant via PSC : page de complétion (téléphone, contrat, mdp optionnel, CGU)
          // Soignant existant : tableau de bord
          navigate(isNewUser ? '/inscription/soignant/completion' : '/soignant/tableau-de-bord');
        } else {
          navigate('/');
        }
      }, 1500);
    };

    finaliser();
  }, [searchParams, navigate]);

  // Relance le flow PSC complet (équivalent du bouton "S'identifier avec Pro Santé Connect")
  const relancerPsc = async () => {
    setRetryLoading(true);
    try {
      const { data, error } = await supabase.functions.invoke('psc-authorize', {
        body: { intention: 'login' },
      });
      if (!error && data?.authorization_url) {
        if (await ouvrirUrlPsc(data.authorization_url)) return;
      }
      // Fallback : retour à la page de connexion
      navigate('/connexion');
    } catch {
      navigate('/connexion');
    } finally {
      setRetryLoading(false);
    }
  };

  return (
    <div className="min-h-[100dvh] gradient-hero flex flex-col items-center justify-center px-4">
      <div className="card-base max-w-md w-full text-center space-y-6">
        <LogoJolene
          className="mx-auto flex w-fit"
          imageClassName="h-8 w-8"
          nomClassName="text-2xl text-rose"
        />

        {status === 'loading' && (
          <>
            <Loader2 className="h-12 w-12 animate-spin text-primary mx-auto" />
            <div>
              <p className="text-lg font-semibold text-foreground">Connexion en cours…</p>
              <p className="text-sm text-muted-foreground mt-1">Finalisation de l'authentification Pro Santé Connect</p>
            </div>
          </>
        )}

        {status === 'success' && (
          <>
            <CheckCircle className="h-14 w-14 text-success mx-auto" />
            <div>
              <p className="text-lg font-semibold text-foreground">Connexion réussie</p>
              <p className="text-sm text-muted-foreground mt-1">{message}</p>
              <p className="text-xs text-muted-foreground mt-3">Redirection vers ton tableau de bord…</p>
            </div>
          </>
        )}

        {status === 'error' && (
          <>
            <XCircle className="h-14 w-14 text-destructive mx-auto" />
            <div className="space-y-3">
              <p className="text-lg font-semibold text-foreground">
                La connexion à Pro Santé Connect n'a pas fonctionné
              </p>
              <p className="text-sm text-muted-foreground">
                Cela peut arriver dans plusieurs cas :
              </p>
              <ul className="text-sm text-muted-foreground text-left list-disc list-inside space-y-1 mx-auto max-w-xs">
                <li>Tu n'as pas encore activé ta e-CPS sur ton téléphone</li>
                <li>Ta carte CPS n'a pas été reconnue par ton lecteur</li>
                <li>Tu as annulé la procédure d'authentification</li>
                <li>Ta e-CPS ou ta carte CPS est expirée</li>
              </ul>
              {message && (
                <p className="text-xs text-muted-foreground/80 italic pt-1">
                  Détail technique : {message}
                </p>
              )}
            </div>

            <div className="flex flex-col gap-2 pt-2">
              <Button
                onClick={() => navigate('/inscription/soignant')}
                className="w-full"
              >
                S'inscrire par email
              </Button>
              <Button
                variant="outline"
                onClick={relancerPsc}
                disabled={retryLoading}
                className="w-full"
              >
                {retryLoading ? (
                  <>
                    <Loader2 className="h-4 w-4 animate-spin mr-2" />
                    Redirection…
                  </>
                ) : (
                  'Réessayer Pro Santé Connect'
                )}
              </Button>
              <a
                href={LIEN_ACTIVATION_ECPS}
                target="_blank"
                rel="noopener noreferrer"
                className="inline-flex items-center justify-center gap-1 text-sm text-primary hover:underline pt-1"
              >
                Activer ma e-CPS
                <ExternalLink className="h-3 w-3" aria-hidden="true" />
              </a>
              <a
                href="/aide/pro-sante-connect"
                className="text-xs text-muted-foreground hover:text-primary hover:underline"
              >
                En savoir plus sur Pro Santé Connect
              </a>
            </div>
          </>
        )}
      </div>
    </div>
  );
}
