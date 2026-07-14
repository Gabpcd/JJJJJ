import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';

const migration = readFileSync(
  join(
    process.cwd(),
    'supabase/migrations/20260714011105_corriger_lint_residuel_prelaunch.sql',
  ),
  'utf8',
);

const runtimeRegression = readFileSync(
  join(
    process.cwd(),
    'tests/admin/security/database-runtime-lint-residual.test.sql',
  ),
  'utf8',
);

const demoDefinition = migration.slice(
  migration.indexOf(
    'CREATE OR REPLACE FUNCTION public.fn_charger_demo_investisseur()',
  ),
  migration.indexOf('-- 9. Variable jamais lue.'),
);

describe('solde du lint PL/pgSQL pré-lancement', () => {
  it('applique uniquement des remplacements exacts et fail-closed', () => {
    expect(migration).toContain('jolene_replace_function_fragment');
    expect(migration).toContain('p_expected_occurrences integer DEFAULT 1');
    expect(migration).toContain('IF v_occurrences <> p_expected_occurrences THEN');
    expect(migration).toContain('DROP FUNCTION pg_temp.jolene_replace_function_fragment');
  });

  it('utilise les colonnes et tables canoniques', () => {
    expect(migration).toContain('e.adresse_ville');
    expect(migration).toContain('e.email_contact');
    expect(migration).toContain('FROM public.notations_missions n');
    expect(migration).toContain('n.publie_le IS NOT NULL');
    expect(migration).toContain('exclu_par = v_user_id OR exclu_id = v_user_id');
    expect(migration).toContain("statut = 'OUVERTE'");
    expect(migration).toContain('f.date_echeance < CURRENT_DATE');
  });

  it('réutilise le lecteur de secret protégé sans créer de RPC à paramètre', () => {
    expect(migration.match(/v_token := public\.fn_lire_secret_cron\(\);/g)).toHaveLength(2);
    expect(migration).toContain('https://flripxtsyegjshnhzjkz.supabase.co');
    expect(migration).not.toMatch(/CREATE OR REPLACE FUNCTION public\.fn_lire_secret_cron/);
    expect(migration.match(/IF v_send_email_called THEN/g)).toHaveLength(2);
    expect(migration).toContain(
      "jsonb_build_object('sens', 'ETAB_VERS_SOIGNANT', 'send_email_called', true)",
    );
  });

  it('aligne les types et le calcul temporel sur le schéma réel', () => {
    expect(migration).toContain("'CDD'::public.type_contrat");
    expect(migration).toContain("interval '30 minutes'");
    expect(migration).toContain("AT TIME ZONE 'Europe/Paris'");
    expect(migration).toContain('v_nuit := v_nuit + v_duree');
    expect(migration).toContain(
      'ALTER FUNCTION public.fn_calculer_heures_majorees(',
    );
    expect(migration).toMatch(/\) STABLE;/);
    expect(migration).toContain('ARRAY[]::uuid[]');
    expect(migration).toContain("p_plan_id, 'ACTIF'");
  });

  it('préserve les données de démonstration sans rejouer un seed invalide', () => {
    expect(demoDefinition).toContain("'mode', 'PRESERVATION'");
    expect(demoDefinition).toContain('WHERE est_compte_test IS TRUE');
    expect(demoDefinition).not.toMatch(/\b(?:INSERT|UPDATE|DELETE)\b/i);
  });

  it('ferme les gardes BOLA des trois variantes d’annulation', () => {
    expect(migration.match(/IS DISTINCT FROM/g)).toHaveLength(5);
    expect(migration).toContain(
      'public.fn_annuler_mission_etab(uuid,text,text)',
    );
    expect(migration).toContain(
      'public.fn_annuler_mission_etablissement(uuid,text)',
    );
    expect(
      migration.match(/'missions', v_mission\.etablissement_id/g),
    ).toHaveLength(2);
    expect(migration).toMatch(
      /REVOKE ALL ON FUNCTION public\.fn_annuler_mission\(uuid, text\)[\s\S]*FROM PUBLIC, anon, authenticated, service_role;/,
    );
  });

  it('construit ses fixtures BOLA dans la transaction sans seed de démonstration', () => {
    expect(runtimeRegression).toContain('BEGIN;');
    expect(runtimeRegression).toContain('INSERT INTO auth.users');
    expect(runtimeRegression).toContain('INSERT INTO public.etablissements');
    expect(runtimeRegression).toContain('INSERT INTO public.membres_etablissement');
    expect(runtimeRegression).toContain('INSERT INTO public.missions');
    expect(runtimeRegression).toContain('ROLLBACK;');
    expect(runtimeRegression).not.toContain(
      'Fixture BOLA impossible : aucune mission cible',
    );
    expect(runtimeRegression).not.toMatch(
      /FROM public\.missions m\s+ORDER BY m\.id\s+LIMIT 1/,
    );
  });

  it('notifie les administrateurs via la source canonique', () => {
    expect(migration).toContain(
      'FROM public.fn_list_admin_user_ids() AS admins(admin_user_id)',
    );
    expect(migration).toContain("      'ADMIN',");
  });

  it('protège les informations de commission par lecture_paiement', () => {
    expect(migration).toContain('v_etab_id uuid');
    expect(migration).toContain('public.fn_compte_auth_actif() IS NOT TRUE');
    expect(migration).toContain("'lecture_paiement', v_etab_id");
    expect(migration).toContain('INTO v_etab WHERE e.id = v_etab_id');
  });

  it('retire le registre 2FA legacy sans élargir les ACL', () => {
    expect(migration).toContain(
      'private.fn_admin_creer_compte_employe_interne_lancement',
    );
    expect(migration).toContain("p.prosrc LIKE '%INSERT INTO admin_securite%'");
    expect(migration).not.toMatch(/\bGRANT\b/i);
    expect(migration).toMatch(
      /REVOKE ALL ON FUNCTION public\.fn_souscrire_prevoyance\(uuid, text\)/,
    );
  });
});
