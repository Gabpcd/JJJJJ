-- La migration 20260804154807 a été appliquée sur le staging avant ses deux
-- derniers commits. Comme sa version était déjà inscrite dans le registre,
-- Supabase n'a pas rejoué les définitions modifiées. Cette migration forward
-- only réaligne le staging sur les définitions live de production, sans
-- rejouer les backfills ni les envois d'e-mails de la migration d'origine.

CREATE OR REPLACE FUNCTION public.dec_valider_compatibilite_mission_liberal()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $body$
DECLARE
  v_type_etab text;
  v_est_public boolean;
  v_mode jsonb;
  v_liberal_interdit boolean;
BEGIN
  SELECT type::text, COALESCE(est_secteur_public, false)
    INTO v_type_etab, v_est_public
    FROM public.etablissements
   WHERE id = NEW.etablissement_id;

  IF NEW.profession_requise IS NULL OR v_type_etab IS NULL THEN
    RETURN NEW;
  END IF;

  v_mode := public.fn_mode_exercice(
    NEW.profession_requise::text,
    v_type_etab,
    CASE WHEN v_est_public THEN 'PUBLIC' ELSE NULL END
  );

  v_liberal_interdit :=
    COALESCE(v_mode->>'niveau', 'BLOQUE') = 'BLOQUE'
    OR (
      NEW.profession_requise::text IN ('IADE', 'IBODE')
      AND COALESCE(v_mode->>'niveau', 'NON_PROPOSE') <> 'AUTORISE'
    );

  -- Un choix explicite interdit doit être refusé, afin que l'interface ne
  -- puisse jamais annoncer qu'une édition libérale a réussi en la mutant.
  IF NEW.type_contrat_recherche = 'LIBERAL' AND v_liberal_interdit THEN
    RAISE EXCEPTION '%', COALESCE(
      v_mode->>'source_libelle',
      'Le mode liberal est indisponible pour cette mission.'
    );
  END IF;

  -- « Tous » reste un choix neutre lorsqu'il est possible. Pour une cellule
  -- réellement interdite, le repli salarié historique reste explicite.
  IF NEW.type_contrat_recherche = 'TOUS' AND v_liberal_interdit THEN
    NEW.type_contrat_recherche := 'SALARIE';
  END IF;

  RETURN NEW;
END;
$body$;

REVOKE ALL ON FUNCTION public.dec_valider_compatibilite_mission_liberal()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.dec_valider_compatibilite_mission_liberal()
  TO service_role;

CREATE OR REPLACE FUNCTION public.fn_resoudre_contrat_mission(
  p_mission_id uuid,
  p_soignant_id uuid,
  p_choix_contrat text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path TO 'pg_catalog', 'public'
AS $body$
DECLARE
  v_mission record;
  v_soignant record;
  v_etablissement record;
  v_recherche text;
  v_choix text;
  v_mode jsonb;
  v_liberal_verifie boolean := false;
BEGIN
  SELECT id, profession_requise, type_contrat_recherche, etablissement_id
    INTO v_mission
  FROM public.missions
  WHERE id = p_mission_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Mission introuvable');
  END IF;

  SELECT
    id,
    COALESCE(type_exercice, 'SALARIE') AS type_exercice,
    preference_contrat_mixte
  INTO v_soignant
  FROM public.soignants
  WHERE id = p_soignant_id
    AND supprime_le IS NULL;
  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'ok', false,
      'error', 'Profil soignant introuvable'
    );
  END IF;

  SELECT
    type::text AS type_etablissement,
    COALESCE(est_secteur_public, false) AS est_public
  INTO v_etablissement
  FROM public.etablissements
  WHERE id = v_mission.etablissement_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'ok', false,
      'error', 'Établissement introuvable'
    );
  END IF;

  IF NOT private.fn_comptes_meme_cohorte_test(
    p_soignant_id,
    v_mission.etablissement_id
  ) THEN
    RETURN jsonb_build_object(
      'ok', false,
      'error', 'Mission indisponible pour ce compte'
    );
  END IF;

  v_liberal_verifie :=
    public.fn_soignant_liberal_actif_verifie(p_soignant_id);

  IF p_choix_contrat IS NOT NULL
     AND upper(p_choix_contrat) NOT IN ('SALARIE', 'LIBERAL') THEN
    RETURN jsonb_build_object(
      'ok', false,
      'error', 'Choix de contrat invalide'
    );
  END IF;

  v_recherche := CASE
    WHEN upper(COALESCE(
      v_mission.type_contrat_recherche::text,
      'SALARIE'
    )) IN ('SALARIE', 'LIBERAL', 'TOUS')
      THEN upper(COALESCE(
        v_mission.type_contrat_recherche::text,
        'SALARIE'
      ))
    ELSE 'SALARIE'
  END;

  IF v_recherche = 'SALARIE' THEN
    v_choix := 'SALARIE';
  ELSIF v_recherche = 'LIBERAL' THEN
    IF v_soignant.type_exercice NOT IN ('LIBERAL', 'MIXTE')
       OR NOT v_liberal_verifie THEN
      RETURN jsonb_build_object(
        'ok', false,
        'error',
          'Cette mission est proposée en libéral ; activez un profil libéral avec SIRET et identité vérifiés.'
      );
    END IF;
    v_choix := 'LIBERAL';
  ELSE
    v_choix := upper(p_choix_contrat);

    IF v_choix = 'LIBERAL' AND NOT v_liberal_verifie THEN
      RETURN jsonb_build_object(
        'ok', false,
        'error',
          'Votre profil libéral doit être actif, avec SIRET et identité vérifiés.'
      );
    END IF;

    IF v_choix IS NULL THEN
      IF v_soignant.type_exercice = 'MIXTE' AND v_liberal_verifie THEN
        v_choix := CASE
          WHEN upper(COALESCE(
            v_soignant.preference_contrat_mixte,
            ''
          )) IN ('SALARIE', 'LIBERAL')
            THEN upper(v_soignant.preference_contrat_mixte)
          ELSE NULL
        END;
        IF v_choix IS NULL THEN
          RETURN jsonb_build_object(
            'ok', false,
            'choix_requis', true,
            'error', 'Choisissez votre mode de contrat.',
            'options', jsonb_build_array(
              jsonb_build_object(
                'value', 'SALARIE',
                'label', 'Salarié (CDD / bulletin de paie)'
              ),
              jsonb_build_object(
                'value', 'LIBERAL',
                'label', 'Libéral (note d''honoraires)'
              )
            )
          );
        END IF;
      ELSIF v_soignant.type_exercice = 'LIBERAL'
            AND v_liberal_verifie THEN
        v_choix := 'LIBERAL';
      ELSE
        v_choix := 'SALARIE';
      END IF;
    END IF;

    IF v_choix = 'LIBERAL'
       AND (
         v_soignant.type_exercice NOT IN ('LIBERAL', 'MIXTE')
         OR NOT v_liberal_verifie
       ) THEN
      RETURN jsonb_build_object(
        'ok', false,
        'error',
          'Votre profil n''est pas activé pour un contrat libéral vérifié.'
      );
    END IF;
  END IF;

  IF v_choix = 'LIBERAL' THEN
    v_mode := public.fn_mode_exercice(
      v_mission.profession_requise::text,
      v_etablissement.type_etablissement,
      CASE
        WHEN v_etablissement.est_public THEN 'PUBLIC'
        ELSE NULL
      END
    );
    IF COALESCE(v_mode->>'niveau', 'BLOQUE') = 'BLOQUE'
       OR (
         v_mission.profession_requise::text IN ('IADE', 'IBODE')
         AND COALESCE(v_mode->>'niveau', 'NON_PROPOSE') <> 'AUTORISE'
       ) THEN
      RETURN jsonb_build_object(
        'ok', false,
        'error', COALESCE(
          v_mode->>'source_libelle',
          'Le mode libéral est indisponible pour cette mission.'
        ),
        'niveau', COALESCE(v_mode->>'niveau', 'BLOQUE')
      );
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'contrat', v_choix,
    'profession_requise', v_mission.profession_requise::text,
    'type_contrat_recherche', v_recherche
  );
END;
$body$;

REVOKE ALL ON FUNCTION public.fn_resoudre_contrat_mission(uuid, uuid, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_resoudre_contrat_mission(uuid, uuid, text)
  TO service_role;

CREATE OR REPLACE FUNCTION public.dec_verifier_eligibilite_liberal()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $body$
DECLARE
  v_heures_cumulees numeric;
  v_seuil_heures numeric;
  v_etablissement record;
  v_mode jsonb;
  v_verifier boolean := false;
BEGIN
  IF NEW.soignant_assigne_id IS NOT NULL
     AND NEW.statut = 'ASSIGNEE'
     AND NEW.type_contrat_applique::text = 'LIBERAL' THEN
    IF TG_OP = 'INSERT' THEN
      v_verifier := true;
    ELSE
      v_verifier := OLD.statut IS DISTINCT FROM NEW.statut
        OR OLD.soignant_assigne_id IS DISTINCT FROM NEW.soignant_assigne_id
        OR OLD.type_contrat_applique IS DISTINCT FROM NEW.type_contrat_applique;
    END IF;
  END IF;

  IF NOT v_verifier THEN
    RETURN NEW;
  END IF;

  IF upper(COALESCE(NEW.type_contrat_recherche::text, 'SALARIE'))
       NOT IN ('LIBERAL', 'TOUS') THEN
    RAISE EXCEPTION 'La mission n''est pas ouverte a un contrat liberal.'
      USING ERRCODE = 'check_violation';
  END IF;

  SELECT e.type::text AS type_etablissement,
         COALESCE(e.est_secteur_public, false) AS est_public
  INTO v_etablissement
  FROM public.etablissements e
  WHERE e.id = NEW.etablissement_id
    AND e.supprime_le IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Etablissement introuvable pour la mission.'
      USING ERRCODE = 'check_violation';
  END IF;

  v_mode := public.fn_mode_exercice(
    NEW.profession_requise::text,
    v_etablissement.type_etablissement,
    CASE WHEN v_etablissement.est_public THEN 'PUBLIC' ELSE NULL END
  );
  IF COALESCE(v_mode->>'niveau', 'BLOQUE') = 'BLOQUE'
     OR (
       NEW.profession_requise::text IN ('IADE', 'IBODE')
       AND COALESCE(v_mode->>'niveau', 'NON_PROPOSE') <> 'AUTORISE'
     ) THEN
    RAISE EXCEPTION '%', COALESCE(
      v_mode->>'source_libelle',
      'Le mode liberal est indisponible pour cette mission.'
    ) USING ERRCODE = 'check_violation';
  END IF;

  IF NOT public.fn_soignant_liberal_actif_verifie(
    NEW.soignant_assigne_id
  ) THEN
    RAISE EXCEPTION 'Le profil liberal doit etre actif, avec SIRET et identite verifies.'
      USING ERRCODE = 'check_violation';
  END IF;

  IF NOT public.fn_documents_ok_pour_mission(
    NEW.soignant_assigne_id, 'LIBERAL'
  ) THEN
    RAISE EXCEPTION 'Les documents requis pour la mission liberale ne sont pas tous verifies.'
      USING ERRCODE = 'check_violation';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.soignants s
    WHERE s.id = NEW.soignant_assigne_id
      AND s.supprime_le IS NULL
  ) THEN
    RAISE EXCEPTION 'Profil soignant introuvable.'
      USING ERRCODE = 'check_violation';
  END IF;

  SELECT h.heures_totales
  INTO v_heures_cumulees
  FROM private.fn_heures_exercice_verifiees(
    NEW.soignant_assigne_id
  ) h;

  SELECT private.fn_seuil_heures_liberal(
    NEW.soignant_assigne_id,
    NEW.profession_requise::text
  )
  INTO v_seuil_heures;
  IF v_seuil_heures IS NULL THEN
    RAISE EXCEPTION 'Le parcours kine (2 240 heures ou zone sous-dotee) doit etre choisi avant une mission liberale.'
      USING ERRCODE = 'check_violation';
  END IF;
  IF COALESCE(v_heures_cumulees, 0) < v_seuil_heures THEN
    RAISE EXCEPTION 'Vous devez cumuler % heures d''exercice pour accepter cette mission liberale. Vous avez actuellement % heures.',
      v_seuil_heures,
      round(COALESCE(v_heures_cumulees, 0), 2)
      USING ERRCODE = 'check_violation';
  END IF;

  RETURN NEW;
END;
$body$;

REVOKE ALL ON FUNCTION public.dec_verifier_eligibilite_liberal()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.dec_verifier_eligibilite_liberal()
  TO service_role;

INSERT INTO private.security_definer_inventory (
  signature,
  categorie,
  definition_md5,
  justification,
  recense_le
)
VALUES
  (
    'dec_valider_compatibilite_mission_liberal()',
    'SERVICE_ONLY_REVOQUE',
    md5(pg_get_functiondef('public.dec_valider_compatibilite_mission_liberal()'::regprocedure)),
    'Trigger serveur : ne favorise aucun régime pour NON_PROPOSE et retire le choix libéral uniquement pour une cellule BLOQUE.',
    now()
  ),
  (
    'dec_verifier_eligibilite_liberal()',
    'SERVICE_ONLY_REVOQUE',
    md5(pg_get_functiondef('public.dec_verifier_eligibilite_liberal()'::regprocedure)),
    'Trigger serveur : vérifie le profil, les pièces et l''expérience du soignant, tout en réservant l''interdiction de régime aux cellules BLOQUE.',
    now()
  )
ON CONFLICT (signature) DO UPDATE
SET categorie = EXCLUDED.categorie,
    definition_md5 = EXCLUDED.definition_md5,
    justification = EXCLUDED.justification,
    recense_le = EXCLUDED.recense_le;
