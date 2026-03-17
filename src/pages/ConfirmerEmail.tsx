import React from 'react';
import { Mail } from 'lucide-react';
import { useAuth } from '@/contexts/AuthContext';
import logoJolene from '@/assets/logo-jolene.png';

export default function ConfirmerEmail() {
  const { deconnexion } = useAuth();

  return (
    <div className="min-h-screen gradient-hero flex items-center justify-center px-4">
      <div className="card-base max-w-md w-full text-center">
        <div className="flex items-center justify-center mb-6">
          <img src={logoJolene} alt="Jolene" className="h-16 w-auto" />
        </div>

        <Mail className="h-16 w-16 text-primary mx-auto mb-4" />

        <h1 className="text-xl font-bold text-foreground mb-3">Vérifiez votre adresse email</h1>

        <p className="text-sm text-muted-foreground mb-6">
          Un email de confirmation vous a été envoyé. Cliquez sur le lien dans cet email pour activer votre compte et accéder à l'application.
        </p>

        <div className="bg-primary/5 border border-primary/20 rounded-xl p-4 mb-6">
          <p className="text-xs text-muted-foreground">
            💡 Si vous ne trouvez pas l'email, vérifiez votre dossier spam. Le lien expire après 24 heures.
          </p>
        </div>

        <button
          onClick={() => deconnexion()}
          className="btn-secondary w-full text-sm"
        >
          Retour à la connexion
        </button>
      </div>
    </div>
  );
}
