import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const read = (path: string) => readFileSync(path, 'utf8');
const migrationPath =
  'supabase/migrations/20260804154807_autoriser_liberal_notifier_litiges_et_envoyer_invitations.sql';

describe('régressions critiques avant publication', () => {
  it('ne transforme plus NON_PROPOSE en interdiction du libéral', () => {
    const mode = read('src/lib/modeExerciceMission.ts');
    const formulaire = read('src/components/FormulaireMission.tsx');
    const migration = read(migrationPath);

    expect(mode).toContain("mode.niveau !== 'BLOQUE'");
    expect(formulaire).toContain('liberalSelectionnableMission');
    expect(formulaire).not.toContain('Salariat recommandé');
    expect(formulaire).toContain("modeExerciceMission?.niveau === 'BLOQUE'");
    expect(migration).not.toContain("v_mode->>'niveau' <> 'AUTORISE'");
    expect(migration.match(/v_mode->>'niveau', 'BLOQUE'\) = 'BLOQUE'/g)).toHaveLength(3);
    expect(migration.match(/IN \('IADE', 'IBODE'\)/g)).toHaveLength(3);
  });

  it('met réellement les invitations manuelles en file et rattrape la récente', () => {
    const equipe = read('src/pages/EquipeEtablissement.tsx');
    const migration = read(migrationPath);

    expect(equipe).toContain('L’e-mail est en cours d’envoi');
    expect(migration).toContain('EMAIL_INVITATION_EQUIPE_MIS_EN_FILE');
    expect(migration).toContain('invitation-equipe-etab:');
    expect(migration).toContain("i.invite_le >= now() - interval '24 hours'");
    expect(migration).not.toContain('AND e.est_compte_test IS FALSE');
  });

  it('notifie et met en avant les propositions de résolution', () => {
    const dashboard = read('src/pages/DashboardSoignant.tsx');
    const litiges = read('src/pages/LitigesSoignant.tsx');
    const layoutAdmin = read('src/components/LayoutAdmin.tsx');
    const litigesAdmin = read('src/pages/admin/AdminLitiges.tsx');
    const migration = read(migrationPath);

    expect(dashboard).toContain('Proposition de résolution à examiner');
    expect(dashboard).toContain('/soignant/litiges?litige=');
    expect(litiges).toContain('Proposition de résolution reçue');
    expect(migration).toContain("'LITIGE_REPONSE'");
    expect(migration).toContain("'Proposition d''accord reçue'");
    expect(migration).toContain("'Proposition de résolution de litige'");
    expect(migration).toContain("'/admin/litiges?litige='");
    expect(migration).toContain("'ADMIN'");
    expect(layoutAdmin).toContain('<BadgeNotification />');
    expect(litigesAdmin).toContain("searchParams.get('litige')");
  });

  it('conserve le contrôle iPad strict sans classer l’audit secondaire en erreur', () => {
    const auth = read('src/contexts/AuthContext.tsx');
    const e2e = read('e2e/release-review-smoke.spec.ts');

    expect(auth).toContain("logger.warn('Audit connexion ignoré'");
    expect(auth).not.toContain("logger.error('Audit connexion échoué'");
    expect(e2e).toContain("message.includes('favicon')");
    expect(e2e).toContain('toEqual([])');
  });
});
