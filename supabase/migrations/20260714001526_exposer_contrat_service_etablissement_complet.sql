-- Source unique du verrou de publication côté établissement.
--
-- Depuis le durcissement préproduction, fn_blocage_publication_etab exige
-- etablissements.contrat_service_signe. La RPC de profil omettait pourtant ce
-- champ : le formulaire de mission recevait `undefined` et bloquait même un
-- établissement qui avait réellement signé. L'ancien `contrat_valide` reste
-- exposé pour l'historique des PDF contrôlés, mais ne vaut pas signature du
-- contrat de service et ne doit jamais ouvrir la publication.

CREATE OR REPLACE FUNCTION public.fn_mon_etablissement_complet()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_etab_id uuid := public.mon_etablissement_id();
  v_result jsonb;
BEGIN
  IF v_etab_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Etablissement introuvable');
  END IF;

  SELECT row_to_json(e)::jsonb
  INTO v_result
  FROM (
    SELECT
      et.id, et.nom, et.siret, et.finess, et.type::text, et.groupe_sante_id,
      et.adresse_rue, et.adresse_ville, et.adresse_code_postal, et.adresse_departement,
      et.adresse_lat, et.adresse_lng, et.email_contact, et.telephone_contact,
      et.stripe_customer_id, et.stripe_account_id,
      et.taux_commission_negocie, et.mode_facturation, et.mode_paiement_commission,
      et.palier_commission_id, et.missions_mois_precedent, et.palier_recalcule_le,
      et.chorus_pro_actif, et.chorus_pro_identifiant, et.delai_paiement_jours,
      et.formule_abonnement, et.convention_collective, et.couleur_theme, et.logo_url,
      et.contrat_url, et.contrat_uploade_le, et.contrat_valide,
      et.contrat_service_signe, et.contrat_service_signe_le,
      et.rib_s3_key, et.rib_ia_coherent, et.iban_last4, et.sms_actif,
      et.taux_majoration_nuit_pourcent, et.taux_majoration_dimanche_pourcent,
      et.taux_majoration_ferie_pourcent,
      et.est_secteur_public, et.peut_publier_missions, et.statut_verification,
      et.note_moyenne, et.nb_evaluations, et.description, et.horaires_ouverture,
      et.rist_plafond_actif, et.rist_taux_base_horaire,
      et.bloque_auto_le, et.bloque_auto_raisons,
      et.cree_le, et.modifie_le,
      CASE WHEN pc.id IS NOT NULL THEN jsonb_build_object(
        'id', pc.id,
        'nom', pc.nom,
        'taux_commission', pc.taux_commission,
        'missions_min', pc.missions_min
      ) ELSE NULL END AS paliers_commission,
      CASE WHEN gs.id IS NOT NULL THEN jsonb_build_object(
        'id', gs.id,
        'nom', gs.nom
      ) ELSE NULL END AS groupes_sante
    FROM public.etablissements et
    LEFT JOIN public.paliers_commission pc ON pc.id = et.palier_commission_id
    LEFT JOIN public.groupes_sante gs ON gs.id = et.groupe_sante_id
    WHERE et.id = v_etab_id
  ) e;

  RETURN COALESCE(v_result, jsonb_build_object('error', 'Etablissement introuvable'));
END;
$$;

REVOKE ALL ON FUNCTION public.fn_mon_etablissement_complet() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_mon_etablissement_complet() TO authenticated, service_role;

COMMENT ON FUNCTION public.fn_mon_etablissement_complet() IS
  'Retourne le profil de l établissement courant, dont contrat_service_signe, source canonique du verrou de publication.';
