import { afterEach, describe, expect, it } from 'vitest';
import { cleanup, render } from '@testing-library/react';
import { SEOHead } from './SEOHead';

const scripts = () => Array.from(document.head.querySelectorAll('script[data-jolene-ld]'));

afterEach(() => {
  cleanup();
  document.head.querySelectorAll('script[data-jolene-ld], link[rel="canonical"]').forEach((e) => e.remove());
});

describe('SEOHead : données structurées', () => {
  it('reprend le script du HTML statique au lieu d\'en ajouter un second', () => {
    const statique = document.createElement('script');
    statique.type = 'application/ld+json';
    statique.setAttribute('data-jolene-ld', 'true');
    statique.textContent = '[{"@type":"FAQPage"}]';
    document.head.appendChild(statique);

    render(<SEOHead title="T" description="D" url="https://jolene.app/x" jsonLd={[{ '@type': 'FAQPage' }]} />);

    expect(scripts()).toHaveLength(1);
    expect(scripts()[0]).toBe(statique);
    expect(JSON.parse(statique.textContent!)).toEqual([{ '@type': 'FAQPage' }]);
  });

  it('retire le script de la page précédente quand la page n\'en déclare pas', () => {
    const { rerender } = render(<SEOHead title="A" description="D" jsonLd={{ '@type': 'WebSite' }} />);
    expect(scripts()).toHaveLength(1);
    rerender(<SEOHead title="B" description="D" />);
    expect(scripts()).toHaveLength(0);
  });

  it('traite une liste vide comme une absence de données structurées', () => {
    render(<SEOHead title="A" description="D" jsonLd={[]} />);
    expect(scripts()).toHaveLength(0);
  });

  it('retire son script au démontage et pose le canonical de la page', () => {
    const { unmount } = render(<SEOHead title="A" description="D" url="https://jolene.app/tarifs" jsonLd={{ '@type': 'WebSite' }} />);
    expect(document.head.querySelector('link[rel="canonical"]')?.getAttribute('href')).toBe('https://jolene.app/tarifs');
    unmount();
    expect(scripts()).toHaveLength(0);
  });
});
