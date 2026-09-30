-- Cette RPC est classée PUBLIC_VOLONTAIRE : seulement des agrégats, sans
-- identifiant/personne, avec exclusion des comptes et missions de test.
-- Le corps revu reste inchangé ; aucun droit de table n'est accordé.
DO $garde_apercu$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p JOIN private.security_definer_inventory i
      ON i.signature = 'fn_apercu_marche_profession(text,double precision,double precision,integer)'
    WHERE p.oid = 'public.fn_apercu_marche_profession(text,double precision,double precision,integer)'::regprocedure
      AND i.categorie = 'PUBLIC_VOLONTAIRE'
      AND i.definition_md5 = md5(p.prosrc)
      AND md5(p.prosrc) = '5b7729f9eb8449051446821a8a08b3c0'
  ) THEN
    RAISE EXCEPTION 'Corps public aperçu marché divergent : nouvelle revue requise';
  END IF;
END;
$garde_apercu$;

GRANT EXECUTE ON FUNCTION public.fn_apercu_marche_profession(text, double precision, double precision, integer) TO anon;
