import { fireEvent, render, screen } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { WidgetAllerPointer } from './WidgetAllerPointer';

const navigate = vi.hoisted(() => vi.fn());

vi.mock('react-router-dom', async (importOriginal) => {
  const original = await importOriginal<typeof import('react-router-dom')>();
  return { ...original, useNavigate: () => navigate };
});

afterEach(() => {
  vi.useRealTimers();
  navigate.mockReset();
});

describe('WidgetAllerPointer', () => {
  it('garde un accès aux présences pour une mission longue en cours', () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-07-31T10:00:00+02:00'));

    render(<WidgetAllerPointer mission={{
      id: 'mission-longue',
      intitule: 'Mission IDE longue',
      statut: 'EN_COURS',
      debut_le: '2026-07-06T08:00:00+02:00',
      fin_le: '2026-08-31T16:00:00+02:00',
      etablissements: { nom: 'Clinique Jolene' },
    }} />);

    fireEvent.click(screen.getByRole('button', { name: /Voir mes présences/i }));
    expect(navigate).toHaveBeenCalledWith('/soignant/presences?tab=encours');
  });

  it('masque une mission assignée dont la fenêtre de pointage est passée', () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-07-31T10:00:00+02:00'));

    const { container } = render(<WidgetAllerPointer mission={{
      id: 'mission-passee',
      intitule: 'Mission passée',
      statut: 'ASSIGNEE',
      debut_le: '2026-07-31T08:00:00+02:00',
      fin_le: '2026-07-31T09:00:00+02:00',
      etablissements: { nom: 'Clinique Jolene' },
    }} />);

    expect(container).toBeEmptyDOMElement();
  });
});
