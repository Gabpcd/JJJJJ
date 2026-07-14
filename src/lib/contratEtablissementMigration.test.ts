import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const migration = readFileSync(
  resolve(process.cwd(), 'supabase/migrations/20260714001526_exposer_contrat_service_etablissement_complet.sql'),
  'utf8',
);
const formulaire = readFileSync(
  resolve(process.cwd(), 'src/components/FormulaireMission.tsx'),
  'utf8',
);
const profil = readFileSync(
  resolve(process.cwd(), 'src/pages/ProfilEtablissement.tsx'),
  'utf8',
);
const activation = readFileSync(
  resolve(process.cwd(), 'src/pages/ActiverEtablissement.tsx'),
  'utf8',
);

describe('source unique du contrat de service établissement', () => {
  it('expose la signature active dans la RPC consommée par les deux écrans', () => {
    expect(migration).toContain('et.contrat_service_signe, et.contrat_service_signe_le');
    expect(formulaire).toContain('contratServiceEstSigne(data)');
    expect(profil).toContain('setContratServiceSigne(contratServiceEstSigne(data))');
  });

  it("n'utilise pas l'ancien PDF validé comme verrou de publication", () => {
    expect(formulaire).not.toMatch(/setContratNonValide\([^\n]*contrat_valide/);
    expect(profil).not.toContain('!contratValide && (');
  });

  it("active l'établissement canonique d'un membre d'équipe", () => {
    expect(activation).toContain('useEtablissementScope');
    expect(activation).toContain(".eq('id', etablissementId)");
    expect(activation).toContain('etablissement_id: etablissementId');
    expect(activation).toContain('p_etablissement_id: etablissementId');
    expect(activation).not.toContain(".eq('id', user.id)");
    expect(activation).not.toContain('etablissement_id: user.id');
    expect(activation).not.toContain('p_etablissement_id: user.id');
  });

  it("conserve la signature sous l'acteur et rattache les justificatifs à l'établissement", () => {
    expect(activation).toContain('`${user.id}/signatures/');
    expect(activation).toContain('`${etablissementId}/representant-piece-');
    expect(activation).toContain('`${etablissementId}/justificatif-fonction-');
  });
});
