-- L'attribution réussissait mais le garde d'identité annulait parraine_par.
-- Aucun changement de prime, de cohorte ou de qualification. Contexte dédié
-- transactionnel, lié à l'UUID exact du parrainage et refermé après un UPDATE.

-- Aucune correction silencieuse des données : si des doubles attributions sont
-- apparues depuis la revue, interrompre tout le lot avant la modification des RPC.
DO $unicite$
DECLARE
  v_colonne smallint;
  v_contrainte pg_catalog.pg_constraint%ROWTYPE;
BEGIN
  -- Le contrôle et le DDL appartiennent au même DO, y compris lors d'un rejeu
  -- isolé par la validation CI : aucune dépendance à un BEGIN externe.
  LOCK TABLE public.parrainages IN SHARE ROW EXCLUSIVE MODE;
  IF EXISTS (SELECT 1 FROM public.parrainages GROUP BY filleul_id HAVING count(*) > 1) THEN
    RAISE EXCEPTION USING ERRCODE = '23505',
      MESSAGE = 'Plusieurs parrainages pour un même filleul : revue des données requise, aucune donnée supprimée';
  END IF;
  SELECT a.attnum INTO v_colonne FROM pg_catalog.pg_attribute a
  WHERE a.attrelid = 'public.parrainages'::regclass
    AND a.attname = 'filleul_id' AND NOT a.attisdropped;
  IF v_colonne IS NULL THEN RAISE EXCEPTION 'Colonne filleul_id introuvable'; END IF;

  SELECT c.* INTO v_contrainte FROM pg_catalog.pg_constraint c
  WHERE c.conrelid = 'public.parrainages'::regclass
    AND c.conname = 'parrainages_filleul_id_key';
  IF FOUND THEN
    IF v_contrainte.contype IS DISTINCT FROM 'u'
      OR v_contrainte.conkey IS DISTINCT FROM ARRAY[v_colonne]::smallint[]
      OR v_contrainte.convalidated IS DISTINCT FROM true
      OR v_contrainte.condeferrable IS DISTINCT FROM false
      OR v_contrainte.condeferred IS DISTINCT FROM false THEN
      RAISE EXCEPTION 'Contrainte parrainages_filleul_id_key existante incompatible : revue du schéma requise';
    END IF;
  ELSE
    ALTER TABLE public.parrainages ADD CONSTRAINT parrainages_filleul_id_key UNIQUE (filleul_id);
  END IF;
END;
$unicite$;

-- Le frontend attribue uniquement via la RPC contrôlée. Conserver les SELECT
-- existants et les droits service_role ; fermer la voie INSERT directe.
REVOKE INSERT ON TABLE public.parrainages FROM PUBLIC, anon, authenticated;
DO $droits$
BEGIN
  IF has_table_privilege('authenticated', 'public.parrainages', 'INSERT')
    OR has_any_column_privilege('authenticated', 'public.parrainages', 'INSERT')
    OR has_table_privilege('anon', 'public.parrainages', 'INSERT')
    OR has_any_column_privilege('anon', 'public.parrainages', 'INSERT') THEN
    RAISE EXCEPTION 'Droit INSERT résiduel sur parrainages : vérifier les privilèges hérités';
  END IF;
END;
$droits$;

CREATE OR REPLACE FUNCTION "public"."fn_appliquer_parrainage"("p_code" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_parrain RECORD;
  v_filleul_id UUID := auth.uid();
  v_nb_filleuls_valides INT;
  v_parrainage_id UUID;
  v_ip TEXT;
  v_user_agent TEXT;
  v_contexte_parrainage text := current_setting('jolene.parrainage_attribution_id', true);
  v_prime integer := (public.fn_param_num('prime_parrainage_eur', 50))::integer;
BEGIN
  IF v_filleul_id IS NULL THEN RETURN '{"error":"Non authentifié"}'::JSONB; END IF;
  IF NOT public.fn_compte_auth_actif() THEN RETURN '{"error":"Compte suspendu, supprimé ou désactivé"}'::jsonb; END IF;
  -- Sérialiser les attributions d'un même filleul avant le contrôle d'unicité.
  PERFORM 1 FROM public.soignants WHERE id = v_filleul_id AND supprime_le IS NULL
    AND statut_compte NOT IN ('SUSPENDU', 'SUPPRIME') FOR UPDATE;
  IF NOT FOUND THEN RETURN '{"error":"Profil soignant introuvable"}'::jsonb; END IF;
  SELECT * INTO v_parrain FROM soignants WHERE code_parrainage = UPPER(TRIM(p_code)) AND supprime_le IS NULL;
  IF v_parrain IS NULL THEN RETURN '{"error":"Code de parrainage invalide"}'::JSONB; END IF;
  IF v_parrain.id = v_filleul_id THEN RETURN '{"error":"Vous ne pouvez pas vous parrainer vous-même"}'::JSONB; END IF;
  SELECT COUNT(*) INTO v_nb_filleuls_valides FROM parrainages WHERE parrain_id = v_parrain.id AND statut IN ('VALIDE','FILLEUL_ACTIF','VALIDE_EN_ATTENTE_SEUIL','PRIME_VERSEE');
  IF v_nb_filleuls_valides >= 20 THEN RETURN '{"error":"Le parrain a atteint la limite de 20 filleuls validés"}'::JSONB; END IF;
  IF EXISTS (SELECT 1 FROM parrainages WHERE filleul_id = v_filleul_id) THEN RETURN '{"error":"Vous avez déjà appliqué un code de parrainage"}'::JSONB; END IF;
  INSERT INTO parrainages (parrain_id, filleul_id, code_parrainage, statut) VALUES (v_parrain.id, v_filleul_id, UPPER(TRIM(p_code)), 'EN_ATTENTE') RETURNING id INTO v_parrainage_id;
  -- Contexte limité à la relation qui vient d'être créée ; aucune permission
  -- générale de modifier la qualification, le score ou le compte Stripe.
  PERFORM set_config('jolene.parrainage_attribution_id', v_parrainage_id::text, true);
  BEGIN
    UPDATE soignants SET parraine_par = v_parrain.id WHERE id = v_filleul_id AND parraine_par IS NULL;
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('jolene.parrainage_attribution_id', COALESCE(v_contexte_parrainage, ''), true);
    RAISE;
  END;
  PERFORM set_config('jolene.parrainage_attribution_id', COALESCE(v_contexte_parrainage, ''), true);
  IF NOT EXISTS (SELECT 1 FROM soignants WHERE id = v_filleul_id AND parraine_par = v_parrain.id) THEN
    RAISE EXCEPTION 'Attribution du parrain non persistée';
  END IF;
  BEGIN
    v_ip := COALESCE(current_setting('request.headers', true)::json->>'x-forwarded-for', current_setting('request.headers', true)::json->>'x-real-ip', 'unknown');
    v_user_agent := COALESCE(current_setting('request.headers', true)::json->>'user-agent', 'unknown');
  EXCEPTION WHEN OTHERS THEN v_ip := 'unknown'; v_user_agent := 'unknown';
  END;
  IF v_ip <> 'unknown' THEN
    DECLARE v_parrain_last_ip TEXT;
    BEGIN
      SELECT (details->>'ip')::text INTO v_parrain_last_ip FROM journaux_audit WHERE acteur_id = v_parrain.id AND action = 'CONNEXION' ORDER BY cree_le DESC LIMIT 1;
      IF v_parrain_last_ip IS NOT NULL AND v_parrain_last_ip = v_ip THEN
        INSERT INTO parrainage_fraude_signals (parrainage_id, type, detail) VALUES (v_parrainage_id, 'MEME_IP', jsonb_build_object('ip', v_ip, 'parrain_id', v_parrain.id, 'filleul_id', v_filleul_id));
      END IF;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END IF;
  INSERT INTO parrainage_fraude_signals (parrainage_id, type, detail) VALUES (v_parrainage_id, 'MEME_DEVICE', jsonb_build_object('ip_filleul', v_ip, 'user_agent_filleul', v_user_agent, 'filleul_id', v_filleul_id, 'parrain_id', v_parrain.id));
  RETURN jsonb_build_object('success', true, 'message', 'Code accepté ! Votre prime de ' || v_prime || '€ sera versée après votre 1ère mission terminée et 100€ de commission encaissée par Jolene.');
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_protect_soignant_verification()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_attribution_autorisee boolean;
BEGIN
  IF auth.role() = 'service_role' OR auth.uid() IS NULL OR public.est_admin() THEN RETURN NEW; END IF;
  IF COALESCE(current_setting('jolene.system_update', true), '') = 'true' THEN RETURN NEW; END IF;

  -- Seul le premier lien du compte authentifié, adossé à la relation exacte
  -- créée par la RPC, peut franchir la protection de parraine_par.
  v_attribution_autorisee := OLD.id = auth.uid()
    AND OLD.parraine_par IS NULL AND NEW.parraine_par IS NOT NULL
    AND EXISTS (SELECT 1 FROM public.parrainages p
      WHERE p.id::text = current_setting('jolene.parrainage_attribution_id', true)
        AND p.filleul_id = OLD.id AND p.parrain_id = NEW.parraine_par
        AND p.statut = 'EN_ATTENTE');

  IF COALESCE(current_setting('jolene.rpc_update', true), '') = 'true' THEN
    IF OLD.id = auth.uid() THEN
      NEW.diplome_verifie := OLD.diplome_verifie;
      NEW.identite_verifiee := OLD.identite_verifiee;
      NEW.tous_documents_valides := OLD.tous_documents_valides;
      NEW.rpps_verifie := OLD.rpps_verifie;
      NEW.rpps_verifie_le := OLD.rpps_verifie_le;
      NEW.rpps_nom_api := OLD.rpps_nom_api;
      NEW.rpps_prenom_api := OLD.rpps_prenom_api;
      NEW.rpps_profession_api := OLD.rpps_profession_api;
      NEW.statut_verification_aria := OLD.statut_verification_aria;
      NEW.coherence_identite := OLD.coherence_identite;
      NEW.coherence_details := OLD.coherence_details;
      NEW.scolarite_formation := OLD.scolarite_formation;
      NEW.scolarite_annee_validee := OLD.scolarite_annee_validee;
      NEW.scolarite_profession_autorisee := OLD.scolarite_profession_autorisee;
      NEW.scolarite_verifiee := OLD.scolarite_verifiee;
      NEW.scolarite_verifiee_le := OLD.scolarite_verifiee_le;
      NEW.licence_remplacement_verifiee := OLD.licence_remplacement_verifiee;
      NEW.licence_remplacement_le := OLD.licence_remplacement_le;
      NEW.licence_remplacement_valide_jusqua := OLD.licence_remplacement_valide_jusqua;
      NEW.licence_remplacement_specialite := OLD.licence_remplacement_specialite;
      IF OLD.profession IS NOT NULL THEN NEW.profession := OLD.profession; END IF;
      NEW.score_fiabilite := OLD.score_fiabilite;
      NEW.note_moyenne := OLD.note_moyenne;
      NEW.total_absences := OLD.total_absences;
      NEW.total_retards_pointage := OLD.total_retards_pointage;
      NEW.total_missions_annulees := OLD.total_missions_annulees;
      NEW.total_missions_terminees := OLD.total_missions_terminees;
      NEW.heures_cumulees := OLD.heures_cumulees;
      NEW.heures_plateforme := OLD.heures_plateforme;
      NEW.stripe_account_id := OLD.stripe_account_id;
      NEW.supprime_le := OLD.supprime_le;
      NEW.parraine_par := CASE WHEN v_attribution_autorisee THEN NEW.parraine_par ELSE OLD.parraine_par END;
      IF OLD.rpps_verifie IS TRUE THEN NEW.numero_rpps := OLD.numero_rpps; END IF;
    END IF;
    RETURN NEW;
  END IF;

  IF OLD.id = auth.uid() THEN
    NEW.diplome_verifie := OLD.diplome_verifie;
    NEW.identite_verifiee := OLD.identite_verifiee;
    NEW.tous_documents_valides := OLD.tous_documents_valides;
    NEW.rpps_verifie := OLD.rpps_verifie;
    NEW.rpps_verifie_le := OLD.rpps_verifie_le;
    NEW.rpps_nom_api := OLD.rpps_nom_api;
    NEW.rpps_prenom_api := OLD.rpps_prenom_api;
    NEW.rpps_profession_api := OLD.rpps_profession_api;
    NEW.statut_verification_aria := OLD.statut_verification_aria;
    NEW.coherence_identite := OLD.coherence_identite;
    NEW.coherence_details := OLD.coherence_details;
    NEW.scolarite_formation := OLD.scolarite_formation;
    NEW.scolarite_annee_validee := OLD.scolarite_annee_validee;
    NEW.scolarite_profession_autorisee := OLD.scolarite_profession_autorisee;
    NEW.scolarite_verifiee := OLD.scolarite_verifiee;
    NEW.scolarite_verifiee_le := OLD.scolarite_verifiee_le;
    NEW.licence_remplacement_verifiee := OLD.licence_remplacement_verifiee;
    NEW.licence_remplacement_le := OLD.licence_remplacement_le;
    NEW.licence_remplacement_valide_jusqua := OLD.licence_remplacement_valide_jusqua;
    NEW.licence_remplacement_specialite := OLD.licence_remplacement_specialite;
    IF OLD.rpps_verifie IS TRUE THEN NEW.numero_rpps := OLD.numero_rpps; END IF;
    IF OLD.profession IS NOT NULL THEN NEW.profession := OLD.profession; END IF;
    NEW.type_exercice := OLD.type_exercice;
    NEW.statut_liberal := OLD.statut_liberal;
    NEW.score_fiabilite := OLD.score_fiabilite;
    NEW.note_moyenne := OLD.note_moyenne;
    NEW.total_absences := OLD.total_absences;
    NEW.total_retards_pointage := OLD.total_retards_pointage;
    NEW.total_missions_annulees := OLD.total_missions_annulees;
    NEW.total_missions_terminees := OLD.total_missions_terminees;
    NEW.heures_cumulees := OLD.heures_cumulees;
    NEW.heures_plateforme := OLD.heures_plateforme;
    NEW.eligible_conversion_3200h := OLD.eligible_conversion_3200h;
    NEW.validation_3200h_statut := OLD.validation_3200h_statut;
    NEW.stripe_account_id := OLD.stripe_account_id;
    NEW.supprime_le := OLD.supprime_le;
    NEW.parraine_par := CASE WHEN v_attribution_autorisee THEN NEW.parraine_par ELSE OLD.parraine_par END;
  END IF;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_protect_soignant_verification() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_protect_soignant_verification() TO service_role;

REVOKE ALL ON FUNCTION public.fn_appliquer_parrainage(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_appliquer_parrainage(text) TO authenticated, service_role;

UPDATE private.security_definer_inventory i
SET definition_md5 = md5(p.prosrc), recense_le = now()
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND ((i.signature = 'fn_appliquer_parrainage(text)' AND p.oid = 'public.fn_appliquer_parrainage(text)'::regprocedure)
    OR (i.signature = 'fn_protect_soignant_verification()' AND p.oid = 'public.fn_protect_soignant_verification()'::regprocedure));

