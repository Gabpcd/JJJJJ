import { usePageTitle } from '@/hooks/usePageTitle';
import { useEffect, useState } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { Loader2, CheckCircle, XCircle, HeartPulse } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { Button } from '@/components/ui/button';

export default function PscCallback() {
  usePageTitle('Pro Santé Connect');
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const [status, setStatus] = useState<'loading' | 'success' | 'error'>('loading');
  const [message, setMessage] = useState('');

  useEffect(() => {
    const finaliser = async () => {
      const result = searchParams.get('status');
      const tokenHash = searchParams.get('token_hash');
      const isNewUser = searchParams.get('new_user') === '1';
      const errorMessage = searchParams.get('message');

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
        ? 'Bienvenue sur Jolene ! Votre compte a été créé via Pro Santé Connect.'
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

  return (
    <div className="min-h-screen gradient-hero flex flex-col items-center justify-center px-4">
      <div className="card-base max-w-md w-full text-center space-y-6">
        <div className="flex items-center justify-center gap-2">
          <HeartPulse className="h-8 w-8 text-rose" />
          <span className="text-2xl font-bold text-rose">Jolene</span>
        </div>

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
              <p className="text-xs text-muted-foreground mt-3">Redirection vers votre tableau de bord…</p>
            </div>
          </>
        )}

        {status === 'error' && (
          <>
            <XCircle className="h-14 w-14 text-destructive mx-auto" />
            <div>
              <p className="text-lg font-semibold text-foreground">Échec de la connexion</p>
              <p className="text-sm text-muted-foreground mt-1">{message}</p>
            </div>
            <div className="flex gap-2 justify-center">
              <Button onClick={() => navigate('/connexion')}>Retour à la connexion</Button>
            </div>
          </>
        )}
      </div>
    </div>
  );
}
