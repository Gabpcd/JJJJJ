-- Lot 16 — fix cosmétique (revue de clôture A6). Le gate D9(b)
-- `fn_trg_gate_assignation_paiement` lève deux messages tournés « établissement »
-- (« Configurez VOTRE mode de paiement… »). Mais l'assignation est aussi
-- déclenchée quand un SOIGNANT accepte une proposition directe d'un étab sans
-- moyen de paiement : le soignant voit alors un message qui ne le concerne pas.
-- Neutralisation du wording (correct que ce soit l'étab ou le soignant qui le
-- voie). Aucun impact sécurité, seul le texte change. Redéfinition depuis la
-- déf LIVE (règle 9.0).
CREATE OR REPLACE FUNCTION public.fn_trg_gate_assignation_paiement()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_mode text;
  v_mandat boolean;
BEGIN
  IF NEW.soignant_assigne_id IS NOT NULL
     AND (OLD.soignant_assigne_id IS NULL OR OLD.soignant_assigne_id <> NEW.soignant_assigne_id)
     AND auth.uid() IS NOT NULL
     AND NOT est_admin() THEN
    SELECT mode_paiement_commission, stripe_sepa_payment_method_id IS NOT NULL
    INTO v_mode, v_mandat
    FROM etablissements WHERE id = NEW.etablissement_id;

    IF v_mode IS NULL THEN
      RAISE EXCEPTION 'Cette mission ne peut pas être attribuée : l''établissement doit d''abord configurer un mode de paiement (Paramètres → Facturation).';
    END IF;
    IF v_mode = 'SEPA_DEBIT' AND NOT v_mandat THEN
      RAISE EXCEPTION 'Cette mission ne peut pas être attribuée : le mandat SEPA de l''établissement n''est pas encore posé (IBAN à ajouter dans Paramètres → Facturation).';
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;
