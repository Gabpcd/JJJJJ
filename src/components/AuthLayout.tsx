import {
  ReactNode,
  useLayoutEffect,
  useRef,
  type MouseEvent as ReactMouseEvent,
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
  const previousStep = useRef(scrollKey);

  useLayoutEffect(() => {
    const scrollContainer = scrollRef.current;
    // Le retour historique est restauré par ScrollToTop, y compris dans ce
    // conteneur interne. Seul un changement d'étape repart en haut.
    if (previousStep.current !== scrollKey) {
      scrollContainer?.scrollTo({ top: 0, behavior: 'instant' });
      previousStep.current = scrollKey;
    }
    if (!scrollContainer) return;

    // WKWebView n'infère pas toujours « Suivant » entre les champs d'un même
    // formulaire. L'indiquer explicitement donne un clavier iOS cohérent et
    // permet de progresser sans devoir masquer le clavier pour atteindre le
    // champ suivant.
    const updateKeyboardHints = (form: HTMLFormElement) => {
      const fields = keyboardFields(form);
      fields.forEach((field, index) => {
        if (field instanceof HTMLInputElement || field instanceof HTMLTextAreaElement) {
          field.enterKeyHint = index < fields.length - 1 ? 'next' : 'done';
        }
      });
      return fields;
    };
    scrollContainer.querySelectorAll('form').forEach(updateKeyboardHints);

    const handleFocus = (event: FocusEvent) => {
      const field = event.target;
      if (!(field instanceof HTMLInputElement || field instanceof HTMLTextAreaElement || field instanceof HTMLSelectElement)) return;
      if (field.form && scrollContainer.contains(field.form)) updateKeyboardHints(field.form);
    };

    // Capturer l'événement DOM avant la délégation React conserve le transfert
    // synchrone du focus dans WKWebView. La liste doit être relue à chaque
    // appui : étudiant/RPPS peuvent être ajoutés ou retirés sans changer d'étape.
    const handleEnter = (event: KeyboardEvent) => {
      if (event.key !== 'Enter' || event.isComposing || event.defaultPrevented) return;
      const field = event.target;
      if (!(field instanceof HTMLInputElement) || !field.form || !scrollContainer.contains(field.form)) return;
      const fields = updateKeyboardHints(field.form);
      const index = fields.indexOf(field);
      const next = index >= 0 ? fields[index + 1] : undefined;
      if (!next) return;

      event.preventDefault();
      next.focus({ preventScroll: true });
    };
    scrollContainer.addEventListener('focusin', handleFocus);
    scrollContainer.addEventListener('keydown', handleEnter, true);

    return () => {
      scrollContainer.removeEventListener('focusin', handleFocus);
      scrollContainer.removeEventListener('keydown', handleEnter, true);
    };
  }, [scrollKey]);

  const handleBack = () => {
    if (backTo) navigate(backTo);
    else if (window.history.length > 1) navigate(-1);
    else navigate('/connexion');
  };

  const handleBackgroundClick = (event: ReactMouseEvent<HTMLElement>) => {
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
          Centré verticalement à partir de sm si le formulaire tient à l'écran.
          Les marges auto reviennent à zéro quand le contenu déborde, notamment
          après le chargement du captcha ou l'affichage d'erreurs. */}
      <main
        ref={scrollRef}
        id="contenu-principal"
        data-scroll-restoration="auth"
        className="auth-scroll min-h-0 flex-1 flex w-full flex-col items-center justify-start sm:[&>:first-child]:mt-auto sm:[&>:last-child]:mb-auto sm:[&>*]:shrink-0 px-4 py-6"
        onClick={handleBackgroundClick}
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
    !field.matches(':disabled')
    && (!(field instanceof HTMLInputElement || field instanceof HTMLTextAreaElement) || !field.readOnly)
    && isKeyboardFieldVisible(field)
  ));
}

function isKeyboardFieldVisible(field: HTMLElement): boolean {
  if (field.closest('[hidden], [inert]')) return false;
  for (let element: HTMLElement | null = field; element; element = element.parentElement) {
    const style = window.getComputedStyle(element);
    if (style.display === 'none' || style.visibility === 'hidden' || style.visibility === 'collapse') return false;
  }
  return true;
}
