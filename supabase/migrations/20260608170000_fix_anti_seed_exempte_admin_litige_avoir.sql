-- Fix : le trigger anti-seed bloquait les résolutions de litige avec ajustement
-- financier (AVOIR / ANNULER_REEMETTRE) sur les factures d'honoraires libérales.
--
-- CONTEXTE (découvert par audit e2e impersonation, rollback) :
-- fn_admin_resoudre_litige crée, dans ses branches AVOIR/ré-émission, une facture
-- d'honoraires au montant AJUSTÉ (taux/heures révisés) — donc légitimement différent
-- du snapshot mission.net_a_payer. Le trigger fn_anti_seed_facture_honoraire (ajouté
-- après le Sprint 17 pour empêcher le seeding de factures incohérentes) déclenchait
-- alors une check_violation « montant_ht incohérent avec mission.net_a_payer » et
-- faisait ÉCHOUER toute résolution AVOIR en production.
--
-- Reproduction e2e : mission libérale IDE → facture honoraires 232.80€ → litige
-- DESACCORD_MONTANT_FACTURE → fn_admin_resoudre_litige(AVOIR, taux 35→20) →
-- "anti-seed facture: montant_ht 72.80 incoherent avec mission.net_a_payer 232.80".
-- Avec la GUC d'override posée, le flux avoir + remboursement se termine (validé).
--
-- FIX : le trigger exempte désormais (en l'auditant) les opérations émanant d'un
-- ADMIN authentifié (est_admin()). C'est plus strict que le path GUC existant
-- (jolene.admin_seed_override_reason, non gaté admin) et débloque les opérations
-- financières légitimes (résolution de litige) sans rouvrir la porte au seeding
-- par script non-admin. La protection anti-seed reste pleine pour tout caller
-- non-admin sans GUC.

CREATE OR REPLACE FUNCTION public.fn_anti_seed_facture_honoraire()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_mission_net numeric;
  v_ecart numeric;
  v_ctx text;
  v_admin_reason text;
BEGIN
  -- 1. Path edge function generate-invoice (GUC posée côté serveur)
  v_ctx := NULLIF(current_setting('jolene.generate_invoice_context', true), '');
  IF v_ctx = 'true' THEN
    RETURN NEW;
  END IF;

  -- 2. Override admin explicite (GUC + raison, audité)
  v_admin_reason := NULLIF(current_setting('jolene.admin_seed_override_reason', true), '');
  IF v_admin_reason IS NOT NULL THEN
    INSERT INTO journaux_audit
      (acteur_id, type_acteur, action, type_ressource, id_ressource, details)
    VALUES (
      auth.uid(), 'ADMIN_PLATEFORME', 'OVERRIDE_ANTI_SEED',
      'factures_honoraires', NEW.id,
      jsonb_build_object(
        'reason', v_admin_reason,
        'mission_id', NEW.mission_id,
        'montant_ht', NEW.montant_ht,
        'numero_facture', NEW.numero_facture
      )
    );
    RETURN NEW;
  END IF;

  -- 3. Opération émanant d'un ADMIN authentifié (ex. fn_admin_resoudre_litige
  -- branches AVOIR / ANNULER_REEMETTRE qui ré-émettent une facture au montant
  -- ajusté). Légitime → exempté ET audité.
  IF public.est_admin() THEN
    INSERT INTO journaux_audit
      (acteur_id, type_acteur, action, type_ressource, id_ressource, details)
    VALUES (
      auth.uid(), 'ADMIN_PLATEFORME', 'OVERRIDE_ANTI_SEED',
      'factures_honoraires', NEW.id,
      jsonb_build_object(
        'reason', 'admin_context (résolution litige / ajustement financier)',
        'mission_id', NEW.mission_id,
        'montant_ht', NEW.montant_ht,
        'numero_facture', NEW.numero_facture
      )
    );
    RETURN NEW;
  END IF;

  -- 4. Sinon : contrôle de cohérence anti-seed (caller non-admin, sans GUC)
  SELECT net_a_payer INTO v_mission_net
  FROM missions WHERE id = NEW.mission_id;

  IF v_mission_net IS NULL THEN
    RAISE EXCEPTION 'anti-seed facture: mission % sans snapshot financier (net_a_payer=NULL). Utilisez generate-invoice ou définissez jolene.admin_seed_override_reason.',
      NEW.mission_id USING ERRCODE = 'check_violation';
  END IF;

  v_ecart := ABS(COALESCE(NEW.montant_ht, 0) - v_mission_net);
  IF v_ecart > 0.50 THEN
    RAISE EXCEPTION 'anti-seed facture: montant_ht % incoherent avec mission.net_a_payer % (ecart=%€ > 0.50€). Utilisez generate-invoice ou jolene.admin_seed_override_reason.',
      NEW.montant_ht, v_mission_net, v_ecart
      USING ERRCODE = 'check_violation';
  END IF;

  RETURN NEW;
END;
$function$;
