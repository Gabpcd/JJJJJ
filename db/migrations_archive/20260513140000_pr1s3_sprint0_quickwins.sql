-- PR 1 Sprint 3 — Sprint 0 quick wins F-1 + F-2 + F-4
--
-- Reprise des fixes P0 du rapport docs/AUDIT_WORKFLOW_CRITIQUE.md qui
-- n'avaient jamais été appliqués.
--
-- F-1 + F-2 : colonne presences.depart_modele_terminal manquante
--   → fn_pointer_depart, fn_purger_gps_ancien, fn_supprimer_mon_compte
--     plantent toutes (référence colonne inexistante)
--   → impact : aucun soignant ne peut clôturer une mission via GPS
--
-- F-4 : service_role n'a pas le grant DELETE sur tokens_push
--   → cleanup des tokens push expirés impossible (send-push.ts:147-151)

-- 1. F-1 + F-2 — Ajout colonne depart_modele_terminal (symétrie avec
--    arrivee_modele_terminal qui existe déjà)
ALTER TABLE public.presences
  ADD COLUMN IF NOT EXISTS depart_modele_terminal text;

COMMENT ON COLUMN public.presences.depart_modele_terminal IS
  'Modèle du terminal utilisé pour pointer le départ (audit/forensic). '
  'Symétrie avec arrivee_modele_terminal. Renseigné par fn_pointer_depart.';

-- 2. F-4 — GRANT DELETE sur tokens_push pour service_role
GRANT DELETE ON public.tokens_push TO service_role;

-- 3. Audit
INSERT INTO public.journaux_audit (
  acteur_id, type_acteur, action, type_ressource, id_ressource, details
) VALUES (
  '00000000-0000-0000-0000-000000000000', 'SYSTEME',
  'SYSTEM', 'table', NULL,
  jsonb_build_object(
    'evenement', 'SPRINT3_PR1_SPRINT0_QUICKWINS_INSTALLED',
    'pr', 'PR 1 Sprint 3',
    'fixes_appliques', ARRAY[
      'F-1: presences.depart_modele_terminal column added',
      'F-2: fn_purger_gps_ancien + fn_supprimer_mon_compte now functional',
      'F-4: GRANT DELETE ON tokens_push TO service_role'
    ],
    'note', 'Sprint 0 quick wins jamais lancés du PR #69 audit'
  )
);
