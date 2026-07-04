-- Vérification IA du RIB établissement.
--
-- FinaliserInscriptionEtab téléverse le RIB de l'établissement (jolene-documents,
-- etablissements.rib_s3_key) SANS aucune vérification IA. Ce RIB sert aux opérations
-- de paiement (prélèvement commission / virements). On ajoute les colonnes de
-- résultat ; la vérification est faite par l'edge function verify-rib-etablissement
-- (Anthropic Vision) : confirme que c'est un RIB et que le titulaire correspond à
-- l'établissement.

ALTER TABLE public.etablissements
  ADD COLUMN IF NOT EXISTS rib_ia_resultat jsonb,
  ADD COLUMN IF NOT EXISTS rib_ia_coherent boolean,
  ADD COLUMN IF NOT EXISTS rib_ia_verifie_le timestamptz;
