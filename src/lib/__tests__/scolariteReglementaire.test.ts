import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const declaration = readFileSync('src/components/inscription/DeclarationEtudiant.tsx', 'utf8');
const verification = readFileSync('supabase/functions/verify-document/index.ts', 'utf8');
const migration = readFileSync(
  'supabase/migrations/20260810143000_aligner_signature_annulation_et_scolarite.sql',
  'utf8',
);

describe('passerelles étudiantes réglementaires de lancement', () => {
  it('couvre la pédicurie-podologie de bout en bout', () => {
    expect(declaration).toContain("valeur: 'PEDICURE_PODOLOGIE'");
    expect(declaration).toContain('48 ECTS dont 9 de stages');
    expect(verification).toContain('PEDICURE_PODOLOGIE: 3');
    expect(migration).toContain("'PEDICURE_PODOLOGIE'");
    expect(migration).toContain("x.formation = 'PEDICURE_PODOLOGIE'");
  });

  it('interdit les élévations IDE et pharmacien fondées sur la seule année', () => {
    expect(declaration).toContain("liste.filter((profession) => profession === 'AS')");
    expect(migration).toContain("formation = 'MEDECINE_DFASM' AND profession_autorisee::text = 'IDE'");
    expect(migration).toContain("formation = 'PHARMACIE' AND profession_autorisee::text = 'PHARMACIEN'");
  });

  it('exige une revue humaine persistée avant le recalcul du profil', () => {
    expect(verification).toContain('revue humaine obligatoire');
    expect(migration).toContain("conditions_scolarite_confirmees', 'false'");
    expect(migration).toContain('PERFORM public.fn_recalculer_preuves_etudiant(v_soignant_id)');
  });

  it('verrouille l’assignation étudiante au salariat et à une équipe avec IDE', () => {
    expect(migration).toContain("'CADRE_ETUDIANT_SALARIAT_REQUIS'");
    expect(migration).toContain("'CADRE_ETUDIANT_STRUCTURE_INELIGIBLE'");
    expect(migration).toContain("p_motif IS DISTINCT FROM 'CADRE_ETUDIANT_AS_CONFIRME'");
    expect(migration).toContain("'ide_dans_equipe_pendant_activites', true");
  });

  it('préserve la réponse atomique du soignant aux propositions établissement', () => {
    expect(migration).toContain("current_setting('jolene.candidature_rpc_mission_id', true)");
    expect(migration).toMatch(
      /OLD\.statut = 'PROPOSEE'[\s\S]*NEW\.statut IN \('ACCEPTEE', 'REFUSEE', 'EXPIREE'\)/,
    );
  });
});
