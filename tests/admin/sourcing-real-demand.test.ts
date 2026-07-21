import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const migration = readFileSync(
  resolve(
    process.cwd(),
    'supabase/migrations/20260721114949_exclude_test_missions_from_sourcing_scores.sql',
  ),
  'utf8',
);
const schema = readFileSync(
  resolve(process.cwd(), 'supabase/schema/public.sql'),
  'utf8',
);

const fonction = migration.slice(
  migration.indexOf('CREATE OR REPLACE FUNCTION public.fn_admin_sourcing_tableau('),
  migration.indexOf(
    'REVOKE ALL ON FUNCTION public.fn_admin_sourcing_tableau',
  ),
);
const ajoutCrm = migration.slice(
  migration.indexOf('CREATE OR REPLACE FUNCTION public.fn_admin_sourcing_ajouter_crm('),
  migration.indexOf(
    'REVOKE ALL ON FUNCTION public.fn_admin_sourcing_ajouter_crm',
  ),
);
const changerAction = migration.slice(
  migration.indexOf('CREATE OR REPLACE FUNCTION public.fn_admin_acquisition_changer_action('),
  migration.indexOf(
    'REVOKE ALL ON FUNCTION public.fn_admin_acquisition_changer_action',
  ),
);

function corpsMigration(nom: string): string {
  const debut = migration.indexOf(`CREATE OR REPLACE FUNCTION public.${nom}(`);
  const debutCorps = migration.indexOf('AS $fn$\n', debut) + 'AS $fn$\n'.length;
  const finCorps = migration.indexOf('\n$fn$;', debutCorps);
  expect(debut).toBeGreaterThanOrEqual(0);
  expect(debutCorps).toBeGreaterThan('AS $fn$\n'.length - 1);
  expect(finCorps).toBeGreaterThan(debutCorps);
  return migration.slice(debutCorps, finCorps);
}

function corpsBaseline(nom: string): string {
  const debut = schema.indexOf(`CREATE OR REPLACE FUNCTION "public"."${nom}"`);
  const marqueur = nom === 'fn_admin_sourcing_tableau' ? 'AS $_$\n' : 'AS $$\n';
  const finMarqueur = nom === 'fn_admin_sourcing_tableau' ? '\n$_$;' : '\n$$;';
  const debutCorps = schema.indexOf(marqueur, debut) + marqueur.length;
  const finCorps = schema.indexOf(finMarqueur, debutCorps);
  expect(debut).toBeGreaterThanOrEqual(0);
  expect(debutCorps).toBeGreaterThan(marqueur.length - 1);
  expect(finCorps).toBeGreaterThan(debutCorps);
  return schema.slice(debutCorps, finCorps);
}

describe('demande réelle du sourcing admin', () => {
  it('exclut les établissements de test du score et du bloc besoins', () => {
    const demandeScore = fonction.match(
      /WITH demandes AS \(([\s\S]*?)\), candidats AS MATERIALIZED/,
    )?.[1];
    const besoins = fonction.match(
      /INTO v_besoins\s+FROM \(([\s\S]*?)\) b;/,
    )?.[1];

    expect(demandeScore).toContain(
      'AND COALESCE(e.est_compte_test, false) IS FALSE',
    );
    expect(besoins).toContain(
      'AND COALESCE(e.est_compte_test, false) IS FALSE',
    );
  });

  it('ne pénalise pas un prospect réel à cause d’un compte test homonyme', () => {
    const dejaInscritSoignant = fonction.match(
      /SELECT 1 FROM public\.soignants s([\s\S]*?)\)\s+AS deja_inscrit/,
    )?.[1];
    const dejaInscritEtablissement = fonction.match(
      /SELECT 1 FROM public\.etablissements e([\s\S]*?)\)\s+AS deja_inscrit/,
    )?.[1];

    expect(dejaInscritSoignant).toContain(
      'AND COALESCE(s.est_compte_test, false) IS FALSE',
    );
    expect(dejaInscritEtablissement).toContain(
      'AND COALESCE(e.est_compte_test, false) IS FALSE',
    );
    expect(
      fonction.match(/COALESCE\([es]\.est_compte_test, false\) IS FALSE/g),
    ).toHaveLength(4);
  });

  it('ne confond pas les contacts CRM soignants et établissements', () => {
    const blocsDejaCrm = Array.from(
      fonction.matchAll(
        /SELECT 1 FROM public\.sales_contacts c([\s\S]*?)\) AS deja_crm/g,
      ),
      (match) => match[1],
    );

    expect(blocsDejaCrm).toHaveLength(2);
    expect(blocsDejaCrm[0]).toContain("WHERE c.type = 'SOIGNANT'");
    expect(blocsDejaCrm[1]).toContain(
      "WHERE c.type = 'ETABLISSEMENT'",
    );
  });

  it('conserve le contrat et les permissions de la RPC admin', () => {
    expect(fonction).toContain("p_cible text DEFAULT 'SOIGNANT'");
    expect(fonction).toContain('RETURNS jsonb');
    expect(fonction).toContain('LANGUAGE plpgsql');
    expect(fonction).toContain('STABLE');
    expect(fonction).toContain('SECURITY DEFINER');
    expect(fonction).toContain('SET search_path = pg_catalog, public, auth');
    expect(fonction).toContain('IF NOT public.est_admin() THEN');
    expect(migration).toContain(
      'REVOKE ALL ON FUNCTION public.fn_admin_sourcing_tableau(text, text, text, text, boolean, boolean, boolean, integer, integer) FROM PUBLIC, anon;',
    );
    expect(migration).toContain(
      'GRANT EXECUTE ON FUNCTION public.fn_admin_sourcing_tableau(text, text, text, text, boolean, boolean, boolean, integer, integer) TO authenticated, service_role;',
    );
  });

  it('pré-aligne la baseline versionnée pour éviter un nouveau drift quotidien', () => {
    const debut = schema.indexOf('CREATE OR REPLACE FUNCTION "public"."fn_admin_sourcing_tableau"');
    const fin = schema.indexOf('ALTER FUNCTION "public"."fn_admin_sourcing_tableau"', debut);
    expect(debut).toBeGreaterThanOrEqual(0);
    expect(fin).toBeGreaterThan(debut);
    const fonctionBaseline = schema.slice(debut, fin);
    expect(
      fonctionBaseline.match(/COALESCE\([es]\.est_compte_test, false\) IS FALSE/g),
    ).toHaveLength(4);
    for (const nom of [
      'fn_admin_sourcing_tableau',
      'fn_admin_sourcing_ajouter_crm',
      'fn_admin_acquisition_changer_action',
    ]) {
      expect(corpsBaseline(nom)).toBe(corpsMigration(nom));
    }
  });

  it('déduplique un soignant uniquement avec un autre contact soignant', () => {
    expect(ajoutCrm).toContain("WHERE c.type = 'SOIGNANT'");
    expect(ajoutCrm).toMatch(
      /WHERE c\.type = 'SOIGNANT'\s+AND \([\s\S]*?source_prospect_type = 'SOIGNANT'[\s\S]*?lower\(c\.email\)[\s\S]*?regexp_replace\(c\.telephone/,
    );
  });

  it('garantit le CRM silencieux sur insertion et sur doublon', () => {
    expect(ajoutCrm.match(/false, NULL/g)).toHaveLength(2);
    expect(ajoutCrm).toMatch(
      /UPDATE public\.sales_contacts\s+SET sequence_active = false,\s+prochaine_action_le = NULL,[\s\S]*?WHERE id = v_contact_id;/,
    );
    expect(ajoutCrm).toContain("'contact_automatique', false");
    expect(migration).toContain(
      'REVOKE ALL ON FUNCTION public.fn_admin_sourcing_ajouter_crm(text, text, smallint) FROM PUBLIC, anon;',
    );
    expect(migration).toContain(
      'GRANT EXECUTE ON FUNCTION public.fn_admin_sourcing_ajouter_crm(text, text, smallint) TO authenticated, service_role;',
    );
  });

  it('verrouille et impose le cycle des recommandations côté serveur', () => {
    expect(changerAction).toContain('IF NOT public.est_admin() THEN');
    expect(changerAction).toMatch(
      /FROM public\.acquisition_actions\s+WHERE id = p_action_id\s+FOR UPDATE/,
    );
    expect(changerAction).toContain(
      "v_statut_actuel = 'BROUILLON' AND p_statut IN ('PRIORISEE', 'IGNORE')",
    );
    expect(changerAction).toContain(
      "v_statut_actuel = 'PRIORISEE' AND p_statut IN ('EN_COURS', 'IGNORE')",
    );
    expect(changerAction).toContain(
      "v_statut_actuel = 'EN_COURS' AND p_statut = 'TERMINEE'",
    );
    expect(changerAction).toContain('p_statut <> v_statut_actuel');
    expect(changerAction).toContain("RAISE EXCEPTION 'Transition invalide (% -> %)'");
    expect(migration).toContain(
      'REVOKE ALL ON FUNCTION public.fn_admin_acquisition_changer_action(uuid, text) FROM PUBLIC, anon;',
    );
    expect(migration).toContain(
      'GRANT EXECUTE ON FUNCTION public.fn_admin_acquisition_changer_action(uuid, text) TO authenticated, service_role;',
    );
  });
});
