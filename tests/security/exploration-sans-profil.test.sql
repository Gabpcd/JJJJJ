-- Comptes et offres de recette invisibles hors de cette transaction.
BEGIN;
INSERT INTO auth.users(id,instance_id,email,role,aud,raw_app_meta_data,email_confirmed_at) VALUES
('69100000-0000-4000-8000-000000000001','00000000-0000-0000-0000-000000000000','exploration-recette@example.invalid','authenticated','authenticated','{}',now());
INSERT INTO public.etablissements(id,nom,siret,finess,finess_verifie,type,adresse_rue,adresse_ville,adresse_code_postal,email_contact,
  statut_verification,peut_publier_missions,siret_verifie,representant_identite_verifiee,rattachement_verifie,contrat_service_signe,est_compte_test)
VALUES('69100000-0000-4000-8000-000000000002','Recette découverte','69100000000002','691000002',true,'CLINIQUE_PRIVEE','1 rue de la Recette','Paris','75001','etablissement-recette@example.invalid',
  'VERIFIE',true,true,true,true,true,false);
-- La base de pré-lancement force tous les établissements en compte test.
-- Simuler une offre publique uniquement pour cette fixture, dans cette session
-- et transaction annulée ; aucune donnée existante ni règle prod modifiée.
SET LOCAL session_replication_role = replica;
UPDATE public.etablissements SET est_compte_test=false WHERE id='69100000-0000-4000-8000-000000000002';
SET LOCAL session_replication_role = origin;
INSERT INTO public.missions(id,etablissement_id,intitule,profession_requise,debut_le,fin_le,taux_horaire_base,statut,type_contrat_recherche,mode_attribution,mode_remuneration,retrocession_pct)
VALUES
('69100000-0000-4000-8000-000000000003','69100000-0000-4000-8000-000000000002','Renfort découverte A','IDE',now()+interval '7 days',now()+interval '7 days 8 hours',30,'OUVERTE','SALARIE','CANDIDATURE','TAUX_HORAIRE',NULL),
('69100000-0000-4000-8000-000000000004','69100000-0000-4000-8000-000000000002','Renfort découverte B','IDE',now()+interval '8 days',now()+interval '8 days 8 hours',30,'OUVERTE','SALARIE','CANDIDATURE','TAUX_HORAIRE',NULL);

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims','{"sub":"69100000-0000-4000-8000-000000000001","role":"authenticated"}',true);
DO $preuve$
DECLARE r jsonb; refuse boolean := false;
BEGIN
  PERFORM public.fn_demarrer_inscription('SOIGNANT','IDE',NULL,true,false);
  r := public.fn_explorer_missions_inscription('69100000-0000-4000-8000-000000000003',0,100);
  IF jsonb_array_length(r) <> 1 OR r->0->>'intitule' <> 'Renfort découverte A'
    OR r->0->>'mode_remuneration' <> 'TAUX_HORAIRE' OR jsonb_array_length(r->0->'creneaux') <> 1 THEN
    RAISE EXCEPTION 'Offre/planning non restitués : %',r;
  END IF;
  IF r->0 ? 'email_contact' OR r->0->'etablissements' ? 'email_contact' THEN RAISE EXCEPTION 'Contact privé exposé'; END IF;
  PERFORM public.fn_modifier_favori_inscription('69100000-0000-4000-8000-000000000003',true);
  PERFORM public.fn_modifier_favori_inscription('69100000-0000-4000-8000-000000000004',true);
  PERFORM public.fn_modifier_favori_inscription('69100000-0000-4000-8000-000000000003',true);
  SELECT donnees INTO r FROM public.parcours_inscription WHERE user_id=auth.uid();
  IF jsonb_array_length(r->'missionsSauvegardees') <> 2 THEN RAISE EXCEPTION 'Favori perdu ou dupliqué'; END IF;
  PERFORM public.fn_modifier_favori_inscription('69100000-0000-4000-8000-000000000003',false);
  SELECT donnees INTO r FROM public.parcours_inscription WHERE user_id=auth.uid();
  IF r->'missionsSauvegardees' <> '["69100000-0000-4000-8000-000000000004"]'::jsonb THEN RAISE EXCEPTION 'Retrait incorrect'; END IF;
  BEGIN PERFORM public.fn_enregistrer_parcours_inscription('{"missionsSauvegardees":[]}');
  EXCEPTION WHEN invalid_parameter_value THEN refuse := true; END;
  IF NOT refuse THEN RAISE EXCEPTION 'Remplacement non atomique des favoris autorisé'; END IF;
  IF public.fn_get_my_role()->>'role' <> 'INCONNU' THEN RAISE EXCEPTION 'Profil créé par exploration'; END IF;
  IF NOT has_function_privilege('authenticated','public.fn_modifier_favori_inscription(uuid,boolean)','EXECUTE')
    OR has_function_privilege('anon','public.fn_modifier_favori_inscription(uuid,boolean)','EXECUTE') THEN RAISE EXCEPTION 'ACL favoris incorrectes'; END IF;
END;
$preuve$;
RESET ROLE;
ROLLBACK;
