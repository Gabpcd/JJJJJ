-- Alignement contrat salarié sur CDD (décision : CDD, pas CDDU).
-- L'effet substantiel est déjà porté par 20260530260000 (fn_calculer_remuneration_mission
-- → 'CDD') et 20260530270000 (fn_traiter_candidature → 'CDD'). Ce fichier existe pour
-- correspondre à la version enregistrée en prod ; il ne fait qu'un reload de schéma.
NOTIFY pgrst, 'reload schema';
