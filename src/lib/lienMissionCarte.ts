/** Préserve la navigation SPA et les clics modifiés ouvrant un nouvel onglet. */
export function relierMissionCarte(lien: HTMLAnchorElement, route: string, navigate: (route: string) => void) {
  lien.href = route;
  lien.addEventListener('click', (event) => {
    if (event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
    event.preventDefault();
    navigate(route);
  });
}
