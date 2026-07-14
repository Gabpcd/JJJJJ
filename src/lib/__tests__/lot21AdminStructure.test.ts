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
    const dashboard = readFileSync(resolve(racine, 'src/pages/admin/AdminDashboard.tsx'), 'utf8');
    const demo = readFileSync(resolve(racine, 'src/pages/admin/AdminDemo.tsx'), 'utf8');
    expect(missions).toContain('estMissionTestAdmin(m)');
    expect(missions).toContain('Donnée de test');
    expect(missions).not.toContain('!estMissionTestAdmin');
    expect(utilisateurs).toContain('estUtilisateurTestAdmin');
    expect(utilisateurs).not.toContain('!estUtilisateurTestAdmin');
    expect(utilisateurs).not.toContain('Afficher les données de test');
    expect(dashboard).toContain('Données de test présentes');
    expect(dashboard).toContain('Elles restent identifiées');
    expect(dashboard).not.toContain('Purge à la mise en production');
    expect(demo).toContain('Données de démo conservées');
    expect(demo).toContain('Vérifier les données de démo');
    expect(demo).not.toContain('Données de démo chargées');
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

  it('ne laisse aucune entrée de navigation admin sans route déclarée', () => {
    const app = readFileSync(resolve(racine, 'src/App.tsx'), 'utf8');
    const layout = readFileSync(resolve(racine, 'src/components/LayoutAdmin.tsx'), 'utf8');
    const routesDeclarees = new Set(
      [...app.matchAll(/<Route path="(\/admin[^"]*)"/g)].map((match) => match[1]),
    );
    const routesNavigation = [
      ...layout.matchAll(/route: '(\/admin[^']*)'/g),
    ].map((match) => match[1]);

    expect(routesNavigation.length).toBeGreaterThan(0);
    expect(routesNavigation.filter((route) => !routesDeclarees.has(route))).toEqual([]);
    expect(routesNavigation).toContain('/admin/messages-contact');
  });

  it('ouvre les justificatifs privés avec une URL signée temporaire', () => {
    const reclamations = readFileSync(resolve(racine, 'src/pages/admin/AdminReclamationsScore.tsx'), 'utf8');
    expect(reclamations).toContain(".from('justificatifs')");
    expect(reclamations).toContain('.createSignedUrl(');
    expect(reclamations).not.toContain('/storage/v1/object/sign/justificatifs/');
    expect(reclamations).not.toContain('flripxtsyegjshnhzjkz');
  });

  it('présente des wordings de production sans jalons de développement visibles', () => {
    const emails = readFileSync(resolve(racine, 'src/pages/admin/AdminEmails.tsx'), 'utf8');
    const templates = readFileSync(resolve(racine, 'src/pages/admin/AdminTemplatesContrats.tsx'), 'utf8');
    const externalisations = readFileSync(resolve(racine, 'src/pages/admin/AdminExternalisationsActions.tsx'), 'utf8');
    const cohortes = readFileSync(resolve(racine, 'src/pages/admin/AdminCohortEconomics.tsx'), 'utf8');

    expect(emails).not.toContain('[DEV]');
    expect(emails).not.toContain('aperçu de développement');
    expect(templates).not.toContain('templates Sprint 2');
    expect(externalisations).toContain('Traitement des externalisations');
    expect(externalisations).not.toContain('Worker externalisations');
    expect(cohortes).toContain('Cohortes & économie unitaire');
    expect(cohortes).not.toContain('Cohort Analysis & Unit Economics');
  });

  it('résout le compte gestionnaire avant une conversation avec un établissement', () => {
    const detail = readFileSync(resolve(racine, 'src/pages/admin/AdminDetailUtilisateur.tsx'), 'utf8');
    const triage = readFileSync(resolve(racine, 'src/pages/admin/AdminScoreTriage.tsx'), 'utf8');
    expect(detail).toContain("useOuvrirConversation('/admin/messagerie')");
    expect(detail).toContain("type === 'etablissement'");
    expect(triage).toContain("ligne.type === 'ETAB'");
  });

  it('ne présente pas une suppression RGPD reliée à une fonction serveur absente', () => {
    const rgpd = readFileSync(resolve(racine, 'src/pages/admin/AdminRGPDTools.tsx'), 'utf8');
    expect(rgpd).not.toContain('fn_admin_force_supprimer_compte');
    expect(rgpd).not.toContain('Forcer la suppression définitive');
    expect(rgpd).toContain("Suivi des demandes d'effacement");
  });
});
