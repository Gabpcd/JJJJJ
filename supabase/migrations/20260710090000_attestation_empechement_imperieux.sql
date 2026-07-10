-- Mini-PR ARRET_MALADIE → attestation d'empêchement impérieux.
-- Décision validée (Gabrielle, 09/07/2026), spec : docs/MINI_PR_ARRET_MALADIE.md,
-- conformité : docs/CONFORMITE.md §1.4 — Jolene ne stocke AUCUNE donnée de
-- santé (hors HDS, art. L1111-8 CSP). Le certificat médical (upload +
-- verify-document) est remplacé par une attestation sur l'honneur générique
-- « empêchement impérieux » : dates d'indisponibilité + flag, ni motif ni
-- catégorie (le motif santé serait une donnée RGPD art. 9), aucun document.
--
-- État prod au moment de la migration : 0 document ARRET_MALADIE stocké.

-- ── 1. CHECK journaux_audit : nouvelle action (pattern CLAUDE.md — vérifier le
--       CHECK avant tout nouveau type, sinon échec silencieux).
DO $do$
DECLARE v_def text;
BEGIN
  SELECT pg_get_constraintdef(oid) INTO v_def
    FROM pg_constraint WHERE conname = 'journaux_audit_action_check';
  IF v_def IS NULL THEN
    RAISE NOTICE 'journaux_audit_action_check absent — rien à étendre';
    RETURN;
  END IF;
  IF v_def LIKE '%ANNULATION_EMPECHEMENT_IMPERIEUX%' THEN
    RETURN;
  END IF;
  v_def := replace(v_def, 'ARRAY[', 'ARRAY[''ANNULATION_EMPECHEMENT_IMPERIEUX''::text, ');
  EXECUTE 'ALTER TABLE public.journaux_audit DROP CONSTRAINT journaux_audit_action_check';
  EXECUTE 'ALTER TABLE public.journaux_audit ADD CONSTRAINT journaux_audit_action_check ' || v_def;
END;
$do$;

-- ── 2. Compteur anti-abus paramétrable ────────────────────────────────────────
INSERT INTO parametres_systeme (cle, valeur, label, description, unite, categorie, val_min, val_max, cablee)
VALUES ('annulations_justifiees_max_12m', 2,
  'Empêchements impérieux — max / 12 mois',
  'Nombre d''annulations justifiées par attestation sur l''honneur tolérées sur 12 mois glissants sans pénalité de score. Au-delà : pénalité malgré l''attestation + passage en revue admin.',
  'annulations', 'GENERAL', 0, 20, true)
ON CONFLICT (cle) DO NOTHING;

-- ── 3. Nouvelle RPC : déclaration structurée, zéro donnée de santé ────────────
-- Reprend la mécanique LIVE de fn_declarer_arret_maladie (flag mission,
-- notifications, remplacement garanti) SANS certificat ni checklist CPAM.
-- Les colonnes missions.est_arret_maladie / arret_maladie_declare_le gardent
-- leur nom historique : elles signifient désormais « empêchement impérieux
-- déclaré » (un booléen d'indisponibilité, pas une donnée de santé).
CREATE OR REPLACE FUNCTION public.fn_declarer_empechement_imperieux(
  p_mission_id uuid, p_indispo_debut date, p_indispo_fin date)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
DECLARE
  v_m RECORD;
  v_nb int := 0;
  v_max int := GREATEST(0, fn_param_num('annulations_justifiees_max_12m', 2)::int);
  v_n12 int;
  v_depasse boolean;
  v_admin uuid;
BEGIN
  SELECT * INTO v_m FROM missions WHERE id = p_mission_id AND soignant_assigne_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Mission introuvable'); END IF;
  IF v_m.statut NOT IN ('ASSIGNEE', 'EN_COURS') THEN
    RETURN jsonb_build_object('error', 'Cette mission n''est plus active.');
  END IF;
  IF v_m.est_arret_maladie THEN
    RETURN jsonb_build_object('error', 'Un empêchement est déjà déclaré sur cette mission.');
  END IF;
  IF p_indispo_debut IS NULL OR p_indispo_fin IS NULL OR p_indispo_fin < p_indispo_debut THEN
    RETURN jsonb_build_object('error', 'Dates d''indisponibilité invalides.');
  END IF;
  IF p_indispo_fin - p_indispo_debut > 90 THEN
    RETURN jsonb_build_object('error', 'Période d''indisponibilité trop longue (90 jours max).');
  END IF;

  -- Anti-abus : N attestations max / 12 mois glissants (param).
  SELECT count(*) INTO v_n12 FROM journaux_audit
   WHERE acteur_id = auth.uid()
     AND action = 'ANNULATION_EMPECHEMENT_IMPERIEUX'
     AND cree_le > NOW() - INTERVAL '12 months';
  v_depasse := (v_n12 + 1) > v_max;

  UPDATE missions SET est_arret_maladie = TRUE, arret_maladie_declare_le = NOW(), modifie_le = NOW()
   WHERE id = p_mission_id;

  -- Trace horodatée : dates + sur l'honneur. JAMAIS de motif/catégorie (RGPD art. 9).
  PERFORM fn_ecrire_audit_safe(
    auth.uid(), 'SOIGNANT', 'ANNULATION_EMPECHEMENT_IMPERIEUX', 'mission', p_mission_id, NULL,
    jsonb_build_object('sur_honneur', true,
                       'indispo_debut', p_indispo_debut, 'indispo_fin', p_indispo_fin,
                       'n_12_mois', v_n12 + 1, 'max_12_mois', v_max, 'depassement', v_depasse));

  -- Au-delà du compteur : la pénalité s'applique malgré l'attestation
  -- (même barème que l'annulation tardive) + passage en revue admin.
  IF v_depasse THEN
    UPDATE soignants SET
      total_missions_annulees = COALESCE(total_missions_annulees, 0) + 1,
      score_fiabilite = GREATEST(0, COALESCE(score_fiabilite, 50) - 8),
      modifie_le = NOW()
    WHERE id = auth.uid();

    FOR v_admin IN SELECT user_id FROM equipe_admin WHERE actif AND user_id IS NOT NULL
    LOOP
      INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
      VALUES (v_admin, 'SYSTEM', 'Empêchements répétés — revue soignant ⚠️',
        'Un soignant vient de déclarer son ' || (v_n12 + 1) || 'e empêchement impérieux sur 12 mois (max toléré : ' ||
        v_max || '). Pénalité de score appliquée. Détails dans le journal d''audit (action ANNULATION_EMPECHEMENT_IMPERIEUX).',
        '/admin/audit', 'ADMIN');
    END LOOP;
  END IF;

  -- Étab : wording générique, aucune mention médicale.
  INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
  VALUES (v_m.etablissement_id, 'SYSTEM', 'Empêchement impérieux déclaré ⚠️',
    'Le soignant assigné à "' || fn_html_escape(v_m.intitule) || '" atteste sur l''honneur d''un empêchement impérieux ' ||
    'et sera indisponible du ' || TO_CHAR(p_indispo_debut, 'DD/MM') || ' au ' || TO_CHAR(p_indispo_fin, 'DD/MM') || '.' ||
    CASE WHEN v_m.garantie_remplacement
      THEN ' Garantie remplacement : le pool d''urgence est alerté automatiquement.'
      ELSE ' Vous pouvez alerter le pool d''urgence depuis la mission.' END,
    '/etablissement/missions/' || v_m.id, 'ETABLISSEMENT');

  INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
  VALUES (auth.uid(), 'SYSTEM', 'Empêchement enregistré',
    'Votre attestation sur l''honneur est enregistrée — aucun justificatif à fournir.' ||
    CASE WHEN v_depasse
      THEN ' Attention : au-delà de ' || v_max || ' empêchements sur 12 mois, la pénalité de score s''applique (c''est le cas ici).'
      ELSE ' Aucune pénalité de score.' END ||
    ' Une fausse déclaration engage votre responsabilité (CGU).',
    '/soignant/missions/' || v_m.id, 'SOIGNANT');

  -- Remplacement garanti : mécanique inchangée (reprise de la définition LIVE).
  IF v_m.garantie_remplacement AND v_m.fin_le > NOW() + INTERVAL '1 hour' THEN
    UPDATE missions SET statut = 'OUVERTE', soignant_assigne_id = NULL,
        mode_attribution = 'PREMIER_ARRIVE', est_urgente = TRUE, niveau_urgence = 3,
        presence_confirmee_le = NULL,
        debut_le = GREATEST(debut_le, NOW() + INTERVAL '15 minutes'),
        modifie_le = NOW()
     WHERE id = p_mission_id;
    v_nb := fn_diffuser_pool_urgence(p_mission_id);
  END IF;

  RETURN jsonb_build_object('success', TRUE, 'pool_alerte', v_nb,
                            'depassement', v_depasse, 'n_12_mois', v_n12 + 1, 'max_12_mois', v_max);
END;
$fn$;

-- ── 4. Ancienne RPC : gap verrouillé (rejet explicite, jamais de comportement
--       silencieux — les bundles en cache peuvent encore l'appeler).
CREATE OR REPLACE FUNCTION public.fn_declarer_arret_maladie(p_mission_id uuid, p_message text DEFAULT NULL::text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
BEGIN
  RETURN jsonb_build_object('error',
    'La déclaration d''arrêt maladie est remplacée par l''attestation d''empêchement impérieux — aucune donnée de santé n''est collectée (docs/CONFORMITE.md §1.4). Rechargez l''application pour accéder au nouveau formulaire.');
END;
$fn$;

-- ── 5. Verrou documents de santé porté à 3/3 ──────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_trg_bloquer_documents_sante()
RETURNS trigger LANGUAGE plpgsql
AS $fn$
BEGIN
  IF NEW.type_document::text IN ('VACCINATIONS', 'MEDECINE_TRAVAIL', 'ARRET_MALADIE') THEN
    RAISE EXCEPTION 'Document de santé interdit au stockage (type %). Jolene ne stocke aucune donnée de santé (hors HDS, L1111-8 CSP). Remplacement : attestation sur l''honneur (empêchement impérieux) + vérification établissement. Cf. docs/CONFORMITE.md §1.', NEW.type_document
      USING ERRCODE = 'P0001';
  END IF;
  RETURN NEW;
END;
$fn$;
