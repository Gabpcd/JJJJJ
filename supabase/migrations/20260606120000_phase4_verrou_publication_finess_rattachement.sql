-- PHASE 4 (point 1) — Verrou de publication symétrique au soignant.
-- Un établissement ne peut publier de mission que si, en plus du socle existant
-- (statut_verification / peut_publier_missions / contrat / factures / suspension
-- paiement), son numéro FINESS ET le rattachement de son représentant sont vérifiés.
-- C'est le pendant exact du soignant non vérifié qui ne peut pas candidater.
--
-- Trois apports :
--   1) Helper UNIFIÉ fn_blocage_publication_etab centralisant tous les contrôles
--      (renvoie NULL si autorisé, sinon le JSONB d'erreur).
--   2) fn_creer_mission ET fn_creer_serie l'appellent — fn_creer_serie n'avait
--      AUCUN contrôle de vérification jusqu'ici (un établissement non vérifié
--      pouvait publier en masse via la série : trou de sécurité corrigé).
--   3) Antériorité : les établissements déjà vérifiés sous l'ancien socle
--      (statut_verification='VERIFIE') sont rattachés en méthode ADMIN afin de
--      ne casser aucune publication en production au lancement.

-- ── 1) Antériorité (grandfathering) ────────────────────────────────────────────
-- Les établissements déjà vérifiés conservent leur droit de publier : on marque
-- FINESS + rattachement vérifiés (méthode ADMIN = validation héritée du socle
-- manuel). On force TRUE — les colonnes ont une valeur par défaut false (pas NULL),
-- et aucun établissement n'a encore été vérifié par le dispositif en production,
-- donc il n'y a aucune vérification réelle à préserver.
UPDATE public.etablissements SET
  finess_verifie          = true,
  finess_verifie_le       = COALESCE(finess_verifie_le, now()),
  rattachement_methode    = COALESCE(rattachement_methode, 'ADMIN'),
  rattachement_verifie    = true,
  rattachement_verifie_le = COALESCE(rattachement_verifie_le, now())
WHERE statut_verification = 'VERIFIE'
  AND (finess_verifie IS NOT TRUE OR rattachement_verifie IS NOT TRUE);

-- ── 2) Helper unifié ───────────────────────────────────────────────────────────
-- Renvoie NULL si l'établissement est autorisé à publier, sinon un objet JSONB
-- {error, message, …} décrivant le blocage. est_admin() court-circuite (bypass).
CREATE OR REPLACE FUNCTION public.fn_blocage_publication_etab(p_etab_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v RECORD;
BEGIN
  IF est_admin() THEN
    RETURN NULL;
  END IF;

  IF p_etab_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Acces refuse');
  END IF;

  SELECT peut_publier_missions, statut_verification, contrat_valide,
         bloque_auto_le, bloque_auto_raisons,
         finess_verifie, rattachement_verifie
    INTO v
  FROM public.etablissements WHERE id = p_etab_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Etablissement introuvable');
  END IF;

  -- 2.1) Socle de vérification historique
  IF v.peut_publier_missions IS NOT TRUE THEN
    IF v.statut_verification = 'EN_ATTENTE' THEN
      RETURN jsonb_build_object('error', 'Votre etablissement est en attente de verification. Vous pourrez publier des missions une fois verifie.');
    ELSIF v.statut_verification = 'REJETE' THEN
      RETURN jsonb_build_object('error', 'Votre etablissement a ete rejete. Contactez support@jolene.app.');
    ELSIF v.statut_verification = 'SUSPENDU' THEN
      RETURN jsonb_build_object('error', 'Votre compte est suspendu.');
    ELSE
      RETURN jsonb_build_object('error', 'Votre etablissement doit etre verifie avant de publier des missions.');
    END IF;
  END IF;

  -- 2.2) NOUVEAU — symétrie soignant : FINESS + rattachement représentant vérifiés
  IF v.finess_verifie IS NOT TRUE OR v.rattachement_verifie IS NOT TRUE THEN
    RETURN jsonb_build_object(
      'error', 'VERIFICATION_INCOMPLETE',
      'message', 'La verification de votre etablissement est incomplete : le numero FINESS et le rattachement de votre representant doivent etre verifies avant de publier des missions.',
      'finess_verifie', COALESCE(v.finess_verifie, false),
      'rattachement_verifie', COALESCE(v.rattachement_verifie, false)
    );
  END IF;

  -- 2.3) Suspension automatique pour retards de paiement
  IF v.bloque_auto_le IS NOT NULL THEN
    RETURN jsonb_build_object(
      'error', 'PUBLICATION_SUSPENDUE',
      'message', 'Publication de nouvelles missions suspendue en raison de retards de paiement. Regularisez vos obligations pour reactiver votre compte.',
      'bloque_auto_le', v.bloque_auto_le,
      'raisons', v.bloque_auto_raisons
    );
  END IF;

  -- 2.4) Contrat de service Jolene
  IF v.contrat_valide IS NOT TRUE THEN
    RETURN jsonb_build_object('error', 'Votre contrat de service Jolene doit etre valide avant de publier des missions.');
  END IF;

  -- 2.5) Factures impayées échues
  IF EXISTS (
    SELECT 1 FROM public.factures
    WHERE etablissement_id = p_etab_id
      AND statut IN ('EMISE', 'EN_RETARD')
      AND date_echeance < CURRENT_DATE
  ) THEN
    RETURN jsonb_build_object('error', 'Vous avez des factures impayees. Veuillez regulariser.');
  END IF;

  RETURN NULL;
END;
$function$;

-- ── 3) fn_creer_mission — délègue au helper unifié ──────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_creer_mission(
  p_intitule text,
  p_description text DEFAULT NULL::text,
  p_profession_requise type_profession DEFAULT NULL::type_profession,
  p_service text DEFAULT NULL::text,
  p_debut_le timestamp with time zone DEFAULT NULL::timestamp with time zone,
  p_fin_le timestamp with time zone DEFAULT NULL::timestamp with time zone,
  p_taux_horaire_base numeric DEFAULT NULL::numeric,
  p_est_urgente boolean DEFAULT false,
  p_niveau_urgence integer DEFAULT 0,
  p_mode_attribution text DEFAULT 'PREMIER_ARRIVE'::text,
  p_specialite_medicale_requise text DEFAULT NULL::text,
  p_accepte_non_specialises boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_etab_id UUID;
    v_blocage JSONB;
    v_mission_id UUID;
    v_mode TEXT;
BEGIN
    v_etab_id := mon_etablissement_id();
    IF v_etab_id IS NULL AND NOT est_admin() THEN
        RETURN '{"error":"Acces refuse"}'::JSONB;
    END IF;

    -- Contrôles de publication centralisés (socle + FINESS/rattachement + paiement)
    v_blocage := fn_blocage_publication_etab(v_etab_id);
    IF v_blocage IS NOT NULL THEN
        RETURN v_blocage;
    END IF;

    IF p_intitule IS NULL OR p_profession_requise IS NULL OR p_debut_le IS NULL OR p_fin_le IS NULL OR p_taux_horaire_base IS NULL THEN
        RETURN '{"error":"Champs obligatoires manquants."}'::JSONB;
    END IF;
    IF p_fin_le <= p_debut_le THEN
        RETURN '{"error":"La fin doit etre apres le debut."}'::JSONB;
    END IF;
    IF p_debut_le < NOW() AND NOT est_admin() THEN
        RETURN '{"error":"La mission ne peut pas commencer dans le passe."}'::JSONB;
    END IF;

    v_mode := COALESCE(p_mode_attribution, 'PREMIER_ARRIVE');
    IF v_mode NOT IN ('PREMIER_ARRIVE', 'CANDIDATURE') THEN
        v_mode := 'PREMIER_ARRIVE';
    END IF;

    PERFORM set_config('jolene.creer_mission_context', 'true', true);

    INSERT INTO missions (
        etablissement_id, intitule, description,
        profession_requise, service, debut_le, fin_le,
        taux_horaire_base, est_urgente, niveau_urgence, mode_attribution,
        specialite_medicale_requise, accepte_non_specialises
    ) VALUES (
        v_etab_id, p_intitule, p_description,
        p_profession_requise, p_service, p_debut_le, p_fin_le,
        p_taux_horaire_base, p_est_urgente,
        CASE WHEN p_est_urgente THEN p_niveau_urgence ELSE 0 END,
        v_mode,
        p_specialite_medicale_requise, p_accepte_non_specialises
    ) RETURNING id INTO v_mission_id;

    RETURN jsonb_build_object('success', true, 'mission_id', v_mission_id);
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$function$;

-- ── 4) fn_creer_serie — ajoute le verrou (auparavant ABSENT) ────────────────────
CREATE OR REPLACE FUNCTION public.fn_creer_serie(
  p_intitule text,
  p_description text DEFAULT NULL::text,
  p_profession_requise type_profession DEFAULT NULL::type_profession,
  p_service text DEFAULT NULL::text,
  p_taux_horaire_base numeric DEFAULT NULL::numeric,
  p_est_urgente boolean DEFAULT false,
  p_niveau_urgence integer DEFAULT 0,
  p_missions jsonb DEFAULT '[]'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_etablissement_id uuid;
  v_blocage jsonb;
  v_count integer;
  v_mission jsonb;
  v_created_ids uuid[] := '{}';
  v_mission_id uuid;
BEGIN
  v_etablissement_id := mon_etablissement_id();
  IF v_etablissement_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Établissement non trouvé.');
  END IF;

  -- Contrôles de publication centralisés (socle + FINESS/rattachement + paiement).
  -- Note : ce verrou n'existait pas dans la série — un établissement non vérifié
  -- pouvait publier en masse en contournant fn_creer_mission. Corrigé.
  v_blocage := fn_blocage_publication_etab(v_etablissement_id);
  IF v_blocage IS NOT NULL THEN
    RETURN (v_blocage - 'error') || jsonb_build_object('success', false, 'error', v_blocage->>'error');
  END IF;

  -- Validation des champs obligatoires
  IF p_intitule IS NULL OR p_profession_requise IS NULL OR p_taux_horaire_base IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Champs obligatoires manquants.');
  END IF;

  -- Max 30 créneaux par série
  v_count := jsonb_array_length(p_missions);
  IF v_count = 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Aucun créneau fourni.');
  END IF;
  IF v_count > 30 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Maximum 30 créneaux par série.');
  END IF;

  -- Insertion de toutes les missions dans la même transaction
  FOR v_mission IN SELECT * FROM jsonb_array_elements(p_missions)
  LOOP
    INSERT INTO missions (
      etablissement_id, intitule, description, profession_requise, service,
      debut_le, fin_le, taux_horaire_base, est_urgente, niveau_urgence
    ) VALUES (
      v_etablissement_id,
      p_intitule,
      p_description,
      p_profession_requise,
      p_service,
      (v_mission->>'debut')::timestamptz,
      (v_mission->>'fin')::timestamptz,
      p_taux_horaire_base,
      p_est_urgente,
      CASE WHEN p_est_urgente THEN p_niveau_urgence ELSE 0 END
    )
    RETURNING id INTO v_mission_id;
    v_created_ids := v_created_ids || v_mission_id;
  END LOOP;

  RETURN jsonb_build_object('success', true, 'count', v_count, 'mission_ids', to_jsonb(v_created_ids));
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$function$;
