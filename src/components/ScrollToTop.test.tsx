import { act, fireEvent, render, screen } from '@testing-library/react';
import { MemoryRouter, Link, useNavigate, useLocation } from 'react-router-dom';
import { beforeEach, afterEach, describe, expect, it, vi } from 'vitest';
import { ScrollToTop } from './ScrollToTop';
import { AuthLayout } from './AuthLayout';
vi.mock('@/contexts/AuthContext', () => ({ useAuth: () => ({ user: { id: 'soignant-1' } }) }));
let height = 3000;
let resize!: () => void;
beforeEach(() => {
  height = 3000;
  Object.defineProperty(window, 'scrollY', { writable: true, configurable: true, value: 0 });
  vi.spyOn(window, 'scrollTo').mockImplementation(((opts: ScrollToOptions) => {
    window.scrollY = Math.min(opts.top || 0, height);
  }) as typeof window.scrollTo);
  Object.defineProperty(HTMLElement.prototype, 'scrollTo', {
    configurable: true,
    value: vi.fn(function (this: HTMLElement, opts: ScrollToOptions) { this.scrollTop = Math.min(opts.top || 0, height); }),
  });
  vi.stubGlobal('ResizeObserver', class { constructor(callback: () => void) { resize = callback; } observe() {} unobserve() {} disconnect() {} });
});
afterEach(() => { vi.restoreAllMocks(); vi.unstubAllGlobals(); });
function Navigation() {
  const navigate = useNavigate();
  return <><ScrollToTop /><Link to="/soignant/recherche-missions">Explorer</Link><Link to="/detail">Détail</Link><Link to="/soignant/mon-compte">Profil</Link><button onClick={() => navigate(-1)}>Retour</button></>;
}
const setup = () => render(<MemoryRouter initialEntries={['/soignant/recherche-missions']}><Navigation /></MemoryRouter>);
const scroll = (y: number) => { window.scrollY = y; fireEvent.scroll(window); };

describe('restauration de la position de lecture', () => {
  it('revient à la position de la liste après le détail et après un changement d’onglet', () => {
    setup(); scroll(620);
    fireEvent.click(screen.getByText('Détail'));
    expect(window.scrollY).toBe(0);
    fireEvent.click(screen.getByText('Retour'));
    expect(window.scrollY).toBe(620);
    fireEvent.click(screen.getByText('Profil'));
    expect(window.scrollY).toBe(0);
    fireEvent.click(screen.getByText('Explorer'));
    expect(window.scrollY).toBe(620);
  });
  it('attend le contenu lazy sans écraser la position mémorisée', () => {
    setup(); scroll(700);
    fireEvent.click(screen.getByText('Détail'));
    height = 0;
    fireEvent.click(screen.getByText('Retour'));
    expect(window.scrollY).toBe(0);
    height = 3000;
    act(() => resize());
    expect(window.scrollY).toBe(700);
  });
  it('cesse de restaurer dès que la personne reprend le défilement', () => {
    setup(); scroll(700);
    fireEvent.click(screen.getByText('Détail'));
    height = 0;
    fireEvent.click(screen.getByText('Retour'));
    fireEvent.touchStart(window);
    height = 3000;
    scroll(150);
    act(() => resize());
    expect(window.scrollY).toBe(150);
  });

  it('conserve la position quand seuls les paramètres de la même page changent', () => {
    function Documents() {
      const navigate = useNavigate();
      return <><ScrollToTop />
        <button onClick={() => navigate('?tab=contrats', { replace: true })}>Contrats</button>
        <Link to="/detail">Détail</Link>
        <button onClick={() => navigate(-1)}>Retour</button>
      </>;
    }
    render(<MemoryRouter initialEntries={['/soignant/mes-documents?tab=justificatifs']}><Documents /></MemoryRouter>);
    scroll(220);
    fireEvent.click(screen.getByText('Contrats'));
    expect(window.scrollY).toBe(220);
    fireEvent.click(screen.getByText('Détail'));
    expect(window.scrollY).toBe(0);
    fireEvent.click(screen.getByText('Retour'));
    expect(window.scrollY).toBe(220);
  });

  it('restaure le conteneur du formulaire au retour, sans déplacer la fenêtre', () => {
    function Formulaire() {
      const { pathname } = useLocation();
      const navigate = useNavigate();
      return <><ScrollToTop />
        {pathname === '/inscription/completer'
          ? <AuthLayout scrollKey={2}><form><input aria-label="RPPS" /><Link to="/cgu">CGU</Link></form></AuthLayout>
          : <button onClick={() => navigate(-1)}>Revenir au formulaire</button>}
      </>;
    }
    render(<MemoryRouter initialEntries={['/inscription/completer']}><Formulaire /></MemoryRouter>);
    const main = screen.getByRole('main');
    main.scrollTop = 620;
    fireEvent.scroll(main);
    fireEvent.click(screen.getByText('CGU'));
    expect(window.scrollY).toBe(0);
    scroll(90);
    fireEvent.click(screen.getByText('Revenir au formulaire'));
    expect(screen.getByRole('main').scrollTop).toBe(620);
    expect(window.scrollY).toBe(0);
  });
});
