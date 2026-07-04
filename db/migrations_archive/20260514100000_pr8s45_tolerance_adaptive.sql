-- PR 8 Sprint 4.5 — Tolérance pointage adaptive
--
-- Réduction de la tolerance par défaut de 500m à 100m (recommandation
-- pour QR-first ; le QR sert de source de vérité primaire, le GPS de
-- double sécurité).
--
-- Constraint élargie : 30m (zone très précise, ex cabinet médical) à
-- 1000m (zone rurale étendue).
--
-- Note Sprint 3 PR 3 avait défini 500 default et range [50, 5000].
-- Sprint 4.5 resserre à 100 default et range [30, 1000] car le QR
-- couvre la sécurité primaire — le GPS sert de cross-check.

-- 1. Drop ancien CHECK + recréer avec nouveau range
ALTER TABLE public.etablissements
  DROP CONSTRAINT IF EXISTS etablissements_tolerance_pointage_m_check;

ALTER TABLE public.etablissements
  ADD CONSTRAINT etablissements_tolerance_pointage_m_check
  CHECK (tolerance_pointage_m BETWEEN 30 AND 1000);

-- 2. Réduire les valeurs hors range actuel à 100
UPDATE public.etablissements
SET tolerance_pointage_m = 100
WHERE tolerance_pointage_m > 1000 OR tolerance_pointage_m < 30;

-- 3. Changer le default
ALTER TABLE public.etablissements
  ALTER COLUMN tolerance_pointage_m SET DEFAULT 100;

COMMENT ON COLUMN public.etablissements.tolerance_pointage_m IS
  'Tolérance pointage GPS en mètres. Default 100m (urbain). Range 30 '
  '(cabinet médical précis) - 1000 (zone rurale étendue). Si l''étab '
  'utilise le QR code (recommandé), cette valeur sert uniquement '
  'd''alerte admin si écart anormal détecté lors du scan GPS background.';

-- 4. Audit
INSERT INTO public.journaux_audit (
  acteur_id, type_acteur, action, type_ressource, id_ressource, details
) VALUES (
  '00000000-0000-0000-0000-000000000000', 'SYSTEME',
  'SYSTEM', 'table', NULL,
  jsonb_build_object(
    'evenement', 'SPRINT45_PR8_TOLERANCE_ADAPTIVE_INSTALLED',
    'pr', 'PR 8 Sprint 4.5',
    'changements', jsonb_build_object(
      'default_avant', 500,
      'default_apres', 100,
      'range_avant', '[50, 5000]',
      'range_apres', '[30, 1000]'
    ),
    'note', 'QR-first reduces GPS tolerance dependency. GPS = cross-check uniquement.'
  )
);
