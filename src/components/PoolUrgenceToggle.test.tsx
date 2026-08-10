import { render, screen, waitFor } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';
import { PoolUrgenceToggle } from './PoolUrgenceToggle';
import { supabase } from '@/integrations/supabase/client';

class ResizeObserverMock {
  observe() {}
  unobserve() {}
  disconnect() {}
}

vi.stubGlobal('ResizeObserver', ResizeObserverMock);

vi.mock('@/contexts/AuthContext', () => ({
  useAuth: () => ({ user: { id: 'soignant-test' } }),
}));

vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    from: vi.fn(),
    rpc: vi.fn(),
  },
}));

describe('PoolUrgenceToggle', () => {
  it("se resynchronise sur l'état canonique reçu après le chargement", () => {
    const { rerender } = render(
      <PoolUrgenceToggle actif={false} rayonKm={30} smsOptIn={false} />,
    );

    expect(screen.getByRole('switch', { name: /Disponible pour les remplacements/i }))
      .toHaveAttribute('aria-checked', 'false');

    rerender(<PoolUrgenceToggle actif rayonKm={42} smsOptIn />);

    expect(screen.getByRole('switch', { name: /Disponible pour les remplacements/i }))
      .toHaveAttribute('aria-checked', 'true');
    expect(screen.getByText('42 km')).toBeInTheDocument();
    expect(screen.getByRole('switch', { name: /Recevoir les alertes du pool urgence par SMS/i }))
      .toHaveAttribute('aria-checked', 'true');
  });

  it("relit l'opt-in SMS canonique même si l'état et le rayon sont déjà fournis", async () => {
    vi.mocked(supabase.from).mockReturnValue({
      select: () => ({
        eq: () => ({
          maybeSingle: () => Promise.resolve({
            data: {
              disponible_urgence: true,
              urgence_rayon_km: 30,
              pool_urgence_sms_opt_in: true,
            },
            error: null,
          }),
        }),
      }),
    } as any);

    render(<PoolUrgenceToggle actif rayonKm={30} />);

    await waitFor(() => expect(
      screen.getByRole('switch', { name: /Recevoir les alertes du pool urgence par SMS/i }),
    ).toHaveAttribute('aria-checked', 'true'));
  });
});
