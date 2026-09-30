-- Fixtures synthétiques, aucun appel fournisseur. Toutes les mutations rollback.
BEGIN;
SELECT set_config('request.jwt.claim.sub','',true);
SELECT set_config('request.jwt.claim.role','service_role',true);
SELECT set_config('request.jwt.claims','{"role":"service_role"}',true);
SELECT set_config('jolene.admin_seed_override_reason','Recette garde initiale résolveur litige',true);

INSERT INTO auth.users(id,instance_id,email,role,aud,raw_app_meta_data,email_confirmed_at)
SELECT ('aba93000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
 '00000000-0000-0000-0000-000000000000',
 'garde-litige-'||n||'@example.invalid','authenticated','authenticated',
 jsonb_build_object('role',CASE WHEN n IN (3,4,5) THEN 'ADMIN_PLATEFORME' WHEN n=2 THEN 'ETABLISSEMENT' ELSE 'SOIGNANT' END),now()
FROM generate_series(1,5) n;
INSERT INTO public.equipe_admin(user_id,nom,prenom,email,actif,acces_groupes)
SELECT ('aba93000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
 'Recette','Garde','garde-litige-'||n||'@example.invalid',n=5,
 ARRAY['Dashboard','Utilisateurs','Missions','Litiges & contrats','Finances','Messagerie','Conformité & Technique','Fondateur']::text[]
FROM generate_series(4,5) n;
INSERT INTO public.etablissements(id,nom,siret,type,adresse_rue,adresse_ville,adresse_code_postal,email_contact,est_compte_test)
VALUES('aba93000-0000-4000-8000-000000000002','Fixture garde litige','99140000930002','CLINIQUE_PRIVEE','1 rue Test','Paris','75001','garde-etab@example.invalid',true);
INSERT INTO public.soignants(id,prenom,nom,email,profession,type_contrat,type_exercice,statut_liberal,siret_liberal,siret_liberal_verifie,siret_liberal_verifie_le,siret_liberal_coherence_identite,heures_cumulees,rpps_verifie,tous_documents_valides,mandat_facturation_signe,statut_compte,est_compte_test)
VALUES('aba93000-0000-4000-8000-000000000001','Fixture','Garde','garde-litige-1@example.invalid','MEDECIN','LIBERAL','MIXTE','ACTIF','99140000930001',true,now(),true,4000,true,true,true,'ACTIF',true);
INSERT INTO public.missions(id,etablissement_id,intitule,profession_requise,debut_le,fin_le,duree_heures,taux_horaire_base,statut,soignant_assigne_id,type_contrat_recherche,type_contrat_applique)
SELECT ('aba93000-0000-4000-8000-'||lpad((100+n)::text,12,'0'))::uuid,
 'aba93000-0000-4000-8000-000000000002','Fixture garde '||n,'MEDECIN',
 now()+interval '20 years'+n*interval '1 day',now()+interval '20 years 8 hours'+n*interval '1 day',8,20,'TERMINEE',
 'aba93000-0000-4000-8000-000000000001','MIXTE',
 (CASE WHEN n<=3 THEN 'SALARIE' ELSE 'LIBERAL' END)::public.type_contrat_applique_enum
FROM generate_series(1,6) n;
INSERT INTO public.litiges(id,mission_id,soignant_id,etablissement_id,initie_par,motif,type_litige,statut)
SELECT ('aba93000-0000-4000-8000-'||lpad((200+n)::text,12,'0'))::uuid,
 ('aba93000-0000-4000-8000-'||lpad((100+n)::text,12,'0'))::uuid,
 'aba93000-0000-4000-8000-000000000001','aba93000-0000-4000-8000-000000000002',
 'SYSTEME','Fixture garde uniforme','DESACCORD_MONTANT_FACTURE',
 CASE (n-1)%3 WHEN 0 THEN 'OUVERT' WHEN 1 THEN 'REVUE_ADMIN' ELSE 'RESOLU_ADMIN' END
FROM generate_series(1,6) n;
CREATE TEMP TABLE litiges_before AS SELECT * FROM public.litiges WHERE id::text LIKE 'aba93000-%';
SELECT set_config('jolene.admin_seed_override_reason','',true);

SET LOCAL ROLE authenticated;
DO $refus$
DECLARE
 n integer; acteur integer; action text; cible uuid; resultat jsonb;
 attendu constant jsonb := '{"success":false,"error":"Administrateur requis."}'::jsonb;
BEGIN
 -- Sans identité ; soignant ; établissement ; simple claim admin ; équipe inactive.
 FOR acteur IN 0..4 LOOP
  PERFORM set_config('request.jwt.claim.sub',CASE WHEN acteur=0 THEN '' ELSE 'aba93000-0000-4000-8000-'||lpad(acteur::text,12,'0') END,true);
  PERFORM set_config('request.jwt.claim.role','authenticated',true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('role','authenticated','aal','aal2','sub',CASE WHEN acteur=0 THEN NULL ELSE 'aba93000-0000-4000-8000-'||lpad(acteur::text,12,'0') END)::text,true);
  FOR n IN 1..7 LOOP
   cible:=('aba93000-0000-4000-8000-'||lpad((200+n)::text,12,'0'))::uuid;
   -- Six dossiers (salarié/libéral × ouvert/revue/résolu) et un absent.
   FOREACH action IN ARRAY ARRAY['AUCUNE','AUTO','COMPLEMENT','INVALIDE'] LOOP
    resultat:=public.fn_admin_resoudre_litige_intelligent(cible,'Décision de recette uniforme','NEUTRE',NULL,NULL,action);
    IF resultat IS DISTINCT FROM attendu THEN RAISE EXCEPTION 'Oracle garde acteur %, dossier %, action % : %',acteur,n,action,resultat; END IF;
   END LOOP;
  END LOOP;
 END LOOP;
 -- L'identité admin valide franchit la garde ; une résolution trop courte
 -- s'arrête dans les résolveurs existants avant toute lecture/verrou/mutation.
 PERFORM set_config('request.jwt.claim.sub','aba93000-0000-4000-8000-000000000005',true);
 PERFORM set_config('request.jwt.claims','{"role":"authenticated","aal":"aal2","sub":"aba93000-0000-4000-8000-000000000005"}',true);
 FOR n IN 1..7 LOOP
  resultat:=public.fn_admin_resoudre_litige_intelligent(('aba93000-0000-4000-8000-'||lpad((200+n)::text,12,'0'))::uuid,'court','NEUTRE',NULL,NULL,'AUCUNE');
  IF resultat->>'error' IS DISTINCT FROM 'La résolution doit contenir entre 10 et 5 000 caractères.' THEN
   RAISE EXCEPTION 'Routage admin existant changé pour dossier % : %',n,resultat;
  END IF;
 END LOOP;
END;
$refus$;
RESET ROLE;
SELECT set_config('request.jwt.claim.sub','',true);
SELECT set_config('request.jwt.claim.role','service_role',true);
SELECT set_config('request.jwt.claims','{"role":"service_role"}',true);
DO $sans_identite$
DECLARE r jsonb;
BEGIN
 r:=public.fn_admin_resoudre_litige_intelligent('aba93000-0000-4000-8000-000000000201','Décision test service','NEUTRE',NULL,NULL,'AUCUNE');
 IF r IS DISTINCT FROM '{"success":false,"error":"Administrateur requis."}'::jsonb THEN RAISE EXCEPTION 'Service sans identité admis : %',r; END IF;
 IF EXISTS((SELECT * FROM public.litiges WHERE id::text LIKE 'aba93000-%') EXCEPT (SELECT * FROM litiges_before))
 OR EXISTS((SELECT * FROM litiges_before) EXCEPT (SELECT * FROM public.litiges WHERE id::text LIKE 'aba93000-%')) THEN
  RAISE EXCEPTION 'Litige modifié pendant un refus';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM private.security_definer_inventory i JOIN pg_proc p ON p.oid=to_regprocedure('public.'||i.signature)
 WHERE i.signature='fn_admin_resoudre_litige_intelligent(uuid,text,text,numeric,numeric,text)'
 AND i.definition_md5='5a13493bf67426d968d0d75aad16b86c' AND md5(p.prosrc)=i.definition_md5 AND i.categorie='ADMIN_EST_ADMIN_VALIDE') THEN
  RAISE EXCEPTION 'Inventaire du wrapper corrigé absent ou divergent';
 END IF;
END;
$sans_identite$;
ROLLBACK;
