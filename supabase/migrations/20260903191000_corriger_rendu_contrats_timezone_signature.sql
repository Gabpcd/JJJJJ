-- Corrige le rendu juridique des contrats générés :
-- - la période d'essai s'accorde au singulier/pluriel ;
-- - le texte ne prétend plus qu'une signature manuscrite a utilisé un OTP SMS.

UPDATE public.templates_contrat
SET
  contenu_html = replace(
    replace(
      contenu_html,
      '{{periode_essai_jours}} jours',
      '{{periode_essai_libelle}}'
    ),
    'en deux exemplaires électroniques signés via OTP SMS Jolene',
    'en deux exemplaires signés électroniquement dans Jolene'
  ),
  variables = CASE
    WHEN variables ? 'periode_essai_jours'
      THEN (variables - 'periode_essai_jours') || '["periode_essai_libelle"]'::jsonb
    ELSE variables
  END,
  modifie_le = now()
WHERE contenu_html LIKE '%{{periode_essai_jours}} jours%'
   OR contenu_html LIKE '%en deux exemplaires électroniques signés via OTP SMS Jolene%';

DO $assertions$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.templates_contrat
    WHERE contenu_html LIKE '%{{periode_essai_jours}} jours%'
       OR contenu_html LIKE '%en deux exemplaires électroniques signés via OTP SMS Jolene%'
  ) THEN
    RAISE EXCEPTION 'Le rendu des contrats contient encore une formulation obsolète';
  END IF;
END
$assertions$;
