import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { describe, expect, it, vi } from 'vitest';
import PageStripeConnect from './PageStripeConnect';

vi.mock('@/components/LayoutApp', () => ({
  LayoutApp: ({ children }: { children: React.ReactNode }) => <>{children}</>,
}));

vi.mock('@/components/ModalContacterJolene', () => ({
  ModalContacterJolene: () => null,
}));

const { utilisateurTest } = vi.hoisted(() => ({
  utilisateurTest: { id: 'soignant-test' },
}));

vi.mock('@/contexts/AuthContext', () => ({
  // Conserver la même référence reproduit le contexte réel et évite que
  // l'effet dépendant de `user` relance artificiellement le chargement.
  useAuth: () => ({ user: utilisateurTest }),
}));

vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    from: () => {
      const builder = {
        select: () => builder,
        eq: () => builder,
        maybeSingle: () => Promise.resolve({
          data: {
            prenom: 'Marie',
            nom: 'Lefèvre',
            type_exercice: 'SALARIE',
            statut_liberal: null,
          },
          error: null,
        }),
      };
      return builder;
    },
    functions: { invoke: vi.fn() },
    rpc: vi.fn(),
  },
}));

describe('PageStripeConnect', () => {
  it('expose Paiements comme titre principal accessible', async () => {
    render(
      <MemoryRouter>
        <PageStripeConnect />
      </MemoryRouter>,
    );

    const titre = await screen.findByRole('heading', { level: 1, name: 'Paiements' });
    expect(titre.tagName).toBe('H1');
    expect(titre).toHaveAccessibleName('Paiements');
  });

  it('expose les raccourcis salarié comme de vrais liens clavier', async () => {
    render(
      <MemoryRouter>
        <PageStripeConnect />
      </MemoryRouter>,
    );

    expect(await screen.findByRole('link', { name: /Mes gains/i })).toHaveAttribute('href', '/soignant/mes-gains');
    expect(screen.getByRole('link', { name: /Mes présences/i })).toHaveAttribute('href', '/soignant/presences');
    expect(screen.getByRole('link', { name: /Mes contrats/i })).toHaveAttribute('href', '/soignant/contrats');
    expect(screen.getByRole('link', { name: /Passer en libéral/i })).toHaveAttribute('href', '/soignant/passer-en-liberal');
  });
});
