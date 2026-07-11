import { describe, it, expect } from 'vitest';
import {
  derivePlanning, libelleDate, semainesCiviles, validerPlanning,
} from './planning-derive';
import type { HorairesJour } from '@/components/LigneHoraireJour';

// Helper : un jour-de-semaine ISO avec sa durée.
function hj(jourISO: number, actif: boolean, duree = 12, hd = '07:00', hf = '19:00'): HorairesJour {
  return { jourISO, label: `J${jourISO}`, heureDebut: hd, heureFin: hf, dureeHeures: duree, actif };
}
const semaineComplete = (duree = 12): HorairesJour[] => [1, 2, 3, 4, 5, 6, 7].map((i) => hj(i, true, duree));

// Repère : 22/07/2026 est un MERCREDI (confirmé par le rapport de bug).
describe('derivePlanning — ordre & libellés dérivés de la période', () => {
  it('mer 22/07 → mer 29/07 : première entrée = mercredi 22/07, lundi daté du 27 seulement', () => {
    const p = derivePlanning('2026-07-22', '2026-07-29');
    expect(p.datesLabels).toBe(true);
    // (2) une mission qui commence un mercredi commence par mercredi
    expect(p.jours[0].jourISO).toBe(3);
    expect(p.jours[0].label).toBe('Mer. 22/07');
    // le lundi n'apparaît QUE daté du 27, et jamais en première position
    const idxLundi = p.jours.findIndex((j) => j.jourISO === 1);
    expect(idxLundi).toBeGreaterThan(0);
    expect(p.jours[idxLundi].label).toBe('Lun. 27/07');
    // aucun autre libellé « Lun. » (une seule occurrence de lundi dans la plage)
    expect(p.jours.filter((j) => j.label.startsWith('Lun.')).length).toBe(1);
  });

  it('plage sans lundi : zéro Lundi (ni affiché ni cochable)', () => {
    const p = derivePlanning('2026-07-21', '2026-07-24'); // mardi → vendredi
    expect(p.jours.some((j) => j.jourISO === 1)).toBe(false);
    expect(p.jours.every((j) => !j.label.startsWith('Lun'))).toBe(true);
    expect(p.jours[0].label).toBe('Mar. 21/07');
  });

  it("mission d'un seul jour", () => {
    const p = derivePlanning('2026-07-22', '2026-07-22');
    expect(p.nbJours).toBe(1);
    expect(p.jours).toHaveLength(1);
    expect(p.jours[0].label).toBe('Mer. 22/07');
  });

  it('chevauchement de mois', () => {
    const p = derivePlanning('2026-07-30', '2026-08-03');
    expect(p.jours[0].label).toBe('Jeu. 30/07');
    const dates = p.jours.flatMap((j) => j.occurrences);
    expect(dates).toContain('2026-07-31');
    expect(dates).toContain('2026-08-01');
    expect(dates).toContain('2026-08-03');
  });

  it("chevauchement d'année", () => {
    const p = derivePlanning('2026-12-30', '2027-01-02');
    expect(p.nbJours).toBe(4);
    const dates = p.jours.flatMap((j) => j.occurrences);
    expect(dates).toContain('2026-12-31');
    expect(dates).toContain('2027-01-01');
  });

  it('plage > 14 jours : libellés abstraits (motif hebdomadaire)', () => {
    const p = derivePlanning('2026-07-01', '2026-07-20'); // 20 jours
    expect(p.datesLabels).toBe(false);
    expect(p.jours[0].label).toBe('Mercredi'); // 01/07/2026 = mercredi
  });

  it('plage invalide (fin < début) ou vide → rien', () => {
    expect(derivePlanning('2026-07-29', '2026-07-22').jours).toHaveLength(0);
    expect(derivePlanning('', '').jours).toHaveLength(0);
  });
});

describe('libelleDate', () => {
  it('formate « Mer. 22/07 »', () => {
    expect(libelleDate('2026-07-22')).toBe('Mer. 22/07');
    expect(libelleDate('2026-07-27')).toBe('Lun. 27/07');
  });
});

describe('validerPlanning — garde-fou 48h par semaine CIVILE réelle', () => {
  it('22→29/07 tout coché à 12h : semaine du 20/07 = 60h (dépasse), 27/07 = 36h, invalide', () => {
    const v = validerPlanning('2026-07-22', '2026-07-29', semaineComplete(12));
    const s2007 = v.semaines.find((s) => s.labelCourt === '20/07');
    const s2707 = v.semaines.find((s) => s.labelCourt === '27/07');
    expect(s2007?.totalHeures).toBe(60); // 22,23,24,25,26 → 5 × 12h
    expect(s2007?.depasse48).toBe(true);
    expect(s2707?.totalHeures).toBe(36); // 27,28,29 → 3 × 12h
    expect(s2707?.depasse48).toBe(false);
    expect(v.valide).toBe(false);
    expect(v.erreurs.some((e) => e.type === 'PLAFOND_48H' && e.semaine === '20/07')).toBe(true);
    expect(v.totalHebdo).toBe(60);
  });

  it('semaine à cheval contrôlée séparément — une seule semaine ≤ 48h est valide', () => {
    // lun 20 → dim 26 juillet, 4 jours à 10h = 40h, une seule semaine
    const h = [1, 2, 3, 4].map((i) => hj(i, true, 10)).concat([5, 6, 7].map((i) => hj(i, false, 10)));
    const v = validerPlanning('2026-07-20', '2026-07-26', h);
    expect(v.semaines).toHaveLength(1);
    expect(v.semaines[0].totalHeures).toBe(40);
    expect(v.valide).toBe(true);
  });
});

describe('semainesCiviles — occurrences réelles regroupées lundi-dimanche', () => {
  it('compte chaque occurrence réelle (mercredi présent deux fois)', () => {
    const s = semainesCiviles('2026-07-22', '2026-07-29', semaineComplete(12));
    // total sur les deux semaines = 8 jours × 12h
    expect(s.reduce((t, w) => t + w.totalHeures, 0)).toBe(96);
    expect(s.map((w) => w.labelCourt)).toEqual(['20/07', '27/07']);
  });
});
