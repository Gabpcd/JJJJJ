import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const detailSerie = readFileSync('src/pages/DetailSerieSoignant.tsx', 'utf8');
const poolUrgence = readFileSync('src/pages/PoolUrgenceSoignant.tsx', 'utf8');
const carteProposition = readFileSync('src/components/CarteProposition.tsx', 'utf8');
const vueSwipe = readFileSync('src/components/swipe/VueSwipeMissions.tsx', 'utf8');

describe('actions candidat avec planning exact', () => {
  it('centralise les acceptations série et urgence derrière la confirmation serveur', () => {
    for (const source of [detailSerie, poolUrgence]) {
      expect(source).toContain("supabase.rpc('fn_confirmer_action_planning_v1'");
      expect(source).toContain('p_creneaux_confirmes');
      expect(source).toContain('PlanningMissionCandidat');
    }
    expect(detailSerie).toContain('Vérifie tous tes engagements');
    expect(detailSerie).toContain('construirePlanningConformite');
    expect(detailSerie).toContain('additionnerHeuresSalarieesParSemaine');
    expect(detailSerie).toContain('missionComptePourPlafond48h');
    expect(detailSerie).toContain('planningTousDisponibles');
    expect(detailSerie).toContain('Les missions dont le planning exact est disponible restent sélectionnables');
    expect(poolUrgence).toContain('RecapitulatifCandidatureDialog');
    expect(detailSerie).not.toContain("supabase.rpc('fn_accepter_mission'");
    expect(poolUrgence).not.toContain("supabase.rpc('fn_accepter_mission_urgence'");
  });

  it('laisse décocher une mission de série conflictuelle sans omission silencieuse', () => {
    expect(detailSerie).toContain('{isOpen && planningExact && (');
    expect(detailSerie).toContain('analyseSelection.missionsSelectionnees');
    expect(detailSerie).toContain('!analyseSelection.peutAccepter');
    expect(detailSerie).not.toContain('selectedIds.has(m.id) && !conflitMissionIds.has(m.id)');
  });

  it('bloque une série si le planning exact des engagements existants manque', () => {
    expect(detailSerie).toContain('planningEngagementsDisponibles');
    expect(detailSerie).toContain('missionsExistantes.every((mission) => construirePlanningConformite(mission).exact)');
    expect(detailSerie).toContain('!planningEngagementsDisponibles || !analyseSelection.peutAccepter');
    expect(detailSerie).toContain('Boolean(missionsResult.error || existantesResult.error)');
  });

  it('n’affiche pas un faux état vide quand le planning du swipe échoue', () => {
    expect(vueSwipe).toContain('isError: missionsEnErreur');
    expect(vueSwipe).toContain('Planning des missions indisponible');
    expect(vueSwipe).toContain('rechargerMissions');
  });

  it('confirme le planning exact avant d’accepter une proposition', () => {
    expect(carteProposition).toContain("p_action: 'PROPOSITION'");
    expect(carteProposition).toContain('creneauxConfirmesPourAction');
    expect(carteProposition).toContain('RecapitulatifCandidatureDialog');
    expect(carteProposition).not.toContain("p_accepter: action === 'ACCEPTEE'");
  });

  it('ne calcule plus le net proposé sur l’enveloppe début-fin', () => {
    expect(carteProposition).toContain('planning.totalHeures');
    expect(carteProposition).not.toMatch(/new Date\(mission\.fin_le\)[\s\S]{0,120}new Date\(mission\.debut_le\)/);
  });

  it('ventile l’attestation proposition sur les créneaux de chaque semaine', () => {
    expect(carteProposition).toContain('calculerSemainesAttestationProposition');
    expect(carteProposition).toContain('attestationsACompleter');
    expect(carteProposition).not.toContain(".select('duree_heures')");
  });
});
