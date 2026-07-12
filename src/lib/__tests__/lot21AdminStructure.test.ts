import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

function fichiersRecursifs(dossier: string): string[] {
  return readdirSync(dossier).flatMap((nom) => {
    const chemin = join(dossier, nom);
    return statSync(chemin).isDirectory() ? fichiersRecursifs(chemin) : [chemin];
  });
}

const racine = process.cwd();
const adminTsx = [
  ...fichiersRecursifs(resolve(racine, 'src/pages/admin')),
  ...fichiersRecursifs(resolve(racine, 'src/components/admin')),
].filter((fichier) => fichier.endsWith('.tsx'));

describe('Lot 21 — mécanique admin', () => {
  it('n’utilise plus d’emoji comme icône dans les pages admin', () => {
    const emoji = /[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}]/u;
    const fautifs = adminTsx.filter((fichier) => emoji.test(readFileSync(fichier, 'utf8')));
    expect(fautifs).toEqual([]);
  });

  it('conserve les données de test visibles et les badge sans filtre', () => {
    const missions = readFileSync(resolve(racine, 'src/pages/admin/AdminMissions.tsx'), 'utf8');
    const utilisateurs = readFileSync(resolve(racine, 'src/pages/admin/AdminUtilisateurs.tsx'), 'utf8');
    expect(missions).toContain('estMissionTestAdmin(m)');
    expect(missions).toContain('Donnée de test');
    expect(missions).not.toContain('!estMissionTestAdmin');
    expect(utilisateurs).toContain('estUtilisateurTestAdmin');
    expect(utilisateurs).not.toContain('!estUtilisateurTestAdmin');
    expect(utilisateurs).not.toContain('Afficher les données de test');
  });

  it('place les deux systèmes de notification en bas, hors des KPI du haut', () => {
    const app = readFileSync(resolve(racine, 'src/App.tsx'), 'utf8');
    const notifications = readFileSync(resolve(racine, 'src/contexts/NotificationContext.tsx'), 'utf8');
    expect(app).toContain('position="bottom-right"');
    expect(app).toContain('mobileOffset');
    expect(notifications).toContain('data-toast-safe-zone="bottom"');
    expect(notifications).toContain('md:bottom-4');
  });

  it('centralise formats français, zéro négatif et warnings de vetting', () => {
    const presentation = readFileSync(resolve(racine, 'src/lib/adminPresentation.ts'), 'utf8');
    const verification = readFileSync(resolve(racine, 'src/pages/admin/AdminVerificationEtablissements.tsx'), 'utf8');
    expect(presentation).toContain("new Intl.NumberFormat('fr-FR'");
    expect(presentation).toContain('normaliserZero');
    expect(presentation).toContain('NAF_INHABITUEL');
    expect(presentation).toContain('SIRET_INVALIDE');
    expect(verification).toContain("Annuaire des Entreprises");
    expect(verification).toContain('alertes-vetting-etablissement');
  });
});
