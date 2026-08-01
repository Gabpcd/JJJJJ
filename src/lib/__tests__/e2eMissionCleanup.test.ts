import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

describe('purge des missions techniques E2E', () => {
  it('supprime toute la descendance escrow avant la mission', () => {
    const source = readFileSync(resolve(process.cwd(), 'e2e/global-setup.ts'), 'utf8');
    const escrow = source.indexOf(".from('paiements_escrow')\n      .select('id')");
    const enfants = [
      'escrow_exposition_releases',
      'escrow_release_queue',
      'stripe_refunds_queue',
    ].map((table) => source.indexOf(`'${table}'`, escrow));
    const boucleEnfantsMission = source.indexOf('for (const table of ENFANTS_MISSION)', escrow);
    const purgeRpc = source.indexOf("admin.rpc('fn_test_purge_mission'", boucleEnfantsMission);

    expect(escrow).toBeGreaterThan(-1);
    enfants.forEach((index) => expect(index).toBeGreaterThan(escrow));
    enfants.forEach((index) => expect(index).toBeLessThan(boucleEnfantsMission));
    expect(source).toContain("'stripe_transfers'");
    expect(source).toContain("'paiements_escrow'");
    expect(purgeRpc).toBeGreaterThan(boucleEnfantsMission);
    expect(source).not.toContain(".from('missions').delete()");
    expect(source).toContain('if (escrowsError)');
    expect(source).toContain('if (escrowChildError)');
  });

  it('refuse toute purge partielle d’une mission non préfixée test', () => {
    const helper = readFileSync(resolve(process.cwd(), 'e2e/helpers/seed.ts'), 'utf8');
    const garde = helper.indexOf("intitule.startsWith('[pw-test:')");
    const premiereSuppression = helper.indexOf(".from('paiements_escrow' as any)", garde);

    expect(garde).toBeGreaterThan(-1);
    expect(premiereSuppression).toBeGreaterThan(garde);
    expect(helper).toContain('refus de purger une mission non technique');
    expect(helper).toContain('if (escrowsReadError)');
    expect(helper).toContain('if (financialError)');
  });

  it('détache les enfants des fixtures avant la RPC historique et le profil', () => {
    const helper = readFileSync(resolve(process.cwd(), 'e2e/helpers/seed.ts'), 'utf8');
    const cleanupMission = helper.indexOf('export async function cleanupMissionCascade');
    const validationMission = helper.indexOf(
      'const preparation = await preparerMissionTechniquePourPurge',
      cleanupMission,
    );
    const purgeLocaleMission = helper.indexOf(
      'for (const table of ENFANTS_MISSION_AVANT_PURGE_RPC)',
      validationMission,
    );
    const purgeRpc = helper.indexOf(".rpc('fn_test_purge_mission' as any", purgeLocaleMission);

    expect(validationMission).toBeGreaterThan(cleanupMission);
    expect(purgeLocaleMission).toBeGreaterThan(validationMission);
    expect(purgeRpc).toBeGreaterThan(purgeLocaleMission);
    expect(helper).toContain("'conformite_travail'");
    expect(helper).toContain("'presences'");
    expect(helper).toContain("'candidatures'");

    const cleanupSoignant = helper.indexOf(
      'export async function cleanupEphemeralVerifiedCaregiver',
    );
    const validationSoignant = helper.indexOf(
      'profilValide.est_compte_test !== true',
      cleanupSoignant,
    );
    const purgeLocaleSoignant = helper.indexOf(
      'for (const table of ENFANTS_SOIGNANT_AVANT_PROFIL)',
      validationSoignant,
    );
    const suppressionProfil = helper.indexOf(".from('soignants' as any)", purgeLocaleSoignant);

    expect(validationSoignant).toBeGreaterThan(cleanupSoignant);
    expect(purgeLocaleSoignant).toBeGreaterThan(validationSoignant);
    expect(suppressionProfil).toBeGreaterThan(purgeLocaleSoignant);
  });
});
