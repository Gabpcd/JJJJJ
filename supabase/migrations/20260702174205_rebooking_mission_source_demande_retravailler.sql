-- 7e-2 (Lot 7 v2 F2) — re-booking traçable + demande soignante.
--
-- 1) missions.mission_source : provenance de la mission (North Star anti-fuite
--    = % de missions issues d'un re-book in-app). Nullable : les missions
--    créées au formulaire restent NULL (défaut historique). Les missions de
--    REMPLACEMENT restent traçables via remplacement_de_mission_id.
-- 2) fn_rebooker_soignant : pose mission_source = 'REBOOK' (base : définition
--    live, inchangée par ailleurs).
-- 3) fn_demander_a_retravailler : « Redemander à travailler ici » côté
--    soignante — notification à l'établissement (mission TERMINEE commune
--    requise, dédup 7 jours).

ALTER TABLE public.missions
  ADD COLUMN IF NOT EXISTS mission_source text
    CONSTRAINT missions_mission_source_check
    CHECK (mission_source IN ('SWIPE', 'CANDIDATURE', 'REBOOK', 'PROPOSITION_DIRECTE', 'REMPLACEMENT'));

CREATE OR REPLACE FUNCTION public.fn_rebooker_soignant(p_soignant_id uuid, p_mission_modele_id uuid, p_debut timestamp with time zone, p_fin timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_m RECORD; v_s RECORD; v_new_id uuid;
BEGIN
  SELECT * INTO v_m FROM missions WHERE id = p_mission_modele_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Mission modèle introuvable'); END IF;
  IF v_m.etablissement_id != mon_etablissement_id() AND NOT est_admin() THEN
    RETURN jsonb_build_object('error', 'Non autorisé');
  END IF;
  IF p_debut IS NULL OR p_fin IS NULL OR p_fin <= p_debut OR p_debut < NOW() THEN
    RETURN jsonb_build_object('error', 'Dates invalides (le début doit être dans le futur).');
  END IF;
  SELECT * INTO v_s FROM soignants WHERE id = p_soignant_id AND supprime_le IS NULL;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Soignant introuvable'); END IF;
  IF v_s.profession != v_m.profession_requise THEN
    RETURN jsonb_build_object('error', 'La profession du soignant ne correspond pas à la mission modèle.');
  END IF;
  IF fn_est_exclu(p_soignant_id, v_m.etablissement_id) THEN
    RETURN jsonb_build_object('error', 'Ce soignant est dans votre liste d''exclusions.');
  END IF;

  INSERT INTO missions (
    etablissement_id, intitule, description, service,
    profession_requise, specialite_medicale_requise, accepte_non_specialises,
    debut_le, fin_le, duree_heures, taux_horaire_base,
    type_contrat_recherche, statut, mode_attribution, est_urgente, garantie_remplacement,
    mission_source
  ) VALUES (
    v_m.etablissement_id, v_m.intitule, v_m.description, v_m.service,
    v_m.profession_requise, v_m.specialite_medicale_requise, v_m.accepte_non_specialises,
    p_debut, p_fin, ROUND(EXTRACT(EPOCH FROM (p_fin - p_debut)) / 3600.0, 2), v_m.taux_horaire_base,
    v_m.type_contrat_recherche, 'OUVERTE', 'CANDIDATURE', FALSE, COALESCE(v_m.garantie_remplacement, FALSE),
    'REBOOK'
  ) RETURNING id INTO v_new_id;

  INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
  VALUES (p_soignant_id, 'CANDIDATURE_PROPOSEE', 'Un établissement veut retravailler avec vous ⭐',
    fn_html_escape(v_m.intitule) || ' du ' || TO_CHAR(p_debut AT TIME ZONE 'Europe/Paris', 'DD/MM à HH24:MI') ||
    ' au ' || TO_CHAR(p_fin AT TIME ZONE 'Europe/Paris', 'DD/MM à HH24:MI') ||
    ' à ' || COALESCE(v_m.taux_horaire_base::text, '?') || ' €/h — vous êtes leur premier choix, postulez en 1 clic.',
    '/soignant/missions/' || v_new_id, 'SOIGNANT');

  RETURN jsonb_build_object('success', TRUE, 'mission_id', v_new_id);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_rebooker_soignant(uuid, uuid, timestamptz, timestamptz) TO authenticated;

-- « Redemander à travailler ici » — l'initiative devient possible côté soignante.
CREATE OR REPLACE FUNCTION public.fn_demander_a_retravailler(p_etablissement_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_uid uuid := auth.uid();
  v_s RECORD;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('error', 'Non authentifié'); END IF;
  SELECT prenom, nom, profession INTO v_s FROM soignants WHERE id = v_uid AND supprime_le IS NULL;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Profil soignant introuvable'); END IF;

  -- Légitimité : au moins une mission TERMINEE ensemble (on redemande à
  -- travailler quelque part où on a déjà travaillé).
  IF NOT EXISTS (
    SELECT 1 FROM missions m
    WHERE m.etablissement_id = p_etablissement_id
      AND m.soignant_assigne_id = v_uid AND m.statut = 'TERMINEE'
  ) THEN
    RETURN jsonb_build_object('error', 'Disponible après une première mission terminée avec cet établissement.');
  END IF;

  IF fn_est_exclu(v_uid, p_etablissement_id) THEN
    RETURN jsonb_build_object('error', 'Demande impossible auprès de cet établissement.');
  END IF;

  -- Dédup 7 jours : une seule sollicitation par étab par semaine.
  IF EXISTS (
    SELECT 1 FROM notifications n
    WHERE n.destinataire_id = p_etablissement_id AND n.type = 'SYSTEM'
      AND n.lien = '/etablissement/soignants/' || v_uid
      AND n.titre LIKE '%veut retravailler%'
      AND n.cree_le > NOW() - INTERVAL '7 days'
  ) THEN
    RETURN jsonb_build_object('error', 'Demande déjà envoyée cette semaine — l''établissement a été prévenu.');
  END IF;

  INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
  VALUES (p_etablissement_id, 'SYSTEM',
    v_s.prenom || ' ' || v_s.nom || ' veut retravailler avec vous ⭐',
    'Vous avez déjà travaillé ensemble. Reproposez-lui une mission en 2 clics depuis son profil.',
    '/etablissement/soignants/' || v_uid, 'ETABLISSEMENT');

  RETURN jsonb_build_object('success', TRUE);
END;
$fn$;

GRANT EXECUTE ON FUNCTION public.fn_demander_a_retravailler(uuid) TO authenticated;
