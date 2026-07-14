import { fireEvent, render, screen } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';
import { CardY2K } from './CardY2K';

describe('CardY2K', () => {
  it('rend une carte cliquable accessible au clavier', () => {
    const onClick = vi.fn();
    render(<CardY2K onClick={onClick}>Ouvrir la facturation</CardY2K>);

    const carte = screen.getByRole('button', { name: 'Ouvrir la facturation' });
    expect(carte).toHaveAttribute('tabindex', '0');

    fireEvent.keyDown(carte, { key: 'Enter' });
    fireEvent.keyDown(carte, { key: ' ' });

    expect(onClick).toHaveBeenCalledTimes(2);
  });

  it('ne donne pas de rôle interactif à une carte informative', () => {
    render(<CardY2K>Information</CardY2K>);
    expect(screen.queryByRole('button', { name: 'Information' })).not.toBeInTheDocument();
  });
});
