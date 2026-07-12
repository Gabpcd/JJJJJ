-- Lot 21 — la file de vérification conserve toutes les données de test visibles
-- (besoin screenshots stores), mais expose est_compte_test pour les identifier.
CREATE OR REPLACE FUNCTION public.fn_admin_lister_etablissements_a_verifier(p_limit integer DEFAULT 100)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_resultat jsonb;
BEGIN
  IF NOT est_admin() THEN
    RETURN jsonb_build_object('error', 'Accès refusé — admin uniquement');
  END IF;

  SELECT COALESCE(jsonb_agg(to_jsonb(e)), '[]'::jsonb) INTO v_resultat
  FROM (
    SELECT id, nom, est_compte_test,
           siret, siret_verifie, siret_raison_sociale, siret_categorie_juridique,
           siret_code_naf, siret_est_actif,
           finess, finess_verifie, finess_raison_sociale,
           finess_categorie, finess_secteur, finess_est_public,
           adresse_rue, adresse_code_postal, adresse_ville, adresse_departement,
           telephone_contact, telephone_verifie,
           representant_nom, representant_prenom, representant_identite_verifiee,
           representant_piece_s3_key, representant_piece_type_document,
           representant_identite_resultat_ia,
           dirigeants, email_contact, email_contact_verifie,
           rattachement_methode, rattachement_verifie, statut_verification,
           contrat_valide, peut_publier_missions, motif_rejet, cree_le
    FROM etablissements
    WHERE supprime_le IS NULL
      AND COALESCE(rattachement_verifie, false) = false
      AND COALESCE(statut_verification, '') <> 'REJETE'
    ORDER BY cree_le DESC NULLS LAST
    LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 100), 500))
  ) e;

  RETURN jsonb_build_object('success', true, 'etablissements', v_resultat);
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_admin_lister_etablissements_a_verifier(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_admin_lister_etablissements_a_verifier(integer) TO authenticated, service_role;
