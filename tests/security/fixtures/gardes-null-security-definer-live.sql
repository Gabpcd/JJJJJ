-- Corps LIVE (production, lecture seule) des 20 fonctions SECURITY DEFINER du
-- lot « gardes NULL », AVANT la migration
-- supabase/migrations/20261109010957_gardes_null_security_definer.sql.
-- Chaque bloc est le texte exact de pg_get_functiondef(oid) relu le 09/11/2026,
-- suivi d'un « ; » : md5(pg_get_functiondef) et md5(prosrc) identiques en
-- production (empreintes non recopiées ici : elles sont recalculées par le
-- test). Aucune donnée, aucun GRANT (posés par le banc).
-- Usage : tests/node/gardes-null-security-definer.node.mjs vérifie que chaque
-- corps de la migration n'en diffère que par la garde corrigée ; le banc
-- PostgreSQL 17 isolé (tests/security/fixtures/gardes-null-security-definer-banc.sql)
-- crée ces 20 fonctions puis exécute la vraie migration.
-- Regénération : SELECT pg_get_functiondef(to_regprocedure('public.' || signature))
-- en lecture seule, dans l'ordre ci-dessous.

-- 1/20 fn_valider_alerte_presence(uuid)
CREATE OR REPLACE FUNCTION public.fn_valider_alerte_presence(p_presence_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_presence RECORD;
    v_etab_id UUID := mon_etablissement_id();
BEGIN
    SELECT p.*, m.etablissement_id FROM presences p 
    JOIN missions m ON m.id = p.mission_id 
    WHERE p.id = p_presence_id INTO v_presence;
    
    IF v_presence IS NULL THEN RETURN jsonb_build_object('error', 'Présence introuvable'); END IF;
    
    IF v_presence.etablissement_id != v_etab_id AND NOT est_admin() THEN
        RETURN jsonb_build_object('error', 'Accès refusé');
    END IF;
    
    UPDATE presences SET 
        valide_par_etablissement = TRUE, 
        valide_le = NOW()
    WHERE id = p_presence_id;
    
    RETURN jsonb_build_object('success', TRUE, 'message', 'Présence validée');
END;
$function$;

-- 2/20 fn_codes_pointage_mission(uuid)
CREATE OR REPLACE FUNCTION public.fn_codes_pointage_mission(p_mission_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_mission record;
BEGIN
  SELECT id, code_arrivee, code_depart, etablissement_id
  INTO v_mission
  FROM missions WHERE id = p_mission_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Mission introuvable');
  END IF;

  IF NOT est_admin() AND v_mission.etablissement_id != mon_etablissement_id() THEN
    RETURN jsonb_build_object('error', 'Accès interdit');
  END IF;

  IF v_mission.code_arrivee IS NULL THEN
    UPDATE missions SET
      code_arrivee = lpad(floor(random() * 1000000)::text, 6, '0'),
      code_depart = lpad(floor(random() * 1000000)::text, 6, '0')
    WHERE id = p_mission_id
    RETURNING code_arrivee, code_depart INTO v_mission.code_arrivee, v_mission.code_depart;
  END IF;

  RETURN jsonb_build_object(
    'code_arrivee', v_mission.code_arrivee,
    'code_depart', v_mission.code_depart
  );
END;
$function$;

-- 3/20 fn_generer_code_secours_mission(uuid,text)
CREATE OR REPLACE FUNCTION public.fn_generer_code_secours_mission(p_mission_id uuid, p_type text DEFAULT 'UNIVERSEL'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_mission RECORD;
  v_code text;
  v_code_hash text;
  v_expire_le timestamptz;
  v_id uuid;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTHENTIFIE');
  END IF;
  IF p_type NOT IN ('ARRIVEE', 'DEPART', 'UNIVERSEL') THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'TYPE_INVALIDE');
  END IF;

  SELECT id, etablissement_id, fin_le, statut INTO v_mission FROM public.missions WHERE id = p_mission_id;
  IF v_mission IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'MISSION_INTROUVABLE');
  END IF;
  IF NOT (est_admin() OR v_mission.etablissement_id = mon_etablissement_id()) THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTORISE');
  END IF;

  -- Invalider codes précédents non utilisés du même type
  UPDATE public.codes_secours_mission
  SET utilise = true, utilise_le = NOW()
  WHERE mission_id = p_mission_id AND type = p_type AND utilise = false;

  -- Générer 6 chiffres aléatoires (uniformément distribués 0-999999)
  v_code := lpad((floor(random() * 1000000))::text, 6, '0');
  v_code_hash := crypt(v_code, gen_salt('bf'));

  v_expire_le := LEAST(
    COALESCE(v_mission.fin_le, NOW() + INTERVAL '7 days') + INTERVAL '2 hours',
    NOW() + INTERVAL '7 days'
  );

  INSERT INTO public.codes_secours_mission (mission_id, code_hash, type, expire_le, cree_par)
  VALUES (p_mission_id, v_code_hash, p_type, v_expire_le, v_uid)
  RETURNING id INTO v_id;

  -- Audit (sans le code en clair !)
  INSERT INTO public.journaux_audit (
    acteur_id, type_acteur, action, type_ressource, id_ressource, details
  ) VALUES (
    v_uid, 'ADMIN_ETABLISSEMENT', 'SYSTEM', 'code_secours_mission', v_id,
    jsonb_build_object('evenement', 'CODE_SECOURS_GENERE',
                        'mission_id', p_mission_id, 'type', p_type,
                        'expire_le', v_expire_le)
  );

  -- Retourne le code EN CLAIR (une seule fois — jamais re-affiché)
  RETURN jsonb_build_object(
    'success', true,
    'id', v_id,
    'code', v_code,
    'type', p_type,
    'expire_le', v_expire_le
  );
END;
$function$;

-- 4/20 fn_generer_qr_mission(uuid,text)
CREATE OR REPLACE FUNCTION public.fn_generer_qr_mission(p_mission_id uuid, p_type text DEFAULT 'UNIVERSEL'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_mission RECORD;
  v_token text;
  v_expire_le timestamptz;
  v_qr_id uuid;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTHENTIFIE');
  END IF;
  IF p_type NOT IN ('ARRIVEE', 'DEPART', 'UNIVERSEL') THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'TYPE_INVALIDE');
  END IF;

  SELECT id, etablissement_id, debut_le, fin_le, statut INTO v_mission
  FROM public.missions WHERE id = p_mission_id;
  IF v_mission IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'MISSION_INTROUVABLE');
  END IF;

  -- Auth : étab admin de la mission ou admin Jolene
  IF NOT (est_admin() OR v_mission.etablissement_id = mon_etablissement_id()) THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTORISE');
  END IF;

  IF v_mission.statut IN ('LITIGE', 'ANNULEE_PAR_ETABLISSEMENT', 'TERMINEE') THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'MISSION_INACTIVE');
  END IF;

  -- Désactiver les QR actifs précédents du même type
  UPDATE public.qr_codes_mission SET actif = false
  WHERE mission_id = p_mission_id AND type = p_type AND actif = true;

  -- Token = UUID v4 + suffix 16 chars random cryptographique
  v_token := gen_random_uuid()::text || '_' ||
             encode(extensions.gen_random_bytes(8), 'hex');

  -- Expiration : min(date_fin + 2h, NOW() + 7j)
  v_expire_le := LEAST(
    COALESCE(v_mission.fin_le, NOW() + INTERVAL '7 days') + INTERVAL '2 hours',
    NOW() + INTERVAL '7 days'
  );

  INSERT INTO public.qr_codes_mission (mission_id, token, type, expire_le, cree_par)
  VALUES (p_mission_id, v_token, p_type, v_expire_le, v_uid)
  RETURNING id INTO v_qr_id;

  -- Audit
  INSERT INTO public.journaux_audit (
    acteur_id, type_acteur, action, type_ressource, id_ressource, details
  ) VALUES (
    v_uid, 'ADMIN_ETABLISSEMENT', 'SYSTEM', 'qr_code_mission', v_qr_id,
    jsonb_build_object('evenement', 'QR_GENERE',
                        'mission_id', p_mission_id,
                        'type', p_type, 'expire_le', v_expire_le)
  );

  RETURN jsonb_build_object(
    'success', true,
    'qr_id', v_qr_id,
    'token', v_token,
    'type', p_type,
    'expire_le', v_expire_le
  );
END;
$function$;

-- 5/20 fn_soignants_urgence(uuid)
CREATE OR REPLACE FUNCTION public.fn_soignants_urgence(p_mission_id uuid)
 RETURNS TABLE(soignant_id uuid, id uuid, prenom text, nom text, score_fiabilite integer, distance_km numeric, urgence_rayon_km integer, telephone text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_mission record;
BEGIN
  SELECT m.id, m.etablissement_id, e.adresse_lat AS etab_lat, e.adresse_lng AS etab_lng
    INTO v_mission
    FROM public.missions m
    JOIN public.etablissements e ON e.id = m.etablissement_id
   WHERE m.id = p_mission_id;
  IF NOT FOUND THEN RETURN; END IF;
  IF NOT (public.est_admin() OR v_mission.etablissement_id = public.mon_etablissement_id()) THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT s.id, s.id, s.prenom::text, s.nom::text,
    COALESCE(s.score_fiabilite, 0)::integer,
    CASE WHEN s.adresse_lat IS NOT NULL AND v_mission.etab_lat IS NOT NULL
      THEN round((public.fn_haversine_distance_m(
        s.adresse_lat, s.adresse_lng, v_mission.etab_lat, v_mission.etab_lng
      ) / 1000.0)::numeric, 1)
      ELSE NULL
    END,
    COALESCE(s.urgence_rayon_km, 15)::integer,
    s.telephone::text
  FROM public.soignants s
  WHERE COALESCE(s.disponible_urgence, false)
    AND public.fn_soignant_eligible_mission(s.id, p_mission_id, true)
    AND NOT public.fn_est_exclu(s.id, v_mission.etablissement_id)
    AND NOT EXISTS (
      SELECT 1 FROM public.missions ma
      WHERE ma.soignant_assigne_id = s.id AND ma.statut = 'EN_COURS'
        AND now() BETWEEN ma.debut_le AND ma.fin_le
    )
    AND (
      s.adresse_lat IS NULL OR v_mission.etab_lat IS NULL
      OR public.fn_haversine_distance_m(
        s.adresse_lat, s.adresse_lng, v_mission.etab_lat, v_mission.etab_lng
      ) <= COALESCE(s.urgence_rayon_km, 15) * 1000
    )
  ORDER BY s.score_fiabilite DESC NULLS LAST, distance_km NULLS LAST;
END;
$function$;

-- 6/20 fn_generer_donnees_dpae(uuid)
CREATE OR REPLACE FUNCTION public.fn_generer_donnees_dpae(p_contrat_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_payload jsonb;
  v_etab_id uuid;
  v_manquants text[] := ARRAY[]::text[];
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non authentifié');
  END IF;

  SELECT cm.etablissement_id INTO v_etab_id
  FROM public.contrats_mission cm
  WHERE cm.id = p_contrat_id;

  IF v_etab_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Contrat introuvable');
  END IF;

  IF NOT (est_admin() OR v_etab_id = mon_etablissement_id()) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non autorisé');
  END IF;

  SELECT jsonb_build_object(
    'success', true,
    'contrat_id', cm.id,
    'type_contrat', cm.type_contrat,
    'etablissement', jsonb_build_object(
      'nom', e.nom,
      'siret', e.siret,
      'naf', e.siret_code_naf,
      'adresse_rue', e.adresse_rue,
      'adresse_ville', e.adresse_ville,
      'adresse_code_postal', e.adresse_code_postal,
      'telephone', e.telephone_contact,
      'email', e.email_contact,
      'organisme_protection_sociale', 'URSSAF'
    ),
    'salarie', jsonb_build_object(
      'nom', s.nom,
      'prenom', s.prenom,
      'sexe', s.sexe,
      'date_naissance', s.date_naissance,
      'lieu_naissance_commune', s.lieu_naissance_commune,
      'lieu_naissance_departement', s.lieu_naissance_departement,
      'pays_naissance', COALESCE(s.pays_naissance, 'France'),
      'nationalite', COALESCE(s.nationalite, 'Française'),
      'numero_securite_sociale', COALESCE(s.numero_securite_sociale, s.numero_secu),
      'adresse_rue', s.adresse_rue,
      'adresse_code_postal', s.adresse_code_postal,
      'adresse_ville', s.adresse_ville,
      'profession', s.profession,
      'champs_a_completer_sur_net_entreprises', (
        SELECT COALESCE(jsonb_agg(m), '[]'::jsonb) FROM (
          SELECT 'sexe' AS m WHERE s.sexe IS NULL
          UNION ALL SELECT 'lieu_naissance_commune' WHERE s.lieu_naissance_commune IS NULL AND COALESCE(s.pays_naissance, 'France') = 'France'
          UNION ALL SELECT 'lieu_naissance_departement' WHERE s.lieu_naissance_departement IS NULL AND COALESCE(s.pays_naissance, 'France') = 'France'
          UNION ALL SELECT 'pays_naissance' WHERE s.pays_naissance IS NULL
          UNION ALL SELECT 'nationalite' WHERE s.nationalite IS NULL
          UNION ALL SELECT 'numero_securite_sociale' WHERE COALESCE(s.numero_securite_sociale, s.numero_secu) IS NULL
        ) t
      )
    ),
    'embauche', jsonb_build_object(
      'date_prevue', m.debut_le,
      'heure_prevue', to_char(m.debut_le, 'HH24:MI'),
      'date_fin', m.fin_le,
      'type_contrat', cm.type_contrat,
      'duree_heures_prevues', m.duree_heures
    ),
    'urssaf_url', 'https://www.net-entreprises.fr/declaration-prealable-embauche/',
    'note', 'Copiez ces données dans le formulaire DPAE Net-Entreprises. Les champs marqués dans champs_a_completer_sur_net_entreprises ne sont pas encore renseignés par le soignant — demandez-lui de compléter son profil ou saisissez-les manuellement.'
  )
  INTO v_payload
  FROM public.contrats_mission cm
  JOIN public.missions m ON m.id = cm.mission_id
  JOIN public.etablissements e ON e.id = cm.etablissement_id
  JOIN public.soignants s ON s.id = cm.soignant_id
  WHERE cm.id = p_contrat_id;

  RETURN v_payload;
END;
$function$;

-- 7/20 fn_enregistrer_numero_dpae(uuid,text)
CREATE OR REPLACE FUNCTION public.fn_enregistrer_numero_dpae(p_contrat_id uuid, p_dpae_numero text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_etab_id uuid;
  v_numero_trim text;
  v_soignant_id uuid;
  v_mission_id uuid;
  v_soignant_prenom text;
  v_etab_nom text;
  v_mission_intitule text;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non authentifié');
  END IF;

  IF p_dpae_numero IS NULL OR length(trim(p_dpae_numero)) = 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Numéro DPAE requis');
  END IF;

  v_numero_trim := trim(p_dpae_numero);

  IF v_numero_trim !~ '^[A-Za-z0-9]{8,30}$' THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Format invalide : 8 à 30 caractères alphanumériques (lettres et chiffres) requis. Aucun espace ni ponctuation.'
    );
  END IF;

  IF v_numero_trim !~ '[0-9]' THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Format invalide : le numéro DPAE doit contenir au moins un chiffre.'
    );
  END IF;

  SELECT cm.etablissement_id, cm.soignant_id, cm.mission_id
    INTO v_etab_id, v_soignant_id, v_mission_id
  FROM public.contrats_mission cm
  WHERE cm.id = p_contrat_id;

  IF v_etab_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Contrat introuvable');
  END IF;

  IF NOT (est_admin() OR v_etab_id = mon_etablissement_id()) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non autorisé');
  END IF;

  UPDATE public.contrats_mission
  SET dpae_numero = v_numero_trim,
      dpae_effectuee = true,
      dpae_effectuee_le = COALESCE(dpae_effectuee_le, NOW()),
      modifie_le = NOW()
  WHERE id = p_contrat_id;

  INSERT INTO public.journaux_audit (
    acteur_id, type_acteur, action, type_ressource, id_ressource, details
  ) VALUES (
    v_uid, 'ADMIN_ETABLISSEMENT', 'SYSTEM', 'contrat_mission', p_contrat_id,
    jsonb_build_object(
      'evenement', 'DPAE_NUMERO_ENREGISTRE',
      'dpae_numero', v_numero_trim,
      'enregistre_le', NOW()::text
    )
  );

  IF v_soignant_id IS NOT NULL AND v_mission_id IS NOT NULL THEN
    SELECT prenom INTO v_soignant_prenom FROM public.soignants WHERE id = v_soignant_id;
    SELECT nom INTO v_etab_nom FROM public.etablissements WHERE id = v_etab_id;
    SELECT intitule INTO v_mission_intitule FROM public.missions WHERE id = v_mission_id;

    BEGIN
      PERFORM net.http_post(
        url := 'https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/send-email',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1)
        ),
        body := jsonb_build_object(
          'type', 'DPAE_DECLAREE_SOIGNANT',
          'destinataire_id', v_soignant_id,
          'data', jsonb_build_object(
            'prenom', COALESCE(v_soignant_prenom, ''),
            'etablissement_nom', COALESCE(v_etab_nom, 'L''établissement'),
            'mission_intitule', COALESCE(v_mission_intitule, 'votre mission'),
            'dpae_numero', v_numero_trim,
            'contrat_id', p_contrat_id::text
          )
        )
      );
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END IF;

  RETURN jsonb_build_object('success', true, 'dpae_numero', v_numero_trim);
END;
$function$;

-- 8/20 fn_rebooker_soignant(uuid,uuid,timestamp with time zone,timestamp with time zone)
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

-- 9/20 fn_booster_mission(uuid)
CREATE OR REPLACE FUNCTION public.fn_booster_mission(p_mission_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_m record;
  v_prix numeric;
  v_nb integer := 0;
BEGIN
  SELECT m.*, e.adresse_lat AS etab_lat, e.adresse_lng AS etab_lng,
         e.adresse_ville AS etab_ville
    INTO v_m
    FROM public.missions m
    JOIN public.etablissements e ON e.id = m.etablissement_id
   WHERE m.id = p_mission_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Mission introuvable'); END IF;
  IF v_m.etablissement_id <> public.mon_etablissement_id() AND NOT public.est_admin() THEN
    RETURN jsonb_build_object('error', 'Non autorisé');
  END IF;
  IF v_m.statut <> 'OUVERTE' THEN
    RETURN jsonb_build_object('error', 'Seule une mission ouverte peut être boostée.');
  END IF;
  IF v_m.boostee_le IS NOT NULL THEN
    RETURN jsonb_build_object('error', 'Cette mission est déjà boostée.');
  END IF;

  v_prix := public.fn_param_num('mission_boost_prix_ht', 0);
  UPDATE public.missions
     SET boostee_le = now(), montant_boost_ht = COALESCE(v_prix, 0), modifie_le = now()
   WHERE id = p_mission_id;

  WITH cibles AS (
    SELECT s.id
      FROM public.soignants s
     WHERE public.fn_soignant_eligible_mission(s.id, p_mission_id, true)
       AND COALESCE(s.statut_compte::text, 'ACTIF') = 'ACTIF'
       AND NOT public.fn_est_exclu(s.id, v_m.etablissement_id)
       AND NOT EXISTS (
         SELECT 1 FROM public.candidatures c
          WHERE c.mission_id = v_m.id AND c.soignant_id = s.id
       )
       AND (
         s.adresse_lat IS NULL OR v_m.etab_lat IS NULL
         OR public.fn_haversine_distance_m(
           s.adresse_lat, s.adresse_lng, v_m.etab_lat, v_m.etab_lng
         ) <= COALESCE(s.rayon_deplacement_km, 50) * 1000
       )
     LIMIT 50
  )
  INSERT INTO public.notifications(destinataire_id, type, titre, corps, lien, type_destinataire)
  SELECT id, 'MISSION_A_POURVOIR', '🚀 Mission mise en avant près de chez vous',
    public.fn_html_escape(v_m.intitule) || ' — ' || COALESCE(v_m.etab_ville, '') || ', le ' ||
    to_char(v_m.debut_le AT TIME ZONE 'Europe/Paris', 'DD/MM') || ' à ' ||
    COALESCE(v_m.taux_horaire_base::text, '?') || ' €/h. L’établissement recherche activement.',
    '/soignant/missions/' || v_m.id, 'SOIGNANT'
  FROM cibles;
  GET DIAGNOSTICS v_nb = ROW_COUNT;

  RETURN jsonb_build_object(
    'success', true, 'soignants_notifies', v_nb, 'prix_ht', COALESCE(v_prix, 0)
  );
END;
$function$;

-- 10/20 fn_presences_detail_mission(uuid)
CREATE OR REPLACE FUNCTION public.fn_presences_detail_mission(p_mission_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_mission RECORD;
    v_presence RECORD;
    v_pauses JSONB;
BEGIN
    SELECT * INTO v_mission FROM missions WHERE id = p_mission_id;
    IF v_mission IS NULL THEN RETURN jsonb_build_object('error', 'Mission introuvable'); END IF;

    IF v_mission.etablissement_id != mon_etablissement_id() AND NOT est_admin() 
       AND v_mission.soignant_assigne_id != auth.uid() THEN
        RETURN jsonb_build_object('error', 'Accès refusé');
    END IF;

    SELECT * INTO v_presence FROM presences WHERE mission_id = p_mission_id LIMIT 1;

    IF v_presence IS NULL THEN
        RETURN jsonb_build_object('pointage_effectue', false, 'heures_planifiees', v_mission.duree_heures);
    END IF;

    -- Récupérer les pauses détaillées
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', pp.id, 'debut', pp.debut_le, 'fin', pp.fin_le, 
        'duree_min', pp.duree_min, 'motif', pp.motif, 'en_cours', pp.fin_le IS NULL
    ) ORDER BY pp.debut_le), '[]'::JSONB) INTO v_pauses
    FROM pauses_presence pp WHERE pp.presence_id = v_presence.id;

    RETURN jsonb_build_object(
        'pointage_effectue', true,
        'heures_planifiees', v_mission.duree_heures,
        'heures_reelles', v_presence.heures_reelles,
        'pointage_arrivee', v_presence.pointage_arrivee_le,
        'pointage_depart', v_presence.pointage_depart_le,
        'methode_arrivee', v_presence.methode_pointage_arrivee,
        'methode_depart', v_presence.methode_pointage_depart,
        'retard_min', v_presence.retard_min,
        'depart_anticipe_min', v_presence.depart_anticipe_min,
        'duree_brute_min', v_presence.duree_brute_min,
        'duree_pause_min', v_presence.duree_pause_min,
        'duree_nette_min', v_presence.duree_nette_min,
        'nb_pauses', jsonb_array_length(v_pauses),
        'pauses', v_pauses,
        'distance_m', v_presence.distance_etablissement_m,
        'perimetre_valide', v_presence.perimetre_gps_valide,
        'alerte_teleportation', v_presence.alerte_teleportation,
        'alertes', v_presence.alertes_fraude,
        'valide', v_presence.valide_par_etablissement
    );
END;
$function$;

-- 11/20 fn_activer_garantie_mission(uuid,boolean)
CREATE OR REPLACE FUNCTION public.fn_activer_garantie_mission(p_mission_id uuid, p_actif boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_m RECORD;
BEGIN
  SELECT * INTO v_m FROM missions WHERE id = p_mission_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Mission introuvable'); END IF;
  IF v_m.etablissement_id != mon_etablissement_id() AND NOT est_admin() THEN
    RETURN jsonb_build_object('error', 'Non autorisé');
  END IF;
  IF v_m.statut NOT IN ('OUVERTE', 'ASSIGNEE') THEN
    RETURN jsonb_build_object('error', 'La garantie ne peut être modifiée que sur une mission ouverte ou assignée.');
  END IF;
  UPDATE missions SET garantie_remplacement = p_actif, modifie_le = NOW() WHERE id = p_mission_id;
  RETURN jsonb_build_object('success', TRUE, 'garantie', p_actif);
END;
$function$;

-- 12/20 fn_deposer_chorus(uuid,text)
CREATE OR REPLACE FUNCTION public.fn_deposer_chorus(p_facture_id uuid, p_chorus_id text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_facture RECORD;
BEGIN
    SELECT * INTO v_facture FROM factures WHERE id = p_facture_id;
    IF v_facture IS NULL THEN RETURN '{"error":"Facture introuvable"}'::JSONB; END IF;
    IF v_facture.etablissement_id != mon_etablissement_id() AND NOT est_admin() THEN
        RETURN '{"error":"Accès refusé"}'::JSONB;
    END IF;

    IF v_facture.rapprochement_paiement_requis OR v_facture.montant_a_payer<=0
      OR v_facture.statut NOT IN ('EMISE','EN_RETARD') THEN
      RETURN jsonb_build_object('error','Facture soldée ou paiement à rapprocher.'); END IF;
    UPDATE factures SET
        chorus_pro_statut = 'DEPOSEE',
        chorus_pro_deposee_le = NOW(),
        chorus_pro_id = p_chorus_id
    WHERE id = p_facture_id;

    RETURN '{"success":true}'::JSONB;
END;
$function$;

-- 13/20 fn_generer_facture(uuid)
CREATE OR REPLACE FUNCTION public.fn_generer_facture(p_mission_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_mission RECORD;
    v_facture_id UUID;
    v_numero TEXT;
    v_annee TEXT := to_char(NOW(), 'YYYY');
    v_seq INTEGER;
BEGIN
    SELECT * INTO v_mission FROM missions WHERE id = p_mission_id;
    IF v_mission IS NULL THEN RETURN '{"error":"Mission introuvable"}'::JSONB; END IF;
    IF NOT est_admin() AND v_mission.etablissement_id != mon_etablissement_id() THEN
        RETURN '{"error":"Accès refusé"}'::JSONB;
    END IF;
    IF v_mission.statut != 'TERMINEE' THEN
        RETURN '{"error":"La mission doit être TERMINEE"}'::JSONB;
    END IF;
    IF EXISTS (SELECT 1 FROM factures WHERE mission_id = p_mission_id) THEN
        RETURN '{"error":"Facture déjà existante"}'::JSONB;
    END IF;

    SELECT COALESCE(MAX(CAST(SUBSTRING(numero_facture FROM '\d+$') AS INTEGER)), 0) + 1
    INTO v_seq FROM factures WHERE numero_facture LIKE 'JOL-' || v_annee || '-%';
    v_numero := 'JOL-' || v_annee || '-' || LPAD(v_seq::TEXT, 5, '0');

    INSERT INTO factures (
        numero_facture, etablissement_id, mission_id,
        montant_ht, taux_tva, montant_tva, montant_ttc,
        nombre_missions, statut, date_emission, date_echeance
    ) VALUES (
        v_numero, v_mission.etablissement_id, p_mission_id,
        COALESCE(v_mission.montant_commission_ht, 0),
        20,
        COALESCE(v_mission.montant_commission_tva, 0),
        COALESCE(v_mission.montant_commission_ttc, 0),
        1, 'EMISE', NOW(), (NOW() + INTERVAL '30 days')::DATE
    ) RETURNING id INTO v_facture_id;

    UPDATE missions SET commission_facturee = TRUE, modifie_le = NOW() WHERE id = p_mission_id;

    INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
    VALUES (v_mission.etablissement_id, 'FACTURE_EMISE', 'Facture ' || v_numero,
        'Montant TTC : ' || COALESCE(v_mission.montant_commission_ttc, 0) || '€',
        '/etablissement/facturation', 'ETABLISSEMENT');

    RETURN jsonb_build_object('success', true, 'facture_id', v_facture_id, 'numero', v_numero);
END;
$function$;

-- 14/20 fn_diffuser_pool_urgence(uuid)
CREATE OR REPLACE FUNCTION public.fn_diffuser_pool_urgence(p_mission_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
DECLARE
  v_etablissement_id uuid;
BEGIN
  SELECT m.etablissement_id
  INTO v_etablissement_id
  FROM public.missions m
  WHERE m.id = p_mission_id;

  IF NOT FOUND THEN
    RETURN 0;
  END IF;
  IF NOT (
    public.est_admin()
    OR v_etablissement_id = public.mon_etablissement_id()
  ) THEN
    RETURN 0;
  END IF;

  RETURN private.fn_diffuser_pool_urgence_interne(p_mission_id);
END;
$function$;

-- 15/20 fn_etablissement_pour_mission(uuid)
CREATE OR REPLACE FUNCTION public.fn_etablissement_pour_mission(p_etablissement_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_result JSONB;
BEGIN
    IF NOT EXISTS(
        SELECT 1 FROM missions 
        WHERE etablissement_id = p_etablissement_id 
        AND (statut = 'OUVERTE' OR soignant_assigne_id = auth.uid())
    ) AND mon_etablissement_id() != p_etablissement_id AND NOT est_admin() THEN
        RETURN jsonb_build_object('error', 'Accès refusé');
    END IF;

    SELECT jsonb_build_object(
        'id', id, 'nom', nom, 'type', type::TEXT,
        'adresse_ville', adresse_ville, 'adresse_code_postal', adresse_code_postal,
        'adresse_departement', adresse_departement, 'adresse_rue', adresse_rue,
        'adresse_lat', adresse_lat, 'adresse_lng', adresse_lng,
        'note_moyenne', note_moyenne, 'convention_collective', convention_collective,
        'est_secteur_public', est_secteur_public, 'finess', finess
    ) INTO v_result
    FROM etablissements WHERE id = p_etablissement_id AND supprime_le IS NULL;

    RETURN COALESCE(v_result, jsonb_build_object('error', 'Établissement introuvable'));
END;
$function$;

-- 16/20 fn_annuler_serie(uuid)
CREATE OR REPLACE FUNCTION public.fn_annuler_serie(p_serie_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_count INTEGER;
BEGIN
    IF NOT est_admin_etablissement() AND NOT est_admin() THEN
        RETURN '{"error":"Accès refusé"}'::JSONB;
    END IF;

    UPDATE missions SET
        statut = 'ANNULEE_PAR_ETABLISSEMENT',
        modifie_le = NOW()
    WHERE serie_id = p_serie_id
      AND statut IN ('OUVERTE', 'ASSIGNEE')
      AND (etablissement_id = mon_etablissement_id() OR est_admin());

    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN jsonb_build_object('success', true, 'missions_annulees', v_count);
END;
$function$;

-- 17/20 fn_assigner_mission_admin(uuid,uuid,text)
CREATE OR REPLACE FUNCTION public.fn_assigner_mission_admin(p_mission_id uuid, p_soignant_id uuid, p_choix_contrat text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_etablissement_id uuid;
BEGIN
  IF NOT (public.est_admin() OR public.est_admin_etablissement()) THEN
    RETURN jsonb_build_object('error', 'Non autorisé');
  END IF;
  SELECT etablissement_id INTO v_etablissement_id
    FROM public.missions WHERE id = p_mission_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Mission introuvable'); END IF;
  IF NOT public.est_admin()
     AND v_etablissement_id IS DISTINCT FROM public.mon_etablissement_id() THEN
    RETURN jsonb_build_object('error', 'Cette mission n''appartient pas à votre établissement');
  END IF;

  RETURN public.fn_finaliser_attribution_mission(p_mission_id, p_soignant_id, p_choix_contrat);
END;
$function$;

-- 18/20 fn_creer_reclamation_score(uuid,text,text,text,text)
CREATE OR REPLACE FUNCTION public.fn_creer_reclamation_score(p_evenement_id uuid, p_evenement_type text, p_motif_categorie text, p_texte_libre text, p_justificatif_storage_path text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_event RECORD;
  v_proprio_id uuid;
  v_reclamation_id uuid;
  v_existante RECORD;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTHENTIFIE');
  END IF;

  IF p_evenement_type NOT IN ('SOIGNANT', 'ETAB') THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'TYPE_INVALIDE',
                                'error', 'evenement_type doit être SOIGNANT ou ETAB');
  END IF;

  IF p_motif_categorie NOT IN ('URGENCE_MEDICALE','DEUIL','FORCE_MAJEURE',
                                'ERREUR_JOLENE','CONTEXTE_PARTICULIER','AUTRE') THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'MOTIF_INVALIDE',
                                'error', 'Motif catégorie invalide');
  END IF;

  IF p_texte_libre IS NULL OR length(trim(p_texte_libre)) < 20 THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'TEXTE_REQUIS',
                                'error', 'Texte libre obligatoire (min 20 caractères)');
  END IF;

  -- Charger l'événement + check propriété + contestable
  IF p_evenement_type = 'SOIGNANT' THEN
    SELECT id, soignant_id, contestable, decision_admin, reclamation_id
    INTO v_event FROM public.evenements_score_soignant WHERE id = p_evenement_id;
    v_proprio_id := v_event.soignant_id;
  ELSE
    SELECT id, etablissement_id AS proprio_id, contestable, decision_admin, reclamation_id
    INTO v_event FROM public.evenements_score_etab WHERE id = p_evenement_id;
    v_proprio_id := v_event.proprio_id;
  END IF;

  IF v_event.id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'EVENT_INTROUVABLE',
                                'error', 'Événement de score introuvable');
  END IF;

  -- Auth : seul le propriétaire peut réclamer
  IF p_evenement_type = 'SOIGNANT' AND v_proprio_id != v_uid THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTORISE',
                                'error', 'Vous n''êtes pas concerné par cet événement');
  END IF;
  IF p_evenement_type = 'ETAB' AND v_proprio_id != mon_etablissement_id() THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTORISE',
                                'error', 'Vous n''êtes pas concerné par cet événement');
  END IF;

  IF NOT v_event.contestable THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_CONTESTABLE',
                                'error', 'Cet événement n''est pas contestable');
  END IF;

  IF v_event.decision_admin IS NOT NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'DEJA_TRAITE',
                                'error', 'Cet événement a déjà été traité par un admin');
  END IF;

  IF v_event.reclamation_id IS NOT NULL THEN
    SELECT id, statut INTO v_existante FROM public.reclamations_score WHERE id = v_event.reclamation_id;
    IF v_existante.statut = 'PENDING' THEN
      RETURN jsonb_build_object('success', false, 'error_code', 'RECLAMATION_EN_COURS',
                                  'error', 'Une réclamation est déjà ouverte pour cet événement',
                                  'reclamation_id', v_existante.id);
    END IF;
  END IF;

  -- Créer la réclamation
  INSERT INTO public.reclamations_score (
    evenement_type, evenement_soignant_id, evenement_etab_id,
    contesteur_id, motif_categorie, texte_libre, justificatif_storage_path
  ) VALUES (
    p_evenement_type,
    CASE WHEN p_evenement_type = 'SOIGNANT' THEN p_evenement_id ELSE NULL END,
    CASE WHEN p_evenement_type = 'ETAB' THEN p_evenement_id ELSE NULL END,
    v_uid, p_motif_categorie, trim(p_texte_libre), p_justificatif_storage_path
  ) RETURNING id INTO v_reclamation_id;

  -- Lier l'event à la réclamation
  IF p_evenement_type = 'SOIGNANT' THEN
    UPDATE public.evenements_score_soignant SET reclamation_id = v_reclamation_id WHERE id = p_evenement_id;
  ELSE
    UPDATE public.evenements_score_etab SET reclamation_id = v_reclamation_id WHERE id = p_evenement_id;
  END IF;

  -- Notification admin via externalisation
  INSERT INTO public.externalisation_actions (type_action, payload, source, source_id)
  VALUES ('EMAIL_NOTIF', jsonb_build_object(
    'destinataire_role', 'ADMIN',
    'type', 'RECLAMATION_SCORE_NOUVELLE',
    'data', jsonb_build_object(
      'reclamation_id', v_reclamation_id,
      'evenement_type', p_evenement_type,
      'motif_categorie', p_motif_categorie,
      'contesteur_id', v_uid
    )
  ), 'AUTRE', v_reclamation_id);

  -- Audit
  INSERT INTO public.journaux_audit (
    acteur_id, type_acteur, action, type_ressource, id_ressource, details
  ) VALUES (
    v_uid, 'SOIGNANT', 'SYSTEM', 'reclamation_score', v_reclamation_id,
    jsonb_build_object('evenement', 'RECLAMATION_SCORE_CREEE',
                        'event_score_id', p_evenement_id,
                        'event_type', p_evenement_type,
                        'motif_categorie', p_motif_categorie,
                        'justificatif', p_justificatif_storage_path IS NOT NULL)
  );

  RETURN jsonb_build_object('success', true, 'reclamation_id', v_reclamation_id, 'statut', 'PENDING');
END;
$function$;

-- 19/20 fn_declarer_honoraires_retrocession(uuid,numeric,text)
CREATE OR REPLACE FUNCTION public.fn_declarer_honoraires_retrocession(p_mission_id uuid, p_montant_honoraires numeric, p_justificatif_cle text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_m RECORD;
  v_retrocede numeric;
  v_taux_com numeric;
  v_com_ht numeric;
BEGIN
  SELECT * INTO v_m FROM missions WHERE id = p_mission_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Mission introuvable'); END IF;
  IF v_m.etablissement_id != mon_etablissement_id() AND NOT est_admin() THEN
    RETURN jsonb_build_object('error', 'Non autorisé');
  END IF;
  IF v_m.mode_remuneration != 'RETROCESSION' THEN
    RETURN jsonb_build_object('error', 'Cette mission n''est pas en rétrocession.');
  END IF;
  IF v_m.statut != 'TERMINEE' THEN
    RETURN jsonb_build_object('error', 'Déclaration possible une fois la mission terminée.');
  END IF;
  IF v_m.montant_honoraires_bruts IS NOT NULL THEN
    RETURN jsonb_build_object('error', 'Honoraires déjà déclarés. Contactez le support pour rectifier.');
  END IF;
  IF p_montant_honoraires IS NULL OR p_montant_honoraires <= 0 OR p_montant_honoraires > 100000 THEN
    RETURN jsonb_build_object('error', 'Montant d''honoraires invalide.');
  END IF;
  IF p_justificatif_cle IS NULL OR length(trim(p_justificatif_cle)) < 5 THEN
    RETURN jsonb_build_object('error', 'Justificatif obligatoire : téléversez le relevé d''actes ou bordereau de la période.');
  END IF;

  v_retrocede := ROUND(p_montant_honoraires * COALESCE(v_m.retrocession_pct, 50) / 100.0, 2);
  v_taux_com := COALESCE(v_m.taux_commission_fige, v_m.taux_commission, 15);
  v_com_ht := ROUND(v_retrocede * v_taux_com / 100.0, 2);

  UPDATE missions SET
    montant_honoraires_bruts = p_montant_honoraires,
    justificatif_honoraires_cle = trim(p_justificatif_cle),
    total_brut = v_retrocede,
    net_a_payer = v_retrocede,
    montant_commission_ht = v_com_ht,
    montant_commission_tva = ROUND(v_com_ht * 0.20, 2),
    montant_commission_ttc = ROUND(v_com_ht * 1.20, 2),
    modifie_le = NOW()
  WHERE id = p_mission_id;

  INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
  VALUES (v_m.soignant_assigne_id, 'SYSTEM', 'Relevé d''honoraires à confirmer 💶',
    'Le cabinet déclare ' || p_montant_honoraires || ' € d''honoraires (justificatif joint) pour "' || fn_html_escape(v_m.intitule) ||
    '" — votre rétrocession (' || COALESCE(v_m.retrocession_pct, 50) || '%) : ' || v_retrocede ||
    ' €. CONFIRMEZ le relevé sur la mission (ou contestez sous 48h via un litige). Sans action de votre part, le montant sera validé automatiquement sous 48h.',
    '/soignant/missions/' || v_m.id, 'SOIGNANT');

  RETURN jsonb_build_object('success', TRUE, 'montant_retrocede', v_retrocede,
    'commission_ttc', ROUND(v_com_ht * 1.20, 2), 'en_attente_confirmation', TRUE);
END;
$function$;

-- 20/20 fn_definir_retrocession_mission(uuid,numeric)
CREATE OR REPLACE FUNCTION public.fn_definir_retrocession_mission(p_mission_id uuid, p_pct numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_m RECORD;
BEGIN
  SELECT * INTO v_m FROM missions WHERE id = p_mission_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Mission introuvable'); END IF;
  IF v_m.etablissement_id != mon_etablissement_id() AND NOT est_admin() THEN
    RETURN jsonb_build_object('error', 'Non autorisé');
  END IF;
  IF v_m.statut != 'OUVERTE' THEN
    RETURN jsonb_build_object('error', 'Modifiable uniquement sur une mission ouverte.');
  END IF;
  IF p_pct IS NULL OR p_pct <= 0 OR p_pct > 100 THEN
    RETURN jsonb_build_object('error', 'Pourcentage de rétrocession invalide (1-100).');
  END IF;
  UPDATE missions SET mode_remuneration = 'RETROCESSION', retrocession_pct = p_pct,
    type_contrat_recherche = 'LIBERAL', modifie_le = NOW()
   WHERE id = p_mission_id;
  RETURN jsonb_build_object('success', TRUE, 'retrocession_pct', p_pct);
END;
$function$;
