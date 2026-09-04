import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const presences = readFileSync('src/pages/PresencesSoignant.tsx', 'utf8');
const copieContrat = readFileSync('src/components/BlocContratTravailMission.tsx', 'utf8');
const detailMissionSoignant = readFileSync('src/pages/DetailMissionSoignant.tsx', 'utf8');
const detailMissionEtablissement = readFileSync('src/pages/DetailMission.tsx', 'utf8');

describe('continuité UX pointage et contrat salarié', () => {
  it('ne montre pas un faux état vide pendant la restauration de session', () => {
    expect(presences).toContain('loading || !consentementCharge || !user');
  });

  it('distingue le contrat Jolene signé de la copie PDF employeur', () => {
    expect(copieContrat).toContain('Copie PDF employeur à déposer');
    expect(copieContrat).toContain('Votre contrat Jolene peut déjà être signé');
    expect(copieContrat).not.toContain('Contrat de travail manquant</p>');
  });

  it('sépare le planning prévu du relevé réel sur une mission terminée', () => {
    expect(detailMissionSoignant).toContain("estTerminee ? 'Horaires planifiés' : 'Horaires'");
    expect(detailMissionSoignant).toContain('Planning prévu au contrat. Les heures réellement travaillées et les pauses');
    expect(detailMissionSoignant).toContain('Voir mes heures pointées et mes pauses');
    expect(detailMissionSoignant).toContain('/soignant/presences/mission/${mission.id}');
  });

  it('présente un litige résolu comme une décision et non comme un dossier en cours', () => {
    expect(detailMissionSoignant).toContain("litigeEstClos ? 'Décision du litige' : 'Litige en cours sur cette mission'");
    expect(detailMissionSoignant).toContain("litigeEstClos ? 'Consulter la décision' : 'Voir le litige'");
    expect(detailMissionSoignant).toContain('statutBadgeV2');
    expect(detailMissionEtablissement).toContain("litigeClos ? 'Décision du litige' : 'Litige en cours'");
    expect(detailMissionEtablissement).toContain('statutBadgeV2');
  });
});
