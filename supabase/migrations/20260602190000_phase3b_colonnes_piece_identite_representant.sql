-- PHASE 3b — Pièce d'identité du représentant (traçabilité + match identité↔dirigeant).
-- Colonnes pour le fichier téléversé (bucket jolene-documents) + le résultat brut de
-- l'extraction IA (diagnostic). Tout document d'identité valable est accepté
-- (CARTE_IDENTITE / PASSEPORT / TITRE_SEJOUR), formats JPG/PNG/PDF.
-- L'edge function verify-piece-identite-etab réutilise le mécanisme de verify-document
-- (Anthropic Vision) pour extraire le nom et le comparer au représentant déclaré, puis
-- écrit representant_identite_verifiee et appelle fn_evaluer_rattachement_etablissement.
ALTER TABLE public.etablissements ADD COLUMN IF NOT EXISTS representant_piece_s3_key text;
ALTER TABLE public.etablissements ADD COLUMN IF NOT EXISTS representant_piece_type_mime text;
ALTER TABLE public.etablissements ADD COLUMN IF NOT EXISTS representant_piece_type_document text;
ALTER TABLE public.etablissements ADD COLUMN IF NOT EXISTS representant_identite_resultat_ia jsonb;

ALTER TABLE public.etablissements DROP CONSTRAINT IF EXISTS etablissements_representant_piece_type_check;
ALTER TABLE public.etablissements ADD CONSTRAINT etablissements_representant_piece_type_check
  CHECK (representant_piece_type_document IS NULL
         OR representant_piece_type_document IN ('CARTE_IDENTITE','PASSEPORT','TITRE_SEJOUR'));
