import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const source = readFileSync(
  resolve(process.cwd(), 'supabase/functions/verify-rpps/index.ts'),
  'utf8',
);

describe('durcissement de verify-rpps', () => {
  it('relit les attributs sensibles depuis le profil pour toute écriture', () => {
    expect(source).toContain(".select('id, numero_rpps, numero_adeli, prenom, nom, profession, supprime_le, est_compte_test')");
    expect(source).toContain('numero = type === \'RPPS\' ? persistedRpps : persistedAdeli');
    expect(source).toContain('nom = stringValue(profile.nom, 120)');
    expect(source).toContain('prenom = stringValue(profile.prenom, 120)');
    expect(source).toContain('profession = stringValue(profile.profession, 80).toUpperCase()');
    expect(source).toContain('requested !== numero');
    expect(source).toContain('professionalIdentifierMatches(numero, requested) !== true');
  });

  it('réserve la mutation au profil lui-même, à un admin actif ou au service', () => {
    expect(source).toContain('verifyUserOrServiceRole(req)');
    expect(source).toContain('callerId !== soignantId');
    expect(source).toContain('verifyAdminOrServiceRole(req)');
    expect(source).toContain('if (profile && correspond)');
    expect(source).toContain("matchNullableSnapshot(updateQuery, numberColumn, persistedNumber)");
    expect(source).toContain("matchNullableSnapshot(updateQuery, 'prenom', profile.prenom)");
    expect(source).toContain("matchNullableSnapshot(updateQuery, 'nom', profile.nom)");
    expect(source).toContain("matchNullableSnapshot(updateQuery, 'profession', profile.profession)");
    expect(source).toContain(".is('supprime_le', null)");
    expect(source).toContain("'PROFILE_CHANGED_DURING_VERIFICATION'");
  });

  it('exige un Practitioner exact, actif, une identité complète et une profession connue', () => {
    expect(source).toContain("resource?.resourceType === 'Practitioner'");
    expect(source).toContain('identifierExact(resource, numero, type)');
    expect(source).toContain('practitioner.active === true');
    expect(source).toContain('personNameMatches(nom, prenom, result.nom, result.prenom) === true');
    expect(source).toContain('const correspond = actif && traitsMatch && professionMatch');
    expect(source).toContain("'IDENTITY_INCOMPLETE'");
    expect(source).toContain("'PROFESSION_UNSUPPORTED'");
    expect(source).not.toContain('prenomNorm.slice(0, 3)');
    expect(source).not.toContain('!nomFourni');
  });

  it('reprend les codes officiels G15 sans confondre dentiste, pharmacien et laboratoire', () => {
    expect(source).toContain("'21': 'PHARMACIEN'");
    expect(source).toContain("'40': 'DENTISTE'");
    expect(source).toContain("'86': 'TECHNICIEN_LABO'");
    expect(source).toContain("'95': 'DIETETICIEN'");
    expect(source).not.toContain("'40': 'PHARMACIEN'");
  });

  it('fail closed sur annuaire absent/inactif et isole les identifiants de démonstration', () => {
    expect(source).toContain("errorResponse(cors, 503, 'RPPS_API_UNAVAILABLE'");
    expect(source).toContain("code: `${codePrefix}_INACTIVE`");
    expect(source).toContain('}, 422)');
    expect(source).toContain("Deno.env.get('ALLOW_DEMO_IDENTIFIERS') === 'true'");
    expect(source).toContain('|| !demoIdentifiersEnabled');
    expect(source).toContain('profile.est_compte_test !== true');
    expect(source).toContain('setVerificationFalse(');
    expect(source).not.toContain("source: 'Mode test (legacy)'");
  });
});
