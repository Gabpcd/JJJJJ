const FIELD_BOTTOM_GAP_PX = 20;
const FIELD_TOP_GAP_PX = 12;

function findScrollableParent(element: HTMLElement): HTMLElement | null {
  let parent = element.parentElement;
  while (parent) {
    const { overflowY } = window.getComputedStyle(parent);
    if (overflowY === 'auto' || overflowY === 'scroll') return parent;
    parent = parent.parentElement;
  }
  return null;
}

/**
 * Ajuste uniquement la quantité de scroll nécessaire après le resize natif du
 * WKWebView. Contrairement à scrollIntoView({ block: 'center' }), cela ne
 * recentre pas toute la page et évite le « saut » visuel au focus.
 */
export function keepNativeFieldVisible(
  field: HTMLElement,
  viewportHeight = window.visualViewport?.height ?? window.innerHeight,
): boolean {
  const rect = field.getBoundingClientRect();
  const scrollParent = findScrollableParent(field)
    ?? (document.scrollingElement as HTMLElement | null);
  if (!scrollParent) return false;

  const bottomLimit = viewportHeight - FIELD_BOTTOM_GAP_PX;
  let delta = 0;
  if (rect.bottom > bottomLimit) delta = rect.bottom - bottomLimit;
  else if (rect.top < FIELD_TOP_GAP_PX) delta = rect.top - FIELD_TOP_GAP_PX;

  if (Math.abs(delta) < 1) return false;
  scrollParent.scrollTop += delta;
  return true;
}

export function activeEditableField(): HTMLElement | null {
  const active = document.activeElement;
  if (
    active instanceof HTMLInputElement
    || active instanceof HTMLTextAreaElement
    || active instanceof HTMLSelectElement
    || active?.getAttribute('contenteditable') === 'true'
  ) {
    return active as HTMLElement;
  }
  return null;
}
