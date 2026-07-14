-- Corrige le chemin public de la copie primaire de la lettre D21-031940.
--
-- La page FEHAP qui publie ce document définit une base absolue à la racine :
-- le chemin /jcms/navigation-internet/upload/... ne désigne donc pas le PDF
-- public. Ne pas réécrire les migrations historiques déjà appliquées ; cette
-- migration corrective maintient leur traçabilité et répare les liens servis
-- par fn_mode_exercice.

UPDATE public.matrice_modes_exercice
SET source_url = 'https://www.fehap.fr/upload/docs/application/pdf/2023-02/courrierconjointministeres_30decembre2021_.pdf'
WHERE profession IN ('AUXILIAIRE_PUERICULTURE', 'IBODE', 'IADE')
  AND source_force = 'DOCTRINE'
  AND source_url IS DISTINCT FROM
    'https://www.fehap.fr/upload/docs/application/pdf/2023-02/courrierconjointministeres_30decembre2021_.pdf';
