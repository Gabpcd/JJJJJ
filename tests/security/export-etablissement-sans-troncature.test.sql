-- Projection existante : 201 missions + 201 contrats, ordre et isolation.
-- Fixtures test uniquement ; aucun appel fournisseur, tout est annulé.
BEGIN;
DO $test$
DECLARE
  etab uuid := '99022000-0000-4000-8000-000000000001';
  autre uuid := '99022000-0000-4000-8000-000000000002';
  membre uuid := '99022000-0000-4000-8000-000000000003';
  sans_etab uuid := '99022000-0000-4000-8000-000000000004';
  soignant uuid := '99022000-0000-4000-8000-000000000005';
  r jsonb; attendu jsonb; bloque boolean; n integer;
BEGIN
  BEGIN
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claim.role', 'service_role', true);
  PERFORM set_config('request.jwt.claims', '{"role":"service_role"}', true);
  PERFORM set_config('jolene.admin_seed_override_reason', 'Recette export 201 éléments annulée', true);
  INSERT INTO auth.users(id, instance_id, email, role, aud, raw_app_meta_data, email_confirmed_at)
  SELECT ('99022000-0000-4000-8000-' || lpad(i::text, 12, '0'))::uuid,
    '00000000-0000-0000-0000-000000000000', 'export-etab-' || i || '@example.invalid',
    'authenticated', 'authenticated', jsonb_build_object('role', CASE WHEN i = 5 THEN 'SOIGNANT' ELSE 'ADMIN_ETABLISSEMENT' END, 'is_test_playwright', true), now()
  FROM generate_series(1, 5) i;
  INSERT INTO public.etablissements(id, nom, siret, type, adresse_rue, adresse_ville, adresse_code_postal, email_contact, est_compte_test)
  VALUES(etab, 'Export complet fixture', '99022000000001', 'CLINIQUE_PRIVEE', 'Test', 'Paris', '75001', 'export-etab-1@example.invalid', true),
    (autre, 'Export tiers fixture', '99022000000002', 'CLINIQUE_PRIVEE', 'Test', 'Paris', '75001', 'export-etab-2@example.invalid', true);
  INSERT INTO public.membres_etablissement(etablissement_id, user_id, role, actif) VALUES(etab, membre, 'PROPRIETAIRE', true);
  INSERT INTO public.soignants(id, email, prenom, nom, profession, type_exercice, est_compte_test)
  VALUES(soignant, 'export-etab-5@example.invalid', 'Export', 'Fixture', 'IDE', 'SALARIE', true);
  INSERT INTO public.missions(id, etablissement_id, intitule, profession_requise, debut_le, fin_le, duree_heures,
    taux_horaire_base, statut, type_contrat_recherche, cree_le)
  SELECT ('99022001-0000-4000-8000-' || lpad(i::text, 12, '0'))::uuid,
    CASE WHEN i = 202 THEN autre ELSE etab END, 'Mission export ' || i, 'IDE',
    '2046-01-01 08:00:00+00'::timestamptz + i * interval '1 day',
    '2046-01-01 16:00:00+00'::timestamptz + i * interval '1 day', 8, 20, 'OUVERTE', 'SALARIE', '2026-01-01 00:00:00+00'
  FROM generate_series(1, 202) i;
  INSERT INTO public.contrats_mission(id, mission_id, etablissement_id, soignant_id, type_contrat, numero_contrat, statut, cree_le, modifie_le)
  SELECT ('99022002-0000-4000-8000-' || lpad(i::text, 12, '0'))::uuid,
    ('99022001-0000-4000-8000-' || lpad(i::text, 12, '0'))::uuid,
    CASE WHEN i = 202 THEN autre ELSE etab END, soignant, 'CDD', 'EXPORT-FIXTURE-' || i, 'BROUILLON',
    '2026-01-01 00:00:00+00', '2026-01-01 00:00:00+00'::timestamptz + i * interval '1 second'
  FROM generate_series(1, 202) i;

  IF has_function_privilege('anon', 'public.fn_exporter_rgpd_etablissement()', 'EXECUTE')
    OR NOT has_function_privilege('authenticated', 'public.fn_exporter_rgpd_etablissement()', 'EXECUTE')
    OR NOT has_function_privilege('service_role', 'public.fn_exporter_rgpd_etablissement()', 'EXECUTE') THEN
    RAISE EXCEPTION 'ACL export divergentes';
  END IF;
  IF NOT EXISTS(SELECT 1 FROM private.security_definer_inventory i JOIN pg_proc p ON p.oid = 'public.fn_exporter_rgpd_etablissement()'::regprocedure
    WHERE i.signature = 'fn_exporter_rgpd_etablissement()' AND i.categorie = 'RPC_UTILISATEUR_AUTH_INTERNE' AND i.definition_md5 = md5(p.prosrc)) THEN
    RAISE EXCEPTION 'Inventaire export non actualisé';
  END IF;
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub', etab::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', etab, 'role', 'authenticated')::text, true);
  r := public.fn_exporter_rgpd_etablissement();
  IF jsonb_array_length(r->'missions') IS DISTINCT FROM 201 OR jsonb_array_length(r->'contrats') IS DISTINCT FROM 201 THEN
    RAISE EXCEPTION 'Export tronqué au-delà de 200';
  END IF;
  IF (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(r) k) IS DISTINCT FROM ARRAY['contrats','etablissement','export_date','factures','missions'] THEN
    RAISE EXCEPTION 'Schéma JSON export changé';
  END IF;
  IF (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(r->'contrats'->0) k) IS DISTINCT FROM ARRAY['cree_le','modifie_le','statut','type_contrat']
    OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(r->'missions'->0) k) IS DISTINCT FROM ARRAY['cree_le','debut_le','fin_le','id','intitule','statut','taux_horaire_base','total_brut'] THEN
    RAISE EXCEPTION 'Projection JSON changée';
  END IF;
  FOR n IN 1..201 LOOP
    IF r->'missions'->(201 - n)->>'id' IS DISTINCT FROM '99022001-0000-4000-8000-' || lpad(n::text, 12, '0')
      OR (r->'contrats'->(201 - n)->>'modifie_le')::timestamptz IS DISTINCT FROM '2026-01-01 00:00:00+00'::timestamptz + n * interval '1 second' THEN
      RAISE EXCEPTION 'Ordre instable ou élément absent : %', n;
    END IF;
  END LOOP;
  attendu := r;
  IF public.fn_exporter_rgpd_etablissement() IS DISTINCT FROM attendu THEN RAISE EXCEPTION 'Export non reproductible dans la transaction'; END IF;

  -- Un membre exporte l'établissement canonique, même si son user.id diffère.
  PERFORM set_config('request.jwt.claim.sub', membre::text, true);
  PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', membre, 'role', 'authenticated')::text, true);
  IF public.fn_exporter_rgpd_etablissement() IS DISTINCT FROM attendu THEN RAISE EXCEPTION 'Scope du membre perdu'; END IF;
  PERFORM set_config('request.jwt.claim.sub', autre::text, true);
  PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', autre, 'role', 'authenticated')::text, true);
  r := public.fn_exporter_rgpd_etablissement();
  IF jsonb_array_length(r->'missions') IS DISTINCT FROM 1 OR jsonb_array_length(r->'contrats') IS DISTINCT FROM 1
    OR r->'missions'->0->>'id' IS DISTINCT FROM '99022001-0000-4000-8000-000000000202'
    OR r->'etablissement'->>'nom' IS DISTINCT FROM 'Export tiers fixture' THEN
    RAISE EXCEPTION 'Export tiers non isolé';
  END IF;
  PERFORM set_config('request.jwt.claim.sub', sans_etab::text, true);
  PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', sans_etab, 'role', 'authenticated')::text, true);
  IF public.fn_exporter_rgpd_etablissement() IS DISTINCT FROM '{"error":"Accès refusé"}'::jsonb THEN RAISE EXCEPTION 'Compte sans établissement autorisé'; END IF;
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claims', '{"role":"authenticated"}', true);
  IF public.fn_exporter_rgpd_etablissement() IS DISTINCT FROM '{"error":"Accès refusé"}'::jsonb THEN RAISE EXCEPTION 'Absence de session autorisée'; END IF;
  EXECUTE 'SET LOCAL ROLE anon';
  bloque := false;
  BEGIN PERFORM public.fn_exporter_rgpd_etablissement(); EXCEPTION WHEN insufficient_privilege THEN bloque := true; END;
  IF NOT bloque THEN RAISE EXCEPTION 'Appel anonyme autorisé'; END IF;

  EXECUTE 'RESET ROLE';
  UPDATE auth.users SET banned_until = now() + interval '1 day' WHERE id = membre;
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub', membre::text, true);
  PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', membre, 'role', 'authenticated')::text, true);
  IF public.fn_exporter_rgpd_etablissement() IS DISTINCT FROM '{"error":"Accès refusé"}'::jsonb THEN RAISE EXCEPTION 'Membre suspendu autorisé'; END IF;
  EXECUTE 'RESET ROLE';
  RAISE EXCEPTION 'ROLLBACK_EXPORT_ETABLISSEMENT' USING ERRCODE = 'ZX220';
  EXCEPTION WHEN SQLSTATE 'ZX220' THEN NULL;
  END;
END;
$test$;
ROLLBACK;
