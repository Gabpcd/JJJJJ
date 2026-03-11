import React, { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { HeartPulse, Mail, Lock, Eye, EyeOff } from 'lucide-react';
import { useAuth } from '@/contexts/AuthContext';
import { useNotification } from '@/contexts/NotificationContext';
import { extraireMessageErreur } from '@/lib/erreurs';

export default function PageConnexion() {
  const navigate = useNavigate();
  const { connexion, loading } = useAuth();
  const { afficherNotification } = useNotification();
  const [email, setEmail] = useState('');
  const [motDePasse, setMotDePasse] = useState('');
  const [afficherMdp, setAfficherMdp] = useState(false);
  const [submitting, setSubmitting] = useState(false);

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
      // AuthContext onAuthStateChange will update user, we need to read role from fresh session
      const { data } = await (await import('@/integrations/supabase/client')).supabase.auth.getUser();
      const role = data.user?.app_metadata?.role || data.user?.user_metadata?.role;
      if (role === 'ETABLISSEMENT') navigate('/etablissement/tableau-de-bord');
      else if (role === 'ADMIN_GROUPE') navigate('/groupe/tableau-de-bord');
      else navigate('/soignant/tableau-de-bord');
    } catch (err) {
      afficherNotification({ type: 'erreur', message: extraireMessageErreur(err) });
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div className="min-h-screen gradient-hero flex items-center justify-center px-4">
      <div className="card-base max-w-md w-full">
        <div className="flex items-center justify-center gap-2 mb-8">
          <HeartPulse className="h-8 w-8 text-primary" />
          <span className="text-2xl font-bold text-primary-dark">Soin Direct</span>
        </div>

        <h1 className="text-xl font-bold text-foreground text-center mb-6">Connexion</h1>

        <form onSubmit={handleSubmit} className="space-y-4">
          <div>
            <label className="text-sm font-medium text-foreground mb-1.5 block">Email</label>
            <div className="relative">
              <Mail className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
              <input type="email" value={email} onChange={(e) => setEmail(e.target.value)} placeholder="votre@email.com" className="input-base pl-10" required />
            </div>
          </div>

          <div>
            <label className="text-sm font-medium text-foreground mb-1.5 block">Mot de passe</label>
            <div className="relative">
              <Lock className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
              <input type={afficherMdp ? 'text' : 'password'} value={motDePasse} onChange={(e) => setMotDePasse(e.target.value)} placeholder="••••••••" className="input-base pl-10 pr-10" required />
              <button type="button" onClick={() => setAfficherMdp(!afficherMdp)} className="absolute right-3 top-1/2 -translate-y-1/2 text-muted-foreground hover:text-foreground">
                {afficherMdp ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
              </button>
            </div>
          </div>

          <button type="submit" disabled={submitting} className="btn-primary w-full disabled:opacity-50">
            {submitting ? 'Connexion…' : 'Se connecter'}
          </button>
        </form>

        <div className="my-6 flex items-center gap-3">
          <div className="flex-1 h-px bg-border" />
          <span className="text-xs text-muted-foreground">ou</span>
          <div className="flex-1 h-px bg-border" />
        </div>

        <div className="space-y-3">
          <button onClick={() => navigate('/inscription/soignant')} className="btn-secondary w-full text-sm">Créer un compte soignant</button>
          <button onClick={() => navigate('/inscription/etablissement')} className="btn-secondary w-full text-sm">Créer un compte établissement</button>
        </div>

        <p className="text-center mt-4">
          <a href="#" className="text-sm text-primary hover:underline">Mot de passe oublié ?</a>
        </p>
      </div>
    </div>
  );
}
