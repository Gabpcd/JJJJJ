-- ============================================================
-- CP-C-3 D — email_queue.statut enum + fn_mon_etablissement_complet
-- ============================================================
-- A. Ajout colonne statut ENUM propre sur email_queue
--    (remplace usage détourné de envoye=TRUE pour marquer
--    annulé/erreur)
-- B. fn_mon_etablissement_complet expose bloque_auto_le et
--    bloque_auto_raisons pour le frontend
-- ============================================================

-- A. email_queue.statut enum
ALTER TABLE public.email_queue
  ADD COLUMN IF NOT EXISTS statut TEXT
    CHECK (statut IN ('EN_ATTENTE', 'ENVOYE', 'ANNULE', 'ERREUR'));

-- Migration des lignes existantes
UPDATE public.email_queue
SET statut = CASE
    WHEN envoye = TRUE AND erreur LIKE 'Backfill%' THEN 'ANNULE'
    WHEN envoye = TRUE AND erreur IS NOT NULL THEN 'ERREUR'
    WHEN envoye = TRUE THEN 'ENVOYE'
    ELSE 'EN_ATTENTE'
END
WHERE statut IS NULL;

ALTER TABLE public.email_queue
  ALTER COLUMN statut SET NOT NULL,
  ALTER COLUMN statut SET DEFAULT 'EN_ATTENTE';

CREATE INDEX IF NOT EXISTS idx_email_queue_statut
  ON public.email_queue(statut)
  WHERE statut = 'EN_ATTENTE';

COMMENT ON COLUMN public.email_queue.statut IS
  'CP-C-3 D : EN_ATTENTE / ENVOYE / ANNULE / ERREUR. Source de vérité (la colonne envoye est deprecated, conservée pour compat).';
COMMENT ON COLUMN public.email_queue.envoye IS
  'DEPRECATED CP-C-3 D : utiliser statut=ENVOYE. Conservée pour compat triggers/fonctions legacy.';

-- B. fn_mon_etablissement_complet : expose bloque_auto_le + bloque_auto_raisons
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
        RETURN jsonb_build_object('error', 'Etablissement introuvable');
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
        FROM etablissements et
        LEFT JOIN paliers_commission pc ON pc.id = et.palier_commission_id
        LEFT JOIN groupes_sante gs ON gs.id = et.groupe_sante_id
        WHERE et.id = v_etab_id
    ) e;

    RETURN COALESCE(v_result, jsonb_build_object('error', 'Etablissement introuvable'));
END;
$function$;
