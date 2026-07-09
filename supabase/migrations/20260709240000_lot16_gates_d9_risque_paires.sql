-- Lot 16 — Gates D9 (b/d) + Couche 4 : événements de risque par paire.
--
-- Constats (09/07/2026, définitions LIVE — règle 9.0) :
--   D9(d) BUG : « Remplacer le contrat » ne repassait PAS contrat_valide à
--     FALSE côté serveur (fn_modifier_mon_etablissement posait contrat_url sans
--     invalider) — l'invalidation n'existait que dans l'état React, perdue au
--     reload → un étab pouvait publier avec un contrat remplacé non re-validé.
--   D9(b) : l'acceptation d'un candidat ne vérifiait AUCUN moyen de paiement
--     hors carte (SEPA sans mandat / mode absent passaient).
--   Couche 4 : aucun événement de risque par paire (étab, soignant) — le refus
--     anti-leak n'alimentait que journaux_audit, inexploitable par binôme.

-- ── 1. D9(d) : remplacer le contrat invalide la validation (serveur) ─────────
-- Base = définition LIVE ; ajouts marqués Lot 16.
CREATE OR REPLACE FUNCTION public.fn_modifier_mon_etablissement(p_nom text DEFAULT NULL::text, p_finess text DEFAULT NULL::text, p_adresse_rue text DEFAULT NULL::text, p_adresse_ville text DEFAULT NULL::text, p_adresse_code_postal text DEFAULT NULL::text, p_adresse_departement text DEFAULT NULL::text, p_email_contact text DEFAULT NULL::text, p_telephone text DEFAULT NULL::text, p_adresse_lat numeric DEFAULT NULL::numeric, p_adresse_lng numeric DEFAULT NULL::numeric, p_taux_majoration_nuit numeric DEFAULT NULL::numeric, p_taux_majoration_dimanche numeric DEFAULT NULL::numeric, p_taux_majoration_ferie numeric DEFAULT NULL::numeric, p_couleur_theme text DEFAULT NULL::text, p_convention_collective text DEFAULT NULL::text, p_mode_paiement_commission text DEFAULT NULL::text, p_logo_url text DEFAULT NULL::text, p_contrat_url text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_etab_id UUID := mon_etablissement_id();
    v_ip inet;
    v_user_agent text;
    v_headers jsonb;
    v_champs_modifies jsonb := '[]'::jsonb;
BEGIN
    IF v_etab_id IS NULL AND NOT est_admin() THEN
        RETURN '{"error":"Établissement non trouvé"}'::JSONB;
    END IF;

    -- Validation couleur hex
    IF p_couleur_theme IS NOT NULL AND p_couleur_theme !~ '^#[0-9a-fA-F]{6}$' THEN
        RETURN '{"error":"Couleur invalide (format #RRGGBB)"}'::JSONB;
    END IF;

    UPDATE etablissements SET
        nom = COALESCE(p_nom, nom),
        finess = COALESCE(p_finess, finess),
        adresse_rue = COALESCE(p_adresse_rue, adresse_rue),
        adresse_ville = COALESCE(p_adresse_ville, adresse_ville),
        adresse_code_postal = COALESCE(p_adresse_code_postal, adresse_code_postal),
        adresse_departement = COALESCE(p_adresse_departement, adresse_departement),
        email_contact = COALESCE(p_email_contact, email_contact),
        telephone_contact = COALESCE(p_telephone, telephone_contact),
        adresse_lat = COALESCE(p_adresse_lat, adresse_lat),
        adresse_lng = COALESCE(p_adresse_lng, adresse_lng),
        taux_majoration_nuit_pourcent = COALESCE(p_taux_majoration_nuit, taux_majoration_nuit_pourcent),
        taux_majoration_dimanche_pourcent = COALESCE(p_taux_majoration_dimanche, taux_majoration_dimanche_pourcent),
        taux_majoration_ferie_pourcent = COALESCE(p_taux_majoration_ferie, taux_majoration_ferie_pourcent),
        couleur_theme = COALESCE(p_couleur_theme, couleur_theme),
        convention_collective = COALESCE(p_convention_collective, convention_collective),
        mode_paiement_commission = COALESCE(p_mode_paiement_commission, mode_paiement_commission),
        logo_url = COALESCE(p_logo_url, logo_url),
        contrat_url = COALESCE(p_contrat_url, contrat_url),
        contrat_uploade_le = CASE WHEN p_contrat_url IS NOT NULL THEN NOW() ELSE contrat_uploade_le END,
        -- Lot 16 / D9(d) : un contrat remplacé repart EN ATTENTE DE VALIDATION.
        contrat_valide = CASE WHEN p_contrat_url IS NOT NULL THEN FALSE ELSE contrat_valide END,
        modifie_le = NOW()
    WHERE id = v_etab_id;

    -- Audit RGPD
    BEGIN
      v_headers := current_setting('request.headers', true)::jsonb;
      v_ip := NULLIF(trim(split_part(coalesce(v_headers->>'x-forwarded-for', ''), ',', 1)), '')::inet;
      v_user_agent := NULLIF(v_headers->>'user-agent', '');
    EXCEPTION WHEN OTHERS THEN
      v_ip := NULL; v_user_agent := NULL;
    END;

    IF p_nom IS NOT NULL OR p_finess IS NOT NULL THEN v_champs_modifies := v_champs_modifies || '"identite"'::jsonb; END IF;
    IF p_adresse_rue IS NOT NULL OR p_adresse_ville IS NOT NULL THEN v_champs_modifies := v_champs_modifies || '"adresse"'::jsonb; END IF;
    IF p_email_contact IS NOT NULL OR p_telephone IS NOT NULL THEN v_champs_modifies := v_champs_modifies || '"contact"'::jsonb; END IF;
    IF p_taux_majoration_nuit IS NOT NULL OR p_taux_majoration_dimanche IS NOT NULL OR p_taux_majoration_ferie IS NOT NULL THEN v_champs_modifies := v_champs_modifies || '"taux_majoration"'::jsonb; END IF;
    IF p_convention_collective IS NOT NULL THEN v_champs_modifies := v_champs_modifies || '"convention_collective"'::jsonb; END IF;
    IF p_contrat_url IS NOT NULL THEN v_champs_modifies := v_champs_modifies || '"contrat"'::jsonb; END IF;

    PERFORM fn_ecrire_audit(
      auth.uid(), 'ADMIN_ETABLISSEMENT', 'ETABLISSEMENT_MODIFICATION',
      'etablissement', v_etab_id, NULL,
      jsonb_build_object('champs_modifies', v_champs_modifies),
      v_ip, v_user_agent
    );

    RETURN '{"success":true}'::JSONB;
END;
$function$;

-- ── 2. D9(b) : assigner un soignant exige un moyen de paiement opérant ───────
-- Data-layer (gap verrouillé) : attrape tous les chemins d'assignation par un
-- utilisateur authentifié. Les flux service_role (seeds, jobs) et admin sont
-- exemptés (auth.uid() NULL / est_admin()). Refus = explication + CTA (D9 :
-- jamais un mur muet).
CREATE OR REPLACE FUNCTION public.fn_trg_gate_assignation_paiement()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
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
      RAISE EXCEPTION 'Configurez votre mode de paiement avant d''attribuer une mission (Paramètres → Facturation).';
    END IF;
    IF v_mode = 'SEPA_DEBIT' AND NOT v_mandat THEN
      RAISE EXCEPTION 'Votre mandat SEPA n''est pas encore posé : ajoutez votre IBAN (Paramètres → Facturation) avant d''attribuer la mission.';
    END IF;
  END IF;
  RETURN NEW;
END;
$fn$;
DROP TRIGGER IF EXISTS trg_gate_assignation_paiement ON public.missions;
CREATE TRIGGER trg_gate_assignation_paiement
  BEFORE UPDATE OF soignant_assigne_id ON public.missions
  FOR EACH ROW EXECUTE FUNCTION public.fn_trg_gate_assignation_paiement();

-- ── 3. Couche 4 : événements de risque par paire (étab, soignant) ────────────
-- Alimentée dès maintenant (refus anti-leak, à étendre : annulation
-- post-contact, binôme récurrent hors plateforme). Le batch de scoring et
-- l'échelle d'escalade s'activent post-launch sur ces données.
CREATE TABLE IF NOT EXISTS public.evenements_risque_paires (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  etablissement_id uuid NOT NULL,
  soignant_id uuid NOT NULL,
  type_evenement text NOT NULL CHECK (type_evenement IN (
    'CONTACT_TENTE', 'ANNULATION_POST_CONTACT', 'BINOME_RECURRENT_INACTIF'
  )),
  details jsonb,
  cree_le timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_risque_paires_paire
  ON public.evenements_risque_paires (etablissement_id, soignant_id, cree_le DESC);

ALTER TABLE public.evenements_risque_paires ENABLE ROW LEVEL SECURITY;
-- Lecture : admin plateforme uniquement ; écriture : service_role (edge/jobs).
DROP POLICY IF EXISTS risque_paires_admin_select ON public.evenements_risque_paires;
CREATE POLICY risque_paires_admin_select ON public.evenements_risque_paires
  FOR SELECT USING (est_admin());
