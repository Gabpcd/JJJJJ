-- Un Customer Stripe ne peut appartenir qu'a un seul établissement Jolene.
-- Le helper Edge s'appuie sur cet invariant pour arbitrer les courses CAS.
-- Les Customers historiques sans metadata tenant restent bloqués jusqu'à leur
-- audit et leur backfill manuel : l'unicité DB seule ne prouve pas la propriété.

DO $customer_stripe_uniqueness$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.etablissements
    WHERE stripe_customer_id IS NOT NULL
    GROUP BY stripe_customer_id
    HAVING count(*) > 1
  ) THEN
    RAISE EXCEPTION
      'Migration refusée : un Customer Stripe est rattaché à plusieurs établissements';
  END IF;
END;
$customer_stripe_uniqueness$;

CREATE UNIQUE INDEX IF NOT EXISTS uniq_etablissements_stripe_customer_id
  ON public.etablissements (stripe_customer_id)
  WHERE stripe_customer_id IS NOT NULL;

COMMENT ON INDEX public.uniq_etablissements_stripe_customer_id IS
  'Isolation tenant : un Customer Stripe ne peut être rattaché qu''à un établissement Jolene.';
