-- BUG : un contrat signé en mode CANVAS n'atteignait SIGNE_COMPLET que si
-- l'établissement signait EN DERNIER. Cause : fn_protect_contrat_integrity
-- (BEFORE UPDATE) fait NEW.statut := OLD.statut quand le caller est le soignant
-- (anti-falsification), ce qui annule la transition de statut légitime lorsque le
-- soignant signe en dernier → contrat bloqué à SIGNE_ETABLISSEMENT → pointage
-- impossible. Resté masqué car non testé de bout en bout dans l'ordre
-- "soignant en dernier" (l'UI n'impose pas d'ordre de signature).
--
-- Correctif : fn_signer_contrat_soignant pose un drapeau de session transactionnel
-- avant son UPDATE ; le trigger autorise alors UNIQUEMENT la transition de statut
-- de signature (SIGNE_SOIGNANT / SIGNE_COMPLET). Le drapeau n'est pas posable depuis
-- un UPDATE direct PostgREST → la protection anti-falsification reste intacte
-- (vérifié : un UPDATE direct du soignant sur statut est toujours reverté).

CREATE OR REPLACE FUNCTION public.fn_protect_contrat_integrity()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  -- Si le caller est le soignant, on ne laisse passer que ses propres champs de signature
  IF OLD.soignant_id = auth.uid()
     AND NOT public.est_admin()
     AND NOT public.est_admin_etablissement() THEN
    NEW.signature_etablissement := OLD.signature_etablissement;
    NEW.signature_etablissement_le := OLD.signature_etablissement_le;
    NEW.signature_image_etablissement := OLD.signature_image_etablissement;
    NEW.signature_ip_etablissement := OLD.signature_ip_etablissement;
    NEW.signature_navigateur_etablissement := OLD.signature_navigateur_etablissement;
    NEW.contenu_html := OLD.contenu_html;
    -- Statut : verrouillé SAUF transition de signature légitime déclenchée par
    -- fn_signer_contrat_soignant (drapeau de session, non posable côté client).
    IF NOT (current_setting('jolene.signature_soignant_en_cours', true) = '1'
            AND NEW.statut IN ('SIGNE_SOIGNANT', 'SIGNE_COMPLET')) THEN
      NEW.statut := OLD.statut;
    END IF;
    NEW.numero_contrat := OLD.numero_contrat;
    NEW.type_contrat := OLD.type_contrat;
    NEW.etablissement_id := OLD.etablissement_id;
    NEW.mission_id := OLD.mission_id;
    NEW.pdf_cle_s3 := OLD.pdf_cle_s3;
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_signer_contrat_soignant(p_contrat_id uuid, p_signature_image text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_contrat RECORD;
BEGIN
    SELECT * INTO v_contrat FROM contrats_mission WHERE id = p_contrat_id;
    IF v_contrat IS NULL THEN RETURN '{"error":"Contrat introuvable"}'::JSONB; END IF;
    IF v_contrat.soignant_id != auth.uid() THEN RETURN '{"error":"Ce contrat ne vous concerne pas"}'::JSONB; END IF;
    IF v_contrat.signature_soignant = TRUE THEN RETURN '{"error":"Déjà signé"}'::JSONB; END IF;

    -- Autorise la transition de statut de signature dans le trigger de protection
    PERFORM set_config('jolene.signature_soignant_en_cours', '1', true);

    UPDATE contrats_mission SET
        signature_soignant = TRUE,
        signature_soignant_le = NOW(),
        signature_image_soignant = p_signature_image,
        signature_navigateur_soignant = current_setting('request.headers', true)::JSON->>'user-agent',
        statut = CASE
            WHEN signature_etablissement = TRUE THEN 'SIGNE_COMPLET'
            ELSE 'SIGNE_SOIGNANT'
        END,
        modifie_le = NOW()
    WHERE id = p_contrat_id;

    RETURN '{"success":true}'::JSONB;
END;
$function$;
