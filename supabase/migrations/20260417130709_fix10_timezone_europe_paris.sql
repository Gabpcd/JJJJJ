-- ============================================================
-- CP-LITIGES-7a FIX 10 — AT TIME ZONE Europe/Paris
-- ============================================================
-- Audit des RPCs/triggers CP-LITIGES qui manipulent dates/heures :
--
-- | Fonction                         | Enjeu TZ                             |
-- |----------------------------------|--------------------------------------|
-- | fn_ajouter_jours_ouvres          | BUG : EXTRACT(DOW) + ::DATE sans TZ  |
-- | fn_fenetre_contestation_ouverte  | OK (comparaison durée absolue)       |
-- | fn_litiges_escalader_auto        | OK (durée abs + délègue à fn ci-dessus)|
-- | fn_envoyer_rappels_litiges       | OK (age_h en durée absolue)          |
-- | fn_alerter_mediation_prioritaire | OK (comparaison durée absolue)       |
--
-- Convention Jolene (cf docs/cron-litiges.md) :
--   - La base stocke en TIMESTAMPTZ (UTC canonique)
--   - Les règles métiers s'expriment en heure Europe/Paris
--   - Les durées absolues (NOW() - INTERVAL 'N hours') restent en UTC
--   - Les calculs CALENDAIRES (DOW, DATE, jour ouvré, jour férié) doivent
--     basculer en Europe/Paris pour éviter les bugs aux frontières de
--     jour et aux transitions DST (mars/octobre).
--
-- Seule fonction à corriger : fn_ajouter_jours_ouvres. Bug reproductible :
-- fn_ajouter_jours_ouvres('2026-04-27 01:00+02'::tstz, 5) — lundi 01h Paris
-- + 5 ouvrés devrait skipper le vendredi férié 1er mai 2026, mais le code
-- buggé évalue DOW/DATE en UTC (donc '2026-04-30' jeudi UTC pas férié),
-- ne skip pas, retourne mardi 05/05 au lieu de lundi 04/05.
--
-- Correctif : on bascule l'arithmétique en TIMESTAMP (wall time Paris)
-- pour toute la boucle, puis on reconvertit en TIMESTAMPTZ à la sortie.
-- Bonus : l'addition INTERVAL '1 day' sur TIMESTAMP (sans TZ) est un
-- vrai jour civil (24h ou 23h/25h en DST), ce qui est le comportement
-- métier attendu.
-- ============================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.fn_ajouter_jours_ouvres(
  p_date TIMESTAMPTZ,
  p_nb_jours INTEGER
)
RETURNS TIMESTAMPTZ
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path TO 'public'
AS $$
DECLARE
  v_local  TIMESTAMP;                                -- wall time Europe/Paris
  v_count  INTEGER := 0;
  v_step   INTEGER := CASE WHEN p_nb_jours >= 0 THEN 1 ELSE -1 END;
  v_target INTEGER := abs(p_nb_jours);
  v_dow    INTEGER;
  v_is_feried BOOLEAN;
BEGIN
  -- Bascule UTC → wall-time Paris pour toute l'arithmétique calendaire.
  v_local := p_date AT TIME ZONE 'Europe/Paris';

  IF v_target = 0 THEN
    RETURN v_local AT TIME ZONE 'Europe/Paris';
  END IF;

  WHILE v_count < v_target LOOP
    v_local := v_local + (v_step || ' day')::INTERVAL;
    v_dow := EXTRACT(DOW FROM v_local)::INTEGER;   -- 0=Dim, 6=Sam (Paris)
    IF v_dow IN (0, 6) THEN
      CONTINUE;
    END IF;
    SELECT EXISTS (
      SELECT 1 FROM public.jours_feries_fr
      WHERE date_ferie = v_local::DATE             -- date civile Paris
    ) INTO v_is_feried;
    IF v_is_feried THEN
      CONTINUE;
    END IF;
    v_count := v_count + 1;
  END LOOP;

  -- Retour en TIMESTAMPTZ (même instant absolu, TZ UTC en base).
  RETURN v_local AT TIME ZONE 'Europe/Paris';
END;
$$;

COMMENT ON FUNCTION public.fn_ajouter_jours_ouvres(TIMESTAMPTZ, INTEGER) IS
  'CP-LITIGES-7a FIX 10 — ajoute N jours ouvrés (FR) en basculant l''arith. '
  'en wall time Europe/Paris (DOW + DATE évalués en Paris, arithmétique '
  'en jour civil). Entrée/sortie TIMESTAMPTZ, TZ UTC en base. Gère DST.';

COMMIT;
