-- 7f-1 (Lot 7 v2 §5 + décision §11.2) — parrainage v1 auto-financé.
--
-- Règles d'or : déclencheur = COMMISSION ENCAISSÉE (jamais « mission
-- terminée ») ; prime totale ≤ 50 % de la commission encaissée au trigger.
-- Lancement : 25 € + 25 € quand le filleul atteint 500 € de GMV ENCAISSÉ
-- (factures d'honoraires PAYEES) ET ≥ 100 € de commission encaissée
-- (= 4 × la prime unitaire → le cap ≤ 50 % est garanti par construction).
--
-- ⚠️ Retrait du bonus « +50 h sur heures_cumulees » à la 1ʳᵉ mission :
-- il violait la règle d'or ET gonflait artificiellement le compteur des
-- 3 200 h qui alimente l'attestation légale. La transition FILLEUL_ACTIF
-- (tracking) et la notification sont conservées.

-- 1) Paramètres de lancement
UPDATE public.parametres_systeme SET valeur = 25 WHERE cle = 'prime_parrainage_eur';
INSERT INTO public.parametres_systeme (cle, valeur, label, description, categorie, val_min, val_max, cablee)
VALUES ('seuil_gmv_parrainage_eur', 500, 'Seuil GMV parrainage',
  'GMV encaissé (factures honoraires PAYEES) que le filleul doit atteindre pour déclencher les primes de parrainage. La prime exige AUSSI commission encaissée ≥ 4× la prime unitaire (cap ≤ 50 %).',
  'FINANCE', 100, 5000, true)
ON CONFLICT (cle) DO NOTHING;

-- 2) Cumul GMV par filleul
ALTER TABLE public.parrainages
  ADD COLUMN IF NOT EXISTS gmv_cumule_filleul numeric NOT NULL DEFAULT 0;

-- 3) Helper : vérifie les DEUX seuils et déclenche la prime (appelé par les
--    deux triggers — commission et GMV — pour que l'ordre d'arrivée soit
--    indifférent). Anti-fraude MEME_IP inchangé.
CREATE OR REPLACE FUNCTION public.fn_parrainage_verifier_seuils(p_parrainage_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_p RECORD;
  v_prime integer := (public.fn_param_num('prime_parrainage_eur', 25))::integer;
  v_seuil_gmv numeric := public.fn_param_num('seuil_gmv_parrainage_eur', 500);
  v_nb_fraude_signals INT;
BEGIN
  SELECT * INTO v_p FROM parrainages WHERE id = p_parrainage_id;
  IF v_p.id IS NULL OR v_p.statut <> 'FILLEUL_ACTIF' THEN RETURN; END IF;

  -- Double condition : GMV encaissé ≥ seuil ET commission encaissée ≥ 4× prime
  -- (prime totale 2×prime ≤ 50 % de la commission — règle d'or §5).
  IF COALESCE(v_p.gmv_cumule_filleul, 0) < v_seuil_gmv
     OR COALESCE(v_p.commission_cumulee_filleul, 0) < 4 * v_prime THEN
    RETURN;
  END IF;

  SELECT COUNT(*) INTO v_nb_fraude_signals FROM parrainage_fraude_signals
  WHERE parrainage_id = v_p.id AND type = 'MEME_IP';
  IF v_nb_fraude_signals > 0 THEN
    UPDATE parrainages SET statut = 'FRAUDE' WHERE id = v_p.id;
    PERFORM public.fn_ecrire_audit_safe(p_acteur_id := v_p.parrain_id, p_type_acteur := 'SYSTEME',
      p_action := 'PARRAINAGE_SOIGNANT_FRAUDE', p_type_ressource := 'parrainage', p_id_ressource := v_p.id,
      p_details := jsonb_build_object('filleul_id', v_p.filleul_id, 'commission_cumulee', v_p.commission_cumulee_filleul, 'gmv_cumule', v_p.gmv_cumule_filleul, 'raison', 'MEME_IP détectée à inscription'));
    INSERT INTO notifications (destinataire_id, type_destinataire, type, titre, corps, lien)
    SELECT id, 'ADMIN_PLATEFORME', 'SYSTEM', 'Parrainage fraude détectée',
      'Parrainage ' || v_p.id::text || ' : même IP parrain/filleul. Versement bloqué.', '/admin/utilisateurs'
    FROM soignants WHERE role = 'ADMIN_PLATEFORME' LIMIT 3;
    RETURN;
  END IF;

  UPDATE parrainages SET statut = 'VALIDE_EN_ATTENTE_SEUIL' WHERE id = v_p.id;
  PERFORM public.fn_ecrire_audit_safe(p_acteur_id := v_p.parrain_id, p_type_acteur := 'SYSTEME',
    p_action := 'PARRAINAGE_SOIGNANT_SEUIL_ATTEINT', p_type_ressource := 'parrainage', p_id_ressource := v_p.id,
    p_details := jsonb_build_object('filleul_id', v_p.filleul_id, 'commission_cumulee', v_p.commission_cumulee_filleul, 'gmv_cumule', v_p.gmv_cumule_filleul));
  INSERT INTO public.externalisation_actions (type_action, payload, source, source_id)
  VALUES ('RECOMPENSE_PARRAINAGE_SOIGNANT', jsonb_build_object(
    'parrainage_id', v_p.id, 'parrain_id', v_p.parrain_id, 'filleul_id', v_p.filleul_id,
    'montant_parrain', v_prime, 'montant_filleul', v_prime,
    'commission_cumulee', v_p.commission_cumulee_filleul, 'gmv_cumule', v_p.gmv_cumule_filleul),
    'parrainage_soignant', v_p.id);
  INSERT INTO notifications (destinataire_id, type_destinataire, type, titre, corps, lien) VALUES
    (v_p.parrain_id, 'SOIGNANT', 'PARRAINAGE_PRIME_VERSEE', 'Prime de parrainage de ' || v_prime || '€ !',
     'Ton filleul a atteint ' || v_seuil_gmv || '€ de missions encaissées. ' || v_prime || '€ arrivent sur ton compte.', '/soignant/parrainage'),
    (v_p.filleul_id, 'SOIGNANT', 'PARRAINAGE_PRIME_VERSEE', 'Prime de parrainage de ' || v_prime || '€ !',
     'Félicitations ! ' || v_prime || '€ de prime de parrainage arrivent sur ton compte.', '/soignant/parrainage');
END;
$fn$;

-- 4) Trigger commission (factures PAYEE) : cumule + délègue au helper.
CREATE OR REPLACE FUNCTION public.fn_trg_parrainage_commission_encaissee()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_mission RECORD; v_parrainage RECORD; v_commission NUMERIC;
BEGIN
  IF NEW.statut <> 'PAYEE' THEN RETURN NEW; END IF;
  IF TG_OP = 'UPDATE' AND COALESCE(OLD.statut, '') = 'PAYEE' THEN RETURN NEW; END IF;
  IF NEW.mission_id IS NULL THEN RETURN NEW; END IF;
  SELECT id, soignant_assigne_id INTO v_mission FROM missions WHERE id = NEW.mission_id;
  IF v_mission IS NULL OR v_mission.soignant_assigne_id IS NULL THEN RETURN NEW; END IF;
  SELECT * INTO v_parrainage FROM parrainages WHERE filleul_id = v_mission.soignant_assigne_id AND statut IN ('FILLEUL_ACTIF','VALIDE_EN_ATTENTE_SEUIL') LIMIT 1;
  IF v_parrainage IS NULL THEN RETURN NEW; END IF;
  v_commission := COALESCE(NEW.montant_ht, 0);
  IF v_commission <= 0 THEN RETURN NEW; END IF;
  UPDATE parrainages SET commission_cumulee_filleul = COALESCE(commission_cumulee_filleul, 0) + v_commission WHERE id = v_parrainage.id;
  PERFORM public.fn_parrainage_verifier_seuils(v_parrainage.id);
  RETURN NEW;
END;
$function$;

-- 5) NOUVEAU trigger GMV (factures d'honoraires PAYEES = missions encaissées).
CREATE OR REPLACE FUNCTION public.fn_trg_parrainage_gmv_encaisse()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_parrainage RECORD; v_gmv NUMERIC;
BEGIN
  IF NEW.statut <> 'PAYEE' THEN RETURN NEW; END IF;
  IF TG_OP = 'UPDATE' AND COALESCE(OLD.statut, '') = 'PAYEE' THEN RETURN NEW; END IF;
  IF NEW.soignant_id IS NULL THEN RETURN NEW; END IF;
  SELECT * INTO v_parrainage FROM parrainages WHERE filleul_id = NEW.soignant_id AND statut IN ('FILLEUL_ACTIF','VALIDE_EN_ATTENTE_SEUIL') LIMIT 1;
  IF v_parrainage IS NULL THEN RETURN NEW; END IF;
  v_gmv := COALESCE(NEW.montant_ht, 0);
  IF v_gmv <= 0 THEN RETURN NEW; END IF;
  UPDATE parrainages SET gmv_cumule_filleul = COALESCE(gmv_cumule_filleul, 0) + v_gmv WHERE id = v_parrainage.id;
  PERFORM public.fn_parrainage_verifier_seuils(v_parrainage.id);
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_parrainage_gmv_encaisse ON public.factures_honoraires;
CREATE TRIGGER trg_parrainage_gmv_encaisse
  AFTER INSERT OR UPDATE OF statut ON public.factures_honoraires
  FOR EACH ROW EXECUTE FUNCTION public.fn_trg_parrainage_gmv_encaisse();

-- 6) Trigger 1ʳᵉ mission : transition FILLEUL_ACTIF conservée (tracking +
--    notif), bonus +50 h RETIRÉ (règle d'or + intégrité du compteur 3 200 h).
CREATE OR REPLACE FUNCTION public.fn_trg_valider_parrainage_soignant_premiere_mission()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_parrainage RECORD;
  v_parrain_a_mission BOOLEAN;
  v_nb_filleuls_actifs INT;
  v_filleul_parrainage RECORD;
  v_prime integer := (public.fn_param_num('prime_parrainage_eur', 25))::integer;
  v_seuil_gmv numeric := public.fn_param_num('seuil_gmv_parrainage_eur', 500);
BEGIN
  IF NEW.statut <> 'TERMINEE' OR COALESCE(OLD.statut, '') = 'TERMINEE' THEN RETURN NEW; END IF;
  IF NEW.soignant_assigne_id IS NULL THEN RETURN NEW; END IF;

  SELECT * INTO v_parrainage FROM parrainages
  WHERE filleul_id = NEW.soignant_assigne_id AND statut = 'EN_ATTENTE'
  LIMIT 1;

  IF v_parrainage IS NOT NULL THEN
    SELECT EXISTS(
      SELECT 1 FROM missions
      WHERE soignant_assigne_id = v_parrainage.parrain_id AND statut = 'TERMINEE'
      LIMIT 1
    ) INTO v_parrain_a_mission;

    IF v_parrain_a_mission THEN
      SELECT COUNT(*) INTO v_nb_filleuls_actifs FROM parrainages
      WHERE parrain_id = v_parrainage.parrain_id
        AND statut IN ('VALIDE', 'FILLEUL_ACTIF', 'VALIDE_EN_ATTENTE_SEUIL', 'PRIME_VERSEE');

      IF v_nb_filleuls_actifs < 20 THEN
        UPDATE parrainages
        SET statut = 'FILLEUL_ACTIF', filleul_active_le = NOW(), valide_le = NOW()
        WHERE id = v_parrainage.id;

        INSERT INTO notifications (destinataire_id, type_destinataire, type, titre, corps, lien)
        VALUES (
          v_parrainage.parrain_id, 'SOIGNANT', 'PARRAINAGE',
          '🎉 Ton filleul a fait sa 1ʳᵉ mission !',
          'Vos primes de ' || v_prime || '€ chacun seront versées quand il aura atteint ' || v_seuil_gmv || '€ de missions encaissées. Suis sa progression sur ta page parrainage.',
          '/soignant/parrainage'
        );

        PERFORM public.fn_ecrire_audit_safe(
          p_acteur_id := v_parrainage.parrain_id, p_type_acteur := 'SYSTEME',
          p_action := 'PARRAINAGE_SOIGNANT_FILLEUL_ACTIF',
          p_type_ressource := 'parrainage', p_id_ressource := v_parrainage.id,
          p_details := jsonb_build_object('filleul_id', v_parrainage.filleul_id, 'mission_id', NEW.id)
        );
      ELSE
        UPDATE parrainages SET statut = 'EXPIRED' WHERE id = v_parrainage.id;
      END IF;
    END IF;
  END IF;

  FOR v_filleul_parrainage IN
    SELECT p.*, s.premiere_mission_le FROM parrainages p
    JOIN soignants s ON s.id = p.filleul_id
    WHERE p.parrain_id = NEW.soignant_assigne_id
      AND p.statut = 'EN_ATTENTE'
      AND s.premiere_mission_le IS NOT NULL
  LOOP
    SELECT COUNT(*) INTO v_nb_filleuls_actifs FROM parrainages
    WHERE parrain_id = NEW.soignant_assigne_id
      AND statut IN ('VALIDE', 'FILLEUL_ACTIF', 'VALIDE_EN_ATTENTE_SEUIL', 'PRIME_VERSEE');

    IF v_nb_filleuls_actifs < 20 THEN
      UPDATE parrainages
      SET statut = 'FILLEUL_ACTIF', filleul_active_le = NOW(), valide_le = NOW()
      WHERE id = v_filleul_parrainage.id;

      INSERT INTO notifications (destinataire_id, type_destinataire, type, titre, corps, lien)
      VALUES (
        NEW.soignant_assigne_id, 'SOIGNANT', 'PARRAINAGE',
        '🎉 Ton filleul est activé !',
        'Vos primes de ' || v_prime || '€ chacun seront versées à ' || v_seuil_gmv || '€ de missions encaissées par ton filleul.',
        '/soignant/parrainage'
      );
    END IF;
  END LOOP;

  RETURN NEW;
END;
$$;
