-- Un worker peut mourir après l'appel Stripe mais avant la persistance du
-- payout. La file EN_COURS est donc un lease récupérable et un escrow déjà
-- RELEASE_PLANIFIE doit rester sélectionnable jusqu'au rattachement exact du
-- payout, sans jamais être rétrogradé automatiquement vers DEBITE.
CREATE OR REPLACE FUNCTION public.fn_escrow_releases_a_traiter(
  p_limit integer DEFAULT 50
)
RETURNS TABLE(
  queue_id uuid,
  paiement_escrow_id uuid,
  mission_id uuid,
  soignant_id uuid,
  etablissement_id uuid,
  honoraires_cents integer,
  escrow_statut text,
  tentatives integer
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT q.id,
         q.paiement_escrow_id,
         q.mission_id,
         pe.soignant_id,
         pe.etablissement_id,
         pe.honoraires_cents,
         pe.statut,
         q.tentatives
  FROM public.escrow_release_queue q
  JOIN public.paiements_escrow pe ON pe.id = q.paiement_escrow_id
  WHERE q.statut IN ('EN_ATTENTE', 'EN_COURS')
    AND q.prochaine_tentative_le <= now()
    AND (
      (pe.statut = 'DEBITE' AND q.tentatives < 5)
      OR pe.statut = 'RELEASE_PLANIFIE'
    )
  ORDER BY q.prochaine_tentative_le ASC
  LIMIT p_limit;
$function$;

REVOKE ALL ON FUNCTION public.fn_escrow_releases_a_traiter(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_escrow_releases_a_traiter(integer) TO service_role;

COMMENT ON FUNCTION public.fn_escrow_releases_a_traiter(integer) IS
  'Retourne les releases DEBITE à initier et les RELEASE_PLANIFIE/leases EN_COURS à réconcilier sans double payout.';
