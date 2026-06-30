-- Retrait LÉGER d'une candidature EN_ATTENTE (garde-fou « annuler dans la foulée »
-- du Postuler 1-tap depuis l'accueil). À distinguer de fn_annuler_candidature_soignant
-- qui gère l'annulation APRÈS acceptation (motif + texte obligatoires + pénalité de
-- score + notification établissement). Ici : avant toute réponse de l'établissement,
-- retirer une candidature envoyée par erreur n'a aucune conséquence → suppression
-- simple, sans pénalité ni motif. Réservé au propriétaire et au statut EN_ATTENTE.

CREATE OR REPLACE FUNCTION public.fn_retirer_candidature(p_candidature_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_statut text;
  v_owner uuid;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non authentifié');
  END IF;

  SELECT statut, soignant_id INTO v_statut, v_owner
  FROM public.candidatures WHERE id = p_candidature_id;

  IF v_statut IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Candidature introuvable');
  END IF;
  IF v_owner <> v_uid THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non autorisé');
  END IF;
  -- Seules les candidatures encore EN_ATTENTE (pré-réponse étab) sont retirables ici.
  -- Une fois ACCEPTEE/REFUSEE, on passe par le flux d'annulation complet.
  IF v_statut <> 'EN_ATTENTE' THEN
    RETURN jsonb_build_object('success', false, 'error', 'La candidature a déjà été traitée et ne peut plus être retirée ici.');
  END IF;

  DELETE FROM public.candidatures WHERE id = p_candidature_id;
  RETURN jsonb_build_object('success', true);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_retirer_candidature(uuid) TO authenticated;
