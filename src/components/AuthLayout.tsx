import {
  ReactNode,
  useLayoutEffect,
  useRef,
  type PointerEvent as ReactPointerEvent,
} from 'react';
import { useNavigate } from 'react-router-dom';
import { ArrowLeft } from 'lucide-react';

interface AuthLayoutProps {
  children: ReactNode;
  /** Affiche un bouton retour en haut à gauche (défaut: true). */
  showBack?: boolean;
  /** Destination du retour. Si absent → navigate(-1). */
  backTo?: string;
  /** Remet le contenu en haut avant l'affichage d'une nouvelle étape. */
  scrollKey?: string | number;
}

/**
 * Layout commun aux écrans publics (connexion / inscription).
 * - Gère la safe-area top en natif (pas de vide blanc).
 * - Header léger avec bouton retour (navigation app-like).
 * - Contenu scrollable + centré, fond gradient-hero.
 * Identique sur web et natif (sur web, safe-area = 0).
 */
export function AuthLayout({ children, showBack = true, backTo, scrollKey }: AuthLayoutProps) {
  const navigate = useNavigate();
  const scrollRef = useRef<HTMLElement>(null);

  useLayoutEffect(() => {
    scrollRef.current?.scrollTo({ top: 0, behavior: 'auto' });

    // WKWebView n'infère pas toujours « Suivant » entre les champs d'un même
    // formulaire. L'indiquer explicitement donne un clavier iOS cohérent et
    // permet de progresser sans devoir masquer le clavier pour atteindre le
    // champ suivant.
    const forms = scrollRef.current?.querySelectorAll('form') ?? [];
    const cleanups: Array<() => void> = [];
    forms.forEach((form) => {
      const fields = keyboardFields(form);
      fields.forEach((field, index) => {
        if (field instanceof HTMLInputElement || field instanceof HTMLTextAreaElement) {
          field.enterKeyHint = index < fields.length - 1 ? 'next' : 'done';
        }

        // Un listener DOM direct est volontaire ici : dans WKWebView, la
        // touche Return du clavier logiciel peut masquer le clavier avant que
        // la délégation d'événement React ait transféré le focus. Intercepter
        // le keydown sur le champ conserve le clavier et produit le parcours
        // natif attendu.
        if (field instanceof HTMLInputElement) {
          const handleEnter = (event: KeyboardEvent) => {
            if (event.key !== 'Enter' || event.isComposing) return;
            const next = fields[index + 1];
            if (!next) return;

            event.preventDefault();
            next.focus({ preventScroll: true });
          };
          field.addEventListener('keydown', handleEnter);
          cleanups.push(() => field.removeEventListener('keydown', handleEnter));
        }
      });
    });

    return () => cleanups.forEach((cleanup) => cleanup());
  }, [scrollKey]);

  const handleBack = () => {
    if (backTo) navigate(backTo);
    else if (window.history.length > 1) navigate(-1);
    else navigate('/connexion');
  };

  const handleBackgroundPointerDown = (event: ReactPointerEvent<HTMLElement>) => {
    const target = event.target;
    if (!(target instanceof Element)) return;
    if (target.closest('input, textarea, select, button, a, label, [role="button"], [role="combobox"], [role="dialog"]')) return;

    const active = document.activeElement;
    if (active instanceof HTMLInputElement || active instanceof HTMLTextAreaElement) {
      active.blur();
    }
  };

  return (
    <div className="auth-layout gradient-hero flex flex-col">
      {/* Header sticky avec safe-area + bouton retour */}
      {showBack && (
        <header
          className="auth-header sticky top-0 z-40 flex shrink-0 items-center px-2"
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
        ref={scrollRef}
        id="contenu-principal"
        className="auth-scroll min-h-0 flex-1 flex w-full flex-col items-center justify-start sm:justify-center px-4 py-6"
        onPointerDown={handleBackgroundPointerDown}
        style={{
          paddingTop: showBack ? '0.5rem' : 'calc(env(safe-area-inset-top) + 1rem)',
          paddingBottom: 'calc(env(safe-area-inset-bottom) + 3rem)',
        }}
      >
        {children}
      </main>
    </div>
  );
}

function keyboardFields(form: HTMLFormElement): Array<HTMLInputElement | HTMLTextAreaElement | HTMLSelectElement> {
  return Array.from(form.querySelectorAll<HTMLInputElement | HTMLTextAreaElement | HTMLSelectElement>(
    'input:not([type="hidden"]):not([type="checkbox"]):not([type="radio"]):not([type="button"]):not([type="submit"]), textarea, select',
  )).filter((field) => (
    !field.disabled
    && (!(field instanceof HTMLInputElement || field instanceof HTMLTextAreaElement) || !field.readOnly)
  ));
}
