-- Métadonnées seulement : onze corps rapprochés individuellement de main 58fda7df.
-- Aucun remplacement de fonction, GRANT ou recapture globale.
-- fn_terminer_mission et fn_admin_resoudre_litige_intelligent sont exclus :
-- leur provenance expliquée ne suffit pas à valider leurs gardes.
DO $inventory$
DECLARE
  v_entries constant jsonb := $entries$[
  {
    "signature": "fn_admin_creer_litige_force(uuid,type_litige,text,text)",
    "old_md5": "a0a1c520b65d7f9a9f62ec9d7599b4f5",
    "definition_md5": "6d05f57097fa2aff068b70a0de48b824",
    "categorie": "ADMIN_EST_ADMIN_VALIDE",
    "proconfig": [
      "search_path=public"
    ],
    "anon_execute": false,
    "justification": "UID non NULL + est_admin() ; motif et justification de contournement contrôlés, audit. Source : 20260903212000_reparer_creation_litige_admin.sql"
  },
  {
    "signature": "fn_admin_resoudre_litige_salarie(uuid,text,text,numeric,numeric,text)",
    "old_md5": null,
    "definition_md5": "139ca12a3fcbff5bd5f65074d3242b53",
    "categorie": "ADMIN_EST_ADMIN_VALIDE",
    "proconfig": [
      "search_path=public"
    ],
    "anon_execute": false,
    "justification": "UID non NULL + est_admin() IS TRUE, validation des montants, verrouillage et audit. Source : 20260903203000_resoudre_litiges_paie_salariee.sql"
  },
  {
    "signature": "fn_capacite_alertes_recherches()",
    "old_md5": null,
    "definition_md5": "9dc1e6aaacd4c1bc19aea8c13caa4ddf",
    "categorie": "RPC_UTILISATEUR_AUTH_INTERNE",
    "proconfig": [
      "search_path=\"\""
    ],
    "anon_execute": false,
    "justification": "Booléen seulement : UID + destinataire établissement actif canonique + activité du worker < 3 h. Source : 20260925093121_alertes_recherches_etablissement_exactes.sql"
  },
  {
    "signature": "fn_creer_filtre_sauvegarde(text,filtre_audience,jsonb,boolean,filtre_frequence_alerte)",
    "old_md5": "b19d7a1b48dc83f363a9e7941c210ca6",
    "definition_md5": "e58c251bdecbe4f8a40c8916b89195dd",
    "categorie": "RPC_UTILISATEUR_AUTH_INTERNE",
    "proconfig": [
      "search_path=public, extensions"
    ],
    "anon_execute": false,
    "justification": "UID propriétaire du filtre ; destinataire actif, audience et critères validés ; capacité worker exigée pour activer les alertes établissement. Source : 20260925093121_alertes_recherches_etablissement_exactes.sql"
  },
  {
    "signature": "fn_missions_publiques_recherche(text,text)",
    "old_md5": "c259d4330d8d660dc84e0661fe512ecc",
    "definition_md5": "6b2201b85728a6541fc6a46bdd390fb0",
    "categorie": "PUBLIC_VOLONTAIRE",
    "proconfig": [
      "search_path=public"
    ],
    "anon_execute": true,
    "justification": "Accès anonyme volontaire, projection publique, missions ouvertes futures, établissements vérifiés publiants non supprimés et non tests ; restrictions métier conservées. Source : 20260925153200_recherche_missions_comptage_unique.sql"
  },
  {
    "signature": "fn_modifier_filtre_sauvegarde(uuid,text,boolean,filtre_frequence_alerte)",
    "old_md5": "7d154326823815661450c4791be2afe7",
    "definition_md5": "9fa49350ff5ed888e5bbdd29f7399dd6",
    "categorie": "RPC_UTILISATEUR_AUTH_INTERNE",
    "proconfig": [
      "search_path=public, extensions"
    ],
    "anon_execute": false,
    "justification": "Filtre id ET utilisateur_id=auth.uid ; activation revérifie destinataire actif, critères et capacité ; renommage/désactivation restent accessibles au propriétaire. Source : 20260925093121_alertes_recherches_etablissement_exactes.sql"
  },
  {
    "signature": "fn_rechercher_soignants_etab(text,text[],text,integer,text,numeric,integer,integer,boolean,boolean,text,integer,integer)",
    "old_md5": "e8f0fd0eacd824c7c83e78ae10b9823d",
    "definition_md5": "5a1fc4a4651f794ca8d95c3f6885195a",
    "categorie": "MIXTE_TENANT_ADMIN",
    "proconfig": [
      "search_path=public, extensions"
    ],
    "anon_execute": false,
    "justification": "Compte auth actif ; admin ou tenant canonique existant non supprimé ; projection professionnelle et nom limité à initiale. Source : 20260925093121_alertes_recherches_etablissement_exactes.sql"
  },
  {
    "signature": "fn_supprimer_compte_etablissement_rate_limited()",
    "old_md5": "ee70f41814b5ed75492aed48bd6361a4",
    "definition_md5": "db6d6e1ec53b7f743e4372810ed9d98c",
    "categorie": "RPC_UTILISATEUR_AUTH_INTERNE",
    "proconfig": [
      "search_path=\"\""
    ],
    "anon_execute": false,
    "justification": "UID obligatoire ; reçu privé confirmé autorise la reprise idempotente ; sinon limitation 1/jour puis suppression du seul établissement propre. Source : 20260925150546_suppression_compte_preuve_privee.sql"
  },
  {
    "signature": "fn_supprimer_compte_rate_limited()",
    "old_md5": "a9e11b49415beec8c724e52465bd4cc2",
    "definition_md5": "f283e828e173bf12d8f633be28431c97",
    "categorie": "RPC_UTILISATEUR_AUTH_INTERNE",
    "proconfig": [
      "search_path=\"\""
    ],
    "anon_execute": false,
    "justification": "UID obligatoire ; reçu privé confirmé autorise la reprise idempotente ; sinon limitation 1/jour puis suppression du seul compte propre. Source : 20260925150546_suppression_compte_preuve_privee.sql"
  },
  {
    "signature": "fn_supprimer_mon_compte()",
    "old_md5": "6ef2d23196777974b1db5e9047ed6e63",
    "definition_md5": "71254d2065c67c11ce0460368f20d01f",
    "categorie": "RPC_UTILISATEUR_AUTH_INTERNE",
    "proconfig": [
      "search_path=public, extensions"
    ],
    "anon_execute": false,
    "justification": "UID égal au profil soignant ciblé, verrou et refus des missions en cours/futures ; preuve privée d’anonymisation. La suspension ne supprime pas le droit de demander sa propre suppression. Source : 20260925150546_suppression_compte_preuve_privee.sql"
  },
  {
    "signature": "fn_supprimer_mon_compte_etablissement()",
    "old_md5": "d99c5d3199ef860fdc71ba17b26ddbaf",
    "definition_md5": "8d1a6220cdc135d36d2d472fcde230ee",
    "categorie": "RPC_UTILISATEUR_AUTH_INTERNE",
    "proconfig": [
      "search_path=public, extensions"
    ],
    "anon_execute": false,
    "justification": "UID égal au propriétaire historique ciblé, pas un tenant arbitraire ; verrou, missions et impayés contrôlés ; preuve privée. Un simple membre ne supprime pas son employeur. Source : 20260925150546_suppression_compte_preuve_privee.sql"
  }
]$entries$::jsonb;
  r record;
  p record;
  i record;
BEGIN
  -- Valider la totalité avant la première écriture. Un seul écart fait échouer
  -- la migration entière, sans accepter le nouveau corps observé implicitement.
  FOR r IN SELECT * FROM jsonb_to_recordset(v_entries) AS x(
    signature text, old_md5 text, definition_md5 text, categorie text,
    proconfig text[], anon_execute boolean, justification text
  ) LOOP
    SELECT proc.*, pg_get_userbyid(proc.proowner) AS owner_name INTO p
    FROM pg_catalog.pg_proc proc
    WHERE proc.oid = to_regprocedure('public.' || r.signature);
    IF NOT FOUND THEN RAISE EXCEPTION 'Fonction absente : %', r.signature; END IF;
    IF md5(p.prosrc) IS DISTINCT FROM r.definition_md5
       OR p.prosecdef IS DISTINCT FROM true
       OR p.owner_name IS DISTINCT FROM 'postgres'
       OR p.proconfig IS DISTINCT FROM r.proconfig
       OR has_function_privilege('anon', p.oid, 'EXECUTE') IS DISTINCT FROM r.anon_execute
       OR has_function_privilege('authenticated', p.oid, 'EXECUTE') IS DISTINCT FROM true
       OR has_function_privilege('service_role', p.oid, 'EXECUTE') IS DISTINCT FROM true
       OR EXISTS (
         SELECT 1 FROM aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
         WHERE a.grantee = 0 AND a.privilege_type = 'EXECUTE'
       ) THEN
      RAISE EXCEPTION 'Corps ou droits inattendus : %', r.signature;
    END IF;
    IF EXISTS (SELECT 1 FROM private.security_definer_inventory
               WHERE signature = 'public.' || r.signature) THEN
      RAISE EXCEPTION 'Alias inventaire inattendu : %', r.signature;
    END IF;
    SELECT * INTO i FROM private.security_definer_inventory WHERE signature = r.signature;
    IF FOUND THEN
      IF i.categorie IS DISTINCT FROM r.categorie
         OR (i.definition_md5 IS DISTINCT FROM r.old_md5
             AND i.definition_md5 IS DISTINCT FROM r.definition_md5) THEN
        RAISE EXCEPTION 'Inventaire divergent : %', r.signature;
      END IF;
    ELSIF r.old_md5 IS NOT NULL THEN
      RAISE EXCEPTION 'Entrée inventaire disparue : %', r.signature;
    END IF;
  END LOOP;

  INSERT INTO private.security_definer_inventory
    (signature, categorie, definition_md5, justification, recense_le)
  SELECT signature, categorie, definition_md5, justification, now()
  FROM jsonb_to_recordset(v_entries) AS x(
    signature text, categorie text, definition_md5 text, justification text
  )
  ON CONFLICT (signature) DO UPDATE SET
    categorie = excluded.categorie,
    definition_md5 = excluded.definition_md5,
    justification = excluded.justification,
    recense_le = excluded.recense_le;
END;
$inventory$;
