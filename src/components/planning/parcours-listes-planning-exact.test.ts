import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const listeEtablissement = readFileSync('src/pages/ListeMissions.tsx', 'utf8');
const listeSoignant = readFileSync('src/pages/MissionsSoignant.tsx', 'utf8');

describe('listes de missions — planning exact', () => {
  it.each([
    ['établissement', listeEtablissement],
    ['soignant', listeSoignant],
  ])('charge sans troncature et vérifie le count côté %s', (_role, source) => {
    expect(source).toContain('chargerCreneauxMissionsPagines');
    expect(source).toContain('analyserCompletudePlanningMission');
    expect(source).toContain('nb_creneaux');
  });

  it('désactive duplication et republication lorsque le planning établissement est incomplet', () => {
    expect(listeEtablissement).toContain('g.mission.planning_incomplet');
    expect(listeEtablissement).toMatch(/onDupliquer=\{g\.mission\.planning_incomplet/);
    expect(listeEtablissement).toMatch(/onRepublier=\{g\.mission\.planning_incomplet/);
  });

  it('propage explicitement le statut incomplet aux cartes soignant', () => {
    expect(listeSoignant).toContain('planning_incomplet: !planning.complet');
    expect(listeSoignant).toContain("'Planning détaillé à confirmer'");
  });
});
