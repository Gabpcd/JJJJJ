import { ReactNode } from 'react';
import { useNavigate } from 'react-router-dom';
import { ArrowLeft } from 'lucide-react';

interface AuthLayoutProps {
  children: ReactNode;
  /** Affiche un bouton retour en haut à gauche (défaut: true). */
  showBack?: boolean;
  /** Destination du retour. Si absent → navigate(-1). */
  backTo?: string;
}

/**
 * Layout commun aux écrans publics (connexion / inscription).
 * - Gère la safe-area top en natif (pas de vide blanc).
 * - Header léger avec bouton retour (navigation app-like).
 * - Contenu scrollable + centré, fond gradient-hero.
 * Identique sur web et natif (sur web, safe-area = 0).
 */
export function AuthLayout({ children, showBack = true, backTo }: AuthLayoutProps) {
  const navigate = useNavigate();

  const handleBack = () => {
    if (backTo) navigate(backTo);
    else if (window.history.length > 1) navigate(-1);
    else navigate('/connexion');
  };

  return (
    <div className="min-h-[100dvh] gradient-hero flex flex-col">
      {/* Header sticky avec safe-area + bouton retour */}
      {showBack && (
        <header
          className="sticky top-0 z-10 flex items-center px-2"
          style={{
            paddingTop: 'calc(env(safe-area-inset-top) + 0.5rem)',
            paddingBottom: '0.5rem',
          }}
        >
          <button
            onClick={handleBack}
            aria-label="Retour"
            className="flex items-center gap-1 p-2 rounded-xl text-foreground/80 hover:text-foreground hover:bg-foreground/5 transition"
          >
            <ArrowLeft className="h-5 w-5" />
            <span className="text-sm font-medium">Retour</span>
          </button>
        </header>
      )}

      {/* Contenu scrollable. Top-aligné sur mobile pour éviter le saut de
          recentrage quand le clavier natif iOS s'ouvre/se ferme (WKWebView
          resize:'native' rétrécit le webview → justify-center recentrerait la
          carte, créant un « rabaissement » visible au clic sur Se connecter).
          Centré verticalement à partir de sm (desktop/tablette, pas de clavier
          natif qui resize). */}
      <main
        id="contenu-principal"
        className="flex-1 flex flex-col items-center justify-start sm:justify-center px-4 py-6"
        style={{
          paddingTop: showBack ? '0.5rem' : 'calc(env(safe-area-inset-top) + 1rem)',
          paddingBottom: 'calc(env(safe-area-inset-bottom) + 1.5rem)',
        }}
      >
        {children}
      </main>
    </div>
  );
}
