import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';

const read = (path: string) => readFileSync(join(process.cwd(), path), 'utf8');
const migration = read(
  'supabase/migrations/20260714003439_corriger_fonctions_runtime_lint.sql',
);
const panneau = read('src/components/PanneauContestation.tsx');
const adminLitiges = read('src/pages/admin/AdminLitiges.tsx');
const formulaire = read('src/components/litige/FormulaireAccord.tsx');
const resolutionModal = read(
  'src/components/admin/litiges/LitigeResolutionModal.tsx',
);

describe('accords de litige liés à une proposition exacte', () => {
  it('aligne le panneau présence sur les statuts et la signature RPC canoniques', () => {
    expect(panneau).toContain("OUVERT: { label: 'Ouvert'");
    expect(panneau).toContain("litige.statut === 'OUVERT'");
    expect(panneau).toContain("p_statut: statut");
    expect(panneau).toContain("p_resolution: resolution");
    expect(panneau).toContain(
      "p_type_litige: 'DESACCORD_HEURES_POINTAGE'",
    );
    expect(panneau).toContain("resoudreAdmin('RESOLU_SOIGNANT')");
    expect(panneau).toContain("resoudreAdmin('RESOLU_ETABLISSEMENT')");
    expect(panneau).not.toContain('RESOLUE_');
    expect(panneau).not.toContain("litige?.statut === 'CONTESTEE'");

    expect(migration).toContain(
      "'public.fn_resoudre_litige(uuid,text,text)'::regprocedure",
    );
    expect(migration).toContain(
      "v_litige.statut = 'REVUE_ADMIN'\n       OR v_litige.payload_modifications IS NOT NULL",
    );
    expect(migration).toContain(
      'Accord structuré à traiter via le parcours financier administrateur',
    );
  });

  it('garde ouverture et réponse par compte actif et permission contrats', () => {
    const openTyped = migration.match(
      /CREATE OR REPLACE FUNCTION public\.fn_ouvrir_litige_rate_limited\(\n {2}p_mission_id uuid,\n {2}p_type_litige[\s\S]*?\$function\$;/,
    )?.[0];
    const openLegacy = migration.match(
      /CREATE OR REPLACE FUNCTION public\.fn_ouvrir_litige_rate_limited\(\n {2}p_mission_id uuid,\n {2}p_motif[\s\S]*?\$function\$;/,
    )?.[0];
    const reply = migration.match(
      /CREATE OR REPLACE FUNCTION public\.fn_repondre_litige\([\s\S]*?\$function\$;/,
    )?.[0];

    expect(openTyped).toBeDefined();
    expect(openTyped).toContain('public.fn_compte_auth_actif() IS NOT TRUE');
    expect(openTyped).toContain("'contrats', v_mission.etablissement_id");
    expect(openTyped).toContain("'REVUE_ADMIN'");
    expect(openLegacy).toBeDefined();
    expect(openLegacy).toContain('public.fn_compte_auth_actif() IS NOT TRUE');
    expect(openLegacy).toContain("'AUTRE'::public.type_litige");

    expect(reply).toBeDefined();
    expect(reply).toContain('public.fn_compte_auth_actif() IS NOT TRUE');
    expect(reply).toContain("'contrats', l.etablissement_id");
    expect(reply).toContain('FOR UPDATE');
    expect(reply).toContain("'MEDIATION_EN_COURS'");
  });

  it('fait passer la RPC réellement appelée par le frontend par le chemin canonique', () => {
    expect(panneau).toContain("supabase.rpc('fn_proposer_cloture_litige'");
    const wrapper = migration.match(
      /CREATE OR REPLACE FUNCTION public\.fn_proposer_cloture_litige[\s\S]*?\$function\$;/,
    )?.[0];
    expect(wrapper).toBeDefined();
    expect(wrapper).toContain('public.fn_cloturer_litige(p_litige_id, NULL)');
    expect(wrapper).not.toMatch(/UPDATE public\.litiges|UPDATE litiges/);

    const confirmer = migration.match(
      /CREATE OR REPLACE FUNCTION public\.fn_confirmer_accord_partie[\s\S]*?\$function\$;/,
    )?.[0];
    expect(confirmer).toBeDefined();
    expect(confirmer).toContain('public.fn_cloturer_litige(p_litige_id, NULL)');
    expect(confirmer).not.toMatch(/UPDATE public\.litiges|UPDATE litiges/);

    const mediation = migration.match(
      /CREATE OR REPLACE FUNCTION public\.fn_proposer_accord_partie[\s\S]*?\$function\$;/,
    )?.[0];
    expect(mediation).toBeDefined();
    expect(mediation).toContain('public.fn_compte_auth_actif() IS NOT TRUE');
    expect(mediation).toContain("'contrats', l.etablissement_id");
    expect(mediation).toContain('FOR UPDATE');
  });

  it('valide le schéma exécutable et conserve un payload UI strictement identique', () => {
    const payloadRpc = migration.match(
      /CREATE OR REPLACE FUNCTION public\.fn_cloturer_litige_avec_payload[\s\S]*?\$function\$;/,
    )?.[0];
    expect(payloadRpc).toBeDefined();
    for (const type of [
      'MODIFICATION_HORAIRES',
      'MODIFICATION_MONTANT',
      'ANNULATION_TOTALE',
      'COMPENSATION_PARTIELLE',
      'MIXTE',
      'ACCORD_SANS_MODIFICATION',
    ]) {
      expect(payloadRpc).toContain(`'${type}'`);
    }
    expect(payloadRpc).toContain("p_payload - ARRAY['type', 'modifications', 'justification']::text[]");
    expect(payloadRpc).toContain("v_modifications <> '{}'::jsonb");
    expect(formulaire).toContain('const payloadExact = {');
    expect(formulaire).toContain('p_payload: payloadExact');
    expect(formulaire).not.toContain('p_payload: propositionExistante');
  });

  it('n’autorise l’exécution admin que sur une double acceptation financière verrouillée', () => {
    const validator = migration.match(
      /CREATE OR REPLACE FUNCTION public\.fn_admin_valider_accord_litige[\s\S]*?\$function\$;/,
    )?.[0];
    expect(validator).toBeDefined();
    expect(validator).toContain('FOR UPDATE');
    expect(validator).toContain("v_litige.statut <> 'REVUE_ADMIN'");
    expect(validator).toContain('v_litige.accord_soignant IS NOT TRUE');
    expect(validator).toContain('v_litige.accord_etablissement IS NOT TRUE');
    expect(validator).toContain('v_litige.accord_soignant_le IS NULL');
    expect(validator).toContain('v_litige.accord_etablissement_le IS NULL');
    expect(validator).toContain("= 'ACCORD_SANS_MODIFICATION'");
    expect(validator).toContain('v_litige.modifications_executees IS TRUE');
    expect(validator).toContain("'RESOLUTION_FINANCIERE_MANUELLE_REQUISE'");
    expect(validator).toContain("'manual_resolution_required', true");
    expect(validator).toContain("COALESCE((v_exec->>'success')::boolean, false) IS NOT TRUE");
    expect(validator).toContain(
      'v_audit_result := public.fn_ecrire_audit_safe(',
    );
    expect(validator).toContain(
      "'evenement', 'LITIGE_ACCORD_VALIDE_ADMIN'",
    );
    expect(validator).toContain(
      `COALESCE(v_audit_result @> '{"success": true}'::jsonb, false)`,
    );
    expect(validator.indexOf('v_exec := public.fn_executer_modifications_litige')).toBeLessThan(
      validator.indexOf("SET statut = 'RESOLU_ADMIN'"),
    );
  });

  it('dégèle les factures sur tous les statuts résolus canoniques', () => {
    for (const statut of [
      'RESOLU_SOIGNANT',
      'RESOLU_ETABLISSEMENT',
      'RESOLU_ADMIN',
      'FERME',
      'RESOLU_ACCORD_PARTIES',
      'RESOLU_FAVEUR_SOIGNANT',
      'RESOLU_FAVEUR_ETAB',
      'RESOLU_PARTAGE',
    ]) {
      expect(migration).toContain(`'${statut}'`);
    }
    expect(migration).toContain(
      "$new$v_statuts_ouverts TEXT[] := ARRAY[\n    'OUVERT', 'EN_DISCUSSION', 'EN_MEDIATION',\n    'MEDIATION_EN_COURS', 'REVUE_ADMIN'",
    );
    expect(migration).toContain(
      "$new$v_statuts_resolus TEXT[] := ARRAY[\n    'RESOLU_SOIGNANT', 'RESOLU_ETABLISSEMENT', 'RESOLU_ADMIN', 'FERME'",
    );
  });

  it('affiche le bouton admin avec les mêmes préconditions que la RPC', () => {
    expect(adminLitiges).toContain("l.statut === 'REVUE_ADMIN'");
    expect(adminLitiges).toContain('l.accord_soignant === true');
    expect(adminLitiges).toContain('l.accord_etablissement === true');
    expect(adminLitiges).toContain('!!l.accord_soignant_le');
    expect(adminLitiges).toContain('!!l.accord_etablissement_le');
    expect(adminLitiges).toContain("l.payload_modifications.type !== 'ACCORD_SANS_MODIFICATION'");
    expect(adminLitiges).toContain('requiertResolutionFinanciereManuelle(l)');
    expect(adminLitiges).toContain('ouvrirResolution(l)');
    expect(adminLitiges).toContain('Traiter l’accord financier');
    expect(adminLitiges).toContain(
      'payload_modifications: l.payload_modifications ?? null',
    );
    expect(resolutionModal).toContain('accord-parties-reference');
    expect(resolutionModal).toContain(
      'Accord exact accepté par les deux parties',
    );
    expect(resolutionModal).toContain(
      'Le serveur appliquera exactement cette référence',
    );
  });

  it('verrouille les RPC historiques réellement appelées par les pages litiges', () => {
    const proposer = migration.match(
      /CREATE OR REPLACE FUNCTION public\.fn_proposer_accord_partie[\s\S]*?\$function\$;/,
    )?.[0];
    const confirmer = migration.match(
      /CREATE OR REPLACE FUNCTION public\.fn_confirmer_accord_partie[\s\S]*?\$function\$;/,
    )?.[0];
    const trancher = migration.match(
      /CREATE OR REPLACE FUNCTION public\.fn_admin_trancher_litige[\s\S]*?\$function\$;/,
    )?.[0];
    const message = migration.match(
      /CREATE OR REPLACE FUNCTION public\.fn_ajouter_message_litige[\s\S]*?\$function\$;/,
    )?.[0];

    for (const fn of [proposer, confirmer, trancher, message]) {
      expect(fn).toBeDefined();
      expect(fn).toContain('FOR UPDATE');
    }
    expect(proposer).toContain('public.fn_compte_auth_actif() IS NOT TRUE');
    expect(proposer).toContain("'contrats', l.etablissement_id");
    expect(proposer).toContain('v_litige.payload_modifications IS NOT NULL');
    expect(confirmer).toContain('public.fn_compte_auth_actif() IS NOT TRUE');
    expect(confirmer).toContain("'contrats', l.etablissement_id");
    expect(confirmer).toContain('public.fn_cloturer_litige(p_litige_id, NULL)');
    expect(confirmer).not.toContain('OR public.est_admin');
    expect(trancher).toContain('public.est_admin() IS NOT TRUE');
    expect(trancher).toContain("v_litige.statut = 'REVUE_ADMIN'");
    expect(trancher).toContain('v_litige.payload_modifications IS NOT NULL');
    expect(message).toContain('public.fn_compte_auth_actif() IS NOT TRUE');
    expect(message).toContain("'contrats', l.etablissement_id");
    expect(message).toContain("'REVUE_ADMIN'");
    expect(message).not.toContain("v_litige.statut = 'CLOTURE'");
  });
});
