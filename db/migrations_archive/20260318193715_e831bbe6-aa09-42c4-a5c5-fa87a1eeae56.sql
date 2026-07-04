CREATE OR REPLACE FUNCTION public.mon_etablissement_id()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(
    NULLIF(raw_app_meta_data ->> 'etablissement_id', '')::uuid,
    CASE
      WHEN raw_app_meta_data ->> 'role' IN ('ADMIN_ETABLISSEMENT', 'ETABLISSEMENT') THEN id
      ELSE NULL
    END
  )
  FROM auth.users
  WHERE id = auth.uid();
$$;

CREATE OR REPLACE FUNCTION public.est_admin_etablissement()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(
    (SELECT (raw_app_meta_data ->> 'role') IN ('ADMIN_ETABLISSEMENT', 'ETABLISSEMENT')
     FROM auth.users
     WHERE id = auth.uid()),
    false
  );
$$;