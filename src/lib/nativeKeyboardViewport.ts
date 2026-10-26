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

  // Un formulaire peut défiler dans un main situé sous un header fixe. Ses
  // limites visibles sont l'intersection de son contenu et du viewport.
  let visibleTop = 0;
  let visibleBottom = viewportHeight;
  if (scrollParent !== document.scrollingElement) {
    const parentTop = scrollParent.getBoundingClientRect().top + scrollParent.clientTop;
    visibleTop = Math.max(visibleTop, parentTop);
    visibleBottom = Math.min(visibleBottom, parentTop + scrollParent.clientHeight);
  }
  if (visibleBottom <= visibleTop) return false;

  const topLimit = visibleTop + FIELD_TOP_GAP_PX;
  const bottomLimit = visibleBottom - FIELD_BOTTOM_GAP_PX;
  let delta = 0;
  if (rect.bottom > bottomLimit) delta = rect.bottom - bottomLimit;
  else if (rect.top < topLimit) delta = rect.top - topLimit;

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
