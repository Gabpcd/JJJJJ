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
      prochainCreneau: {
        debut: '2026-08-31T08:00:00+02:00',
        fin: '2026-08-31T16:00:00+02:00',
      },
    }} />);

    expect(screen.getByText(/lundi 31 août · 08:00 → 16:00/i)).toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: /Voir horaires et présences/i }));
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

  it('utilise le prochain créneau réel pour ouvrir le pointage d’une mission assignée', () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-08-31T07:30:00+02:00'));

    render(<WidgetAllerPointer mission={{
      id: 'mission-longue-assignee',
      intitule: 'Mission IDE longue',
      statut: 'ASSIGNEE',
      debut_le: '2026-07-06T08:00:00+02:00',
      fin_le: '2026-08-31T16:00:00+02:00',
      debut_affiche: '2026-08-31T08:00:00+02:00',
      prochainCreneau: {
        debut: '2026-08-31T08:00:00+02:00',
        fin: '2026-08-31T16:00:00+02:00',
      },
    }} />);

    fireEvent.click(screen.getByRole('button', { name: /Voir horaires et présences/i }));
    expect(navigate).toHaveBeenCalledWith('/soignant/presences?tab=aujourdhui');
  });

  it('reste visible pendant tout le créneau même si la mission est encore assignée', () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-08-31T12:00:00+02:00'));

    render(<WidgetAllerPointer mission={{
      id: 'mission-en-service',
      intitule: 'Mission IDE',
      statut: 'ASSIGNEE',
      debut_le: '2026-08-31T08:00:00+02:00',
      fin_le: '2026-08-31T16:00:00+02:00',
      creneauActuel: true,
      prochainCreneau: {
        debut: '2026-08-31T08:00:00+02:00',
        fin: '2026-08-31T16:00:00+02:00',
      },
    }} />);

    expect(screen.getByText(/créneau de travail actuel/i)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /aller pointer/i })).toBeInTheDocument();
  });
});
