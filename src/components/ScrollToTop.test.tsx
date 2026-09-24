import { act, fireEvent, render, screen } from '@testing-library/react';
import { MemoryRouter, Link, useNavigate } from 'react-router-dom';
import { beforeEach, afterEach, describe, expect, it, vi } from 'vitest';
import { ScrollToTop } from './ScrollToTop';
vi.mock('@/contexts/AuthContext', () => ({ useAuth: () => ({ user: { id: 'soignant-1' } }) }));
let height = 3000;
let resize!: () => void;
beforeEach(() => {
  height = 3000;
  Object.defineProperty(window, 'scrollY', { writable: true, configurable: true, value: 0 });
  vi.spyOn(window, 'scrollTo').mockImplementation(((opts: ScrollToOptions) => {
    window.scrollY = Math.min(opts.top || 0, height);
  }) as typeof window.scrollTo);
  vi.stubGlobal('ResizeObserver', class { constructor(callback: () => void) { resize = callback; } observe() {} disconnect() {} });
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
});
