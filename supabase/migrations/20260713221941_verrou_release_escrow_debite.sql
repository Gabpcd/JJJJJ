-- Un payout ne peut être préparé qu'après confirmation Stripe du débit.
-- La sélection côté base est volontairement restrictive : l'Edge Function
-- applique ensuite un compare-and-set DEBITE -> RELEASE_PLANIFIE juste avant
-- de créer le payout.
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
  WHERE q.statut = 'EN_ATTENTE'
    AND q.prochaine_tentative_le <= now()
    AND q.tentatives < 5
    AND pe.statut = 'DEBITE'
  ORDER BY q.prochaine_tentative_le ASC
  LIMIT p_limit;
$function$;

REVOKE ALL ON FUNCTION public.fn_escrow_releases_a_traiter(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_escrow_releases_a_traiter(integer) TO service_role;

COMMENT ON FUNCTION public.fn_escrow_releases_a_traiter(integer) IS
  'Retourne uniquement les releases dont le débit Stripe est confirmé (paiements_escrow.statut = DEBITE).';
