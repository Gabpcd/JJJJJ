-- B1/B7 — Backfill `type_contrat_applique` sur les missions TERMINEE (le seul
-- périmètre qui alimente les charges = réalisé). La colonne se fige normalement
-- à l'acceptation (fn_traiter_candidature / fn_assigner_mission_admin) ; les NULL
-- restants sont du legacy (missions assignées avant cette logique, ou seedées).
--
-- Garde-fou : NULL = « régime non déterminé » → exclu du calcul, JAMAIS compté 0 €.
-- On ne devine pas : Passe 1 = cas certains depuis type_contrat_recherche ;
-- Passe 2 = cas ambigus (TOUS/multi) dérivés de l'artefact réel de fin de mission
-- (bulletin → SALARIE, facture honoraires → LIBERAL). Aucun artefact → reste NULL.
-- Idempotent (WHERE type_contrat_applique IS NULL).

-- Passe 1 — régime certain depuis le type de contrat recherché.
UPDATE public.missions
   SET type_contrat_applique = 'LIBERAL'::type_contrat_applique_enum
 WHERE statut = 'TERMINEE'
   AND type_contrat_applique IS NULL
   AND type_contrat_recherche = 'LIBERAL';

UPDATE public.missions
   SET type_contrat_applique = 'SALARIE'::type_contrat_applique_enum
 WHERE statut = 'TERMINEE'
   AND type_contrat_applique IS NULL
   AND type_contrat_recherche IN ('SALARIE', 'CDD', 'VACATION');

-- Passe 2 — cas ambigus (TOUS / multi) : dérivés de l'artefact réel.
-- Bulletin de paie émis ⇒ la mission a été traitée en SALARIE.
UPDATE public.missions m
   SET type_contrat_applique = 'SALARIE'::type_contrat_applique_enum
 WHERE m.statut = 'TERMINEE'
   AND m.type_contrat_applique IS NULL
   AND EXISTS (SELECT 1 FROM public.bulletins_paie b WHERE b.mission_id = m.id);

-- Facture d'honoraires émise ⇒ traitée en LIBERAL (n'écrase pas la passe bulletin).
UPDATE public.missions m
   SET type_contrat_applique = 'LIBERAL'::type_contrat_applique_enum
 WHERE m.statut = 'TERMINEE'
   AND m.type_contrat_applique IS NULL
   AND EXISTS (SELECT 1 FROM public.factures_honoraires f WHERE f.mission_id = m.id);

-- Les missions TERMINEE encore NULL restent « non déterminées » : non comptées.
