-- ═══════════════════════════════════════════════════════════════════════════
-- Fixes recette escrow 05/07/2026 — 2 bugs prod bloquants découverts en
-- déroulant la recette 7b-D sur branche neuve (recette-escrow-v3), validés
-- post-fix sur cette même branche.
--
-- BUG 1 (P1, silencieux, depuis l'introduction du wrapper) :
--   fn_ecrire_audit_safe insérait dans des colonnes INEXISTANTES (cle_s3, ip,
--   navigateur — la table a cle_s3_ressource, ip_acteur, navigateur_acteur).
--   L'INSERT échouait à 100 % des appels et le EXCEPTION WHEN OTHERS renvoyait
--   {success:false} que personne ne lit → les 74 call sites du wrapper
--   n'écrivaient JAMAIS d'audit (preuve prod : BULLETIN_PAIE_EMIS=0,
--   NOTATION_DONNEE=0, MEDIATION_*=0 sur 24 410 audits).
--   Redéfinition depuis la déf LIVE (pg_get_functiondef prod) — seule la liste
--   de colonnes de l'INSERT change.
--
-- BUG 2 (bloquant escrow, pattern Sprint 17 « contrainte désynchronisée ») :
--   fn_escrow_rembourser insère dans stripe_refunds_queue avec
--   avoir_id=NULL/facture_origine_id=NULL (un refund escrow n'a ni avoir ni
--   facture d'origine), mais ces colonnes étaient NOT NULL → le remboursement
--   escrow (A5/A6) ne pouvait JAMAIS réussir. On relâche les deux NOT NULL et
--   on garde l'intégrité par un CHECK : toute ligne de la queue provient soit
--   d'un avoir (circuit legacy), soit d'un paiement escrow.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── BUG 1 : fn_ecrire_audit_safe — colonnes réelles de journaux_audit ────────
CREATE OR REPLACE FUNCTION "public"."fn_ecrire_audit_safe"("p_acteur_id" "uuid", "p_type_acteur" "text", "p_action" "text", "p_type_ressource" "text", "p_id_ressource" "uuid", "p_cle_s3" "text" DEFAULT NULL::"text", "p_details" "jsonb" DEFAULT NULL::"jsonb", "p_ip" "inet" DEFAULT NULL::"inet", "p_navigateur" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_id uuid;
  v_uid uuid := auth.uid();
  v_is_service boolean := COALESCE(current_setting('request.jwt.claim.role', true), '') = 'service_role';
  v_acteur_id uuid := p_acteur_id;
BEGIN
  -- Iter3 sec fix : empêcher impersonation cross-user dans audit log
  IF NOT v_is_service AND NOT est_admin() THEN
    IF v_uid IS NULL THEN
      RAISE EXCEPTION 'Non authentifié' USING ERRCODE = '28000';
    END IF;
    v_acteur_id := v_uid;
  END IF;

  -- FIX 05/07/2026 (recette escrow) : les colonnes s'appellent ip_acteur,
  -- navigateur_acteur, cle_s3_ressource — l'INSERT historique visait ip,
  -- navigateur, cle_s3 (inexistantes) → échec 100 % avalé par le catch.
  INSERT INTO journaux_audit (
    acteur_id, type_acteur, action, type_ressource, id_ressource,
    cle_s3_ressource, details, ip_acteur, navigateur_acteur
  ) VALUES (
    v_acteur_id, p_type_acteur, p_action, p_type_ressource, p_id_ressource,
    p_cle_s3, p_details, p_ip, p_navigateur
  ) RETURNING id INTO v_id;
  RETURN jsonb_build_object('success', true, 'id', v_id);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$$;

-- ── BUG 2 : stripe_refunds_queue — origine avoir OU escrow ──────────────────
ALTER TABLE "public"."stripe_refunds_queue" ALTER COLUMN "avoir_id" DROP NOT NULL;
ALTER TABLE "public"."stripe_refunds_queue" ALTER COLUMN "facture_origine_id" DROP NOT NULL;
ALTER TABLE "public"."stripe_refunds_queue" ADD CONSTRAINT "stripe_refunds_queue_origine_check"
  CHECK ("avoir_id" IS NOT NULL OR "paiement_escrow_id" IS NOT NULL);
