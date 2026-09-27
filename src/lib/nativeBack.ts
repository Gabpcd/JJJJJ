type BackOptions = {
  document: Document;
  pathname: () => string;
  back: () => void;
  exit: () => void;
  notify: () => void;
  now?: () => number;
};

const MAIN_ROUTES = new Set([
  '/soignant/tableau-de-bord', '/etablissement/tableau-de-bord',
  '/groupe/tableau-de-bord', '/admin', '/',
]);

function visible(element: HTMLElement, view: Window) {
  if (!element.getClientRects().length) return false;
  for (let node: HTMLElement | null = element; node; node = node.parentElement) {
    const style = view.getComputedStyle(node);
    if (node.hidden || node.getAttribute('aria-hidden') === 'true'
      || style.display === 'none' || style.visibility === 'hidden') return false;
  }
  return true;
}

function dismissActiveLayer(document: Document): boolean {
  const view = document.defaultView;
  if (!view) return false;
  // Presence retains an exiting Radix modal until animationend; it still
  // locks the body and hides the parent. A second Back during that interval
  // must not navigate behind the still-open parent or bypass its confirmation.
  if (document.body.style.pointerEvents === 'none'
    && Array.from(document.querySelectorAll<HTMLElement>(
      '[role="dialog"][data-state="closed"], [role="alertdialog"][data-state="closed"], '
      + '[role="menu"][data-state="closed"], [role="listbox"][data-state="closed"]',
    )).some((element) => element.style.pointerEvents === 'auto' && visible(element, view))) return true;
  const candidates = Array.from(document.querySelectorAll<HTMLElement>(
    '[aria-modal="true"], [role="dialog"][data-state="open"], '
    + '[role="alertdialog"][data-state="open"], '
    + '[data-radix-popper-content-wrapper] [role="menu"][data-state="open"], '
    + '[data-radix-popper-content-wrapper] [role="listbox"][data-state="open"]',
  ));
  const layer = candidates.reverse().find((element) => {
    if (element.dataset.state === 'closed' || !visible(element, view)) return false;
    if (element.getAttribute('aria-modal') === 'true') return true;
    if (element.matches('[role="menu"], [role="listbox"]')) return true;
    // Radix modal Dialog/Sheet/AlertDialog locks the body and enables its
    // active DismissableLayer. A persistent nonmodal role=dialog must not
    // prevent normal navigation merely because that role is present.
    return document.body.style.pointerEvents === 'none' && element.style.pointerEvents === 'auto';
  });
  if (!layer) return false;

  // Radix listens in document capture and dismisses only its top layer.
  // Respect prevented Escape (confirmation/unsaved form); never click an
  // action. Once handled, do not also close a custom parent menu in bubble.
  const stopHandledEscape = (event: KeyboardEvent) => {
    if (event.key === 'Escape' && event.defaultPrevented) event.stopImmediatePropagation();
  };
  document.addEventListener('keydown', stopHandledEscape, true);
  try {
    const target = document.activeElement && layer.contains(document.activeElement) ? document.activeElement : layer;
    target.dispatchEvent(new view.KeyboardEvent('keydown', { key: 'Escape', code: 'Escape', bubbles: true, cancelable: true }));
  } finally {
    document.removeEventListener('keydown', stopHandledEscape, true);
  }
  return true;
}

export function createNativeBackHandler(options: BackOptions) {
  let lastBackPress: number | null = null;
  return ({ canGoBack }: { canGoBack: boolean }) => {
    // Android consumes Back for its IME before Capacitor calls this handler.
    if (dismissActiveLayer(options.document)) {
      lastBackPress = null;
      return;
    }
    const rawPath = options.pathname();
    const path = rawPath.length > 1 ? rawPath.replace(/\/+$/, '') : rawPath;
    if (canGoBack && !MAIN_ROUTES.has(path)) {
      lastBackPress = null;
      options.back();
    }
    else {
      const now = (options.now ?? Date.now)();
      if (lastBackPress !== null && now - lastBackPress < 2000) options.exit();
      else { lastBackPress = now; options.notify(); }
    }
  };
}
