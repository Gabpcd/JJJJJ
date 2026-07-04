-- fn_mon_etablissement_complet : joindre paliers_commission et groupes_sante
--
-- Avant : la RPC retournait uniquement palier_commission_id et groupe_sante_id (UUID).
-- Après : elle retourne également `paliers_commission: { nom, taux_base }` et
--         `groupes_sante: { nom }` via LEFT JOIN, ce que le frontend attend déjà.
--
-- Fixe le crash sur DashboardEtablissement.tsx:280,286 et FacturationEtablissement.tsx:372,383
-- qui accèdent à `etab.paliers_commission.nom` et `etab.groupes_sante.nom`.

CREATE OR REPLACE FUNCTION public.fn_mon_etablissement_complet()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_etab_id UUID := mon_etablissement_id();
    v_result JSONB;
BEGIN
    IF v_etab_id IS NULL THEN
        RETURN jsonb_build_object('error', 'Établissement introuvable');
    END IF;

    SELECT row_to_json(e)::JSONB INTO v_result FROM (
        SELECT
            et.id, et.nom, et.siret, et.finess, et.type::TEXT, et.groupe_sante_id,
            et.adresse_rue, et.adresse_ville, et.adresse_code_postal, et.adresse_departement,
            et.adresse_lat, et.adresse_lng, et.email_contact, et.telephone_contact,
            et.stripe_customer_id, et.stripe_account_id,
            et.taux_commission_negocie, et.mode_facturation, et.mode_paiement_commission,
            et.palier_commission_id, et.missions_mois_precedent, et.palier_recalcule_le,
            et.chorus_pro_actif, et.chorus_pro_identifiant, et.delai_paiement_jours,
            et.formule_abonnement, et.convention_collective, et.couleur_theme, et.logo_url,
            et.contrat_url, et.contrat_uploade_le, et.contrat_valide,
            et.taux_majoration_nuit_pourcent, et.taux_majoration_dimanche_pourcent,
            et.taux_majoration_ferie_pourcent,
            et.est_secteur_public, et.peut_publier_missions, et.statut_verification,
            et.note_moyenne, et.nb_evaluations, et.description, et.horaires_ouverture,
            et.rist_plafond_actif, et.rist_taux_base_horaire,
            et.cree_le, et.modifie_le,
            -- JOIN paliers_commission (le frontend attend etab.paliers_commission.nom)
            CASE WHEN pc.id IS NOT NULL THEN jsonb_build_object(
                'id', pc.id,
                'nom', pc.nom,
                'taux_base', pc.taux_base,
                'seuil_min_missions', pc.seuil_min_missions
            ) ELSE NULL END AS paliers_commission,
            -- JOIN groupes_sante (le frontend attend etab.groupes_sante.nom)
            CASE WHEN gs.id IS NOT NULL THEN jsonb_build_object(
                'id', gs.id,
                'nom', gs.nom
            ) ELSE NULL END AS groupes_sante
        FROM etablissements et
        LEFT JOIN paliers_commission pc ON pc.id = et.palier_commission_id
        LEFT JOIN groupes_sante gs ON gs.id = et.groupe_sante_id
        WHERE et.id = v_etab_id
    ) e;

    RETURN COALESCE(v_result, jsonb_build_object('error', 'Établissement introuvable'));
END;
$function$;
