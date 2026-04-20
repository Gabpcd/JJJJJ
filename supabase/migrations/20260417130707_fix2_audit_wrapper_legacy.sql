-- ============================================================
-- CP-LITIGES-7a FIX 2 — Audit RGPD wrapper legacy 2-arg
-- ============================================================
-- Le wrapper DEPRECATED fn_ouvrir_litige_rate_limited(UUID, TEXT)
-- (CP-LITIGES-2 lignes 523-540) délègue à la version 3-arg mais
-- ne loggait pas d'entrée audit LITIGE_OUVERTURE_LEGACY. Ce FIX
-- ajoute fn_ecrire_audit AVANT la délégation pour traçabilité RGPD
-- des appels legacy qui ne devraient plus se produire (mais qui
-- seraient un signal d'alerte si ça arrive).
--
-- RAISE WARNING existant conservé.
-- ============================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.fn_ouvrir_litige_rate_limited(
  p_mission_id UUID,
  p_motif TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_user_id UUID := auth.uid();
BEGIN
  RAISE WARNING 'fn_ouvrir_litige_rate_limited(UUID, TEXT) is DEPRECATED since CP-LITIGES-2. Use 3-arg signature with type_litige.';

  -- [FIX-2] Audit RGPD : tracer l'appel legacy avant délégation.
  PERFORM public.fn_ecrire_audit(
    v_user_id, 'DEPRECATED_CALLER', 'LITIGE_OUVERTURE_LEGACY',
    'mission', p_mission_id, NULL,
    jsonb_build_object(
      'mission_id', p_mission_id,
      'motif', left(p_motif, 200),
      'info', 'Appel via wrapper 2-arg DEPRECATED — migration UI incomplète'
    ),
    NULL, NULL
  );

  RETURN public.fn_ouvrir_litige_rate_limited(
    p_mission_id,
    'AUTRE'::public.type_litige,
    p_motif
  );
END;
$$;

COMMENT ON FUNCTION public.fn_ouvrir_litige_rate_limited(UUID, TEXT) IS
  'DEPRECATED + AUDITED (FIX 2). Wrapper rétrocompat 2-arg → 3-arg. '
  'Logge LITIGE_OUVERTURE_LEGACY avant délégation. À supprimer en Sub-PR 3.';

COMMIT;
