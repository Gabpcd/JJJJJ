import { act, fireEvent, render, screen } from '@testing-library/react';
import { beforeEach, afterEach, describe, expect, it, vi } from 'vitest';
import { StackCards } from './StackCards';

beforeEach(() => {
  vi.useFakeTimers();
  // jsdom n'implémente pas PointerEvent/capture ; les clics réels sont aussi
  // vérifiés dans la recette navigateur.
  vi.stubGlobal('PointerEvent', MouseEvent);
  HTMLElement.prototype.setPointerCapture = vi.fn();
  HTMLElement.prototype.hasPointerCapture = vi.fn(() => true);
  HTMLElement.prototype.releasePointerCapture = vi.fn();
});
afterEach(() => { vi.useRealTimers(); vi.unstubAllGlobals(); });

function setup() {
  const open = vi.fn(); const swipe = vi.fn();
  render(<StackCards onSwipe={swipe} items={[{ key: 'mission-1', content: <div role="button" tabIndex={0} onClick={open}>Voir la mission</div> }]} />);
  const card = screen.getByRole('button', { name: 'Voir la mission' });
  const gesture = card.parentElement!;
  return { open, swipe, card, gesture };
}
function drag(el: HTMLElement, x: number) {
  fireEvent.pointerDown(el, { clientX: 10, clientY: 10, button: 0 });
  fireEvent.pointerMove(el, { clientX: x, clientY: 12 });
}

describe('tap et gestes des missions', () => {
  it('laisse un appui court ouvrir le détail sans capturer son clic', () => {
    const { card, open, swipe } = setup();
    fireEvent.pointerDown(card, { clientX: 10, clientY: 10, button: 0 });
    fireEvent.pointerUp(card, { clientX: 12, clientY: 10 });
    fireEvent.click(card, { detail: 1 });
    expect(open).toHaveBeenCalledOnce();
    expect(HTMLElement.prototype.setPointerCapture).not.toHaveBeenCalled();
    expect(swipe).not.toHaveBeenCalled();
  });
  it('un drag horizontal déclenche une seule action, jamais une ouverture du détail', () => {
    const { gesture, card, open, swipe } = setup();
    drag(gesture, 150);
    fireEvent.pointerUp(gesture, { clientX: 150, clientY: 12 });
    fireEvent.click(card, { detail: 1 });
    act(() => vi.runAllTimers());
    expect(open).not.toHaveBeenCalled();
    expect(swipe).toHaveBeenCalledExactlyOnceWith('right', 'mission-1');
  });
  it('une annulation système ne valide pas le swipe même au-delà du seuil', () => {
    const { gesture, swipe } = setup();
    drag(gesture, 180);
    fireEvent.pointerCancel(gesture);
    act(() => vi.runAllTimers());
    expect(swipe).not.toHaveBeenCalled();
  });
  it('respecte le défilement vertical et ne capture pas le pointeur', () => {
    const { gesture, swipe } = setup();
    fireEvent.pointerDown(gesture, { clientX: 10, clientY: 10, button: 0 });
    fireEvent.pointerMove(gesture, { clientX: 15, clientY: 150 });
    fireEvent.pointerUp(gesture, { clientX: 15, clientY: 150 });
    act(() => vi.runAllTimers());
    expect(HTMLElement.prototype.setPointerCapture).not.toHaveBeenCalled();
    expect(swipe).not.toHaveBeenCalled();
  });
  it('annule une action en attente si la carte est retirée', () => {
    const swipe = vi.fn();
    const { unmount } = render(<StackCards onSwipe={swipe} items={[{ key: 'm', content: <div>Mission</div> }]} />);
    const gesture = screen.getByText('Mission').parentElement!;
    drag(gesture, 200);
    fireEvent.pointerUp(gesture, { clientX: 200, clientY: 12 });
    unmount();
    act(() => vi.runAllTimers());
    expect(swipe).not.toHaveBeenCalled();
  });
});
