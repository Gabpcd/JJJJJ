import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const migration = readFileSync(
  'supabase/migrations/20260801091225_aligner_planning_exact_candidature_creation_edition.sql',
  'utf8',
);
const migrationDuree = readFileSync(
  'supabase/migrations/20260801090000_elargir_duree_mission.sql',
  'utf8',
);
const baseline = readFileSync(
  'supabase/migrations/00000000000000_baseline_prod.sql',
  'utf8',
);
const stagingWorkflow = readFileSync(
  '.github/workflows/deploy-supabase-staging.yml',
  'utf8',
);
const apiMigration = readFileSync(
  'supabase/migrations/20260801114528_api_v1_planning_exact.sql',
  'utf8',
);
const remplacementRbacMigration = readFileSync(
  'supabase/migrations/20260801153000_securiser_rbac_sync_planning_remplacement.sql',
  'utf8',
);
const apiV1 = readFileSync('supabase/functions/api-v1/index.ts', 'utf8');
const formulaireMission = readFileSync('src/components/FormulaireMission.tsx', 'utf8');
const modifierMission = readFileSync('src/pages/ModifierMission.tsx', 'utf8');

function empreinteCorps(nom: string): string {
  const declaration = migration.indexOf(`CREATE OR REPLACE FUNCTION public.${nom}(`);
  const marqueur = '$function$';
  const debut = migration.indexOf(`AS ${marqueur}`, declaration) + `AS ${marqueur}`.length;
  const fin = migration.indexOf(marqueur, debut);
  expect(declaration, `${nom}: déclaration absente`).toBeGreaterThanOrEqual(0);
  expect(debut, `${nom}: corps absent`).toBeGreaterThan(`AS ${marqueur}`.length);
  expect(fin, `${nom}: fin du corps absente`).toBeGreaterThan(debut);
  return createHash('md5').update(migration.slice(debut, fin)).digest('hex');
}

function corpsFonction(nom: string): string {
  const declaration = migration.indexOf(`CREATE OR REPLACE FUNCTION public.${nom}(`);
  const marqueur = '$function$';
  const debut = migration.indexOf(`AS ${marqueur}`, declaration) + `AS ${marqueur}`.length;
  const fin = migration.indexOf(marqueur, debut);
  expect(declaration, `${nom}: déclaration absente`).toBeGreaterThanOrEqual(0);
  expect(debut, `${nom}: corps absent`).toBeGreaterThan(`AS ${marqueur}`.length);
  expect(fin, `${nom}: fin du corps absente`).toBeGreaterThan(debut);
  return migration.slice(debut, fin);
}

describe('planning exact de bout en bout', () => {
  it('valide un payload de créneaux datés avant toute écriture', () => {
    expect(migration).toContain('fn_valider_creneaux_mission_json');
    expect(migration).toContain('p_appliquer_plafond_48h boolean DEFAULT true');
    expect(migration).toContain('Deux créneaux de la mission se chevauchent');
    expect(migration).toContain('PLAFOND_48H_HEBDO');
    expect(migration).toContain("'code', 'REPOS_11H'");
    expect(migration).toContain("AT TIME ZONE 'Europe/Paris'");
    expect(migration).toContain("SET TimeZone TO 'UTC'");
    expect(migration).toContain('Chaque date et heure doit inclure son fuseau');
    expect(migration).toContain('Une mission ne peut pas couvrir plus de 366 dates');
    expect(migration).toContain('ck_max_732_creneaux');
  });

  it('réserve le plafond salarié de 48 h aux régimes non libéraux', () => {
    const validation = corpsFonction('fn_valider_creneaux_mission_json');
    const debutCondition = validation.indexOf(
      'IF COALESCE(p_appliquer_plafond_48h, true) THEN',
    );
    expect(debutCondition).toBeGreaterThanOrEqual(0);
    expect(validation.indexOf('WHERE total > 48')).toBeGreaterThan(debutCondition);
    expect(migration).toContain("p_type_contrat_recherche <> 'LIBERAL'");
    expect(migration).toContain("v_type_contrat_recherche <> 'LIBERAL'");
    expect(migration).toContain('c.type_contrat_choisi::text');
    expect(migration).toContain("COALESCE(v_choix_contrat, '')");
    expect(apiMigration).toContain("p_type_contrat_recherche <> 'LIBERAL'");
    expect(apiMigration).toContain("|| ' [CONTRAT:' || p_type_contrat_recherche || ']'");
  });

  it('crée et modifie mission et créneaux dans une transaction unique', () => {
    expect(migration.trimStart()).toMatch(/^--[\s\S]*\nBEGIN;/);
    expect(migration.trimEnd()).toMatch(/COMMIT;$/);
    expect(migration).toContain('CREATE OR REPLACE FUNCTION public.fn_creer_mission_multi_jours');
    expect(migration).toContain('CREATE OR REPLACE FUNCTION public.fn_modifier_mission_etablissement_v3');
    expect(migration).toContain("DELETE FROM public.mission_creneaux");
    expect(migration).toContain("AND type_creneau = 'PREVISIONNEL'");
    expect(migration).toContain("'planning_modifie', v_planning_modifie");
    expect(migration).toContain('Le planning ne peut pas être modifié pendant que des candidatures sont en attente');
    expect(migration).toContain('IF v_planning_modifie THEN');
    expect(migration).not.toContain('LOCK TABLE public.missions, public.mission_creneaux IN ACCESS EXCLUSIVE MODE');
    expect(migration).not.toContain('DISABLE TRIGGER USER');
    expect(migration).toContain("m.fin_le <= m.debut_le + interval '24 hours'");
    expect(migration).toContain('duree_heures <= 17568');
  });

  it('refuse édition et republication si le nombre de créneaux source est incomplet', () => {
    expect(modifierMission).toContain('construirePlanningCandidat');
    expect(modifierMission).toContain("if (!planning.exact)");
    expect(modifierMission).toContain('Planning contractuel incomplet');
    expect(formulaireMission).toContain('planningSourceRepublication');
    expect(formulaireMission).toContain('republicationBloquee');
    expect(formulaireMission).toContain('La republication est bloquée');
  });

  it('élargit la précision de durée dans une migration courte préalable', () => {
    expect(migrationDuree.trimStart()).toMatch(/^--[\s\S]*\nBEGIN;/);
    expect(migrationDuree).toContain('pg_get_triggerdef');
    expect(migrationDuree).toContain('pg_catalog.pg_depend');
    expect(migrationDuree).toContain('DROP TRIGGER %I ON public.missions');
    expect(migrationDuree).toContain('ALTER COLUMN duree_heures TYPE numeric(7, 2)');
    expect(migrationDuree).toContain('EXECUTE v_trigger.definition');
    expect(migrationDuree).toContain("n''a pas été restauré");
    expect(migrationDuree).toContain('numeric_precision');
    expect(migrationDuree).toContain('numeric_scale');
    expect(migrationDuree.trimEnd()).toMatch(/COMMIT;$/);
  });

  it('convertit les créations legacy et recopie les créneaux des remplacements', () => {
    expect(migration).toContain('CREATE OR REPLACE FUNCTION public.dec_initialiser_planning_exact_legacy');
    expect(migration).toContain('NEW.remplacement_de_mission_id IS NOT NULL');
    expect(migration).toContain('mc.mission_id = NEW.remplacement_de_mission_id');
    expect(migration).toContain('GREATEST(mc.debut, NEW.debut_le)');
    expect(migration).toContain('LEAST(mc.fin, NEW.fin_le)');
    expect(migration).toContain("'jolene.planning_exact_managed', 'true'");
    expect(migration).toContain("'[PLANNING_SOURCE_INDISPONIBLE]");

    const pontLegacy = corpsFonction('dec_initialiser_planning_exact_legacy');
    expect(pontLegacy.indexOf('UPDATE public.missions')).toBeGreaterThan(
      pontLegacy.lastIndexOf('INSERT INTO public.mission_creneaux'),
    );

    const gardeConflit = corpsFonction('dec_refuser_chevauchement_soignant');
    expect(gardeConflit).toMatch(
      /IF TG_OP = 'INSERT'[\s\S]*AND v_nb = 0[\s\S]*IS DISTINCT FROM 'true' THEN[\s\S]*RETURN NEW;/,
    );
    expect(baseline).toMatch(
      /TRIGGER "dec_chevauchement" BEFORE INSERT OR UPDATE[\s\S]*dec_refuser_chevauchement_soignant/,
    );
    expect(baseline).toMatch(
      /TRIGGER "dec_mission_repos_11h_before_update" BEFORE UPDATE[\s\S]*dec_verifier_repos_11h/,
    );
  });

  it('scelle étroitement le recalage RBAC des remplacements', () => {
    expect(remplacementRbacMigration).toContain(
      'CREATE OR REPLACE FUNCTION private.fn_guard_contexte_empechement_mission',
    );
    expect(remplacementRbacMigration).toContain(
      "v_expected := 'REPLACEMENT:'",
    );
    expect(remplacementRbacMigration).toContain(
      "current_setting('jolene.sync_in_progress', true) = 'true'",
    );
    expect(remplacementRbacMigration).toContain(
      "'debut_le', 'fin_le', 'duree_heures', 'nb_creneaux'",
    );
    expect(remplacementRbacMigration).toContain(
      'NEW.nb_creneaux = v_planning_nb',
    );
    expect(remplacementRbacMigration).toContain(
      'NEW.duree_heures = v_planning_total',
    );
    expect(remplacementRbacMigration).toContain(
      'CREATE OR REPLACE FUNCTION public.fn_enforce_etablissement_rbac_trigger',
    );
    expect(remplacementRbacMigration).not.toContain(
      "set_config('jolene.system_update', 'true'",
    );
    expect(remplacementRbacMigration).not.toContain('session_replication_role');
  });

  it('ne compare plus les enveloppes globales pour les conflits', () => {
    expect(migration).toContain('CREATE OR REPLACE FUNCTION public.dec_refuser_chevauchement_soignant');
    expect(migration).toContain('CREATE OR REPLACE FUNCTION public.fn_conflit_planning_soignant');
    expect(migration).toContain('cible.debut < existant.fin');
    expect(migration).toContain('cible.fin > existant.debut');
    expect(migration).not.toMatch(/m\.debut_le\s*<\s*v_mission\.fin_le/);
    expect(migration).not.toMatch(/m\.fin_le\s*>\s*v_mission\.debut_le/);
    expect(migration).toContain("'code', 'REPOS_11H'");
    expect(migration).toContain("m.statut IN ('ASSIGNEE', 'EN_COURS', 'TERMINEE')");
  });

  it('échoue fermé si le détail du planning est absent', () => {
    expect(migration).toContain('PLANNING_DETAILLE_INDISPONIBLE');
    expect(migration).toContain('ne peut pas être attribuée sans planning daté complet');
    expect(migration).toContain('Le planning daté doit être complet avant toute candidature');
    expect(migration).toContain('PLANNING_EXISTANT_INDISPONIBLE');
    expect(migration).toContain('NEW.nb_creneaux <> v_nb');
    expect(migration).toContain('dec_exiger_planning_confirme_candidature');
    expect(migration).toContain("'jolene.planning_confirme_mission_id'");
  });

  it('vérifie aussi côté serveur les actions candidat et établissement', () => {
    expect(migration).toContain('CREATE OR REPLACE FUNCTION public.fn_confirmer_action_planning_v1');
    expect(migration).toContain('CREATE OR REPLACE FUNCTION public.fn_traiter_candidature_planning_v1');
    expect(migration).toContain('c.mission_id = p_mission_id');
    expect(migration).toContain('c.soignant_id = (SELECT auth.uid())');
    expect(migration).toContain("'PLANNING_MODIFIE_RECONFIRMER'");
  });

  it('restreint les helpers internes et conserve les adaptateurs de rollout authentifiés', () => {
    expect(migration).toMatch(
      /REVOKE ALL ON FUNCTION public\.fn_valider_creneaux_mission_json\(jsonb, boolean\)[\s\S]*FROM PUBLIC, anon, authenticated/,
    );
    expect(migration).toMatch(
      /REVOKE ALL ON FUNCTION public\.fn_conflit_planning_soignant\(uuid, uuid\)[\s\S]*FROM PUBLIC, anon, authenticated/,
    );
    expect(migration).toMatch(
      /GRANT EXECUTE ON FUNCTION public\.fn_modifier_mission_etablissement_v3[\s\S]*TO authenticated, service_role/,
    );
    expect(migration).toMatch(
      /REVOKE INSERT, UPDATE, DELETE ON TABLE public\.mission_creneaux\s+FROM anon, authenticated/,
    );
    expect(migration).toMatch(
      /GRANT EXECUTE ON FUNCTION public\.fn_creer_mission\([\s\S]*TO authenticated, service_role/,
    );
    expect(migration).toMatch(
      /GRANT EXECUTE ON FUNCTION public\.fn_modifier_mission_etablissement_v2\([\s\S]*TO authenticated, service_role/,
    );
    expect(migration).toContain('Adaptateur de compatibilité pendant la phase d\'expansion');
    expect(migration).not.toMatch(
      /fn_creer_mission\([\s\S]{0,500}FROM PUBLIC, anon, authenticated/,
    );
  });

  it('recapture explicitement chaque SECURITY DEFINER modifiée ou ajoutée', () => {
    for (const nom of [
      'fn_confirmer_action_planning_v1',
      'fn_traiter_candidature_planning_v1',
      'fn_conflit_planning_soignant',
      'fn_creer_mission_multi_jours',
      'fn_modifier_mission_etablissement_v3',
      'fn_modifier_mission_etablissement_v2',
      'dec_initialiser_planning_exact_legacy',
    ]) {
      expect(migration).toContain(`'${empreinteCorps(nom)}'`);
    }
    expect(migration).toContain('Manifest SECURITY DEFINER planning incomplet : %/426');
    expect(migration).toContain("categorie = 'MIXTE_TENANT_ADMIN'");
    expect(migration).toContain(') <> 104 THEN');
  });

  it('restaure l’inventaire prod avant le push staging et en vérifie le compte dynamique', () => {
    const restauration = stagingWorkflow.indexOf(
      "TRUNCATE TABLE private.security_definer_inventory",
    );
    const commandePush = /^\s*supabase db push \\$/m.exec(stagingWorkflow);
    const push = commandePush?.index ?? -1;
    expect(stagingWorkflow).toContain('/tmp/security-definer-inventory.csv');
    expect(restauration).toBeGreaterThanOrEqual(0);
    expect(push).toBeGreaterThan(restauration);
    expect(stagingWorkflow).toContain('EXPECTED_INVENTORY_COUNT=$(python3 -c');
    expect(stagingWorkflow).toContain(
      'INVENTORY_COUNT" != "$EXPECTED_INVENTORY_COUNT"',
    );
    expect(stagingWorkflow.match(/--single-transaction/g)).toHaveLength(3);
    expect(stagingWorkflow).not.toContain(
      '-f supabase/migrations/20260729121443_figer_inventaire_security_definer.sql',
    );
  });

  it('cree les missions API et leurs creneaux dans une seule RPC transactionnelle', () => {
    expect(apiV1).toContain('couple legacy debut_le/fin_le');
    expect(apiV1).toContain('debutLegacy');
    expect(apiV1).toContain("supabase.rpc('fn_creer_mission_api_v2'");
    expect(apiV1).not.toMatch(/\.from\(['"]missions['"]\)\.insert/);
    expect(apiMigration).toContain('CREATE OR REPLACE FUNCTION public.fn_creer_mission_api_v1');
    expect(apiMigration).toContain('SECURITY INVOKER');
    expect(apiMigration).toContain('INSERT INTO public.mission_creneaux');
    expect(apiMigration).toMatch(
      /REVOKE ALL ON FUNCTION public\.fn_creer_mission_api_v1[\s\S]*FROM PUBLIC, anon, authenticated/,
    );
    expect(apiMigration).toMatch(
      /GRANT EXECUTE ON FUNCTION public\.fn_creer_mission_api_v1[\s\S]*TO service_role/,
    );
  });

  it('valide strictement les dates API, retourne les créneaux et masque les erreurs SQL', () => {
    expect(apiV1).toContain('function instantIsoStrict');
    expect(apiV1).toContain('joursParMois');
    expect(apiV1).toContain('heureDecalage === 14');
    expect(apiV1).toContain('creneaux.push({ debut, fin })');
    expect(apiV1).not.toContain('mission_creneaux(debut, fin, ordre, est_pause, type_creneau)');
    expect(apiV1).toContain(".select('id, mission_id, debut, fin, ordre', { count: 'exact' })");
    expect(apiV1).toContain('.range(offsetCreneaux, offsetCreneaux + TAILLE_PAGE_CRENEAUX - 1)');
    expect(apiV1).toContain(".order('mission_id', { ascending: true })");
    expect(apiV1).toContain(".order('id', { ascending: true })");
    expect(apiV1).toContain('idsCreneauxVus.has(creneau.id)');
    expect(apiV1).toContain('count !== totalCreneauxAttendu');
    expect(apiV1).toContain('countFinal !== totalCreneauxAttendu');
    expect(apiV1).toContain('planning.length !== nbCreneauxDeclare');
    expect(apiV1).not.toContain('resultat.error');
    expect(apiMigration).not.toMatch(/'error',\s*SQLERRM/);
    expect(apiMigration).toContain("'code', 'CREATION_MISSION_INDISPONIBLE'");
  });

  it('applique contrat et retrocession atomiquement a la creation formulaire et API', () => {
    expect(formulaireMission).toContain("supabase.rpc('fn_creer_mission_multi_jours_v3'");
    expect(formulaireMission).not.toContain("supabase.rpc('fn_modifier_type_contrat_mission'");
    expect(formulaireMission).not.toContain("supabase.rpc('fn_definir_retrocession_mission'");
    expect(formulaireMission).not.toContain("setTauxHoraire('0')");
    expect(apiMigration).toContain('CREATE OR REPLACE FUNCTION public.fn_creer_mission_multi_jours_v2');
    expect(apiMigration).toContain('RAISE EXCEPTION \'Retrocession non appliquee: %\'');
    expect(apiMigration).toContain('p_type_contrat_recherche');
    expect(apiMigration).toContain('p_mode_remuneration');
    expect(apiMigration).toContain('p_retrocession_pct');
  });
});
