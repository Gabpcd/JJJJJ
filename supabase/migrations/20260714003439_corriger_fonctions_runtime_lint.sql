-- Correctifs P0/P1 issus de `supabase db lint --linked --level warning`.
--
-- Cette migration ne modifie aucune donnée métier : elle remplace uniquement
-- des définitions de fonctions déjà présentes. Les remplacements chirurgicaux
-- passent par un helper temporaire qui exige UNE occurrence exacte de chaque
-- fragment ; un drift futur fait donc échouer la migration au lieu d'altérer
-- silencieusement une autre portion de fonction.

-- ---------------------------------------------------------------------------
-- Helper temporaire de remplacement exact pour les fonctions longues dont on
-- ne change qu'une expression. CREATE OR REPLACE conserve propriétaire et ACL.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION pg_temp.jolene_replace_function_fragment(
  p_signature regprocedure,
  p_old text,
  p_new text
)
RETURNS void
LANGUAGE plpgsql
AS $helper$
DECLARE
  v_definition text;
  v_occurrences integer;
BEGIN
  IF p_old IS NULL OR p_old = '' THEN
    RAISE EXCEPTION 'Fragment source vide pour %', p_signature;
  END IF;

  SELECT pg_get_functiondef(p_signature) INTO v_definition;
  IF v_definition IS NULL THEN
    RAISE EXCEPTION 'Fonction introuvable : %', p_signature;
  END IF;

  v_occurrences :=
    (length(v_definition) - length(replace(v_definition, p_old, '')))
    / length(p_old);

  IF v_occurrences <> 1 THEN
    RAISE EXCEPTION
      'Remplacement refusé pour % : fragment attendu 1 fois, trouvé %',
      p_signature,
      v_occurrences;
  END IF;

  EXECUTE replace(v_definition, p_old, p_new);
END;
$helper$;

-- ---------------------------------------------------------------------------
-- 1. Cohérence documentaire : un tableau text[] ne peut pas être concaténé
--    avec un scalaire text. array_append rend le type explicite sur chaque cas.
--    L'argument optionnel reste nécessaire aux flux serveur/admin, mais un
--    soignant authentifié ne peut jamais inspecter le dossier d'un tiers.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_verifier_coherence_documents(
  p_soignant_id uuid DEFAULT NULL::uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_is_service_role boolean := COALESCE(
    auth.jwt()->>'role',
    current_setting('request.jwt.claim.role', true),
    ''
  ) = 'service_role';
  v_soignant_id uuid := COALESCE(p_soignant_id, v_uid);
  v_soignant record;
  v_docs jsonb;
  v_docs_sans_nom integer;
  v_noms_extraits text[];
  v_coherent boolean := true;
  v_problemes text[] := ARRAY[]::text[];
BEGIN
  IF NOT v_is_service_role
     AND (
       v_uid IS NULL
       OR public.fn_compte_auth_actif() IS NOT TRUE
     ) THEN
    RAISE EXCEPTION 'Accès refusé'
      USING ERRCODE = '42501';
  END IF;

  IF v_soignant_id IS DISTINCT FROM v_uid AND NOT v_is_service_role THEN
    IF NOT public.est_admin_valide() THEN
      RAISE EXCEPTION 'Accès refusé'
        USING ERRCODE = '42501';
    END IF;
  END IF;

  SELECT prenom, nom
    INTO v_soignant
    FROM public.soignants
   WHERE id = v_soignant_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Soignant introuvable');
  END IF;

  SELECT jsonb_agg(jsonb_build_object(
    'type', d.type_document,
    'nom_extrait', d.nom_extrait_ia,
    'prenom_extrait', d.prenom_extrait_ia,
    'coherence_nom', d.coherence_nom,
    'score_confiance', d.score_confiance_ia,
    'statut', d.statut_verification
  ))
    INTO v_docs
    FROM public.documents_soignants d
   WHERE d.soignant_id = v_soignant_id
     AND d.supprime_le IS NULL
     AND d.statut_verification IN ('VERIFIE', 'EN_ATTENTE');

  IF v_docs IS NULL OR jsonb_array_length(v_docs) = 0 THEN
    RETURN jsonb_build_object(
      'coherent', true,
      'message', 'Pas assez de documents vérifiés',
      'documents', '[]'::jsonb
    );
  END IF;

  SELECT count(*)
    INTO v_docs_sans_nom
    FROM jsonb_array_elements(v_docs) elem
   WHERE elem->>'nom_extrait' IS NULL
      OR trim(elem->>'nom_extrait') = '';

  IF v_docs_sans_nom > 0 THEN
    v_problemes := array_append(
      v_problemes,
      format(
        '%s document(s) sans nom lisible — cohérence non vérifiable sur ces pièces',
        v_docs_sans_nom
      )
    );
  END IF;

  SELECT array_agg(DISTINCT upper(trim(elem->>'nom_extrait')))
    INTO v_noms_extraits
    FROM jsonb_array_elements(v_docs) elem
   WHERE elem->>'nom_extrait' IS NOT NULL
     AND trim(elem->>'nom_extrait') <> '';

  IF array_length(v_noms_extraits, 1) > 1 THEN
    v_coherent := false;
    v_problemes := array_append(
      v_problemes,
      'Noms différents détectés entre documents : '
        || array_to_string(v_noms_extraits, ', ')
    );
  END IF;

  IF v_noms_extraits IS NOT NULL AND array_length(v_noms_extraits, 1) > 0 THEN
    DECLARE
      v_profil_nom text := upper(trim(v_soignant.nom));
      v_match boolean := false;
    BEGIN
      FOR i IN 1..array_length(v_noms_extraits, 1) LOOP
        IF v_noms_extraits[i] LIKE '%' || v_profil_nom || '%'
           OR v_profil_nom LIKE '%' || v_noms_extraits[i] || '%' THEN
          v_match := true;
        END IF;
      END LOOP;

      IF NOT v_match THEN
        v_coherent := false;
        v_problemes := array_append(
          v_problemes,
          'Nom du profil (' || v_soignant.nom || ') ne correspond pas aux documents'
        );
      END IF;
    END;
  END IF;

  IF EXISTS (
    SELECT 1
      FROM jsonb_array_elements(v_docs) elem
     WHERE (elem->>'coherence_nom')::boolean = false
  ) THEN
    v_coherent := false;
    v_problemes := array_append(
      v_problemes,
      'Un ou plusieurs documents ont un nom incohérent avec le profil'
    );
  END IF;

  -- Revue admin best-effort : l'alerte ne doit jamais rendre la vérification
  -- documentaire indisponible.
  IF NOT v_coherent THEN
    BEGIN
      INSERT INTO public.journaux_audit (
        acteur_id, type_acteur, action, type_ressource, id_ressource, details
      ) VALUES (
        v_soignant_id,
        'SYSTEM',
        'COHERENCE_DOCUMENTS_ALERTE',
        'soignant',
        v_soignant_id,
        jsonb_build_object(
          'problemes', to_jsonb(v_problemes),
          'profil_nom', v_soignant.nom,
          'profil_prenom', v_soignant.prenom
        )
      );
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END IF;

  RETURN jsonb_build_object(
    'coherent', v_coherent,
    'problemes', to_jsonb(v_problemes),
    'documents', v_docs,
    'profil_nom', v_soignant.nom,
    'profil_prenom', v_soignant.prenom,
    'docs_sans_nom_lisible', v_docs_sans_nom
  );
END;
$function$;

-- ---------------------------------------------------------------------------
-- 2. Annulation établissement : missions.type_contrat n'existe pas. Le régime
--    figé à l'assignation est type_contrat_applique ; salarié reste le défaut
--    prudent si une très ancienne mission n'a pas été figée.
-- ---------------------------------------------------------------------------
SELECT pg_temp.jolene_replace_function_fragment(
  'public.fn_annuler_mission_etab(uuid,text,text)'::regprocedure,
  $old$COALESCE(v_contrat.type_contrat, v_mission.type_contrat::text),$old$,
  $new$COALESCE(v_contrat.type_contrat, v_mission.type_contrat_applique::text, 'SALARIE'),$new$
);

-- ---------------------------------------------------------------------------
-- 3. Validation par lot : suppression de la table temporaire de session. Le
--    RETURNING de l'UPDATE est agrégé en JSONB, puis réutilisé pour audit/notifs.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_valider_presences_lot(p_ids uuid[])
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_etab_id uuid;
  v_count integer;
  v_presence_ids jsonb := '[]'::jsonb;
  v_validees jsonb := '[]'::jsonb;
  v_row jsonb;
BEGIN
  v_etab_id := public.mon_etablissement_id();
  IF v_etab_id IS NULL
     OR public.fn_a_permission_etablissement('pointage', v_etab_id) IS NOT TRUE THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non autorisé');
  END IF;

  WITH maj AS (
    UPDATE public.presences p
       SET valide_par_etablissement = true,
           valide_le = now(),
           modifie_le = now()
      FROM public.missions m
     WHERE p.id = ANY(p_ids)
       AND p.mission_id = m.id
       AND m.etablissement_id = v_etab_id
       AND p.valide_par_etablissement = false
       AND p.perimetre_gps_valide = true
       AND COALESCE(p.alerte_teleportation, false) = false
    RETURNING p.id, p.mission_id, p.soignant_id
  )
  SELECT count(*)::integer,
         COALESCE(jsonb_agg(maj.id), '[]'::jsonb),
         COALESCE(
           jsonb_agg(jsonb_build_object(
             'presence_id', maj.id,
             'mission_id', maj.mission_id,
             'soignant_id', maj.soignant_id
           )),
           '[]'::jsonb
         )
    INTO v_count, v_presence_ids, v_validees
    FROM maj;

  IF v_count > 0 THEN
    PERFORM public.fn_ecrire_audit(
      v_etab_id,
      'ETABLISSEMENT',
      'PRESENCE_VALIDATION_LOT',
      'presence',
      NULL,
      NULL,
      jsonb_build_object(
        'nb_validees', v_count,
        'presence_ids', v_presence_ids
      )
    );

    FOR v_row IN
      SELECT value FROM jsonb_array_elements(v_validees)
    LOOP
      BEGIN
        PERFORM public.fn_creer_notification(
          p_destinataire_id   := (v_row->>'soignant_id')::uuid,
          p_type_destinataire := 'SOIGNANT',
          p_type              := 'PRESENCE_VALIDEE',
          p_titre             := 'Présence validée',
          p_corps             := 'Vos heures ont été validées par l''établissement. Le paiement suit son cours.',
          p_lien              := '/soignant/presences',
          p_type_ressource    := 'presence',
          p_id_ressource      := (v_row->>'presence_id')::uuid
        );
      EXCEPTION WHEN OTHERS THEN
        NULL;
      END;
    END LOOP;
  END IF;

  RETURN jsonb_build_object('success', true, 'nb_validees', v_count);
END;
$function$;

-- ---------------------------------------------------------------------------
-- 4. Tolérance pointage : le timestamp réel est etablissements.modifie_le.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_modifier_tolerance_pointage_etab(
  p_tolerance_pointage_m integer
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_etab_id uuid;
  v_ancienne_valeur integer;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTHENTIFIE');
  END IF;

  IF p_tolerance_pointage_m IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'VALEUR_REQUISE');
  END IF;

  IF p_tolerance_pointage_m < 30 OR p_tolerance_pointage_m > 1000 THEN
    RETURN jsonb_build_object(
      'success', false,
      'error_code', 'HORS_RANGE',
      'error', 'Tolérance doit être entre 30 et 1000 mètres'
    );
  END IF;

  v_etab_id := public.mon_etablissement_id();
  IF v_etab_id IS NULL
     OR public.fn_a_permission_etablissement('profil_etab', v_etab_id) IS NOT TRUE THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTORISE');
  END IF;

  SELECT tolerance_pointage_m
    INTO v_ancienne_valeur
    FROM public.etablissements
   WHERE id = v_etab_id;

  UPDATE public.etablissements
     SET tolerance_pointage_m = p_tolerance_pointage_m,
         modifie_le = now()
   WHERE id = v_etab_id;

  INSERT INTO public.journaux_audit (
    acteur_id, type_acteur, action, type_ressource, id_ressource, details
  ) VALUES (
    v_uid,
    'ADMIN_ETABLISSEMENT',
    'MODIFICATION_PROFIL',
    'etablissement',
    v_etab_id,
    jsonb_build_object(
      'champ', 'tolerance_pointage_m',
      'ancienne_valeur', v_ancienne_valeur,
      'nouvelle_valeur', p_tolerance_pointage_m,
      'horodatage', now()
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'tolerance_pointage_m', p_tolerance_pointage_m,
    'horodatage', now()
  );
END;
$function$;

-- Dépendance runtime directe : le trigger d'invalidation peut rétrograder un
-- ancien dossier VERIFIE devenu incomplet lors de n'importe quelle mise à jour
-- non sensible (dont la tolérance GPS). Le protector doit accepter cette
-- révocation canonique produite par le trigger précédent. Il n'autorise ici
-- qu'une rétrogradation VERIFIE -> EN_COURS avec publication coupée ; aucune
-- promotion ni écriture de verdict n'est rendue possible.
SELECT pg_temp.jolene_replace_function_fragment(
  'public.fn_protect_etablissement_commercial()'::regprocedure,
  $old$v_revocation_globale := v_source_changee
    OR (v_signature_transition
      AND OLD.contrat_service_signe IS TRUE
      AND NEW.contrat_service_signe IS FALSE);$old$,
  $new$v_revocation_globale := v_source_changee
    OR (v_signature_transition
      AND OLD.contrat_service_signe IS TRUE
      AND NEW.contrat_service_signe IS FALSE)
    OR (
      OLD.statut_verification = 'VERIFIE'
      AND NOT (
        NEW.siret_verifie IS TRUE
        AND NEW.finess_verifie IS TRUE
        AND NEW.representant_identite_verifiee IS TRUE
        AND NEW.rattachement_verifie IS TRUE
        AND NEW.contrat_service_signe IS TRUE
      )
      AND NEW.statut_verification = 'EN_COURS'
      AND NEW.peut_publier_missions IS FALSE
    );$new$
);

-- ---------------------------------------------------------------------------
-- 5. Clôture litige : resolu_par est un UUID. On conserve le motif humain dans
--    resolution et on trace l'utilisateur qui a effectivement clos le litige.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_cloturer_litige(
  p_litige_id uuid,
  p_resolution text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_litige record;
  v_qui text;
  v_uid uuid := auth.uid();
  v_etablissement_id uuid;
  v_est_admin boolean := false;
BEGIN
  -- Autoriser avant toute lecture du statut : un UUID tiers ne doit révéler
  -- ni l'existence du litige, ni le fait qu'il soit déjà clôturé.
  IF v_uid IS NULL OR public.fn_compte_auth_actif() IS NOT TRUE THEN
    RETURN jsonb_build_object('error', 'Accès refusé');
  END IF;

  v_etablissement_id := public.mon_etablissement_id();
  v_est_admin := public.est_admin();

  SELECT l.*
    INTO v_litige
    FROM public.litiges l
   WHERE l.id = p_litige_id
     AND (
       l.soignant_id = v_uid
       OR (
         l.etablissement_id = v_etablissement_id
         AND public.fn_a_permission_etablissement(
           'contrats', l.etablissement_id
         ) IS TRUE
       )
       OR v_est_admin
     )
   FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Litige introuvable ou accès refusé');
  END IF;
  IF v_litige.statut NOT IN (
    'OUVERT', 'EN_DISCUSSION', 'EN_MEDIATION', 'MEDIATION_EN_COURS'
  ) THEN
    RETURN jsonb_build_object('error', 'Litige déjà résolu ou non modifiable.');
  END IF;
  IF v_litige.payload_modifications IS NOT NULL THEN
    RETURN jsonb_build_object(
      'error',
      'Un accord avec proposition doit être accepté via son payload exact'
    );
  END IF;

  IF v_uid = v_litige.soignant_id THEN
    v_qui := 'soignant';
    UPDATE public.litiges
       SET accord_soignant = true,
           accord_soignant_le = now()
     WHERE id = p_litige_id;
  ELSIF v_etablissement_id = v_litige.etablissement_id
        AND public.fn_a_permission_etablissement(
          'contrats', v_litige.etablissement_id
        ) IS TRUE THEN
    v_qui := 'etablissement';
    UPDATE public.litiges
       SET accord_etablissement = true,
           accord_etablissement_le = now()
     WHERE id = p_litige_id;
  ELSIF v_est_admin THEN
    UPDATE public.litiges
       SET statut = 'RESOLU_ADMIN',
           resolu_par = v_uid,
           resolution = COALESCE(
             p_resolution,
             'Clôturé par l''équipe Jolene'
           ),
           resolu_le = now()
     WHERE id = p_litige_id;
    RETURN jsonb_build_object('success', true, 'statut', 'RESOLU_ADMIN');
  ELSE
    RETURN jsonb_build_object('error', 'Accès refusé');
  END IF;

  SELECT l.*
    INTO v_litige
    FROM public.litiges l
   WHERE l.id = p_litige_id
     AND (
       l.soignant_id = v_uid
       OR (
         l.etablissement_id = v_etablissement_id
         AND public.fn_a_permission_etablissement(
           'contrats', l.etablissement_id
         ) IS TRUE
       )
       OR v_est_admin
     );

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Litige introuvable ou accès refusé');
  END IF;

  IF v_litige.accord_soignant = true
     AND v_litige.accord_etablissement = true THEN
    UPDATE public.litiges
       SET statut = 'RESOLU_ACCORD_PARTIES',
           resolu_par = v_uid,
           resolution = COALESCE(p_resolution, 'Clôturé par accord mutuel'),
           resolu_le = now()
     WHERE id = p_litige_id;
    RETURN jsonb_build_object(
      'success', true,
      'statut', 'RESOLU_ACCORD_PARTIES',
      'resolution', 'accord_mutuel'
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'accord_' || v_qui, true,
    'en_attente', CASE
      WHEN v_qui = 'soignant' THEN 'établissement'
      ELSE 'soignant'
    END
  );
END;
$function$;

-- Compatibilité du flux frontend historique : aucune logique d'accord parallèle
-- ne subsiste, la RPC délègue à la clôture verrouillée et permissionnée.
CREATE OR REPLACE FUNCTION public.fn_proposer_cloture_litige(p_litige_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_result jsonb;
BEGIN
  v_result := public.fn_cloturer_litige(p_litige_id, NULL);
  IF v_result ? 'error' THEN
    RETURN v_result;
  END IF;
  IF v_result->>'statut' = 'RESOLU_ACCORD_PARTIES' THEN
    RETURN jsonb_build_object(
      'success', true,
      'statut', 'cloture_validee',
      'message', 'Litige clôturé à l''amiable'
    );
  END IF;
  RETURN jsonb_build_object(
    'success', true,
    'statut', 'en_attente',
    'details', v_result
  );
END;
$function$;

-- Les deux autres RPC historiques du panneau de médiation ne doivent pas
-- maintenir une seconde implémentation du consentement. La proposition de
-- médiation reste une transition sans accord, mais elle est verrouillée et
-- bornée à une partie active; la confirmation délègue au chemin canonique qui
-- refuse tout payload non nul sans comparaison exacte.
CREATE OR REPLACE FUNCTION public.fn_proposer_accord_partie(p_litige_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_etablissement_id uuid;
  v_litige record;
  v_role text;
BEGIN
  IF v_uid IS NULL OR public.fn_compte_auth_actif() IS NOT TRUE THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non authentifié');
  END IF;

  v_etablissement_id := public.mon_etablissement_id();
  SELECT l.*
    INTO v_litige
    FROM public.litiges l
   WHERE l.id = p_litige_id
     AND (
       l.soignant_id = v_uid
       OR (
         l.etablissement_id = v_etablissement_id
         AND public.fn_a_permission_etablissement(
           'contrats', l.etablissement_id
         ) IS TRUE
       )
     )
   FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Litige introuvable ou accès refusé'
    );
  END IF;
  IF v_litige.statut NOT IN ('OUVERT', 'EN_DISCUSSION', 'EN_MEDIATION') THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Litige déjà en médiation ou résolu'
    );
  END IF;
  IF v_litige.payload_modifications IS NOT NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'La proposition existante doit être traitée via son payload exact'
    );
  END IF;

  v_role := CASE
    WHEN v_litige.soignant_id = v_uid THEN 'soignant'
    ELSE 'etablissement'
  END;

  UPDATE public.litiges
     SET statut = 'MEDIATION_EN_COURS'
   WHERE id = p_litige_id;

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_uid,
    p_type_acteur := CASE
      WHEN v_role = 'etablissement' THEN 'ADMIN_ETABLISSEMENT'
      ELSE 'SOIGNANT'
    END,
    p_action := 'MEDIATION_OUVERTE',
    p_type_ressource := 'litige',
    p_id_ressource := p_litige_id,
    p_details := jsonb_build_object('initie_par', v_role)
  );

  PERFORM public.fn_creer_notification(
    p_destinataire_id := CASE
      WHEN v_role = 'etablissement' THEN v_litige.soignant_id
      ELSE v_litige.etablissement_id
    END,
    p_type_destinataire := CASE
      WHEN v_role = 'etablissement' THEN 'SOIGNANT'
      ELSE 'ETABLISSEMENT'
    END,
    p_type := 'LITIGE_MEDIATION',
    p_titre := 'Médiation litige proposée',
    p_corps := 'L''autre partie propose une médiation amiable. Vous avez 7 jours pour discuter et confirmer un accord.',
    p_lien := CASE
      WHEN v_role = 'etablissement' THEN '/soignant/litiges'
      ELSE '/etablissement/litiges'
    END,
    p_type_ressource := 'litige',
    p_id_ressource := p_litige_id
  );

  RETURN jsonb_build_object('success', true, 'statut', 'MEDIATION_EN_COURS');
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_confirmer_accord_partie(p_litige_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_etablissement_id uuid;
  v_litige record;
BEGIN
  IF v_uid IS NULL OR public.fn_compte_auth_actif() IS NOT TRUE THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non authentifié');
  END IF;

  v_etablissement_id := public.mon_etablissement_id();
  SELECT l.*
    INTO v_litige
    FROM public.litiges l
   WHERE l.id = p_litige_id
     AND (
       l.soignant_id = v_uid
       OR (
         l.etablissement_id = v_etablissement_id
         AND public.fn_a_permission_etablissement(
           'contrats', l.etablissement_id
         ) IS TRUE
       )
     )
   FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Litige introuvable ou accès refusé'
    );
  END IF;
  IF v_litige.payload_modifications IS NOT NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'La proposition doit être acceptée via son payload exact'
    );
  END IF;

  RETURN public.fn_cloturer_litige(p_litige_id, NULL);
END;
$function$;

-- La transition de double accord est portée par un trigger canonique exécuté
-- après dec_proteger_litige. Un payload financier attend toujours la revue
-- admin ; un accord sans impact prend le statut résolu admis par la contrainte.
CREATE OR REPLACE FUNCTION public.fn_trg_litige_accord_mutuel()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_type text;
  v_financier boolean;
BEGIN
  IF NEW.accord_soignant_le IS NOT NULL
     AND NEW.accord_etablissement_le IS NOT NULL
     AND NEW.statut IN (
       'OUVERT', 'EN_DISCUSSION', 'EN_MEDIATION', 'MEDIATION_EN_COURS'
     ) THEN
    v_type := NEW.payload_modifications->>'type';
    v_financier := NEW.payload_modifications IS NOT NULL
      AND COALESCE(v_type, 'ACCORD_SANS_MODIFICATION')
        <> 'ACCORD_SANS_MODIFICATION';

    NEW.accord_soignant := true;
    NEW.accord_etablissement := true;
    IF v_financier THEN
      NEW.statut := 'REVUE_ADMIN';
      NEW.resolu_le := NULL;
    ELSE
      NEW.statut := 'RESOLU_ACCORD_PARTIES';
      NEW.resolu_le := COALESCE(NEW.resolu_le, now());
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

-- Les accords et propositions passent exclusivement par les RPC contrôlées.
-- Une politique RLS de ligne ne peut pas empêcher un UPDATE PostgREST de poser
-- directement les deux accords/timestamps ou de changer le payload.
REVOKE UPDATE ON TABLE public.litiges FROM anon, authenticated;

-- Accord transactionnel : la ligne est verrouillée avant l'examen du statut.
-- Un changement JSONB de proposition annule toujours le consentement opposé ;
-- seul un second accord sur le payload exactement identique peut progresser.
CREATE OR REPLACE FUNCTION public.fn_cloturer_litige_avec_payload(
  p_litige_id uuid,
  p_payload jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_etablissement_id uuid;
  v_litige record;
  v_role text;
  v_other_role text;
  v_exec_result jsonb;
  v_admin_ids uuid[];
  v_type text;
  v_modifications jsonb;
  v_arrivee timestamptz;
  v_depart timestamptz;
  v_montant numeric;
  v_compensation numeric;
BEGIN
  IF v_uid IS NULL OR public.fn_compte_auth_actif() IS NOT TRUE THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Non authentifié'
    );
  END IF;
  IF p_payload IS NULL OR jsonb_typeof(p_payload) <> 'object' THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Payload de proposition invalide'
    );
  END IF;

  -- Le JSONB lui-même est la version de la proposition : toute différence de
  -- valeur invalide l'accord opposé. Les champs de présentation ne sont jamais
  -- stockés et chaque type ne peut porter que les données qu'il exécute.
  v_type := p_payload->>'type';
  v_modifications := p_payload->'modifications';
  IF jsonb_typeof(p_payload->'type') IS DISTINCT FROM 'string'
     OR v_type NOT IN (
       'MODIFICATION_HORAIRES',
       'MODIFICATION_MONTANT',
       'ANNULATION_TOTALE',
       'COMPENSATION_PARTIELLE',
       'MIXTE',
       'ACCORD_SANS_MODIFICATION'
     )
     OR jsonb_typeof(v_modifications) IS DISTINCT FROM 'object'
     OR jsonb_typeof(p_payload->'justification') IS DISTINCT FROM 'string'
     OR btrim(p_payload->>'justification') = ''
     OR length(p_payload->>'justification') > 2000
     OR p_payload - ARRAY['type', 'modifications', 'justification']::text[]
       <> '{}'::jsonb THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Schéma de proposition invalide'
    );
  END IF;

  IF v_type = 'ACCORD_SANS_MODIFICATION' THEN
    IF v_modifications <> '{}'::jsonb THEN
      RETURN jsonb_build_object(
        'success', false,
        'error', 'Un accord sans modification doit avoir un objet modifications vide'
      );
    END IF;
  ELSIF v_type IN ('MODIFICATION_HORAIRES', 'MIXTE') THEN
    IF jsonb_typeof(v_modifications->'pointage_arrivee_le') IS DISTINCT FROM 'string'
       OR jsonb_typeof(v_modifications->'pointage_depart_le') IS DISTINCT FROM 'string'
       OR v_modifications
         - (CASE WHEN v_type = 'MIXTE'
             THEN ARRAY[
               'pointage_arrivee_le', 'pointage_depart_le',
               'montant_total_corrige'
             ]::text[]
             ELSE ARRAY['pointage_arrivee_le', 'pointage_depart_le']::text[]
           END)
         <> '{}'::jsonb THEN
      RETURN jsonb_build_object(
        'success', false,
        'error', 'Champs horaires invalides'
      );
    END IF;
    BEGIN
      v_arrivee := (v_modifications->>'pointage_arrivee_le')::timestamptz;
      v_depart := (v_modifications->>'pointage_depart_le')::timestamptz;
    EXCEPTION WHEN invalid_datetime_format OR datetime_field_overflow THEN
      RETURN jsonb_build_object(
        'success', false,
        'error', 'Format des horaires invalide'
      );
    END;
    IF v_depart <= v_arrivee OR v_depart - v_arrivee > interval '7 days' THEN
      RETURN jsonb_build_object(
        'success', false,
        'error', 'Plage horaire invalide'
      );
    END IF;
  END IF;

  IF v_type IN ('MODIFICATION_MONTANT', 'MIXTE') THEN
    IF jsonb_typeof(v_modifications->'montant_total_corrige') IS DISTINCT FROM 'number' THEN
      RETURN jsonb_build_object(
        'success', false,
        'error', 'Montant corrigé invalide'
      );
    END IF;
    v_montant := (v_modifications->>'montant_total_corrige')::numeric;
    IF v_montant <= 0 OR v_montant > 10000000 THEN
      RETURN jsonb_build_object(
        'success', false,
        'error', 'Montant corrigé hors limites'
      );
    END IF;
    IF v_type = 'MODIFICATION_MONTANT'
       AND v_modifications - ARRAY['montant_total_corrige']::text[]
         <> '{}'::jsonb THEN
      RETURN jsonb_build_object(
        'success', false,
        'error', 'Champs de montant invalides'
      );
    END IF;
  ELSIF v_type = 'COMPENSATION_PARTIELLE' THEN
    IF jsonb_typeof(v_modifications->'pourcentage_compensation') IS DISTINCT FROM 'number'
       OR v_modifications - ARRAY['pourcentage_compensation']::text[]
         <> '{}'::jsonb THEN
      RETURN jsonb_build_object(
        'success', false,
        'error', 'Compensation invalide'
      );
    END IF;
    v_compensation := (v_modifications->>'pourcentage_compensation')::numeric;
    IF v_compensation <= 0 OR v_compensation > 100 THEN
      RETURN jsonb_build_object(
        'success', false,
        'error', 'Compensation hors limites'
      );
    END IF;
  ELSIF v_type = 'ANNULATION_TOTALE' THEN
    IF jsonb_typeof(v_modifications->'motif_annulation') IS DISTINCT FROM 'string'
       OR btrim(v_modifications->>'motif_annulation') = ''
       OR v_modifications - ARRAY['motif_annulation']::text[] <> '{}'::jsonb THEN
      RETURN jsonb_build_object(
        'success', false,
        'error', 'Motif d''annulation invalide'
      );
    END IF;
  END IF;

  v_etablissement_id := public.mon_etablissement_id();

  SELECT l.*
    INTO v_litige
    FROM public.litiges l
   WHERE l.id = p_litige_id
     AND (
       l.soignant_id = v_uid
       OR (
         l.etablissement_id = v_etablissement_id
         AND public.fn_a_permission_etablissement(
           'contrats', l.etablissement_id
         ) IS TRUE
       )
     )
   FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Litige introuvable ou accès refusé'
    );
  END IF;
  IF v_litige.statut NOT IN (
    'OUVERT', 'EN_DISCUSSION', 'EN_MEDIATION', 'MEDIATION_EN_COURS'
  ) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Litige déjà résolu ou non modifiable'
    );
  END IF;

  IF v_litige.soignant_id = v_uid THEN
    v_role := 'soignant';
    v_other_role := 'etablissement';
  ELSE
    v_role := 'etablissement';
    v_other_role := 'soignant';
  END IF;

  IF p_payload IS DISTINCT FROM v_litige.payload_modifications THEN
    UPDATE public.litiges
       SET payload_modifications = p_payload,
           accord_soignant = (v_role = 'soignant'),
           accord_soignant_le = CASE
             WHEN v_role = 'soignant' THEN now() ELSE NULL
           END,
           accord_etablissement = (v_role = 'etablissement'),
           accord_etablissement_le = CASE
             WHEN v_role = 'etablissement' THEN now() ELSE NULL
           END
     WHERE id = p_litige_id;
  ELSIF v_role = 'soignant' THEN
    UPDATE public.litiges
       SET accord_soignant = true,
           accord_soignant_le = COALESCE(accord_soignant_le, now())
     WHERE id = p_litige_id;
  ELSE
    UPDATE public.litiges
       SET accord_etablissement = true,
           accord_etablissement_le = COALESCE(
             accord_etablissement_le, now()
           )
     WHERE id = p_litige_id;
  END IF;

  SELECT l.*
    INTO v_litige
    FROM public.litiges l
   WHERE l.id = p_litige_id;

  IF v_litige.statut = 'REVUE_ADMIN' THEN
    SELECT COALESCE(array_agg(admin_user_id), ARRAY[]::uuid[])
      INTO v_admin_ids
      FROM public.fn_list_admin_user_ids() AS admins(admin_user_id);

    IF cardinality(v_admin_ids) > 0 THEN
      INSERT INTO public.externalisation_actions (
        type_action, payload, source, source_id
      )
      SELECT
        'PUSH_NOTIF',
        jsonb_build_object(
          'destinataire_id', uid,
          'type_evenement', 'ALERTE_ADMIN',
          'titre', '⚖️ Accord financier à valider',
          'corps', 'Les parties ont accepté le même ajustement financier. Validation admin requise.',
          'lien', '/admin/litiges'
        ),
        'LITIGE_EXEC',
        p_litige_id
      FROM unnest(v_admin_ids) AS destinataires(uid);
    END IF;

    RETURN jsonb_build_object(
      'success', true,
      'statut', 'EN_ATTENTE_VALIDATION_ADMIN',
      'type', v_litige.payload_modifications->>'type',
      'payload_propose', v_litige.payload_modifications
    );
  END IF;

  IF v_litige.statut = 'RESOLU_ACCORD_PARTIES' THEN
    PERFORM set_config('jolene.litige_exec_ok', 'true', true);
    v_exec_result := public.fn_executer_modifications_litige(p_litige_id);
    RETURN jsonb_build_object(
      'success', true,
      'statut', 'RESOLU_ACCORD_PARTIES',
      'execution', v_exec_result
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'statut', 'EN_ATTENTE_ACCORD_AUTRE_PARTIE',
    'role_en_attente', v_other_role,
    'payload_propose', v_litige.payload_modifications
  );
END;
$function$;

-- Validation admin : seule une proposition financière effectivement acceptée
-- par les deux parties et placée en REVUE_ADMIN peut être exécutée.
CREATE OR REPLACE FUNCTION public.fn_admin_valider_accord_litige(
  p_litige_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_litige record;
  v_exec jsonb;
  v_audit_result jsonb;
  v_type text;
  v_rows integer;
BEGIN
  IF public.est_admin() IS NOT TRUE THEN
    RETURN jsonb_build_object('success', false, 'error', 'Admin requis');
  END IF;

  SELECT l.*
    INTO v_litige
    FROM public.litiges l
   WHERE l.id = p_litige_id
   FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Litige introuvable');
  END IF;

  v_type := v_litige.payload_modifications->>'type';
  IF v_litige.statut <> 'REVUE_ADMIN'
     OR v_litige.accord_soignant IS NOT TRUE
     OR v_litige.accord_etablissement IS NOT TRUE
     OR v_litige.accord_soignant_le IS NULL
     OR v_litige.accord_etablissement_le IS NULL
     OR v_litige.payload_modifications IS NULL
     OR COALESCE(v_type, 'ACCORD_SANS_MODIFICATION')
       = 'ACCORD_SANS_MODIFICATION'
     OR v_litige.modifications_executees IS TRUE THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Aucun accord financier complet à valider sur ce litige'
    );
  END IF;

  -- Ces ajustements doivent passer par fn_admin_resoudre_litige : cette RPC
  -- demande à l'admin les paramètres comptables exacts selon l'état réel de
  -- la facture. On retourne un résultat structuré sans sortir le dossier de
  -- REVUE_ADMIN et sans tenter d'avoir approximatif.
  IF v_type IN (
    'MODIFICATION_HORAIRES',
    'MODIFICATION_MONTANT',
    'MIXTE'
  ) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error_code', 'RESOLUTION_FINANCIERE_MANUELLE_REQUISE',
      'error', 'Cet ajustement doit être appliqué via la résolution financière administrateur.',
      'manual_resolution_required', true,
      'type', v_type
    );
  END IF;

  PERFORM set_config('jolene.litige_exec_ok', 'true', true);
  v_exec := public.fn_executer_modifications_litige(p_litige_id);

  IF COALESCE((v_exec->>'success')::boolean, false) IS NOT TRUE THEN
    RAISE EXCEPTION 'Échec de l''exécution de l''accord financier: %',
      COALESCE(v_exec->>'error', 'erreur inconnue');
  END IF;

  UPDATE public.litiges
     SET statut = 'RESOLU_ADMIN',
         resolu_le = COALESCE(resolu_le, now()),
         resolu_par = v_uid
   WHERE id = p_litige_id;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 1 THEN
    RAISE EXCEPTION 'Validation concurrente de l''accord refusée';
  END IF;

  v_audit_result := public.fn_ecrire_audit_safe(
    p_acteur_id := v_uid,
    p_type_acteur := 'ADMIN_PLATEFORME',
    p_action := 'LITIGE_RESOLUTION',
    p_type_ressource := 'litige',
    p_id_ressource := p_litige_id,
    p_details := jsonb_build_object(
      'evenement', 'LITIGE_ACCORD_VALIDE_ADMIN',
      'execution', v_exec
    )
  );
  IF COALESCE(v_audit_result @> '{"success": true}'::jsonb, false)
       IS NOT TRUE THEN
    RAISE EXCEPTION 'Audit de validation d''accord non écrit: %',
      COALESCE(v_audit_result->>'error', 'résultat interne invalide');
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'statut', 'RESOLU_ADMIN',
    'execution', v_exec
  );
END;
$function$;

-- Le trigger de gel historique contenait des statuts jamais admis par le
-- CHECK de litiges et omettait les résolutions canoniques récentes. REVUE_ADMIN
-- reste ouverte (facture gelée) jusqu'à la validation effective.
SELECT pg_temp.jolene_replace_function_fragment(
  'public.fn_trg_litige_gel_degel_facture()'::regprocedure,
  $old$v_statuts_ouverts TEXT[] := ARRAY['OUVERT','EN_DISCUSSION','EN_MEDIATION','CONTESTEE'];$old$,
  $new$v_statuts_ouverts TEXT[] := ARRAY[
    'OUVERT', 'EN_DISCUSSION', 'EN_MEDIATION',
    'MEDIATION_EN_COURS', 'REVUE_ADMIN'
  ];$new$
);
SELECT pg_temp.jolene_replace_function_fragment(
  'public.fn_trg_litige_gel_degel_facture()'::regprocedure,
  $old$v_statuts_resolus TEXT[] := ARRAY['RESOLU','RESOLU_SOIGNANT','RESOLU_ETABLISSEMENT','RESOLU_ADMIN','FERME','CLOTURE'];$old$,
  $new$v_statuts_resolus TEXT[] := ARRAY[
    'RESOLU_SOIGNANT', 'RESOLU_ETABLISSEMENT', 'RESOLU_ADMIN', 'FERME',
    'RESOLU_ACCORD_PARTIES', 'RESOLU_FAVEUR_SOIGNANT',
    'RESOLU_FAVEUR_ETAB', 'RESOLU_PARTAGE'
  ];$new$
);

-- Le panneau de contestation historique appelle encore cette résolution admin
-- simple. Elle ne doit jamais servir à contourner la validation/exécution d'un
-- accord structuré placé en REVUE_ADMIN.
SELECT pg_temp.jolene_replace_function_fragment(
  'public.fn_resoudre_litige(uuid,text,text)'::regprocedure,
  $old$    SELECT * INTO v_litige FROM litiges WHERE id = p_litige_id;
    IF v_litige IS NULL THEN RETURN '{"error":"Litige introuvable"}'::JSONB; END IF;

    SELECT * INTO v_mission FROM missions WHERE id = v_litige.mission_id;$old$,
  $new$    SELECT *
      INTO v_litige
      FROM public.litiges
     WHERE id = p_litige_id
     FOR UPDATE;
    IF v_litige IS NULL THEN
      RETURN '{"error":"Litige introuvable"}'::jsonb;
    END IF;
    IF v_litige.statut = 'REVUE_ADMIN'
       OR v_litige.payload_modifications IS NOT NULL THEN
      RETURN jsonb_build_object(
        'error',
        'Accord structuré à traiter via le parcours financier administrateur'
      );
    END IF;
    IF v_litige.statut NOT IN (
      'OUVERT', 'EN_DISCUSSION', 'EN_MEDIATION', 'MEDIATION_EN_COURS'
    ) THEN
      RETURN jsonb_build_object(
        'error', 'Litige déjà résolu ou non modifiable'
      );
    END IF;

    SELECT * INTO v_mission
      FROM public.missions
     WHERE id = v_litige.mission_id;$new$
);

-- Les deux signatures d'ouverture doivent partager la même garde. Le wrapper
-- historique contrôle le compte avant d'écrire son audit, puis délègue à la
-- signature typée. Côté établissement, l'appartenance seule ne vaut jamais
-- droit de mutation : la permission « contrats » est obligatoire.
CREATE OR REPLACE FUNCTION public.fn_ouvrir_litige_rate_limited(
  p_mission_id uuid,
  p_type_litige public.type_litige,
  p_motif text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_mission record;
  v_existing integer;
  v_recent integer;
  v_initie_par text;
  v_etab_id uuid;
  v_soignant_id uuid;
  v_presence_id uuid;
  v_rate_limit integer;
  v_litige_id uuid;
  v_est_informatif boolean;
  v_fenetre_ouverte boolean;
  v_facture_id uuid;
  v_mon_etablissement_id uuid;
BEGIN
  IF v_user_id IS NULL OR public.fn_compte_auth_actif() IS NOT TRUE THEN
    RETURN jsonb_build_object('error', 'Accès refusé');
  END IF;
  IF length(trim(COALESCE(p_motif, ''))) < 10
     OR length(trim(COALESCE(p_motif, ''))) > 2000 THEN
    RETURN jsonb_build_object(
      'error', 'Le motif doit contenir entre 10 et 2 000 caractères.'
    );
  END IF;

  v_mon_etablissement_id := public.mon_etablissement_id();
  SELECT m.id, m.etablissement_id, m.soignant_assigne_id, m.statut
    INTO v_mission
    FROM public.missions m
   WHERE m.id = p_mission_id
   FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Mission introuvable');
  END IF;

  IF v_mission.soignant_assigne_id = v_user_id THEN
    v_initie_par := 'SOIGNANT';
    v_etab_id := v_mission.etablissement_id;
    v_soignant_id := v_user_id;
  ELSIF v_mission.etablissement_id = v_mon_etablissement_id
        AND public.fn_a_permission_etablissement(
          'contrats', v_mission.etablissement_id
        ) IS TRUE THEN
    v_initie_par := 'ETABLISSEMENT';
    v_etab_id := v_mission.etablissement_id;
    v_soignant_id := v_mission.soignant_assigne_id;
  ELSE
    RETURN jsonb_build_object(
      'error', 'Vous n''êtes pas partie prenante de cette mission.'
    );
  END IF;

  SELECT count(*)
    INTO v_existing
    FROM public.litiges l
   WHERE l.mission_id = p_mission_id
     AND l.type_litige = p_type_litige
     AND l.statut IN (
       'OUVERT', 'EN_DISCUSSION', 'EN_MEDIATION', 'MEDIATION_EN_COURS',
       'REVUE_ADMIN'
     );
  IF v_existing > 0 THEN
    RETURN jsonb_build_object(
      'error', 'Un litige de ce type est déjà ouvert pour cette mission.'
    );
  END IF;

  v_rate_limit := COALESCE(
    (
      SELECT pl.valeur::integer
        FROM public.parametres_litiges pl
       WHERE pl.cle = 'rate_limit_litiges_par_heure'
    ),
    3
  );
  SELECT count(*)
    INTO v_recent
    FROM public.litiges l
   WHERE (
     l.soignant_id = v_user_id
     OR l.etablissement_id = v_mon_etablissement_id
   )
     AND l.cree_le > now() - interval '1 hour';
  IF v_recent >= v_rate_limit THEN
    RETURN jsonb_build_object(
      'error', 'Trop de litiges ouverts récemment. Réessayez plus tard.'
    );
  END IF;

  IF p_type_litige IN (
    'DESACCORD_MONTANT_FACTURE', 'NON_PAIEMENT', 'FRAIS_COMPLEMENTAIRES'
  ) THEN
    SELECT f.id
      INTO v_facture_id
      FROM public.factures_honoraires f
     WHERE f.mission_id = p_mission_id
       AND f.type_document = 'FACTURE'
       AND f.statut IN ('EMISE', 'EN_RETARD', 'PAYEE')
     ORDER BY f.date_emission DESC NULLS LAST
     LIMIT 1
     FOR UPDATE;
    IF v_facture_id IS NULL THEN
      RETURN jsonb_build_object(
        'error',
        'Aucune facture contestable (ÉMISE, EN RETARD ou PAYÉE) pour cette mission.'
      );
    END IF;
  ELSIF p_type_litige = 'DESACCORD_HEURES_POINTAGE' THEN
    -- Le désaccord peut précéder la facturation : on le laisse s'ouvrir, mais
    -- on rattache immédiatement tout document actif afin que l'accord horaires
    -- puisse suivre la résolution financière sans sélection ambiguë.
    SELECT f.id
      INTO v_facture_id
      FROM public.factures_honoraires f
     WHERE f.mission_id = p_mission_id
       AND f.type_document = 'FACTURE'
       AND f.statut IN ('BROUILLON', 'EMISE', 'EN_RETARD', 'PAYEE')
     ORDER BY f.date_emission DESC NULLS LAST
     LIMIT 1
     FOR UPDATE;
  END IF;

  v_fenetre_ouverte := public.fn_fenetre_contestation_ouverte(
    p_type_litige, p_mission_id, v_facture_id
  );
  v_est_informatif := NOT v_fenetre_ouverte;
  IF v_est_informatif
     AND p_type_litige NOT IN (
       'COMPORTEMENT_SOIGNANT',
       'COMPORTEMENT_ETABLISSEMENT',
       'CONDITIONS_MISSION_NON_RESPECTEES'
     ) THEN
    RETURN jsonb_build_object(
      'error',
      'Fenêtre de contestation fermée pour ce type de litige. Contactez le support.'
    );
  END IF;

  SELECT p.id
    INTO v_presence_id
    FROM public.presences p
   WHERE p.mission_id = p_mission_id
   ORDER BY p.cree_le DESC
   LIMIT 1;

  INSERT INTO public.litiges (
    mission_id, soignant_id, etablissement_id, presence_id, facture_id,
    initie_par, motif, statut, type_litige, est_informatif
  ) VALUES (
    p_mission_id, v_soignant_id, v_etab_id, v_presence_id, v_facture_id,
    v_initie_par, trim(p_motif), 'OUVERT', p_type_litige, v_est_informatif
  )
  RETURNING id INTO v_litige_id;

  PERFORM public.fn_ecrire_audit(
    v_user_id, v_initie_par, 'LITIGE_OUVERTURE',
    'litige', v_litige_id, NULL,
    jsonb_build_object(
      'mission_id', p_mission_id,
      'type_litige', p_type_litige,
      'initie_par', v_initie_par,
      'est_informatif', v_est_informatif,
      'facture_id', v_facture_id
    ),
    NULL, NULL
  );

  RETURN jsonb_build_object(
    'success', true,
    'litige_id', v_litige_id,
    'est_informatif', v_est_informatif,
    'facture_id', v_facture_id
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_ouvrir_litige_rate_limited(
  p_mission_id uuid,
  p_motif text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
BEGIN
  IF v_user_id IS NULL OR public.fn_compte_auth_actif() IS NOT TRUE THEN
    RETURN jsonb_build_object('error', 'Accès refusé');
  END IF;

  RETURN public.fn_ouvrir_litige_rate_limited(
    p_mission_id, 'AUTRE'::public.type_litige, p_motif
  );
END;
$function$;

-- Une réponse ne peut être écrite qu'après sélection autorisée et verrouillée.
-- En médiation, le message ne fait pas régresser le statut vers discussion.
CREATE OR REPLACE FUNCTION public.fn_repondre_litige(
  p_litige_id uuid,
  p_reponse text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_litige record;
  v_auteur text;
  v_type_acteur text;
  v_reponse_safe text;
  v_date_str text;
  v_ip inet;
  v_user_agent text;
  v_headers jsonb;
  v_etablissement_id uuid;
  v_est_admin boolean := false;
BEGIN
  IF v_uid IS NULL OR public.fn_compte_auth_actif() IS NOT TRUE THEN
    RETURN jsonb_build_object('error', 'Accès refusé');
  END IF;

  v_etablissement_id := public.mon_etablissement_id();
  v_est_admin := public.est_admin();
  SELECT l.*
    INTO v_litige
    FROM public.litiges l
   WHERE l.id = p_litige_id
     AND (
       l.soignant_id = v_uid
       OR (
         l.etablissement_id = v_etablissement_id
         AND public.fn_a_permission_etablissement(
           'contrats', l.etablissement_id
         ) IS TRUE
       )
       OR v_est_admin
     )
   FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Litige introuvable ou accès refusé');
  END IF;
  IF v_litige.statut NOT IN (
    'OUVERT', 'EN_DISCUSSION', 'EN_MEDIATION', 'MEDIATION_EN_COURS'
  ) THEN
    RETURN jsonb_build_object('error', 'Ce litige est déjà clôturé');
  END IF;

  IF v_uid = v_litige.soignant_id THEN
    v_auteur := 'Soignant';
    v_type_acteur := 'SOIGNANT';
  ELSIF v_etablissement_id = v_litige.etablissement_id
        AND public.fn_a_permission_etablissement(
          'contrats', v_litige.etablissement_id
        ) IS TRUE THEN
    v_auteur := 'Établissement';
    v_type_acteur := 'ADMIN_ETABLISSEMENT';
  ELSIF v_est_admin THEN
    v_auteur := 'Admin';
    v_type_acteur := 'ADMIN_PLATEFORME';
  ELSE
    RETURN jsonb_build_object('error', 'Accès refusé');
  END IF;

  v_reponse_safe := left(
    regexp_replace(
      COALESCE(NULLIF(trim(p_reponse), ''), ''), '<[^>]*>', '', 'g'
    ),
    2000
  );
  IF length(v_reponse_safe) < 10 THEN
    RETURN jsonb_build_object(
      'error', 'La réponse doit contenir au moins 10 caractères'
    );
  END IF;
  v_date_str := to_char(now(), 'DD/MM/YYYY HH24:MI');

  UPDATE public.litiges
     SET reponse = CASE
       WHEN reponse IS NOT NULL AND reponse <> '' THEN
         reponse || E'\n---\n[' || v_date_str || '] '
           || v_auteur || ': ' || v_reponse_safe
       ELSE '[' || v_date_str || '] ' || v_auteur || ': ' || v_reponse_safe
     END,
     statut = CASE
       WHEN statut IN ('EN_MEDIATION', 'MEDIATION_EN_COURS') THEN statut
       ELSE 'EN_DISCUSSION'
     END
   WHERE id = p_litige_id;

  BEGIN
    v_headers := current_setting('request.headers', true)::jsonb;
    v_ip := NULLIF(
      trim(split_part(COALESCE(v_headers->>'x-forwarded-for', ''), ',', 1)),
      ''
    )::inet;
    v_user_agent := NULLIF(v_headers->>'user-agent', '');
  EXCEPTION WHEN OTHERS THEN
    v_ip := NULL;
    v_user_agent := NULL;
  END;

  PERFORM public.fn_ecrire_audit(
    v_uid, v_type_acteur, 'LITIGE_REPONSE',
    'litige', p_litige_id, NULL,
    jsonb_build_object(
      'mission_id', v_litige.mission_id,
      'motif_original', v_litige.motif,
      'auteur_reponse', v_auteur,
      'reponse_length', length(v_reponse_safe),
      'nouveau_statut', CASE
        WHEN v_litige.statut IN ('EN_MEDIATION', 'MEDIATION_EN_COURS')
          THEN v_litige.statut
        ELSE 'EN_DISCUSSION'
      END
    ),
    v_ip, v_user_agent
  );

  RETURN jsonb_build_object('success', true);
END;
$function$;

-- Arbitrage non financier : REVUE_ADMIN et tout payload de proposition sont
-- réservés à fn_admin_valider_accord_litige. Cette RPC ne peut trancher qu'un
-- litige actif sans proposition structurée, sous verrou de ligne.
CREATE OR REPLACE FUNCTION public.fn_admin_trancher_litige(
  p_litige_id uuid,
  p_decision text,
  p_motif text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_litige record;
  v_decision_clean text;
  v_statut_final text;
  v_motif_clean text;
BEGIN
  IF public.est_admin() IS NOT TRUE THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Seul l''administrateur peut trancher'
    );
  END IF;

  v_decision_clean := upper(trim(COALESCE(p_decision, '')));
  IF v_decision_clean NOT IN (
    'FAVEUR_SOIGNANT', 'FAVEUR_ETAB', 'PARTAGE'
  ) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Décision invalide (FAVEUR_SOIGNANT/FAVEUR_ETAB/PARTAGE)'
    );
  END IF;
  v_motif_clean := trim(COALESCE(p_motif, ''));
  IF length(v_motif_clean) < 50 OR length(v_motif_clean) > 2000 THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Le motif doit contenir entre 50 et 2000 caractères'
    );
  END IF;

  SELECT l.*
    INTO v_litige
    FROM public.litiges l
   WHERE l.id = p_litige_id
   FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'success', false, 'error', 'Litige introuvable'
    );
  END IF;
  IF v_litige.statut = 'REVUE_ADMIN'
     OR v_litige.payload_modifications IS NOT NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error',
      'Accord structuré à traiter via fn_admin_valider_accord_litige'
    );
  END IF;
  IF v_litige.statut NOT IN (
    'OUVERT', 'EN_DISCUSSION', 'EN_MEDIATION', 'MEDIATION_EN_COURS'
  ) THEN
    RETURN jsonb_build_object(
      'success', false, 'error', 'Litige déjà résolu ou non arbitrable'
    );
  END IF;

  v_statut_final := 'RESOLU_' || v_decision_clean;
  UPDATE public.litiges
     SET statut = v_statut_final,
         resolution = v_motif_clean,
         resolu_par = v_uid,
         resolu_le = now()
   WHERE id = p_litige_id;

  INSERT INTO public.notifications (
    destinataire_id, type_destinataire, type, titre, corps, lien
  ) VALUES
    (
      v_litige.soignant_id,
      'SOIGNANT',
      'LITIGE_RESOLU',
      CASE v_decision_clean
        WHEN 'FAVEUR_SOIGNANT' THEN 'Litige tranché en votre faveur ✅'
        WHEN 'FAVEUR_ETAB' THEN 'Litige tranché en faveur de l''établissement'
        ELSE 'Litige tranché : décision partagée'
      END,
      v_motif_clean,
      '/soignant/litiges'
    ),
    (
      v_litige.etablissement_id,
      'ETABLISSEMENT',
      'LITIGE_RESOLU',
      CASE v_decision_clean
        WHEN 'FAVEUR_SOIGNANT' THEN 'Litige tranché en faveur du soignant'
        WHEN 'FAVEUR_ETAB' THEN 'Litige tranché en votre faveur ✅'
        ELSE 'Litige tranché : décision partagée'
      END,
      v_motif_clean,
      '/etablissement/litiges'
    );

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_uid,
    p_type_acteur := 'ADMIN_PLATEFORME',
    p_action := 'LITIGE_ADMIN_TRANCHE',
    p_type_ressource := 'litige',
    p_id_ressource := p_litige_id,
    p_details := jsonb_build_object(
      'decision', v_decision_clean,
      'statut_final', v_statut_final,
      'motif', v_motif_clean
    )
  );

  RETURN jsonb_build_object(
    'success', true, 'statut_final', v_statut_final
  );
END;
$function$;

-- La messagerie suit la même autorisation que le litige. Une liste blanche de
-- statuts actifs évite qu'un nouveau statut terminal devienne écrivable par
-- défaut ; REVUE_ADMIN reste ouverte aux échanges mais pas à l'arbitrage RPC.
CREATE OR REPLACE FUNCTION public.fn_ajouter_message_litige(
  p_litige_id uuid,
  p_contenu text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_litige record;
  v_type_auteur text;
  v_etablissement_id uuid;
  v_est_admin boolean := false;
  v_contenu text;
BEGIN
  IF v_uid IS NULL OR public.fn_compte_auth_actif() IS NOT TRUE THEN
    RETURN jsonb_build_object('error', 'Accès refusé');
  END IF;

  v_etablissement_id := public.mon_etablissement_id();
  v_est_admin := public.est_admin();
  SELECT l.*
    INTO v_litige
    FROM public.litiges l
   WHERE l.id = p_litige_id
     AND (
       l.soignant_id = v_uid
       OR (
         l.etablissement_id = v_etablissement_id
         AND public.fn_a_permission_etablissement(
           'contrats', l.etablissement_id
         ) IS TRUE
       )
       OR v_est_admin
     )
   FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Litige introuvable ou accès refusé');
  END IF;
  IF v_litige.statut NOT IN (
    'OUVERT', 'EN_DISCUSSION', 'EN_MEDIATION', 'MEDIATION_EN_COURS',
    'REVUE_ADMIN'
  ) THEN
    RETURN jsonb_build_object('error', 'Ce litige est clôturé.');
  END IF;

  v_contenu := trim(COALESCE(p_contenu, ''));
  IF length(v_contenu) < 10 OR length(v_contenu) > 5000 THEN
    RETURN jsonb_build_object(
      'error', 'Le message doit contenir entre 10 et 5000 caractères.'
    );
  END IF;

  IF v_uid = v_litige.soignant_id THEN
    v_type_auteur := 'SOIGNANT';
  ELSIF v_etablissement_id = v_litige.etablissement_id
        AND public.fn_a_permission_etablissement(
          'contrats', v_litige.etablissement_id
        ) IS TRUE THEN
    v_type_auteur := 'ETABLISSEMENT';
  ELSIF v_est_admin THEN
    v_type_auteur := 'ADMIN';
  ELSE
    RETURN jsonb_build_object('error', 'Accès refusé');
  END IF;

  INSERT INTO public.messages_litige (
    litige_id, auteur_id, type_auteur, contenu
  ) VALUES (
    p_litige_id, v_uid, v_type_auteur, public.fn_html_escape(v_contenu)
  );

  IF v_type_auteur = 'SOIGNANT' THEN
    INSERT INTO public.notifications (
      destinataire_id, type, titre, corps, lien, type_destinataire
    ) VALUES (
      v_litige.etablissement_id,
      'SYSTEM',
      'Nouveau message sur le litige',
      'Un message a été ajouté au litige concernant la mission.',
      '/etablissement/missions/' || v_litige.mission_id,
      'ETABLISSEMENT'
    );
  ELSIF v_type_auteur = 'ETABLISSEMENT' THEN
    INSERT INTO public.notifications (
      destinataire_id, type, titre, corps, lien, type_destinataire
    ) VALUES (
      v_litige.soignant_id,
      'SYSTEM',
      'Nouveau message sur le litige',
      'Un message a été ajouté au litige concernant la mission.',
      '/soignant/mes-missions/' || v_litige.mission_id,
      'SOIGNANT'
    );
  ELSE
    INSERT INTO public.notifications (
      destinataire_id, type, titre, corps, lien, type_destinataire
    ) VALUES
      (
        v_litige.soignant_id,
        'SYSTEM',
        'Nouveau message de l''équipe Jolene',
        'Un message administrateur a été ajouté à votre litige.',
        '/soignant/litiges',
        'SOIGNANT'
      ),
      (
        v_litige.etablissement_id,
        'SYSTEM',
        'Nouveau message de l''équipe Jolene',
        'Un message administrateur a été ajouté à votre litige.',
        '/etablissement/litiges',
        'ETABLISSEMENT'
      );
  END IF;

  RETURN jsonb_build_object('success', true);
END;
$function$;

-- ---------------------------------------------------------------------------
-- 6. Résolution d'alerte système : pas de colonne resolu_par. Le schéma Lot 19
--    porte resolu_motif et details ; l'acteur y est donc tracé sans DDL inutile.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_admin_resoudre_alerte(p_alerte_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT public.est_admin() THEN
    RETURN jsonb_build_object('error', 'Accès refusé');
  END IF;

  UPDATE public.alertes_systeme
     SET resolu_le = COALESCE(resolu_le, now()),
         resolu_motif = COALESCE(
           resolu_motif,
           'Résolution manuelle par un administrateur'
         ),
         details = COALESCE(details, '{}'::jsonb)
           || jsonb_build_object(
             'resolution_admin', jsonb_build_object(
               'resolu_par', auth.uid(),
               'resolu_le', now()
             )
           )
   WHERE id = p_alerte_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Alerte introuvable');
  END IF;

  RETURN jsonb_build_object('ok', true);
END;
$function$;

-- ---------------------------------------------------------------------------
-- 7. fn_list_admin_user_ids retourne SETOF uuid (colonne anonyme), pas une
--    table avec colonne id. Les alias de colonne explicites corrigent les cinq
--    flux concernés et rendent le tableau vide typé/fiable lorsqu'il n'y a pas
--    d'administrateur destinataire.
-- ---------------------------------------------------------------------------
SELECT pg_temp.jolene_replace_function_fragment(
  'public.fn_envoyer_message_contact(text,text,text)'::regprocedure,
  $old$FROM unnest(ARRAY(SELECT id FROM public.fn_list_admin_user_ids())) AS uid;$old$,
  $new$FROM public.fn_list_admin_user_ids() AS admins(uid);$new$
);

SELECT pg_temp.jolene_replace_function_fragment(
  'public.fn_detecter_teleportations()'::regprocedure,
  $old$v_admin_ids := ARRAY(SELECT id FROM public.fn_list_admin_user_ids());$old$,
  $new$SELECT COALESCE(array_agg(admin_user_id), ARRAY[]::uuid[])
      INTO v_admin_ids
      FROM public.fn_list_admin_user_ids() AS admins(admin_user_id);$new$
);

SELECT pg_temp.jolene_replace_function_fragment(
  'public.fn_escalade_remplacement_non_pourvu()'::regprocedure,
  $old$FROM unnest(ARRAY(SELECT id FROM public.fn_list_admin_user_ids())) AS uid;$old$,
  $new$FROM public.fn_list_admin_user_ids() AS admins(uid);$new$
);

CREATE OR REPLACE FUNCTION public.fn_alerte_reclamations_pending_old()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_count integer;
  v_liste jsonb;
  v_admin_ids uuid[] := ARRAY[]::uuid[];
BEGIN
  SELECT count(*),
         jsonb_agg(jsonb_build_object(
           'id', id,
           'evenement_type', evenement_type,
           'contesteur_id', contesteur_id,
           'motif_categorie', motif_categorie,
           'texte_libre', left(texte_libre, 100),
           'cree_le', cree_le,
           'jours_attente', extract(epoch FROM (now() - cree_le)) / 86400
         ) ORDER BY cree_le ASC)
    INTO v_count, v_liste
    FROM public.reclamations_score
   WHERE statut = 'PENDING'
     AND cree_le < now() - interval '14 days';

  IF v_count = 0 THEN
    RETURN jsonb_build_object('success', true, 'count', 0);
  END IF;

  SELECT COALESCE(array_agg(admin_user_id), ARRAY[]::uuid[])
    INTO v_admin_ids
    FROM public.fn_list_admin_user_ids() AS admins(admin_user_id);

  IF cardinality(v_admin_ids) > 0 THEN
    INSERT INTO public.externalisation_actions (
      type_action, payload, source, source_id
    )
    SELECT
      'EMAIL_NOTIF',
      jsonb_build_object(
        'destinataire_id', uid,
        'type', 'ALERTE_RECLAMATIONS_PENDING',
        'data', jsonb_build_object(
          'count', v_count,
          'liste', v_liste,
          'lien_admin', 'https://jolene.app/admin/reclamations-score'
        )
      ),
      'CRON_ALERTES',
      NULL
    FROM unnest(v_admin_ids) AS uid;

    INSERT INTO public.externalisation_actions (
      type_action, payload, source, source_id
    )
    SELECT
      'PUSH_NOTIF',
      jsonb_build_object(
        'destinataire_id', uid,
        'type_evenement', 'ALERTE_ADMIN',
        'titre', '⚠️ ' || v_count || ' réclamation'
          || CASE WHEN v_count > 1 THEN 's' ELSE '' END
          || ' en attente > 14j',
        'corps', 'Examen requis.',
        'lien', '/admin/reclamations-score'
      ),
      'CRON_ALERTES',
      NULL
    FROM unnest(v_admin_ids) AS uid;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'count', v_count,
    'admins_notifies', cardinality(v_admin_ids)
  );
END;
$function$;

-- ---------------------------------------------------------------------------
-- Exécution d'un accord : fail-closed sur les opérations comptables qui ne
-- disposent pas encore d'une traduction exacte et atomique.
--
-- L'implémentation historique fabriquait directement une action
-- AVOIR_PDF_GENERATION sans montant pour MODIFICATION_HORAIRES et MIXTE. Le
-- worker interprète l'absence de montant comme un avoir total : une simple
-- correction d'horaires pouvait donc annuler toute la facture. Elle marquait
-- aussi l'accord exécuté même lorsqu'une sous-RPC retournait success=false.
--
-- Au lancement, seuls les chemins dont les effets sont bornés et durables sont
-- automatisés : accord sans impact, annulation totale et compensation
-- partielle. Les trois ajustements nécessitant un recalcul de facture restent
-- disponibles via la résolution financière admin, qui traite explicitement
-- BROUILLON / EMISE / PAYEE. Aucun avoir approximatif n'est généré ici.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_executer_modifications_litige(
  p_litige_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_litige record;
  v_payload jsonb;
  v_type text;
  v_modifications jsonb;
  v_result jsonb;
  v_results jsonb := '[]'::jsonb;
  v_audit_result jsonb;
  v_rows integer;
  v_internal boolean := COALESCE(
    current_setting('jolene.litige_exec_ok', true), ''
  ) = 'true';
BEGIN
  IF public.est_admin() IS NOT TRUE AND v_internal IS NOT TRUE THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Exécution de l''accord non autorisée'
    );
  END IF;

  SELECT l.*
    INTO v_litige
    FROM public.litiges l
   WHERE l.id = p_litige_id
   FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Litige introuvable'
    );
  END IF;

  IF v_litige.modifications_executees IS TRUE THEN
    RETURN jsonb_build_object(
      'success', true,
      'already_executed', true,
      'executees_a', v_litige.modifications_executees_a
    );
  END IF;

  IF v_litige.accord_soignant IS NOT TRUE
     OR v_litige.accord_etablissement IS NOT TRUE
     OR v_litige.accord_soignant_le IS NULL
     OR v_litige.accord_etablissement_le IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Double accord horodaté requis avant exécution'
    );
  END IF;

  v_payload := v_litige.payload_modifications;
  IF v_payload IS NULL THEN
    IF v_litige.statut <> 'RESOLU_ACCORD_PARTIES' THEN
      RETURN jsonb_build_object(
        'success', false,
        'error', 'Statut incompatible avec un accord sans modification'
      );
    END IF;
    v_type := 'ACCORD_SANS_MODIFICATION';
    v_results := jsonb_build_array(
      jsonb_build_object('type', v_type, 'success', true)
    );
  ELSE
    IF jsonb_typeof(v_payload) IS DISTINCT FROM 'object'
       OR jsonb_typeof(v_payload->'type') IS DISTINCT FROM 'string'
       OR jsonb_typeof(v_payload->'modifications') IS DISTINCT FROM 'object'
       OR jsonb_typeof(v_payload->'justification') IS DISTINCT FROM 'string'
       OR btrim(v_payload->>'justification') = ''
       OR length(v_payload->>'justification') > 2000
       OR v_payload - ARRAY[
         'type', 'modifications', 'justification'
       ]::text[] <> '{}'::jsonb THEN
      RETURN jsonb_build_object(
        'success', false,
        'error', 'Schéma de proposition stocké invalide'
      );
    END IF;

    v_type := v_payload->>'type';
    v_modifications := v_payload->'modifications';

    IF v_type IN (
      'MODIFICATION_HORAIRES',
      'MODIFICATION_MONTANT',
      'MIXTE'
    ) THEN
      RETURN jsonb_build_object(
        'success', false,
        'error_code', 'RESOLUTION_FINANCIERE_MANUELLE_REQUISE',
        'error', 'Cet ajustement doit être appliqué via la résolution financière administrateur.',
        'manual_resolution_required', true,
        'type', v_type
      );
    END IF;

    IF v_type = 'ACCORD_SANS_MODIFICATION' THEN
      IF v_litige.statut <> 'RESOLU_ACCORD_PARTIES'
         OR v_modifications <> '{}'::jsonb THEN
        RETURN jsonb_build_object(
          'success', false,
          'error', 'Accord sans modification incohérent'
        );
      END IF;
      v_results := jsonb_build_array(
        jsonb_build_object('type', v_type, 'success', true)
      );
    ELSIF v_type = 'ANNULATION_TOTALE' THEN
      IF public.est_admin() IS NOT TRUE
         OR v_litige.statut <> 'REVUE_ADMIN'
         OR jsonb_typeof(v_modifications->'motif_annulation') IS DISTINCT FROM 'string'
         OR btrim(v_modifications->>'motif_annulation') = ''
         OR v_modifications - ARRAY['motif_annulation']::text[]
           <> '{}'::jsonb THEN
        RETURN jsonb_build_object(
          'success', false,
          'error', 'Annulation totale non autorisée ou mal formée'
        );
      END IF;

      -- Un paiement Connect est une charge plateforme suivie d'un transfer
      -- séparé. Le remboursement de la charge seule ne reprendrait pas les
      -- fonds déjà envoyés au compte connecté. Tant qu'un reversal exact et
      -- atomique n'est pas implémenté, la résolution reste manuelle et
      -- l'accord ne doit surtout pas être marqué exécuté.
      IF EXISTS (
        SELECT 1
          FROM public.stripe_transfers st
         WHERE st.mission_id = v_litige.mission_id
           AND st.statut NOT IN ('ECHOUE', 'ANNULEE', 'REMBOURSE')
      ) THEN
        RETURN jsonb_build_object(
          'success', false,
          'error_code', 'RESOLUTION_FINANCIERE_MANUELLE_REQUISE',
          'error', 'Le paiement Stripe Connect exige un remboursement et un reversal vérifiés par un administrateur.',
          'manual_resolution_required', true,
          'type', v_type
        );
      END IF;

      v_result := public.fn_annuler_mission_complete(
        v_litige.mission_id,
        v_payload->>'justification',
        p_litige_id
      );
      IF COALESCE(v_result @> '{"success": true}'::jsonb, false) IS NOT TRUE THEN
        RAISE EXCEPTION 'Échec atomique de l''annulation totale: %',
          COALESCE(v_result->>'error', 'résultat interne invalide');
      END IF;
      v_results := jsonb_build_array(v_result);
    ELSIF v_type = 'COMPENSATION_PARTIELLE' THEN
      IF public.est_admin() IS NOT TRUE
         OR v_litige.statut <> 'REVUE_ADMIN'
         OR jsonb_typeof(
           v_modifications->'pourcentage_compensation'
         ) IS DISTINCT FROM 'number'
         OR v_modifications - ARRAY['pourcentage_compensation']::text[]
           <> '{}'::jsonb
         OR (v_modifications->>'pourcentage_compensation')::numeric <= 0
         OR (v_modifications->>'pourcentage_compensation')::numeric > 100 THEN
        RETURN jsonb_build_object(
          'success', false,
          'error', 'Compensation partielle non autorisée ou mal formée'
        );
      END IF;

      IF EXISTS (
        SELECT 1
          FROM public.stripe_transfers st
         WHERE st.mission_id = v_litige.mission_id
           AND st.statut NOT IN ('ECHOUE', 'ANNULEE', 'REMBOURSE')
      ) THEN
        RETURN jsonb_build_object(
          'success', false,
          'error_code', 'RESOLUTION_FINANCIERE_MANUELLE_REQUISE',
          'error', 'Le paiement Stripe Connect exige un remboursement et un reversal vérifiés par un administrateur.',
          'manual_resolution_required', true,
          'type', v_type
        );
      END IF;

      v_result := public.fn_appliquer_compensation_partielle(
        v_litige.mission_id,
        (v_modifications->>'pourcentage_compensation')::numeric,
        v_payload->>'justification',
        p_litige_id
      );
      IF COALESCE(v_result @> '{"success": true}'::jsonb, false) IS NOT TRUE THEN
        RAISE EXCEPTION 'Échec atomique de la compensation partielle: %',
          COALESCE(v_result->>'error', 'résultat interne invalide');
      END IF;
      v_results := jsonb_build_array(v_result);
    ELSE
      RETURN jsonb_build_object(
        'success', false,
        'error', 'Type de modification non pris en charge'
      );
    END IF;
  END IF;

  UPDATE public.litiges
     SET modifications_executees = true,
         modifications_executees_a = now(),
         modifications_executees_par = v_uid
   WHERE id = p_litige_id
     AND modifications_executees IS NOT TRUE;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 1 THEN
    RAISE EXCEPTION 'Marquage concurrent de l''accord exécuté refusé';
  END IF;

  v_audit_result := public.fn_ecrire_audit_safe(
    p_acteur_id := v_uid,
    p_type_acteur := CASE
      WHEN public.est_admin() THEN 'ADMIN_PLATEFORME'
      ELSE 'SYSTEME'
    END,
    p_action := 'LITIGE_RESOLUTION',
    p_type_ressource := 'litige',
    p_id_ressource := p_litige_id,
    p_details := jsonb_build_object(
      'evenement', 'LITIGE_MODIFICATIONS_EXECUTEES',
      'type', v_type,
      'mission_id', v_litige.mission_id,
      'results', v_results
    )
  );
  IF COALESCE(v_audit_result @> '{"success": true}'::jsonb, false)
       IS NOT TRUE THEN
    RAISE EXCEPTION 'Audit d''exécution d''accord non écrit: %',
      COALESCE(v_audit_result->>'error', 'résultat interne invalide');
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'type', v_type,
    'results', v_results
  );
END;
$function$;

-- Le taux d'une mission libérale n'est pas un salaire horaire : l'ancien
-- plancher global à 11,88 € mélangeait les régimes. La garde universelle reste
-- strictement positive et bornée ; les minima salariaux relèvent des règles CDD.
ALTER TABLE public.missions
  DROP CONSTRAINT IF EXISTS chk_taux_horaire_raisonnable;
ALTER TABLE public.missions
  ADD CONSTRAINT chk_taux_horaire_raisonnable
  CHECK (
    taux_horaire_base = 0
    OR (taux_horaire_base > 0 AND taux_horaire_base <= 1000)
  );

-- La modale admin appelle cette signature à six arguments. La résolution est
-- une seule transaction : litige, mission, présence et facture sont verrouillés
-- avant de choisir l'action comptable. Un accord exact accepté en REVUE_ADMIN
-- est appliqué tel quel ; toute valeur différente fournie par l'admin devient
-- une décision de remplacement explicitement auditée.
CREATE OR REPLACE FUNCTION public.fn_admin_resoudre_litige(
  p_litige_id uuid,
  p_resolution text,
  p_en_faveur_de text DEFAULT NULL,
  p_ajuster_heures numeric DEFAULT NULL,
  p_ajuster_taux numeric DEFAULT NULL,
  p_action_financiere text DEFAULT 'AUTO'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_litige public.litiges%ROWTYPE;
  v_mission public.missions%ROWTYPE;
  v_presence public.presences%ROWTYPE;
  v_facture public.factures_honoraires%ROWTYPE;
  v_transfer public.stripe_transfers%ROWTYPE;
  v_facture_trouvee boolean := false;
  v_presence_trouvee boolean := false;
  v_transfer_trouve boolean := false;
  v_action text := upper(btrim(COALESCE(p_action_financiere, 'AUTO')));
  v_faveur text := upper(btrim(COALESCE(p_en_faveur_de, 'NEUTRE')));
  v_nouveau_statut text;
  v_heures_ref numeric;
  v_taux_ref numeric;
  v_heures_payload numeric;
  v_montant_payload numeric;
  v_heures_final numeric;
  v_taux_final numeric;
  v_nouveau_montant_ht numeric;
  v_nouveau_montant_tva numeric;
  v_nouveau_montant_ttc numeric;
  v_diff numeric;
  v_diff_tva numeric;
  v_diff_ttc numeric;
  v_payload jsonb;
  v_modifications jsonb;
  v_type_payload text;
  v_arrivee_payload timestamptz;
  v_depart_payload timestamptz;
  v_accord_remplace boolean := false;
  v_ajustement_demande boolean := false;
  v_helper_result jsonb;
  v_audit_result jsonb;
  v_regen_id bigint;
  v_regen_ids bigint[] := ARRAY[]::bigint[];
  v_nouvelle_facture_id uuid;
  v_nouveau_numero text;
  v_avoir_id uuid;
  v_avoir_numero text;
  v_mode_remboursement public.mode_remboursement_avoir;
  v_delai_stripe_j integer;
  v_delai_urssaf_j integer;
  v_regul_sociale boolean := false;
  v_rows integer;
  v_email_data jsonb;
BEGIN
  IF v_uid IS NULL OR public.est_admin() IS NOT TRUE THEN
    RETURN jsonb_build_object('error', 'Admin AAL2 requis pour cette opération.');
  END IF;
  IF length(btrim(COALESCE(p_resolution, ''))) < 10
     OR length(btrim(COALESCE(p_resolution, ''))) > 5000 THEN
    RETURN jsonb_build_object(
      'error', 'La résolution doit contenir entre 10 et 5 000 caractères.'
    );
  END IF;
  IF v_faveur NOT IN ('SOIGNANT', 'ETABLISSEMENT', 'NEUTRE') THEN
    RETURN jsonb_build_object(
      'error', 'p_en_faveur_de doit être SOIGNANT, ETABLISSEMENT ou NEUTRE.'
    );
  END IF;
  IF v_action NOT IN (
    'AUTO', 'AUCUNE', 'RECALCUL', 'ANNULER_REEMETTRE', 'AVOIR'
  ) THEN
    RETURN jsonb_build_object('error', 'p_action_financiere invalide.');
  END IF;
  IF p_ajuster_heures IS NOT NULL
     AND (
       p_ajuster_heures::text IN ('NaN', 'Infinity', '-Infinity')
       OR p_ajuster_heures <= 0
       OR p_ajuster_heures > 168
     ) THEN
    RETURN jsonb_build_object(
      'error', 'Les heures ajustées doivent être finies, strictement positives et au plus égales à 168.'
    );
  END IF;
  IF p_ajuster_taux IS NOT NULL
     AND (
       p_ajuster_taux::text IN ('NaN', 'Infinity', '-Infinity')
       OR p_ajuster_taux < 0.01
       OR p_ajuster_taux > 1000
     ) THEN
    RETURN jsonb_build_object(
      'error', 'Le taux ajusté doit être fini, strictement positif et au plus égal à 1 000 €.'
    );
  END IF;

  SELECT l.*
    INTO v_litige
    FROM public.litiges l
   WHERE l.id = p_litige_id
   FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Litige introuvable.');
  END IF;
  IF v_litige.statut NOT IN (
    'OUVERT', 'EN_DISCUSSION', 'EN_MEDIATION', 'MEDIATION_EN_COURS',
    'REVUE_ADMIN'
  ) THEN
    RETURN jsonb_build_object('error', 'Ce litige est déjà résolu ou non modifiable.');
  END IF;

  v_payload := v_litige.payload_modifications;
  IF v_payload IS NOT NULL THEN
    IF v_litige.modifications_executees IS TRUE THEN
      RETURN jsonb_build_object(
        'error', 'Les modifications de cet accord ont déjà été exécutées.'
      );
    END IF;
    IF v_litige.statut <> 'REVUE_ADMIN'
       OR v_litige.accord_soignant IS NOT TRUE
       OR v_litige.accord_etablissement IS NOT TRUE
       OR v_litige.accord_soignant_le IS NULL
       OR v_litige.accord_etablissement_le IS NULL THEN
      RETURN jsonb_build_object(
        'error', 'Un payload financier exige REVUE_ADMIN et le double accord horodaté.'
      );
    END IF;
    IF jsonb_typeof(v_payload) IS DISTINCT FROM 'object'
       OR jsonb_typeof(v_payload->'type') IS DISTINCT FROM 'string'
       OR jsonb_typeof(v_payload->'modifications') IS DISTINCT FROM 'object'
       OR jsonb_typeof(v_payload->'justification') IS DISTINCT FROM 'string'
       OR btrim(v_payload->>'justification') = ''
       OR length(v_payload->>'justification') > 2000
       OR v_payload - ARRAY[
         'type', 'modifications', 'justification'
       ]::text[] <> '{}'::jsonb THEN
      RETURN jsonb_build_object('error', 'Schéma de l’accord stocké invalide.');
    END IF;

    v_type_payload := v_payload->>'type';
    v_modifications := v_payload->'modifications';
    IF v_type_payload NOT IN (
      'MODIFICATION_HORAIRES', 'MODIFICATION_MONTANT', 'MIXTE'
    ) THEN
      RETURN jsonb_build_object(
        'error',
        'Ce type d’accord doit être exécuté par son validateur dédié.'
      );
    END IF;

    IF v_type_payload IN ('MODIFICATION_HORAIRES', 'MIXTE') THEN
      IF jsonb_typeof(v_modifications->'pointage_arrivee_le') IS DISTINCT FROM 'string'
         OR jsonb_typeof(v_modifications->'pointage_depart_le') IS DISTINCT FROM 'string'
         OR v_modifications
           - (CASE WHEN v_type_payload = 'MIXTE'
               THEN ARRAY[
                 'pointage_arrivee_le', 'pointage_depart_le',
                 'montant_total_corrige'
               ]::text[]
               ELSE ARRAY[
                 'pointage_arrivee_le', 'pointage_depart_le'
               ]::text[]
             END) <> '{}'::jsonb THEN
        RETURN jsonb_build_object('error', 'Horaires convenus invalides.');
      END IF;
      BEGIN
        v_arrivee_payload :=
          (v_modifications->>'pointage_arrivee_le')::timestamptz;
        v_depart_payload :=
          (v_modifications->>'pointage_depart_le')::timestamptz;
      EXCEPTION WHEN invalid_datetime_format OR datetime_field_overflow THEN
        RETURN jsonb_build_object('error', 'Format des horaires convenus invalide.');
      END;
      IF v_depart_payload <= v_arrivee_payload
         OR v_depart_payload - v_arrivee_payload > interval '7 days' THEN
        RETURN jsonb_build_object('error', 'Plage horaire convenue invalide.');
      END IF;
    END IF;

    IF v_type_payload IN ('MODIFICATION_MONTANT', 'MIXTE') THEN
      IF jsonb_typeof(v_modifications->'montant_total_corrige')
           IS DISTINCT FROM 'number'
         OR (
           v_type_payload = 'MODIFICATION_MONTANT'
           AND v_modifications - ARRAY['montant_total_corrige']::text[]
             <> '{}'::jsonb
         ) THEN
        RETURN jsonb_build_object('error', 'Montant convenu invalide.');
      END IF;
      v_montant_payload :=
        (v_modifications->>'montant_total_corrige')::numeric;
      IF v_montant_payload <= 0 OR v_montant_payload > 10000000 THEN
        RETURN jsonb_build_object('error', 'Montant convenu hors limites.');
      END IF;
    END IF;
  END IF;

  SELECT m.*
    INTO v_mission
    FROM public.missions m
   WHERE m.id = v_litige.mission_id
   FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Mission du litige introuvable.');
  END IF;

  IF v_litige.presence_id IS NOT NULL THEN
    SELECT p.*
      INTO v_presence
      FROM public.presences p
     WHERE p.id = v_litige.presence_id
       AND p.mission_id = v_litige.mission_id
     FOR UPDATE;
    v_presence_trouvee := FOUND;
  ELSE
    SELECT p.*
      INTO v_presence
      FROM public.presences p
     WHERE p.mission_id = v_litige.mission_id
     ORDER BY p.valide_le DESC NULLS LAST, p.cree_le DESC
     LIMIT 1
     FOR UPDATE;
    v_presence_trouvee := FOUND;
  END IF;

  IF (p_ajuster_heures IS NOT NULL
      OR v_type_payload IN ('MODIFICATION_HORAIRES', 'MIXTE'))
     AND v_presence_trouvee IS NOT TRUE THEN
    RETURN jsonb_build_object(
      'error', 'Aucune présence verrouillable pour appliquer les heures.'
    );
  END IF;

  IF v_presence_trouvee
     AND v_type_payload IN ('MODIFICATION_HORAIRES', 'MIXTE') THEN
    v_heures_payload := round(
      GREATEST(
        0,
        EXTRACT(epoch FROM (v_depart_payload - v_arrivee_payload)) / 3600
        - COALESCE(v_presence.duree_pause_min, 0) / 60
      )::numeric,
      2
    );
    IF v_heures_payload <= 0 OR v_heures_payload > 168 THEN
      RETURN jsonb_build_object('error', 'Durée nette convenue hors limites.');
    END IF;
  END IF;

  IF v_litige.facture_id IS NOT NULL THEN
    SELECT f.*
      INTO v_facture
      FROM public.factures_honoraires f
     WHERE f.id = v_litige.facture_id
     FOR UPDATE;
    v_facture_trouvee := FOUND;
  ELSE
    SELECT f.*
      INTO v_facture
      FROM public.factures_honoraires f
     WHERE f.mission_id = v_litige.mission_id
       AND f.type_document = 'FACTURE'
       AND f.statut_litige = 'EN_ATTENTE_LITIGE'
     ORDER BY f.date_emission ASC, f.id
     LIMIT 1
     FOR UPDATE;
    v_facture_trouvee := FOUND;
  END IF;

  IF v_facture_trouvee
     AND (
       v_facture.mission_id IS DISTINCT FROM v_litige.mission_id
       OR v_facture.soignant_id IS DISTINCT FROM v_litige.soignant_id
       OR v_facture.etablissement_id IS DISTINCT FROM v_litige.etablissement_id
       OR v_facture.type_document <> 'FACTURE'
     ) THEN
    RETURN jsonb_build_object(
      'error', 'La facture liée ne correspond pas aux parties et à la mission du litige.'
    );
  END IF;

  -- Le verrou SQL couvre aussi la tentative Connect locale. Une Checkout
  -- Session ne peut pas être expirée de façon atomique en PostgreSQL : tant
  -- que son état n'est pas explicitement ECHOUE/ANNULEE/REMBOURSE, on refuse
  -- de remplacer le document qui a servi à calculer son montant.
  SELECT st.*
    INTO v_transfer
    FROM public.stripe_transfers st
   WHERE st.mission_id = v_litige.mission_id
   ORDER BY st.cree_le DESC, st.id
   LIMIT 1
   FOR UPDATE;
  v_transfer_trouve := FOUND;

  v_ajustement_demande := v_payload IS NOT NULL
    OR p_ajuster_heures IS NOT NULL
    OR p_ajuster_taux IS NOT NULL;
  IF v_ajustement_demande AND v_facture_trouvee IS NOT TRUE THEN
    RETURN jsonb_build_object(
      'error', 'Aucune facture verrouillable pour appliquer cet ajustement.'
    );
  END IF;

  IF v_presence_trouvee THEN
    v_heures_ref := COALESCE(
      v_presence.heures_ajustees_litige,
      v_presence.heures_reelles
    );
  END IF;
  v_taux_ref := v_mission.taux_horaire_base;
  IF v_facture_trouvee AND (v_taux_ref IS NULL OR v_taux_ref = 0) THEN
    v_taux_ref := CASE
      WHEN v_heures_ref > 0 THEN v_facture.montant_ht / v_heures_ref
      ELSE NULL
    END;
  END IF;
  IF v_facture_trouvee AND v_heures_ref IS NULL AND v_taux_ref > 0 THEN
    v_heures_ref := v_facture.montant_ht / v_taux_ref;
  END IF;

  v_heures_final := COALESCE(
    p_ajuster_heures, v_heures_payload, v_heures_ref
  );
  v_taux_final := COALESCE(p_ajuster_taux, v_taux_ref);

  IF v_payload IS NOT NULL THEN
    v_accord_remplace := p_ajuster_taux IS NOT NULL
      OR (
        p_ajuster_heures IS NOT NULL
        AND (
          v_heures_payload IS NULL
          OR abs(p_ajuster_heures - v_heures_payload) > 0.005
        )
      );
  END IF;

  IF v_montant_payload IS NOT NULL AND v_accord_remplace IS NOT TRUE THEN
    v_nouveau_montant_ht := round(v_montant_payload, 2);
  ELSIF v_ajustement_demande THEN
    IF v_heures_final IS NULL OR v_heures_final <= 0
       OR v_heures_final > 168
       OR v_taux_final IS NULL OR v_taux_final < 0.01
       OR v_taux_final > 1000 THEN
      RETURN jsonb_build_object(
        'error', 'Heures ou taux de référence absents ou hors limites.'
      );
    END IF;
    v_nouveau_montant_ht := round(v_heures_final * v_taux_final, 2);
  ELSIF v_facture_trouvee THEN
    v_nouveau_montant_ht := v_facture.montant_ht;
  END IF;

  -- montant_total_corrige désigne bien le total TTC affiché aux parties.
  -- On dérive le HT et la TVA au lieu d'ajouter une seconde fois la TVA.
  IF v_montant_payload IS NOT NULL AND v_accord_remplace IS NOT TRUE THEN
    v_nouveau_montant_ttc := round(v_montant_payload, 2);
    v_nouveau_montant_ht := round(
      v_nouveau_montant_ttc
        / (1 + COALESCE(v_facture.taux_tva, 0) / 100),
      2
    );
    v_nouveau_montant_tva :=
      v_nouveau_montant_ttc - v_nouveau_montant_ht;
  ELSIF v_nouveau_montant_ht IS NOT NULL THEN
    v_nouveau_montant_tva := round(
      v_nouveau_montant_ht * COALESCE(v_facture.taux_tva, 0) / 100,
      2
    );
    v_nouveau_montant_ttc :=
      v_nouveau_montant_ht + v_nouveau_montant_tva;
  END IF;

  IF v_nouveau_montant_ht IS NOT NULL
     AND (
       v_nouveau_montant_ht <= 0 OR v_nouveau_montant_ht > 10000000
       OR v_nouveau_montant_ttc <= 0
       OR v_nouveau_montant_ttc > 10000000
     ) THEN
    RETURN jsonb_build_object('error', 'Montant final hors limites.');
  END IF;

  IF v_action = 'AUTO' THEN
    IF v_ajustement_demande IS NOT TRUE THEN
      v_action := 'AUCUNE';
    ELSIF v_facture.statut = 'BROUILLON' THEN
      v_action := 'RECALCUL';
    ELSIF v_facture.statut IN ('EMISE', 'EN_RETARD') THEN
      v_action := 'ANNULER_REEMETTRE';
    ELSIF v_facture.statut = 'PAYEE' THEN
      v_action := 'AVOIR';
    ELSE
      RETURN jsonb_build_object(
        'error', 'Le statut de la facture ne permet aucune action financière sûre.'
      );
    END IF;
  END IF;

  IF v_action = 'AUCUNE' AND v_ajustement_demande THEN
    RETURN jsonb_build_object(
      'error', 'AUCUNE est interdite lorsqu’un ajustement ou un accord financier existe.'
    );
  END IF;
  IF v_action <> 'AUCUNE' AND v_facture_trouvee IS NOT TRUE THEN
    RETURN jsonb_build_object('error', 'Action financière sans facture interdite.');
  END IF;
  IF v_action IN ('RECALCUL', 'ANNULER_REEMETTRE')
     AND v_transfer_trouve
     AND v_transfer.statut NOT IN ('ECHOUE', 'ANNULEE', 'REMBOURSE')
     AND (
       v_transfer.stripe_checkout_session_id IS NOT NULL
       OR v_transfer.statut IN (
         'EN_ATTENTE', 'CHARGE_REUSSI', 'TRANSFERE', 'PAYE'
       )
     ) THEN
    RETURN jsonb_build_object(
      'error',
      'Une tentative ou un paiement Stripe Connect est encore actif. Expirez ou réconciliez-le avant de modifier la facture.'
    );
  END IF;
  IF v_action = 'RECALCUL' AND v_facture.statut <> 'BROUILLON' THEN
    RETURN jsonb_build_object('error', 'RECALCUL exige une facture BROUILLON.');
  END IF;
  IF v_action = 'ANNULER_REEMETTRE'
     AND v_facture.statut NOT IN ('EMISE', 'EN_RETARD') THEN
    RETURN jsonb_build_object(
      'error', 'ANNULER_REEMETTRE exige une facture EMISE ou EN_RETARD.'
    );
  END IF;
  IF v_action = 'AVOIR' AND v_facture.statut <> 'PAYEE' THEN
    RETURN jsonb_build_object('error', 'AVOIR exige une facture PAYEE.');
  END IF;
  IF v_action <> 'AUCUNE'
     AND v_nouveau_montant_ttc IS NOT DISTINCT FROM v_facture.montant_ttc THEN
    RETURN jsonb_build_object(
      'error', 'L’ajustement ne change pas le montant de la facture.'
    );
  END IF;

  IF v_action = 'ANNULER_REEMETTRE' AND EXISTS (
    SELECT 1
      FROM public.factures_honoraires enfant
     WHERE enfant.facture_precedente_id = v_facture.id
       AND enfant.type_document = 'FACTURE'
       AND enfant.statut NOT IN (
         'ANNULEE', 'REMPLACEE', 'ERREUR_GENERATION'
       )
  ) THEN
    RETURN jsonb_build_object('error', 'Une facture de remplacement existe déjà.');
  END IF;
  IF v_action = 'AVOIR' AND EXISTS (
    SELECT 1
      FROM public.factures_honoraires enfant
     WHERE enfant.facture_precedente_id = v_facture.id
       AND enfant.type_document = 'AVOIR'
       AND enfant.statut NOT IN (
         'ANNULEE', 'REMPLACEE', 'ERREUR_GENERATION'
       )
  ) THEN
    RETURN jsonb_build_object('error', 'Un avoir actif existe déjà pour cette facture.');
  END IF;

  IF v_action = 'RECALCUL' THEN
    UPDATE public.factures_honoraires
       SET montant_ht = v_nouveau_montant_ht,
           montant_tva = v_nouveau_montant_tva,
           montant_ttc = v_nouveau_montant_ttc,
           statut_litige = 'LITIGE_RESOLU_AJUSTE',
           pdf_a_regenerer = true
     WHERE id = v_facture.id
       AND statut = 'BROUILLON';
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    IF v_rows <> 1 THEN
      RAISE EXCEPTION 'Recalcul concurrent refusé';
    END IF;
    v_regen_id := public.fn_trigger_regen_pdf_immediate(v_facture.id);
    IF v_regen_id IS NOT NULL THEN
      IF v_regen_id <= 0 THEN
        RAISE EXCEPTION 'Identifiant de régénération PDF invalide';
      END IF;
      v_regen_ids := array_append(v_regen_ids, v_regen_id);
    END IF;

  ELSIF v_action = 'ANNULER_REEMETTRE' THEN
    UPDATE public.factures_honoraires
       SET statut = 'REMPLACEE',
           statut_litige = 'LITIGE_RESOLU_AJUSTE'
     WHERE id = v_facture.id
       AND statut IN ('EMISE', 'EN_RETARD');
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    IF v_rows <> 1 THEN
      RAISE EXCEPTION 'Remplacement concurrent refusé';
    END IF;

    v_nouveau_numero := public.next_invoice_number(v_facture.soignant_id);
    IF btrim(COALESCE(v_nouveau_numero, '')) = '' THEN
      RAISE EXCEPTION 'Numéro de facture de remplacement invalide';
    END IF;
    INSERT INTO public.factures_honoraires (
      soignant_id, etablissement_id, mission_id,
      numero_facture, montant_ht, montant_tva, montant_ttc,
      taux_tva, exoneration_tva, date_emission, date_echeance,
      statut, mandat_version, type_document, facture_precedente_id,
      statut_litige, litige_id, pdf_a_regenerer,
      periode_debut, periode_fin, numero_semaine_iso, annee_iso,
      est_facture_finale_mission
    ) VALUES (
      v_facture.soignant_id, v_facture.etablissement_id,
      v_facture.mission_id, v_nouveau_numero, v_nouveau_montant_ht,
      v_nouveau_montant_tva, v_nouveau_montant_ttc,
      v_facture.taux_tva, v_facture.exoneration_tva,
      CURRENT_DATE, CURRENT_DATE + 30, 'BROUILLON',
      v_facture.mandat_version, 'FACTURE', v_facture.id,
      'LITIGE_RESOLU_AJUSTE', p_litige_id, true,
      v_facture.periode_debut, v_facture.periode_fin,
      v_facture.numero_semaine_iso, v_facture.annee_iso,
      v_facture.est_facture_finale_mission
    )
    RETURNING id INTO v_nouvelle_facture_id;
    IF v_nouvelle_facture_id IS NULL THEN
      RAISE EXCEPTION 'Facture de remplacement non créée';
    END IF;
    v_regen_id :=
      public.fn_trigger_regen_pdf_immediate(v_nouvelle_facture_id);
    IF v_regen_id IS NOT NULL THEN
      IF v_regen_id <= 0 THEN
        RAISE EXCEPTION 'Identifiant de régénération PDF invalide';
      END IF;
      v_regen_ids := array_append(v_regen_ids, v_regen_id);
    END IF;

  ELSIF v_action = 'AVOIR' THEN
    v_diff := round(v_facture.montant_ht - v_nouveau_montant_ht, 2);
    v_diff_tva := round(v_facture.montant_tva - v_nouveau_montant_tva, 2);
    v_diff_ttc := round(v_facture.montant_ttc - v_nouveau_montant_ttc, 2);
    IF v_diff <= 0 OR v_diff_tva < 0 OR v_diff_ttc <= 0
       OR v_diff_ttc > v_facture.montant_ttc THEN
      RETURN jsonb_build_object(
        'error', 'Un avoir exige un montant corrigé strictement inférieur au montant payé.'
      );
    END IF;

    SELECT COALESCE(pl.valeur::integer, 30)
      INTO v_delai_stripe_j
      FROM public.parametres_litiges pl
     WHERE pl.cle = 'delai_stripe_refund_auto_j';
    v_delai_stripe_j := COALESCE(v_delai_stripe_j, 30);
    IF v_transfer_trouve THEN
      -- Un remboursement Connect doit aussi reprendre le transfer et la
      -- commission. La queue legacy ne sait pas garantir cette atomicité.
      v_mode_remboursement := 'VIREMENT_MANUEL';
    ELSIF v_facture.stripe_payment_intent_id IS NOT NULL
       AND v_facture.date_paiement IS NOT NULL
       AND v_facture.date_paiement
         > CURRENT_DATE - make_interval(days => v_delai_stripe_j) THEN
      v_mode_remboursement := 'AUTO_STRIPE';
    ELSE
      v_mode_remboursement := 'VIREMENT_MANUEL';
    END IF;

    v_avoir_numero := public.next_avoir_number(v_facture.soignant_id);
    IF btrim(COALESCE(v_avoir_numero, '')) = '' THEN
      RAISE EXCEPTION 'Numéro d’avoir invalide';
    END IF;
    INSERT INTO public.factures_honoraires (
      soignant_id, etablissement_id, mission_id,
      numero_facture, montant_ht, montant_tva, montant_ttc,
      taux_tva, exoneration_tva, date_emission, date_echeance,
      statut, mandat_version, type_document, facture_precedente_id,
      statut_litige, litige_id, mode_remboursement, pdf_a_regenerer,
      periode_debut, periode_fin, numero_semaine_iso, annee_iso,
      est_facture_finale_mission
    ) VALUES (
      v_facture.soignant_id, v_facture.etablissement_id,
      v_facture.mission_id, v_avoir_numero, v_diff,
      v_diff_tva, v_diff_ttc,
      v_facture.taux_tva, v_facture.exoneration_tva,
      CURRENT_DATE, CURRENT_DATE, 'EMISE', v_facture.mandat_version,
      'AVOIR', v_facture.id, 'LITIGE_RESOLU_AJUSTE', p_litige_id,
      v_mode_remboursement, true, v_facture.periode_debut,
      v_facture.periode_fin, v_facture.numero_semaine_iso,
      v_facture.annee_iso, v_facture.est_facture_finale_mission
    )
    RETURNING id INTO v_avoir_id;
    IF v_avoir_id IS NULL THEN
      RAISE EXCEPTION 'Avoir non créé';
    END IF;

    UPDATE public.factures_honoraires
       SET statut_litige = 'LITIGE_RESOLU_AJUSTE'
     WHERE id = v_facture.id
       AND statut = 'PAYEE';
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    IF v_rows <> 1 THEN
      RAISE EXCEPTION 'Avoir concurrent refusé';
    END IF;

    IF v_mode_remboursement = 'AUTO_STRIPE' THEN
      INSERT INTO public.stripe_refunds_queue (
        avoir_id, facture_origine_id, stripe_payment_intent_id, montant_cts
      ) VALUES (
        v_avoir_id, v_facture.id, v_facture.stripe_payment_intent_id,
        round(v_diff_ttc * 100)::integer
      );
      GET DIAGNOSTICS v_rows = ROW_COUNT;
      IF v_rows <> 1 THEN
        RAISE EXCEPTION 'Remboursement Stripe non mis en file';
      END IF;
    END IF;

    v_regen_id := public.fn_trigger_regen_pdf_immediate(v_avoir_id);
    IF v_regen_id IS NOT NULL THEN
      IF v_regen_id <= 0 THEN
        RAISE EXCEPTION 'Identifiant de régénération PDF invalide';
      END IF;
      v_regen_ids := array_append(v_regen_ids, v_regen_id);
    END IF;
  END IF;

  -- Les changements de données source arrivent après l'effet comptable. Toute
  -- erreur lève une exception et annule aussi facture/avoir dans la transaction.
  IF v_type_payload IN ('MODIFICATION_HORAIRES', 'MIXTE')
     AND (
       p_ajuster_heures IS NULL
       OR abs(p_ajuster_heures - v_heures_payload) <= 0.005
     ) THEN
    v_helper_result := public.fn_modifier_horaires_presence(
      v_presence.id,
      v_arrivee_payload,
      v_depart_payload,
      v_payload->>'justification'
    );
    IF COALESCE(v_helper_result @> '{"success": true}'::jsonb, false)
         IS NOT TRUE THEN
      RAISE EXCEPTION 'Échec atomique de la correction des horaires: %',
        COALESCE(v_helper_result->>'error', 'résultat interne invalide');
    END IF;
    UPDATE public.presences
       SET heures_ajustees_litige = NULL,
           ajustement_litige_id = p_litige_id,
           motif_litige = left(
             'Accord litige : ' || (v_payload->>'justification'),
             2000
           ),
           modifie_le = now()
     WHERE id = v_presence.id;
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    IF v_rows <> 1 THEN
      RAISE EXCEPTION 'Traçabilité de la correction des horaires non appliquée';
    END IF;
  ELSIF p_ajuster_heures IS NOT NULL THEN
    UPDATE public.presences
       SET heures_ajustees_litige = p_ajuster_heures,
           ajustement_litige_id = p_litige_id,
           motif_litige = left(
             'Décision admin litige : ' || btrim(p_resolution),
             2000
           ),
           modifie_le = now()
     WHERE id = v_presence.id;
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    IF v_rows <> 1 THEN
      RAISE EXCEPTION 'Ajustement de présence non appliqué';
    END IF;
  END IF;

  IF p_ajuster_taux IS NOT NULL THEN
    UPDATE public.missions
       SET taux_horaire_base = p_ajuster_taux,
           modifie_le = now()
     WHERE id = v_mission.id;
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    IF v_rows <> 1 THEN
      RAISE EXCEPTION 'Ajustement de taux non appliqué';
    END IF;
  END IF;

  IF v_action IN ('RECALCUL', 'ANNULER_REEMETTRE', 'AVOIR') THEN
    UPDATE public.missions
       SET commission_a_recalculer = true
     WHERE id = v_mission.id;
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    IF v_rows <> 1 THEN
      RAISE EXCEPTION 'Marquage de recalcul de commission non appliqué';
    END IF;
  END IF;

  IF (p_ajuster_heures IS NOT NULL OR v_heures_payload IS NOT NULL)
     AND v_facture_trouvee
     AND v_action IN ('ANNULER_REEMETTRE', 'AVOIR') THEN
    SELECT COALESCE(pl.valeur::integer, 3) * 30
      INTO v_delai_urssaf_j
      FROM public.parametres_litiges pl
     WHERE pl.cle = 'delai_notif_urssaf_mois';
    v_delai_urssaf_j := COALESCE(v_delai_urssaf_j, 90);
    IF CURRENT_DATE - v_facture.date_emission > v_delai_urssaf_j THEN
      UPDATE public.missions
         SET regularisation_sociale_requise = true
       WHERE id = v_mission.id;
      GET DIAGNOSTICS v_rows = ROW_COUNT;
      IF v_rows <> 1 THEN
        RAISE EXCEPTION 'Régularisation sociale non marquée';
      END IF;
      v_regul_sociale := true;
    END IF;
  END IF;

  v_nouveau_statut := CASE v_faveur
    WHEN 'SOIGNANT' THEN 'RESOLU_SOIGNANT'
    WHEN 'ETABLISSEMENT' THEN 'RESOLU_ETABLISSEMENT'
    ELSE 'RESOLU_ADMIN'
  END;

  UPDATE public.litiges
     SET statut = v_nouveau_statut,
         resolution = btrim(p_resolution),
         resolu_par = v_uid,
         resolu_le = now(),
         modifications_executees = CASE
           WHEN v_payload IS NOT NULL THEN true
           ELSE modifications_executees
         END,
         modifications_executees_a = CASE
           WHEN v_payload IS NOT NULL THEN now()
           ELSE modifications_executees_a
         END,
         modifications_executees_par = CASE
           WHEN v_payload IS NOT NULL THEN v_uid
           ELSE modifications_executees_par
         END
   WHERE id = p_litige_id
     AND statut IN (
       'OUVERT', 'EN_DISCUSSION', 'EN_MEDIATION', 'MEDIATION_EN_COURS',
       'REVUE_ADMIN'
     );
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 1 THEN
    RAISE EXCEPTION 'Résolution concurrente refusée';
  END IF;

  IF v_accord_remplace THEN
    v_audit_result := public.fn_ecrire_audit_safe(
      p_acteur_id := v_uid,
      p_type_acteur := 'ADMIN_PLATEFORME',
      p_action := 'LITIGE_RESOLUTION',
      p_type_ressource := 'litige',
      p_id_ressource := p_litige_id,
      p_details := jsonb_build_object(
        'evenement', 'LITIGE_ACCORD_REMPLACE_PAR_DECISION_ADMIN',
        'accord_payload_remplace', v_payload,
        'accord_soignant_le', v_litige.accord_soignant_le,
        'accord_etablissement_le', v_litige.accord_etablissement_le,
        'resolution_admin', btrim(p_resolution),
        'heures_admin', p_ajuster_heures,
        'taux_admin', p_ajuster_taux,
        'montant_final_ht', v_nouveau_montant_ht,
        'montant_final_ttc', v_nouveau_montant_ttc,
        'action_financiere', v_action
      )
    );
    IF COALESCE(v_audit_result @> '{"success": true}'::jsonb, false)
         IS NOT TRUE THEN
      RAISE EXCEPTION 'Audit du remplacement d’accord non écrit: %',
        COALESCE(v_audit_result->>'error', 'résultat interne invalide');
    END IF;
  END IF;

  v_audit_result := public.fn_ecrire_audit_safe(
    p_acteur_id := v_uid,
    p_type_acteur := 'ADMIN_PLATEFORME',
    p_action := 'LITIGE_RESOLUTION',
    p_type_ressource := 'litige',
    p_id_ressource := p_litige_id,
    p_details := jsonb_build_object(
      'evenement', 'LITIGE_RESOLUTION_FINANCIERE',
      'action_financiere', v_action,
      'en_faveur_de', v_faveur,
      'accord_payload_applique', CASE
        WHEN v_payload IS NOT NULL AND NOT v_accord_remplace THEN v_payload
        ELSE NULL
      END,
      'accord_remplace', v_accord_remplace,
      'heures_final', v_heures_final,
      'taux_final', v_taux_final,
      'montant_avant_ht', CASE
        WHEN v_facture_trouvee THEN v_facture.montant_ht ELSE NULL
      END,
      'montant_avant_ttc', CASE
        WHEN v_facture_trouvee THEN v_facture.montant_ttc ELSE NULL
      END,
      'montant_apres_ht', v_nouveau_montant_ht,
      'montant_apres_ttc', v_nouveau_montant_ttc,
      'facture_id', CASE WHEN v_facture_trouvee THEN v_facture.id ELSE NULL END,
      'nouvelle_facture_id', v_nouvelle_facture_id,
      'avoir_id', v_avoir_id,
      'mode_remboursement', v_mode_remboursement,
      'regularisation_sociale_requise', v_regul_sociale,
      'regen_pdf_request_ids', to_jsonb(v_regen_ids)
    )
  );
  IF COALESCE(v_audit_result @> '{"success": true}'::jsonb, false)
       IS NOT TRUE THEN
    RAISE EXCEPTION 'Audit de résolution non écrit: %',
      COALESCE(v_audit_result->>'error', 'résultat interne invalide');
  END IF;

  IF v_action IN ('RECALCUL', 'ANNULER_REEMETTRE', 'AVOIR') THEN
    v_email_data := jsonb_build_object(
      'action_financiere', v_action,
      'en_faveur_de', v_faveur,
      'resolution', btrim(p_resolution),
      'numero_facture', v_facture.numero_facture,
      'numero_nouvelle', v_nouveau_numero,
      'numero_avoir', v_avoir_numero,
      'montant_avant', v_facture.montant_ht,
      'montant_apres', v_nouveau_montant_ht,
      'montant_avant_ttc', v_facture.montant_ttc,
      'montant_apres_ttc', v_nouveau_montant_ttc
    );
    PERFORM public.fn_litige_push_notification(
      v_litige.soignant_id,
      'SOIGNANT',
      'LITIGE_RESOLU_AJUSTE',
      'Litige résolu — ajustement appliqué',
      'La résolution du litige a été appliquée à la facturation.',
      p_litige_id,
      v_email_data
    );
    PERFORM public.fn_litige_push_notification(
      v_litige.etablissement_id,
      'ETABLISSEMENT',
      'LITIGE_RESOLU_AJUSTE',
      'Litige résolu — ajustement appliqué',
      'La résolution du litige a été appliquée à la facturation.',
      p_litige_id,
      v_email_data
    );
    IF v_action = 'AVOIR' AND v_avoir_id IS NOT NULL THEN
      PERFORM public.fn_litige_push_notification(
        v_litige.soignant_id,
        'SOIGNANT',
        'AVOIR_EMIS',
        'Avoir ' || COALESCE(v_avoir_numero, '') || ' émis',
        'Un avoir a été émis suite à la résolution du litige.',
        p_litige_id,
        jsonb_build_object(
          'avoir_id', v_avoir_id,
          'numero_avoir', v_avoir_numero,
          'numero_facture_origine', v_facture.numero_facture,
          'montant_avoir_ht', v_diff,
          'montant_avoir_ttc', v_diff_ttc,
          'mode_remboursement', v_mode_remboursement,
          'mode_remboursement_texte', CASE v_mode_remboursement::text
            WHEN 'AUTO_STRIPE' THEN
              'Remboursement Stripe automatique (2 à 5 jours ouvrés)'
            WHEN 'VIREMENT_MANUEL' THEN
              'Remboursement manuel après vérification de la reprise des fonds'
            ELSE 'Mode de remboursement à confirmer'
          END
        )
      );
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'action_financiere', v_action,
    'statut', v_nouveau_statut,
    'facture_id', CASE WHEN v_facture_trouvee THEN v_facture.id ELSE NULL END,
    'nouvelle_facture_id', v_nouvelle_facture_id,
    'avoir_id', v_avoir_id,
    'avoir_numero', v_avoir_numero,
    'mode_remboursement', v_mode_remboursement,
    'regularisation_sociale_requise', v_regul_sociale,
    'regen_pdf_request_ids', to_jsonb(v_regen_ids),
    'heures_final', v_heures_final,
    'taux_final', v_taux_final,
    'montant_final_ht', v_nouveau_montant_ht,
    'montant_final_ttc', v_nouveau_montant_ttc,
    'accord_remplace', v_accord_remplace
  );
END;
$function$;

COMMENT ON FUNCTION public.fn_admin_resoudre_litige(
  uuid, text, text, numeric, numeric, text
) IS
  'Résolution admin AAL2 atomique. Verrouille litige/mission/présence/facture, applique la matrice de statuts comptables, protège contre les doubles documents et trace tout remplacement d’un accord accepté.';

-- Ces trois fonctions sont des tâches système/cron. Une recréation de fonction
-- ne doit jamais dépendre des ACL historiques du schéma : on réaffirme ici le
-- périmètre service_role-only après toutes les corrections de corps ci-dessus.
REVOKE ALL ON FUNCTION public.fn_alerte_reclamations_pending_old()
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_detecter_teleportations()
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_escalade_remplacement_non_pourvu()
  FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.fn_alerte_reclamations_pending_old()
  TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_detecter_teleportations()
  TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_escalade_remplacement_non_pourvu()
  TO service_role;

-- Assertions de migration : aucun fragment P0 ciblé ne doit survivre dans le
-- corps effectif des fonctions remplacées.
DO $assertions$
DECLARE
  v_bad text;
BEGIN
  SELECT string_agg(p.oid::regprocedure::text, ', ')
    INTO v_bad
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public'
     AND p.proname = ANY(ARRAY[
       'fn_verifier_coherence_documents',
       'fn_annuler_mission_etab',
       'fn_valider_presences_lot',
       'fn_modifier_tolerance_pointage_etab',
       'fn_cloturer_litige',
       'fn_cloturer_litige_avec_payload',
       'fn_admin_resoudre_alerte',
       'fn_envoyer_message_contact',
       'fn_detecter_teleportations',
       'fn_escalade_remplacement_non_pourvu',
       'fn_alerte_reclamations_pending_old'
     ])
     AND (
       p.prosrc LIKE '%v_mission.type_contrat::text%'
       OR p.prosrc LIKE '%DELETE FROM _validees_lot%'
       OR p.prosrc LIKE '%mis_a_jour_le = now()%'
       OR p.prosrc LIKE '%resolu_par = ''ADMIN''%'
       OR p.prosrc LIKE '%resolu_par = ''ACCORD_MUTUEL''%'
       OR p.prosrc LIKE '%SET resolu_le = now(), resolu_par = auth.uid()%'
       OR p.prosrc LIKE '%ARRAY(SELECT id FROM public.fn_list_admin_user_ids())%'
       OR p.prosrc LIKE '%v_problemes || ''Un ou plusieurs documents%'
     );

  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'Fragments runtime invalides encore présents dans : %', v_bad;
  END IF;
END;
$assertions$;

DROP FUNCTION pg_temp.jolene_replace_function_fragment(regprocedure, text, text);
