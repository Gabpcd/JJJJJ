-- Admission des internes : spécialité prouvée et choix explicite établissement.
-- Les contrats et attributions antérieurs restent inchangés.

-- Préconditions relevées LIVE le 29/10/2026 : aucun corps voisin ne peut être écrasé.
DO $catalogue$
DECLARE r record; v_path text := current_setting('search_path');
BEGIN
  PERFORM set_config('search_path','public',true);
  FOR r IN SELECT * FROM (VALUES
    ('private.fn_resultats_filtre_missions(uuid,timestamp with time zone)','4acbd9ffe4c9542071de1f39fca927f1','postgres','{postgres=X/postgres}'),
    ('private.fn_resultats_recherche_soignants_etab(uuid,text,text[],text,integer,text,numeric,integer,integer,boolean,boolean,text)','02a970341c629c52c3532db338b7ffaa','postgres','{postgres=X/postgres}'),
    ('private.fn_soignant_visible_pool_etablissement(uuid,uuid,uuid)','5e012124b21477facd88b36ee2099afd','postgres','{postgres=X/postgres}'),
    ('public.fn_accepter_mission_urgence(uuid)','bcecb0ef55ee1ee1d54b9a7f7e622645','postgres','{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'),
    ('public.fn_admin_moderer_document_internal_20260810(uuid,text,text,jsonb,text)','9c4be4995b90bcc4ad41385ff772df44','postgres','{postgres=X/postgres}'),
    ('public.fn_calculer_tous_documents_valides(uuid)','b657145d300a5750338f7f3aadeb169e','postgres','{postgres=X/postgres,service_role=X/postgres}'),
    ('public.fn_creer_mission_multi_jours_v3(text,text,type_profession,text,numeric,boolean,integer,text,text,boolean,jsonb,text,text,numeric,text)','bba0db7877485b54ac22cdb76351cdb6','postgres','{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}'),
    ('public.fn_documents_ok_pour_mission(uuid,text)','6d12fc8dbca0531792dc810a786e3f64','postgres','{postgres=X/postgres,service_role=X/postgres}'),
    ('public.fn_enregistrer_swipe(uuid,text,text)','a9bcaf6626e8f8c143f41b89af6fcbe2','postgres','{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}'),
    ('public.fn_finaliser_attribution_mission(uuid,uuid,text)','15b78cd8f72f811becb878b3ed1bc8fe','postgres','{postgres=X/postgres,service_role=X/postgres}'),
    ('public.fn_finaliser_document_verification(uuid,uuid,uuid,text,text,text,text,text,date,text,text,text,text,text,boolean,boolean,text,text,date,date,jsonb,text,text,numeric,boolean,date,text,text,text,integer,text,date,text,text,date,date,numeric,text)','fa55027307a0de0ec444edf49641b0ed','postgres','{postgres=X/postgres,service_role=X/postgres}'),
    ('public.fn_get_my_role()','5db4161b2bd9140582726cc9e4186350','postgres','{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'),
    ('public.fn_invalider_preuves_identite_sur_changement()','acd66e6fdfe800238fb33326a835ae21','postgres','{postgres=X/postgres,service_role=X/postgres}'),
    ('public.fn_lire_candidatures_mission_habilitee(uuid)','5df1abf5ab9393948925c698f136c2b2','postgres','{postgres=X/postgres,authenticated=X/postgres}'),
    ('public.fn_modifier_mission_etablissement_v4(uuid,text,text,text,type_profession,numeric,boolean,integer,text,text,text,boolean,jsonb,text)','d9ef95fc3cb282d8ed772da831b2812c','postgres','{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}'),
    ('public.fn_noms_personne_correspondent(text,text,text,text)','e5eee5295cced868f22fa7d2de62443e','postgres','{postgres=X/postgres,service_role=X/postgres}'),
    ('public.fn_normaliser_nom(text)','3369efbb36c0194fdad01b8f27dc36fc','postgres','{postgres=X/postgres,service_role=X/postgres}'),
    ('public.fn_pool_urgence_etablissement(uuid)','942b532b9a1f84cfdb5123264dcd77de','postgres','{postgres=X/postgres,authenticated=X/postgres}'),
    ('public.fn_postuler_mission(uuid,text,text)','609f31938fe027d4ee7e8c5c57796a51','postgres','{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'),
    ('public.fn_proposer_mission_soignant(uuid,uuid,text)','c42bec9be211f8a5d030886d03fb45bc','postgres','{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'),
    ('public.fn_protect_specialite_medicale_verifiee()','274d54c264d65cf0d7e7a1a7a4336eca','postgres','{postgres=X/postgres,service_role=X/postgres}'),
    ('public.fn_rebooker_soignant(uuid,uuid,timestamp with time zone,timestamp with time zone)','aa2b77dc5bcfe0ed536902dd0ac47f54','postgres','{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'),
    ('public.fn_recalculer_preuves_etudiant_internal_20260810(uuid)','6154d8cd3e123afe5bdcfd20aaf995ee','postgres','{postgres=X/postgres,service_role=X/postgres}'),
    ('public.fn_recalculer_tous_documents_valides()','5a5ba97fcb2e36b0fb0c8829d988ffb3','postgres','{postgres=X/postgres,service_role=X/postgres}'),
    ('public.fn_rechercher_soignants_etab(text,text[],text,integer,text,numeric,integer,integer,boolean,boolean,text,integer,integer)','de9fe7f13a3134de261dda46eb33134d','postgres','{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'),
    ('public.fn_soignant_compatible_mission(type_profession,text,type_profession,text,boolean)','da12dc43b9820a9c3b5b8878ec230ddf','postgres','{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'),
    ('public.fn_soignant_eligible_mission(uuid,uuid,boolean)','f62ecb0014f1284385e57d604eeb229f','postgres','{postgres=X/postgres,service_role=X/postgres}'),
    ('public.fn_soignant_pour_etablissement(uuid)','9ef6f323607bb01b9cd4d4fc0c1f4b49','postgres','{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'),
    ('public.fn_trg_recalculer_preuves_etudiant_document()','1e99fcc3010d16e1be5c86936e37e368','postgres','{postgres=X/postgres,service_role=X/postgres}'),
    ('public.fn_type_document_preuve_compatible(type_document,type_document)','23cad3499449899d1b983408e2e5984c','postgres','{postgres=X/postgres,service_role=X/postgres}')
  ) AS x(signature,definition_md5,owner_name,acl) LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid=to_regprocedure(r.signature)
      AND md5(pg_get_functiondef(p.oid))=r.definition_md5
      AND pg_get_userbyid(p.proowner)=r.owner_name
      AND COALESCE(p.proacl::text,'')=r.acl) THEN
      RAISE EXCEPTION 'INTERNAT_DEPENDANCE_MODIFIEE : %',r.signature USING ERRCODE='55000';
    END IF;
  END LOOP;
  PERFORM set_config('search_path',v_path,true);
END;
$catalogue$;


-- Règle produit demandée : un interne ne reçoit que les missions de la
-- spécialité portée par sa preuve active, après choix explicite de l'établissement.
-- Aucune déduction juridique, aucune modification des contrats déjà attribués.

-- L'audit LIVE du 27/10 ne trouve aucun médecin étudiant/licence existante.
-- Si la situation change avant déploiement, une revue des profils doit précéder
-- toute initialisation ; aucun classement rétroactif implicite d'un diplômé.
DO $preflight$
BEGIN
  IF EXISTS (SELECT 1 FROM public.soignants s WHERE s.profession::text='MEDECIN'
    AND s.supprime_le IS NULL AND (s.est_etudiant OR s.licence_remplacement_le IS NOT NULL
      OR s.licence_remplacement_verifiee)) THEN
    RAISE EXCEPTION 'Préparation internat : revue des profils existants requise avant migration.';
  END IF;
END;
$preflight$;

ALTER TABLE public.soignants
  ADD COLUMN internat_medical_identifie boolean NOT NULL DEFAULT false;
ALTER TABLE public.missions
  ADD COLUMN accepte_internes boolean NOT NULL DEFAULT false,
  ADD COLUMN accepte_internes_confirme_par uuid,
  ADD COLUMN accepte_internes_confirme_le timestamptz;

-- Le marqueur ne constitue pas une preuve : il empêche de contourner le
-- contrôle en décochant est_etudiant après l'identification du parcours.
-- Aucun médecin existant n'est classé interne par défaut.
CREATE FUNCTION private.fn_identifier_parcours_interne()
RETURNS trigger LANGUAGE plpgsql SET search_path TO '' AS $body$
BEGIN
  IF TG_OP = 'UPDATE' AND OLD.internat_medical_identifie THEN
    NEW.internat_medical_identifie := true;
  ELSE
    NEW.internat_medical_identifie := NEW.profession::text IS NOT DISTINCT FROM 'MEDECIN'
      AND (NEW.est_etudiant IS TRUE OR NEW.licence_remplacement_verifiee IS TRUE);
  END IF;
  RETURN NEW;
END;
$body$;
REVOKE ALL ON FUNCTION private.fn_identifier_parcours_interne() FROM PUBLIC, anon, authenticated;
CREATE TRIGGER trg_zz_identifier_parcours_interne
BEFORE INSERT OR UPDATE ON public.soignants
FOR EACH ROW EXECUTE FUNCTION private.fn_identifier_parcours_interne();

-- Pas de rapprochement sémantique : seul un code existant ou un libellé exact
-- après casse/espaces est résolu. Ambiguïté ou variante => revue manuelle.
CREATE FUNCTION private.fn_code_specialite_licence_exact(p_texte text)
RETURNS text LANGUAGE sql STABLE SET search_path TO '' AS $body$
  SELECT CASE WHEN count(*) = 1 THEN min(sm.code) ELSE NULL END
  FROM public.specialites_medicales sm
  WHERE sm.code ~ '^SM[0-9]+$'
    AND sm.actif IS TRUE AND sm.profession_parent = 'MEDECIN'
    AND (upper(btrim(p_texte)) = sm.code
      OR lower(regexp_replace(btrim(p_texte), '\s+', ' ', 'g'))
         = lower(regexp_replace(btrim(sm.label), '\s+', ' ', 'g')));
$body$;
REVOKE ALL ON FUNCTION private.fn_code_specialite_licence_exact(text) FROM PUBLIC, anon, authenticated;

-- Décision humaine distincte : une attestation d'inscription à l'Ordre portant
-- la qualification, et non le seul RPPS ou la déclaration d'études.
CREATE TABLE private.qualifications_medicales (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  soignant_id uuid NOT NULL,
  document_id uuid NOT NULL,
  specialite_code text NOT NULL,
  preuve_empreinte text NOT NULL,
  decide_par uuid NOT NULL,
  decide_le timestamptz NOT NULL DEFAULT now(),
  motif text NOT NULL CHECK (char_length(motif) BETWEEN 20 AND 1000),
  critere text NOT NULL DEFAULT 'INSCRIPTION_ORDRE_QUALIFICATION_V1'
    CHECK (critere = 'INSCRIPTION_ORDRE_QUALIFICATION_V1'),
  revoque_le timestamptz,
  revoque_par uuid,
  motif_revocation text
);
CREATE UNIQUE INDEX qualifications_medicales_active ON private.qualifications_medicales(soignant_id)
  WHERE revoque_le IS NULL;
ALTER TABLE private.qualifications_medicales ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.qualifications_medicales FROM PUBLIC, anon, authenticated, service_role;

-- Pas de FK vers le document : la décision conserve son histoire si la source
-- disparaît. Le lecteur recalcule sa validité. Cela évite un verrou documentaire
-- acquis après le verrou profil des admissions et décisions.
CREATE FUNCTION private.fn_empreinte_qualification(p_soignant_id uuid,p_document_id uuid)
RETURNS text LANGUAGE sql STABLE SET search_path TO '' AS $body$
  SELECT encode(extensions.digest(jsonb_build_array(
    s.id,s.nom,s.prenom,s.date_naissance,s.sexe,s.lieu_naissance_commune,
    s.profession,s.numero_rpps,s.rpps_verifie,
    d.id,d.soignant_id,d.type_document,d.s3_bucket,d.s3_cle,d.s3_version_id,
    d.modifie_le,d.statut_verification,d.verifie_par,d.verifie_le,d.coherence_nom,
    d.valide_depuis,d.valide_jusqua,d.supprime_le,d.revoque_le
  )::text,'sha256'),'hex')
  FROM public.soignants s JOIN public.documents_soignants d ON d.soignant_id=s.id
  WHERE s.id=p_soignant_id AND d.id=p_document_id;
$body$;
REVOKE ALL ON FUNCTION private.fn_empreinte_qualification(uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private.fn_qualification_medicale_actuelle(p_soignant_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO '' AS $body$
  SELECT jsonb_build_object('decision_id',q.id,'specialite_code',q.specialite_code,
    'specialite_label',sm.label,'valide_jusqua',d.valide_jusqua)
  FROM private.qualifications_medicales q
  JOIN public.soignants s ON s.id=q.soignant_id
  JOIN public.documents_soignants d ON d.id=q.document_id AND d.soignant_id=s.id
  JOIN public.specialites_medicales sm ON sm.code=q.specialite_code
    AND sm.actif IS TRUE AND sm.profession_parent = 'MEDECIN'
  WHERE s.id=p_soignant_id AND s.profession='MEDECIN' AND s.supprime_le IS NULL
    AND s.rpps_verifie IS TRUE AND s.numero_rpps IS NOT NULL
    AND q.revoque_le IS NULL AND d.type_document='CARTE_ORDRE'
    AND d.statut_verification='VERIFIE' AND d.verifie_le IS NOT NULL
    AND d.coherence_nom IS TRUE AND d.supprime_le IS NULL AND d.revoque_le IS NULL
    AND d.valide_depuis IS NOT NULL AND d.valide_depuis<=current_date
    AND (d.valide_jusqua IS NULL OR d.valide_jusqua>current_date)
    AND q.preuve_empreinte=private.fn_empreinte_qualification(s.id,d.id);
$body$;
REVOKE ALL ON FUNCTION private.fn_qualification_medicale_actuelle(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION private.fn_qualification_medicale_actuelle(uuid) TO service_role;

CREATE FUNCTION public.fn_admin_lire_qualification_medicale(p_soignant_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO '' AS $body$
DECLARE v_s public.soignants%ROWTYPE; v_q private.qualifications_medicales%ROWTYPE; v_documents jsonb;
BEGIN
  IF auth.uid() IS NULL OR public.est_admin() IS NOT TRUE THEN
    RAISE EXCEPTION 'Administrateur autorisé requis' USING ERRCODE='42501';
  END IF;
  SELECT * INTO v_s FROM public.soignants WHERE id=p_soignant_id AND supprime_le IS NULL;
  IF NOT FOUND OR v_s.profession <> 'MEDECIN' OR v_s.internat_medical_identifie IS NOT TRUE THEN
    RAISE EXCEPTION 'Ce profil ne relève pas de la transition après internat.' USING ERRCODE='23514';
  END IF;
  SELECT * INTO v_q FROM private.qualifications_medicales WHERE soignant_id=p_soignant_id AND revoque_le IS NULL;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('id',d.id,'nom_fichier',d.nom_fichier,
    's3_bucket',d.s3_bucket,'s3_cle',d.s3_cle,
    'statut',d.statut_verification,'valide_depuis',d.valide_depuis,'valide_jusqua',d.valide_jusqua,
    'empreinte',private.fn_empreinte_qualification(v_s.id,d.id)) ORDER BY d.televerse_le DESC,d.id),'[]'::jsonb)
  INTO v_documents FROM public.documents_soignants d
  WHERE d.soignant_id=v_s.id AND d.type_document='CARTE_ORDRE' AND d.supprime_le IS NULL AND d.revoque_le IS NULL;
  RETURN jsonb_build_object('soignant_id',v_s.id,'numero_rpps',v_s.numero_rpps,
    'rpps_verifie',v_s.rpps_verifie,'documents',v_documents,'decision_id',v_q.id,
    'qualification',private.fn_qualification_medicale_actuelle(v_s.id),
    'decision_invalidee',v_q.id IS NOT NULL AND private.fn_qualification_medicale_actuelle(v_s.id) IS NULL);
END;
$body$;
REVOKE ALL ON FUNCTION public.fn_admin_lire_qualification_medicale(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.fn_admin_lire_qualification_medicale(uuid) TO authenticated;

CREATE FUNCTION public.fn_admin_decider_qualification_medicale(
  p_soignant_id uuid,p_document_id uuid,p_preuve_empreinte text,p_decision_attendue uuid,
  p_specialite_code text,p_numero_rpps_lu text,p_inscription_confirmee boolean,
  p_qualification_confirmee boolean,p_motif text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $body$
DECLARE v_s public.soignants%ROWTYPE; v_d public.documents_soignants%ROWTYPE;
  v_q private.qualifications_medicales%ROWTYPE; v_id uuid;
BEGIN
  IF auth.uid() IS NULL OR public.est_admin() IS NOT TRUE THEN
    RAISE EXCEPTION 'Administrateur autorisé requis' USING ERRCODE='42501';
  END IF;
  -- Même sérialisation que l'admission ; ne pas prendre de verrou document après.
  SELECT * INTO v_s FROM public.soignants WHERE id=p_soignant_id AND supprime_le IS NULL FOR UPDATE;
  IF NOT FOUND OR v_s.profession <> 'MEDECIN' OR v_s.internat_medical_identifie IS NOT TRUE THEN
    RAISE EXCEPTION 'Profil non concerné par la transition après internat.' USING ERRCODE='23514';
  END IF;
  SELECT * INTO v_q FROM private.qualifications_medicales WHERE soignant_id=v_s.id AND revoque_le IS NULL;
  SELECT * INTO v_d FROM public.documents_soignants WHERE id=p_document_id AND soignant_id=v_s.id;
  IF NOT FOUND OR p_preuve_empreinte IS NULL OR p_preuve_empreinte IS DISTINCT FROM
      private.fn_empreinte_qualification(v_s.id,v_d.id) THEN
    RAISE EXCEPTION 'La preuve ou l’identité a changé : rechargez la revue.' USING ERRCODE='40001';
  END IF;
  -- Réponse perdue/double clic : le même état et la même décision restent uniques.
  IF v_q.id IS NOT NULL AND v_q.document_id=p_document_id AND v_q.preuve_empreinte=p_preuve_empreinte
      AND v_q.specialite_code=p_specialite_code AND v_q.decide_par=auth.uid()
      AND v_q.motif=btrim(p_motif) AND private.fn_qualification_medicale_actuelle(v_s.id) IS NOT NULL THEN
    RETURN public.fn_admin_lire_qualification_medicale(v_s.id);
  END IF;
  IF v_q.id IS DISTINCT FROM p_decision_attendue THEN
    RAISE EXCEPTION 'Une autre décision a été prise : rechargez la revue.' USING ERRCODE='40001';
  END IF;
  IF v_d.type_document<>'CARTE_ORDRE' OR v_d.statut_verification<>'VERIFIE'
      OR v_d.verifie_le IS NULL OR v_d.coherence_nom IS NOT TRUE
      OR v_d.supprime_le IS NOT NULL OR v_d.revoque_le IS NOT NULL
      OR v_d.valide_depuis IS NULL OR v_d.valide_depuis>current_date
      OR (v_d.valide_jusqua IS NOT NULL AND v_d.valide_jusqua<=current_date)
      OR v_s.rpps_verifie IS NOT TRUE OR v_s.numero_rpps IS NULL
      OR btrim(p_numero_rpps_lu) IS DISTINCT FROM v_s.numero_rpps
      OR p_inscription_confirmee IS NOT TRUE OR p_qualification_confirmee IS NOT TRUE
      OR p_motif IS NULL OR char_length(btrim(p_motif)) NOT BETWEEN 20 AND 1000
      OR p_specialite_code IS NULL OR NOT EXISTS (SELECT 1 FROM public.specialites_medicales sm
        WHERE sm.code=p_specialite_code AND sm.code~'^SM[0-9]+$'
          AND sm.actif IS TRUE AND sm.profession_parent='MEDECIN') THEN
    RAISE EXCEPTION 'Confirmez l’attestation d’inscription actuelle, le RPPS et la qualification exacte portée par cette preuve.' USING ERRCODE='23514';
  END IF;
  UPDATE private.qualifications_medicales SET revoque_le=now(),revoque_par=auth.uid(),
    motif_revocation='Remplacée par une nouvelle revue documentée.' WHERE id=v_q.id;
  INSERT INTO private.qualifications_medicales(soignant_id,document_id,specialite_code,preuve_empreinte,decide_par,motif)
  VALUES(v_s.id,v_d.id,p_specialite_code,p_preuve_empreinte,auth.uid(),btrim(p_motif)) RETURNING id INTO v_id;
  INSERT INTO public.journaux_audit(acteur_id,type_acteur,action,type_ressource,id_ressource,details)
  VALUES(auth.uid(),'ADMIN','MODERATION_DOCUMENT','document',v_d.id,
    jsonb_build_object('decision','QUALIFICATION_APRES_INTERNAT','decision_id',v_id,'precedente',v_q.id,
      'critere','INSCRIPTION_ORDRE_QUALIFICATION_V1','specialite_code',p_specialite_code,
      'preuve_empreinte',p_preuve_empreinte,'motif',btrim(p_motif)));
  RETURN public.fn_admin_lire_qualification_medicale(v_s.id);
END;
$body$;
REVOKE ALL ON FUNCTION public.fn_admin_decider_qualification_medicale(uuid,uuid,text,uuid,text,text,boolean,boolean,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.fn_admin_decider_qualification_medicale(uuid,uuid,text,uuid,text,text,boolean,boolean,text) TO authenticated;

CREATE FUNCTION public.fn_admin_revoquer_qualification_medicale(p_soignant_id uuid,p_decision_id uuid,p_motif text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $body$
DECLARE v_q private.qualifications_medicales%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL OR public.est_admin() IS NOT TRUE THEN
    RAISE EXCEPTION 'Administrateur autorisé requis' USING ERRCODE='42501';
  END IF;
  PERFORM 1 FROM public.soignants WHERE id=p_soignant_id FOR UPDATE;
  SELECT * INTO v_q FROM private.qualifications_medicales WHERE id=p_decision_id AND soignant_id=p_soignant_id;
  IF NOT FOUND OR p_motif IS NULL OR char_length(btrim(p_motif)) NOT BETWEEN 20 AND 1000 THEN
    RAISE EXCEPTION 'Décision ou motif de révocation invalide.' USING ERRCODE='23514';
  END IF;
  IF v_q.revoque_le IS NOT NULL THEN RETURN public.fn_admin_lire_qualification_medicale(p_soignant_id); END IF;
  UPDATE private.qualifications_medicales SET revoque_le=now(),revoque_par=auth.uid(),motif_revocation=btrim(p_motif) WHERE id=v_q.id;
  INSERT INTO public.journaux_audit(acteur_id,type_acteur,action,type_ressource,id_ressource,details)
  VALUES(auth.uid(),'ADMIN','MODERATION_DOCUMENT','document',v_q.document_id,
    jsonb_build_object('decision','REVOCATION_QUALIFICATION_APRES_INTERNAT','decision_id',v_q.id,'motif',btrim(p_motif)));
  RETURN public.fn_admin_lire_qualification_medicale(p_soignant_id);
END;
$body$;
REVOKE ALL ON FUNCTION public.fn_admin_revoquer_qualification_medicale(uuid,uuid,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.fn_admin_revoquer_qualification_medicale(uuid,uuid,text) TO authenticated;

CREATE FUNCTION private.fn_statut_internat_medical(p_soignant_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path TO '' AS $body$
DECLARE
  v_s public.soignants%ROWTYPE;
  v_nb_codes integer;
  v_code text;
  v_expiration date;
  v_label text;
  v_expire boolean;
BEGIN
  SELECT * INTO v_s FROM public.soignants s
  WHERE s.id = p_soignant_id AND s.supprime_le IS NULL;
  IF NOT FOUND THEN RETURN jsonb_build_object('statut', 'A_VERIFIER'); END IF;
  IF v_s.profession::text <> 'MEDECIN'
     OR NOT (v_s.internat_medical_identifie OR v_s.est_etudiant
       OR v_s.licence_remplacement_verifiee) THEN
    RETURN jsonb_build_object('statut', 'NON_CONCERNE');
  END IF;

  IF private.fn_qualification_medicale_actuelle(p_soignant_id) IS NOT NULL THEN
    RETURN jsonb_build_object('statut','NON_CONCERNE','qualification_confirmee',true)
      || (private.fn_qualification_medicale_actuelle(p_soignant_id) - 'decision_id');
  END IF;

  SELECT count(DISTINCT sm.code), min(sm.code), max(ds.valide_jusqua)
  INTO v_nb_codes, v_code, v_expiration
  FROM public.documents_soignants ds
  JOIN public.specialites_medicales sm
    ON sm.code = ds.resultat_ia->>'licence_remplacement_specialite_code'
   AND sm.code ~ '^SM[0-9]+$'
   AND sm.actif IS TRUE AND sm.profession_parent = 'MEDECIN'
  WHERE ds.soignant_id = p_soignant_id
    AND ds.type_document::text = 'LICENCE_REMPLACEMENT'
    AND ds.statut_verification::text = 'VERIFIE'
    AND ds.supprime_le IS NULL AND ds.revoque_le IS NULL
    AND ds.verifie_le IS NOT NULL AND ds.coherence_nom IS TRUE
    AND ds.valide_depuis IS NOT NULL AND ds.valide_depuis <= current_date
    AND ds.valide_jusqua > current_date
    AND ds.valide_jusqua <= (ds.valide_depuis + interval '13 months')::date
    AND ds.resultat_ia->>'verdict_serveur' = 'VERIFIE'
    AND ds.resultat_ia->>'type_correspond' = 'true'
    AND ds.resultat_ia->>'document_lisible' = 'true'
    AND ds.resultat_ia->>'document_complet' = 'true';

  IF v_nb_codes = 1 THEN
    SELECT label INTO v_label FROM public.specialites_medicales WHERE code = v_code;
    RETURN jsonb_build_object('statut', 'VERIFIE', 'specialite_code', v_code,
      'specialite_label', v_label, 'valide_jusqua', v_expiration);
  END IF;
  -- Plusieurs codes actifs ne donnent pas plusieurs droits implicites.
  -- Une pièce rejetée/révoquée/archivée ne produit jamais un badge vérifié.
  SELECT EXISTS (SELECT 1 FROM public.documents_soignants ds
    WHERE ds.soignant_id = p_soignant_id
      AND ds.type_document::text = 'LICENCE_REMPLACEMENT'
      AND ds.statut_verification::text IN ('VERIFIE', 'EXPIRE')
      AND ds.supprime_le IS NULL AND ds.revoque_le IS NULL
      AND ds.valide_jusqua <= current_date) INTO v_expire;
  RETURN jsonb_build_object('statut', CASE
    WHEN v_nb_codes = 0 AND v_expire THEN 'EXPIRE' ELSE 'A_VERIFIER' END);
END;
$body$;
REVOKE ALL ON FUNCTION private.fn_statut_internat_medical(uuid) FROM PUBLIC, anon, authenticated;

CREATE FUNCTION private.fn_internat_compatible(
  p_preuve jsonb, p_profession public.type_profession, p_specialite text,
  p_accepte_internes boolean, p_fin timestamptz, p_accepte_non_specialises boolean
)
RETURNS boolean LANGUAGE sql IMMUTABLE SET search_path TO '' AS $body$
  SELECT COALESCE(
    (p_preuve->>'statut' = 'NON_CONCERNE' AND (
      COALESCE((p_preuve->>'qualification_confirmee')::boolean,false) IS NOT TRUE
      OR public.fn_soignant_compatible_mission('MEDECIN',p_preuve->>'specialite_code',
        p_profession,p_specialite,p_accepte_non_specialises)))
    OR (p_preuve->>'statut' = 'VERIFIE'
      AND p_profession::text = 'MEDECIN'
      AND p_accepte_internes IS TRUE
      AND NULLIF(p_specialite, '') IS NOT NULL
      AND p_preuve->>'specialite_code' = p_specialite
      AND p_fin IS NOT NULL
      AND (p_preuve->>'valide_jusqua')::date
          > (p_fin AT TIME ZONE 'Europe/Paris')::date), false);
$body$;
REVOKE ALL ON FUNCTION private.fn_internat_compatible(jsonb,public.type_profession,text,boolean,timestamptz,boolean)
FROM PUBLIC, anon, authenticated;

-- Point d'entrée commun : aucun appelant ne réinterprète est_etudiant.
-- Le chemin des médecins non concernés conserve le helper LIVE à l'identique.
CREATE FUNCTION private.fn_compatibilite_profil_mission(
  p_soignant_id uuid, p_profession public.type_profession, p_specialite text,
  p_accepte_non_specialises boolean, p_accepte_internes boolean, p_fin timestamptz
)
RETURNS boolean LANGUAGE plpgsql STABLE SET search_path TO '' AS $body$
DECLARE v_s public.soignants%ROWTYPE; v_preuve jsonb;
BEGIN
  SELECT * INTO v_s FROM public.soignants WHERE id=p_soignant_id AND supprime_le IS NULL;
  IF NOT FOUND THEN RETURN false; END IF;
  v_preuve := private.fn_statut_internat_medical(p_soignant_id);
  IF v_preuve->>'statut' = 'NON_CONCERNE' THEN
    RETURN public.fn_soignant_compatible_mission(v_s.profession,
      COALESCE(v_preuve->>'specialite_code',v_s.specialite_medicale),
      p_profession, p_specialite, p_accepte_non_specialises);
  END IF;
  RETURN private.fn_internat_compatible(v_preuve, p_profession, p_specialite,
    p_accepte_internes, p_fin, p_accepte_non_specialises);
END;
$body$;
REVOKE ALL ON FUNCTION private.fn_compatibilite_profil_mission(uuid,public.type_profession,text,boolean,boolean,timestamptz)
FROM PUBLIC, anon, authenticated;

-- Sérialisation par le profil seul : aucun verrou documentaire côté admission.
-- LIVE : chaque INSERT/UPDATE/DELETE documentaire appelle le recalcul des
-- documents valides, qui UPDATE le profil avant COMMIT. Pour une licence,
-- le recalcul étudiant verrouille aussi les anciens/nouveaux propriétaires.
-- Une mutation déjà engagée peut donc détenir son document et attendre ici ;
-- la lecture MVCC ci-dessous ne l'attend pas et termine avant son COMMIT.
-- Ajouter un verrou documentaire avant OU après ce verrou recréerait un cycle
-- avec l'identité (profil -> documents) ou la finalisation (document -> profil).
-- FOR UPDATE dès l'entrée : le score urgent LIVE prend ensuite ce même niveau.
-- SHARE permettrait deux admissions puis une conversion mutuellement bloquée.
-- NO KEY UPDATE laisserait aussi entrer un FK KEY SHARE documentaire avant
-- cette conversion en UPDATE. Le garde prend donc la force ultime dès ici.
-- Une attestation d'Ordre ne peut pas changer de propriétaire : les autres
-- mutations passent par le recalcul LIVE qui verrouille ce propriétaire.
CREATE FUNCTION private.fn_proteger_proprietaire_attestation_ordre()
RETURNS trigger LANGUAGE plpgsql SET search_path TO '' AS $body$
BEGIN
  IF NEW.soignant_id IS DISTINCT FROM OLD.soignant_id
    AND (NEW.type_document='CARTE_ORDRE' OR OLD.type_document='CARTE_ORDRE') THEN
    RAISE EXCEPTION 'Une attestation d’Ordre ne peut pas être transférée à un autre soignant.'
      USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END;
$body$;
REVOKE ALL ON FUNCTION private.fn_proteger_proprietaire_attestation_ordre() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER trg_proteger_proprietaire_attestation_ordre
BEFORE UPDATE ON public.documents_soignants
FOR EACH ROW EXECUTE FUNCTION private.fn_proteger_proprietaire_attestation_ordre();

CREATE FUNCTION private.fn_verrouiller_preuves_internat(p_soignant_id uuid)
RETURNS void LANGUAGE plpgsql VOLATILE SET search_path TO '' AS $body$
BEGIN
  PERFORM s.id FROM public.soignants s WHERE s.id=p_soignant_id FOR UPDATE;
END;
$body$;
REVOKE ALL ON FUNCTION private.fn_verrouiller_preuves_internat(uuid) FROM PUBLIC, anon, authenticated;

-- Barrière finale pour tout nouveau candidat/proposition, y compris une écriture
-- directe autorisée par les RLS existantes. Refus/annulation restent accessibles.
CREATE FUNCTION private.fn_guard_candidature_internat()
RETURNS trigger LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO '' AS $body$
DECLARE v_m public.missions%ROWTYPE; v_preuve jsonb;
BEGIN
  IF TG_OP='UPDATE' AND NOT (
      NEW.statut IN ('ACCEPTEE','EN_ATTENTE','EN_ATTENTE_VALIDATION_ETAB','PROPOSEE')
      AND (NEW.statut IS DISTINCT FROM OLD.statut
        OR NEW.soignant_id IS DISTINCT FROM OLD.soignant_id
        OR NEW.mission_id IS DISTINCT FROM OLD.mission_id)) THEN RETURN NEW; END IF;
  SELECT * INTO v_m FROM public.missions WHERE id=NEW.mission_id FOR SHARE;
  IF NOT FOUND THEN RETURN NEW; END IF; -- FK/couches existantes traitent l'absence.
  PERFORM private.fn_verrouiller_preuves_internat(NEW.soignant_id);
  -- Instruction SQL distincte APRES l'attente : le helper STABLE utilise ce
  -- nouveau snapshot, jamais celui de l'instruction qui a attendu le verrou.
  SELECT private.fn_statut_internat_medical(NEW.soignant_id) INTO v_preuve;
  IF NOT private.fn_internat_compatible(v_preuve,
    v_m.profession_requise, v_m.specialite_medicale_requise, v_m.accepte_internes, v_m.fin_le, v_m.accepte_non_specialises) THEN
    RAISE EXCEPTION 'Cette mission ne correspond pas au parcours d’internat vérifié ou au choix de l’établissement.'
      USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END;
$body$;
REVOKE ALL ON FUNCTION private.fn_guard_candidature_internat() FROM PUBLIC, anon, authenticated;
CREATE TRIGGER trg_zz_guard_candidature_internat BEFORE INSERT OR UPDATE ON public.candidatures
FOR EACH ROW EXECUTE FUNCTION private.fn_guard_candidature_internat();

CREATE FUNCTION private.fn_guard_nouvelle_attribution_internat()
RETURNS trigger LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO '' AS $body$
DECLARE v_preuve jsonb;
BEGIN
  IF NEW.soignant_assigne_id IS NULL THEN RETURN NEW; END IF;
  IF TG_OP='UPDATE' AND NEW.soignant_assigne_id IS NOT DISTINCT FROM OLD.soignant_assigne_id
    THEN RETURN NEW; END IF;
  PERFORM private.fn_verrouiller_preuves_internat(NEW.soignant_assigne_id);
  -- Même frontière de snapshot que pour la candidature, après le verrou.
  SELECT private.fn_statut_internat_medical(NEW.soignant_assigne_id) INTO v_preuve;
  IF NOT private.fn_internat_compatible(v_preuve,
    NEW.profession_requise, NEW.specialite_medicale_requise, NEW.accepte_internes, NEW.fin_le, NEW.accepte_non_specialises) THEN
    RAISE EXCEPTION 'Attribution impossible : parcours d’internat ou choix de l’établissement incompatible.'
      USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END;
$body$;
REVOKE ALL ON FUNCTION private.fn_guard_nouvelle_attribution_internat() FROM PUBLIC, anon, authenticated;
CREATE TRIGGER trg_zzz_guard_nouvelle_attribution_internat BEFORE INSERT OR UPDATE ON public.missions
FOR EACH ROW EXECUTE FUNCTION private.fn_guard_nouvelle_attribution_internat();

-- Filtre RLS borné au compte courant, sans lecture récursive de missions.
-- Les anciennes attributions restent lisibles et ne sont jamais requalifiées.
CREATE FUNCTION private.fn_mission_visible_internat(
  p_profession public.type_profession, p_specialite text, p_accepte_internes boolean,
  p_fin timestamptz, p_assigne uuid, p_statut public.statut_mission, p_etablissement_id uuid, p_accepte_non_specialises boolean
)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO '' AS $body$
BEGIN
  IF auth.uid() IS NULL THEN RETURN false; END IF;
  IF public.est_admin() IS TRUE
     OR public.fn_a_permission_etablissement('lecture_missions',p_etablissement_id) IS TRUE
     OR public.est_soignant() IS NOT TRUE OR p_assigne=auth.uid()
     OR p_statut::text <> 'OUVERTE' THEN RETURN true; END IF;
  RETURN private.fn_internat_compatible(private.fn_statut_internat_medical(auth.uid()),
    p_profession, p_specialite, p_accepte_internes, p_fin, p_accepte_non_specialises);
END;
$body$;
REVOKE ALL ON FUNCTION private.fn_mission_visible_internat(public.type_profession,text,boolean,timestamptz,uuid,public.statut_mission,uuid,boolean)
FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.fn_mission_visible_internat(public.type_profession,text,boolean,timestamptz,uuid,public.statut_mission,uuid,boolean)
TO authenticated;
CREATE POLICY missions_internat_restrictive ON public.missions AS RESTRICTIVE
FOR SELECT TO authenticated USING (private.fn_mission_visible_internat(
  profession_requise,specialite_medicale_requise,accepte_internes,fin_le,soignant_assigne_id,statut,etablissement_id,accepte_non_specialises));

GRANT EXECUTE ON FUNCTION private.fn_statut_internat_medical(uuid),
  private.fn_code_specialite_licence_exact(text),
  private.fn_internat_compatible(jsonb,public.type_profession,text,boolean,timestamptz,boolean),
  private.fn_compatibilite_profil_mission(uuid,public.type_profession,text,boolean,boolean,timestamptz)
TO service_role;


-- intention privée bornée à l'appel de publication/édition.
-- Les anciens RPC ne peuvent ni ajouter ni transférer un consentement implicite.
CREATE TABLE private.mission_internat_intent (
  backend_pid integer NOT NULL,
  transaction_id bigint NOT NULL,
  acteur_id uuid NOT NULL,
  mission_id uuid,
  accepte_internes boolean NOT NULL,
  specialite_code text,
  PRIMARY KEY (backend_pid, transaction_id)
);
ALTER TABLE private.mission_internat_intent ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE private.mission_internat_intent FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION private.fn_appliquer_choix_internat()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $body$
DECLARE v_ctx private.mission_internat_intent%ROWTYPE; v_changement boolean;
BEGIN
  SELECT * INTO v_ctx FROM private.mission_internat_intent c
  WHERE c.backend_pid=pg_backend_pid() AND c.transaction_id=txid_current()
    AND c.acteur_id=auth.uid()
    AND ((TG_OP='INSERT' AND c.mission_id IS NULL)
      OR (TG_OP='UPDATE' AND c.mission_id=NEW.id));
  IF FOUND THEN
    IF public.fn_a_permission_etablissement('missions', NEW.etablissement_id) IS NOT TRUE THEN
      RAISE EXCEPTION 'Choix d’internat : accès refusé' USING ERRCODE='42501';
    END IF;
    IF v_ctx.accepte_internes AND (NEW.profession_requise::text <> 'MEDECIN'
      OR NEW.specialite_medicale_requise IS DISTINCT FROM v_ctx.specialite_code
      OR NOT EXISTS (SELECT 1 FROM public.specialites_medicales sm
        WHERE sm.code=v_ctx.specialite_code AND sm.code ~ '^SM[0-9]+$' AND sm.actif IS TRUE AND sm.profession_parent='MEDECIN')) THEN
      RAISE EXCEPTION 'Choisissez la spécialité médicale des internes que vous acceptez.' USING ERRCODE='23514';
    END IF;
    v_changement := TG_OP='INSERT';
    IF TG_OP='UPDATE' THEN
      v_changement := OLD.accepte_internes IS DISTINCT FROM v_ctx.accepte_internes
        OR OLD.specialite_medicale_requise IS DISTINCT FROM NEW.specialite_medicale_requise
        OR OLD.profession_requise IS DISTINCT FROM NEW.profession_requise;
      IF v_changement AND (OLD.soignant_assigne_id IS NOT NULL OR OLD.statut::text <> 'OUVERTE') THEN
        RAISE EXCEPTION 'Le choix d’internat d’une mission attribuée ne peut pas être modifié.' USING ERRCODE='23514';
      END IF;
    END IF;
    NEW.accepte_internes := v_ctx.accepte_internes;
    IF v_changement THEN
      NEW.accepte_internes_confirme_par := auth.uid();
      NEW.accepte_internes_confirme_le := now();
    END IF;
  ELSIF TG_OP='INSERT' THEN
    IF NEW.accepte_internes IS TRUE THEN
      RAISE EXCEPTION 'Confirmez le choix des internes dans le formulaire de publication.' USING ERRCODE='23514';
    END IF;
    NEW.accepte_internes := false;
    NEW.accepte_internes_confirme_par := NULL;
    NEW.accepte_internes_confirme_le := NULL;
  ELSE
    IF NEW.accepte_internes IS DISTINCT FROM OLD.accepte_internes
       OR (OLD.accepte_internes AND (
         NEW.specialite_medicale_requise IS DISTINCT FROM OLD.specialite_medicale_requise
         OR NEW.profession_requise IS DISTINCT FROM OLD.profession_requise)) THEN
      RAISE EXCEPTION 'Confirmez le choix des internes dans le formulaire de modification.' USING ERRCODE='23514';
    END IF;
    NEW.accepte_internes_confirme_par := OLD.accepte_internes_confirme_par;
    NEW.accepte_internes_confirme_le := OLD.accepte_internes_confirme_le;
  END IF;
  RETURN NEW;
END;
$body$;
REVOKE ALL ON FUNCTION private.fn_appliquer_choix_internat() FROM PUBLIC, anon, authenticated;
CREATE TRIGGER trg_01_appliquer_choix_internat BEFORE INSERT OR UPDATE ON public.missions
FOR EACH ROW EXECUTE FUNCTION private.fn_appliquer_choix_internat();

CREATE FUNCTION public.fn_creer_mission_multi_jours_v4(
 p_intitule text, p_description text, p_profession_requise public.type_profession,
 p_service text, p_taux_horaire_base numeric, p_est_urgente boolean, p_niveau_urgence integer,
 p_mode_attribution text, p_specialite_medicale_requise text, p_accepte_non_specialises boolean,
 p_creneaux jsonb, p_type_contrat_recherche text, p_mode_remuneration text,
 p_retrocession_pct numeric, p_nature_tva_prestation text, p_accepte_internes boolean
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $body$
DECLARE v_resultat jsonb;
BEGIN
  IF auth.uid() IS NULL OR public.fn_compte_auth_actif() IS NOT TRUE THEN
    RAISE EXCEPTION 'Non authentifié' USING ERRCODE='28000';
  END IF;
  IF p_accepte_internes IS NULL OR (p_accepte_internes AND (
    p_profession_requise::text <> 'MEDECIN' OR NOT EXISTS (
      SELECT 1 FROM public.specialites_medicales sm
      WHERE sm.code=p_specialite_medicale_requise AND sm.code ~ '^SM[0-9]+$' AND sm.actif IS TRUE AND sm.profession_parent='MEDECIN'))) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Indiquez votre choix et la spécialité des internes acceptés.');
  END IF;
  INSERT INTO private.mission_internat_intent VALUES
    (pg_backend_pid(),txid_current(),auth.uid(),NULL,p_accepte_internes,p_specialite_medicale_requise);
  v_resultat := public.fn_creer_mission_multi_jours_v3(
    p_intitule,p_description,p_profession_requise,p_service,p_taux_horaire_base,p_est_urgente,
    p_niveau_urgence,p_mode_attribution,p_specialite_medicale_requise,p_accepte_non_specialises,
    p_creneaux,p_type_contrat_recherche,p_mode_remuneration,p_retrocession_pct,p_nature_tva_prestation);
  DELETE FROM private.mission_internat_intent
    WHERE backend_pid=pg_backend_pid() AND transaction_id=txid_current();
  RETURN v_resultat || jsonb_build_object('accepte_internes',p_accepte_internes);
END;
$body$;
REVOKE ALL ON FUNCTION public.fn_creer_mission_multi_jours_v4(text,text,public.type_profession,text,numeric,boolean,integer,text,text,boolean,jsonb,text,text,numeric,text,boolean)
FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_creer_mission_multi_jours_v4(text,text,public.type_profession,text,numeric,boolean,integer,text,text,boolean,jsonb,text,text,numeric,text,boolean)
TO authenticated;

CREATE FUNCTION public.fn_modifier_mission_etablissement_v5(
 p_mission_id uuid, p_intitule text, p_description text, p_service text,
 p_profession_requise public.type_profession, p_taux_horaire_base numeric, p_est_urgente boolean,
 p_niveau_urgence integer, p_mode_attribution text, p_type_contrat_recherche text,
 p_specialite_medicale_requise text, p_accepte_non_specialises boolean, p_creneaux jsonb,
 p_nature_tva_prestation text, p_accepte_internes boolean
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $body$
DECLARE v_resultat jsonb; v_m public.missions%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL OR public.fn_compte_auth_actif() IS NOT TRUE THEN
    RAISE EXCEPTION 'Non authentifié' USING ERRCODE='28000';
  END IF;
  SELECT * INTO v_m FROM public.missions WHERE id=p_mission_id FOR UPDATE;
  IF NOT FOUND OR public.fn_a_permission_etablissement('missions',v_m.etablissement_id) IS NOT TRUE THEN
    RETURN jsonb_build_object('success',false,'error','Mission introuvable ou accès refusé.');
  END IF;
  IF p_accepte_internes IS NULL OR (p_accepte_internes AND (
    p_profession_requise::text <> 'MEDECIN' OR NOT EXISTS (
      SELECT 1 FROM public.specialites_medicales sm
      WHERE sm.code=p_specialite_medicale_requise AND sm.code ~ '^SM[0-9]+$' AND sm.actif IS TRUE AND sm.profession_parent='MEDECIN'))) THEN
    RETURN jsonb_build_object('success',false,'error','Indiquez votre choix et la spécialité des internes acceptés.');
  END IF;
  INSERT INTO private.mission_internat_intent VALUES
    (pg_backend_pid(),txid_current(),auth.uid(),p_mission_id,p_accepte_internes,p_specialite_medicale_requise);
  v_resultat := public.fn_modifier_mission_etablissement_v4(
    p_mission_id,p_intitule,p_description,p_service,p_profession_requise,p_taux_horaire_base,
    p_est_urgente,p_niveau_urgence,p_mode_attribution,p_type_contrat_recherche,
    p_specialite_medicale_requise,p_accepte_non_specialises,p_creneaux,p_nature_tva_prestation);
  DELETE FROM private.mission_internat_intent
    WHERE backend_pid=pg_backend_pid() AND transaction_id=txid_current();
  RETURN v_resultat || jsonb_build_object('accepte_internes',p_accepte_internes);
END;
$body$;
REVOKE ALL ON FUNCTION public.fn_modifier_mission_etablissement_v5(uuid,text,text,text,public.type_profession,numeric,boolean,integer,text,text,text,boolean,jsonb,text,boolean)
FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_modifier_mission_etablissement_v5(uuid,text,text,text,public.type_profession,numeric,boolean,integer,text,text,text,boolean,jsonb,text,boolean)
TO authenticated;


-- Corps LIVE ; seules les greffes de compatibilité changent.
-- LIVE public.fn_postuler_mission: 609f31938fe027d4ee7e8c5c57796a51
CREATE OR REPLACE FUNCTION public.fn_postuler_mission(p_mission_id uuid, p_message text DEFAULT NULL::text, p_choix_contrat text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_mission record;
  v_soignant record;
  v_resolution jsonb;
  v_choix text;
  v_candidature_id uuid;
  v_notification_id uuid;
  v_docs_ok boolean;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('error', 'Non authentifié');
  END IF;

  SELECT * INTO v_mission
  FROM public.missions
  WHERE id = p_mission_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Mission introuvable');
  END IF;
  IF v_mission.statut <> 'OUVERTE' THEN
    RETURN jsonb_build_object(
      'error',
      'Cette mission n''est plus disponible'
    );
  END IF;
  IF v_mission.mode_attribution <> 'CANDIDATURE' THEN
    RETURN jsonb_build_object(
      'error',
      'Cette mission n''accepte pas les candidatures'
    );
  END IF;

  SELECT * INTO v_soignant
  FROM public.soignants
  WHERE id = auth.uid()
    AND supprime_le IS NULL;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Profil soignant introuvable');
  END IF;
  IF COALESCE(v_soignant.statut_compte::text, 'ACTIF') <> 'ACTIF' THEN
    RETURN jsonb_build_object(
      'error',
      'Votre compte ne permet pas de candidater. Contactez bonjour@jolene.app.'
    );
  END IF;

  IF NOT private.fn_comptes_meme_cohorte_test(
    auth.uid(),
    v_mission.etablissement_id
  ) THEN
    RETURN jsonb_build_object(
      'error',
      'Mission indisponible pour ce compte'
    );
  END IF;

  IF NOT private.fn_compatibilite_profil_mission(
    auth.uid(), v_mission.profession_requise, v_mission.specialite_medicale_requise,
    COALESCE(v_mission.accepte_non_specialises, true), v_mission.accepte_internes, v_mission.fin_le
  ) THEN
    RETURN jsonb_build_object(
      'error',
      'Votre profession ne correspond pas à la mission requise ('
        || v_mission.profession_requise::text
        || ').'
    );
  END IF;
  IF public.fn_est_exclu(auth.uid(), v_mission.etablissement_id) THEN
    RETURN jsonb_build_object('error', 'Accès refusé.');
  END IF;

  v_resolution := public.fn_resoudre_contrat_mission(
    p_mission_id,
    auth.uid(),
    p_choix_contrat
  );
  IF COALESCE((v_resolution->>'ok')::boolean, false) IS NOT TRUE THEN
    RETURN v_resolution - 'ok';
  END IF;
  v_choix := v_resolution->>'contrat';

  IF EXISTS (
    SELECT 1
    FROM public.candidatures
    WHERE mission_id = p_mission_id
      AND soignant_id = auth.uid()
  ) THEN
    RETURN jsonb_build_object(
      'error',
      'Vous avez déjà postulé à cette mission'
    );
  END IF;

  v_docs_ok := public.fn_documents_ok_pour_mission(
    auth.uid(),
    v_choix
  );
  IF v_choix = 'LIBERAL' AND NOT v_docs_ok THEN
    RETURN jsonb_build_object(
      'error',
        'Les documents requis pour candidater en libéral sont manquants ou expirés.',
      'documents_requis_pour', 'LIBERAL',
      'lien_documents', '/soignant/mes-documents'
    );
  END IF;

  INSERT INTO public.candidatures (
    mission_id,
    soignant_id,
    message,
    statut,
    type_contrat_choisi
  ) VALUES (
    p_mission_id,
    auth.uid(),
    public.fn_html_escape(p_message),
    'EN_ATTENTE',
    v_choix
  )
  RETURNING id INTO v_candidature_id;

  INSERT INTO public.notifications (
    destinataire_id,
    type_destinataire,
    type,
    titre,
    corps,
    lien,
    type_ressource,
    id_ressource
  ) VALUES (
    v_mission.etablissement_id,
    'ETABLISSEMENT',
    'CANDIDATURE_RECUE',
    '📋 Nouvelle candidature reçue',
    COALESCE(v_soignant.prenom, 'Un soignant')
      || ' a postulé à votre mission « '
      || public.fn_html_escape(v_mission.intitule)
      || ' ».',
    '/etablissement/missions/' || p_mission_id, 'candidature', v_candidature_id
  ) RETURNING id INTO v_notification_id;
  PERFORM private.fn_enfiler_push_candidature_recue(v_candidature_id, v_notification_id);

  IF NOT v_docs_ok THEN
    INSERT INTO public.notifications (
      destinataire_id,
      type,
      titre,
      corps,
      lien,
      type_destinataire
    )
    SELECT
      auth.uid(),
      'RAPPEL_DOCUMENTS',
      'Complétez vos documents salariés',
      'Votre candidature est envoyée. Les documents requis pour le CDD doivent être validés avant que l''établissement puisse vous accepter.',
      '/soignant/mes-documents',
      'SOIGNANT'
    WHERE NOT EXISTS (
      SELECT 1
      FROM public.notifications
      WHERE destinataire_id = auth.uid()
        AND type = 'RAPPEL_DOCUMENTS'
        AND cree_le > now() - interval '24 hours'
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'candidature_id', v_candidature_id,
    'choix_contrat', v_choix,
    'profession_requise', v_mission.profession_requise::text,
    'docs_a_completer', NOT v_docs_ok,
    'documents_requis_pour', v_choix
  );
END;
$function$;

-- LIVE public.fn_soignant_eligible_mission: f62ecb0014f1284385e57d604eeb229f
CREATE OR REPLACE FUNCTION public.fn_soignant_eligible_mission(p_soignant_id uuid, p_mission_id uuid, p_exiger_documents boolean DEFAULT false)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
DECLARE
  v_mission record;
  v_soignant record;
  v_type text;
  v_resolution jsonb;
BEGIN
  SELECT m.profession_requise, m.specialite_medicale_requise, m.accepte_internes, m.fin_le,
         COALESCE(m.accepte_non_specialises, true) AS accepte_non_specialises,
         COALESCE(m.type_contrat_recherche::text, 'SALARIE') AS type_contrat_recherche,
         m.remplacement_de_mission_id,
         COALESCE(e.est_compte_test, false) AS est_compte_test
    INTO v_mission
    FROM public.missions m
    JOIN public.etablissements e ON e.id = m.etablissement_id
   WHERE m.id = p_mission_id AND m.statut = 'OUVERTE';
  IF NOT FOUND THEN RETURN false; END IF;

  SELECT profession, specialite_medicale,
         COALESCE(type_exercice, 'SALARIE') AS type_exercice,
         COALESCE(est_compte_test, false) AS est_compte_test
    INTO v_soignant
    FROM public.soignants
   WHERE id = p_soignant_id
     AND supprime_le IS NULL
     AND COALESCE(statut_compte::text, 'ACTIF') = 'ACTIF';
  IF NOT FOUND THEN RETURN false; END IF;

  IF v_soignant.est_compte_test IS DISTINCT FROM v_mission.est_compte_test THEN
    RETURN false;
  END IF;

  -- Aucun assigné remplacé, ni auteur d'une attestation EPI, ne peut revenir
  -- par un descendant de la chaîne. L'ascendance récursive couvre aussi
  -- EPI(A) -> remplacement B -> no-show(B) -> remplacement C.
  IF v_mission.remplacement_de_mission_id IS NOT NULL
     AND EXISTS (
       WITH RECURSIVE ascendance AS (
         SELECT m.id, m.soignant_assigne_id, m.remplacement_de_mission_id
         FROM public.missions m
         WHERE m.id = v_mission.remplacement_de_mission_id
         UNION
         SELECT parent.id, parent.soignant_assigne_id,
                parent.remplacement_de_mission_id
         FROM public.missions parent
         JOIN ascendance enfant
           ON parent.id = enfant.remplacement_de_mission_id
       )
       SELECT 1
       FROM ascendance a
       WHERE a.soignant_assigne_id = p_soignant_id
          OR EXISTS (
            SELECT 1
            FROM public.journaux_audit ja
            WHERE ja.acteur_id = p_soignant_id
              AND ja.action = 'ANNULATION_EMPECHEMENT_IMPERIEUX'
              AND ja.type_ressource = 'mission'
              AND ja.id_ressource = a.id
          )
     ) THEN
    RETURN false;
  END IF;

  IF NOT private.fn_compatibilite_profil_mission(
    p_soignant_id, v_mission.profession_requise, v_mission.specialite_medicale_requise,
    COALESCE(v_mission.accepte_non_specialises, true), v_mission.accepte_internes, v_mission.fin_le
  ) THEN
    RETURN false;
  END IF;

  v_resolution := public.fn_resoudre_contrat_mission(
    p_mission_id, p_soignant_id, NULL
  );
  IF COALESCE((v_resolution->>'ok')::boolean, false) IS NOT TRUE
     AND COALESCE((v_resolution->>'choix_requis')::boolean, false) IS NOT TRUE THEN
    RETURN false;
  END IF;
  IF NOT p_exiger_documents THEN RETURN true; END IF;

  IF COALESCE((v_resolution->>'choix_requis')::boolean, false) THEN
    RETURN public.fn_documents_ok_pour_mission(p_soignant_id, 'SALARIE')
      OR (v_soignant.type_exercice IN ('LIBERAL', 'MIXTE')
          AND public.fn_documents_ok_pour_mission(p_soignant_id, 'LIBERAL'));
  END IF;
  v_type := v_resolution->>'contrat';
  IF v_type = 'LIBERAL' THEN
    RETURN public.fn_documents_ok_pour_mission(p_soignant_id, 'LIBERAL');
  END IF;
  RETURN public.fn_documents_ok_pour_mission(p_soignant_id, 'SALARIE');
END;
$function$;

-- LIVE public.fn_accepter_mission_urgence: bcecb0ef55ee1ee1d54b9a7f7e622645
CREATE OR REPLACE FUNCTION public.fn_accepter_mission_urgence(p_mission_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_mission record;
  v_soignant record;
  v_resolution jsonb;
  v_candidature_id uuid;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'Non authentifié'); END IF;
  SELECT * INTO v_soignant FROM public.soignants WHERE id = v_uid AND supprime_le IS NULL;
  IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'error', 'Profil soignant introuvable'); END IF;
  SELECT * INTO v_mission FROM public.missions WHERE id = p_mission_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'error', 'Mission introuvable'); END IF;
  IF v_mission.statut <> 'OUVERTE' OR NOT COALESCE(v_mission.est_urgente, false) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Mission urgente non disponible');
  END IF;
  IF NOT private.fn_compatibilite_profil_mission(
    v_uid, v_mission.profession_requise, v_mission.specialite_medicale_requise,
    COALESCE(v_mission.accepte_non_specialises, true), v_mission.accepte_internes, v_mission.fin_le
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Profession ou spécialité incompatible');
  END IF;
  IF public.fn_est_exclu(v_uid, v_mission.etablissement_id) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Accès refusé');
  END IF;

  v_resolution := public.fn_resoudre_contrat_mission(p_mission_id, v_uid, NULL);
  IF COALESCE((v_resolution->>'ok')::boolean, false) IS NOT TRUE THEN
    RETURN jsonb_build_object('success', false) || (v_resolution - 'ok');
  END IF;
  IF NOT public.fn_documents_ok_pour_mission(v_uid, v_resolution->>'contrat') THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Vos documents ne sont pas validés pour cette mission ' || lower(v_resolution->>'contrat'),
      'documents_requis_pour', v_resolution->>'contrat'
    );
  END IF;
  IF EXISTS (SELECT 1 FROM public.candidatures WHERE mission_id = p_mission_id AND soignant_id = v_uid) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Vous avez déjà candidaté à cette mission');
  END IF;

  INSERT INTO public.candidatures(
    mission_id, soignant_id, statut, message, type_contrat_choisi, cree_le
  ) VALUES (
    p_mission_id, v_uid, 'EN_ATTENTE_VALIDATION_ETAB',
    'Acceptation rapide via pool urgence', v_resolution->>'contrat', now()
  ) RETURNING id INTO v_candidature_id;

  INSERT INTO public.notifications(destinataire_id, type_destinataire, type, titre, corps, lien, type_ressource, id_ressource)
  VALUES (
    v_mission.etablissement_id, 'ETABLISSEMENT', 'POOL_URGENCE_ACCEPTATION',
    '🚨 Acceptation rapide du pool urgence',
    COALESCE(v_soignant.prenom, 'Un soignant') || ' (' || v_soignant.profession::text ||
      ') a accepté votre mission urgente. Validez ou refusez sous 1 h.',
    '/etablissement/missions/' || p_mission_id, 'candidature', v_candidature_id
  );

  RETURN jsonb_build_object(
    'success', true,
    'candidature_id', v_candidature_id,
    'choix_contrat', v_resolution->>'contrat',
    'profession_requise', v_mission.profession_requise::text,
    'message', 'Acceptation enregistrée. En attente de validation par l''établissement.'
  );
END;
$function$;

-- LIVE public.fn_enregistrer_swipe: a9bcaf6626e8f8c143f41b89af6fcbe2
CREATE OR REPLACE FUNCTION public.fn_enregistrer_swipe(p_mission_id uuid, p_direction text, p_choix_contrat text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_direction public.swipe_direction;
  v_mission record;
  v_soignant record;
  v_resolution jsonb;
  v_choix text;
  v_swipe_id uuid;
  v_candidature_id uuid;
  v_notification_id uuid;
  v_planning jsonb;
  v_warning text;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'auth_required'); END IF;
  IF p_direction = 'SUPER_LIKE' THEN p_direction := 'FAVORI'; END IF;
  IF p_direction NOT IN ('LIKE', 'DISLIKE', 'FAVORI') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'direction_invalide');
  END IF;
  v_direction := p_direction::public.swipe_direction;

  SELECT * INTO v_mission FROM public.missions WHERE id = p_mission_id;
  IF NOT FOUND OR v_mission.statut <> 'OUVERTE' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'mission_indisponible');
  END IF;
  SELECT * INTO v_soignant FROM public.soignants WHERE id = v_uid AND supprime_le IS NULL;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'error', 'profil_introuvable'); END IF;
  IF NOT private.fn_compatibilite_profil_mission(
    v_uid, v_mission.profession_requise, v_mission.specialite_medicale_requise,
    COALESCE(v_mission.accepte_non_specialises, true), v_mission.accepte_internes, v_mission.fin_le
  ) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'profession_incompatible');
  END IF;
  IF public.fn_est_exclu(v_uid, v_mission.etablissement_id) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'acces_refuse');
  END IF;

  IF v_direction = 'LIKE' THEN
    IF EXISTS (SELECT 1 FROM public.candidatures WHERE mission_id = p_mission_id AND soignant_id = v_uid) THEN
      RETURN jsonb_build_object('ok', false, 'error', 'Vous avez déjà candidaté à cette mission');
    END IF;
    v_planning := public.fn_conflit_planning_soignant(v_uid, p_mission_id);
    IF COALESCE((v_planning->>'conflit')::boolean, false) THEN
      RETURN jsonb_build_object('ok', false, 'error', v_planning->>'message', 'conflit_planning', true);
    END IF;
    v_warning := v_planning->>'warning';

    v_resolution := public.fn_resoudre_contrat_mission(p_mission_id, v_uid, p_choix_contrat);
    IF COALESCE((v_resolution->>'ok')::boolean, false) IS NOT TRUE THEN
      RETURN jsonb_build_object('ok', false) || (v_resolution - 'ok');
    END IF;
    v_choix := v_resolution->>'contrat';
    IF v_choix = 'LIBERAL' AND NOT public.fn_documents_ok_pour_mission(v_uid, 'LIBERAL') THEN
      RETURN jsonb_build_object(
        'ok', false,
        'error', 'Les documents requis pour candidater en libéral sont manquants ou expirés.',
        'documents_requis_pour', 'LIBERAL'
      );
    END IF;
  END IF;

  INSERT INTO public.swipes(soignant_id, mission_id, direction)
  VALUES (v_uid, p_mission_id, v_direction)
  ON CONFLICT (soignant_id, mission_id) DO NOTHING
  RETURNING id INTO v_swipe_id;
  IF v_swipe_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'mission_deja_swipee');
  END IF;

  IF v_direction = 'FAVORI' THEN
    INSERT INTO public.missions_sauvegardees(soignant_id, mission_id)
    VALUES (v_uid, p_mission_id)
    ON CONFLICT (soignant_id, mission_id) DO NOTHING;
    RETURN jsonb_build_object('ok', true, 'swipe_id', v_swipe_id, 'direction', 'FAVORI', 'sauvegardee', true);
  ELSIF v_direction = 'LIKE' THEN
    INSERT INTO public.candidatures(mission_id, soignant_id, message, statut, type_contrat_choisi)
    VALUES (p_mission_id, v_uid, NULL, 'EN_ATTENTE', v_choix)
    RETURNING id INTO v_candidature_id;
    INSERT INTO public.notifications(destinataire_id, type_destinataire, type, titre, corps, lien, type_ressource, id_ressource)
    VALUES (
      v_mission.etablissement_id, 'ETABLISSEMENT', 'CANDIDATURE_RECUE',
      '📋 Nouvelle candidature reçue',
      COALESCE(v_soignant.prenom, 'Un soignant') || ' a postulé à votre mission « ' ||
        public.fn_html_escape(v_mission.intitule) || ' ».',
      '/etablissement/missions/' || p_mission_id, 'candidature', v_candidature_id
  ) RETURNING id INTO v_notification_id;
  PERFORM private.fn_enfiler_push_candidature_recue(v_candidature_id, v_notification_id);
  END IF;

  RETURN jsonb_build_object(
    'ok', true, 'swipe_id', v_swipe_id, 'direction', p_direction,
    'candidature_id', v_candidature_id, 'choix_contrat', v_choix,
    'profession_requise', v_mission.profession_requise::text,
    'docs_a_completer', v_direction = 'LIKE' AND NOT public.fn_documents_ok_pour_mission(v_uid, v_choix),
    'warning', v_warning
  );
END;
$function$;

-- LIVE public.fn_finaliser_attribution_mission: 15b78cd8f72f811becb878b3ed1bc8fe
CREATE OR REPLACE FUNCTION public.fn_finaliser_attribution_mission(p_mission_id uuid, p_soignant_id uuid, p_choix_contrat text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_mission record;
  v_soignant record;
  v_etab record;
  v_resolution jsonb;
  v_choix text;
  v_semaine record;
  v_heures_existantes numeric;
  v_heures_externes numeric;
  v_heures_total numeric;
  v_nb_creneaux_valides integer;
  v_type_contrat text;
  v_type_paiement text;
  v_mode_paiement text;
  v_numero text;
  v_html text;
  v_contrat_id uuid;
  v_rows integer;
BEGIN
  SELECT * INTO v_mission FROM public.missions WHERE id = p_mission_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Mission introuvable'); END IF;
  IF v_mission.statut <> 'OUVERTE' THEN
    RETURN jsonb_build_object('error', 'Cette mission n''est plus disponible');
  END IF;

  SELECT * INTO v_soignant FROM public.soignants
   WHERE id = p_soignant_id AND supprime_le IS NULL;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Profil soignant introuvable'); END IF;

  IF NOT private.fn_compatibilite_profil_mission(
    p_soignant_id, v_mission.profession_requise, v_mission.specialite_medicale_requise,
    COALESCE(v_mission.accepte_non_specialises, true), v_mission.accepte_internes, v_mission.fin_le
  ) THEN
    RETURN jsonb_build_object(
      'error', 'Ce soignant (' || v_soignant.profession::text ||
        ') n''est pas compatible avec la profession requise par la mission (' ||
        v_mission.profession_requise::text || ').'
    );
  END IF;

  IF public.fn_est_exclu(p_soignant_id, v_mission.etablissement_id) THEN
    RETURN jsonb_build_object('error', 'Accès refusé pour cette mission.');
  END IF;

  v_resolution := public.fn_resoudre_contrat_mission(p_mission_id, p_soignant_id, p_choix_contrat);
  IF COALESCE((v_resolution->>'ok')::boolean, false) IS NOT TRUE THEN
    RETURN v_resolution - 'ok';
  END IF;
  v_choix := v_resolution->>'contrat';

  IF NOT public.fn_documents_ok_pour_mission(p_soignant_id, v_choix) THEN
    RETURN jsonb_build_object(
      'error', 'Les documents requis pour une mission ' || lower(v_choix) ||
        ' ne sont pas encore validés.',
      'documents_requis_pour', v_choix,
      'lien_documents', '/soignant/mes-documents'
    );
  END IF;

  -- Sérialise toutes les attributions visant un même soignant dans la
  -- transaction courante. Deux missions acceptées en parallèle ne peuvent
  -- ainsi plus vérifier chacune un planning encore vide puis dépasser 48 h.
  PERFORM pg_advisory_xact_lock(
    hashtextextended('jolene:attribution:' || p_soignant_id::text, 0)
  );

  IF v_choix = 'SALARIE' THEN
    IF COALESCE(v_mission.nb_creneaux, 0) > 1 THEN
      SELECT count(*)::integer INTO v_nb_creneaux_valides
        FROM public.mission_creneaux mc
       WHERE mc.mission_id = p_mission_id
         AND mc.fin IS NOT NULL
         AND mc.type_creneau = CASE
           WHEN EXISTS (
             SELECT 1 FROM public.mission_creneaux p
              WHERE p.mission_id = p_mission_id AND p.type_creneau = 'PREVISIONNEL'
                AND p.fin IS NOT NULL AND NOT p.est_pause
           ) THEN 'PREVISIONNEL'
           ELSE 'EFFECTIF'
         END;
      IF v_nb_creneaux_valides < v_mission.nb_creneaux THEN
        RETURN jsonb_build_object(
          'error', 'Planning hebdomadaire incomplet : impossible de vérifier le plafond de 48 h.',
          'code', 'PLANNING_HEBDOMADAIRE_INDISPONIBLE',
          'creneaux_valides', v_nb_creneaux_valides,
          'creneaux_attendus', v_mission.nb_creneaux
        );
      END IF;
    END IF;

    FOR v_semaine IN
      SELECT * FROM public.fn_semaines_mission(p_mission_id)
    LOOP
      v_heures_existantes := public.fn_heures_soignant_semaine(
        p_soignant_id, v_semaine.semaine_debut, p_mission_id
      );
      SELECT COALESCE(heures_salarie, 0)
        INTO v_heures_externes
        FROM public.attestations_heures_externes
       WHERE soignant_id = p_soignant_id
         AND semaine_du = v_semaine.semaine_debut;
      IF NOT FOUND THEN v_heures_externes := 0; END IF;
      v_heures_total := v_heures_existantes + v_heures_externes + v_semaine.heures;

      IF v_heures_total > 48 THEN
        RETURN jsonb_build_object(
          'error', 'Dépassement du plafond de 48 h pour la semaine du ' ||
            to_char(v_semaine.semaine_debut, 'DD/MM/YYYY') || ' (' ||
            round(v_heures_existantes, 1) || ' h déjà planifiées + ' ||
            round(v_semaine.heures, 1) || ' h pour cette mission + ' ||
            round(v_heures_externes, 1) || ' h ailleurs).',
          'code', 'PLAFOND_48H_HEBDO',
          'semaine_du', v_semaine.semaine_debut,
          'heures_existantes', round(v_heures_existantes, 2),
          'heures_mission', round(v_semaine.heures, 2),
          'heures_externes', round(v_heures_externes, 2),
          'total', round(v_heures_total, 2)
        );
      END IF;
    END LOOP;
  END IF;

  IF v_choix = 'LIBERAL' THEN
    v_type_contrat := 'REMPLACEMENT_LIBERAL';
    v_type_paiement := 'NOTE_HONORAIRES';
    v_mode_paiement := 'STRIPE_CONNECT';
  ELSE
    v_type_contrat := 'CDD';
    v_type_paiement := 'BULLETIN_PAIE';
    v_mode_paiement := 'DIRECT';
  END IF;

  PERFORM set_config('jolene.assignment_rpc_soignant_id', p_soignant_id::text, true);
  UPDATE public.missions
     SET soignant_assigne_id = p_soignant_id,
         statut = 'ASSIGNEE',
         type_contrat_applique = v_choix::public.type_contrat_applique_enum,
         choix_contrat_soignant = v_choix,
         type_paiement_soignant = v_type_paiement,
         mode_paiement_soignant = v_mode_paiement,
         modifie_le = now()
   WHERE id = p_mission_id AND statut = 'OUVERTE';
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows = 0 THEN
    RETURN jsonb_build_object('error', 'Cette mission vient d''être attribuée.');
  END IF;

  SELECT * INTO v_etab FROM public.etablissements WHERE id = v_mission.etablissement_id;
  v_numero := public.fn_generer_numero_contrat_safe(v_type_contrat);
  SELECT contenu_html INTO v_html
    FROM public.templates_contrat
   WHERE type_contrat = v_type_contrat AND est_actif = true
   LIMIT 1;

  IF v_html IS NOT NULL THEN
    v_html := replace(v_html, '{{etablissement_nom}}', public.fn_html_escape(COALESCE(v_etab.nom, '')));
    v_html := replace(v_html, '{{etablissement_siret}}', public.fn_html_escape(COALESCE(v_etab.siret, '')));
    v_html := replace(v_html, '{{etablissement_finess}}', public.fn_html_escape(COALESCE(v_etab.finess, 'N/A')));
    v_html := replace(v_html, '{{etablissement_adresse}}', public.fn_html_escape(COALESCE(v_etab.adresse_rue || ', ' || v_etab.adresse_code_postal || ' ' || v_etab.adresse_ville, '')));
    v_html := replace(v_html, '{{soignant_prenom}}', public.fn_html_escape(COALESCE(v_soignant.prenom, '')));
    v_html := replace(v_html, '{{soignant_nom}}', public.fn_html_escape(COALESCE(v_soignant.nom, '')));
    v_html := replace(v_html, '{{soignant_rpps}}', public.fn_html_escape(COALESCE(v_soignant.numero_rpps, '')));
    v_html := replace(v_html, '{{soignant_siret}}', public.fn_html_escape(COALESCE(v_soignant.siret_liberal, '')));
    v_html := replace(v_html, '{{profession}}', public.fn_html_escape(v_mission.profession_requise::text));
    v_html := replace(v_html, '{{service}}', public.fn_html_escape(COALESCE(v_mission.service, '')));
    v_html := replace(v_html, '{{debut_date}}', to_char(v_mission.debut_le AT TIME ZONE 'Europe/Paris', 'DD/MM/YYYY'));
    v_html := replace(v_html, '{{debut_heure}}', to_char(v_mission.debut_le AT TIME ZONE 'Europe/Paris', 'HH24:MI'));
    v_html := replace(v_html, '{{fin_date}}', to_char(v_mission.fin_le AT TIME ZONE 'Europe/Paris', 'DD/MM/YYYY'));
    v_html := replace(v_html, '{{fin_heure}}', to_char(v_mission.fin_le AT TIME ZONE 'Europe/Paris', 'HH24:MI'));
    v_html := replace(v_html, '{{duree_heures}}', COALESCE(v_mission.duree_heures::text, ''));
    v_html := replace(v_html, '{{taux_horaire}}', COALESCE(v_mission.taux_horaire_base::text, ''));
    v_html := replace(v_html, '{{retrocession_pct}}', COALESCE(v_mission.retrocession_pct::text, ''));
    v_html := replace(v_html, '{{numero_contrat}}', public.fn_html_escape(v_numero));
    v_html := replace(v_html, '{{date_signature}}', to_char(now() AT TIME ZONE 'Europe/Paris', 'DD/MM/YYYY'));
    v_html := replace(v_html, '{{lieu}}', public.fn_html_escape(COALESCE(v_etab.adresse_ville, '')));
  END IF;

  SELECT id INTO v_contrat_id
    FROM public.contrats_mission
   WHERE mission_id = p_mission_id
     AND soignant_id = p_soignant_id
     AND statut <> 'ANNULE'
   ORDER BY cree_le DESC
   LIMIT 1;

  IF v_contrat_id IS NULL THEN
    INSERT INTO public.contrats_mission(
      mission_id, etablissement_id, soignant_id,
      type_contrat, numero_contrat, contenu_html, statut
    ) VALUES (
      p_mission_id, v_mission.etablissement_id, p_soignant_id,
      v_type_contrat, v_numero, v_html, 'EN_ATTENTE_SIGNATURES'
    ) RETURNING id INTO v_contrat_id;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'contrat_id', v_contrat_id,
    'contrat_numero', v_numero,
    'choix_applique', v_choix,
    'profession_requise', v_mission.profession_requise::text,
    'type_paiement', v_type_paiement,
    'mode_paiement', v_mode_paiement
  );
END;
$function$;

-- LIVE public.fn_proposer_mission_soignant: c42bec9be211f8a5d030886d03fb45bc
CREATE OR REPLACE FUNCTION public.fn_proposer_mission_soignant(p_mission_id uuid, p_soignant_id uuid, p_choix_contrat text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_mission record;
  v_soignant record;
  v_resolution jsonb;
  v_choix text;
  v_candidature_id uuid;
  v_candidature_statut text;
BEGIN
  SELECT * INTO v_mission FROM public.missions WHERE id = p_mission_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Mission introuvable'); END IF;
  IF NOT public.est_admin()
     AND v_mission.etablissement_id IS DISTINCT FROM public.mon_etablissement_id() THEN
    RETURN jsonb_build_object('error', 'Accès refusé');
  END IF;
  IF v_mission.statut <> 'OUVERTE' THEN
    RETURN jsonb_build_object('error', 'La mission n’est plus ouverte');
  END IF;

  SELECT * INTO v_soignant
    FROM public.soignants
   WHERE id = p_soignant_id AND supprime_le IS NULL;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Soignant introuvable'); END IF;
  IF NOT private.fn_compatibilite_profil_mission(
    p_soignant_id, v_mission.profession_requise, v_mission.specialite_medicale_requise,
    COALESCE(v_mission.accepte_non_specialises, true), v_mission.accepte_internes, v_mission.fin_le
  ) THEN
    RETURN jsonb_build_object(
      'error', 'Ce soignant n’est pas compatible avec la profession requise par la mission (' ||
        v_mission.profession_requise::text || ').'
    );
  END IF;
  IF public.fn_est_exclu(p_soignant_id, v_mission.etablissement_id) THEN
    RETURN jsonb_build_object('error', 'Ce soignant est dans votre liste d’exclusions.');
  END IF;

  v_resolution := public.fn_resoudre_contrat_mission(
    p_mission_id, p_soignant_id, p_choix_contrat
  );
  IF COALESCE((v_resolution->>'ok')::boolean, false) IS NOT TRUE THEN
    RETURN v_resolution - 'ok';
  END IF;
  v_choix := v_resolution->>'contrat';
  IF NOT public.fn_documents_ok_pour_mission(p_soignant_id, v_choix) THEN
    RETURN jsonb_build_object(
      'error', 'Ce soignant n’a pas encore les documents validés pour une mission ' || lower(v_choix) || '.',
      'documents_requis_pour', v_choix
    );
  END IF;

  UPDATE public.candidatures
     SET statut = 'EXPIREE', traite_le = now()
   WHERE mission_id = p_mission_id
     AND soignant_id = p_soignant_id
     AND statut = 'PROPOSEE'
     AND cree_le < now() - interval '2 hours';

  SELECT id, statut
    INTO v_candidature_id, v_candidature_statut
    FROM public.candidatures
   WHERE mission_id = p_mission_id
     AND soignant_id = p_soignant_id
   FOR UPDATE;

  IF FOUND AND v_candidature_statut IN ('EN_ATTENTE', 'EN_ATTENTE_VALIDATION_ETAB', 'PROPOSEE', 'ACCEPTEE') THEN
    RETURN jsonb_build_object('error', 'Cette mission a déjà été proposée à ce soignant.');
  END IF;

  IF v_candidature_id IS NULL THEN
    INSERT INTO public.candidatures(
      mission_id, soignant_id, statut, type_contrat_choisi
    ) VALUES (
      p_mission_id, p_soignant_id, 'PROPOSEE', v_choix
    ) RETURNING id INTO v_candidature_id;
  ELSE
    PERFORM set_config(
      'jolene.candidature_reactivation_ctx',
      p_mission_id::text || ':' || p_soignant_id::text,
      true
    );
    UPDATE public.candidatures
       SET statut = 'PROPOSEE',
           type_contrat_choisi = v_choix,
           traite_le = NULL,
           motif_refus = NULL,
           cree_le = now()
     WHERE id = v_candidature_id;
    PERFORM set_config('jolene.candidature_reactivation_ctx', '', true);
  END IF;

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := auth.uid(),
    p_type_acteur := CASE WHEN public.est_admin() THEN 'ADMIN' ELSE 'ADMIN_ETABLISSEMENT' END,
    p_action := 'MISSION_PROPOSEE_SOIGNANT',
    p_type_ressource := 'candidature',
    p_id_ressource := v_candidature_id,
    p_details := jsonb_build_object(
      'mission_id', p_mission_id,
      'soignant_id', p_soignant_id,
      'profession_requise', v_mission.profession_requise::text,
      'type_contrat_choisi', v_choix,
      'reactivation', v_candidature_statut IS NOT NULL
    )
  );

  INSERT INTO public.notifications(destinataire_id, type, titre, corps, lien, type_destinataire)
  VALUES (
    p_soignant_id, 'CANDIDATURE_PROPOSEE', 'Mission proposée',
    'Un établissement vous propose la mission « ' || public.fn_html_escape(v_mission.intitule) ||
      ' » en ' || lower(v_choix) || '.',
    '/soignant/missions/' || p_mission_id, 'SOIGNANT'
  );

  RETURN jsonb_build_object(
    'success', true,
    'candidature_id', v_candidature_id,
    'choix_persiste', v_choix,
    'profession_requise', v_mission.profession_requise::text,
    'reactivation', v_candidature_statut IS NOT NULL
  );
END;
$function$;

-- LIVE public.fn_rebooker_soignant: aa2b77dc5bcfe0ed536902dd0ac47f54
CREATE OR REPLACE FUNCTION public.fn_rebooker_soignant(p_soignant_id uuid, p_mission_modele_id uuid, p_debut timestamp with time zone, p_fin timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_m record;
  v_s record;
  v_new_id uuid;
  v_resolution jsonb;
BEGIN
  SELECT * INTO v_m FROM public.missions WHERE id = p_mission_modele_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Mission modèle introuvable'); END IF;
  IF v_m.etablissement_id <> public.mon_etablissement_id() AND NOT public.est_admin() THEN
    RETURN jsonb_build_object('error', 'Non autorisé');
  END IF;
  IF p_debut IS NULL OR p_fin IS NULL OR p_fin <= p_debut OR p_debut < now() THEN
    RETURN jsonb_build_object('error', 'Dates invalides (le début doit être dans le futur).');
  END IF;
  SELECT * INTO v_s FROM public.soignants WHERE id = p_soignant_id AND supprime_le IS NULL;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Soignant introuvable'); END IF;
  IF NOT private.fn_compatibilite_profil_mission(
    p_soignant_id, v_m.profession_requise, v_m.specialite_medicale_requise,
    COALESCE(v_m.accepte_non_specialises, true), false, p_fin
  ) THEN
    RETURN jsonb_build_object('error', 'Le soignant n’est pas compatible avec la profession requise par la mission modèle.');
  END IF;
  IF public.fn_est_exclu(p_soignant_id, v_m.etablissement_id) THEN
    RETURN jsonb_build_object('error', 'Ce soignant est dans votre liste d’exclusions.');
  END IF;
  v_resolution := public.fn_resoudre_contrat_mission(
    p_mission_modele_id, p_soignant_id, NULL
  );
  IF COALESCE((v_resolution->>'ok')::boolean, false) IS NOT TRUE
     AND COALESCE((v_resolution->>'choix_requis')::boolean, false) IS NOT TRUE THEN
    RETURN v_resolution - 'ok';
  END IF;

  INSERT INTO public.missions(
    etablissement_id, intitule, description, service,
    profession_requise, specialite_medicale_requise, accepte_non_specialises,
    debut_le, fin_le, duree_heures, taux_horaire_base,
    type_contrat_recherche, statut, mode_attribution, est_urgente,
    garantie_remplacement, mission_source
  ) VALUES (
    v_m.etablissement_id, v_m.intitule, v_m.description, v_m.service,
    v_m.profession_requise, v_m.specialite_medicale_requise, v_m.accepte_non_specialises,
    p_debut, p_fin, round(extract(epoch FROM (p_fin - p_debut)) / 3600.0, 2),
    v_m.taux_horaire_base, v_m.type_contrat_recherche, 'OUVERTE', 'CANDIDATURE',
    false, COALESCE(v_m.garantie_remplacement, false), 'REBOOK'
  ) RETURNING id INTO v_new_id;

  INSERT INTO public.notifications(destinataire_id, type, titre, corps, lien, type_destinataire)
  VALUES (
    p_soignant_id, 'CANDIDATURE_PROPOSEE', 'Un établissement veut retravailler avec vous ⭐',
    public.fn_html_escape(v_m.intitule) || ' du ' ||
      to_char(p_debut AT TIME ZONE 'Europe/Paris', 'DD/MM à HH24:MI') || ' au ' ||
      to_char(p_fin AT TIME ZONE 'Europe/Paris', 'DD/MM à HH24:MI') || ' à ' ||
      COALESCE(v_m.taux_horaire_base::text, '?') || ' €/h — vous êtes leur premier choix, postulez en 1 clic.',
    '/soignant/missions/' || v_new_id, 'SOIGNANT'
  );
  RETURN jsonb_build_object('success', true, 'mission_id', v_new_id);
END;
$function$;

-- LIVE private.fn_soignant_visible_pool_etablissement: 5e012124b21477facd88b36ee2099afd
CREATE OR REPLACE FUNCTION private.fn_soignant_visible_pool_etablissement(p_etablissement_user_id uuid, p_soignant_id uuid, p_etablissement_id uuid)
 RETURNS boolean
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT COALESCE(EXISTS (
    SELECT 1
    FROM public.etablissements e
    JOIN public.soignants s ON s.id = p_soignant_id
    WHERE e.id = p_etablissement_id
      AND e.supprime_le IS NULL
      AND private.fn_interlocuteur_operationnel_actif(
        p_etablissement_user_id,
        e.id
      )
      AND private.fn_soignant_messagerie_actif(s.id)
      AND COALESCE(s.disponible_urgence, false) IS TRUE
      AND public.fn_documents_ok_pour_mission(s.id, 'TOUS')
      AND NOT public.fn_est_exclu(s.id, e.id)
      AND (
        EXISTS (
          SELECT 1
          FROM public.missions mi
          WHERE mi.etablissement_id = e.id
            AND mi.statut IN (
              'OUVERTE', 'ASSIGNEE', 'EN_COURS', 'ABSENCE', 'LITIGE'
            )
            AND private.fn_compatibilite_profil_mission(
    s.id, mi.profession_requise, mi.specialite_medicale_requise,
    COALESCE(mi.accepte_non_specialises, true), mi.accepte_internes, mi.fin_le
  )
        )
        OR (private.fn_statut_internat_medical(s.id)->>'statut' = 'NON_CONCERNE' AND NOT EXISTS (
          SELECT 1
          FROM public.missions mi
          WHERE mi.etablissement_id = e.id
            AND mi.statut IN (
              'OUVERTE', 'ASSIGNEE', 'EN_COURS', 'ABSENCE', 'LITIGE'
            )
        ))
      )
  ), false);
$function$;

-- LIVE public.fn_pool_urgence_etablissement: 942b532b9a1f84cfdb5123264dcd77de
CREATE OR REPLACE FUNCTION public.fn_pool_urgence_etablissement(p_etablissement_id uuid)
 RETURNS TABLE(soignant_id uuid, prenom text, nom text, profession text, score_fiabilite integer, pool_urgence_rayon_km integer, distance_km numeric, missions_urgence_terminees bigint, en_mission_maintenant boolean, derniere_mission_chez_nous timestamp with time zone, bio text, avatar_url text, est_favori boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_etab public.etablissements%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL OR public.fn_compte_auth_actif() IS NOT TRUE THEN
    RAISE EXCEPTION 'Non authentifié' USING ERRCODE = '28000';
  END IF;
  IF public.fn_a_permission_etablissement(
       'candidatures', p_etablissement_id
     ) IS NOT TRUE THEN
    RAISE EXCEPTION
      'Accès refusé : pool urgence réservé aux responsables de l’établissement'
      USING ERRCODE = '42501';
  END IF;

  SELECT e.* INTO v_etab
  FROM public.etablissements e
  WHERE e.id = p_etablissement_id
    AND e.supprime_le IS NULL;
  IF NOT FOUND THEN RETURN; END IF;

  RETURN QUERY
  SELECT
    s.id,
    s.prenom::text,
    s.nom::text,
    s.profession::text,
    CASE
      WHEN COALESCE(s.total_missions_terminees, 0) >= 3
      THEN s.score_fiabilite::integer
      ELSE NULL
    END,
    COALESCE(s.urgence_rayon_km, 15)::integer,
    CASE
      WHEN s.adresse_lat IS NOT NULL
       AND s.adresse_lng IS NOT NULL
       AND v_etab.adresse_lat IS NOT NULL
       AND v_etab.adresse_lng IS NOT NULL THEN
        pg_catalog.round((
          6371 * pg_catalog.acos(least(
            1.0::double precision,
            greatest(
              (-1.0)::double precision,
              pg_catalog.cos(pg_catalog.radians(v_etab.adresse_lat))
                * pg_catalog.cos(pg_catalog.radians(s.adresse_lat))
                * pg_catalog.cos(
                    pg_catalog.radians(s.adresse_lng)
                    - pg_catalog.radians(v_etab.adresse_lng)
                  )
                + pg_catalog.sin(pg_catalog.radians(v_etab.adresse_lat))
                  * pg_catalog.sin(pg_catalog.radians(s.adresse_lat))
            )
          ))
        )::numeric, 1)
      ELSE NULL
    END,
    (
      SELECT pg_catalog.count(*)::bigint
      FROM public.missions m
      WHERE m.soignant_assigne_id = s.id
        AND COALESCE(m.est_urgente, false) IS TRUE
        AND m.statut = 'TERMINEE'
    ),
    EXISTS (
      SELECT 1
      FROM public.missions m
      WHERE m.soignant_assigne_id = s.id
        AND m.statut = 'EN_COURS'
        AND pg_catalog.now() BETWEEN m.debut_le AND m.fin_le
    ),
    (
      SELECT pg_catalog.max(m2.fin_le)
      FROM public.missions m2
      WHERE m2.soignant_assigne_id = s.id
        AND m2.etablissement_id = p_etablissement_id
        AND m2.statut = 'TERMINEE'
    ),
    s.bio::text,
    s.avatar_url::text,
    EXISTS (
      SELECT 1
      FROM public.favoris_etab_soignant f
      WHERE f.soignant_id = s.id
        AND f.etablissement_id = p_etablissement_id
    )
  FROM public.soignants s
  WHERE private.fn_soignant_messagerie_actif(s.id)
    AND COALESCE(s.disponible_urgence, false) IS TRUE
    AND public.fn_documents_ok_pour_mission(s.id, 'TOUS')
    AND NOT public.fn_est_exclu(s.id, p_etablissement_id)
    AND (
      EXISTS (
        SELECT 1
        FROM public.missions m
        WHERE m.etablissement_id = p_etablissement_id
          AND m.statut IN (
            'OUVERTE', 'ASSIGNEE', 'EN_COURS', 'ABSENCE', 'LITIGE'
          )
          AND private.fn_compatibilite_profil_mission(
    s.id, m.profession_requise, m.specialite_medicale_requise,
    COALESCE(m.accepte_non_specialises, true), m.accepte_internes, m.fin_le
  )
      )
      OR (private.fn_statut_internat_medical(s.id)->>'statut' = 'NON_CONCERNE' AND NOT EXISTS (
        SELECT 1
        FROM public.missions m
        WHERE m.etablissement_id = p_etablissement_id
          AND m.statut IN (
            'OUVERTE', 'ASSIGNEE', 'EN_COURS', 'ABSENCE', 'LITIGE'
          )
      ))
    )
  ORDER BY
    CASE
      WHEN COALESCE(s.total_missions_terminees, 0) >= 3
      THEN s.score_fiabilite
      ELSE NULL
    END DESC NULLS LAST,
    CASE
      WHEN s.adresse_lat IS NOT NULL
       AND s.adresse_lng IS NOT NULL
       AND v_etab.adresse_lat IS NOT NULL
       AND v_etab.adresse_lng IS NOT NULL THEN
        6371 * pg_catalog.acos(least(
          1.0::double precision,
          greatest(
            (-1.0)::double precision,
            pg_catalog.cos(pg_catalog.radians(v_etab.adresse_lat))
              * pg_catalog.cos(pg_catalog.radians(s.adresse_lat))
              * pg_catalog.cos(
                  pg_catalog.radians(s.adresse_lng)
                  - pg_catalog.radians(v_etab.adresse_lng)
                )
              + pg_catalog.sin(pg_catalog.radians(v_etab.adresse_lat))
                * pg_catalog.sin(pg_catalog.radians(s.adresse_lat))
          )
        ))
      ELSE NULL
    END NULLS LAST;
END;
$function$;



-- LIVE public.fn_finaliser_document_verification: fa55027307a0de0ec444edf49641b0ed
CREATE OR REPLACE FUNCTION public.fn_finaliser_document_verification(p_document_id uuid, p_attempt_id uuid, p_expected_soignant_id uuid, p_expected_s3_bucket text, p_expected_s3_cle text, p_expected_type_document text, p_expected_nom text, p_expected_prenom text, p_expected_date_naissance date, p_expected_sexe text, p_expected_lieu_naissance text, p_expected_profession text, p_expected_numero_rpps text, p_expected_numero_adeli text, p_expected_rpps_verifie boolean, p_expected_adeli_verifie boolean, p_statut_verification text, p_motif_rejet text DEFAULT NULL::text, p_valide_depuis date DEFAULT NULL::date, p_valide_jusqua date DEFAULT NULL::date, p_resultat_ia jsonb DEFAULT NULL::jsonb, p_nom_extrait_ia text DEFAULT NULL::text, p_prenom_extrait_ia text DEFAULT NULL::text, p_score_confiance_ia numeric DEFAULT NULL::numeric, p_coherence_nom boolean DEFAULT NULL::boolean, p_identite_date_naissance date DEFAULT NULL::date, p_identite_sexe text DEFAULT NULL::text, p_identite_lieu_naissance text DEFAULT NULL::text, p_scolarite_formation text DEFAULT NULL::text, p_scolarite_annee_validee integer DEFAULT NULL::integer, p_scolarite_profession text DEFAULT NULL::text, p_licence_valide_jusqua date DEFAULT NULL::date, p_licence_specialite text DEFAULT NULL::text, p_expected_heures_employeur text DEFAULT NULL::text, p_expected_heures_date_debut date DEFAULT NULL::date, p_expected_heures_date_fin date DEFAULT NULL::date, p_expected_heures_declarees numeric DEFAULT NULL::numeric, p_expected_heures_type_preuve text DEFAULT NULL::text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_doc public.documents_soignants%ROWTYPE;
  v_soignant public.soignants%ROWTYPE;
  v_heures public.heures_externes%ROWTYPE;
  v_statut public.statut_verification;
  v_coherence_nom boolean := p_coherence_nom;
  v_identite boolean;
  v_code_licence text;
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'Service role requis' USING ERRCODE = '42501';
  END IF;
  IF p_document_id IS NULL OR p_attempt_id IS NULL OR p_expected_soignant_id IS NULL THEN
    RAISE EXCEPTION 'Tentative documentaire incomplète' USING ERRCODE = '22023';
  END IF;
  IF p_statut_verification NOT IN ('VERIFIE', 'EN_ATTENTE', 'REJETE') THEN
    RAISE EXCEPTION 'Verdict documentaire invalide' USING ERRCODE = '22023';
  END IF;
  v_statut := p_statut_verification::public.statut_verification;

  SELECT * INTO v_doc
  FROM public.documents_soignants
  WHERE id = p_document_id
    AND verification_attempt_id = p_attempt_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Tentative documentaire périmée' USING ERRCODE = '40001';
  END IF;

  IF v_doc.soignant_id IS DISTINCT FROM p_expected_soignant_id
     OR v_doc.s3_bucket IS DISTINCT FROM p_expected_s3_bucket
     OR v_doc.s3_cle IS DISTINCT FROM p_expected_s3_cle
     OR v_doc.type_document::text IS DISTINCT FROM p_expected_type_document
     OR v_doc.supprime_le IS NOT NULL THEN
    RAISE EXCEPTION 'Source documentaire modifiée pendant la vérification'
      USING ERRCODE = '40001';
  END IF;

  SELECT * INTO v_soignant
  FROM public.soignants
  WHERE id = p_expected_soignant_id AND supprime_le IS NULL
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Profil soignant introuvable' USING ERRCODE = 'P0002';
  END IF;

  IF v_soignant.nom IS DISTINCT FROM p_expected_nom
     OR v_soignant.prenom IS DISTINCT FROM p_expected_prenom
     OR v_soignant.date_naissance IS DISTINCT FROM p_expected_date_naissance
     OR v_soignant.sexe IS DISTINCT FROM p_expected_sexe
     OR v_soignant.lieu_naissance_commune IS DISTINCT FROM p_expected_lieu_naissance
     OR v_soignant.profession::text IS DISTINCT FROM p_expected_profession
     OR v_soignant.numero_rpps IS DISTINCT FROM p_expected_numero_rpps
     OR v_soignant.numero_adeli IS DISTINCT FROM p_expected_numero_adeli
     OR COALESCE(v_soignant.rpps_verifie, false) IS DISTINCT FROM COALESCE(p_expected_rpps_verifie, false)
     OR COALESCE(v_soignant.adeli_verifie, false) IS DISTINCT FROM COALESCE(p_expected_adeli_verifie, false) THEN
    RAISE EXCEPTION 'Profil modifié pendant la vérification'
      USING ERRCODE = '40001';
  END IF;

  v_identite := v_doc.type_document IN ('CARTE_IDENTITE', 'PASSEPORT', 'TITRE_SEJOUR');
  IF v_identite THEN
    v_coherence_nom := public.fn_noms_personne_correspondent(
      v_soignant.nom, v_soignant.prenom, p_nom_extrait_ia, p_prenom_extrait_ia
    );
  END IF;

  IF v_identite AND v_statut = 'VERIFIE' THEN
    IF NOT v_coherence_nom OR p_identite_date_naissance IS NULL THEN
      RAISE EXCEPTION 'Identité extraite incomplète ou incohérente' USING ERRCODE = '23514';
    END IF;
    IF v_soignant.date_naissance IS NOT NULL
       AND v_soignant.date_naissance IS DISTINCT FROM p_identite_date_naissance THEN
      RAISE EXCEPTION 'Date de naissance incohérente' USING ERRCODE = '23514';
    END IF;

    UPDATE public.soignants
    SET date_naissance = COALESCE(date_naissance, p_identite_date_naissance),
        sexe = CASE
          WHEN sexe IS NULL AND p_identite_sexe IN ('M', 'F') THEN p_identite_sexe
          ELSE sexe
        END,
        lieu_naissance_commune = CASE
          WHEN lieu_naissance_commune IS NULL
               AND NULLIF(btrim(p_identite_lieu_naissance), '') IS NOT NULL
            THEN left(btrim(p_identite_lieu_naissance), 120)
          ELSE lieu_naissance_commune
        END,
        modifie_le = now()
    WHERE id = v_soignant.id;
  END IF;

  IF p_scolarite_formation IS NOT NULL
     OR p_scolarite_annee_validee IS NOT NULL
     OR p_scolarite_profession IS NOT NULL THEN
    IF v_statut IS DISTINCT FROM 'VERIFIE'
       OR v_doc.type_document IS DISTINCT FROM 'ATTESTATION_SCOLARITE'
       OR p_scolarite_formation IS NULL
       OR p_scolarite_annee_validee IS NULL
       OR p_scolarite_profession IS DISTINCT FROM v_soignant.profession::text
       OR NOT EXISTS (
         SELECT 1
         FROM public.fn_professions_autorisees_scolarite(
           p_scolarite_formation,
           p_scolarite_annee_validee
         ) AS profession_autorisee
         WHERE profession_autorisee = v_soignant.profession
       ) THEN
      RAISE EXCEPTION 'Effet de scolarité incohérent' USING ERRCODE = '23514';
    END IF;

    UPDATE public.soignants
    SET scolarite_formation = left(p_scolarite_formation, 50),
        scolarite_annee_validee = p_scolarite_annee_validee,
        scolarite_profession_autorisee = v_soignant.profession,
        scolarite_verifiee = true,
        scolarite_verifiee_le = now(),
        est_etudiant = true,
        modifie_le = now()
    WHERE id = v_soignant.id;
  END IF;

  IF p_licence_valide_jusqua IS NOT NULL OR p_licence_specialite IS NOT NULL THEN
    v_code_licence := private.fn_code_specialite_licence_exact(p_licence_specialite);
    IF v_code_licence IS NULL THEN
      RAISE EXCEPTION 'Spécialité de licence non résolue : revue manuelle requise' USING ERRCODE='23514';
    END IF;
    p_resultat_ia := COALESCE(p_resultat_ia, '{}'::jsonb)
      || jsonb_build_object('licence_remplacement_specialite_code', v_code_licence);
    IF v_statut IS DISTINCT FROM 'VERIFIE'
       OR v_doc.type_document IS DISTINCT FROM 'LICENCE_REMPLACEMENT'
       OR v_soignant.profession::text IS DISTINCT FROM 'MEDECIN'
       OR p_licence_valide_jusqua IS NULL
       OR p_licence_valide_jusqua < current_date
       OR NULLIF(btrim(p_licence_specialite), '') IS NULL THEN
      RAISE EXCEPTION 'Effet de licence incohérent' USING ERRCODE = '23514';
    END IF;

    UPDATE public.soignants
    SET licence_remplacement_verifiee = true,
        licence_remplacement_le = now(),
        licence_remplacement_valide_jusqua = p_licence_valide_jusqua,
        licence_remplacement_specialite = left(btrim(p_licence_specialite), 200),
        est_etudiant = true,
        modifie_le = now()
    WHERE id = v_soignant.id;
  END IF;

  IF v_statut = 'VERIFIE'
     AND v_doc.type_document::text IN ('BULLETIN_PAIE', 'ATTESTATION_EMPLOYEUR', 'CERTIFICAT_TRAVAIL') THEN
    SELECT * INTO v_heures
    FROM public.heures_externes
    WHERE document_id = v_doc.id AND soignant_id = v_soignant.id
    FOR SHARE;
    IF NOT FOUND
       OR v_heures.employeur_nom IS DISTINCT FROM p_expected_heures_employeur
       OR v_heures.date_debut IS DISTINCT FROM p_expected_heures_date_debut
       OR v_heures.date_fin IS DISTINCT FROM p_expected_heures_date_fin
       OR v_heures.heures_declarees IS DISTINCT FROM p_expected_heures_declarees
       OR v_heures.type_preuve IS DISTINCT FROM p_expected_heures_type_preuve THEN
      RAISE EXCEPTION 'Déclaration d''heures modifiée pendant la vérification'
        USING ERRCODE = '40001';
    END IF;
  END IF;

  UPDATE public.documents_soignants
  SET resultat_ia = p_resultat_ia,
      nom_extrait_ia = NULLIF(left(btrim(COALESCE(p_nom_extrait_ia, '')), 200), ''),
      prenom_extrait_ia = NULLIF(left(btrim(COALESCE(p_prenom_extrait_ia, '')), 200), ''),
      score_confiance_ia = CASE
        WHEN p_score_confiance_ia IS NULL THEN NULL
        ELSE greatest(0, least(100, p_score_confiance_ia))
      END,
      coherence_nom = v_coherence_nom,
      statut_verification = v_statut,
      motif_rejet = NULLIF(left(COALESCE(p_motif_rejet, ''), 1000), ''),
      valide_depuis = CASE WHEN v_statut = 'REJETE' THEN NULL ELSE p_valide_depuis END,
      valide_jusqua = CASE WHEN v_statut = 'REJETE' THEN NULL ELSE p_valide_jusqua END,
      verifie_le = CASE WHEN v_statut = 'VERIFIE' THEN now() ELSE NULL END,
      verification_attempt_id = NULL,
      modifie_le = now()
  WHERE id = v_doc.id AND verification_attempt_id = p_attempt_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Tentative documentaire remplacée' USING ERRCODE = '40001';
  END IF;

  RETURN true;
END;
$function$;

-- LIVE public.fn_admin_moderer_document_internal_20260810: 9c4be4995b90bcc4ad41385ff772df44
CREATE OR REPLACE FUNCTION public.fn_admin_moderer_document_internal_20260810(p_document_id uuid, p_action text, p_motif text, p_validation_manuelle jsonb, p_raison_override text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_action text := upper(NULLIF(btrim(p_action), ''));
  v_validation jsonb := COALESCE(p_validation_manuelle, '{}'::jsonb);
  v_doc public.documents_soignants%ROWTYPE;
  v_soignant public.soignants%ROWTYPE;
  v_heures public.heures_externes%ROWTYPE;
  v_expected_doc_modifie timestamptz;
  v_expected_soignant_modifie timestamptz;
  v_nom_extrait text;
  v_prenom_extrait text;
  v_date_naissance date;
  v_date_emission date;
  v_date_expiration date;
  v_date_emission_raw text;
  v_date_expiration_raw text;
  v_profession_certifiee text;
  v_type_identifiant text;
  v_numero_professionnel text;
  v_numero_attendu text;
  v_iban text;
  v_iban_normalise text;
  v_iban_last4 text;
  v_liaison_bancaire jsonb;
  v_exige_expiration boolean := false;
  v_diplome_compatible boolean := false;
  v_diplome_etranger boolean := false;
  v_formation text;
  v_annee_validee integer;
  v_specialite_licence text;
  v_code_licence text;
  v_override_requis boolean := false;
  v_ai_indisponible boolean := false;
  v_source text;
  v_raison_override text := NULLIF(btrim(p_raison_override), '');
  v_snapshot jsonb;
  v_resultat_final jsonb;
  v_previous_moderation text := COALESCE(
    current_setting('jolene.document_moderation_rpc', true),
    ''
  );
  v_row_count integer := 0;
  v_allowed_key text;
BEGIN
  -- est_admin() impose déjà rôle app_metadata, compte actif, registre
  -- equipe_admin complet et AAL2. Le contrôle AAL explicite protège aussi
  -- contre une future régression de cette fonction partagée.
  IF v_uid IS NULL
     OR NOT public.est_admin() THEN
    RAISE EXCEPTION 'Administrateur autorisé requis'
      USING ERRCODE = '42501';
  END IF;
  IF p_document_id IS NULL OR v_action NOT IN ('VALIDER', 'REJETER') THEN
    RAISE EXCEPTION 'Action de modération invalide'
      USING ERRCODE = '22023';
  END IF;
  IF jsonb_typeof(v_validation) IS DISTINCT FROM 'object' THEN
    RAISE EXCEPTION 'Contexte de modération invalide'
      USING ERRCODE = '22023';
  END IF;

  -- Liste blanche : empêche de journaliser ou conserver par mégarde un champ
  -- arbitraire/sensible fourni par le navigateur.
  SELECT key INTO v_allowed_key
  FROM jsonb_object_keys(v_validation) AS keys(key)
  WHERE key <> ALL (ARRAY[
    'expected_document_modifie_le', 'expected_soignant_modifie_le',
    'expected_statut', 'expected_type_document', 'expected_soignant_id',
    'expected_s3_bucket', 'expected_s3_cle', 'expected_s3_version_id',
    'document_lisible', 'document_complet', 'type_document_confirme',
    'antifraude_verifiee', 'override_confirme', 'nom_extrait',
    'prenom_extrait', 'date_naissance', 'date_emission', 'date_expiration',
    'profession_certifiee', 'diplome_etranger',
    'type_identifiant_professionnel', 'numero_professionnel', 'iban',
    'scolarite_formation', 'scolarite_annee_validee',
    'licence_remplacement_specialite', 'licence_remplacement_specialite_code', 'employeur_extrait',
    'periode_debut_extraite', 'periode_fin_extraite', 'heures_extraites'
  ]::text[])
  LIMIT 1;
  IF v_allowed_key IS NOT NULL THEN
    RAISE EXCEPTION 'Champ de modération non autorisé : %', v_allowed_key
      USING ERRCODE = '22023';
  END IF;

  IF NULLIF(v_validation ->> 'expected_document_modifie_le', '') IS NULL
     OR NULLIF(v_validation ->> 'expected_soignant_modifie_le', '') IS NULL
     OR NULLIF(v_validation ->> 'expected_statut', '') IS NULL
     OR NULLIF(v_validation ->> 'expected_type_document', '') IS NULL
     OR NULLIF(v_validation ->> 'expected_soignant_id', '') IS NULL
     OR NULLIF(v_validation ->> 'expected_s3_bucket', '') IS NULL
     OR NULLIF(v_validation ->> 'expected_s3_cle', '') IS NULL THEN
    RAISE EXCEPTION 'Snapshot CAS incomplet : rechargez la file de modération'
      USING ERRCODE = '22023';
  END IF;
  BEGIN
    v_expected_doc_modifie := (v_validation ->> 'expected_document_modifie_le')::timestamptz;
    v_expected_soignant_modifie := (v_validation ->> 'expected_soignant_modifie_le')::timestamptz;
  EXCEPTION WHEN invalid_datetime_format OR datetime_field_overflow THEN
    RAISE EXCEPTION 'Snapshot CAS invalide : rechargez la file de modération'
      USING ERRCODE = '22023';
  END;

  SELECT * INTO v_doc
  FROM public.documents_soignants
  WHERE id = p_document_id
  FOR UPDATE;
  IF NOT FOUND OR v_doc.supprime_le IS NOT NULL THEN
    RAISE EXCEPTION 'Document introuvable ou supprimé' USING ERRCODE = 'P0002';
  END IF;

  SELECT * INTO v_soignant
  FROM public.soignants
  WHERE id = v_doc.soignant_id AND supprime_le IS NULL
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Profil soignant introuvable' USING ERRCODE = 'P0002';
  END IF;

  IF v_doc.modifie_le IS DISTINCT FROM v_expected_doc_modifie
     OR v_soignant.modifie_le IS DISTINCT FROM v_expected_soignant_modifie
     OR v_doc.statut_verification::text IS DISTINCT FROM v_validation ->> 'expected_statut'
     OR v_doc.type_document::text IS DISTINCT FROM v_validation ->> 'expected_type_document'
     OR v_doc.soignant_id::text IS DISTINCT FROM v_validation ->> 'expected_soignant_id'
     OR v_doc.s3_bucket IS DISTINCT FROM v_validation ->> 'expected_s3_bucket'
     OR v_doc.s3_cle IS DISTINCT FROM v_validation ->> 'expected_s3_cle'
     OR v_doc.s3_version_id IS DISTINCT FROM NULLIF(v_validation ->> 'expected_s3_version_id', '') THEN
    RAISE EXCEPTION 'Le document, sa source ou le profil a changé : rechargez avant de décider'
      USING ERRCODE = '40001';
  END IF;
  IF v_doc.statut_verification NOT IN (
       'EN_ATTENTE', 'REVUE_MANUELLE_REQUISE', 'API_INDISPONIBLE'
     )
     OR v_doc.verification_attempt_id IS NOT NULL THEN
    RAISE EXCEPTION 'Ce document n’est plus disponible pour une décision manuelle'
      USING ERRCODE = '40001';
  END IF;

  v_snapshot := jsonb_build_object(
    'document', jsonb_build_object(
      'id', v_doc.id,
      'modifie_le', v_doc.modifie_le,
      'statut', v_doc.statut_verification,
      'type_document', v_doc.type_document,
      's3_bucket', v_doc.s3_bucket,
      's3_cle', v_doc.s3_cle,
      's3_version_id', v_doc.s3_version_id,
      'type_mime', v_doc.type_mime,
      'taille_octets', v_doc.taille_octets,
      'motif_precedent', v_doc.motif_rejet,
      'resultat_ia_present', v_doc.resultat_ia IS NOT NULL
    ),
    'profil', jsonb_build_object(
      'id', v_soignant.id,
      'modifie_le', v_soignant.modifie_le,
      'nom', v_soignant.nom,
      'prenom', v_soignant.prenom,
      'date_naissance', v_soignant.date_naissance,
      'profession', v_soignant.profession,
      'rpps_verifie', COALESCE(v_soignant.rpps_verifie, false),
      'adeli_verifie', COALESCE(v_soignant.adeli_verifie, false)
    )
  );

  IF v_action = 'REJETER' THEN
    IF char_length(btrim(COALESCE(p_motif, ''))) < 10
       OR char_length(btrim(COALESCE(p_motif, ''))) > 1000 THEN
      RAISE EXCEPTION 'Le motif de rejet doit contenir entre 10 et 1000 caractères'
        USING ERRCODE = '22023';
    END IF;

    PERFORM set_config('jolene.document_moderation_rpc', 'true', true);
    BEGIN
      UPDATE public.documents_soignants
      SET statut_verification = 'REJETE',
          verifie_par = v_uid,
          verifie_le = now(),
          motif_rejet = btrim(p_motif),
          valide_depuis = NULL,
          valide_jusqua = NULL,
          verification_attempt_id = NULL,
          resultat_ia = COALESCE(resultat_ia, '{}'::jsonb) || jsonb_build_object(
            'verdict_serveur', 'REJETE',
            'motif_serveur', btrim(p_motif),
            'source_validation', 'ADMIN_REJET'
          ),
          modifie_le = now()
      WHERE id = v_doc.id
        AND modifie_le = v_expected_doc_modifie
        AND statut_verification = v_doc.statut_verification
        AND verification_attempt_id IS NULL;
      GET DIAGNOSTICS v_row_count = ROW_COUNT;
      IF v_row_count IS DISTINCT FROM 1 THEN
        RAISE EXCEPTION 'Décision concurrente détectée' USING ERRCODE = '40001';
      END IF;

      INSERT INTO public.journaux_audit (
        acteur_id, type_acteur, action, type_ressource, id_ressource,
        cle_s3_ressource, details
      ) VALUES (
        v_uid, 'ADMIN', 'MODERATION_DOCUMENT', 'document', v_doc.id,
        v_doc.s3_cle,
        jsonb_build_object(
          'decision', 'REJETER',
          'source', 'ADMIN_REJET',
          'motif', btrim(p_motif),
          'snapshot', v_snapshot
        )
      );

      UPDATE public.file_revue_manuelle
      SET statut = 'RESOLU_MANUELLEMENT',
          assigne_a = v_uid,
          notes_resolution = left('Document rejeté : ' || btrim(p_motif), 1000),
          revu_le = COALESCE(revu_le, now()),
          resolu_le = now()
      WHERE id_entite = v_doc.id
        AND type_entite = 'TELEVERSEMENT_DOCUMENT'
        AND statut IN ('EN_ATTENTE', 'EN_COURS_REVUE', 'ESCALADE');

      PERFORM public.fn_calculer_tous_documents_valides(v_doc.soignant_id);
    EXCEPTION WHEN OTHERS THEN
      PERFORM set_config(
        'jolene.document_moderation_rpc',
        v_previous_moderation,
        true
      );
      RAISE;
    END;
    PERFORM set_config(
      'jolene.document_moderation_rpc',
      v_previous_moderation,
      true
    );
    RETURN jsonb_build_object('success', true, 'action', 'REJETER');
  END IF;

  -- Toute validation exige une revue visuelle explicite et une identité lue.
  IF v_validation -> 'document_lisible' IS DISTINCT FROM 'true'::jsonb
     OR v_validation -> 'document_complet' IS DISTINCT FROM 'true'::jsonb
     OR v_validation -> 'type_document_confirme' IS DISTINCT FROM 'true'::jsonb
     OR v_validation -> 'antifraude_verifiee' IS DISTINCT FROM 'true'::jsonb THEN
    RAISE EXCEPTION 'Lisibilité, complétude, type et contrôle antifraude doivent être confirmés'
      USING ERRCODE = '23514';
  END IF;

  v_nom_extrait := NULLIF(left(btrim(v_validation ->> 'nom_extrait'), 200), '');
  v_prenom_extrait := NULLIF(left(btrim(v_validation ->> 'prenom_extrait'), 200), '');
  IF NOT public.fn_noms_personne_correspondent(
    v_soignant.nom,
    v_soignant.prenom,
    v_nom_extrait,
    v_prenom_extrait
  ) THEN
    RAISE EXCEPTION 'Le nom et le prénom lus ne correspondent pas au profil'
      USING ERRCODE = '23514';
  END IF;

  v_date_emission_raw := NULLIF(btrim(v_validation ->> 'date_emission'), '');
  v_date_expiration_raw := NULLIF(btrim(v_validation ->> 'date_expiration'), '');
  v_date_emission := private.fn_date_iso_moderation(v_date_emission_raw);
  v_date_expiration := private.fn_date_iso_moderation(v_date_expiration_raw);
  IF v_date_emission_raw IS NOT NULL AND v_date_emission IS NULL THEN
    RAISE EXCEPTION 'Date d’émission invalide' USING ERRCODE = '22023';
  END IF;
  IF v_date_expiration_raw IS NOT NULL AND v_date_expiration IS NULL THEN
    RAISE EXCEPTION 'Date d’expiration invalide' USING ERRCODE = '22023';
  END IF;
  IF v_date_emission > current_date THEN
    RAISE EXCEPTION 'La date d’émission ne peut pas être future' USING ERRCODE = '23514';
  END IF;
  IF v_date_expiration IS NOT NULL AND v_date_expiration <= current_date THEN
    RAISE EXCEPTION 'Un document expiré ne peut pas être validé' USING ERRCODE = '23514';
  END IF;
  IF v_date_emission IS NOT NULL
     AND v_date_expiration IS NOT NULL
     AND v_date_expiration < v_date_emission THEN
    RAISE EXCEPTION 'La date d’expiration précède la date d’émission'
      USING ERRCODE = '23514';
  END IF;

  SELECT COALESCE(bool_or(drp.a_expiration), false)
  INTO v_exige_expiration
  FROM public.documents_requis_par_profession drp
  WHERE drp.profession = v_soignant.profession
    AND public.fn_type_document_preuve_compatible(
      drp.type_document,
      v_doc.type_document
    );
  v_exige_expiration := COALESCE(v_exige_expiration, false)
    OR v_doc.type_document IN (
      'CARTE_IDENTITE', 'PASSEPORT', 'TITRE_SEJOUR',
      'RCP_ASSURANCE', 'LICENCE_REMPLACEMENT'
    );
  IF v_exige_expiration AND v_date_expiration IS NULL THEN
    RAISE EXCEPTION 'La date d’expiration est obligatoire pour ce document'
      USING ERRCODE = '23514';
  END IF;

  IF v_doc.type_document IN ('CARTE_IDENTITE', 'PASSEPORT', 'TITRE_SEJOUR') THEN
    v_date_naissance := private.fn_date_iso_moderation(
      v_validation ->> 'date_naissance'
    );
    IF v_date_naissance IS NULL
       OR v_date_naissance < DATE '1900-01-01'
       OR v_date_naissance >= current_date THEN
      RAISE EXCEPTION 'Date de naissance absente ou non plausible'
        USING ERRCODE = '23514';
    END IF;
    IF v_soignant.date_naissance IS NOT NULL
       AND v_soignant.date_naissance IS DISTINCT FROM v_date_naissance THEN
      RAISE EXCEPTION 'La date de naissance du document contredit le profil'
        USING ERRCODE = '23514';
    END IF;
  END IF;

  IF v_doc.type_document IN ('DIPLOME', 'AUTORISATION_EXERCICE') THEN
    v_profession_certifiee := upper(NULLIF(btrim(
      v_validation ->> 'profession_certifiee'
    ), ''));
    IF NOT EXISTS (
      SELECT 1
      FROM unnest(enum_range(NULL::public.type_profession)) AS p(profession)
      WHERE p.profession::text = v_profession_certifiee
    ) THEN
      RAISE EXCEPTION 'Profession certifiée absente ou inconnue'
        USING ERRCODE = '23514';
    END IF;
    v_diplome_compatible := CASE v_soignant.profession::text
      WHEN 'IDE' THEN v_profession_certifiee IN ('IDE', 'IADE', 'IBODE')
      WHEN 'IADE' THEN v_profession_certifiee = 'IADE'
      WHEN 'IBODE' THEN v_profession_certifiee = 'IBODE'
      ELSE v_profession_certifiee = v_soignant.profession::text
    END;
    IF NOT v_diplome_compatible THEN
      RAISE EXCEPTION 'La qualification certifiée ne correspond pas à la profession du profil'
        USING ERRCODE = '23514';
    END IF;

    v_diplome_etranger := COALESCE(
      (v_validation ->> 'diplome_etranger')::boolean,
      false
    );
    IF v_doc.type_document = 'DIPLOME'
       AND v_diplome_etranger
       AND NOT EXISTS (
         SELECT 1
         FROM public.documents_soignants autorisation
         WHERE autorisation.soignant_id = v_doc.soignant_id
           AND autorisation.type_document = 'AUTORISATION_EXERCICE'
           AND autorisation.statut_verification = 'VERIFIE'
           AND autorisation.supprime_le IS NULL
           AND (
             autorisation.valide_jusqua IS NULL
             OR autorisation.valide_jusqua > current_date
           )
           AND CASE v_soignant.profession::text
             WHEN 'IDE' THEN upper(COALESCE(
               autorisation.resultat_ia ->> 'profession_certifiee', ''
             )) IN ('IDE', 'IADE', 'IBODE')
             WHEN 'IADE' THEN upper(COALESCE(
               autorisation.resultat_ia ->> 'profession_certifiee', ''
             )) = 'IADE'
             WHEN 'IBODE' THEN upper(COALESCE(
               autorisation.resultat_ia ->> 'profession_certifiee', ''
             )) = 'IBODE'
             ELSE upper(COALESCE(
               autorisation.resultat_ia ->> 'profession_certifiee', ''
             )) = v_soignant.profession::text
           END
       ) THEN
      RAISE EXCEPTION 'Un diplôme étranger exige une autorisation d’exercice vérifiée et concordante'
        USING ERRCODE = '23514';
    END IF;
  END IF;

  IF v_doc.type_document = 'RPPS_ADELI' THEN
    v_type_identifiant := upper(NULLIF(btrim(
      v_validation ->> 'type_identifiant_professionnel'
    ), ''));
    v_numero_professionnel := regexp_replace(
      COALESCE(v_validation ->> 'numero_professionnel', ''),
      '[^0-9]',
      '',
      'g'
    );
    IF v_type_identifiant = 'RPPS' THEN
      v_numero_attendu := regexp_replace(COALESCE(v_soignant.numero_rpps, ''), '[^0-9]', '', 'g');
      IF COALESCE(v_soignant.rpps_verifie, false) IS NOT TRUE
         OR v_numero_professionnel !~ '^\d{11}$'
         OR v_numero_professionnel IS DISTINCT FROM v_numero_attendu THEN
        RAISE EXCEPTION 'RPPS non vérifié ou différent du profil'
          USING ERRCODE = '23514';
      END IF;
    ELSIF v_type_identifiant = 'ADELI' THEN
      v_numero_attendu := regexp_replace(COALESCE(v_soignant.numero_adeli, ''), '[^0-9]', '', 'g');
      IF COALESCE(v_soignant.adeli_verifie, false) IS NOT TRUE
         OR v_numero_professionnel !~ '^\d{9}$'
         OR v_numero_professionnel IS DISTINCT FROM v_numero_attendu THEN
        RAISE EXCEPTION 'ADELI non vérifié ou différent du profil'
          USING ERRCODE = '23514';
      END IF;
    ELSE
      RAISE EXCEPTION 'Type d’identifiant professionnel invalide'
        USING ERRCODE = '23514';
    END IF;
  END IF;

  IF v_doc.type_document = 'RIB' THEN
    v_iban := v_validation ->> 'iban';
    IF NOT private.fn_iban_valide_moderation(v_iban) THEN
      RAISE EXCEPTION 'IBAN invalide (format ou checksum ISO 13616)'
        USING ERRCODE = '23514';
    END IF;
    v_iban_normalise := upper(regexp_replace(v_iban, '[^A-Za-z0-9]', '', 'g'));
    v_iban_last4 := right(v_iban_normalise, 4);
    IF NULLIF(btrim(v_soignant.iban_virement), '') IS NOT NULL
       AND upper(regexp_replace(v_soignant.iban_virement, '[^A-Za-z0-9]', '', 'g'))
         IS DISTINCT FROM v_iban_normalise THEN
      RAISE EXCEPTION 'L’IBAN du RIB diffère de l’IBAN de versement enregistré'
        USING ERRCODE = '23514';
    END IF;
  END IF;

  IF v_doc.type_document = 'ATTESTATION_SCOLARITE' THEN
    v_formation := upper(NULLIF(btrim(
      v_validation ->> 'scolarite_formation'
    ), ''));
    BEGIN
      v_annee_validee := (v_validation ->> 'scolarite_annee_validee')::integer;
    EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN
      v_annee_validee := NULL;
    END;
    IF v_date_emission IS NULL
       OR v_date_emission < current_date - 400
       OR v_date_emission > current_date THEN
      RAISE EXCEPTION 'L’attestation de scolarité doit dater de moins de 400 jours'
        USING ERRCODE = '23514';
    END IF;
    IF v_formation IS NULL OR v_annee_validee IS NULL
       OR NOT EXISTS (
         SELECT 1
         FROM public.fn_professions_autorisees_scolarite(
           v_formation,
           v_annee_validee
         ) AS autorisee(profession)
         WHERE autorisee.profession = v_soignant.profession
       ) THEN
      RAISE EXCEPTION 'La formation ou l’année validée ne permet pas la profession du profil'
        USING ERRCODE = '23514';
    END IF;
  END IF;

  IF v_doc.type_document = 'LICENCE_REMPLACEMENT' THEN
    v_code_licence := NULLIF(btrim(v_validation->>'licence_remplacement_specialite_code'), '');
    IF NOT EXISTS (SELECT 1 FROM public.specialites_medicales sm
      WHERE sm.code=v_code_licence AND sm.code ~ '^SM[0-9]+$') THEN
      RAISE EXCEPTION 'Choisissez la spécialité canonique portée par la licence.' USING ERRCODE='23514';
    END IF;
    v_specialite_licence := NULLIF(left(btrim(
      v_validation ->> 'licence_remplacement_specialite'
    ), 200), '');
    IF v_soignant.profession IS DISTINCT FROM 'MEDECIN'
       OR v_date_emission IS NULL
       OR v_date_expiration IS NULL
       OR v_date_expiration > (v_date_emission + interval '13 months')::date
       OR v_specialite_licence IS NULL THEN
      RAISE EXCEPTION 'Licence de remplacement non concordante, incomplète ou hors validité'
        USING ERRCODE = '23514';
    END IF;
  END IF;

  IF v_doc.type_document::text IN (
    'BULLETIN_PAIE', 'ATTESTATION_EMPLOYEUR', 'CERTIFICAT_TRAVAIL'
  ) THEN
    SELECT * INTO v_heures
    FROM public.heures_externes
    WHERE document_id = v_doc.id
      AND soignant_id = v_doc.soignant_id
    FOR SHARE;
    IF NOT FOUND
       OR public.fn_normaliser_nom(v_heures.employeur_nom)
         IS DISTINCT FROM public.fn_normaliser_nom(
           v_validation ->> 'employeur_extrait'
         )
       OR v_heures.date_debut IS DISTINCT FROM private.fn_date_iso_moderation(
         v_validation ->> 'periode_debut_extraite'
       )
       OR v_heures.date_fin IS DISTINCT FROM private.fn_date_iso_moderation(
         v_validation ->> 'periode_fin_extraite'
       )
       OR v_heures.heures_declarees IS DISTINCT FROM
         NULLIF(v_validation ->> 'heures_extraites', '')::numeric
       OR v_heures.type_preuve IS DISTINCT FROM v_doc.type_document::text THEN
      RAISE EXCEPTION 'Employeur, période ou heures non concordants avec la déclaration'
        USING ERRCODE = '23514';
    END IF;
  END IF;

  v_ai_indisponible := v_doc.statut_verification = 'API_INDISPONIBLE'
    OR v_doc.resultat_ia IS NULL
    OR v_doc.resultat_ia ? 'erreur_anthropic'
    OR v_doc.resultat_ia ? 'erreur_parse';
  v_override_requis := NOT v_ai_indisponible AND (
    upper(COALESCE(v_doc.resultat_ia ->> 'verdict', '')) = 'REJETE'
    OR upper(COALESCE(v_doc.resultat_ia ->> 'verdict_serveur', '')) = 'REJETE'
    OR v_doc.resultat_ia -> 'type_correspond' = 'false'::jsonb
    OR v_doc.resultat_ia -> 'document_lisible' = 'false'::jsonb
    OR v_doc.resultat_ia -> 'document_complet' = 'false'::jsonb
    OR v_doc.resultat_ia -> 'nom_correspond' = 'false'::jsonb
    OR v_doc.coherence_nom IS FALSE
    OR (
      jsonb_typeof(v_doc.resultat_ia -> 'indices_falsification') = 'array'
      AND jsonb_array_length(v_doc.resultat_ia -> 'indices_falsification') > 0
    )
  );
  IF v_raison_override IS NOT NULL THEN
    v_override_requis := true;
  END IF;
  IF v_override_requis AND (
    v_validation -> 'override_confirme' IS DISTINCT FROM 'true'::jsonb
    OR char_length(v_raison_override) < 30
    OR char_length(v_raison_override) > 1000
  ) THEN
    RAISE EXCEPTION 'Une dérogation exceptionnelle confirmée et motivée (30 à 1000 caractères) est obligatoire'
      USING ERRCODE = '23514';
  END IF;
  v_source := CASE
    WHEN v_override_requis THEN 'ADMIN_OVERRIDE_EXCEPTIONNEL'
    WHEN v_ai_indisponible THEN 'ADMIN_SAISIE_MANUELLE'
    ELSE 'ADMIN_REVUE_IA'
  END;

  -- Les champs manuels nécessaires aux règles dérivées sont persistés dans
  -- resultat_ia, mais jamais l'IBAN complet. Le suffixe historique de colonne
  -- reste inchangé pour compatibilité avec les recalculs existants.
  v_resultat_final := (
    COALESCE(v_doc.resultat_ia, '{}'::jsonb)
      - 'iban'
      - 'iban_extrait'
      - 'raw_text'
  ) || jsonb_strip_nulls(jsonb_build_object(
    'verdict_serveur', 'VERIFIE',
    'motif_serveur', NULL,
    'source_validation', v_source,
    'revue_manuelle_le', now(),
    'type_correspond', true,
    'document_lisible', true,
    'document_complet', true,
    'antifraude_manuelle_verifiee', true,
    'nom_correspond', true,
    'nom_extrait', v_nom_extrait,
    'prenom_extrait', v_prenom_extrait,
    'date_naissance_extraite', v_date_naissance,
    'date_emission', v_date_emission,
    'date_expiration', v_date_expiration,
    'profession_certifiee', v_profession_certifiee,
    'diplome_etranger', CASE
      WHEN v_doc.type_document = 'DIPLOME' THEN v_diplome_etranger
      ELSE NULL
    END,
    'type_identifiant_professionnel', v_type_identifiant,
    'numero_professionnel_extrait', v_numero_professionnel,
    'iban_last4', v_iban_last4,
    'iban_valide', CASE WHEN v_doc.type_document = 'RIB' THEN true ELSE NULL END,
    'iban_preuve_hash_v1', CASE
      WHEN v_doc.type_document = 'RIB' THEN encode(
        extensions.digest(
          convert_to(v_iban_normalise || ':' || v_doc.id::text, 'UTF8'),
          'sha256'
        ),
        'hex'
      )
      ELSE NULL
    END,
    'scolarite_formation', v_formation,
    'scolarite_annee_validee', v_annee_validee,
    'licence_remplacement_specialite', v_specialite_licence,
    'licence_remplacement_specialite_code', v_code_licence,
    'employeur_extrait', CASE WHEN v_heures.id IS NULL THEN NULL ELSE v_heures.employeur_nom END,
    'periode_debut_extraite', CASE WHEN v_heures.id IS NULL THEN NULL ELSE v_heures.date_debut END,
    'periode_fin_extraite', CASE WHEN v_heures.id IS NULL THEN NULL ELSE v_heures.date_fin END,
    'heures_extraites', CASE WHEN v_heures.id IS NULL THEN NULL ELSE v_heures.heures_declarees END
  ));

  PERFORM set_config('jolene.document_moderation_rpc', 'true', true);
  BEGIN
    IF v_doc.type_document IN ('CARTE_IDENTITE', 'PASSEPORT', 'TITRE_SEJOUR')
       AND v_soignant.date_naissance IS NULL THEN
      UPDATE public.soignants
      SET date_naissance = v_date_naissance,
          modifie_le = now()
      WHERE id = v_soignant.id
        AND modifie_le = v_expected_soignant_modifie
        AND date_naissance IS NULL;
      GET DIAGNOSTICS v_row_count = ROW_COUNT;
      IF v_row_count IS DISTINCT FROM 1 THEN
        RAISE EXCEPTION 'Le profil a changé pendant la décision'
          USING ERRCODE = '40001';
      END IF;
    END IF;

    UPDATE public.documents_soignants
    SET statut_verification = 'VERIFIE',
        verifie_par = v_uid,
        verifie_le = now(),
        motif_rejet = NULL,
        valide_depuis = v_date_emission,
        valide_jusqua = v_date_expiration,
        resultat_ia = v_resultat_final,
        nom_extrait_ia = v_nom_extrait,
        prenom_extrait_ia = v_prenom_extrait,
        coherence_nom = true,
        verification_attempt_id = NULL,
        modifie_le = now()
    WHERE id = v_doc.id
      AND modifie_le = v_expected_doc_modifie
      AND statut_verification = v_doc.statut_verification
      AND verification_attempt_id IS NULL;
    GET DIAGNOSTICS v_row_count = ROW_COUNT;
    IF v_row_count IS DISTINCT FROM 1 THEN
      RAISE EXCEPTION 'Décision concurrente détectée' USING ERRCODE = '40001';
    END IF;

    IF v_doc.type_document = 'RIB' THEN
      -- L'IBAN complet n'est jamais persisté dans resultat_ia ni dans l'audit.
      -- Il est transmis en mémoire à la liaison service-role, qui le rattache à
      -- cette version exacte du RIB et à la pièce d'identité courante.
      -- Cette fonction est créée par la migration de durcissement suivante.
      -- La résolution dynamique évite une dépendance d'ordre au moment du
      -- CREATE FUNCTION, tout en conservant l'appel dans la même transaction.
      EXECUTE
        'SELECT public.fn_lier_iban_verifie_document($1, $2, $3)'
      INTO v_liaison_bancaire
      USING v_doc.id, v_doc.s3_cle, v_iban_normalise;
      IF COALESCE((v_liaison_bancaire ->> 'success')::boolean, false) IS NOT TRUE
         AND COALESCE(v_liaison_bancaire ->> 'error_code', '') NOT IN (
           'IDENTITE_VERIFIEE_REQUISE',
           'IDENTITE_COURANTE_REQUISE'
         ) THEN
        RAISE EXCEPTION 'Le RIB validé ne peut pas être lié au compte de versement'
          USING ERRCODE = '23514';
      END IF;
    END IF;

    INSERT INTO public.journaux_audit (
      acteur_id, type_acteur, action, type_ressource, id_ressource,
      cle_s3_ressource, details
    ) VALUES (
      v_uid, 'ADMIN', 'MODERATION_DOCUMENT', 'document', v_doc.id,
      v_doc.s3_cle,
      jsonb_build_object(
        'decision', 'VALIDER',
        'source', v_source,
        'snapshot', v_snapshot,
        'champs_confirmes', jsonb_strip_nulls(jsonb_build_object(
          'nom_extrait', v_nom_extrait,
          'prenom_extrait', v_prenom_extrait,
          'date_naissance', v_date_naissance,
          'date_emission', v_date_emission,
          'date_expiration', v_date_expiration,
          'profession_certifiee', v_profession_certifiee,
          'type_identifiant_professionnel', v_type_identifiant,
          'numero_professionnel', v_numero_professionnel,
          'iban_last4', v_iban_last4,
          'scolarite_formation', v_formation,
          'scolarite_annee_validee', v_annee_validee,
          'licence_specialite', v_specialite_licence
        )),
        'override_raison', v_raison_override
      )
    );

    UPDATE public.file_revue_manuelle
    SET statut = 'RESOLU_MANUELLEMENT',
        assigne_a = v_uid,
        notes_resolution = left(
          CASE
            WHEN v_override_requis THEN 'Validation exceptionnelle : ' || v_raison_override
            ELSE 'Validation documentaire après revue contextualisée (' || v_source || ')'
          END,
          1000
        ),
        revu_le = COALESCE(revu_le, now()),
        resolu_le = now()
    WHERE id_entite = v_doc.id
      AND type_entite = 'TELEVERSEMENT_DOCUMENT'
      AND statut IN ('EN_ATTENTE', 'EN_COURS_REVUE', 'ESCALADE');

    PERFORM public.fn_calculer_tous_documents_valides(v_doc.soignant_id);
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config(
      'jolene.document_moderation_rpc',
      v_previous_moderation,
      true
    );
    RAISE;
  END;
  PERFORM set_config(
    'jolene.document_moderation_rpc',
    v_previous_moderation,
    true
  );

  RETURN jsonb_build_object(
    'success', true,
    'action', 'VALIDER',
    'source', v_source
  );
END;
$function$;

-- LIVE public.fn_lire_candidatures_mission_habilitee: 5df1abf5ab9393948925c698f136c2b2
CREATE OR REPLACE FUNCTION public.fn_lire_candidatures_mission_habilitee(p_mission_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_mission public.missions%ROWTYPE; v_nom text;
BEGIN
  IF auth.uid() IS NULL OR public.fn_compte_auth_actif() IS NOT TRUE
    OR NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id=auth.uid()
      AND u.email_confirmed_at IS NOT NULL)
  THEN RAISE EXCEPTION 'Mission indisponible ou accès refusé' USING ERRCODE='42501'; END IF;

  SELECT m.* INTO v_mission FROM public.missions m
  JOIN public.etablissements e ON e.id=m.etablissement_id AND e.supprime_le IS NULL
  WHERE m.id=p_mission_id;
  IF NOT FOUND
    OR public.fn_role_etablissement_courant(v_mission.etablissement_id)
      IS NULL
    OR public.fn_a_permission_etablissement('candidatures',v_mission.etablissement_id) IS NOT TRUE
  THEN RAISE EXCEPTION 'Mission indisponible ou accès refusé' USING ERRCODE='42501'; END IF;

  -- Une adhésion active au bon établissement est nécessaire ; ni métadonnée
  -- éditable, ni simple appartenance au groupe de santé ne suffit.
  -- Le repli propriétaire historique ne réactive pas une adhésion révoquée.
  IF NOT EXISTS (SELECT 1 FROM public.membres_etablissement me
      WHERE me.user_id=auth.uid() AND me.etablissement_id=v_mission.etablissement_id
        AND me.actif IS TRUE AND me.role IN ('PROPRIETAIRE','ADMIN_GROUPE','RH'))
    AND NOT (auth.uid()=v_mission.etablissement_id
      AND NOT EXISTS (SELECT 1 FROM public.membres_etablissement me
        WHERE me.user_id=auth.uid() AND me.etablissement_id=v_mission.etablissement_id))
  THEN RAISE EXCEPTION 'Mission indisponible ou accès refusé' USING ERRCODE='42501'; END IF;

  SELECT e.nom INTO v_nom FROM public.etablissements e WHERE e.id=v_mission.etablissement_id;
  RETURN jsonb_build_object(
    'mission',jsonb_build_object('id',v_mission.id,'intitule',v_mission.intitule,
      'etablissement_id',v_mission.etablissement_id,'etablissement_nom',v_nom,
      'statut',v_mission.statut,'mode_attribution',v_mission.mode_attribution,
      'nb_creneaux',v_mission.nb_creneaux,'profession_requise',v_mission.profession_requise,
      'specialite_medicale_requise',v_mission.specialite_medicale_requise,
      'accepte_internes',v_mission.accepte_internes),
    'creneaux',COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'id',mc.id,'mission_id',mc.mission_id,'debut',mc.debut,'fin',mc.fin,
      'est_pause',mc.est_pause,'type_creneau',mc.type_creneau) ORDER BY mc.debut,mc.id)
      FROM public.mission_creneaux mc WHERE mc.mission_id=v_mission.id
        AND mc.type_creneau='PREVISIONNEL' AND mc.est_pause IS FALSE),'[]'::jsonb),
    'candidatures',COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'id',c.id,'soignant_id',c.soignant_id,'message',c.message,'statut',c.statut,'cree_le',c.cree_le,
      'soignant',jsonb_build_object('id',s.id,'prenom',s.prenom,
        'nom',left(COALESCE(s.nom,''),1)||'.','nom_anonymise',true,
        'profession',s.profession,'specialite_medicale',s.specialite_medicale,
        'type_exercice',s.type_exercice,'est_etudiant',s.est_etudiant,
        'internat',private.fn_statut_internat_medical(s.id),
        'score_fiabilite',s.score_fiabilite,'total_missions_terminees',s.total_missions_terminees,
        'note_moyenne',s.note_moyenne,'nb_evaluations',s.nb_evaluations,
        'etudiant_details',s.etudiant_details,'tous_documents_valides',s.tous_documents_valides))
      ORDER BY c.cree_le,c.id)
      FROM public.candidatures c JOIN public.soignants s ON s.id=c.soignant_id
      WHERE c.mission_id=v_mission.id AND s.supprime_le IS NULL
        AND private.fn_comptes_meme_cohorte_test(s.id,v_mission.etablissement_id) IS TRUE),'[]'::jsonb));
END;
$function$;

-- LIVE public.fn_soignant_pour_etablissement: 9ef6f323607bb01b9cd4d4fc0c1f4b49
CREATE OR REPLACE FUNCTION public.fn_soignant_pour_etablissement(p_soignant_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_etab_id UUID := mon_etablissement_id();
    v_a_mission_aujourdhui BOOLEAN;
    v_a_relation_contractuelle BOOLEAN;
BEGIN
    IF NOT est_admin() AND v_etab_id IS NULL THEN
        RETURN jsonb_build_object('error', 'Accès refusé');
    END IF;

    SELECT EXISTS (
        SELECT 1 FROM missions
        WHERE soignant_assigne_id = p_soignant_id
          AND etablissement_id = v_etab_id
          AND statut IN ('ASSIGNEE','EN_COURS','TERMINEE','ABSENCE','LITIGE')
    ) INTO v_a_relation_contractuelle;

    SELECT EXISTS (
        SELECT 1 FROM missions
        WHERE soignant_assigne_id = p_soignant_id
          AND etablissement_id = v_etab_id
          AND statut IN ('ASSIGNEE','EN_COURS')
          AND debut_le::DATE <= CURRENT_DATE + 1
    ) INTO v_a_mission_aujourdhui;

    RETURN (
        SELECT jsonb_build_object(
            'id', id,
            'prenom', prenom,
            'nom', CASE
                WHEN est_admin() OR v_a_relation_contractuelle THEN nom
                ELSE LEFT(COALESCE(nom, ''), 1) || '.'
            END,
            'nom_anonymise', NOT (est_admin() OR v_a_relation_contractuelle),
            'profession', profession::TEXT,
            'specialite_medicale', specialite_medicale,
            'telephone', CASE WHEN v_a_mission_aujourdhui OR est_admin() THEN telephone ELSE NULL END,
            'numero_rpps', numero_rpps,
            'score_fiabilite', score_fiabilite,
            'note_moyenne', note_moyenne,
            'nb_evaluations', nb_evaluations,
            'total_missions_terminees', total_missions_terminees,
            'rpps_verifie', rpps_verifie,
            'tous_documents_valides', tous_documents_valides,
            'avatar_url', avatar_url,
            'type_exercice', COALESCE(type_exercice, 'SALARIE'),
            'bio', bio,
            'annees_experience', annees_experience,
            'specialites', specialites,
            'disponible_urgence', disponible_urgence,
            'est_etudiant', est_etudiant,
            'etudiant_details', etudiant_details,
            'internat', private.fn_statut_internat_medical(id)
        )
        FROM soignants WHERE id = p_soignant_id AND supprime_le IS NULL
    );
END;
$function$;



-- PRÉPARATION NON APPLIQUÉE. Source LIVE relue le 27 octobre 2026.
-- Greffe internat uniquement ; signature, ACL et contexte invoker conservés.
CREATE OR REPLACE FUNCTION private.fn_resultats_filtre_missions(p_filtre_id uuid, p_since timestamp with time zone)
 RETURNS TABLE(mission_id uuid)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
DECLARE f public.filtres_sauvegardes; s public.soignants; profession text; accepted text[]; raw text; rayon numeric; ville text;
BEGIN
 SELECT * INTO f FROM public.filtres_sauvegardes WHERE id=p_filtre_id AND audience='SOIGNANT_RECHERCHE_MISSIONS';
 IF NOT FOUND OR NOT private.fn_filtres_recherche_missions_valides(f.filtres) OR NOT private.fn_destinataire_alerte_actif(f.utilisateur_id) THEN RETURN; END IF;
 SELECT * INTO s FROM public.soignants WHERE id=f.utilisateur_id AND supprime_le IS NULL;
 IF NOT FOUND AND NOT EXISTS(SELECT 1 FROM public.parcours_inscription WHERE user_id=f.utilisateur_id AND type_compte='SOIGNANT') THEN RETURN; END IF;
 profession:=coalesce(s.profession::text,(SELECT donnees->>'profession' FROM public.parcours_inscription WHERE user_id=f.utilisateur_id AND type_compte='SOIGNANT'));
 raw:=trim(coalesce(s.types_contrat_acceptes,''));
 IF raw<>'' THEN
  BEGIN
   IF jsonb_typeof(raw::jsonb)='array' THEN
    IF jsonb_array_length(raw::jsonb)>0 THEN SELECT array_agg(value) INTO accepted FROM jsonb_array_elements_text(raw::jsonb); END IF;
   END IF;
  EXCEPTION WHEN invalid_text_representation THEN NULL; END;
  IF accepted IS NULL THEN SELECT array_agg(trim(x)) INTO accepted FROM unnest(string_to_array(raw,',')) x WHERE trim(x)<>''; END IF;
 END IF;
 IF accepted IS NULL THEN accepted:=CASE s.type_exercice WHEN 'MIXTE' THEN ARRAY['CDD','LIBERAL'] WHEN 'LIBERAL' THEN ARRAY['LIBERAL'] ELSE CASE WHEN s.type_contrat IS NOT NULL THEN ARRAY[s.type_contrat::text] ELSE ARRAY['CDD','VACATION','LIBERAL','SALARIE'] END END; END IF;
 rayon:=coalesce((f.filtres->>'rayonKm')::numeric,s.rayon_deplacement_km,50);
 ville:=lower(trim(coalesce(f.filtres->>'villeRecherche','')));
 RETURN QUERY SELECT m.id FROM public.missions m
 JOIN public.etablissements e ON e.id=m.etablissement_id AND e.supprime_le IS NULL
 CROSS JOIN LATERAL(SELECT coalesce(nullif(m.type_contrat_recherche,''),substring(m.description FROM '\[CONTRAT:(TOUS|SALARIE|LIBERAL)\]'),'TOUS') AS type) contrat
 WHERE m.statut='OUVERTE' AND m.debut_le>=now() AND m.cree_le>p_since AND m.cree_le<=now()
 AND private.fn_destinataire_alerte_actif(e.id)
 AND CASE WHEN s.id IS NULL THEN
   m.soignant_assigne_id IS NULL AND public.fn_mission_publique(m.id) IS NOT NULL
   AND NOT private.fn_mission_lie_compte_test(m.id)
  ELSE private.fn_comptes_meme_cohorte_test(f.utilisateur_id,e.id) END
 AND NOT public.fn_est_exclu(f.utilisateur_id,e.id)
 -- Admission internat commune aussi pour les aperçus et emails de recherches.
 -- Préinscription sans profil : conserve le catalogue public existant.
 AND (s.id IS NULL OR private.fn_internat_compatible(
   private.fn_statut_internat_medical(s.id), m.profession_requise,
   m.specialite_medicale_requise, m.accepte_internes, m.fin_le, m.accepte_non_specialises))
 AND CASE WHEN coalesce(f.filtres->>'profession','')<>'' THEN m.profession_requise::text=f.filtres->>'profession'
  ELSE profession IS NULL OR profession='' OR m.profession_requise::text=profession OR (profession IN ('IADE','IBODE') AND m.profession_requise::text='IDE') END
 AND coalesce(m.taux_horaire_base,0)>=coalesce((f.filtres->>'tauxMin')::numeric,0)
 AND (coalesce((f.filtres->>'urgentesOnly')::boolean,false)=false OR m.est_urgente IS TRUE)
 AND (ville='' OR position(ville IN lower(coalesce(e.adresse_ville,'')))>0 OR starts_with(lower(coalesce(e.adresse_code_postal,'')),ville))
 AND (s.adresse_lat IS NULL OR s.adresse_lng IS NULL OR e.adresse_lat IS NULL OR e.adresse_lng IS NULL OR
  round((6371*2*asin(least(1,sqrt(power(sin(radians(e.adresse_lat-s.adresse_lat)/2),2)+cos(radians(s.adresse_lat))*cos(radians(e.adresse_lat))*power(sin(radians(e.adresse_lng-s.adresse_lng)/2),2)))))::numeric,1)<=rayon)
 AND (contrat.type<>'LIBERAL' OR 'LIBERAL'=ANY(accepted))
 AND (coalesce(f.filtres->>'typeContrat','TOUS')<>'CDD' OR contrat.type<>'LIBERAL')
 AND (coalesce(f.filtres->>'typeContrat','TOUS')<>'LIBERAL' OR contrat.type<>'SALARIE')
 AND private.fn_mission_correspond_horaire(m.id,coalesce(f.filtres->>'horaire','TOUS'));
END $function$
;


-- Projection de découverte bornée au rôle établissement.
-- Corps LIVE conservé sauf ajout de la projection internat dans chaque résultat.
-- Aucun filtre de mission/opt-in ajouté ; p_specialites garde son sens de tags.
-- CREATE OR REPLACE conserve signature et ACL : postgres/authenticated/service_role.
CREATE OR REPLACE FUNCTION public.fn_rechercher_soignants_etab(p_profession text DEFAULT NULL::text, p_specialites text[] DEFAULT NULL::text[], p_ville text DEFAULT NULL::text, p_distance_max_km integer DEFAULT NULL::integer, p_type_exercice text DEFAULT NULL::text, p_note_min numeric DEFAULT NULL::numeric, p_score_min integer DEFAULT NULL::integer, p_experience_min integer DEFAULT NULL::integer, p_disponible_urgence boolean DEFAULT NULL::boolean, p_documents_valides boolean DEFAULT NULL::boolean, p_recherche_texte text DEFAULT NULL::text, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_etab_id uuid;
  v_limit integer;
  v_offset integer;
  v_result jsonb;
BEGIN
  IF NOT public.fn_compte_auth_actif() THEN
    RETURN jsonb_build_object('error','Accès refusé : compte inactif');
  END IF;
  IF NOT est_admin() THEN
    v_etab_id := mon_etablissement_id();
    IF v_etab_id IS NULL OR NOT EXISTS(SELECT 1 FROM public.etablissements e WHERE e.id=v_etab_id AND e.supprime_le IS NULL) THEN
      RETURN jsonb_build_object(
        'error',
        'Accès refusé : étab requis'
      );
    END IF;
  END IF;

  v_limit := LEAST(GREATEST(COALESCE(p_limit, 50), 1), 100);
  v_offset := GREATEST(COALESCE(p_offset, 0), 0);

  WITH with_distance AS (
    SELECT s.*, r.distance_km
    FROM private.fn_resultats_recherche_soignants_etab(
      v_etab_id, p_profession, p_specialites, p_ville, p_distance_max_km,
      p_type_exercice, p_note_min, p_score_min, p_experience_min,
      p_disponible_urgence, p_documents_valides, p_recherche_texte
    ) r
    JOIN public.soignants s ON s.id=r.soignant_id
  ),
  ranked AS (
    SELECT
      *,
      row_number() OVER (
        ORDER BY
          CASE
            WHEN COALESCE(total_missions_terminees, 0) >= 3
              THEN score_fiabilite
            ELSE -1
          END DESC NULLS LAST,
          CASE
            WHEN COALESCE(nb_evaluations, 0) >= 3
              THEN note_moyenne
            ELSE -1
          END DESC NULLS LAST,
          COALESCE(total_missions_terminees, 0) DESC,
          id
      ) AS rn,
      count(*) OVER () AS total_count
    FROM with_distance
  ),
  paged AS (
    SELECT *
    FROM ranked
    WHERE rn > v_offset
      AND rn <= v_offset + v_limit
  )
  SELECT jsonb_build_object(
    'soignants',
    COALESCE(jsonb_agg(jsonb_build_object(
      'id', p.id,
      'prenom', p.prenom,
      'nom_initiale', left(p.nom, 1) || '.',
      'profession', p.profession::text,
      'specialite_medicale', p.specialite_medicale,
      'internat', private.fn_statut_internat_medical(p.id),
      'type_exercice', COALESCE(p.type_exercice, 'SALARIE'),
      'score_fiabilite', CASE
        WHEN COALESCE(p.total_missions_terminees, 0) >= 3
          THEN p.score_fiabilite
        ELSE NULL
      END,
      'note_moyenne', CASE
        WHEN COALESCE(p.nb_evaluations, 0) >= 3
          THEN p.note_moyenne
        ELSE NULL
      END,
      'nb_evaluations', COALESCE(p.nb_evaluations, 0),
      'total_missions_terminees',
        COALESCE(p.total_missions_terminees, 0),
      'annees_experience', p.annees_experience,
      'specialites', COALESCE(p.specialites, ARRAY[]::text[]),
      'bio_extrait', left(COALESCE(p.bio, ''), 200),
      'avatar_url', p.avatar_url,
      'rpps_verifie', COALESCE(p.rpps_verifie, false),
      'tous_documents_valides',
        COALESCE(p.tous_documents_valides, false),
      'disponible_urgence', COALESCE(p.disponible_urgence, false),
      'ville', p.adresse_ville,
      'distance_km', p.distance_km,
      'priorite_missions_urgentes',
        COALESCE(p.priorite_missions_urgentes, false),
      'badge_ambassadeur',
        COALESCE(p.badge_ambassadeur, false)
    ) ORDER BY p.rn), '[]'::jsonb),
    'count_total', COALESCE(max(p.total_count), 0),
    'limit', v_limit,
    'offset', v_offset
  )
  INTO v_result
  FROM paged p;

  RETURN COALESCE(
    v_result,
    jsonb_build_object(
      'soignants', '[]'::jsonb,
      'count_total', 0,
      'limit', v_limit,
      'offset', v_offset
    )
  );
END;
$function$;

-- Registre : uniquement les routines modifiées par ce lot.
UPDATE private.security_definer_inventory SET definition_md5=(SELECT md5(prosrc) FROM pg_proc WHERE oid='private.fn_resultats_filtre_missions(uuid,timestamp with time zone)'::regprocedure),recense_le=now() WHERE signature IN ('private.fn_resultats_filtre_missions(uuid,timestamp with time zone)','private.fn_resultats_filtre_missions(uuid,timestamp with time zone)');
UPDATE private.security_definer_inventory SET definition_md5=(SELECT md5(prosrc) FROM pg_proc WHERE oid='private.fn_soignant_visible_pool_etablissement(uuid,uuid,uuid)'::regprocedure),recense_le=now() WHERE signature IN ('private.fn_soignant_visible_pool_etablissement(uuid,uuid,uuid)','private.fn_soignant_visible_pool_etablissement(uuid,uuid,uuid)');
UPDATE private.security_definer_inventory SET definition_md5=(SELECT md5(prosrc) FROM pg_proc WHERE oid='public.fn_accepter_mission_urgence(uuid)'::regprocedure),recense_le=now() WHERE signature IN ('public.fn_accepter_mission_urgence(uuid)','fn_accepter_mission_urgence(uuid)');
UPDATE private.security_definer_inventory SET definition_md5=(SELECT md5(prosrc) FROM pg_proc WHERE oid='public.fn_admin_moderer_document_internal_20260810(uuid,text,text,jsonb,text)'::regprocedure),recense_le=now() WHERE signature IN ('public.fn_admin_moderer_document_internal_20260810(uuid,text,text,jsonb,text)','fn_admin_moderer_document_internal_20260810(uuid,text,text,jsonb,text)');
UPDATE private.security_definer_inventory SET definition_md5=(SELECT md5(prosrc) FROM pg_proc WHERE oid='public.fn_enregistrer_swipe(uuid,text,text)'::regprocedure),recense_le=now() WHERE signature IN ('public.fn_enregistrer_swipe(uuid,text,text)','fn_enregistrer_swipe(uuid,text,text)');
UPDATE private.security_definer_inventory SET definition_md5=(SELECT md5(prosrc) FROM pg_proc WHERE oid='public.fn_finaliser_attribution_mission(uuid,uuid,text)'::regprocedure),recense_le=now() WHERE signature IN ('public.fn_finaliser_attribution_mission(uuid,uuid,text)','fn_finaliser_attribution_mission(uuid,uuid,text)');
UPDATE private.security_definer_inventory SET definition_md5=(SELECT md5(prosrc) FROM pg_proc WHERE oid='public.fn_finaliser_document_verification(uuid,uuid,uuid,text,text,text,text,text,date,text,text,text,text,text,boolean,boolean,text,text,date,date,jsonb,text,text,numeric,boolean,date,text,text,text,integer,text,date,text,text,date,date,numeric,text)'::regprocedure),recense_le=now() WHERE signature IN ('public.fn_finaliser_document_verification(uuid,uuid,uuid,text,text,text,text,text,date,text,text,text,text,text,boolean,boolean,text,text,date,date,jsonb,text,text,numeric,boolean,date,text,text,text,integer,text,date,text,text,date,date,numeric,text)','fn_finaliser_document_verification(uuid,uuid,uuid,text,text,text,text,text,date,text,text,text,text,text,boolean,boolean,text,text,date,date,jsonb,text,text,numeric,boolean,date,text,text,text,integer,text,date,text,text,date,date,numeric,text)');
UPDATE private.security_definer_inventory SET definition_md5=(SELECT md5(prosrc) FROM pg_proc WHERE oid='public.fn_lire_candidatures_mission_habilitee(uuid)'::regprocedure),recense_le=now() WHERE signature IN ('public.fn_lire_candidatures_mission_habilitee(uuid)','fn_lire_candidatures_mission_habilitee(uuid)');
UPDATE private.security_definer_inventory SET definition_md5=(SELECT md5(prosrc) FROM pg_proc WHERE oid='public.fn_pool_urgence_etablissement(uuid)'::regprocedure),recense_le=now() WHERE signature IN ('public.fn_pool_urgence_etablissement(uuid)','fn_pool_urgence_etablissement(uuid)');
UPDATE private.security_definer_inventory SET definition_md5=(SELECT md5(prosrc) FROM pg_proc WHERE oid='public.fn_postuler_mission(uuid,text,text)'::regprocedure),recense_le=now() WHERE signature IN ('public.fn_postuler_mission(uuid,text,text)','fn_postuler_mission(uuid,text,text)');
UPDATE private.security_definer_inventory SET definition_md5=(SELECT md5(prosrc) FROM pg_proc WHERE oid='public.fn_proposer_mission_soignant(uuid,uuid,text)'::regprocedure),recense_le=now() WHERE signature IN ('public.fn_proposer_mission_soignant(uuid,uuid,text)','fn_proposer_mission_soignant(uuid,uuid,text)');
UPDATE private.security_definer_inventory SET definition_md5=(SELECT md5(prosrc) FROM pg_proc WHERE oid='public.fn_rebooker_soignant(uuid,uuid,timestamp with time zone,timestamp with time zone)'::regprocedure),recense_le=now() WHERE signature IN ('public.fn_rebooker_soignant(uuid,uuid,timestamp with time zone,timestamp with time zone)','fn_rebooker_soignant(uuid,uuid,timestamp with time zone,timestamp with time zone)');
UPDATE private.security_definer_inventory SET definition_md5=(SELECT md5(prosrc) FROM pg_proc WHERE oid='public.fn_rechercher_soignants_etab(text,text[],text,integer,text,numeric,integer,integer,boolean,boolean,text,integer,integer)'::regprocedure),recense_le=now() WHERE signature IN ('public.fn_rechercher_soignants_etab(text,text[],text,integer,text,numeric,integer,integer,boolean,boolean,text,integer,integer)','fn_rechercher_soignants_etab(text,text[],text,integer,text,numeric,integer,integer,boolean,boolean,text,integer,integer)');
UPDATE private.security_definer_inventory SET definition_md5=(SELECT md5(prosrc) FROM pg_proc WHERE oid='public.fn_soignant_eligible_mission(uuid,uuid,boolean)'::regprocedure),recense_le=now() WHERE signature IN ('public.fn_soignant_eligible_mission(uuid,uuid,boolean)','fn_soignant_eligible_mission(uuid,uuid,boolean)');
UPDATE private.security_definer_inventory SET definition_md5=(SELECT md5(prosrc) FROM pg_proc WHERE oid='public.fn_soignant_pour_etablissement(uuid)'::regprocedure),recense_le=now() WHERE signature IN ('public.fn_soignant_pour_etablissement(uuid)','fn_soignant_pour_etablissement(uuid)');
INSERT INTO private.security_definer_inventory(signature,categorie,definition_md5,justification,recense_le) SELECT p.oid::regprocedure::text,'SERVICE_ONLY_REVOQUE',md5(p.prosrc),'Projection interne bornée ; lecture de la preuve courante, accès clients révoqué.',now() FROM pg_proc p WHERE p.oid='private.fn_qualification_medicale_actuelle(uuid)'::regprocedure;
INSERT INTO private.security_definer_inventory(signature,categorie,definition_md5,justification,recense_le) SELECT p.oid::regprocedure::text,'ADMIN_EST_ADMIN_VALIDE',md5(p.prosrc),'auth.uid et est_admin LIVE avant toute lecture de preuve.',now() FROM pg_proc p WHERE p.oid='public.fn_admin_lire_qualification_medicale(uuid)'::regprocedure;
INSERT INTO private.security_definer_inventory(signature,categorie,definition_md5,justification,recense_le) SELECT p.oid::regprocedure::text,'ADMIN_EST_ADMIN_VALIDE',md5(p.prosrc),'Administrateur validé ; preuve CAS, choix et audit atomiques.',now() FROM pg_proc p WHERE p.oid='public.fn_admin_decider_qualification_medicale(uuid,uuid,text,uuid,text,text,boolean,boolean,text)'::regprocedure;
INSERT INTO private.security_definer_inventory(signature,categorie,definition_md5,justification,recense_le) SELECT p.oid::regprocedure::text,'ADMIN_EST_ADMIN_VALIDE',md5(p.prosrc),'Administrateur validé ; révocation contextualisée et audit atomique.',now() FROM pg_proc p WHERE p.oid='public.fn_admin_revoquer_qualification_medicale(uuid,uuid,text)'::regprocedure;
INSERT INTO private.security_definer_inventory(signature,categorie,definition_md5,justification,recense_le) SELECT p.oid::regprocedure::text,'SERVICE_ONLY_REVOQUE',md5(p.prosrc),'Trigger uniquement ; nouvelle admission vérifiée sous verrou profil.',now() FROM pg_proc p WHERE p.oid='private.fn_guard_candidature_internat()'::regprocedure;
INSERT INTO private.security_definer_inventory(signature,categorie,definition_md5,justification,recense_le) SELECT p.oid::regprocedure::text,'SERVICE_ONLY_REVOQUE',md5(p.prosrc),'Trigger uniquement ; contrôle de la preuve sans réécrire les attributions anciennes.',now() FROM pg_proc p WHERE p.oid='private.fn_guard_nouvelle_attribution_internat()'::regprocedure;
INSERT INTO private.security_definer_inventory(signature,categorie,definition_md5,justification,recense_le) SELECT p.oid::regprocedure::text,'MIXTE_TENANT_ADMIN',md5(p.prosrc),'RLS restrictive bornée au soignant courant ; accès tenant/admin conservés.',now() FROM pg_proc p WHERE p.oid='private.fn_mission_visible_internat(public.type_profession,text,boolean,timestamptz,uuid,public.statut_mission,uuid,boolean)'::regprocedure;
INSERT INTO private.security_definer_inventory(signature,categorie,definition_md5,justification,recense_le) SELECT p.oid::regprocedure::text,'SERVICE_ONLY_REVOQUE',md5(p.prosrc),'Trigger uniquement ; intention privée transactionnelle et permission établissement.',now() FROM pg_proc p WHERE p.oid='private.fn_appliquer_choix_internat()'::regprocedure;
INSERT INTO private.security_definer_inventory(signature,categorie,definition_md5,justification,recense_le) SELECT p.oid::regprocedure::text,'RPC_UTILISATEUR_AUTH_INTERNE',md5(p.prosrc),'Compte actif puis création LIVE contrôlant le tenant, choix explicite interne.',now() FROM pg_proc p WHERE p.oid='public.fn_creer_mission_multi_jours_v4(text,text,public.type_profession,text,numeric,boolean,integer,text,text,boolean,jsonb,text,text,numeric,text,boolean)'::regprocedure;
INSERT INTO private.security_definer_inventory(signature,categorie,definition_md5,justification,recense_le) SELECT p.oid::regprocedure::text,'RPC_UTILISATEUR_AUTH_INTERNE',md5(p.prosrc),'Compte actif et permission mission du tenant avant modification LIVE.',now() FROM pg_proc p WHERE p.oid='public.fn_modifier_mission_etablissement_v5(uuid,text,text,text,public.type_profession,numeric,boolean,integer,text,text,text,boolean,jsonb,text,boolean)'::regprocedure;
