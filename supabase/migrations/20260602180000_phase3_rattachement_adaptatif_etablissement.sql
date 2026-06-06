-- PHASE 3 — Rattachement adaptatif personne↔établissement.
-- Helper de normalisation de nom (minuscule + pli des accents français + trim),
-- sans dépendre de l'extension unaccent (absente sur ce projet).
CREATE OR REPLACE FUNCTION public.fn_normaliser_nom(p text)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path TO 'public' AS $$
  SELECT btrim(lower(translate(
    coalesce(p, ''),
    'àâäáãéèêëíìîïóòôöõúùûüçñ',
    'aaaaaeeeeiiiiooooouuuucn'
  )));
$$;

-- Décide la méthode de rattachement et la marque vérifiée le cas échéant :
--   AUTO_DIRIGEANT : identité du représentant vérifiée ET correspond à un dirigeant
--     personne physique renvoyé par l'INSEE (petites structures : pharmacie, cabinet…)
--   EMAIL_PRO      : sinon, si l'email de contact a été confirmé (gros établissements)
--   ADMIN          : sinon, validation manuelle requise (fallback)
-- Testé (rollback) : AUTO_DIRIGEANT / EMAIL_PRO / ADMIN + pli des accents.
CREATE OR REPLACE FUNCTION public.fn_evaluer_rattachement_etablissement(p_etablissement_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_etab RECORD;
  v_methode text := 'ADMIN';
  v_verifie boolean := false;
  v_match boolean := false;
BEGIN
  IF NOT (est_admin() OR p_etablissement_id = mon_etablissement_id()) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non autorisé');
  END IF;

  SELECT finess_est_public, dirigeants, representant_nom, representant_prenom,
         representant_identite_verifiee, email_contact_verifie
  INTO v_etab FROM public.etablissements WHERE id = p_etablissement_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Établissement introuvable');
  END IF;

  -- 1) AUTO_DIRIGEANT : identité vérifiée + match avec un dirigeant personne physique
  IF v_etab.representant_identite_verifiee IS TRUE
     AND v_etab.representant_nom IS NOT NULL
     AND v_etab.dirigeants IS NOT NULL THEN
    SELECT TRUE INTO v_match
    FROM jsonb_array_elements(v_etab.dirigeants) AS d
    WHERE public.fn_normaliser_nom(d->>'type_dirigeant') LIKE '%physique%'
      AND public.fn_normaliser_nom(d->>'nom') = public.fn_normaliser_nom(v_etab.representant_nom)
      AND (
        v_etab.representant_prenom IS NULL
        OR public.fn_normaliser_nom(d->>'prenoms') LIKE '%' || public.fn_normaliser_nom(v_etab.representant_prenom) || '%'
      )
    LIMIT 1;
    IF v_match IS TRUE THEN
      v_methode := 'AUTO_DIRIGEANT'; v_verifie := TRUE;
    END IF;
  END IF;

  -- 2) EMAIL_PRO : sinon, email de contact confirmé
  IF NOT v_verifie AND v_etab.email_contact_verifie IS TRUE THEN
    v_methode := 'EMAIL_PRO'; v_verifie := TRUE;
  END IF;

  -- 3) sinon ADMIN (défaut)

  UPDATE public.etablissements SET
    rattachement_methode = v_methode,
    rattachement_verifie = v_verifie,
    rattachement_verifie_le = CASE WHEN v_verifie THEN now() ELSE NULL END
  WHERE id = p_etablissement_id;

  RETURN jsonb_build_object('success', true, 'methode', v_methode, 'verifie', v_verifie, 'match_dirigeant', COALESCE(v_match, false));
END;
$$;
