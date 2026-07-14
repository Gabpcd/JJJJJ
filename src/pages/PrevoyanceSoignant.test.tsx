import { fireEvent, render, screen } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';
import PrevoyanceSoignant from './PrevoyanceSoignant';

const authUser = { id: 'soignant-test' };

vi.mock('@/components/LayoutApp', () => ({
  LayoutApp: ({ children }: { children: React.ReactNode }) => <>{children}</>,
}));

vi.mock('@/contexts/AuthContext', () => ({
  useAuth: () => ({ user: authUser }),
}));

vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    from: (table: string) => {
      const response = table === 'soignants'
        ? { data: { email: 'soignant@test.dev' }, error: null }
        : { data: null, error: null };
      const builder = {
        select: () => builder,
        eq: () => builder,
        maybeSingle: () => Promise.resolve(response),
      };
      return builder;
    },
    rpc: vi.fn(),
  },
}));

describe('PrevoyanceSoignant', () => {
  it('calcule avec Bronze lorsque Bronze est affiché par défaut', async () => {
    render(<PrevoyanceSoignant />);

    const select = await screen.findByLabelText('Niveau de couverture', { exact: true });
    expect(select).toHaveValue('BRONZE');
    const couvertureBronze = screen.getByText('Couverture Bronze (30%)');
    expect(couvertureBronze).toBeInTheDocument();
    expect(couvertureBronze.parentElement).toHaveTextContent(/1.?050.*€/);
    expect(screen.queryByText(/Couverture Indifférent/)).not.toBeInTheDocument();

    fireEvent.change(select, { target: { value: 'ARGENT' } });
    const couvertureArgent = screen.getByText('Couverture Argent (50%)');
    expect(couvertureArgent).toBeInTheDocument();
    expect(couvertureArgent.parentElement).toHaveTextContent(/1.?750.*€/);
  });
});
