-- Le trigger CRM historique initialise prochaine_action_le a now() pour tout
-- nouveau contact. Le radar d'acquisition est volontairement plus strict :
-- apres l'upsert, il remet toujours la sequence en pause et vide l'echeance.

CREATE OR REPLACE FUNCTION public.fn_admin_acquisition_ajouter_crm(p_signal_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $fn$
DECLARE
  v_signal public.acquisition_signaux%ROWTYPE;
  v_contact_id uuid;
BEGIN
  IF NOT public.est_admin() THEN
    RAISE EXCEPTION 'Acces admin requis' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_signal
  FROM public.acquisition_signaux
  WHERE id = p_signal_id
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Signal introuvable'; END IF;

  INSERT INTO public.sales_contacts (
    type, nom, profession, ville, departement, finess, statut, notes,
    source_prospect_type, source_prospect_id, source_donnees, score_sourcing,
    sequence_active, prochaine_action_le, sequence_etape, ne_plus_contacter
  ) VALUES (
    'ETABLISSEMENT', v_signal.nom_etablissement, v_signal.profession,
    v_signal.ville, v_signal.departement, v_signal.finess, 'PROSPECT',
    'Signal de demande : ' || v_signal.intitule || E'\nSource : '
      || COALESCE(v_signal.source_url, v_signal.source_code),
    'ETABLISSEMENT', 'SIGNAL:' || v_signal.id::text, v_signal.source_code,
    v_signal.score_demande, false, NULL, 0, false
  )
  ON CONFLICT (source_prospect_type, source_prospect_id)
    WHERE source_prospect_type IS NOT NULL AND source_prospect_id IS NOT NULL
  DO UPDATE SET
    notes = EXCLUDED.notes,
    score_sourcing = EXCLUDED.score_sourcing,
    sequence_active = false,
    prochaine_action_le = NULL,
    maj_le = now()
  RETURNING id INTO v_contact_id;

  -- Le trigger BEFORE INSERT de la file CRM remplit une echeance par defaut.
  -- Ce second verrou garantit l'etat silencieux sur INSERT comme sur UPDATE.
  UPDATE public.sales_contacts
     SET sequence_active = false,
         prochaine_action_le = NULL,
         maj_le = now()
   WHERE id = v_contact_id;

  UPDATE public.acquisition_signaux
     SET statut = 'CRM', maj_le = now()
   WHERE id = p_signal_id;

  RETURN jsonb_build_object(
    'success', true,
    'contact_id', v_contact_id,
    'sequence_active', false,
    'prochaine_action_le', NULL,
    'contact_automatique', false
  );
END;
$fn$;

REVOKE ALL ON FUNCTION public.fn_admin_acquisition_ajouter_crm(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_admin_acquisition_ajouter_crm(uuid) TO authenticated, service_role;

COMMENT ON FUNCTION public.fn_admin_acquisition_ajouter_crm(uuid) IS
  'Ajoute manuellement un signal au CRM avec sequence desactivee et aucune echeance ; aucun contact automatique.';
