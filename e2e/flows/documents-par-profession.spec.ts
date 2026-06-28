/**
 * Tests E2E — matrice documents requis par profession + type_exercice.
 *
 * Valide le contrat de la table documents_requis_par_profession + la
 * logique de filtrage frontend (profession ET type_exercice) :
 *   - LIBERAL/MIXTE → inclut LIBERAL_ONLY (RCP/RIB/URSSAF)
 *   - SALARIE/CDD → exclut LIBERAL_ONLY (n'affiche que TOUS)
 *
 * Anti-régression du Sprint Hotfix UX Documents (matrice CEO).
 */

import { test, expect } from '@playwright/test';
import { adminClient } from '../helpers/db';

const TEST_REQS = !!process.env.SUPABASE_SERVICE_ROLE_KEY;
const EXCLUS = ['VACCINATIONS', 'MEDECINE_TRAVAIL'];

/** Réplique la logique de filtrage frontend (DocumentsSoignant.charger). */
function docsVisibles(rows: any[], profession: string, typeExercice: string): string[] {
  const estLiberal = typeExercice === 'LIBERAL' || typeExercice === 'MIXTE';
  return rows
    .filter((d) => {
      if (d.profession !== profession) return false;
      if (EXCLUS.includes(d.type_document)) return false;
      const exReq = d.type_exercice_requis || 'TOUS';
      if (exReq === 'LIBERAL_ONLY') return estLiberal;
      if (exReq === 'SALARIE_ONLY') return !estLiberal;
      return true;
    })
    .map((d) => d.type_document)
    .sort();
}

test.describe('Matrice documents requis par profession + exercice', () => {
  let rows: any[] = [];

  test.beforeAll(async () => {
    test.skip(!TEST_REQS, 'SUPABASE_SERVICE_ROLE_KEY requis');
    const { data, error } = await adminClient()
      .from('documents_requis_par_profession' as any)
      .select('profession, type_document, type_exercice_requis, est_critique');
    expect(error).toBeFalsy();
    rows = (data as any[]) || [];
    expect(rows.length).toBeGreaterThan(0);
  });

  test('AS salariée → CARTE_IDENTITE + DIPLOME (+ autorisation exercice optionnelle)', () => {
    const docs = docsVisibles(rows, 'AS', 'SALARIE');
    expect(docs).toEqual(['AUTORISATION_EXERCICE', 'CARTE_IDENTITE', 'DIPLOME', 'TITRE_SEJOUR']);
  });

  test('AES salariée → CARTE_IDENTITE + DIPLOME (+ autorisation exercice optionnelle)', () => {
    const docs = docsVisibles(rows, 'AES', 'SALARIE');
    expect(docs).toEqual(['AUTORISATION_EXERCICE', 'CARTE_IDENTITE', 'DIPLOME', 'TITRE_SEJOUR']);
  });

  test('IDE salariée → CARTE_IDENTITE + DIPLOME + RPPS_ADELI + RIB (pas de RCP/URSSAF)', () => {
    // Le RIB est requis pour TOUS les exercices (migration rib_visible_tous_exercices) :
    // l'établissement employeur consulte le RIB du salarié pour verser le salaire
    // (fn_consulter_rib_soignant). Seuls RCP + URSSAF restent libéraux uniquement.
    const docs = docsVisibles(rows, 'IDE', 'SALARIE');
    expect(docs).toEqual(['AUTORISATION_EXERCICE', 'CARTE_IDENTITE', 'DIPLOME', 'RIB', 'RPPS_ADELI', 'TITRE_SEJOUR']);
    expect(docs).not.toContain('RCP_ASSURANCE');
    expect(docs).not.toContain('ATTESTATION_URSSAF');
  });

  test('IDE libérale → CARTE_IDENTITE + DIPLOME + RPPS + RCP + RIB + URSSAF', () => {
    const docs = docsVisibles(rows, 'IDE', 'LIBERAL');
    expect(docs).toEqual([
      'ATTESTATION_URSSAF', 'AUTORISATION_EXERCICE', 'CARTE_IDENTITE', 'DIPLOME', 'RCP_ASSURANCE', 'RIB', 'RPPS_ADELI', 'TITRE_SEJOUR',
    ]);
  });

  test('IDE mixte → inclut aussi les documents LIBERAL_ONLY', () => {
    const docs = docsVisibles(rows, 'IDE', 'MIXTE');
    expect(docs).toContain('RCP_ASSURANCE');
    expect(docs).toContain('RIB');
    expect(docs).toContain('ATTESTATION_URSSAF');
  });

  test('PHARMACIEN → RPPS mais jamais RCP/RIB/URSSAF (salarié only)', () => {
    const salarie = docsVisibles(rows, 'PHARMACIEN', 'SALARIE');
    expect(salarie).toEqual(['AUTORISATION_EXERCICE', 'CARTE_IDENTITE', 'DIPLOME', 'RPPS_ADELI', 'TITRE_SEJOUR']);
    // Même en simulant libéral, pas de RCP/RIB/URSSAF (non seedés pour pharmacien)
    const liberal = docsVisibles(rows, 'PHARMACIEN', 'LIBERAL');
    expect(liberal).not.toContain('RCP_ASSURANCE');
    expect(liberal).not.toContain('RIB');
  });

  test('MANIPULATEUR_RADIO → ADELI (RPPS_ADELI) mais pas RCP/RIB/URSSAF', () => {
    const docs = docsVisibles(rows, 'MANIPULATEUR_RADIO', 'SALARIE');
    expect(docs).toEqual(['AUTORISATION_EXERCICE', 'CARTE_IDENTITE', 'DIPLOME', 'RPPS_ADELI', 'TITRE_SEJOUR']);
  });

  test('PREPARATEUR_PHARMA → uniquement CARTE_IDENTITE + DIPLOME', () => {
    const docs = docsVisibles(rows, 'PREPARATEUR_PHARMA', 'SALARIE');
    expect(docs).toEqual(['AUTORISATION_EXERCICE', 'CARTE_IDENTITE', 'DIPLOME', 'TITRE_SEJOUR']);
  });

  test('ORTHOPHONISTE libérale → ADELI + RCP + RIB + URSSAF', () => {
    const docs = docsVisibles(rows, 'ORTHOPHONISTE', 'LIBERAL');
    expect(docs).toEqual([
      'ATTESTATION_URSSAF', 'AUTORISATION_EXERCICE', 'CARTE_IDENTITE', 'DIPLOME', 'RCP_ASSURANCE', 'RIB', 'RPPS_ADELI', 'TITRE_SEJOUR',
    ]);
  });

  test('KBIS retiré de toute la table (sociétés, pas BNC libéral)', () => {
    const kbis = rows.filter((d) => d.type_document === 'KBIS');
    expect(kbis).toHaveLength(0);
  });

  test('Critique partout sauf AUTORISATION_EXERCICE + TITRE_SEJOUR (optionnels by design)', () => {
    const OPTIONNELS = ['AUTORISATION_EXERCICE', 'TITRE_SEJOUR'];
    const critiques = rows.filter((d) => !OPTIONNELS.includes(d.type_document));
    expect(critiques.every((d) => d.est_critique === true)).toBe(true);
    const optionnels = rows.filter((d) => OPTIONNELS.includes(d.type_document));
    expect(optionnels.length).toBeGreaterThan(0);
    expect(optionnels.every((d) => d.est_critique === false)).toBe(true);
  });
});
