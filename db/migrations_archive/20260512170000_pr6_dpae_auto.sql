-- PR 6 Sprint 1 — DPAE Option A (PDF pré-rempli + Net-Entreprises)
--
-- Aujourd'hui : DPAE purement déclarative (confirm-dpae = bouton "c'est
-- fait", sans génération de PDF, sans stockage du numéro DPAE retourné
-- par URSSAF).
--
-- Cette PR ajoute :
-- 1. Colonne contrats_mission.dpae_numero pour stocker le n° DPAE URSSAF
-- 2. RPC fn_generer_donnees_dpae(p_contrat_id) qui retourne le payload
--    DPAE complet (étab + soignant + mission) à copier sur
--    net-entreprises.fr (gain de temps + zéro erreur de saisie)
-- 3. RPC fn_enregistrer_numero_dpae(p_contrat_id, p_dpae_numero) que
--    l'étab appelle après avoir soumis sur net-entreprises.fr
--
-- Option B (API tiers déclarant URSSAF directe) hors scope Sprint 1
-- — démarche d'agrément longue (3-6 mois minimum).

-- 1. Ajouter colonne dpae_numero si pas déjà existante
ALTER TABLE public.contrats_mission
  ADD COLUMN IF NOT EXISTS dpae_numero text;

CREATE INDEX IF NOT EXISTS idx_contrats_mission_dpae_numero
  ON public.contrats_mission(dpae_numero)
  WHERE dpae_numero IS NOT NULL;

-- 2. RPC fn_generer_donnees_dpae : récupère le payload DPAE depuis le
-- contrat + mission + étab + soignant.
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
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non authentifié');
  END IF;

  -- Vérifier que l'utilisateur courant est l'étab du contrat
  SELECT cm.etablissement_id INTO v_etab_id
  FROM public.contrats_mission cm
  WHERE cm.id = p_contrat_id;

  IF v_etab_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Contrat introuvable');
  END IF;

  IF NOT (est_admin() OR v_etab_id = mon_etablissement_id()) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non autorisé');
  END IF;

  -- Construire le payload DPAE.
  -- Note : certains champs DPAE obligatoires (sexe, lieu de naissance,
  -- nationalité, service santé travail) ne sont pas dans notre schéma.
  -- Ils sont retournés en NULL — l'étab les complète sur Net-Entreprises.
  -- L'amélioration "schéma DPAE complet" est laissée pour Sprint 2.
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
      'date_naissance', s.date_naissance,
      'numero_securite_sociale', COALESCE(s.numero_securite_sociale, s.numero_secu),
      'adresse_rue', s.adresse_rue,
      'adresse_code_postal', s.adresse_code_postal,
      'adresse_ville', s.adresse_ville,
      'profession', s.profession,
      'champs_a_completer_sur_net_entreprises', ARRAY[
        'sexe', 'lieu_de_naissance_commune', 'lieu_de_naissance_pays',
        'nationalite'
      ]
    ),
    'embauche', jsonb_build_object(
      'date_prevue', m.debut_le,
      'heure_prevue', to_char(m.debut_le, 'HH24:MI'),
      'date_fin', m.fin_le,
      'type_contrat', cm.type_contrat,
      'duree_heures_prevues', m.duree_heures
    ),
    'urssaf_url', 'https://www.net-entreprises.fr/declaration-prealable-embauche/',
    'note', 'Copiez ces données dans le formulaire DPAE Net-Entreprises. Complétez les champs manquants (sexe, lieu de naissance, nationalité). Une fois validée par l''URSSAF, renseignez le numéro DPAE retourné via fn_enregistrer_numero_dpae.'
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

-- 3. RPC fn_enregistrer_numero_dpae : l'étab saisit le n° DPAE retourné
-- par URSSAF après soumission.
CREATE OR REPLACE FUNCTION public.fn_enregistrer_numero_dpae(
  p_contrat_id uuid,
  p_dpae_numero text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_etab_id uuid;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non authentifié');
  END IF;

  IF p_dpae_numero IS NULL OR length(trim(p_dpae_numero)) = 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Numéro DPAE requis');
  END IF;

  SELECT etablissement_id INTO v_etab_id
  FROM public.contrats_mission WHERE id = p_contrat_id;

  IF NOT (est_admin() OR v_etab_id = mon_etablissement_id()) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non autorisé');
  END IF;

  UPDATE public.contrats_mission
  SET dpae_numero = trim(p_dpae_numero),
      dpae_effectuee = true,
      dpae_effectuee_le = COALESCE(dpae_effectuee_le, NOW()),
      modifie_le = NOW()
  WHERE id = p_contrat_id;

  -- Audit (action SYSTEM autorisée)
  INSERT INTO public.journaux_audit (
    acteur_id, type_acteur, action, type_ressource, id_ressource, details
  ) VALUES (
    v_uid, 'ADMIN_ETABLISSEMENT', 'SYSTEM', 'contrat_mission', p_contrat_id,
    jsonb_build_object(
      'evenement', 'DPAE_NUMERO_ENREGISTRE',
      'dpae_numero', trim(p_dpae_numero),
      'enregistre_le', NOW()::text
    )
  );

  RETURN jsonb_build_object('success', true, 'dpae_numero', trim(p_dpae_numero));
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_enregistrer_numero_dpae(uuid, text) TO authenticated;

-- 4. Audit installation
INSERT INTO public.journaux_audit (
  acteur_id, type_acteur, action, type_ressource, id_ressource, details
) VALUES (
  '00000000-0000-0000-0000-000000000000', 'SYSTEME',
  'SYSTEM', 'fonction', NULL,
  jsonb_build_object(
    'evenement', 'DPAE_OPTION_A_INSTALLED',
    'pr', 'PR 6 Sprint 1',
    'composants', ARRAY[
      'colonne contrats_mission.dpae_numero',
      'RPC fn_generer_donnees_dpae',
      'RPC fn_enregistrer_numero_dpae'
    ],
    'option', 'A — PDF/payload pré-rempli + lien net-entreprises.fr',
    'option_b_reportee', 'API tiers déclarant URSSAF (agrément 3-6 mois)'
  )
);
