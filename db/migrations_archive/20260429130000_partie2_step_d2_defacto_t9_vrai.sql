-- Partie 2 — Step D2 : Trigger Defacto opt-in + T9 vrai débloqué

-- 1. Trigger AFTER UPDATE EMISE → auto-cession Defacto si opt-in
CREATE OR REPLACE FUNCTION public.fn_trg_defacto_auto_cession()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_opt_in boolean;
  v_soignant RECORD;
BEGIN
  IF NEW.statut = 'EMISE' AND (OLD.statut IS DISTINCT FROM 'EMISE')
     AND NEW.type_document = 'FACTURE' THEN
    SELECT defacto_opt_in, mandat_facturation_signe
    INTO v_opt_in, v_soignant.mandat_facturation_signe
    FROM soignants WHERE id = NEW.soignant_id;

    IF COALESCE(v_opt_in, false) = true THEN
      IF NOT EXISTS (SELECT 1 FROM cessions_creance WHERE facture_honoraire_id = NEW.id) THEN
        INSERT INTO cessions_creance (
          soignant_id, facture_honoraire_id, montant,
          version_texte, contenu_hash, signed_at, ip_address, user_agent
        ) VALUES (
          NEW.soignant_id, NEW.id, NEW.montant_ttc,
          'auto_defacto_opt_in_v1', 'auto', NOW(), 'system', 'weekly-invoicing-cron'
        );
        UPDATE factures_honoraires SET factor_assigned = true WHERE id = NEW.id;
        PERFORM public.fn_ecrire_audit_safe(
          p_acteur_id := NEW.soignant_id, p_type_acteur := 'SYSTEME',
          p_action := 'FACTURATION', p_type_ressource := 'facture_honoraire',
          p_id_ressource := NEW.id,
          p_details := jsonb_build_object('event','DEFACTO_AUTO_CESSION','montant_ttc',NEW.montant_ttc,'opt_in',true)
        );
      END IF;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_defacto_auto_cession ON public.factures_honoraires;
CREATE TRIGGER trg_defacto_auto_cession
  AFTER UPDATE OF statut ON public.factures_honoraires
  FOR EACH ROW EXECUTE FUNCTION public.fn_trg_defacto_auto_cession();

-- 2. T9 vrai : PERIODE_LITIGIEUSE + colonnes periode_* litiges
ALTER TABLE public.litiges
  ADD COLUMN IF NOT EXISTS periode_debut date,
  ADD COLUMN IF NOT EXISTS periode_fin date;

ALTER TABLE public.litiges DROP CONSTRAINT IF EXISTS litiges_gel_facture_scope_check;
ALTER TABLE public.litiges ADD CONSTRAINT litiges_gel_facture_scope_check
  CHECK (gel_facture_scope IN ('MISSION_ENTIERE','FACTURE_UNIQUE','AUCUN','PERIODE_LITIGIEUSE'));

-- Trigger gel/dégel étendu avec branche PERIODE_LITIGIEUSE
CREATE OR REPLACE FUNCTION public.fn_trg_litige_gel_degel_facture()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_statuts_ouverts TEXT[] := ARRAY['OUVERT','EN_DISCUSSION','EN_MEDIATION','CONTESTEE'];
  v_statuts_resolus TEXT[] := ARRAY['RESOLU','RESOLU_SOIGNANT','RESOLU_ETABLISSEMENT','RESOLU_ADMIN','FERME','CLOTURE'];
  v_became_open BOOLEAN;
  v_became_resolved BOOLEAN;
  v_scope text;
BEGIN
  IF TG_OP = 'INSERT' THEN
    v_became_open := NEW.statut = ANY(v_statuts_ouverts);
    v_became_resolved := FALSE;
  ELSE
    v_became_open := NEW.statut = ANY(v_statuts_ouverts) AND (OLD.statut IS NULL OR OLD.statut <> NEW.statut);
    v_became_resolved := NEW.statut = ANY(v_statuts_resolus) AND (OLD.statut IS NULL OR OLD.statut <> NEW.statut);
  END IF;
  v_scope := COALESCE(NEW.gel_facture_scope, 'MISSION_ENTIERE');

  IF v_became_open AND NOT NEW.est_informatif AND v_scope <> 'AUCUN' THEN
    IF NEW.categorie_litige = 'FINANCIER' AND NEW.facture_id IS NOT NULL THEN
      UPDATE factures_honoraires SET statut_litige='EN_ATTENTE_LITIGE', litige_id=NEW.id
       WHERE id=NEW.facture_id AND statut_litige='NORMAL' AND statut<>'PAYEE';
    ELSIF NEW.categorie_litige IN ('PRESENCE','CONDITIONS','COMPORTEMENT') THEN
      IF v_scope = 'FACTURE_UNIQUE' AND NEW.facture_id IS NOT NULL THEN
        UPDATE factures_honoraires SET statut_litige='EN_ATTENTE_LITIGE', litige_id=NEW.id
         WHERE id=NEW.facture_id AND statut_litige='NORMAL' AND statut<>'PAYEE';
      ELSIF v_scope = 'PERIODE_LITIGIEUSE' AND NEW.periode_debut IS NOT NULL AND NEW.periode_fin IS NOT NULL THEN
        UPDATE factures_honoraires SET statut_litige='EN_ATTENTE_LITIGE', litige_id=NEW.id
         WHERE mission_id=NEW.mission_id AND statut_litige='NORMAL' AND statut<>'PAYEE'
           AND periode_debut <= NEW.periode_fin AND periode_fin >= NEW.periode_debut;
      ELSE
        UPDATE factures_honoraires SET statut_litige='EN_ATTENTE_LITIGE', litige_id=NEW.id
         WHERE mission_id=NEW.mission_id AND statut_litige='NORMAL' AND statut<>'PAYEE';
      END IF;
    END IF;
  END IF;

  IF v_became_resolved THEN
    UPDATE factures_honoraires SET statut_litige='LITIGE_RESOLU_CONFIRME'
     WHERE litige_id=NEW.id AND statut_litige='EN_ATTENTE_LITIGE';
  END IF;
  RETURN NEW;
END;
$$;

-- fn_admin_modifier_gel_scope_litige étendu (PERIODE_LITIGIEUSE accepté)
CREATE OR REPLACE FUNCTION public.fn_admin_modifier_gel_scope_litige(
  p_litige_id uuid, p_nouveau_scope text, p_raison text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_old_scope text;
  v_litige RECORD;
BEGIN
  IF NOT est_admin() THEN RETURN jsonb_build_object('success',false,'error','Admin requis'); END IF;
  IF p_nouveau_scope NOT IN ('MISSION_ENTIERE','FACTURE_UNIQUE','AUCUN','PERIODE_LITIGIEUSE') THEN
    RETURN jsonb_build_object('success',false,'error','Scope invalide');
  END IF;
  IF COALESCE(trim(p_raison),'') = '' THEN RETURN jsonb_build_object('success',false,'error','Raison obligatoire'); END IF;
  SELECT * INTO v_litige FROM litiges WHERE id = p_litige_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('success',false,'error','Litige introuvable'); END IF;
  v_old_scope := v_litige.gel_facture_scope;
  IF p_nouveau_scope = 'FACTURE_UNIQUE' AND v_litige.facture_id IS NULL THEN
    RETURN jsonb_build_object('success',false,'error','FACTURE_UNIQUE requiert facture_id');
  END IF;
  IF p_nouveau_scope = 'PERIODE_LITIGIEUSE' AND (v_litige.periode_debut IS NULL OR v_litige.periode_fin IS NULL) THEN
    RETURN jsonb_build_object('success',false,'error','PERIODE_LITIGIEUSE requiert periode_debut et periode_fin');
  END IF;
  UPDATE litiges SET gel_facture_scope = p_nouveau_scope WHERE id = p_litige_id;
  UPDATE factures_honoraires SET statut_litige='NORMAL', litige_id=NULL
   WHERE litige_id=p_litige_id AND statut_litige='EN_ATTENTE_LITIGE';
  IF v_litige.statut IN ('OUVERT','EN_DISCUSSION','EN_MEDIATION','CONTESTEE')
     AND NOT COALESCE(v_litige.est_informatif,false) AND p_nouveau_scope <> 'AUCUN' THEN
    IF v_litige.categorie_litige = 'FINANCIER' AND v_litige.facture_id IS NOT NULL THEN
      UPDATE factures_honoraires SET statut_litige='EN_ATTENTE_LITIGE', litige_id=p_litige_id
       WHERE id=v_litige.facture_id AND statut_litige='NORMAL' AND statut<>'PAYEE';
    ELSIF v_litige.categorie_litige::text IN ('PRESENCE','CONDITIONS','COMPORTEMENT') THEN
      IF p_nouveau_scope = 'FACTURE_UNIQUE' AND v_litige.facture_id IS NOT NULL THEN
        UPDATE factures_honoraires SET statut_litige='EN_ATTENTE_LITIGE', litige_id=p_litige_id
         WHERE id=v_litige.facture_id AND statut_litige='NORMAL' AND statut<>'PAYEE';
      ELSIF p_nouveau_scope = 'PERIODE_LITIGIEUSE' AND v_litige.periode_debut IS NOT NULL AND v_litige.periode_fin IS NOT NULL THEN
        UPDATE factures_honoraires SET statut_litige='EN_ATTENTE_LITIGE', litige_id=p_litige_id
         WHERE mission_id=v_litige.mission_id AND statut_litige='NORMAL' AND statut<>'PAYEE'
           AND periode_debut <= v_litige.periode_fin AND periode_fin >= v_litige.periode_debut;
      ELSE
        UPDATE factures_honoraires SET statut_litige='EN_ATTENTE_LITIGE', litige_id=p_litige_id
         WHERE mission_id=v_litige.mission_id AND statut_litige='NORMAL' AND statut<>'PAYEE';
      END IF;
    END IF;
  END IF;
  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_uid, p_type_acteur := 'ADMIN_PLATEFORME',
    p_action := 'LITIGE_GEL_SCOPE_MODIFIE', p_type_ressource := 'litige',
    p_id_ressource := p_litige_id,
    p_details := jsonb_build_object('old_scope',v_old_scope,'new_scope',p_nouveau_scope,'raison',p_raison,'reapplique_immediatement',true)
  );
  RETURN jsonb_build_object('success',true,'litige_id',p_litige_id,'old_scope',v_old_scope,'new_scope',p_nouveau_scope);
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_admin_modifier_gel_scope_litige(uuid, text, text) TO authenticated;

NOTIFY pgrst, 'reload schema';
