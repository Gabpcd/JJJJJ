import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const migration = readFileSync(
  resolve(process.cwd(), 'supabase/migrations/20260712161000_finaliser_matrice_modes_exercice.sql'),
  'utf8',
);
const cascade = readFileSync(
  resolve(process.cwd(), 'supabase/migrations/20260712163000_lot21_finaliser_cascade_profession_mission.sql'),
  'utf8',
);
const constantes = readFileSync(resolve(process.cwd(), 'src/lib/constantes.ts'), 'utf8');
const formulaire = readFileSync(resolve(process.cwd(), 'src/components/FormulaireMission.tsx'), 'utf8');
const seedDemo = readFileSync(resolve(process.cwd(), 'scripts/seed-demo.ts'), 'utf8');

describe('encodage table des modes d’exercice', () => {
  it('résout la mission depuis profession_requise et la table', () => {
    expect(migration).toContain('NEW.profession_requise::text');
    expect(migration).toContain('public.fn_mode_exercice(');
    expect(migration).toContain("v_mode->>'niveau' <> 'AUTORISE'");
  });

  it('applique le défaut NON_PROPOSE et ne seede aucune cellule publique', () => {
    expect(migration).toContain("'niveau', 'NON_PROPOSE'");
    expect(migration).toContain('aucune cellule "public"');
    expect(migration).not.toMatch(/ARRAY\[[^\]]*'public'[^\]]*\]\s+c;/);
  });

  it('contient les wordings validés avec leur force de source', () => {
    expect(migration).toContain("Conseil d''État, 11/02/2025, n°491128");
    expect(cascade).toContain(
      "lettre interministérielle du 30 décembre 2021 (n° D21-031940), validée par le Conseil d''État (11/02/2025, n°491128)",
    );
    expect(migration).toContain('art. L.6323-1-5 du code de la santé publique');
    expect(migration).toContain("'JUGE'");
    expect(migration).toContain("'DOCTRINE'");
    expect(migration).toContain("'CONFORMITE_JOLENE'");
  });

  it('supprime la matrice juridique TypeScript en dur', () => {
    expect(constantes).not.toContain('LIBERAL_COMPATIBILITY');
    expect(constantes).not.toContain('PROFESSIONS_NON_LIBERAL');
    expect(constantes).not.toContain('peutExercerLiberal');
    expect(formulaire).toContain('useModeExerciceMission');
    expect(formulaire).toContain('modeExerciceMission.source_libelle');
  });

  it('applique la mission aux quatre portes d’attribution', () => {
    expect(cascade).toContain('public.fn_resoudre_contrat_mission(');
    expect(cascade).toContain('v_etablissement.est_compte_test AND NOT v_soignant.est_compte_test');
    expect(cascade).toContain('public.fn_finaliser_attribution_mission(');
    expect(cascade).toContain('CREATE OR REPLACE FUNCTION public.fn_postuler_mission(');
    expect(cascade).toContain('CREATE OR REPLACE FUNCTION public.fn_accepter_mission(');
    expect(cascade).toContain('CREATE OR REPLACE FUNCTION public.fn_traiter_candidature(');
    expect(cascade).toContain('CREATE OR REPLACE FUNCTION public.fn_assigner_mission_admin(');
    expect(cascade).toContain('CREATE OR REPLACE FUNCTION public.fn_proposer_mission_soignant(');
    expect(cascade).toContain('CREATE OR REPLACE FUNCTION public.fn_repondre_proposition(');
    expect(cascade).toContain('CREATE OR REPLACE FUNCTION public.fn_protect_candidature_statut()');
    expect(cascade).toContain("set_config(\n    'jolene.candidature_rpc_mission_id'");
    expect(cascade).toContain("set_config('jolene.assignment_rpc_soignant_id'");
    expect(cascade).toContain('CREATE OR REPLACE FUNCTION public.dec_verifier_docs_jusqua_fin()');
    expect(cascade).toContain("drp.type_exercice_requis = 'SALARIE_ONLY'");
    expect(cascade).toContain('CREATE OR REPLACE FUNCTION public.fn_calculer_cotisations(');
    expect(cascade).toContain('CREATE OR REPLACE FUNCTION public.fn_creer_bulletin_paie(');
    expect(cascade).toContain('CREATE OR REPLACE FUNCTION public.fn_trg_auto_facture_honoraires()');
    expect(cascade).toContain('CREATE TRIGGER trg_facture_honoraires_regime_mission');
    expect(cascade).toContain('CREATE OR REPLACE FUNCTION public.fn_mode_paiement_mission(');
    expect(cascade).toContain('CREATE OR REPLACE FUNCTION public.dec_verifier_plafond_48h()');
    expect(cascade).toContain('CREATE OR REPLACE FUNCTION public.fn_toggle_pool_urgence(');
    expect(cascade).toContain('CREATE OR REPLACE FUNCTION public.fn_rebooker_soignant(');
    expect(cascade).toContain('SELECT c.id, c.mission_id, c.cree_le, c.type_contrat_choisi,');
    expect(cascade).toContain(") AS missions\n        FROM public.candidatures c");
    expect(cascade).not.toContain("Mission réservée aux salariés");
  });

  it('couvre feed, pool et notifications avec une éligibilité commune', () => {
    expect(cascade).toContain('public.fn_soignant_eligible_mission(');
    expect(cascade).toContain('CREATE OR REPLACE FUNCTION public.fn_obtenir_missions_swipe(');
    expect(cascade).toContain('CREATE OR REPLACE FUNCTION public.fn_diffuser_pool_urgence(');
    expect(cascade).toContain('CREATE OR REPLACE FUNCTION public.fn_vagues_notification_urgentes(');
    expect(cascade).toContain('CREATE OR REPLACE FUNCTION public.fn_matching_inverse_dispos(');
    expect(cascade).toContain('CREATE OR REPLACE FUNCTION public.fn_suggestions_missions_pour_soignant(');
    expect(cascade).toContain('CREATE OR REPLACE FUNCTION public.fn_booster_mission(');
    expect(cascade).toContain('CREATE OR REPLACE FUNCTION public.fn_relancer_missions_sans_candidat()');
    expect(cascade).toContain('CREATE OR REPLACE FUNCTION public.fn_trg_auto_notify_mission_urgente()');
    expect(cascade).toContain('CREATE OR REPLACE FUNCTION public.fn_detecter_noshow_et_remplacer()');
    expect(cascade).toContain('CREATE OR REPLACE FUNCTION public.fn_escalade_remplacement_non_pourvu()');
    expect(cascade).toContain("'filtre', 'fn_soignant_eligible_mission'");
  });

  it('garde le compte de démonstration sur le code profession IDE valide', () => {
    expect(seedDemo).toContain("profession: 'IDE'");
    expect(seedDemo).toContain(".eq('profession', 'IDE')");
    expect(seedDemo).toContain("user.rpc('fn_modifier_mon_profil'");
    expect(seedDemo).toContain("user.rpc('fn_marquer_etape_onboarding'");
    expect(seedDemo).not.toContain(".from('soignants')\n    .update(");
    expect(seedDemo).not.toContain("'INFIRMIER'");
  });
});
