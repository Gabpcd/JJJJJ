import { render, screen } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import { BandeauSansGPS } from './BandeauSansGPS';

describe('BandeauSansGPS', () => {
  it('décrit le mode de pointage sans prétendre qu’un pointage a déjà eu lieu', () => {
    render(<BandeauSansGPS />);

    expect(screen.getByText(/Pointage sans localisation activé/i)).toBeInTheDocument();
    expect(screen.queryByText(/pointage est bien pris en compte/i)).not.toBeInTheDocument();
  });
});
