import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { BandeauHorsLigne } from './BandeauHorsLigne';

describe('BandeauHorsLigne', () => {
  beforeEach(() => {
    vi.spyOn(navigator, 'onLine', 'get').mockReturnValue(false);
    vi.stubGlobal('fetch', vi.fn());
  });

  afterEach(() => {
    vi.restoreAllMocks();
    vi.unstubAllGlobals();
  });

  it("ne déclare pas Safari hors ligne lorsqu'une vraie requête aboutit", async () => {
    vi.mocked(fetch).mockResolvedValue({ status: 200 } as Response);

    render(<BandeauHorsLigne />);

    await waitFor(() => expect(fetch).toHaveBeenCalled());
    expect(screen.queryByRole('alert')).not.toBeInTheDocument();
  });

  it('reste non bloquant et disparaît après une reconnexion confirmée', async () => {
    vi.mocked(fetch)
      .mockRejectedValueOnce(new Error('offline'))
      .mockResolvedValueOnce({ status: 200 } as Response);

    render(<BandeauHorsLigne />);

    const bandeau = await screen.findByRole('alert');
    expect(bandeau).toHaveClass('pointer-events-none');
    const retry = screen.getByRole('button', { name: 'Réessayer la connexion' });
    expect(retry).toHaveClass('pointer-events-auto');

    fireEvent.click(retry);
    await waitFor(() => expect(screen.queryByRole('alert')).not.toBeInTheDocument());
  });
});
