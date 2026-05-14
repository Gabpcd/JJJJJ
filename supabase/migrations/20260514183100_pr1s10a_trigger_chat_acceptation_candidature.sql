-- ╔══════════════════════════════════════════════════════════════════════════
-- ║ Sprint 10-A v3 PR 1 — Trigger création conversation à acceptation
-- ║ candidature (chat ouvert dès qu'un soignant est accepté sur une mission)
-- ╚══════════════════════════════════════════════════════════════════════════
--
-- Décision produit Gabrielle (Sprint 10-A v3) :
--   PAS AVANT acceptation (anti-spam, anti-shopping)
--   PAS SEULEMENT APRÈS signature (besoin échanges pré-mission possibles)
--   ⇒ Trigger sur UPDATE candidatures.statut → 'ACCEPTEE'
--
-- Architecture :
--   - 1 conversation = 1 paire (soignant ↔ user_etab) liée à 1 mission
--   - conversations.participant_1_id = soignant, participant_2_id = user étab
--   - Création idempotente (skip si conversation existe déjà pour ce couple)
--   - Audit trail systématique journaux_audit (action='SYSTEM' + détails)
--
-- Sécurité :
--   - SECURITY DEFINER pour contourner RLS (les 2 parties ont rarement SELECT
--     croisé sur participants)
--   - search_path public explicite (anti-injection)
--   - Le trigger ne BLOQUE jamais l'acceptation (try/catch + audit ECHEC)

CREATE OR REPLACE FUNCTION public.fn_creer_conversation_si_absente(
  p_mission_id uuid,
  p_soignant_id uuid,
  p_etablissement_id uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $body$
DECLARE
  v_user_etab_id uuid;
  v_conv_id uuid;
BEGIN
  -- Résoudre user_id du PROPRIÉTAIRE de l'établissement (multi-membres Sprint 5.7)
  SELECT user_id INTO v_user_etab_id
  FROM membres_etablissement
  WHERE etablissement_id = p_etablissement_id
    AND role = 'PROPRIETAIRE'
    AND actif = true
  ORDER BY accepte_le ASC
  LIMIT 1;

  -- Si pas de propriétaire (ne devrait pas arriver post-Sprint 5.7), abandonner
  -- silencieusement (le trigger ne doit JAMAIS bloquer l'acceptation candidature)
  IF v_user_etab_id IS NULL THEN
    INSERT INTO public.journaux_audit(acteur_id, type_acteur, action, type_ressource, id_ressource, details)
    VALUES ('00000000-0000-0000-0000-000000000000', 'SYSTEME', 'SYSTEM', 'conversations', NULL,
            jsonb_build_object(
              'evenement', 'MESSAGERIE_CREATION_CONVERSATION_ECHEC',
              'raison', 'proprietaire_etab_introuvable',
              'mission_id', p_mission_id,
              'soignant_id', p_soignant_id,
              'etablissement_id', p_etablissement_id
            ));
    RETURN NULL;
  END IF;

  -- Idempotence : ne créer que si pas déjà existante pour ce couple+mission
  -- Couvre les deux ordres possibles de participants
  SELECT id INTO v_conv_id
  FROM conversations
  WHERE mission_id = p_mission_id
    AND (
      (participant_1_id = p_soignant_id AND participant_2_id = v_user_etab_id)
      OR (participant_1_id = v_user_etab_id AND participant_2_id = p_soignant_id)
    )
  LIMIT 1;

  IF v_conv_id IS NOT NULL THEN
    RETURN v_conv_id;  -- conversation déjà ouverte, idempotent
  END IF;

  -- Créer la nouvelle conversation : participant_1 = soignant (convention)
  INSERT INTO conversations(mission_id, participant_1_id, participant_2_id, cree_le, dernier_message_le)
  VALUES (p_mission_id, p_soignant_id, v_user_etab_id, NOW(), NOW())
  RETURNING id INTO v_conv_id;

  -- Audit trail (utilise action='SYSTEM' + details.evenement pour respecter CHECK)
  INSERT INTO public.journaux_audit(acteur_id, type_acteur, action, type_ressource, id_ressource, details)
  VALUES (p_soignant_id, 'SYSTEME', 'SYSTEM', 'conversations', v_conv_id,
          jsonb_build_object(
            'evenement', 'MESSAGERIE_CONVERSATION_OUVERTE',
            'origine', 'TRIGGER_ACCEPTATION_CANDIDATURE',
            'mission_id', p_mission_id,
            'soignant_id', p_soignant_id,
            'etablissement_id', p_etablissement_id,
            'user_etab_id', v_user_etab_id
          ));

  RETURN v_conv_id;
END;
$body$;

-- ─── Trigger AFTER UPDATE ON candidatures ─────────────────────────────────

CREATE OR REPLACE FUNCTION public.tg_candidature_acceptee_creer_conversation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $body$
DECLARE
  v_etab_id uuid;
BEGIN
  -- Récupérer l'étab via la mission
  SELECT etablissement_id INTO v_etab_id
  FROM missions
  WHERE id = NEW.mission_id;

  IF v_etab_id IS NULL THEN
    RETURN NEW;  -- mission introuvable, on n'agit pas
  END IF;

  -- Créer la conversation (idempotent). Erreurs avalées pour ne pas bloquer
  -- l'acceptation candidature : on log seulement.
  BEGIN
    PERFORM public.fn_creer_conversation_si_absente(
      NEW.mission_id,
      NEW.soignant_id,
      v_etab_id
    );
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO public.journaux_audit(acteur_id, type_acteur, action, type_ressource, id_ressource, details)
    VALUES ('00000000-0000-0000-0000-000000000000', 'SYSTEME', 'SYSTEM', 'candidatures', NEW.id,
            jsonb_build_object(
              'evenement', 'MESSAGERIE_TRIGGER_ECHEC',
              'sql_state', SQLSTATE,
              'sql_errm', SQLERRM,
              'mission_id', NEW.mission_id,
              'soignant_id', NEW.soignant_id
            ));
  END;

  RETURN NEW;
END;
$body$;

DROP TRIGGER IF EXISTS trg_candidature_acceptee_chat ON candidatures;
CREATE TRIGGER trg_candidature_acceptee_chat
  AFTER UPDATE OF statut ON candidatures
  FOR EACH ROW
  WHEN (NEW.statut = 'ACCEPTEE' AND (OLD.statut IS NULL OR OLD.statut != 'ACCEPTEE'))
  EXECUTE FUNCTION public.tg_candidature_acceptee_creer_conversation();

-- Grants : fonctions appelées uniquement via trigger SECURITY DEFINER, pas de grant authenticated
GRANT EXECUTE ON FUNCTION public.fn_creer_conversation_si_absente(uuid, uuid, uuid) TO service_role;

COMMENT ON FUNCTION public.fn_creer_conversation_si_absente IS
  'Sprint 10-A v3 PR 1 : crée conversation soignant↔user_etab pour une mission si absente. Idempotent. SECURITY DEFINER. Échec silencieux + audit pour ne jamais bloquer l acceptation.';

COMMENT ON FUNCTION public.tg_candidature_acceptee_creer_conversation IS
  'Trigger AFTER UPDATE candidatures.statut → ACCEPTEE : ouvre conversation messagerie. Sprint 10-A v3 PR 1.';

-- Audit installation
INSERT INTO public.journaux_audit(acteur_id, type_acteur, action, type_ressource, id_ressource, details)
VALUES ('00000000-0000-0000-0000-000000000000', 'SYSTEME', 'SYSTEM', 'migration', NULL,
        jsonb_build_object(
          'evenement', 'SPRINT_10A_PR1_INSTALLED',
          'trigger', 'trg_candidature_acceptee_chat',
          'pr', 'Sprint 10-A v3 PR 1',
          'date_iso', NOW()::text
        ));

NOTIFY pgrst, 'reload schema';
