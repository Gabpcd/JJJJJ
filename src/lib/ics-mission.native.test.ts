import { beforeEach, describe, expect, it, vi } from 'vitest';

const mocks = vi.hoisted(() => ({
  isNative: vi.fn(),
  createEventWithPrompt: vi.fn(),
  telechargerOuPartager: vi.fn(),
}));

vi.mock('@/lib/platform', () => ({ isNative: mocks.isNative }));
vi.mock('@/lib/telechargement', () => ({
  telechargerOuPartager: mocks.telechargerOuPartager,
}));
vi.mock('@ebarooni/capacitor-calendar', () => ({
  CapacitorCalendar: { createEventWithPrompt: mocks.createEventWithPrompt },
}));

import { ouvrirMissionDansCalendrier } from '@/lib/ics-mission';

const mission = {
  id: 'mission 42',
  intitule: 'Mission IDE',
  debut_le: '2026-09-09T08:00:00.000Z',
  fin_le: '2026-09-09T16:00:00.000Z',
  etablissements: {
    nom: 'Clinique Jolene',
    adresse_rue: '10 rue de la Paix',
    adresse_ville: 'Paris',
  },
};

describe('ouvrirMissionDansCalendrier', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.createEventWithPrompt.mockResolvedValue({ id: null });
  });

  it('ouvre l’éditeur système prérempli sur iOS/Android', async () => {
    mocks.isNative.mockReturnValue(true);

    await ouvrirMissionDansCalendrier(mission);

    expect(mocks.createEventWithPrompt).toHaveBeenCalledWith({
      title: 'Mission IDE',
      startDate: new Date(mission.debut_le).getTime(),
      endDate: new Date(mission.fin_le).getTime(),
      location: '10 rue de la Paix, Paris',
      description: 'Mission Jolene — Clinique Jolene',
      alerts: [-1440, -60],
      url: 'https://jolene.app/soignant/missions/mission%2042',
    });
    expect(mocks.telechargerOuPartager).not.toHaveBeenCalled();
  });

  it('conserve le téléchargement ICS sur le web', async () => {
    mocks.isNative.mockReturnValue(false);

    await ouvrirMissionDansCalendrier(mission);

    expect(mocks.createEventWithPrompt).not.toHaveBeenCalled();
    expect(mocks.telechargerOuPartager).toHaveBeenCalledOnce();
    expect(mocks.telechargerOuPartager.mock.calls[0]?.[1]).toBe('mission-jolene-2026-09-09.ics');
  });

  it('refuse un créneau incohérent avant d’ouvrir le système', async () => {
    mocks.isNative.mockReturnValue(true);

    await expect(ouvrirMissionDansCalendrier({
      ...mission,
      fin_le: mission.debut_le,
    })).rejects.toThrow('créneau');
    expect(mocks.createEventWithPrompt).not.toHaveBeenCalled();
  });
});
