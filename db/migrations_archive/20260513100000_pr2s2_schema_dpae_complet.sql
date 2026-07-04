-- PR 2 Sprint 2 — Schéma DPAE complet
--
-- Ajoute les colonnes manquantes côté soignants pour générer une DPAE
-- complète sans renvoyer l'étab faire des recherches manuelles sur
-- Net-Entreprises :
--   - sexe (M/F)
--   - lieu_naissance_commune
--   - lieu_naissance_departement (numéro 2A/2B/01..95/971..976)
--   - pays_naissance (default 'France')
--   - nationalite (default 'Française')
--
-- Met à jour fn_generer_donnees_dpae pour les inclure dans le payload
-- et réduit le tableau 'champs_a_completer_sur_net_entreprises' aux
-- seuls champs encore manquants (numéro NIR si non fourni).

-- 1. ALTER TABLE soignants : nouvelles colonnes DPAE
ALTER TABLE public.soignants
  ADD COLUMN IF NOT EXISTS sexe text,
  ADD COLUMN IF NOT EXISTS lieu_naissance_commune text,
  ADD COLUMN IF NOT EXISTS lieu_naissance_departement text,
  ADD COLUMN IF NOT EXISTS pays_naissance text DEFAULT 'France',
  ADD COLUMN IF NOT EXISTS nationalite text DEFAULT 'Française';

-- CHECK constraint sexe (idempotent — drop puis add)
ALTER TABLE public.soignants
  DROP CONSTRAINT IF EXISTS soignants_sexe_check;
ALTER TABLE public.soignants
  ADD CONSTRAINT soignants_sexe_check
  CHECK (sexe IS NULL OR sexe IN ('M', 'F'));

COMMENT ON COLUMN public.soignants.sexe IS
  'M ou F. Requis pour DPAE (URSSAF). Renseigné par le soignant dans son profil.';
COMMENT ON COLUMN public.soignants.lieu_naissance_commune IS
  'Commune de naissance (nom). Requis DPAE pour la France.';
COMMENT ON COLUMN public.soignants.lieu_naissance_departement IS
  'Numéro département de naissance (01..95, 2A, 2B, 971..976). Requis DPAE.';
COMMENT ON COLUMN public.soignants.pays_naissance IS
  'Pays de naissance. Default France. Si autre, le département est NULL.';
COMMENT ON COLUMN public.soignants.nationalite IS
  'Nationalité du soignant. Default Française.';

-- 2. Helper : indicateur si le profil DPAE est complet (utilisé en UI)
CREATE OR REPLACE FUNCTION public.fn_soignant_dpae_complet(p_soignant_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_s RECORD;
  v_manquants text[] := ARRAY[]::text[];
BEGIN
  SELECT sexe, lieu_naissance_commune, lieu_naissance_departement,
         pays_naissance, nationalite,
         COALESCE(numero_securite_sociale, numero_secu) AS nir,
         date_naissance, adresse_rue, adresse_ville
  INTO v_s
  FROM public.soignants WHERE id = p_soignant_id;

  IF v_s IS NULL THEN
    RETURN jsonb_build_object('complet', false, 'manquants', ARRAY['profil_introuvable']);
  END IF;

  IF v_s.sexe IS NULL THEN v_manquants := array_append(v_manquants, 'sexe'); END IF;
  IF v_s.date_naissance IS NULL THEN v_manquants := array_append(v_manquants, 'date_naissance'); END IF;
  IF v_s.pays_naissance IS NULL THEN v_manquants := array_append(v_manquants, 'pays_naissance'); END IF;
  IF v_s.nationalite IS NULL THEN v_manquants := array_append(v_manquants, 'nationalite'); END IF;
  -- Commune + dept obligatoires si naissance en France
  IF COALESCE(v_s.pays_naissance, 'France') = 'France' THEN
    IF v_s.lieu_naissance_commune IS NULL THEN v_manquants := array_append(v_manquants, 'lieu_naissance_commune'); END IF;
    IF v_s.lieu_naissance_departement IS NULL THEN v_manquants := array_append(v_manquants, 'lieu_naissance_departement'); END IF;
  END IF;
  IF v_s.nir IS NULL OR v_s.nir = '' THEN v_manquants := array_append(v_manquants, 'numero_securite_sociale'); END IF;
  IF v_s.adresse_rue IS NULL OR v_s.adresse_rue = '' THEN v_manquants := array_append(v_manquants, 'adresse'); END IF;

  RETURN jsonb_build_object(
    'complet', array_length(v_manquants, 1) IS NULL,
    'manquants', v_manquants
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_soignant_dpae_complet(uuid) TO authenticated;

-- 3. Remplacer fn_generer_donnees_dpae pour inclure les nouveaux champs
--    et réduire champs_a_completer.
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

GRANT EXECUTE ON FUNCTION public.fn_generer_donnees_dpae(uuid) TO authenticated;

-- 4. RPC pour le soignant lui-même : mettre à jour ses infos DPAE.
--    Les colonnes sont déjà couvertes par la policy UPDATE générique
--    soignants (id = auth.uid()), mais on isole une RPC pour
--    centraliser la validation + audit.
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
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non authentifié');
  END IF;

  IF p_sexe IS NOT NULL AND p_sexe NOT IN ('M', 'F') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Sexe doit être M ou F');
  END IF;

  -- Validation département : 01-95, 2A, 2B, 971-976
  IF p_lieu_naissance_departement IS NOT NULL
     AND p_lieu_naissance_departement !~ '^(0[1-9]|[1-8][0-9]|9[0-5]|2A|2B|97[1-6])$' THEN
    RETURN jsonb_build_object('success', false, 'error',
      'Département invalide (attendu : 01-95, 2A, 2B, 971-976).');
  END IF;

  UPDATE public.soignants
  SET sexe = p_sexe,
      lieu_naissance_commune = NULLIF(trim(p_lieu_naissance_commune), ''),
      lieu_naissance_departement = NULLIF(trim(p_lieu_naissance_departement), ''),
      pays_naissance = COALESCE(NULLIF(trim(p_pays_naissance), ''), 'France'),
      nationalite = COALESCE(NULLIF(trim(p_nationalite), ''), 'Française'),
      modifie_le = NOW()
  WHERE id = v_uid;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Profil soignant introuvable');
  END IF;

  RETURN jsonb_build_object('success', true);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_maj_infos_dpae(text, text, text, text, text) TO authenticated;

-- 5. Audit
INSERT INTO public.journaux_audit (
  acteur_id, type_acteur, action, type_ressource, id_ressource, details
) VALUES (
  '00000000-0000-0000-0000-000000000000', 'SYSTEME',
  'SYSTEM', 'table', NULL,
  jsonb_build_object(
    'evenement', 'PR2_SPRINT2_SCHEMA_DPAE_COMPLET_INSTALLED',
    'pr', 'PR 2 Sprint 2',
    'colonnes_ajoutees', ARRAY['sexe', 'lieu_naissance_commune',
      'lieu_naissance_departement', 'pays_naissance', 'nationalite'],
    'rpcs', ARRAY['fn_soignant_dpae_complet', 'fn_maj_infos_dpae',
      'fn_generer_donnees_dpae (mis à jour)']
  )
);
