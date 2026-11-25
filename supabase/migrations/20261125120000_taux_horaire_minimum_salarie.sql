-- Taux horaire minimal d'une mission salariée : paramètre vérifié par le serveur.
--
-- Défaut corrigé : le formulaire web (FormulaireMission.tsx, attribut min du champ) et l'app iOS
-- (LibellesWeb.Publication.tauxMinimumHorsLiberal) codaient en dur 11,65 €/h, sous le SMIC horaire
-- brut en vigueur depuis le 1er juin 2026 : 12,31 € (arrêté du 22 mai 2026 portant relèvement du
-- salaire minimum de croissance, JORF n° 0121 du 24 mai 2026,
-- https://www.legifrance.gouv.fr/loda/id/JORFTEXT000054126589/ ; Code du travail L3231-1 et
-- suivants, sanction R3233-1). Le serveur ne refusait qu'un taux <= 0.
--
-- 1. Paramètre parametres_systeme.taux_horaire_minimum_salarie (table paramétrée de CLAUDE.md,
--    aucun seuil juridique en dur dans une fonction). Unité : euros brut par heure, la même que
--    missions.taux_horaire_base (numeric en euros, CHECK chk_taux_horaire_raisonnable) : comparaison
--    directe, sans conversion. Bornes 12,31 à 100 : fn_admin_maj_parametre refuse une valeur hors
--    bornes, donc le plancher ne peut pas être abaissé sous le SMIC de juin 2026 depuis l'interface ;
--    un relèvement du SMIC se fait en remontant la valeur (et la borne basse par migration).
--    ON CONFLICT DO NOTHING : un rejeu n'écrase jamais un réglage de l'administrateur.
--
-- 2. Verrou en un seul point : deux déclencheurs de contrainte DIFFÉRÉS sur public.missions (création,
--    et mise à jour qui change taux_horaire_base ou type_contrat_recherche), une seule fonction
--    private.fn_trg_verifier_taux_minimum_salarie. Pourquoi différés : les RPC de création insèrent la
--    mission en TOUS (défaut de colonne) puis appliquent le type demandé par fn_modifier_type_contrat_mission
--    dans la même transaction, et elles attrapent toute exception (WHEN OTHERS → « temporairement
--    indisponible »). Contrôlé à la validation de la transaction, le verrou lit l'état FINAL de la ligne
--    (une mission LIBERAL n'est jamais refusée) et son message atteint l'utilisateur tel quel.
--    Champ d'application :
--      - SALARIE et TOUS : refus sous le plancher (une mission TOUS peut être pourvue en salarié au taux
--        publié ; dec_valider_type_contrat_mission la restreint d'ailleurs à SALARIE pour les professions
--        salariées seules) ;
--      - LIBERAL (honoraires) : jamais concerné ;
--      - mise à jour qui ne touche ni le taux ni le type (statut, assignation, gel, crons) : le
--        déclencheur ne s'exécute pas (clause WHEN) ;
--      - contexte système sans requête API (pg_cron, migrations, SQL d'administration : aucun
--        request.jwt.claims) : non contrôlé, pour qu'aucun cron ne soit annulé à la validation. Une
--        requête PostgREST, y compris service_role (API établissement, edge api-v1), reste contrôlée.
--    Paramètre absent : refus explicite (un gap connu reste verrouillé), jamais un plancher implicite.
--
-- 3. Lecture : fn_taux_horaire_minimum_salarie() (site, et app iOS si elle s'y raccorde un jour), GRANT
--    authenticated et service_role (fonction neuve : aucun grant hérité, CLAUDE.md).
--
-- Garde de parité : tests/node/taux-horaire-minimum-salarie.node.mjs (valeur de cette migration =
-- repli du site = constante de l'app). Test du verrou : tests/postgres/taux-horaire-minimum-salarie.pg17.mjs.
-- HARD STOP n°4 : règle juridique exposée à l'utilisateur (points 1 à 3 validés le 25/11/2026) ; B9 : go humain.
--
-- Verrous : la création des déclencheurs prend un verrou SHARE ROW EXCLUSIVE sur public.missions. lock_timeout
-- borne l'attente à 5 s (même pratique que 20261124123500) : si le délai expire, la migration échoue en entier
-- (aucun objet créé, la transaction de la CLI est annulée) et le workflow deploy-supabase est à relancer ; les
-- écritures sur missions ne restent jamais bloquées derrière elle.
-- Aucun BEGIN/COMMIT : la CLI ou le banc appelant possède la transaction.
SET LOCAL lock_timeout = '5s';

INSERT INTO public.parametres_systeme(cle,valeur,label,description,unite,val_min,val_max,categorie,avertissement,cablee)
VALUES('taux_horaire_minimum_salarie',12.31,'Taux horaire minimal d''une mission salariée (€/h brut)',
 'Plancher du taux horaire brut d''une mission salariée ou ouverte à tous les profils (TOUS), contrôlé par le serveur à la création et à chaque modification du taux ou du type de contrat ; lu par le site et par l''app. Valeur : SMIC horaire brut au 1er juin 2026, 12,31 € (arrêté du 22 mai 2026 portant relèvement du salaire minimum de croissance, JORF n° 0121 du 24 mai 2026 ; Code du travail L3231-1 et suivants). Les missions libérales (honoraires) ne sont pas concernées.',
 '€/h brut',12.31,100,'FINANCE','Valeur légale : ne jamais l''abaisser sous le SMIC horaire brut en vigueur. À relever à chaque revalorisation du SMIC (le site et l''app la relisent ; leurs valeurs de repli se corrigent par PR).',true)
ON CONFLICT(cle) DO NOTHING;

CREATE OR REPLACE FUNCTION public.fn_taux_horaire_minimum_salarie()
RETURNS numeric
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $body$
  SELECT p.valeur FROM public.parametres_systeme p WHERE p.cle = 'taux_horaire_minimum_salarie';
$body$;

COMMENT ON FUNCTION public.fn_taux_horaire_minimum_salarie() IS
  'Taux horaire minimal (€/h brut) d''une mission SALARIE ou TOUS, paramètre taux_horaire_minimum_salarie ; NULL si absent.';

REVOKE ALL ON FUNCTION public.fn_taux_horaire_minimum_salarie() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_taux_horaire_minimum_salarie() TO authenticated, service_role;

CREATE OR REPLACE FUNCTION private.fn_trg_verifier_taux_minimum_salarie()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $body$
DECLARE
  v_type text;
  v_taux numeric;
  v_minimum numeric;
BEGIN
  -- Contexte système (pg_cron, migration, SQL d'administration) : aucune requête API en cours.
  IF NULLIF(pg_catalog.current_setting('request.jwt.claims', true), '') IS NULL
     AND NULLIF(pg_catalog.current_setting('request.jwt.claim.sub', true), '') IS NULL
     AND NULLIF(pg_catalog.current_setting('request.jwt.claim.role', true), '') IS NULL THEN
    RETURN NULL;
  END IF;

  -- Déclencheur différé : état final de la ligne à la validation de la transaction.
  SELECT m.type_contrat_recherche, m.taux_horaire_base
    INTO v_type, v_taux
    FROM public.missions m
   WHERE m.id = NEW.id;
  IF NOT FOUND OR v_type = 'LIBERAL' THEN
    RETURN NULL;
  END IF;

  SELECT p.valeur INTO v_minimum
    FROM public.parametres_systeme p
   WHERE p.cle = 'taux_horaire_minimum_salarie';
  IF v_minimum IS NULL THEN
    RAISE EXCEPTION 'Le taux horaire minimal d''une mission salariée n''est pas paramétré : publication suspendue. Contactez l''assistance Jolene.'
      USING ERRCODE = 'P0001',
            HINT = 'TAUX_HORAIRE_MINIMUM_NON_PARAMETRE',
            DETAIL = 'parametres_systeme.taux_horaire_minimum_salarie absent (migration 20261125120000_taux_horaire_minimum_salarie.sql).';
  END IF;

  IF v_taux < v_minimum THEN
    RAISE EXCEPTION 'Le taux horaire doit être d''au moins % €/h.',
      pg_catalog.replace(pg_catalog.to_char(v_minimum, 'FM9999990.00'), '.', ',')
      USING ERRCODE = 'P0001',
            HINT = 'TAUX_HORAIRE_SOUS_MINIMUM_SALARIE';
  END IF;
  RETURN NULL;
END;
$body$;

COMMENT ON FUNCTION private.fn_trg_verifier_taux_minimum_salarie() IS
  'Verrou différé : refuse une mission SALARIE ou TOUS dont le taux horaire est sous parametres_systeme.taux_horaire_minimum_salarie (création, ou modification du taux ou du type). Migration 20261125120000.';

REVOKE ALL ON FUNCTION private.fn_trg_verifier_taux_minimum_salarie() FROM PUBLIC, anon, authenticated;

DO $body$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_trigger
                  WHERE tgrelid = 'public.missions'::regclass
                    AND tgname = 'trg_zz_taux_minimum_salarie_creation') THEN
    CREATE CONSTRAINT TRIGGER trg_zz_taux_minimum_salarie_creation
      AFTER INSERT ON public.missions
      DEFERRABLE INITIALLY DEFERRED
      FOR EACH ROW
      EXECUTE FUNCTION private.fn_trg_verifier_taux_minimum_salarie();
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_trigger
                  WHERE tgrelid = 'public.missions'::regclass
                    AND tgname = 'trg_zz_taux_minimum_salarie_modification') THEN
    CREATE CONSTRAINT TRIGGER trg_zz_taux_minimum_salarie_modification
      AFTER UPDATE ON public.missions
      DEFERRABLE INITIALLY DEFERRED
      FOR EACH ROW
      WHEN (OLD.taux_horaire_base IS DISTINCT FROM NEW.taux_horaire_base
            OR OLD.type_contrat_recherche IS DISTINCT FROM NEW.type_contrat_recherche)
      EXECUTE FUNCTION private.fn_trg_verifier_taux_minimum_salarie();
  END IF;
END;
$body$;

-- Inventaire des fonctions SECURITY DEFINER (comme 20261118152150 et 20261124123500).
INSERT INTO private.security_definer_inventory (signature, categorie, definition_md5, justification, recense_le)
SELECT 'fn_taux_horaire_minimum_salarie()', 'RPC_UTILISATEUR_AUTH_INTERNE', pg_catalog.md5(p.prosrc),
       'Lecture seule de parametres_systeme.taux_horaire_minimum_salarie (une valeur numérique, aucune donnée personnelle) ; EXECUTE authenticated et service_role, REVOKE PUBLIC et anon. Source : 20261125120000_taux_horaire_minimum_salarie.sql',
       pg_catalog.now()
FROM pg_catalog.pg_proc p
WHERE p.oid = 'public.fn_taux_horaire_minimum_salarie()'::pg_catalog.regprocedure
ON CONFLICT (signature) DO UPDATE
SET categorie = EXCLUDED.categorie,
    definition_md5 = EXCLUDED.definition_md5,
    justification = EXCLUDED.justification,
    recense_le = EXCLUDED.recense_le;

INSERT INTO private.security_definer_inventory (signature, categorie, definition_md5, justification, recense_le)
SELECT 'private.fn_trg_verifier_taux_minimum_salarie()', 'SERVICE_ONLY_REVOQUE', pg_catalog.md5(p.prosrc),
       'Fonction de déclencheur différé sur public.missions (création, modification du taux ou du type) : relit la ligne et le paramètre, lève une exception ; aucune écriture. REVOKE PUBLIC, anon et authenticated. Source : 20261125120000_taux_horaire_minimum_salarie.sql',
       pg_catalog.now()
FROM pg_catalog.pg_proc p
WHERE p.oid = 'private.fn_trg_verifier_taux_minimum_salarie()'::pg_catalog.regprocedure
ON CONFLICT (signature) DO UPDATE
SET categorie = EXCLUDED.categorie,
    definition_md5 = EXCLUDED.definition_md5,
    justification = EXCLUDED.justification,
    recense_le = EXCLUDED.recense_le;
