import { LogOut, ShieldX } from 'lucide-react';
import { useNavigate } from 'react-router-dom';
import { useAuth } from '@/contexts/AuthContext';
import { usePageTitle } from '@/hooks/usePageTitle';

export default function AccesAdminIndisponible() {
  usePageTitle('Accès administrateur indisponible');
  const { deconnexion } = useAuth();
  const navigate = useNavigate();

  const seDeconnecter = async () => {
    await deconnexion();
    navigate('/connexion', { replace: true });
  };

  return (
    <main className="flex min-h-[100dvh] items-center justify-center bg-background px-4">
      <section className="w-full max-w-lg rounded-2xl border border-border bg-card p-6 text-center shadow-sm" aria-labelledby="admin-access-denied-title">
        <ShieldX className="mx-auto mb-4 h-12 w-12 text-destructive" aria-hidden="true" />
        <h1 id="admin-access-denied-title" className="text-xl font-bold text-foreground">Accès administrateur indisponible</h1>
        <p className="mt-3 text-sm text-muted-foreground">
          Pendant la phase de lancement, seuls les comptes disposant de l’ensemble des périmètres administrateur peuvent accéder à l’administration Jolene.
        </p>
        <p className="mt-2 text-sm text-muted-foreground">
          Contactez la fondatrice pour faire vérifier votre compte.
        </p>
        <button type="button" onClick={() => void seDeconnecter()} className="btn-secondary mt-6 inline-flex min-h-11 items-center justify-center gap-2 px-5">
          <LogOut className="h-4 w-4" aria-hidden="true" /> Se déconnecter
        </button>
      </section>
    </main>
  );
}
