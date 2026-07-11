-- Phase 2 store-readiness — BLOCAGE utilisateur (App Store Guideline 1.2, UGC :
-- report ET block). Le signalement existe déjà (fn_signaler_utilisateur) ; il
-- manquait le blocage EFFECTIF. On ajoute une table + 3 RPCs + l'intégration
-- dans fn_envoyer_message (refus d'échange si l'un des deux participants a
-- bloqué l'autre). Redéfinition de fn_envoyer_message depuis la déf LIVE
-- (règle 9.0), seul le check blocage est ajouté.

CREATE TABLE IF NOT EXISTS public.utilisateurs_bloques (
  bloqueur_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  bloque_id   uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  motif       text,
  cree_le     timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (bloqueur_id, bloque_id),
  CONSTRAINT chk_pas_soi_meme CHECK (bloqueur_id <> bloque_id)
);

ALTER TABLE public.utilisateurs_bloques ENABLE ROW LEVEL SECURITY;

-- Lecture : chacun voit SES blocages ; admin voit tout. Écriture via RPC only.
DROP POLICY IF EXISTS pol_blocages_select ON public.utilisateurs_bloques;
CREATE POLICY pol_blocages_select ON public.utilisateurs_bloques FOR SELECT
  USING (bloqueur_id = (SELECT auth.uid()) OR (SELECT est_admin()));

-- Bloquer un utilisateur (idempotent).
CREATE OR REPLACE FUNCTION public.fn_bloquer_utilisateur(p_cible_id uuid, p_motif text DEFAULT NULL)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('error', 'Non authentifié'); END IF;
  IF p_cible_id IS NULL OR p_cible_id = v_uid THEN
    RETURN jsonb_build_object('error', 'Cible invalide.');
  END IF;
  INSERT INTO utilisateurs_bloques (bloqueur_id, bloque_id, motif)
  VALUES (v_uid, p_cible_id, NULLIF(TRIM(COALESCE(p_motif, '')), ''))
  ON CONFLICT (bloqueur_id, bloque_id) DO UPDATE SET motif = EXCLUDED.motif;
  RETURN jsonb_build_object('success', true);
END;
$function$;

-- Débloquer.
CREATE OR REPLACE FUNCTION public.fn_debloquer_utilisateur(p_cible_id uuid)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('error', 'Non authentifié'); END IF;
  DELETE FROM utilisateurs_bloques WHERE bloqueur_id = v_uid AND bloque_id = p_cible_id;
  RETURN jsonb_build_object('success', true);
END;
$function$;

-- Est-ce que je bloque cet utilisateur ? (pour piloter le bouton Bloquer/Débloquer)
CREATE OR REPLACE FUNCTION public.fn_est_bloque(p_cible_id uuid)
 RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
  SELECT EXISTS (SELECT 1 FROM utilisateurs_bloques WHERE bloqueur_id = auth.uid() AND bloque_id = p_cible_id);
$function$;

GRANT EXECUTE ON FUNCTION public.fn_bloquer_utilisateur(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_debloquer_utilisateur(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_est_bloque(uuid) TO authenticated;

-- Intégration : fn_envoyer_message refuse si blocage bilatéral (déf LIVE + check).
CREATE OR REPLACE FUNCTION public.fn_envoyer_message(p_conversation_id uuid, p_contenu text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
    v_conv RECORD;
    v_autre uuid;
BEGIN
    IF p_contenu IS NULL OR LENGTH(TRIM(p_contenu)) < 1 THEN
        RETURN jsonb_build_object('error', 'Le message ne peut pas être vide.');
    END IF;
    IF LENGTH(p_contenu) > 5000 THEN
        RETURN jsonb_build_object('error', 'Le message est trop long (5000 caractères max).');
    END IF;

    SELECT * INTO v_conv FROM conversations WHERE id = p_conversation_id;
    IF v_conv IS NULL THEN RETURN '{"error":"Conversation introuvable"}'::JSONB; END IF;

    IF v_conv.participant_1_id != auth.uid()
       AND v_conv.participant_2_id != auth.uid()
       AND NOT est_admin() THEN
        RETURN '{"error":"Accès refusé"}'::JSONB;
    END IF;

    -- Blocage (App Store 1.2) : si l'un des deux participants a bloqué l'autre,
    -- plus aucun message ne passe (dans les deux sens).
    v_autre := CASE WHEN v_conv.participant_1_id = auth.uid()
                    THEN v_conv.participant_2_id ELSE v_conv.participant_1_id END;
    IF v_autre IS NOT NULL AND EXISTS (
      SELECT 1 FROM utilisateurs_bloques
      WHERE (bloqueur_id = auth.uid() AND bloque_id = v_autre)
         OR (bloqueur_id = v_autre AND bloque_id = auth.uid())
    ) THEN
        RETURN jsonb_build_object('error', 'Vous ne pouvez plus échanger avec cet utilisateur (blocage actif).');
    END IF;

    INSERT INTO messages_chat (conversation_id, auteur_id, contenu, est_admin)
    VALUES (p_conversation_id, auth.uid(), fn_html_escape(p_contenu), est_admin());

    UPDATE conversations SET dernier_message_le = NOW() WHERE id = p_conversation_id;

    RETURN '{"success":true}'::JSONB;
END;
$function$;
