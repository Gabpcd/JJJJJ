-- Parrainage établissement : aligne la mécanique sur le parrainage soignant.
-- AVANT : filleul publie une mission (ASSIGNEE/TERMINEE) -> parrain reçoit 100€ de crédit.
-- APRÈS : quand Jolene a encaissé 100€ de commission auprès du filleul (factures PAYEE),
--         le parrain ET le filleul reçoivent CHACUN 50€ de crédit déduit de leur facture
--         commission. Symétrie totale avec le soignant (50€ + 50€, seuil 100€ commission).
-- Badge « Ambassadeur » après 3 filleuls validés (géré côté frontend).

-- 1. Supprime le crédit de 100€ déclenché sur la mission (mécanique obsolète).
DROP TRIGGER IF EXISTS trg_valider_parrainage_etab ON public.missions;

CREATE OR REPLACE FUNCTION public.fn_trg_valider_parrainage_etab()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
BEGIN
  -- Mécanique déplacée vers fn_trg_valider_parrainage_etab_commission (seuil 100€ de
  -- commission encaissée, crédit 50€ parrain + 50€ filleul). No-op de compatibilité.
  RETURN NEW;
END;
$function$;

-- 2. Récompense quand Jolene encaisse 100€ de commission auprès du filleul.
CREATE OR REPLACE FUNCTION public.fn_trg_valider_parrainage_etab_commission()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_parrainage RECORD;
  v_filleul_nom TEXT;
  v_parrain_nom TEXT;
  v_total_commission NUMERIC;
  v_credit_parrain UUID;
  v_credit_filleul UUID;
  v_nb_validations_mois INT;
  v_prime INT := 50;
BEGIN
  IF NEW.statut <> 'PAYEE' THEN RETURN NEW; END IF;
  IF TG_OP = 'UPDATE' AND COALESCE(OLD.statut, '') = 'PAYEE' THEN RETURN NEW; END IF;
  IF NEW.etablissement_id IS NULL THEN RETURN NEW; END IF;

  SELECT * INTO v_parrainage FROM parrainages_etablissements
  WHERE filleul_etab_id = NEW.etablissement_id AND statut = 'PENDING'
  LIMIT 1;
  IF v_parrainage.id IS NULL THEN RETURN NEW; END IF;

  SELECT COALESCE(SUM(montant_ht), 0) INTO v_total_commission
  FROM factures
  WHERE etablissement_id = NEW.etablissement_id
    AND statut = 'PAYEE'
    AND COALESCE(montant_ht, 0) > 0;

  IF v_total_commission < 100 THEN RETURN NEW; END IF;

  UPDATE parrainages_etablissements
  SET statut = 'VALIDATED', valide_le = NOW(), mis_a_jour_le = NOW()
  WHERE id = v_parrainage.id;

  SELECT nom INTO v_filleul_nom FROM etablissements WHERE id = v_parrainage.filleul_etab_id;
  SELECT nom INTO v_parrain_nom FROM etablissements WHERE id = v_parrainage.parrain_etab_id;

  INSERT INTO credits_etablissement (etablissement_id, montant_eur, motif, parrainage_id)
  VALUES (v_parrainage.parrain_etab_id, v_prime, 'PARRAINAGE', v_parrainage.id)
  RETURNING id INTO v_credit_parrain;

  INSERT INTO credits_etablissement (etablissement_id, montant_eur, motif, parrainage_id)
  VALUES (v_parrainage.filleul_etab_id, v_prime, 'PARRAINAGE', v_parrainage.id)
  RETURNING id INTO v_credit_filleul;

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_parrainage.parrain_etab_id, p_type_acteur := 'SYSTEME',
    p_action := 'CREDIT_PARRAINAGE_CREE', p_type_ressource := 'parrainage_etab', p_id_ressource := v_parrainage.id,
    p_details := jsonb_build_object('credit_parrain_id', v_credit_parrain, 'credit_filleul_id', v_credit_filleul,
                                    'montant_eur', v_prime, 'filleul_etab_id', v_parrainage.filleul_etab_id,
                                    'commission_cumulee', v_total_commission)
  );

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_parrainage.filleul_etab_id, p_type_acteur := 'SYSTEME',
    p_action := 'PARRAINAGE_ETAB_VALIDE', p_type_ressource := 'parrainage_etab', p_id_ressource := v_parrainage.id,
    p_details := jsonb_build_object('parrain_etab_id', v_parrainage.parrain_etab_id, 'facture_id', NEW.id)
  );

  INSERT INTO notifications (destinataire_id, type_destinataire, type, titre, corps, lien)
  VALUES (
    v_parrainage.parrain_etab_id, 'ETABLISSEMENT', 'CREDIT_PARRAINAGE',
    '🎉 +' || v_prime || '€ de crédit Jolene !',
    'Votre filleul ' || COALESCE(v_filleul_nom, 'établissement') || ' a généré 100€ de commission. ' || v_prime || '€ de crédit ont été ajoutés et seront déduits de votre prochaine facture commission.',
    '/etablissement/parrainage'
  );

  INSERT INTO notifications (destinataire_id, type_destinataire, type, titre, corps, lien)
  VALUES (
    v_parrainage.filleul_etab_id, 'ETABLISSEMENT', 'CREDIT_PARRAINAGE',
    '🎉 +' || v_prime || '€ de crédit parrainage !',
    'Grâce au parrainage de ' || COALESCE(v_parrain_nom, 'votre parrain') || ', ' || v_prime || '€ de crédit ont été ajoutés et seront déduits de votre prochaine facture commission.',
    '/etablissement/parrainage'
  );

  -- Garde-fou anti-abus : > 5 validations dans le mois -> signal audit.
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

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_valider_parrainage_etab_commission ON public.factures;
CREATE TRIGGER trg_valider_parrainage_etab_commission
  AFTER INSERT OR UPDATE ON public.factures
  FOR EACH ROW EXECUTE FUNCTION public.fn_trg_valider_parrainage_etab_commission();

-- 3. « Mes filleuls » : n'affiche QUE le crédit du parrain (pas la part filleul de 50€).
CREATE OR REPLACE FUNCTION public.fn_mes_filleuls_etab()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_etab_id UUID := mon_etablissement_id();
  v_result JSONB;
BEGIN
  IF v_etab_id IS NULL AND NOT est_admin() THEN
    RETURN jsonb_build_object('error', 'Accès refusé');
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'parrainage_id', pe.id,
    'filleul_etab_id', e.id,
    'filleul_nom', e.nom,
    'filleul_ville', e.adresse_ville,
    'statut', pe.statut,
    'cree_le', pe.cree_le,
    'valide_le', pe.valide_le,
    'credit_montant_eur', (
      SELECT SUM(c.montant_eur) FROM credits_etablissement c
      WHERE c.parrainage_id = pe.id AND c.etablissement_id = pe.parrain_etab_id
    )
  ) ORDER BY pe.cree_le DESC), '[]'::jsonb)
  INTO v_result
  FROM parrainages_etablissements pe
  JOIN etablissements e ON e.id = pe.filleul_etab_id
  WHERE pe.parrain_etab_id = v_etab_id OR est_admin();

  RETURN v_result;
END;
$function$;

-- 4. Message d'application du code aligné sur la nouvelle mécanique.
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
    'message', 'Code parrainage appliqué. Dès que Jolene aura encaissé 100€ de commission sur vos missions, vous et votre parrain recevrez chacun 50€ de crédit commission.'
  );
END;
$function$;
