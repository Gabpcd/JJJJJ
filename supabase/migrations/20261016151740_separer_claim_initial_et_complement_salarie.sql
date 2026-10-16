-- Après les six migrations déjà installées : corriger uniquement l'admission
-- d'un complément salarié distinct de sa commission initiale payée par carte.
-- Aucune suppression/réattribution de claim ni modification d'une facture.
BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE OR REPLACE FUNCTION private.fn_admission_virement_commission(p_facture_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public AS $admission$
DECLARE
  f public.factures%ROWTYPE;
  h public.factures_honoraires%ROWTYPE;
  e public.etablissements%ROWTYPE;
  motif text;
BEGIN
  SELECT * INTO f FROM public.factures WHERE id=p_facture_id;
  SELECT * INTO e FROM public.etablissements WHERE id=f.etablissement_id;
  IF f.id IS NULL OR e.id IS NULL THEN motif:='FACTURE_INDISPONIBLE';
  ELSIF f.type_document NOT IN ('FACTURE','FACTURE_COMPLEMENTAIRE')
    OR f.statut IS NULL OR f.statut NOT IN ('EMISE','EN_RETARD') THEN motif:='FACTURE_NON_PAYABLE';
  ELSIF f.est_secteur_public IS TRUE OR e.est_secteur_public IS TRUE
    OR e.chorus_pro_actif IS TRUE THEN motif:='FACTURE_PUBLIQUE_CHORUS';
  ELSIF e.mode_paiement_commission='SEPA_DEBIT' THEN motif:='PAIEMENT_SEPA_AUTOMATIQUE';
  ELSIF f.stripe_payment_intent_id IS NOT NULL OR f.stripe_hosted_url IS NOT NULL
    OR f.stripe_invoice_id IS NOT NULL THEN motif:='PAIEMENT_EN_LIGNE_ENGAGE';
  ELSIF EXISTS (SELECT 1 FROM public.stripe_payment_flow_claims c
    WHERE c.resource_key='FACTURE:'||f.id::text
      OR ((c.resource_key='MISSION:'||f.mission_id::text
        OR EXISTS (SELECT 1 FROM public.missions m WHERE m.facture_id=f.id
          AND c.resource_key='MISSION:'||m.id::text))
        AND NOT EXISTS (
          -- Seul le claim carte de l'initiale canonique déjà réglée est distinct
          -- de ce complément salarial. Tout claim de la pièce exacte, autre
          -- flux, propriétaire, session ou contexte reste bloquant.
          SELECT 1 FROM public.missions m
          JOIN public.factures initiale ON initiale.id=f.facture_precedente_id
            AND m.facture_id=initiale.id
          JOIN public.stripe_payment_flow_claims initial_claim
            ON initial_claim.resource_key='FACTURE:'||initiale.id::text
          WHERE f.type_document='FACTURE_COMPLEMENTAIRE' AND f.facture_honoraire_id IS NULL
            AND m.id=f.mission_id AND m.type_contrat_applique='SALARIE'
            AND m.etablissement_id=f.etablissement_id
            AND initiale.etablissement_id=f.etablissement_id AND initiale.type_document='FACTURE'
            AND initiale.facture_honoraire_id IS NULL AND initiale.statut='PAYEE'
            AND (initiale.mission_id IS NULL OR initiale.mission_id=m.id)
            AND nullif(initiale.stripe_payment_intent_id,'') IS NOT NULL
            AND c.resource_key='MISSION:'||m.id::text AND c.flow='CHECKOUT_INVOICE'
            AND c.owner_token='invoice:'||initiale.id::text
            AND initial_claim.flow=c.flow AND initial_claim.owner_token=c.owner_token
            AND nullif(c.stripe_checkout_session_id,'') IS NOT NULL
            AND initial_claim.stripe_checkout_session_id=c.stripe_checkout_session_id
            AND initial_claim.stripe_payment_intent_id IS NOT DISTINCT FROM c.stripe_payment_intent_id
            AND (c.stripe_payment_intent_id IS NULL OR c.stripe_payment_intent_id=initiale.stripe_payment_intent_id)
        ))) THEN motif:='PAIEMENT_EN_LIGNE_ENGAGE';
  ELSIF EXISTS (SELECT 1 FROM public.stripe_transfers st
    WHERE st.facture_id=f.id OR (st.mission_id=f.mission_id
      AND (st.facture_honoraire_id=f.facture_honoraire_id OR st.facture_honoraire_id IS NULL))
      -- Repli historique seulement : une trace liée à une autre FH de la même
      -- mission ne représente pas la commission de cette période explicite.
      OR (st.facture_honoraire_id IS NULL AND EXISTS (SELECT 1 FROM public.missions m
        WHERE m.facture_id=f.id AND st.mission_id=m.id)))
    THEN motif:='PAIEMENT_EN_LIGNE_ENGAGE';
  ELSIF EXISTS (SELECT 1 FROM public.factures a WHERE a.facture_precedente_id=f.id
    AND a.type_document='AVOIR' AND a.statut<>'ANNULEE') THEN motif:='AVOIR_A_RAPPROCHER';
  END IF;

  IF motif IS NULL AND f.facture_honoraire_id IS NOT NULL THEN
    SELECT * INTO h FROM public.factures_honoraires WHERE id=f.facture_honoraire_id;
    IF h.id IS NULL OR h.type_document<>'FACTURE'
      OR ROW(h.mission_id,h.etablissement_id) IS DISTINCT FROM ROW(f.mission_id,f.etablissement_id)
      OR h.statut NOT IN ('EMISE','EN_RETARD','PAYEE') THEN motif:='HONORAIRES_INDISPONIBLES';
    ELSIF h.stripe_payment_intent_id IS NOT NULL THEN motif:='PAIEMENT_EN_LIGNE_ENGAGE';
    ELSIF EXISTS (SELECT 1 FROM public.factures_honoraires a
      WHERE a.facture_precedente_id=h.id AND a.type_document='AVOIR'
        AND a.statut NOT IN ('ANNULEE','ERREUR_GENERATION','REMPLACEE')) THEN motif:='AVOIR_A_RAPPROCHER';
    ELSIF (SELECT count(*) FROM public.paiements_soignant p
      WHERE p.facture_honoraire_id=h.id OR (p.mission_id=h.mission_id AND p.facture_honoraire_id IS NULL))<>1
      OR NOT EXISTS (SELECT 1 FROM public.paiements_soignant p
        WHERE p.facture_honoraire_id=h.id AND p.mission_id=h.mission_id
          AND p.etablissement_id=h.etablissement_id AND p.soignant_id=h.soignant_id
          AND p.stripe_transfer_id IS NULL AND p.statut IN ('DECLARE','CONFIRME')
          AND p.methode IN ('VIREMENT','CHEQUE','NOTE_HONORAIRES')
          AND p.montant_net=h.montant_ttc) THEN motif:='HONORAIRES_DIRECTS_REQUIS';
    END IF;
  ELSIF motif IS NULL AND f.mission_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.missions m WHERE m.id=f.mission_id
      AND m.etablissement_id=f.etablissement_id AND m.type_contrat_applique='SALARIE'
  ) THEN
    -- Une ancienne commission libérale sans pièce explicite reste à rapprocher.
    motif:='HONORAIRES_INDISPONIBLES';
  END IF;
  RETURN jsonb_build_object('facture_id',p_facture_id,
    'virement_autorise',motif IS NULL,'motif',motif);
END;
$admission$;

-- Fonction privée déjà propriétaire postgres et sans droits clients :
-- CREATE OR REPLACE conserve son ACL ; aucun inventaire public à modifier.
COMMIT;
