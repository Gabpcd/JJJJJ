import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const surfaces = [
  ['src/pages/admin/AdminVerificationEtablissements.tsx', '.createSignedUrl(path, 900)'],
  ['src/pages/admin/AdminHeuresExternes.tsx', '.createSignedUrl(path, 3600)'],
  ['src/components/parcours-liberal/ListeHeuresExternes.tsx', '.createSignedUrl(path, 3600)'],
  ['src/components/WorkflowPaiementMission.tsx', "fn_consulter_rib_soignant"],
  ['src/components/BlocContratTravailMission.tsx', "verify-contrat-travail"],
] as const;

describe('documents signés — compatibilité Safari', () => {
  for (const [fichier, debutRequete] of surfaces) {
    it(`${fichier} préouvre et sécurise la fenêtre avant la requête`, () => {
      const source = readFileSync(resolve(process.cwd(), fichier), 'utf8');
      const ouverture = source.indexOf("window.open('about:blank', '_blank')");
      const requete = source.indexOf(debutRequete, ouverture);

      expect(ouverture).toBeGreaterThanOrEqual(0);
      expect(requete).toBeGreaterThan(ouverture);
      expect(source).toContain('if (!preview)');
      expect(source).toContain('preview.opener = null');
      expect(source).toContain('preview.location.replace(');
      expect(source).toContain('preview.close()');
    });
  }
});
