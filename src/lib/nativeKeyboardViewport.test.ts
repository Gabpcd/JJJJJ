import { afterEach, describe, expect, it, vi } from 'vitest';
import { keepNativeFieldVisible } from './nativeKeyboardViewport';

afterEach(() => {
  document.body.innerHTML = '';
  vi.restoreAllMocks();
});

function formFixture(rect: Partial<DOMRect>) {
  const scroller = document.createElement('main');
  scroller.style.overflowY = 'auto';
  scroller.scrollTop = 100;
  const input = document.createElement('input');
  scroller.append(input);
  document.body.append(scroller);
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

  it('ne déplace pas un champ déjà visible', () => {
    const { scroller, input } = formFixture({ top: 240, bottom: 288 });

    expect(keepNativeFieldVisible(input, 560)).toBe(false);
    expect(scroller.scrollTop).toBe(100);
  });

  it('redescend minimalement un champ passé sous le header', () => {
    const { scroller, input } = formFixture({ top: 4, bottom: 52 });

    expect(keepNativeFieldVisible(input, 560)).toBe(true);
    expect(scroller.scrollTop).toBe(92);
  });
});
