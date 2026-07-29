import { usePageTitle } from '@/hooks/usePageTitle';
import React from 'react';
import { Mail } from 'lucide-react';
import { LogoJolene } from '@/components/LogoJolene';
import { useAuth } from '@/contexts/AuthContext';

export default function ConfirmerEmail() {
  usePageTitle('Confirmer Email');
  const { deconnexion } = useAuth();

  return (
    <div className="min-h-[100dvh] gradient-hero flex items-center justify-center px-4">
      <div className="card-base max-w-md w-full text-center">
        <LogoJolene
          className="mx-auto mb-6 flex w-fit"
          imageClassName="h-8 w-8"
          nomClassName="text-2xl text-rose"
        />

        <Mail className="h-16 w-16 text-primary mx-auto mb-4" />

        <h1 className="text-xl font-bold text-foreground mb-3">Vérifie ton adresse email</h1>

        <p className="text-sm text-muted-foreground mb-6">
          Un email de confirmation t'a été envoyé. Clique sur le lien dans cet email pour activer ton compte et accéder à l'application.
        </p>

        <div className="bg-primary/5 border border-primary/20 rounded-xl p-4 mb-6">
          <p className="text-xs text-muted-foreground">
            💡 Si tu ne trouves pas l'email, vérifie ton dossier spam. Le lien expire après 24 heures.
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
