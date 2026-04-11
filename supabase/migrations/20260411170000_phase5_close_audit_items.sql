-- ─── Phase 5 : fixes de clôture post-audit ───
--
-- Cette migration ferme les 4 items identifiés par l'audit exhaustif mais
-- marqués "non bloquants" dans la phase précédente. Tous fixés maintenant
-- pour avoir un état 100% propre pour le lancement.
--
-- 1. fn_accepter_mission : créer le contrat dans contrats_mission au lieu
--    de juste générer un numéro. Retourne contrat_id pour que le frontend
--    puisse rediriger vers /contrat/:id après acceptation d'une mission.
-- 2. attestations_heures_externes UPDATE policy : ajouter fenêtre de 24h
--    pour corriger une erreur de saisie, au-delà c'est immuable (sauf admin).
-- 3. fn_confirmer_paiement_soignant : RPC dédiée pour la confirmation par
--    le soignant, plus propre que le UPDATE direct depuis le frontend
--    (defense in depth — le trigger fn_protect_paiement_soignant reste en
--    place mais on évite désormais les UPDATE directs côté client).
--
-- NB : le point "fn_stats_rh_etablissement cout_previsionnel" est un fix
-- purement frontend (DashboardRH.tsx) — le backend retourne déjà les bons
-- champs `cout_previsionnel_total` et `cout_previsionnel_brut`.

-- ═══════════════════════════════════════════════════════════════════
-- 1. fn_accepter_mission — créer le contrat + retourner contrat_id
-- ═══════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.fn_accepter_mission(p_mission_id uuid, p_choix_contrat text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_mission RECORD;
    v_soignant RECORD;
    v_type_paiement TEXT;
    v_mode_paiement TEXT;
    v_type_contrat_gen TEXT;
    v_numero_contrat TEXT;
    v_contrat_id UUID;
BEGIN
    SELECT * INTO v_mission FROM missions WHERE id = p_mission_id;
    IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Mission introuvable'); END IF;
    IF v_mission.statut != 'OUVERTE' THEN RETURN jsonb_build_object('error', 'Cette mission n''est plus disponible'); END IF;
    IF v_mission.mode_attribution != 'PREMIER_ARRIVE' THEN RETURN jsonb_build_object('error', 'Cette mission nécessite une candidature'); END IF;

    SELECT * INTO v_soignant FROM soignants WHERE id = auth.uid();
    IF v_soignant IS NULL THEN RETURN jsonb_build_object('error', 'Profil soignant introuvable'); END IF;

    IF v_soignant.profession != v_mission.profession_requise THEN
        RETURN jsonb_build_object('error', 'Profession incompatible.');
    END IF;
    IF v_mission.type_contrat_recherche = 'SALARIE' AND COALESCE(v_soignant.type_exercice, 'SALARIE') NOT IN ('SALARIE', 'MIXTE') THEN
        RETURN jsonb_build_object('error', 'Mission réservée aux salariés.');
    END IF;
    IF v_mission.type_contrat_recherche = 'LIBERAL' AND COALESCE(v_soignant.type_exercice, 'SALARIE') NOT IN ('LIBERAL', 'MIXTE') THEN
        RETURN jsonb_build_object('error', 'Mission réservée aux libéraux.');
    END IF;

    -- MIXTE + TOUS → choix obligatoire
    IF v_soignant.type_exercice = 'MIXTE' AND v_mission.type_contrat_recherche = 'TOUS' THEN
        IF p_choix_contrat IS NULL OR p_choix_contrat NOT IN ('SALARIE', 'LIBERAL') THEN
            RETURN jsonb_build_object('error', 'Choisissez votre mode de contrat.', 'choix_requis', TRUE,
                'options', jsonb_build_array(
                    jsonb_build_object('value', 'SALARIE', 'label', 'Salarié (CDDU / bulletin de paie)'),
                    jsonb_build_object('value', 'LIBERAL', 'label', 'Libéral (note d''honoraires)')));
        END IF;
    END IF;

    IF fn_est_exclu(auth.uid(), v_mission.etablissement_id) THEN RETURN jsonb_build_object('error', 'Accès refusé.'); END IF;
    IF v_soignant.tous_documents_valides IS NOT TRUE THEN RETURN jsonb_build_object('error', 'Documents non validés.'); END IF;

    -- Déterminer type paiement
    IF v_soignant.type_exercice = 'LIBERAL' OR (v_soignant.type_exercice = 'MIXTE' AND (p_choix_contrat = 'LIBERAL' OR v_mission.type_contrat_recherche = 'LIBERAL')) THEN
        v_type_paiement := 'NOTE_HONORAIRES';
        v_mode_paiement := 'STRIPE_CONNECT';
        v_type_contrat_gen := 'LIBERAL';
    ELSE
        v_type_paiement := 'BULLETIN_PAIE';
        v_mode_paiement := 'DIRECT';
        v_type_contrat_gen := 'CDDU';
    END IF;

    UPDATE missions SET
        soignant_assigne_id = auth.uid(), statut = 'ASSIGNEE',
        choix_contrat_soignant = p_choix_contrat,
        type_paiement_soignant = v_type_paiement,
        mode_paiement_soignant = v_mode_paiement,
        modifie_le = NOW()
    WHERE id = p_mission_id AND statut = 'OUVERTE';

    -- ★ NOUVEAU : créer le contrat dans contrats_mission et retourner son id
    v_numero_contrat := fn_generer_numero_contrat_safe(v_type_contrat_gen);

    INSERT INTO contrats_mission (
        mission_id, etablissement_id, soignant_id,
        type_contrat, numero_contrat, statut
    ) VALUES (
        p_mission_id, v_mission.etablissement_id, auth.uid(),
        v_type_contrat_gen, v_numero_contrat, 'EN_ATTENTE_SIGNATURES'
    )
    ON CONFLICT DO NOTHING
    RETURNING id INTO v_contrat_id;

    -- Si le contrat existait déjà (conflict), on le récupère
    IF v_contrat_id IS NULL THEN
        SELECT id INTO v_contrat_id FROM contrats_mission
        WHERE mission_id = p_mission_id
        ORDER BY cree_le DESC LIMIT 1;
    END IF;

    RETURN jsonb_build_object(
        'success', TRUE,
        'contrat_id', v_contrat_id,
        'contrat_numero', v_numero_contrat,
        'type_paiement', v_type_paiement,
        'mode_paiement', v_mode_paiement
    );
END;
$function$;

-- ═══════════════════════════════════════════════════════════════════
-- 2. attestations_heures_externes : fenêtre d'édition 24h
-- ═══════════════════════════════════════════════════════════════════
-- Ancien: qual = (soignant_id = auth.uid()) — soignant peut modifier à vie
-- Nouveau: idem + restriction à 24h après création + admin sans limite
--
-- NB : la table n'a PAS de colonne `statut` (vérifié via
-- information_schema), donc la contrainte originalement proposée par
-- l'audit (`statut = 'EN_ATTENTE'`) n'était pas applicable. On implémente
-- à la place une fenêtre de correction post-saisie de 24h, qui couvre le
-- cas d'usage légitime "j'ai fait une faute de frappe" sans permettre la
-- réécriture rétroactive des heures déclarées.
DROP POLICY IF EXISTS pol_att_ext_update ON public.attestations_heures_externes;
CREATE POLICY pol_att_ext_update ON public.attestations_heures_externes
  FOR UPDATE
  TO authenticated
  USING (
    est_admin()
    OR (soignant_id = auth.uid() AND cree_le > NOW() - INTERVAL '24 hours')
  )
  WITH CHECK (
    est_admin()
    OR (soignant_id = auth.uid() AND cree_le > NOW() - INTERVAL '24 hours')
  );

-- ═══════════════════════════════════════════════════════════════════
-- 3. fn_confirmer_paiement_soignant : RPC dédiée (defense in depth)
-- ═══════════════════════════════════════════════════════════════════
-- Remplace l'UPDATE direct `supabase.from('paiements_soignant').update(...)`
-- utilisé dans BandeauPaiementDeclare.tsx. Le trigger
-- fn_protect_paiement_soignant reste en place comme filet de sécurité.
CREATE OR REPLACE FUNCTION public.fn_confirmer_paiement_soignant(p_paiement_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_uid UUID := auth.uid();
    v_paiement RECORD;
BEGIN
    IF v_uid IS NULL THEN
        RETURN jsonb_build_object('error', 'Non authentifié');
    END IF;

    SELECT * INTO v_paiement FROM paiements_soignant WHERE id = p_paiement_id;
    IF v_paiement IS NULL THEN
        RETURN jsonb_build_object('error', 'Paiement introuvable');
    END IF;

    -- Seul le soignant destinataire peut confirmer
    IF v_paiement.soignant_id != v_uid THEN
        RETURN jsonb_build_object('error', 'Accès refusé');
    END IF;

    -- Ne pas reconfirmer si déjà confirmé
    IF v_paiement.confirme_par_soignant = TRUE THEN
        RETURN jsonb_build_object('error', 'Paiement déjà confirmé');
    END IF;

    -- Ne pas confirmer un paiement annulé ou contesté
    IF v_paiement.statut NOT IN ('DECLARE', 'EN_ATTENTE') THEN
        RETURN jsonb_build_object('error', 'Ce paiement ne peut plus être confirmé (statut: ' || v_paiement.statut || ')');
    END IF;

    UPDATE paiements_soignant
    SET
        statut = 'CONFIRME',
        confirme_par_soignant = TRUE,
        confirme_par_soignant_le = NOW(),
        modifie_le = NOW()
    WHERE id = p_paiement_id;

    RETURN jsonb_build_object('success', true, 'confirme_le', NOW());
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_confirmer_paiement_soignant(uuid) TO authenticated;
