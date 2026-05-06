-- T9 (amélioration intermédiaire) — Modulation du scope de gel facture
-- en attendant la Partie 2 facturation hebdomadaire libérale.
--
-- Contexte (cf. docs/tech-debt.md T9) :
-- Le trigger fn_trg_litige_gel_degel_facture gèle aujourd'hui :
--   - FINANCIER : la facture pointée par litige.facture_id (granularité fine OK)
--   - PRESENCE / CONDITIONS / COMPORTEMENT : TOUTES les factures non-PAYEE
--     de la mission (pas de granularité)
-- Le résultat attendu (post-Partie 2) serait : ne geler que les factures
-- dont [periode_debut, periode_fin] chevauchent la période litigieuse.
--
-- Partie 2 BLOQUE T9 dans sa version définitive parce que :
--   - factures_honoraires n'a pas de colonnes periode_debut / periode_fin
--   - Le modèle actuel = 1 facture par mission (UNIQUE mission_id sur la
--     facture FACTURE), il n'existe pas plusieurs factures par mission
--   - generate-invoice ne sait pas générer une "facture pour S1 d'une
--     mission de 4 semaines"
--
-- Cette migration livre une AMÉLIORATION INTERMÉDIAIRE qui permet à
-- l'admin de moduler l'effet du gel sans attendre Partie 2 :
--
--   gel_facture_scope = 'MISSION_ENTIERE' (défaut, comportement actuel)
--                     = 'FACTURE_UNIQUE'  (force gel UNIQUEMENT facture_id,
--                                          même pour catégories non-FINANCIER)
--                     = 'AUCUN'           (litige informatif/réputationnel,
--                                          pas de gel)
--
-- Quand la Partie 2 arrivera, on ajoutera 'PERIODE_LITIGIEUSE' à la liste
-- et le trigger filtrera les factures par chevauchement de période. Le
-- code intermédiaire reste compatible.

-- ───────────────────────────────────────────────────────────────────────
-- 1. Colonne sur litiges

ALTER TABLE public.litiges
  ADD COLUMN IF NOT EXISTS gel_facture_scope text NOT NULL DEFAULT 'MISSION_ENTIERE';

ALTER TABLE public.litiges
  DROP CONSTRAINT IF EXISTS litiges_gel_facture_scope_check;
ALTER TABLE public.litiges
  ADD CONSTRAINT litiges_gel_facture_scope_check
  CHECK (gel_facture_scope IN ('MISSION_ENTIERE', 'FACTURE_UNIQUE', 'AUCUN'));

COMMENT ON COLUMN public.litiges.gel_facture_scope IS
  'Granularité du gel des factures lors d''ouverture du litige. MISSION_ENTIERE (défaut, gel global), FACTURE_UNIQUE (gel uniquement de la facture pointée par facture_id), AUCUN (pas de gel — litige informatif). Une 4e valeur PERIODE_LITIGIEUSE sera ajoutée avec la Partie 2 facturation hebdomadaire.';

-- ───────────────────────────────────────────────────────────────────────
-- 2. Mise à jour du trigger pour respecter le scope

CREATE OR REPLACE FUNCTION public.fn_trg_litige_gel_degel_facture()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_statuts_ouverts TEXT[] := ARRAY['OUVERT', 'EN_DISCUSSION', 'EN_MEDIATION', 'CONTESTEE'];
  v_statuts_resolus TEXT[] := ARRAY['RESOLU', 'RESOLU_SOIGNANT', 'RESOLU_ETABLISSEMENT', 'RESOLU_ADMIN', 'FERME', 'CLOTURE'];
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
    -- Cas FINANCIER : toujours sur facture_id (granularité fine déjà supportée)
    IF NEW.categorie_litige = 'FINANCIER' AND NEW.facture_id IS NOT NULL THEN
      UPDATE public.factures_honoraires
         SET statut_litige = 'EN_ATTENTE_LITIGE',
             litige_id = NEW.id
       WHERE id = NEW.facture_id
         AND statut_litige = 'NORMAL'
         AND statut <> 'PAYEE';

    -- Cas PRESENCE/CONDITIONS/COMPORTEMENT : selon scope choisi
    ELSIF NEW.categorie_litige IN ('PRESENCE', 'CONDITIONS', 'COMPORTEMENT') THEN
      IF v_scope = 'FACTURE_UNIQUE' AND NEW.facture_id IS NOT NULL THEN
        -- L'admin a explicitement scopé à une facture précise
        UPDATE public.factures_honoraires
           SET statut_litige = 'EN_ATTENTE_LITIGE',
               litige_id = NEW.id
         WHERE id = NEW.facture_id
           AND statut_litige = 'NORMAL'
           AND statut <> 'PAYEE';
      ELSE
        -- Comportement par défaut MISSION_ENTIERE : gel global de la mission
        UPDATE public.factures_honoraires
           SET statut_litige = 'EN_ATTENTE_LITIGE',
               litige_id = NEW.id
         WHERE mission_id = NEW.mission_id
           AND statut_litige = 'NORMAL'
           AND statut <> 'PAYEE';
      END IF;
    END IF;
  END IF;

  IF v_became_resolved THEN
    UPDATE public.factures_honoraires
       SET statut_litige = 'LITIGE_RESOLU_CONFIRME'
     WHERE litige_id = NEW.id
       AND statut_litige = 'EN_ATTENTE_LITIGE';
  END IF;

  RETURN NEW;
END;
$$;

-- ───────────────────────────────────────────────────────────────────────
-- 3. RPC admin pour modifier le scope d'un litige existant

CREATE OR REPLACE FUNCTION public.fn_admin_modifier_gel_scope_litige(
  p_litige_id uuid,
  p_nouveau_scope text,
  p_raison text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_old_scope text;
  v_litige RECORD;
BEGIN
  IF NOT est_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Admin requis');
  END IF;

  IF p_nouveau_scope NOT IN ('MISSION_ENTIERE', 'FACTURE_UNIQUE', 'AUCUN') THEN
    RETURN jsonb_build_object('success', false, 'error',
      'Scope invalide. Valeurs : MISSION_ENTIERE, FACTURE_UNIQUE, AUCUN');
  END IF;

  IF COALESCE(trim(p_raison), '') = '' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Raison obligatoire (audit)');
  END IF;

  SELECT * INTO v_litige FROM litiges WHERE id = p_litige_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Litige introuvable');
  END IF;

  v_old_scope := v_litige.gel_facture_scope;

  IF p_nouveau_scope = 'FACTURE_UNIQUE' AND v_litige.facture_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error',
      'FACTURE_UNIQUE requiert litige.facture_id renseigné');
  END IF;

  -- Mise à jour : le trigger fn_trg_litige_gel_degel_facture re-fire au prochain
  -- changement de statut. Pour appliquer immédiatement, on dégèle les factures
  -- actuellement gelées par ce litige et on les re-gèle selon le nouveau scope.
  -- (Le statut du litige reste inchangé, on bypass la transition pour ré-évaluer.)
  UPDATE litiges SET gel_facture_scope = p_nouveau_scope WHERE id = p_litige_id;

  -- Dégel des factures actuellement liées
  UPDATE factures_honoraires
  SET statut_litige = 'NORMAL', litige_id = NULL
  WHERE litige_id = p_litige_id
    AND statut_litige = 'EN_ATTENTE_LITIGE';

  -- Re-application selon nouveau scope (uniquement si litige toujours ouvert)
  IF v_litige.statut IN ('OUVERT', 'EN_DISCUSSION', 'EN_MEDIATION', 'CONTESTEE')
     AND NOT COALESCE(v_litige.est_informatif, false)
     AND p_nouveau_scope <> 'AUCUN' THEN
    IF v_litige.categorie_litige = 'FINANCIER' AND v_litige.facture_id IS NOT NULL THEN
      UPDATE factures_honoraires
        SET statut_litige = 'EN_ATTENTE_LITIGE', litige_id = p_litige_id
      WHERE id = v_litige.facture_id
        AND statut_litige = 'NORMAL'
        AND statut <> 'PAYEE';
    ELSIF v_litige.categorie_litige::text IN ('PRESENCE', 'CONDITIONS', 'COMPORTEMENT') THEN
      IF p_nouveau_scope = 'FACTURE_UNIQUE' AND v_litige.facture_id IS NOT NULL THEN
        UPDATE factures_honoraires
          SET statut_litige = 'EN_ATTENTE_LITIGE', litige_id = p_litige_id
        WHERE id = v_litige.facture_id
          AND statut_litige = 'NORMAL'
          AND statut <> 'PAYEE';
      ELSE
        UPDATE factures_honoraires
          SET statut_litige = 'EN_ATTENTE_LITIGE', litige_id = p_litige_id
        WHERE mission_id = v_litige.mission_id
          AND statut_litige = 'NORMAL'
          AND statut <> 'PAYEE';
      END IF;
    END IF;
  END IF;

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_uid,
    p_type_acteur := 'ADMIN_PLATEFORME',
    p_action := 'LITIGE_GEL_SCOPE_MODIFIE',
    p_type_ressource := 'litige',
    p_id_ressource := p_litige_id,
    p_details := jsonb_build_object(
      'old_scope', v_old_scope,
      'new_scope', p_nouveau_scope,
      'raison', p_raison,
      'reapplique_immediatement', true
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'litige_id', p_litige_id,
    'old_scope', v_old_scope,
    'new_scope', p_nouveau_scope
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_admin_modifier_gel_scope_litige(uuid, text, text) TO authenticated;

NOTIFY pgrst, 'reload schema';
