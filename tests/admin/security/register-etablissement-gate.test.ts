import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const registerSource = readFileSync(
  resolve(process.cwd(), 'supabase/functions/register-etablissement/index.ts'),
  'utf8',
);
const finalisationSource = readFileSync(
  resolve(process.cwd(), 'src/pages/FinaliserInscriptionEtab.tsx'),
  'utf8',
);

describe('gate établissement à l’inscription', () => {
  it('ne promeut jamais le compte depuis le seul contrôle SIRET', () => {
    expect(registerSource).toContain("const statutVerification = 'EN_COURS' as const");
    expect(registerSource).toContain('peut_publier_missions: false');
    expect(registerSource).toContain('auto_verifie: false');
    expect(registerSource).not.toContain("const statutVerification = autoVerifie ? 'VERIFIE'");
  });

  it('lie un FINESS actif au SIRET exact avant de valider la preuve', () => {
    expect(registerSource).toContain('identifiantFinessExact(id, finess)');
    expect(registerSource).toContain('finessResult.actif');
    expect(registerSource).toContain('finessResult.siret === siret');
  });

  it('utilise le CORS partagé compatible web et coques natives', () => {
    expect(registerSource).toContain("from '../_shared/cors.ts'");
    expect(registerSource).toContain("if (req.method === 'OPTIONS') return preflightResponse(req)");
    expect(registerSource).toContain("if (req.method !== 'POST')");
  });

  it('n’annonce la publication que lorsque toutes les preuves sont validées', () => {
    expect(finalisationSource).toContain("etabInfo.statut_verification === 'VERIFIE'");
    expect(finalisationSource).toContain('etabInfo.peut_publier_missions === true');
    expect(finalisationSource).toContain('etabInfo.siret_verifie === true');
    expect(finalisationSource).toContain('etabInfo.finess_verifie === true');
    expect(finalisationSource).toContain('etabInfo.representant_identite_verifiee === true');
    expect(finalisationSource).toContain('etabInfo.rattachement_verifie === true');
  });
});
