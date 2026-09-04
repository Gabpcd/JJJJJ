-- Le contrat ne doit ni présenter les majorations Jolene comme des minima
-- légaux universels, ni interdire sans nuance les gardes de 12 h que la loi
-- permet lorsqu'une dérogation applicable existe (C. trav. L3121-18 et -19).

UPDATE public.templates_contrat
SET contenu_html = replace(
      replace(
        contenu_html,
        'majorations légales incluses (nuit ≥ 25%, dimanche ≥ 25%, jour férié ≥ 50%) ou conventionnelles selon la CCN applicable',
        'les majorations éventuelles de nuit, de dimanche et de jour férié sont déterminées par les dispositions légales et conventionnelles applicables'
      ),
      'Le Salarié s''engage à respecter les durées maximales légales : 10h/jour (L3121-18), 48h/semaine absolu (L3121-20), 44h moyenne sur 12 semaines (L3121-22), et les repos minimums : 11h entre deux journées (L3131-1), 35h hebdomadaire (L3132-2).',
      'La durée quotidienne de principe est de 10 heures (L3121-18). Tout dépassement suppose qu''une dérogation légale, réglementaire ou conventionnelle applicable le permette, sans excéder 12 heures (L3121-19). L''Employeur garantit l''applicabilité de cette dérogation pour tout créneau concerné. Restent applicables les plafonds de 48 heures sur une semaine et de 44 heures en moyenne sur douze semaines, ainsi que les repos minimums de 11 heures entre deux journées et de 35 heures par semaine.'
    ),
    modifie_le = now()
WHERE est_actif = true
  AND type_contrat IN ('CDD', 'CDDU', 'VACATION')
  AND (
    contenu_html LIKE '%majorations légales incluses (nuit ≥ 25%%'
    OR contenu_html LIKE '%10h/jour (L3121-18)%'
  );

DO $assertions$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.templates_contrat
    WHERE est_actif = true
      AND type_contrat IN ('CDD', 'CDDU', 'VACATION')
      AND (
        contenu_html LIKE '%majorations légales incluses (nuit ≥ 25%%'
        OR contenu_html LIKE '%10h/jour (L3121-18)%'
      )
  ) THEN
    RAISE EXCEPTION 'Le modèle CDD contient encore une formulation légale contradictoire';
  END IF;
END
$assertions$;
