import { describe, expect, it, vi } from 'vitest';
import { relierMissionCarte } from './lienMissionCarte';

describe('lien de mission dans la carte', () => {
  it('ouvre le détail avec le routeur sans recharger le document', () => {
    const lien = document.createElement('a');
    const navigate = vi.fn();
    relierMissionCarte(lien, '/soignant/missions/test', navigate);
    const clic = new MouseEvent('click', { cancelable: true, button: 0 });
    lien.dispatchEvent(clic);
    expect(clic.defaultPrevented).toBe(true);
    expect(navigate).toHaveBeenCalledWith('/soignant/missions/test');
    expect(lien.getAttribute('href')).toBe('/soignant/missions/test');
  });

  it('conserve le comportement des clics modifiés', () => {
    const lien = document.createElement('a');
    const navigate = vi.fn();
    relierMissionCarte(lien, '/soignant/missions/test', navigate);
    const clic = new MouseEvent('click', { cancelable: true, metaKey: true });
    let traiteParLien = true;
    // Intercepte seulement le comportement par défaut de jsdom, après le gestionnaire testé.
    lien.addEventListener('click', (event) => {
      traiteParLien = event.defaultPrevented;
      event.preventDefault();
    });
    lien.dispatchEvent(clic);
    expect(traiteParLien).toBe(false);
    expect(navigate).not.toHaveBeenCalled();
  });
});
