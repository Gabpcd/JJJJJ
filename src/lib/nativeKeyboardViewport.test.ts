import { afterEach, describe, expect, it, vi } from 'vitest';
import { keepNativeFieldVisible } from './nativeKeyboardViewport';

afterEach(() => {
  document.body.innerHTML = '';
  vi.restoreAllMocks();
});

function formFixture(rect: Partial<DOMRect>, scrollerTop = 0, scrollerHeight = 900) {
  const scroller = document.createElement('main');
  scroller.style.overflowY = 'auto';
  scroller.scrollTop = 100;
  const input = document.createElement('input');
  scroller.append(input);
  document.body.append(scroller);
  vi.spyOn(scroller, 'getBoundingClientRect').mockReturnValue({
    x: 0, y: scrollerTop, top: scrollerTop, left: 0, right: 300,
    bottom: scrollerTop + scrollerHeight, width: 300, height: scrollerHeight,
    toJSON: () => ({}),
  });
  vi.spyOn(scroller, 'clientHeight', 'get').mockReturnValue(scrollerHeight);
  vi.spyOn(input, 'getBoundingClientRect').mockReturnValue({
    x: 0, y: 0, top: 0, left: 0, right: 300, bottom: 48,
    width: 300, height: 48, toJSON: () => ({}),
    ...rect,
  });
  return { scroller, input };
}

describe('visibilité des champs avec le clavier natif', () => {
  it('remonte seulement la partie masquée par le clavier', () => {
    const { scroller, input } = formFixture({ top: 520, bottom: 568 });

    expect(keepNativeFieldVisible(input, 560)).toBe(true);
    expect(scroller.scrollTop).toBe(128);
  });

  it('ne déplace pas un champ déjà visible dans le formulaire sous le header', () => {
    const { scroller, input } = formFixture({ top: 240, bottom: 288 }, 110, 450);

    expect(keepNativeFieldVisible(input, 560)).toBe(false);
    expect(scroller.scrollTop).toBe(100);
  });

  it('redescend minimalement un champ passé sous le header', () => {
    const { scroller, input } = formFixture({ top: 90, bottom: 138 }, 110, 450);

    expect(keepNativeFieldVisible(input, 560)).toBe(true);
    expect(scroller.scrollTop).toBe(68);
  });

  it('respecte le bas du scroller même si le viewport est plus haut', () => {
    const { scroller, input } = formFixture({ top: 382, bottom: 430 }, 110, 290);

    expect(keepNativeFieldVisible(input, 560)).toBe(true);
    expect(scroller.scrollTop).toBe(150);
  });

  it('respecte le clavier quand il coupe le bas du scroller', () => {
    const { scroller, input } = formFixture({ top: 480, bottom: 528 }, 110, 700);

    expect(keepNativeFieldVisible(input, 500)).toBe(true);
    expect(scroller.scrollTop).toBe(148);
  });

  it('ne tente pas de défiler un conteneur hors du viewport', () => {
    const { scroller, input } = formFixture({ top: 620, bottom: 668 }, 600, 290);

    expect(keepNativeFieldVisible(input, 560)).toBe(false);
    expect(scroller.scrollTop).toBe(100);
  });
});
