-- Create a secure function for soignants to get establishment info (non-sensitive fields only)
CREATE OR REPLACE FUNCTION public.fn_etablissement_pour_soignant(p_etablissement_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_result jsonb;
BEGIN
  -- Verify caller is a soignant with a mission at this establishment
  IF NOT est_soignant() THEN
    RAISE EXCEPTION 'Accès réservé aux soignants';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM missions
    WHERE etablissement_id = p_etablissement_id
      AND soignant_assigne_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Aucune mission associée à cet établissement';
  END IF;

  SELECT jsonb_build_object(
    'id', e.id,
    'nom', e.nom,
    'type', e.type,
    'adresse_rue', e.adresse_rue,
    'adresse_ville', e.adresse_ville,
    'adresse_code_postal', e.adresse_code_postal,
    'adresse_departement', e.adresse_departement,
    'adresse_lat', e.adresse_lat,
    'adresse_lng', e.adresse_lng,
    'telephone_contact', e.telephone_contact,
    'email_contact', e.email_contact
  ) INTO v_result
  FROM etablissements e
  WHERE e.id = p_etablissement_id AND e.supprime_le IS NULL;

  RETURN COALESCE(v_result, '{}'::jsonb);
END;
$$;