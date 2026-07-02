-- Lot 6c — Décisions produit D1 + D2 (sémantique des gestes du swipe).
--
-- D1 : ⭐ = FAVORIS illimités (sauvegarder la mission pour y revenir), plus de
--      candidature prioritaire ni de quota 5/jour. La super-candidature est
--      reportée v2 (trigger mesurable : médiane candidatures/mission > 3 sur
--      30 j glissants).
-- D2 : ❤️ = candidature immédiate FERME. Garde-fous : blocage si conflit avec
--      une mission déjà confirmée sur le créneau (trigger = couvre TOUS les
--      chemins de candidature), warning missions adjacentes, auto-expiration
--      des candidatures quand la mission démarre sans réponse de l'étab.

-- 1) Missions sauvegardées (favoris de MISSIONS — distinct des favoris d'étab)

CREATE TABLE IF NOT EXISTS public.missions_sauvegardees (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  soignant_id uuid NOT NULL REFERENCES public.soignants(id) ON DELETE CASCADE,
  mission_id uuid NOT NULL REFERENCES public.missions(id) ON DELETE CASCADE,
  cree_le timestamptz NOT NULL DEFAULT now(),
  -- Anti-fuite du favori : le push « ta mission sauvegardée démarre dans 48 h »
  -- n'est envoyé qu'une fois.
  notifie_expiration boolean NOT NULL DEFAULT false,
  UNIQUE (soignant_id, mission_id)
);

CREATE INDEX IF NOT EXISTS idx_missions_sauvegardees_soignant ON public.missions_sauvegardees (soignant_id);
CREATE INDEX IF NOT EXISTS idx_missions_sauvegardees_mission ON public.missions_sauvegardees (mission_id);

ALTER TABLE public.missions_sauvegardees ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS missions_sauvegardees_select ON public.missions_sauvegardees;
CREATE POLICY missions_sauvegardees_select ON public.missions_sauvegardees
  FOR SELECT TO authenticated USING (soignant_id = auth.uid());

DROP POLICY IF EXISTS missions_sauvegardees_insert ON public.missions_sauvegardees;
CREATE POLICY missions_sauvegardees_insert ON public.missions_sauvegardees
  FOR INSERT TO authenticated WITH CHECK (soignant_id = auth.uid());

DROP POLICY IF EXISTS missions_sauvegardees_delete ON public.missions_sauvegardees;
CREATE POLICY missions_sauvegardees_delete ON public.missions_sauvegardees
  FOR DELETE TO authenticated USING (soignant_id = auth.uid());

GRANT SELECT, INSERT, DELETE ON public.missions_sauvegardees TO authenticated;
GRANT ALL ON public.missions_sauvegardees TO service_role;

-- 2) Direction de swipe FAVORI (l'enum garde SUPER_LIKE pour l'historique)

ALTER TYPE public.swipe_direction ADD VALUE IF NOT EXISTS 'FAVORI';

-- 3) Garde-fou conflit de planning — helper partagé

CREATE OR REPLACE FUNCTION public.fn_conflit_planning_soignant(p_soignant_id uuid, p_mission_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $fn_cps$
DECLARE
  v_mission RECORD;
  v_conflit RECORD;
  v_adjacent RECORD;
BEGIN
  SELECT debut_le, fin_le INTO v_mission FROM missions WHERE id = p_mission_id;
  IF v_mission.debut_le IS NULL THEN
    RETURN jsonb_build_object('conflit', false);
  END IF;

  -- Conflit dur : chevauchement avec une mission déjà confirmée → blocage.
  SELECT m.intitule, m.debut_le, m.fin_le INTO v_conflit
  FROM missions m
  WHERE m.soignant_assigne_id = p_soignant_id
    AND m.statut IN ('ASSIGNEE', 'EN_COURS')
    AND m.debut_le < v_mission.fin_le
    AND m.fin_le > v_mission.debut_le
  LIMIT 1;

  IF v_conflit.intitule IS NOT NULL THEN
    RETURN jsonb_build_object(
      'conflit', true,
      'mission_conflit', v_conflit.intitule,
      'message', 'Tu es déjà confirmé(e) sur « ' || v_conflit.intitule || ' » du '
        || to_char(v_conflit.debut_le AT TIME ZONE 'Europe/Paris', 'DD/MM HH24hMI') || ' au '
        || to_char(v_conflit.fin_le AT TIME ZONE 'Europe/Paris', 'DD/MM HH24hMI')
        || ' — ce créneau chevauche cette mission.'
    );
  END IF;

  -- Adjacence serrée (< 60 min entre deux missions) : warning non bloquant.
  SELECT m.intitule INTO v_adjacent
  FROM missions m
  WHERE m.soignant_assigne_id = p_soignant_id
    AND m.statut IN ('ASSIGNEE', 'EN_COURS')
    AND (
      (m.fin_le <= v_mission.debut_le AND v_mission.debut_le - m.fin_le < interval '60 minutes')
      OR (v_mission.fin_le <= m.debut_le AND m.debut_le - v_mission.fin_le < interval '60 minutes')
    )
  LIMIT 1;

  IF v_adjacent.intitule IS NOT NULL THEN
    RETURN jsonb_build_object(
      'conflit', false,
      'warning', 'Attention : moins d''1 h de battement avec « ' || v_adjacent.intitule || ' ».'
    );
  END IF;

  RETURN jsonb_build_object('conflit', false);
END;
$fn_cps$;

GRANT EXECUTE ON FUNCTION public.fn_conflit_planning_soignant(uuid, uuid) TO authenticated, service_role;

-- Filet de sécurité sur TOUS les chemins de candidature soignant (swipe, liste,
-- accueil 1-tap, urgence). Les propositions étab (PROPOSEE) ne sont pas
-- concernées : l'intention vient de l'étab, le conflit se rejoue à l'acceptation.
CREATE OR REPLACE FUNCTION public.fn_trg_candidature_conflit_planning()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $fn_tccp$
DECLARE
  v_check jsonb;
BEGIN
  IF NEW.statut IN ('EN_ATTENTE', 'EN_ATTENTE_VALIDATION_ETAB') THEN
    v_check := fn_conflit_planning_soignant(NEW.soignant_id, NEW.mission_id);
    IF (v_check->>'conflit')::boolean THEN
      RAISE EXCEPTION '%', (v_check->>'message');
    END IF;
  END IF;
  RETURN NEW;
END;
$fn_tccp$;

DROP TRIGGER IF EXISTS trg_candidature_conflit_planning ON public.candidatures;
CREATE TRIGGER trg_candidature_conflit_planning
  BEFORE INSERT ON public.candidatures
  FOR EACH ROW EXECUTE FUNCTION public.fn_trg_candidature_conflit_planning();

-- 4) fn_enregistrer_swipe v2 : FAVORI (sauvegarde) + garde-fous candidature

CREATE OR REPLACE FUNCTION public.fn_enregistrer_swipe(p_mission_id uuid, p_direction text, p_choix_contrat text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_soignant_id uuid := auth.uid();
  v_direction swipe_direction;
  v_swipe_id uuid;
  v_mission RECORD;
  v_soignant RECORD;
  v_candidature_id uuid;
  v_choix_contrat text;
  v_choix_effectif text;
  v_rcp_valide boolean;
  v_planning jsonb;
  v_warning text;
BEGIN
  IF v_soignant_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required');
  END IF;

  -- D1 : ⭐ = favoris. SUPER_LIKE accepté en rétro-compat (anciens bundles) et
  -- traité comme FAVORI — plus aucun chemin ne crée de candidature prioritaire.
  IF p_direction = 'SUPER_LIKE' THEN
    p_direction := 'FAVORI';
  END IF;

  IF p_direction NOT IN ('LIKE', 'DISLIKE', 'FAVORI') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'direction_invalide');
  END IF;

  v_direction := p_direction::swipe_direction;

  IF v_direction = 'LIKE' THEN
    SELECT * INTO v_mission FROM missions WHERE id = p_mission_id;
    SELECT * INTO v_soignant FROM soignants WHERE id = v_soignant_id;

    IF v_mission.id IS NOT NULL AND v_soignant.id IS NOT NULL
       AND v_mission.statut = 'OUVERTE'
       AND fn_soignant_compatible_mission(
             v_soignant.profession, v_soignant.specialite_medicale,
             v_mission.profession_requise, v_mission.specialite_medicale_requise,
             v_mission.accepte_non_specialises)
       AND NOT fn_est_exclu(v_soignant_id, v_mission.etablissement_id)
       AND NOT EXISTS (SELECT 1 FROM candidatures WHERE mission_id = p_mission_id AND soignant_id = v_soignant_id)
    THEN
      IF v_mission.type_contrat_recherche = 'SALARIE'
         AND COALESCE(v_soignant.type_exercice, 'SALARIE') NOT IN ('SALARIE', 'MIXTE') THEN
        RETURN jsonb_build_object('ok', false, 'error', 'Cette mission est réservée aux salariés.');
      END IF;
      IF v_mission.type_contrat_recherche = 'LIBERAL'
         AND COALESCE(v_soignant.type_exercice, 'SALARIE') NOT IN ('LIBERAL', 'MIXTE') THEN
        RETURN jsonb_build_object('ok', false, 'error', 'Cette mission est réservée aux libéraux.');
      END IF;

      -- D2 garde-fou 2 : conflit de planning AVANT tout (message propre, pas
      -- d'exception). Le trigger sur candidatures reste le filet de sécurité.
      v_planning := fn_conflit_planning_soignant(v_soignant_id, p_mission_id);
      IF (v_planning->>'conflit')::boolean THEN
        RETURN jsonb_build_object('ok', false, 'error', v_planning->>'message', 'conflit_planning', true);
      END IF;
      v_warning := v_planning->>'warning';

      IF v_soignant.type_exercice = 'MIXTE' AND v_mission.type_contrat_recherche = 'TOUS' THEN
        v_choix_effectif := COALESCE(p_choix_contrat, v_soignant.preference_contrat_mixte);
        IF v_choix_effectif IS NULL OR v_choix_effectif NOT IN ('SALARIE', 'LIBERAL') THEN
          RETURN jsonb_build_object(
            'ok', false,
            'choix_requis', true,
            'error', 'Veuillez choisir votre mode de contrat.',
            'options', jsonb_build_array(
              jsonb_build_object('value', 'SALARIE', 'label', 'Salarié (CDD)'),
              jsonb_build_object('value', 'LIBERAL', 'label', 'Libéral (note d''honoraires)')));
        END IF;
      END IF;

      IF v_mission.type_contrat_recherche = 'SALARIE' THEN v_choix_contrat := 'SALARIE';
      ELSIF v_mission.type_contrat_recherche = 'LIBERAL' THEN v_choix_contrat := 'LIBERAL';
      ELSIF v_soignant.type_exercice = 'MIXTE' THEN v_choix_contrat := v_choix_effectif;
      ELSE v_choix_contrat := COALESCE(v_soignant.type_exercice, 'SALARIE');
      END IF;

      IF v_choix_contrat = 'LIBERAL' THEN
        SELECT EXISTS(SELECT 1 FROM documents_soignants
          WHERE soignant_id = v_soignant_id AND type_document = 'RCP_ASSURANCE'
            AND statut_verification = 'VERIFIE' AND supprime_le IS NULL
            AND (valide_jusqua IS NULL OR valide_jusqua > CURRENT_DATE)) INTO v_rcp_valide;
        IF NOT v_rcp_valide THEN
          RETURN jsonb_build_object('ok', false, 'error',
            'Assurance RCP manquante ou expirée — obligatoire pour candidater en libéral. Téléversez-la dans vos documents (ou choisissez salarié si la mission le permet).');
        END IF;
      END IF;
    END IF;
  END IF;

  INSERT INTO public.swipes (soignant_id, mission_id, direction)
    VALUES (v_soignant_id, p_mission_id, v_direction)
    ON CONFLICT (soignant_id, mission_id) DO NOTHING
    RETURNING id INTO v_swipe_id;

  IF v_swipe_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'mission_deja_swipee');
  END IF;

  -- D1 : sauvegarde de la mission (favoris illimités, aucune candidature)
  IF v_direction = 'FAVORI' THEN
    INSERT INTO public.missions_sauvegardees (soignant_id, mission_id)
    VALUES (v_soignant_id, p_mission_id)
    ON CONFLICT (soignant_id, mission_id) DO NOTHING;

    RETURN jsonb_build_object('ok', true, 'swipe_id', v_swipe_id, 'direction', 'FAVORI', 'sauvegardee', true);
  END IF;

  IF v_direction = 'LIKE' AND v_choix_contrat IS NOT NULL THEN
    INSERT INTO candidatures (mission_id, soignant_id, message, statut, type_contrat_choisi)
    VALUES (p_mission_id, v_soignant_id, NULL, 'EN_ATTENTE', v_choix_contrat)
    RETURNING id INTO v_candidature_id;

    INSERT INTO notifications (destinataire_id, type_destinataire, type, titre, corps, lien)
    VALUES (
      v_mission.etablissement_id, 'ETABLISSEMENT', 'CANDIDATURE_RECUE',
      '📋 Nouvelle candidature reçue',
      COALESCE(v_soignant.prenom, 'Un soignant') || ' a postulé à votre mission « ' || v_mission.intitule || ' ».',
      '/etablissement/missions/' || p_mission_id
    );
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'swipe_id', v_swipe_id,
    'direction', p_direction,
    'candidature_id', v_candidature_id,
    'choix_contrat', v_choix_contrat,
    'warning', v_warning
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_enregistrer_swipe(uuid, text, text) TO authenticated, service_role;

-- 5) D2 garde-fou 4 : auto-expiration des candidatures sans réponse
--    quand la mission démarre — jamais de candidature zombie.

CREATE OR REPLACE FUNCTION public.fn_expirer_candidatures_missions_demarrees()
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $fn_ecmd$
DECLARE
  v_nb integer;
BEGIN
  UPDATE candidatures c
  SET statut = 'EXPIREE'
  FROM missions m
  WHERE m.id = c.mission_id
    AND c.statut IN ('EN_ATTENTE', 'EN_ATTENTE_VALIDATION_ETAB')
    AND m.debut_le <= now();
  GET DIAGNOSTICS v_nb = ROW_COUNT;
  RETURN v_nb;
END;
$fn_ecmd$;

REVOKE EXECUTE ON FUNCTION public.fn_expirer_candidatures_missions_demarrees() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_expirer_candidatures_missions_demarrees() TO service_role;

SELECT cron.schedule(
  'expirer-candidatures-demarrees',
  '*/20 * * * *',
  'SELECT public.fn_expirer_candidatures_missions_demarrees()'
);

-- 6) D1 anti-fuite du favori : push « ta mission sauvegardée démarre bientôt »

ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_type_check;
ALTER TABLE public.notifications ADD CONSTRAINT notifications_type_check CHECK (type = ANY (ARRAY[
  'CANDIDATURE_ACCEPTEE','CANDIDATURE_REFUSEE','CANDIDATURE_PROPOSEE','CANDIDATURE_RECUE',
  'MISSION_ACCEPTEE','MISSION_ANNULEE','MISSION_TERMINEE','MISSION_URGENTE','MISSION_NON_POURVUE',
  'MISSION_ASSIGNEE','MISSION_A_POURVOIR','CONTRAT_A_SIGNER','CONTRAT_SIGNE','FACTURE_EMISE',
  'FACTURE_PAYEE','DOCUMENT_EXPIRANT','RAPPEL_DOCUMENTS','DOCUMENT_VERIFIE','DOCUMENT_REJETE',
  'MESSAGE_RECU','MESSAGE_ADMIN','POINTAGE_ARRIVEE','POINTAGE_DEPART','EVALUATION_RECUE',
  'PARRAINAGE','CREDIT_PARRAINAGE','PARRAINAGE_PRIME_VERSEE','RAPPEL_MISSION','RAPPEL_CANDIDATURES',
  'POOL_URGENCE','POOL_URGENCE_ACCEPTATION','SYSTEM','LITIGE_OUVERT','LITIGE_REPONSE','LITIGE_RESOLU',
  'LITIGE_MEDIATION','LITIGE_RESOLU_AJUSTE','LITIGE_ESCALADE_ADMIN','LITIGE_MEDIATION_PRIORITAIRE',
  'LITIGE_RAPPEL_J1','LITIGE_RAPPEL_J3','LITIGE_RAPPEL_J5','CHORUS_DEPOSEE','CHORUS_MISE_A_DISPOSITION',
  'CHORUS_PAIEMENT_EN_COURS','CHORUS_PAIEMENT_COMPTABILISE','CHORUS_REJETEE','FAVORI_NOUVELLE_MISSION',
  'AVOIR_EMIS','COMMISSION_AJUSTEE','REMBOURSEMENT_MANUEL_A_FAIRE','REMBOURSEMENT_CONFIRME',
  'MATCHING_SUPER_LIKE','FAVORI_MISSION_EXPIRE'
]::text[]));

CREATE OR REPLACE FUNCTION public.fn_notifier_favoris_expirants()
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $fn_nfe$
DECLARE
  v_nb integer := 0;
  r RECORD;
BEGIN
  FOR r IN
    SELECT ms.id AS sauvegarde_id, ms.soignant_id, m.id AS mission_id, m.intitule,
           to_char(m.debut_le AT TIME ZONE 'Europe/Paris', 'DD/MM à HH24hMI') AS debut_txt
    FROM missions_sauvegardees ms
    JOIN missions m ON m.id = ms.mission_id
    WHERE ms.notifie_expiration = false
      AND m.statut = 'OUVERTE'
      AND m.debut_le > now()
      AND m.debut_le <= now() + interval '48 hours'
      AND NOT EXISTS (
        SELECT 1 FROM candidatures c
        WHERE c.mission_id = m.id AND c.soignant_id = ms.soignant_id
      )
  LOOP
    INSERT INTO notifications (destinataire_id, type_destinataire, type, titre, corps, lien)
    VALUES (
      r.soignant_id, 'SOIGNANT', 'FAVORI_MISSION_EXPIRE',
      '⭐ Ta mission sauvegardée démarre bientôt',
      '« ' || r.intitule || ' » démarre le ' || r.debut_txt || ' — postule avant qu''elle ne parte.',
      '/soignant/missions/' || r.mission_id
    );
    UPDATE missions_sauvegardees SET notifie_expiration = true WHERE id = r.sauvegarde_id;
    v_nb := v_nb + 1;
  END LOOP;
  RETURN v_nb;
END;
$fn_nfe$;

REVOKE EXECUTE ON FUNCTION public.fn_notifier_favoris_expirants() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_notifier_favoris_expirants() TO service_role;

SELECT cron.schedule(
  'notifier-favoris-expirants',
  '47 * * * *',
  'SELECT public.fn_notifier_favoris_expirants()'
);
