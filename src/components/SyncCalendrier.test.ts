import { describe, expect, it } from 'vitest';
import { generateMissionIcs } from '@/lib/ics-mission';

describe('generateMissionIcs', () => {
  it('génère deux événements pour les deux vrais créneaux d\'une mission longue', () => {
    const ics = generateMissionIcs({
      id: 'mission-longue',
      intitule: 'Mission IDE',
      debut_le: '2026-07-06T06:00:00.000Z',
      fin_le: '2026-08-31T14:00:00.000Z',
      creneaux: [
        {
          id: 'juillet',
          debut: '2026-07-06T06:00:00.000Z',
          fin: '2026-07-06T14:00:00.000Z',
          est_pause: false,
          type_creneau: 'PREVISIONNEL',
        },
        {
          id: 'aout',
          debut: '2026-08-31T06:00:00.000Z',
          fin: '2026-08-31T14:00:00.000Z',
          est_pause: false,
          type_creneau: 'PREVISIONNEL',
        },
      ],
    });

    expect(ics.match(/BEGIN:VEVENT/g)).toHaveLength(2);
    expect(ics).toContain('DTSTART:20260706T060000Z');
    expect(ics).toContain('DTSTART:20260831T060000Z');
    expect(ics).not.toContain('DTSTART:20260706T060000Z\r\nDTEND:20260831T140000Z');
  });

  it('ne crée pas un faux événement continu pour une mission longue sans planning', () => {
    const ics = generateMissionIcs({
      id: 'sans-planning',
      intitule: 'Mission longue',
      debut_le: '2026-07-06T06:00:00.000Z',
      fin_le: '2026-08-31T14:00:00.000Z',
    });

    expect(ics).not.toContain('BEGIN:VEVENT');
  });
});
