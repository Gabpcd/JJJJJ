-- Lot 14 — D4/D6 : verrou paiement manuel sur mission escrow, gel J+15
-- paramétrable, mode de paiement commission par défaut selon le secteur.
--
-- Constats (09/07/2026, inventaire + définitions LIVE — règle 9.0) :
--   D4 : fn_declarer_paiement_soignant n'empêchait PAS une déclaration
--        manuelle sur une mission LIBÉRALE dont le paiement passe par
--        l'escrow ⚡ (double-paiement possible, fuite du circuit sécurisé).
--   Gel : dec_bloquer_si_facture_impayee bloquait à 30 j codés en dur —
--        décision D6/D9 = gel des NOUVELLES publications à J+15 d'impayé,
--        paramétrable (les missions en cours ne sont jamais touchées).
--   D6 : mode_paiement_commission démarrait à FACTURE_MENSUELLE pour tout le
--        monde (DSO auto-infligé) — défaut par secteur : public → CHORUS_PRO,
--        privé → SEPA_DEBIT (mandat posé par l'onboarding opt-out existant).

-- ── 1. Verrou D4 (gap verrouillé, data-layer : attrape TOUS les chemins) ─────
-- Une mission couverte par un escrow actif ne peut PAS recevoir de paiement
-- manuel : le circuit ⚡ (capture → release à la validation) fait foi, la seule
-- voie de modification est le litige. REMBOURSE = escrow annulé → le manuel
-- redevient possible (cas support).
CREATE OR REPLACE FUNCTION public.fn_trg_bloquer_paiement_manuel_escrow()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
BEGIN
  IF NEW.mission_id IS NOT NULL AND EXISTS (
    SELECT 1 FROM paiements_escrow pe
    WHERE pe.mission_id = NEW.mission_id
      AND pe.statut <> 'REMBOURSE'
  ) THEN
    RAISE EXCEPTION 'Le paiement de cette mission passe par le circuit sécurisé (paiement rapide) : il sera versé automatiquement à la validation des présences. La déclaration manuelle est indisponible (décision D4 — cf. docs/PLAYBOOK_ESCROW.md) ; en cas de désaccord, ouvrez un litige depuis la mission.';
  END IF;
  RETURN NEW;
END;
$fn$;
DROP TRIGGER IF EXISTS trg_bloquer_paiement_manuel_escrow ON public.paiements_soignant;
CREATE TRIGGER trg_bloquer_paiement_manuel_escrow
  BEFORE INSERT ON public.paiements_soignant
  FOR EACH ROW EXECUTE FUNCTION public.fn_trg_bloquer_paiement_manuel_escrow();

-- ── 2. Gel des publications à J+15 d'impayé (paramétrable) ───────────────────
-- Base = définition LIVE. Changements : délai fn_param_num
-- ('gel_publication_impaye_jours', 15) au lieu de 30 j en dur, message avec
-- l'explication + le chemin de déblocage (jamais un mur muet — D9).
CREATE OR REPLACE FUNCTION public.dec_bloquer_si_facture_impayee()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_nb_impayees INTEGER;
    v_delai_jours NUMERIC;
BEGIN
    IF TG_OP = 'INSERT' THEN
        v_delai_jours := public.fn_param_num('gel_publication_impaye_jours', 15);

        SELECT COUNT(*) INTO v_nb_impayees
        FROM factures
        WHERE etablissement_id = NEW.etablissement_id
          AND statut = 'EMISE'
          AND cree_le + make_interval(days => v_delai_jours::int) < NOW();

        IF v_nb_impayees > 0 AND NOT est_admin() THEN
            RAISE EXCEPTION 'Vous avez % facture(s) impayée(s) depuis plus de % jours : les nouvelles publications sont suspendues (vos missions en cours ne sont pas affectées). Régularisez depuis Facturation pour republier.', v_nb_impayees, v_delai_jours::int;
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;

-- Paramètre (défaut 15 j), visible/éditable en admin.
INSERT INTO parametres_systeme(cle, valeur, label, description, unite, categorie)
VALUES('gel_publication_impaye_jours', 15,
       'Gel publications — impayé (jours)',
       'Nombre de jours après émission d''une facture impayée au-delà duquel les nouvelles publications de missions sont gelées (les missions en cours ne sont jamais touchées).',
       'jours', 'GENERAL')
ON CONFLICT (cle) DO NOTHING;

-- ── 3. D6 : défaut du mode de paiement commission par SECTEUR ────────────────
-- À la création d'un établissement (INSERT uniquement — l'existant n'est pas
-- réécrit) : public → CHORUS_PRO (mandat administratif), privé → SEPA_DEBIT
-- (mandat posé par l'onboarding opt-out). La CB reste disponible au choix.
CREATE OR REPLACE FUNCTION public.fn_trg_defaut_mode_paiement_secteur()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
BEGIN
  IF NEW.mode_paiement_commission IS NULL OR NEW.mode_paiement_commission = 'FACTURE_MENSUELLE' THEN
    IF NEW.type::text IN ('HOPITAL_PUBLIC', 'CHU', 'CENTRE_SANTE', 'HAD') THEN
      NEW.mode_paiement_commission := 'CHORUS_PRO';
    ELSE
      NEW.mode_paiement_commission := 'SEPA_DEBIT';
    END IF;
  END IF;
  RETURN NEW;
END;
$fn$;
DROP TRIGGER IF EXISTS trg_defaut_mode_paiement_secteur ON public.etablissements;
CREATE TRIGGER trg_defaut_mode_paiement_secteur
  BEFORE INSERT ON public.etablissements
  FOR EACH ROW EXECUTE FUNCTION public.fn_trg_defaut_mode_paiement_secteur();
