-- ============================================================
-- CP-LITIGES-7a FIX 6 — factures_honoraires.statut : ajout 'REMPLACEE'
-- ============================================================
-- `statut` est une colonne TEXT NOT NULL avec un CHECK constraint nommé
-- `factures_honoraires_statut_check` qui accepte aujourd'hui :
--   ('BROUILLON','EMISE','PAYEE','ANNULEE','FACTORISEE','EN_RETARD')
-- Vérifié via MCP execute_sql.
--
-- On ajoute 'REMPLACEE' pour distinguer sémantiquement :
--   ANNULEE  = facture invalide (erreur, test, annulation définitive) ;
--              montant à EXCLURE des stats chiffre d'affaires URSSAF.
--   REMPLACEE = facture annulée techniquement car remplacée par une
--              nouvelle facture (action ANNULER_REEMETTRE de
--              fn_admin_resoudre_litige suite à litige résolu au fond).
--              Montant à EXCLURE aussi (pour éviter double comptage avec
--              la nouvelle facture), mais trace légitime pour l'audit.
--
-- Aucune facture existante n'est en REMPLACEE (pas de backfill).
--
-- Ce FIX livre uniquement la STRUCTURE. Les consommations suivantes sont
-- livrées dans des FIX ultérieurs :
--   - fn_admin_resoudre_litige cas ANNULER_REEMETTRE : SET statut
--     = 'REMPLACEE' au lieu de 'ANNULEE' (FIX 6-consommation RPC).
--   - Triggers d'immutabilité (cp3_fix_targeted_bypass, cp5b_protect_
--     previsionnel_gel) : ajouter 'REMPLACEE' à la liste des statuts
--     modifiables (FIX 6-consommation triggers).
--   - generate-invoice/index.ts:660 : exclure aussi 'REMPLACEE' de la
--     recherche de facture à regénérer (FIX 6-consommation edge).
--   - AdminFacturation.tsx + labels UI : ajouter 'REMPLACEE'
--     (FIX 6-consommation UI, CP-LITIGES-7b).
-- ============================================================

BEGIN;

ALTER TABLE public.factures_honoraires
  DROP CONSTRAINT IF EXISTS factures_honoraires_statut_check;

ALTER TABLE public.factures_honoraires
  ADD CONSTRAINT factures_honoraires_statut_check
  CHECK (statut IN (
    'BROUILLON',
    'EMISE',
    'PAYEE',
    'ANNULEE',
    'FACTORISEE',
    'EN_RETARD',
    'REMPLACEE'
  ));

COMMENT ON COLUMN public.factures_honoraires.statut IS
  'CP-LITIGES-7a FIX 6 — statut comptable de la note d''honoraires. '
  'BROUILLON (pré-émission), EMISE (envoyée à l''étab), PAYEE, '
  'EN_RETARD (échéance dépassée), FACTORISEE (cession affacturage), '
  'ANNULEE (invalide, ex. test ou erreur ; exclue du CA), '
  'REMPLACEE (remplacée techniquement par une nouvelle facture suite '
  'à litige résolu via fn_admin_resoudre_litige ANNULER_REEMETTRE ; '
  'exclue du CA pour éviter le double comptage avec la nouvelle).';

COMMIT;
