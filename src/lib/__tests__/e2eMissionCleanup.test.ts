import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { afterEach, describe, expect, it, vi } from 'vitest';
import {
  PURGE_MISSION_RPC_TIMEOUT_MS,
  purgerMissionTechniqueAvecTimeout,
} from '../../../e2e/helpers/cleanup-mission-test';

afterEach(() => {
  vi.useRealTimers();
});

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
    const purgeRpc = source.indexOf(
      'purgerMissionTechniqueAvecTimeout(admin, missionId)',
      boucleEnfantsMission,
    );

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
    const purgeRpc = helper.indexOf(
      'purgerMissionTechniqueAvecTimeout(admin, missionId)',
      purgeLocaleMission,
    );

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

  it('borne les deux appels de purge avec un unique AbortController', async () => {
    vi.useFakeTimers();
    let signalRecu: AbortSignal | undefined;
    const abortSignal = vi.fn((signal: AbortSignal) => {
      signalRecu = signal;
      return new Promise<{ error: { message: string; details: string; hint: string; code: string } }>(
        (resolvePromise) => {
          signal.addEventListener(
            'abort',
            () => resolvePromise({
              error: {
                message: 'AbortError: request timed out',
                details: '',
                hint: 'Request was aborted (timeout or manual cancellation)',
                code: '',
              },
            }),
            { once: true },
          );
        },
      );
    });
    const rpc = vi.fn(() => ({ abortSignal }));
    const admin = { rpc } as unknown as Parameters<
      typeof purgerMissionTechniqueAvecTimeout
    >[0];

    const requete = purgerMissionTechniqueAvecTimeout(
      admin,
      '00000000-0000-0000-0000-000000000001',
    );

    expect(signalRecu?.aborted).toBe(false);
    await vi.advanceTimersByTimeAsync(PURGE_MISSION_RPC_TIMEOUT_MS);
    const error = await requete;

    expect(signalRecu?.aborted).toBe(true);
    expect(error?.hint).toContain('Request was aborted');
    expect(rpc).toHaveBeenCalledOnce();
    expect(abortSignal).toHaveBeenCalledOnce();
    expect(vi.getTimerCount()).toBe(0);

    const globalSetup = readFileSync(resolve(process.cwd(), 'e2e/global-setup.ts'), 'utf8');
    const seed = readFileSync(resolve(process.cwd(), 'e2e/helpers/seed.ts'), 'utf8');
    expect(globalSetup).not.toContain("rpc('fn_test_purge_mission");
    expect(seed).not.toContain("rpc('fn_test_purge_mission");
  });

  it('ne retraite pas les missions escrow déjà gelées et mises en quarantaine', () => {
    const source = readFileSync(
      resolve(process.cwd(), 'e2e/flows/escrow-revenus-soignant.spec.ts'),
      'utf8',
    );
    const beforeAll = source.indexOf('test.beforeAll(async () => {');
    const timeout = source.indexOf('test.setTimeout(120_000);', beforeAll);
    const lectureResidus = source.indexOf(".like('intitule', '[pw-test:escrow%')", beforeAll);
    const filtreNonGele = source.indexOf(".is('fige_le', null)", lectureResidus);
    const verificationErreur = source.indexOf('if (oldMissionsError)', filtreNonGele);
    const purge = source.indexOf('await purgeMissionsBounded(', verificationErreur);

    expect(beforeAll).toBeGreaterThan(-1);
    expect(timeout).toBeGreaterThan(beforeAll);
    expect(lectureResidus).toBeGreaterThan(timeout);
    expect(filtreNonGele).toBeGreaterThan(lectureResidus);
    expect(verificationErreur).toBeGreaterThan(filtreNonGele);
    expect(purge).toBeGreaterThan(verificationErreur);
  });

  it('laisse finir le cleanup escrow agrégé sans relâcher la borne de chaque RPC', () => {
    const source = readFileSync(
      resolve(process.cwd(), 'e2e/flows/escrow-revenus-soignant.spec.ts'),
      'utf8',
    );
    const afterAll = source.indexOf('test.afterAll(async () => {');
    const timeout = source.indexOf('test.setTimeout(300_000);', afterAll);
    const purge = source.indexOf('await purgeMissionsBounded(seededMissions);', afterAll);

    expect(afterAll).toBeGreaterThan(-1);
    expect(timeout).toBeGreaterThan(afterAll);
    expect(purge).toBeGreaterThan(timeout);
    expect(PURGE_MISSION_RPC_TIMEOUT_MS).toBe(25_000);
  });
});
