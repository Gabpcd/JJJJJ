import { render, screen } from '@testing-library/react';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import { Countdown72hSignature } from './Countdown72hSignature';

const CREE_LE = '2026-09-24T06:55:00.000Z';
const heuresApres = (heures: number) => new Date(new Date(CREE_LE).getTime() + heures * 3600 * 1000);

beforeEach(() => { vi.useFakeTimers(); });
afterEach(() => { vi.useRealTimers(); });

// Le texte lu (lecteur d'écran, copie, innerText) doit séparer la phrase du
// décompte : « sous 72h », jamais « sous72h ».
it('sépare « sous » du décompte restant', () => {
  vi.setSystemTime(new Date(CREE_LE));
  render(<Countdown72hSignature contratCreeLe={CREE_LE} />);
  expect(screen.getByRole('timer')).toHaveTextContent(/^Signature à finaliser sous 72h 00m 00s$/, { normalizeWhitespace: false });
});

it('garde l’espace dans la variante urgente (moins de 24h)', () => {
  vi.setSystemTime(heuresApres(60));
  render(<Countdown72hSignature contratCreeLe={CREE_LE} />);
  expect(screen.getByRole('timer')).toHaveTextContent(/^Signature urgente — moins de 24h restantes ! 12h 00m 00s$/, { normalizeWhitespace: false });
});

it('affiche l’expiration au-delà de 72h', () => {
  vi.setSystemTime(heuresApres(73));
  render(<Countdown72hSignature contratCreeLe={CREE_LE} />);
  expect(screen.queryByRole('timer')).not.toBeInTheDocument();
  expect(screen.getByText('⚠️ Délai de signature expiré (72h dépassées).')).toBeInTheDocument();
});
