-- Bloc C : validation clé NIR + verrouillage après validation
-- Bloc D (partiel) : bug TVA — exiger numéro si assujetti

-- 1. Refonte fn_maj_nir_soignant : ajout validation clé INSEE + verrouillage
CREATE OR REPLACE FUNCTION public.fn_maj_nir_soignant(p_nir text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_normalise text;
  v_nir_base bigint;
  v_cle_attendue int;
  v_cle_fournie int;
  v_ancien text;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTHENTIFIE');
  END IF;

  -- Vérifier si le NIR est déjà verrouillé (nir_verifie = true)
  SELECT numero_securite_sociale INTO v_ancien FROM soignants WHERE id = v_uid;
  IF v_ancien IS NOT NULL AND EXISTS (
    SELECT 1 FROM soignants WHERE id = v_uid AND (nir_verifie = true)
  ) THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NIR_VERROUILLE',
      'error', 'Votre NIR a déjà été vérifié et ne peut plus être modifié.');
  END IF;

  IF p_nir IS NULL OR length(trim(p_nir)) = 0 THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NIR_REQUIS');
  END IF;

  v_normalise := regexp_replace(upper(trim(p_nir)), '\s+', '', 'g');

  -- Corse : 2A → 19, 2B → 18 pour le calcul de clé
  -- Format : sexe(1) année(2) mois(2) dept(2-3) commune(3) ordre(3) [clé(2)]
  IF v_normalise !~ '^[12][0-9]{2}(0[1-9]|1[0-2])(0[1-9]|[12][0-9]|3[01]|2A|2B|9[0-9])[0-9]{6}([0-9]{2})?$' THEN
    RETURN jsonb_build_object(
      'success', false, 'error_code', 'NIR_FORMAT_INVALIDE',
      'error', 'Le NIR doit faire 13 chiffres (sans clé) ou 15 chiffres (avec clé). Vérifiez votre carte Vitale.'
    );
  END IF;

  -- Validation de la clé si 15 chiffres fournis
  IF length(v_normalise) = 15 THEN
    DECLARE
      v_base_str text := left(v_normalise, 13);
    BEGIN
      -- Gestion Corse : 2A → remplacer par 19, 2B → remplacer par 18
      v_base_str := replace(v_base_str, '2A', '19');
      v_base_str := replace(v_base_str, '2B', '18');
      v_nir_base := v_base_str::bigint;
      v_cle_fournie := right(v_normalise, 2)::int;
      v_cle_attendue := 97 - (v_nir_base % 97);
      IF v_cle_fournie != v_cle_attendue THEN
        RETURN jsonb_build_object(
          'success', false, 'error_code', 'NIR_CLE_INVALIDE',
          'error', 'La clé de contrôle du NIR est incorrecte. Vérifiez les 2 derniers chiffres sur votre carte Vitale.'
        );
      END IF;
    END;
  END IF;

  UPDATE public.soignants
  SET numero_securite_sociale = v_normalise,
      nir_verifie = CASE WHEN length(v_normalise) = 15 THEN true ELSE false END,
      modifie_le = now()
  WHERE id = v_uid;

  INSERT INTO public.journaux_audit (
    acteur_id, type_acteur, action, type_ressource, id_ressource, details
  ) VALUES (
    v_uid, 'SOIGNANT', 'DONNEES_PERSO_MODIFICATION', 'soignant', v_uid,
    jsonb_build_object(
      'champ', 'numero_securite_sociale',
      'nir_verifie', length(v_normalise) = 15,
      'horodatage', now()
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'nir_verifie', length(v_normalise) = 15,
    'message', CASE WHEN length(v_normalise) = 15
      THEN 'NIR vérifié et verrouillé (clé valide).'
      ELSE 'NIR enregistré. Ajoutez les 2 chiffres de clé (carte Vitale) pour verrouiller.'
    END
  );
END;
$function$;

-- Refonte fn_modifier_mon_nir : même logique (doublon historique, on l'aligne)
CREATE OR REPLACE FUNCTION public.fn_modifier_mon_nir(p_nir text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
BEGIN
  RETURN fn_maj_nir_soignant(p_nir);
END;
$function$;

-- Ajouter la colonne nir_verifie si elle n'existe pas
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='soignants' AND column_name='nir_verifie') THEN
    ALTER TABLE public.soignants ADD COLUMN nir_verifie boolean NOT NULL DEFAULT false;
  END IF;
END $$;

-- 2. Bug TVA : fn_modifier_tva_liberal doit exiger le numéro si assujetti=true
CREATE OR REPLACE FUNCTION public.fn_modifier_tva_liberal(p_assujetti_tva boolean, p_numero_tva text DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_ancien_assujetti BOOLEAN;
  v_ancien_numero TEXT;
  v_ip inet;
  v_user_agent text;
  v_headers jsonb;
BEGIN
  -- Validation : si assujetti, le numéro de TVA est obligatoire
  IF p_assujetti_tva AND (p_numero_tva IS NULL OR length(trim(p_numero_tva)) = 0) THEN
    RETURN jsonb_build_object('error', 'Numéro de TVA intracommunautaire requis si vous êtes assujetti.');
  END IF;

  -- Validation format TVA intracommunautaire français (FRxx + 9-11 chiffres)
  IF p_assujetti_tva AND p_numero_tva IS NOT NULL AND trim(p_numero_tva) !~ '^FR[0-9A-Z]{2}[0-9]{9}$' THEN
    RETURN jsonb_build_object('error', 'Format de TVA invalide. Attendu : FRxx suivi de 9 chiffres (ex. FR12345678901).');
  END IF;

  SELECT assujetti_tva, numero_tva INTO v_ancien_assujetti, v_ancien_numero
  FROM soignants WHERE id = auth.uid();

  UPDATE soignants
  SET assujetti_tva = p_assujetti_tva,
      numero_tva = CASE WHEN p_assujetti_tva THEN trim(p_numero_tva) ELSE NULL END,
      modifie_le = now()
  WHERE id = auth.uid();

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Soignant introuvable');
  END IF;

  BEGIN
    v_headers := current_setting('request.headers', true)::jsonb;
    v_ip := NULLIF(trim(split_part(coalesce(v_headers->>'x-forwarded-for', ''), ',', 1)), '')::inet;
    v_user_agent := NULLIF(v_headers->>'user-agent', '');
  EXCEPTION WHEN OTHERS THEN
    v_ip := NULL; v_user_agent := NULL;
  END;

  PERFORM fn_ecrire_audit(
    auth.uid(), 'SOIGNANT', 'TVA_MODIFICATION',
    'soignant', auth.uid(), NULL,
    jsonb_build_object(
      'ancien_assujetti', v_ancien_assujetti,
      'nouveau_assujetti', p_assujetti_tva,
      'ancien_numero', v_ancien_numero,
      'nouveau_numero', CASE WHEN p_assujetti_tva THEN trim(p_numero_tva) ELSE NULL END
    ),
    v_ip, v_user_agent
  );

  RETURN jsonb_build_object('success', true);
END;
$function$;

-- 3. Bug DPAE : fn_maj_infos_dpae acceptait des champs vides → « enregistré »
-- même sans rien remplir. Ajout validation des champs requis côté serveur.
CREATE OR REPLACE FUNCTION public.fn_maj_infos_dpae(
  p_sexe text,
  p_lieu_naissance_commune text,
  p_lieu_naissance_departement text,
  p_pays_naissance text,
  p_nationalite text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_manquants text[] := ARRAY[]::text[];
  v_pays text := COALESCE(NULLIF(trim(p_pays_naissance), ''), 'France');
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non authentifié');
  END IF;

  -- Validation champs obligatoires
  IF p_sexe IS NULL OR p_sexe NOT IN ('M', 'F') THEN
    v_manquants := array_append(v_manquants, 'Sexe (état civil)');
  END IF;
  IF p_nationalite IS NULL OR length(trim(p_nationalite)) = 0 THEN
    v_manquants := array_append(v_manquants, 'Nationalité');
  END IF;
  -- Commune + département obligatoires si naissance en France
  IF v_pays = 'France' THEN
    IF p_lieu_naissance_commune IS NULL OR length(trim(p_lieu_naissance_commune)) = 0 THEN
      v_manquants := array_append(v_manquants, 'Commune de naissance');
    END IF;
    IF p_lieu_naissance_departement IS NULL OR length(trim(p_lieu_naissance_departement)) = 0 THEN
      v_manquants := array_append(v_manquants, 'Département de naissance');
    END IF;
    IF p_lieu_naissance_departement IS NOT NULL
       AND p_lieu_naissance_departement !~ '^(0[1-9]|[1-8][0-9]|9[0-5]|2A|2B|97[1-6])$' THEN
      RETURN jsonb_build_object('success', false, 'error',
        'Département invalide (attendu : 01-95, 2A, 2B, 971-976).');
    END IF;
  END IF;

  IF array_length(v_manquants, 1) IS NOT NULL THEN
    RETURN jsonb_build_object('success', false, 'error',
      'Champs obligatoires manquants : ' || array_to_string(v_manquants, ', ') || '.');
  END IF;

  UPDATE public.soignants
  SET sexe = p_sexe,
      lieu_naissance_commune = NULLIF(trim(p_lieu_naissance_commune), ''),
      lieu_naissance_departement = NULLIF(trim(p_lieu_naissance_departement), ''),
      pays_naissance = v_pays,
      nationalite = COALESCE(NULLIF(trim(p_nationalite), ''), 'Française'),
      modifie_le = NOW()
  WHERE id = v_uid;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Profil soignant introuvable');
  END IF;

  RETURN jsonb_build_object('success', true);
END;
$function$;
