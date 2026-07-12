-- Lot 21 — Suspension d'un compte : motif OBLIGATOIRE, journalisé dans journaux_audit.
--
-- Feuille de route Lots 19-21 §Lot 21.3 : « Suspendre rétrogradé en secondaire,
-- derrière une confirmation avec motif obligatoire journalisé dans journaux_audit ».
--
-- La RPC journalisait déjà SUSPENSION_COMPTE mais SANS motif et sans l'exiger.
-- On ajoute p_motif : exigé côté serveur pour suspendre (rejet si absent),
-- optionnel pour réactiver, et inclus dans le détail d'audit.
-- Suspension = soft-delete réversible (supprime_le = NOW()), pas de suppression dure.

-- Bug latent (pattern Sprint 17) : la contrainte journaux_audit_action_check ne
-- listait PAS 'SUSPENSION_COMPTE'/'REACTIVATION_COMPTE' → l'INSERT audit de la RPC
-- levait une violation CHECK → toute suspension échouait déjà en prod (chemin jamais
-- exercé). On ajoute les 2 actions SANS toucher au reste de la liste (reconstruction
-- dynamique idempotente : lit la définition courante et n'injecte que le delta).
DO $do$
DECLARE v_def text;
BEGIN
  SELECT pg_get_constraintdef(oid) INTO v_def
  FROM pg_constraint WHERE conname = 'journaux_audit_action_check';
  IF v_def IS NOT NULL AND position('SUSPENSION_COMPTE' IN v_def) = 0 THEN
    ALTER TABLE journaux_audit DROP CONSTRAINT journaux_audit_action_check;
    EXECUTE 'ALTER TABLE journaux_audit ADD CONSTRAINT journaux_audit_action_check '
      || replace(v_def, '])))', $q$, 'SUSPENSION_COMPTE'::text, 'REACTIVATION_COMPTE'::text])))$q$);
  END IF;
END $do$;

-- L'ajout de p_motif change la signature (3→4 args) : on DROP l'ancienne pour
-- éviter une surcharge ambiguë (3-arg + 4-arg-avec-défaut), puis on recrée + GRANT.
DROP FUNCTION IF EXISTS public.fn_admin_suspendre_utilisateur(text, uuid, boolean);

CREATE OR REPLACE FUNCTION public.fn_admin_suspendre_utilisateur(
    p_table text,
    p_id uuid,
    p_suspendre boolean DEFAULT true,
    p_motif text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_nom TEXT;
    v_motif TEXT := NULLIF(TRIM(COALESCE(p_motif, '')), '');
BEGIN
    IF NOT est_admin() THEN
        RETURN jsonb_build_object('error', 'Accès refusé — admin uniquement');
    END IF;

    IF p_table NOT IN ('soignants', 'etablissements') THEN
        RETURN jsonb_build_object('error', 'Table invalide');
    END IF;

    -- Motif obligatoire pour suspendre (tracé). Réactivation : motif optionnel.
    IF p_suspendre AND v_motif IS NULL THEN
        RETURN jsonb_build_object('error', 'Motif obligatoire pour suspendre un compte');
    END IF;

    IF p_table = 'soignants' THEN
        IF p_suspendre THEN
            UPDATE soignants SET supprime_le = NOW() WHERE id = p_id AND supprime_le IS NULL;
        ELSE
            UPDATE soignants SET supprime_le = NULL WHERE id = p_id AND supprime_le IS NOT NULL;
        END IF;
        SELECT COALESCE(prenom || ' ' || nom, 'Inconnu') INTO v_nom FROM soignants WHERE id = p_id;
    ELSIF p_table = 'etablissements' THEN
        IF p_suspendre THEN
            UPDATE etablissements SET supprime_le = NOW(), peut_publier_missions = FALSE WHERE id = p_id AND supprime_le IS NULL;
        ELSE
            UPDATE etablissements SET supprime_le = NULL WHERE id = p_id AND supprime_le IS NOT NULL;
        END IF;
        SELECT COALESCE(nom, 'Inconnu') INTO v_nom FROM etablissements WHERE id = p_id;
    END IF;

    INSERT INTO journaux_audit (acteur_id, type_acteur, action, type_ressource, id_ressource, details)
    VALUES (
        auth.uid(), 'ADMIN',
        CASE WHEN p_suspendre THEN 'SUSPENSION_COMPTE' ELSE 'REACTIVATION_COMPTE' END,
        p_table, p_id,
        jsonb_build_object(
            'nom', v_nom,
            'table', p_table,
            'action', CASE WHEN p_suspendre THEN 'suspendre' ELSE 'réactiver' END,
            'motif', v_motif)
    );

    RETURN jsonb_build_object(
        'success', TRUE,
        'message', CASE WHEN p_suspendre THEN 'Compte suspendu : ' ELSE 'Compte réactivé : ' END || v_nom
    );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_admin_suspendre_utilisateur(text, uuid, boolean, text) TO authenticated;
