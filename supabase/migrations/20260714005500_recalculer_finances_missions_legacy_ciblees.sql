-- Recalcule uniquement les missions que l'ancien second moteur financier a
-- laissées avec un plafond Rist impossible. La migration 20260714000629 a
-- supprimé ce moteur ; ce backfill remet les lignes historiques en cohérence
-- avec les trois triggers financiers canoniques.
--
-- La table est verrouillée pendant le changement temporaire du mode des
-- triggers. session_replication_role = replica neutralise tous les triggers
-- métier à effets de bord ; seuls les trois triggers explicitement passés en
-- ALWAYS s'exécutent. Les données de démonstration ne sont ni masquées ni
-- supprimées : seules les colonnes financières des lignes ciblées sont
-- recalculées par les fonctions de production.

LOCK TABLE public.missions IN ACCESS EXCLUSIVE MODE;

DO $verification_triggers$
DECLARE
  v_triggers_financiers integer;
BEGIN
  -- Ne pas lancer le backfill si un autre trigger ALWAYS existe : il pourrait
  -- produire un effet de bord malgré session_replication_role = replica.
  IF EXISTS (
    SELECT 1
      FROM pg_trigger
     WHERE tgrelid = 'public.missions'::regclass
       AND NOT tgisinternal
       AND tgenabled = 'A'
  ) THEN
    RAISE EXCEPTION 'Backfill financier interrompu : un trigger ALWAYS inattendu existe sur public.missions';
  END IF;

  SELECT count(*)
    INTO v_triggers_financiers
    FROM pg_trigger
   WHERE tgrelid = 'public.missions'::regclass
     AND NOT tgisinternal
     AND tgname IN (
       'dec_mission_plafond_rist',
       'dec_mission_z_finance',
       'dec_net_estime'
     )
     AND tgenabled = 'O';

  IF v_triggers_financiers <> 3 THEN
    RAISE EXCEPTION
      'Backfill financier interrompu : les 3 triggers canoniques ne sont pas tous actifs (trouvés : %)',
      v_triggers_financiers;
  END IF;
END;
$verification_triggers$;

CREATE TEMP TABLE missions_finance_legacy_a_recalculer (
  id uuid PRIMARY KEY
) ON COMMIT DROP;

INSERT INTO missions_finance_legacy_a_recalculer (id)
SELECT m.id
  FROM public.missions m
  LEFT JOIN public.etablissements e ON e.id = m.etablissement_id
 WHERE m.rist_plafond_applique IS TRUE
   AND (
     m.soignant_assigne_id IS NULL
     OR NOT COALESCE(e.est_secteur_public, false)
     OR COALESCE(
       m.type_contrat_applique::text,
       NULLIF(upper(btrim(m.choix_contrat_soignant)), ''),
       CASE
         WHEN m.type_contrat_recherche::text = 'SALARIE' THEN 'SALARIE'
         ELSE NULL
       END
     ) IS DISTINCT FROM 'SALARIE'
   );

ALTER TABLE public.missions ENABLE ALWAYS TRIGGER dec_mission_plafond_rist;
ALTER TABLE public.missions ENABLE ALWAYS TRIGGER dec_mission_z_finance;
ALTER TABLE public.missions ENABLE ALWAYS TRIGGER dec_net_estime;

SET LOCAL session_replication_role = replica;

-- Affectation volontairement neutre : elle déclenche le pipeline financier
-- canonique sans changer un champ métier et sans dépendre d'une formule SQL
-- recopiée dans la migration.
UPDATE public.missions AS m
   SET taux_horaire_base = m.taux_horaire_base
  FROM missions_finance_legacy_a_recalculer AS cible
 WHERE cible.id = m.id;

SET LOCAL session_replication_role = origin;

ALTER TABLE public.missions ENABLE TRIGGER dec_mission_plafond_rist;
ALTER TABLE public.missions ENABLE TRIGGER dec_mission_z_finance;
ALTER TABLE public.missions ENABLE TRIGGER dec_net_estime;

DO $verification_resultat$
BEGIN
  IF EXISTS (
    SELECT 1
      FROM public.missions m
      JOIN missions_finance_legacy_a_recalculer cible ON cible.id = m.id
     WHERE m.rist_plafond_applique IS TRUE
        OR m.taux_rist_plafonne IS DISTINCT FROM m.taux_horaire_base
  ) THEN
    RAISE EXCEPTION 'Backfill financier incomplet : une mission ciblée conserve un plafond Rist impossible';
  END IF;
END;
$verification_resultat$;
