-- Fenêtre de contestation des présences portée à 72 h (18/11/2026).
--
-- Décision D12 de docs/mobile-swift/DECISIONS_LOT2.md (Q9, 8 novembre 2026),
-- point 2 : contenu exact de la migration de paramétrage.
--
-- Constat (lecture seule, prod, 18/11/2026) : parametres_litiges porte
-- delai_contestation_pointage_h = '48' (« Fenêtre 48h post-pointage pour
-- contester présence. », semé par 20260417130000_cp_litiges_1_ddl). Le web
-- annonce 72 h (« Vous avez 72 h après la validation pour contester. »,
-- PanneauContestation.tsx) et les CGU §4.6 prévoient l'auto-validation des
-- présences après 72 heures sans contestation.
--
-- Effet : passe la valeur à 72. Deux lecteurs live (supabase/schema/public.sql) :
--   - fn_fenetre_contestation_ouverte : la contestation DESACCORD_HEURES_POINTAGE
--     (et ABSENCE_SOIGNANT, DEPART_ANTICIPE, RETARD_IMPORTANT) reste ouverte
--     72 h après valide_le au lieu de 48 h ; le défaut 48 du code (COALESCE)
--     ne change pas ;
--   - fn_auto_creation_litiges_presence (cron) : les litiges ABSENCE_SOIGNANT
--     et DEPART_ANTICIPE sont créés après 72 h au lieu de 48 h, une fois la
--     fenêtre fermée (même paramètre, cohérence conservée).
--
-- Sources (force) :
--   - Code civil, art. 1110 et 1190 (contrat d'adhésion, interprété contre
--     celui qui l'a proposé) et art. 1104 (bonne foi) : TEXTE ;
--   - CGU §4.6 (src/pages/PageCGU.tsx) : auto-validation après 72 heures,
--     aucun délai de contestation fixé : TEXTE CONTRACTUEL JOLENE ;
--   - valeur 72 h : CHOIX DE CONFORMITÉ JOLENE (favorable au soignant).
--
-- Catégorie B9 (écrasement d'une valeur de production) + HARD STOP n°4 :
-- validation explicite de Gabrielle requise avant merge. Idempotente.

INSERT INTO public.parametres_litiges (cle, valeur, description)
VALUES (
  'delai_contestation_pointage_h',
  '72',
  'Fenêtre 72 h après validation pour contester une présence (Q9, DECISIONS_LOT2 D12).'
)
ON CONFLICT (cle) DO UPDATE
  SET valeur = EXCLUDED.valeur,
      description = EXCLUDED.description,
      modifie_le = now();
