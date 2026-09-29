-- Fixtures transactionnelles sans fournisseur ni paiement. Les ACL de la
-- fonction sont exercées avec les vrais rôles SQL, sans élargir les GRANT.
BEGIN;
SELECT set_config('request.jwt.claim.sub','',true);
SELECT set_config('request.jwt.claim.role','service_role',true);
SELECT set_config('request.jwt.claims','{"role":"service_role"}',true);
INSERT INTO auth.users(id,instance_id,email,role,aud,raw_app_meta_data,email_confirmed_at)
SELECT ('98700000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
 '00000000-0000-0000-0000-000000000000'::uuid,
 'suivi-escrow-'||n||'@example.invalid','authenticated','authenticated',
 jsonb_build_object('role',CASE WHEN n IN(1,2) THEN 'SOIGNANT' ELSE 'ADMIN_ETABLISSEMENT' END,'is_test_playwright',true),now()
FROM generate_series(1,5) n;
INSERT INTO public.soignants(id,prenom,nom,email,profession,est_compte_test)
SELECT ('98700000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'Fixture','Escrow',
 'suivi-escrow-'||n||'@example.invalid','MEDECIN',true FROM generate_series(1,2)n;
INSERT INTO public.etablissements(id,nom,siret,type,adresse_rue,adresse_ville,adresse_code_postal,email_contact,est_compte_test)
VALUES('98700000-0000-4000-8000-000000000010','Fixture suivi escrow','99198700000010','CLINIQUE_PRIVEE','1 rue Test','Paris','75001','suivi-escrow-etab@example.invalid',true);
INSERT INTO public.membres_etablissement(etablissement_id,user_id,role,actif)
VALUES('98700000-0000-4000-8000-000000000010','98700000-0000-4000-8000-000000000003','PROPRIETAIRE',true),
 ('98700000-0000-4000-8000-000000000010','98700000-0000-4000-8000-000000000004','POINTAGE_ONLY',true),
 ('98700000-0000-4000-8000-000000000010','98700000-0000-4000-8000-000000000005','LECTURE_SEULE',true);
SELECT public.fn_test_seed_mission(jsonb_build_object('id','98700000-0000-4000-8000-000000000020',
 'intitule','Recette statut escrow','etablissement_id','98700000-0000-4000-8000-000000000010',
 'profession_requise','MEDECIN','service','Recette','debut_le',now()+interval '20 years','fin_le',now()+interval '20 years 8 hours','taux_horaire_base',30,'statut','OUVERTE'));
-- Le test porte sur la lecture après remboursement d’une mission en litige,
-- pas sur une attribution de mission à venir ni sur ses exigences documentaires.
SELECT public.fn_test_update_mission('98700000-0000-4000-8000-000000000020',
 '{"soignant_assigne_id":"98700000-0000-4000-8000-000000000001","type_contrat_applique":"LIBERAL","type_paiement_soignant":"NOTE_HONORAIRES","statut":"LITIGE"}');
INSERT INTO public.paiements_escrow(mission_id,etablissement_id,soignant_id,montant_total_cents,commission_cents,honoraires_cents,statut,methode_debit,debit_prevu_le,premiere_mission_etab)
VALUES('98700000-0000-4000-8000-000000000020','98700000-0000-4000-8000-000000000010',
 '98700000-0000-4000-8000-000000000001',28356,4356,24000,'REMBOURSE','SEPA',now()+interval '20 years',true);
DO $acl$
BEGIN
 IF has_function_privilege('anon','public.fn_suivi_escrow_mission(uuid)','EXECUTE')
   OR NOT has_function_privilege('authenticated','public.fn_suivi_escrow_mission(uuid)','EXECUTE')
   OR has_table_privilege('authenticated','public.paiements_escrow','SELECT') THEN
  RAISE EXCEPTION 'ACL du suivi ou table financière élargies'; END IF;
END $acl$;
SET LOCAL ROLE authenticated;
-- Autorisations positives : soignant assigné, propriétaire et lecture financière.
DO $autorises$
DECLARE n integer; r jsonb;
BEGIN
 FOREACH n IN ARRAY ARRAY[1,3,5] LOOP
  PERFORM set_config('request.jwt.claim.sub','',true);
  PERFORM set_config('request.jwt.claim.role','',true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub','98700000-0000-4000-8000-'||lpad(n::text,12,'0'))::text,true);
  SELECT jsonb_agg(to_jsonb(s)) INTO r FROM public.fn_suivi_escrow_mission('98700000-0000-4000-8000-000000000020') s;
  IF r IS DISTINCT FROM '[{"statut":"REMBOURSE","paye_le":null}]'::jsonb THEN
   RAISE EXCEPTION 'Lecture autorisée absente ou données supplémentaires : acteur %',n; END IF;
 END LOOP;
END $autorises$;
-- Refus : autre soignant, membre sans permission financière, utilisateur étranger,
-- absence de session, mission étrangère/inexistante.
DO $refus$
DECLARE n integer; bloque boolean;
BEGIN
 FOREACH n IN ARRAY ARRAY[2,4,99] LOOP
  PERFORM set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub','98700000-0000-4000-8000-'||lpad(n::text,12,'0'))::text,true);
  bloque:=false;
  BEGIN PERFORM public.fn_suivi_escrow_mission('98700000-0000-4000-8000-000000000020');
  EXCEPTION WHEN insufficient_privilege THEN bloque:=true; END;
  IF NOT bloque THEN RAISE EXCEPTION 'Lecture non autorisée pour acteur %',n; END IF;
 END LOOP;
 PERFORM set_config('request.jwt.claims','{"role":"authenticated"}',true);
 bloque:=false;
 BEGIN PERFORM public.fn_suivi_escrow_mission('98700000-0000-4000-8000-000000000020');
 EXCEPTION WHEN insufficient_privilege THEN bloque:=true; END;
 IF NOT bloque THEN RAISE EXCEPTION 'Session absente autorisée'; END IF;
 PERFORM set_config('request.jwt.claims','{"role":"authenticated","sub":"98700000-0000-4000-8000-000000000003"}',true);
 bloque:=false;
 BEGIN PERFORM public.fn_suivi_escrow_mission('98700000-0000-4000-8000-000000000099');
 EXCEPTION WHEN insufficient_privilege THEN bloque:=true; END;
 IF NOT bloque THEN RAISE EXCEPTION 'Mission étrangère autorisée'; END IF;
END $refus$;
RESET ROLE;
UPDATE auth.users SET banned_until=now()+interval '1 day' WHERE id='98700000-0000-4000-8000-000000000001';
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims','{"role":"authenticated","sub":"98700000-0000-4000-8000-000000000001"}',true);
DO $suspendu$
DECLARE bloque boolean:=false;
BEGIN
 BEGIN PERFORM public.fn_suivi_escrow_mission('98700000-0000-4000-8000-000000000020');
 EXCEPTION WHEN insufficient_privilege THEN bloque:=true; END;
 IF NOT bloque THEN RAISE EXCEPTION 'Compte suspendu autorisé'; END IF;
END $suspendu$;
RESET ROLE;
ROLLBACK;
