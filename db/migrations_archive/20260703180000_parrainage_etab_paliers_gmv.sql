-- Parrainage établissement — paliers GMV (remplace le forfait unique 50 € à 100 €
-- de commission). GO produit Gabrielle 03/07.
--
-- Modèle : deux paliers déclenchés par la commission ENCAISSÉE (facture PAYEE),
-- mesurés sur le GMV encaissé du filleul (SUM total_brut des missions dont la
-- facture commission est PAYEE) :
--   - Palier 1 : 500 € de GMV → 50 € de crédit (parrain ET filleul)
--   - Palier 2 : 2 000 € de GMV → 150 € de crédit (parrain ET filleul)
-- Montants et seuils PARAMÉTRABLES via parametres_systeme (admin).
--
-- Redéfini depuis la définition LIVE de fn_trg_valider_parrainage_etab_commission
-- (garde-fou 9.0). Logique notifications / anomalie / audit préservée.
--
-- ⚠️ Logique d'argent (crédits commission) — PR draft, à valider par Gabrielle
-- avant merge (règles ①②).

-- ── 1. Paramètres (paliers GMV en centimes + récompenses en euros) ─────────
INSERT INTO parametres_systeme (cle, valeur, label, description, unite, categorie, val_min, val_max, cablee)
VALUES
  ('parrainage_etab_palier1_gmv_cents', 50000,
   'Parrainage étab — palier 1 (GMV)',
   'GMV encaissé du filleul (centimes) déclenchant le crédit palier 1.',
   'cents', 'FINANCE', 0, 100000000, true),
  ('parrainage_etab_palier1_recompense_eur', 50,
   'Parrainage étab — récompense palier 1',
   'Crédit commission (€) accordé au parrain ET au filleul au palier 1.',
   'euros', 'FINANCE', 0, 100000, true),
  ('parrainage_etab_palier2_gmv_cents', 200000,
   'Parrainage étab — palier 2 (GMV)',
   'GMV encaissé du filleul (centimes) déclenchant le crédit palier 2.',
   'cents', 'FINANCE', 0, 100000000, true),
  ('parrainage_etab_palier2_recompense_eur', 150,
   'Parrainage étab — récompense palier 2',
   'Crédit commission (€) accordé au parrain ET au filleul au palier 2.',
   'euros', 'FINANCE', 0, 100000, true)
ON CONFLICT (cle) DO NOTHING;

-- ── 2. Suivi des paliers atteints ──────────────────────────────────────────
ALTER TABLE parrainages_etablissements
  ADD COLUMN IF NOT EXISTS palier1_atteint_le timestamptz,
  ADD COLUMN IF NOT EXISTS palier2_atteint_le timestamptz;

-- Rétro-compat : les parrainages déjà VALIDATED sous l'ancien modèle (forfait
-- 50 € à 100 € commission) sont réputés avoir atteint le palier 1 (crédit déjà
-- versé) — on ne re-crédite pas.
UPDATE parrainages_etablissements
SET palier1_atteint_le = COALESCE(valide_le, mis_a_jour_le, now())
WHERE statut = 'VALIDATED' AND palier1_atteint_le IS NULL;

-- ── 3. Helper : créditer un palier (parrain + filleul) + notifs + audit ────
CREATE OR REPLACE FUNCTION public.fn_parrainage_etab_crediter_palier(
  p_parrainage_id uuid,
  p_montant_eur integer,
  p_palier integer,
  p_gmv_cents numeric
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $palier$
DECLARE
  v_p RECORD;
  v_filleul_nom text;
  v_parrain_nom text;
  v_credit_parrain uuid;
  v_credit_filleul uuid;
BEGIN
  SELECT * INTO v_p FROM parrainages_etablissements WHERE id = p_parrainage_id;
  IF v_p.id IS NULL THEN RETURN; END IF;

  SELECT nom INTO v_filleul_nom FROM etablissements WHERE id = v_p.filleul_etab_id;
  SELECT nom INTO v_parrain_nom FROM etablissements WHERE id = v_p.parrain_etab_id;

  INSERT INTO credits_etablissement (etablissement_id, montant_eur, motif, parrainage_id)
  VALUES (v_p.parrain_etab_id, p_montant_eur, 'PARRAINAGE', v_p.id)
  RETURNING id INTO v_credit_parrain;

  INSERT INTO credits_etablissement (etablissement_id, montant_eur, motif, parrainage_id)
  VALUES (v_p.filleul_etab_id, p_montant_eur, 'PARRAINAGE', v_p.id)
  RETURNING id INTO v_credit_filleul;

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_p.parrain_etab_id, p_type_acteur := 'SYSTEME',
    p_action := 'CREDIT_PARRAINAGE_CREE', p_type_ressource := 'parrainage_etab',
    p_id_ressource := v_p.id,
    p_details := jsonb_build_object(
      'palier', p_palier, 'montant_eur', p_montant_eur,
      'credit_parrain_id', v_credit_parrain, 'credit_filleul_id', v_credit_filleul,
      'gmv_cents', p_gmv_cents, 'filleul_etab_id', v_p.filleul_etab_id)
  );

  INSERT INTO notifications (destinataire_id, type_destinataire, type, titre, corps, lien)
  VALUES (
    v_p.parrain_etab_id, 'ETABLISSEMENT', 'CREDIT_PARRAINAGE',
    '🎉 +' || p_montant_eur || '€ de crédit Jolene !',
    'Votre filleul ' || COALESCE(v_filleul_nom, 'établissement') || ' a franchi le palier '
      || p_palier || '. ' || p_montant_eur || '€ de crédit ont été ajoutés et seront déduits de votre prochaine facture commission.',
    '/etablissement/parrainage'
  );

  INSERT INTO notifications (destinataire_id, type_destinataire, type, titre, corps, lien)
  VALUES (
    v_p.filleul_etab_id, 'ETABLISSEMENT', 'CREDIT_PARRAINAGE',
    '🎉 +' || p_montant_eur || '€ de crédit parrainage !',
    'Grâce au parrainage de ' || COALESCE(v_parrain_nom, 'votre parrain') || ', vous avez franchi le palier '
      || p_palier || ' : ' || p_montant_eur || '€ de crédit ont été ajoutés et seront déduits de votre prochaine facture commission.',
    '/etablissement/parrainage'
  );
END;
$palier$;

REVOKE EXECUTE ON FUNCTION public.fn_parrainage_etab_crediter_palier(uuid, integer, integer, numeric) FROM PUBLIC, anon, authenticated;

-- ── 4. Trigger de validation (redéfini depuis le live, paliers GMV) ────────
CREATE OR REPLACE FUNCTION public.fn_trg_valider_parrainage_etab_commission()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_parrainage RECORD;
  v_gmv_cents NUMERIC;
  v_p1_gmv INTEGER := public.fn_param_num('parrainage_etab_palier1_gmv_cents', 50000)::int;
  v_p1_eur INTEGER := public.fn_param_num('parrainage_etab_palier1_recompense_eur', 50)::int;
  v_p2_gmv INTEGER := public.fn_param_num('parrainage_etab_palier2_gmv_cents', 200000)::int;
  v_p2_eur INTEGER := public.fn_param_num('parrainage_etab_palier2_recompense_eur', 150)::int;
  v_nb_validations_mois INT;
BEGIN
  IF NEW.statut <> 'PAYEE' THEN RETURN NEW; END IF;
  IF TG_OP = 'UPDATE' AND COALESCE(OLD.statut, '') = 'PAYEE' THEN RETURN NEW; END IF;
  IF NEW.etablissement_id IS NULL THEN RETURN NEW; END IF;

  -- Parrainage du filleul encore éligible à un palier (palier 2 non atteint).
  SELECT * INTO v_parrainage FROM parrainages_etablissements
  WHERE filleul_etab_id = NEW.etablissement_id
    AND statut IN ('PENDING', 'VALIDATED')
    AND palier2_atteint_le IS NULL
  LIMIT 1;
  IF v_parrainage.id IS NULL THEN RETURN NEW; END IF;

  -- GMV encaissé du filleul = SUM total_brut des missions dont la facture
  -- commission est PAYEE (× 100 pour comparer aux seuils en centimes).
  SELECT COALESCE(SUM(m.total_brut), 0) * 100 INTO v_gmv_cents
  FROM missions m
  JOIN factures f ON f.id = m.facture_id
  WHERE m.etablissement_id = NEW.etablissement_id
    AND f.statut = 'PAYEE';

  -- Palier 1 : valide le parrainage + crédite (une seule fois).
  IF v_gmv_cents >= v_p1_gmv AND v_parrainage.palier1_atteint_le IS NULL THEN
    UPDATE parrainages_etablissements
    SET statut = 'VALIDATED', valide_le = COALESCE(valide_le, NOW()),
        palier1_atteint_le = NOW(), mis_a_jour_le = NOW()
    WHERE id = v_parrainage.id;

    PERFORM public.fn_parrainage_etab_crediter_palier(v_parrainage.id, v_p1_eur, 1, v_gmv_cents);

    PERFORM public.fn_ecrire_audit_safe(
      p_acteur_id := v_parrainage.filleul_etab_id, p_type_acteur := 'SYSTEME',
      p_action := 'PARRAINAGE_ETAB_VALIDE', p_type_ressource := 'parrainage_etab',
      p_id_ressource := v_parrainage.id,
      p_details := jsonb_build_object('parrain_etab_id', v_parrainage.parrain_etab_id,
                                      'facture_id', NEW.id, 'palier', 1, 'gmv_cents', v_gmv_cents)
    );

    -- Anti-abus : > 5 validations dans le mois pour un même parrain.
    SELECT COUNT(*) INTO v_nb_validations_mois FROM parrainages_etablissements
    WHERE parrain_etab_id = v_parrainage.parrain_etab_id
      AND statut = 'VALIDATED' AND valide_le >= DATE_TRUNC('month', NOW());
    IF v_nb_validations_mois > 5 THEN
      PERFORM public.fn_ecrire_audit_safe(
        p_acteur_id := v_parrainage.parrain_etab_id, p_type_acteur := 'SYSTEME',
        p_action := 'PARRAINAGE_ETAB_ANOMALIE', p_type_ressource := 'etablissement',
        p_id_ressource := v_parrainage.parrain_etab_id,
        p_details := jsonb_build_object('nb_validations_mois', v_nb_validations_mois)
      );
    END IF;
  END IF;

  -- Palier 2 : crédit additionnel (une seule fois). Peut tomber sur la même
  -- facture que le palier 1 si le GMV franchit d'emblée les 2 seuils.
  IF v_gmv_cents >= v_p2_gmv AND v_parrainage.palier2_atteint_le IS NULL THEN
    UPDATE parrainages_etablissements
    SET palier2_atteint_le = NOW(), mis_a_jour_le = NOW()
    WHERE id = v_parrainage.id;

    PERFORM public.fn_parrainage_etab_crediter_palier(v_parrainage.id, v_p2_eur, 2, v_gmv_cents);
  END IF;

  RETURN NEW;
END;
$function$;

-- ── 5. Message d'application du code (RPC) — nouveau libellé paliers ───────
CREATE OR REPLACE FUNCTION public.fn_appliquer_parrainage_etab(p_code text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_filleul_id UUID;
  v_parrain_etab RECORD;
  v_filleul_siret TEXT;
  v_existing UUID;
  v_nb_valides INT;
BEGIN
  v_filleul_id := mon_etablissement_id();
  IF v_filleul_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Vous devez être connecté en tant qu''établissement');
  END IF;

  IF p_code IS NULL OR LENGTH(TRIM(p_code)) = 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Code invalide');
  END IF;

  SELECT id, nom, siret INTO v_parrain_etab FROM etablissements
  WHERE code_parrainage = UPPER(TRIM(p_code));

  IF v_parrain_etab IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Code parrainage introuvable');
  END IF;

  IF v_parrain_etab.id = v_filleul_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'Vous ne pouvez pas vous parrainer vous-même');
  END IF;

  SELECT siret INTO v_filleul_siret FROM etablissements WHERE id = v_filleul_id;
  IF EXISTS (
    SELECT 1 FROM parrainages_etablissements pe
    JOIN etablissements ef ON ef.id = pe.filleul_etab_id
    WHERE ef.siret = v_filleul_siret AND pe.statut = 'VALIDATED'
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Cet établissement (SIRET) a déjà bénéficié d''un parrainage validé');
  END IF;

  SELECT id INTO v_existing FROM parrainages_etablissements WHERE filleul_etab_id = v_filleul_id;
  IF v_existing IS NOT NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Vous avez déjà appliqué un code parrainage');
  END IF;

  SELECT COUNT(*) INTO v_nb_valides FROM parrainages_etablissements
  WHERE parrain_etab_id = v_parrain_etab.id AND statut = 'VALIDATED';
  IF v_nb_valides >= 10 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Cet établissement parrain a atteint la limite de 10 parrainages validés');
  END IF;

  INSERT INTO parrainages_etablissements (parrain_etab_id, filleul_etab_id, code_parrainage, statut)
  VALUES (v_parrain_etab.id, v_filleul_id, UPPER(TRIM(p_code)), 'PENDING');

  UPDATE etablissements SET parraine_par_id = v_parrain_etab.id
  WHERE id = v_filleul_id AND parraine_par_id IS NULL;

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_filleul_id,
    p_type_acteur := 'ADMIN_ETABLISSEMENT',
    p_action := 'PARRAINAGE_ETAB_APPLIQUE',
    p_type_ressource := 'etablissement',
    p_id_ressource := v_parrain_etab.id,
    p_details := jsonb_build_object('code_parrainage', UPPER(TRIM(p_code)), 'parrain_nom', v_parrain_etab.nom)
  );

  RETURN jsonb_build_object(
    'success', true,
    'parrain_nom', v_parrain_etab.nom,
    'message', 'Code parrainage appliqué. Vous et votre parrain recevrez des crédits commission au fil des missions : 50€ chacun dès 500€ de missions réalisées, puis 150€ chacun à 2 000€.'
  );
END;
$function$;
