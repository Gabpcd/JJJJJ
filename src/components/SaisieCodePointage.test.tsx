import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';
import { SaisieCodePointage } from './SaisieCodePointage';

describe('SaisieCodePointage', () => {
  it('utilise toujours le validateur courant après une mise à jour du parent', async () => {
    const ancienValidateur = vi.fn().mockResolvedValue({ success: true });
    const validateurCourant = vi.fn().mockResolvedValue({ success: true });
    const vue = render(<SaisieCodePointage type="arrivee" onValider={ancienValidateur} />);

    fireEvent.click(screen.getByRole('button', { name: 'Pointer avec un code' }));
    vue.rerender(<SaisieCodePointage type="arrivee" onValider={validateurCourant} />);

    fireEvent.paste(screen.getAllByRole('textbox')[0], {
      clipboardData: { getData: () => '123456' },
    });

    await waitFor(() => expect(validateurCourant).toHaveBeenCalledWith('123456'));
    expect(ancienValidateur).not.toHaveBeenCalled();
  });
});
