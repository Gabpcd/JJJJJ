# Audit de dérive repo ↔ prod — fonctions PostgreSQL

> **Date** : 4 juillet 2026 (extraction prod des 3–4 juillet).
> **Contexte** : chantier « Réconciliation 9.0 », déclenché par les deux incidents
> du 2 juillet 2026 (voir §5).

## 1. Méthode et périmètre

**La prod est la source de vérité.** Les fichiers de `supabase/migrations/` sont un
journal historique, pas un état : une fonction peut avoir été corrigée en prod (hotfix
MCP, patch dynamique) sans que le dernier `CREATE FUNCTION` littéral du repo ait suivi.

Méthode :

- **Extraction** : lecture seule des catalogues prod (`pg_proc` /
  `pg_get_functiondef`) via MCP `execute_sql` — aucune écriture.
- **Comparaison** : pour chaque fonction prod, recherche du dernier `CREATE [OR
  REPLACE] FUNCTION` la définissant dans `supabase/migrations/`, puis **diff textuel
  des corps normalisés** (espaces/retours à la ligne repliés).
- **Découpage** : 703 fonctions du schéma `public`, traitées en 9 tranches (~80
  fonctions) par des agents parallèles. Classifications détaillées dans
  `db/baseline_prod_2026-07-04/drift/slice_01.json` → `slice_09.json`.
- **Verdicts** : `MATCH` (identique à normalisation près), `DIFFERENT` (corps
  divergent), `ABSENT_DU_REPO` (aucun `CREATE` dans aucune migration).

Périmètre :

- **Ce document** : les **fonctions** uniquement (diff effectué).
- **Structure / policies / cron / edge** : snapshot prod **capturé** dans
  `db/baseline_prod_2026-07-04/` (145 tables + 566 contraintes dans
  `tables/schema.sql`, 28 enums, 515 index, 187 triggers, 313 policies RLS,
  grants de 146 tables, 46 jobs pg_cron, 68 edge functions ACTIVE dont 5
  `verify_jwt=true`). Le **diff structurel** repo ↔ prod de ces objets sera couvert
  à l'étape 3 (squash baseline via `supabase db dump` en CI) — non fait ici.

## 2. Récapitulatif

| Verdict | Nombre | % |
|---|---:|---:|
| **Total fonctions prod (schéma public)** | **703** | 100 % |
| MATCH (repo à jour) | 355 | 50,5 % |
| DIFFERENT (corps divergent) | 164 | 23,3 % |
| — dont écarts de code réels | 51 | 7,3 % |
| — dont cosmétiques (commentaires/espaces) | 113 | 16,1 % |
| ABSENT_DU_REPO (aucun `CREATE` dans les migrations) | 184 | 26,2 % |

Détail par tranche :

| Slice | Total | MATCH | DIFFERENT | ABSENT |
|---|---:|---:|---:|---:|
| 01 | 80 | 17 | 13 | 50 |
| 02 | 80 | 54 | 16 | 10 |
| 03 | 80 | 39 | 27 | 14 |
| 04 | 80 | 37 | 23 | 20 |
| 05 | 80 | 38 | 18 | 24 |
| 06 | 80 | 50 | 12 | 18 |
| 07 | 80 | 41 | 20 | 19 |
| 08 | 80 | 43 | 20 | 17 |
| 09 | 63 | 36 | 15 | 12 |

**Lecture** : près d'une fonction prod sur deux (49,5 %) n'est PAS reconstructible
fidèlement depuis le dernier fichier de migration du repo. C'est exactement le
mécanisme de l'incident enum du 02/07.

## 3. DIFFERENT — détail

**Règle unique, quelle que soit la gravité de l'écart : toute redéfinition part de la
définition LIVE** (`scripts/dump-live-def.sh <fonction>` ou `pg_get_functiondef` via
SQL, ou `db/baseline_prod_2026-07-04/functions/`), **jamais** d'un fichier de
migration du repo.

### 3.1 Écarts de code réels (51 fonctions)

Corps exécutable, textes retournés ou signatures divergents. Dans la grande majorité
des cas, **la prod est plus récente que le repo** (fixes Sprint 17 appliqués par patch
dynamique, éradication CDDU, hardening `search_path`, refontes de notifications).
Familles récurrentes : doublon `IN ('CDD','CDD')` prod vs `'CDDU'` repo (éradication
CDDU par `20260530280000` sans CREATE littéral), fix antipattern `RECORD IS NOT NULL`
→ `.id IS NOT NULL` (Sprint 17), qualification `extensions.gen_random_bytes`, statuts
mission `LITIGE`/`ANNULEE_PAR_ETABLISSEMENT` prod vs `ANNULEE_LITIGE`/`ANNULEE_ETAB`
repo, bypass `service_role` sur les triggers de protection.

| Fonction | Dernière migration repo | Résumé de l'écart | Action |
|---|---|---|---|
| `dec_auto_generer_qr_mission` | `20260514090000_pr4s45_qr_code_backend.sql` | Prod qualifie extensions.gen_random_bytes(8) alors que le repo appelle gen_random_bytes(8) non qualifié. | Repartir du live avant toute modif |
| `dec_email_contrat_signe_complet` | `20260512180000_pr7_workflow_post_signature.sql` | dpae_requise : le repo teste type_contrat IN ('CDD','CDDU') alors que prod contient IN ('CDD','CDD') — CDDU non couvert en prod. | Repartir du live avant toute modif |
| `dec_maj_note_moyenne` | `20260328170027_6b898a19-2468-4d32-9605-b8a1fe7c4128.sql` | Prod ajoute PERFORM set_config('jolene.system_update','true',true) avant l'UPDATE soignants (flag pour le trigger de protection), absent du repo. | Repartir du live avant toute modif |
| `dec_notifier_resolution_litige` | `20260316130534_497d79c0-9e0a-4915-a09b-9f13f819668b.sql` | Prod pointe vers /soignant/litiges et /etablissement/litiges avec label FERME 'clôturé par accord mutuel' ; le repo garde /presences, 'fermé par l'administrateur' et une variable v_etab_nom obsolète. | Repartir du live avant toute modif |
| `dec_notifier_creation_litige` | `20260316131737_10db766c-e011-4d56-8a5d-4b6b4fbb4af8.sql` | Prod notifie vers /etablissement/litiges et /soignant/litiges avec messages simplifiés (appels fn_creer_notification inlinés) ; le repo garde la version antérieure (/presences, variables v_dest_id/v_dest_type, mention 'Veuillez consulter et répondre'). | Repartir du live avant toute modif |
| `dec_notifier_reponse_litige` | `20260316131737_10db766c-e011-4d56-8a5d-4b6b4fbb4af8.sql` | Prod détecte les réponses ajoutées (comparaison LENGTH + split_part + préfixes 'Établissement:'/'Soignant:') et pointe vers /litiges ; le repo ne gère que la première réponse et pointe vers /presences. | Repartir du live avant toute modif |
| `fn_admin_chorus_submission_reset` | `20260421140000_cp_c_5_d_1_rpcs_admin_chorus.sql` | Messages retour prod sans tirets cadratins ni accents ('rien a reset', 'Facture reset admin peut...') et commentaires repo absents en prod ; logique identique. | Repartir du live avant toute modif |
| `fn_admin_kpi` | `20260316125013_a1866917-bff8-43f4-abe2-5695c70ca849.sql` | Prod est une version enrichie (garde est_admin, fin_mois, filtres supprime_le, KPIs litiges/GMV/factures_impayees, commissions calculées sur fin_le) — repo nettement obsolète. | Repartir du live avant toute modif |
| `fn_admin_graphiques` | `20260316093918_9bfd1394-2499-48de-86c6-c92d86db76bf.sql` | Prod ajoute la garde est_admin, calcule missions_par_semaine sur cree_le (toutes missions) et ca_par_mois depuis les factures (date_emission/montant_ht) — repo obsolète (modifie_le TERMINEE + commissions missions). | Repartir du live avant toute modif |
| `fn_admin_invocations_purge` | `20260415160000_admin_invocations.sql` | Écarts mineurs : message d'exception raccourci en prod ('Purge déjà en cours') + commentaires/espacement ; logique de purge identique. | Repartir du live avant toute modif |
| `fn_admin_invocations_append_only` | `20260415160000_admin_invocations.sql` | Prod ajoute la machine à états internal_status (PENDING→INVOKED/CRASHED→COMPLETED, états terminaux) et l'immutabilité de request_id, avec messages sans accents — repo obsolète. | Repartir du live avant toute modif |
| `fn_admin_resoudre_litige` | `20260417130720_fix_bonus_resolution_null_values.sql` | Ancien overload 5 params (p_ajuster_heures avant p_en_faveur_de) encore présent en prod sans aucune définition repo pour cette signature — corps entièrement différent de la version 6 params du repo. | Repartir du live avant toute modif |
| `fn_admin_resoudre_litige` | `20260417130720_fix_bonus_resolution_null_values.sql` | Prod (6 params) intègre les fixes Sprint 17 (v_facture.id IS NOT NULL + periode_debut/periode_fin/numero_semaine_iso/annee_iso dans les INSERT) appliqués par patch dynamique 20260530287000/288000 — aucun CREATE littéral à jour dans le repo. | Repartir du live avant toute modif |
| `fn_alerter_mediation_prioritaire` | `20260417130400_cp_litiges_4_cron.sql` | Prod a retiré l'emoji 🚨 du titre de la notification push (seul écart de code, plus commentaires). | Repartir du live avant toute modif |
| `fn_alerter_paiements_retard` | `20260420171000_cp_c_2_c_refonte_alerter_paiements.sql` | Prod remplace € par EUR et désaccentue les textes des relances, et supprime deux variables inutilisées (v_etab_email, v_etab_nom). | Repartir du live avant toute modif |
| `fn_alerte_reclamations_pending_old` | `20260513280000_pr3s4_cron_alertes_admin.sql` | La version repo contient un INSERT journaux_audit final et des textes plus verbeux (clé 'message', corps de notif) absents de la version prod. | Repartir du live avant toute modif |
| `fn_annuler_mission_complete` | `20260513210000_pr2s35_litiges_execution_accords.sql` | Prod écrit statut mission 'LITIGE' là où le repo écrit 'ANNULEE_LITIGE'. | Repartir du live avant toute modif |
| `fn_annuler_mission_etab` | `20260513230000_pr5s35_annulation_etab_indemnites.sql` | Statuts divergents : prod utilise 'LITIGE'/'ANNULEE_PAR_ETABLISSEMENT' là où le repo utilise 'ANNULEE_LITIGE'/'ANNULEE_ETAB'. | Repartir du live avant toute modif |
| `fn_assigner_mission_admin` | `20260420162000_e16_c_assigner_admin.sql` | Prod utilise type_contrat 'CDD' vs 'CDDU' dans le repo (éradication CDDU appliquée dynamiquement par 20260530280000, sans CREATE littéral). | Repartir du live avant toute modif |
| `fn_bfa_info` | `20260328172746_e156b0ad-f95c-4e90-9d75-1dd2c78ee7cd.sql` | Prod corrige l'antipattern record NULL ('v_prochain.id IS NOT NULL' au lieu de 'v_prochain IS NOT NULL'), fix absent du repo. | Repartir du live avant toute modif |
| `fn_calculer_indemnite_annulation_etab` | `20260513230000_pr5s35_annulation_etab_indemnites.sql` | Prod a remplacé 'CDDU' par 'CDD' (doublon) dans la liste IN ('CDD','CDD','SALARIE') — le repo garde encore 'CDDU'. | Repartir du live avant toute modif |
| `fn_calculer_score_etab` | `20260513240000_pr6s35_scores_revises.sql` | Prod lit les notes depuis evaluations (evalue_id, type_evaluateur='SOIGNANT', visible IS NOT FALSE) alors que le repo lit notations (cible_id, cible_type='ETABLISSEMENT', masquee_par_admin). | Repartir du live avant toute modif |
| `fn_declarer_virement` | `20260324172130_a48f34c7-8b05-4c3f-a07e-2c11f128ca32.sql` | Prod contrôle mon_etablissement_id() (repo : auth.uid()), valide et TRIM la référence (min 3 chars) et renvoie jsonb (repo : json) — migration 2026-03 obsolète. | Repartir du live avant toute modif |
| `fn_declarer_paiement_soignant` | `20260421180949_fix_f_gardes_type_contrat_paiement_soignant.sql` | Prod raccourcit les messages d'erreur des gardes 2/3 et renomme CDDU en CDD ; commentaires Fix F supprimés. | Repartir du live avant toute modif |
| `fn_etablissement_public` | `20260312205752_b54770d9-64d5-4bff-a195-65b2b874f6ec.sql` | Divergence fonctionnelle : la prod retourne un jsonb enrichi (logo_url, couleur_theme) via RETURN jsonb_build_object, le repo une version SELECT colonnes sans ces champs. | Repartir du live avant toute modif |
| `fn_externalisations_a_traiter` | `20260513270000_pr2s4_worker_externalisation.sql` | Divergence fonctionnelle : la prod supprime le RETURNING orphelin de l'UPDATE (erreur plpgsql « query has no destination ») encore présent dans le repo, plus commentaires retirés. | Repartir du live avant toute modif |
| `fn_generer_code_parrainage` | `20260528180208_fix_search_path_parrainage_code.sql` | Divergence fonctionnelle : la prod qualifie extensions.gen_random_bytes (hardening search_path) là où le repo appelle gen_random_bytes non qualifié. | Repartir du live avant toute modif |
| `fn_generer_facture_mensuelle` | `20260313152433_8096a62c-342b-4938-a6cd-ba3793e15e8d.sql` | Divergence fonctionnelle majeure : implémentations distinctes (prod : garde p_etablissement_id/est_admin() et erreurs JSONB littérales ; repo : mon_etablissement_id(), v_mission_ids et période calculée). | Repartir du live avant toute modif |
| `fn_generer_qr_mission` | `20260514090000_pr4s45_qr_code_backend.sql` | Divergence fonctionnelle : statuts mission bloquants LITIGE/ANNULEE_PAR_ETABLISSEMENT en prod vs ANNULEE_LITIGE/ANNULEE_ETAB dans le repo, et extensions.gen_random_bytes qualifié en prod. | Repartir du live avant toute modif |
| `fn_litige_preuves_agregees` | `20260417130717_cp7b1_rpcs_admin.sql` | Prod teste `v_presence.id IS NOT NULL` (fix antipattern record-NULL) là où le repo teste `v_presence IS NOT NULL` ; le reste de l'écart = commentaires. | Repartir du live avant toute modif |
| `fn_mes_dpae` | `20260514150000_pr10s55_dpae_soignant_nir_rpc.sql` | Prod filtre `type_contrat IN ('CDD','CDD','SALARIE')` (doublon CDD, CDDU absent) alors que le repo a `('CDD','CDDU','SALARIE')`. | Repartir du live avant toute modif |
| `fn_mes_exclusions_recues` | `20260313161955_3a037783-b29e-4819-be07-4ed20d591063.sql` | Corps entièrement réécrit en prod : retour jsonb_agg avec type_exclu_par/etablissement_nom vs simple SELECT de colonnes dans le repo (obsolète). | Repartir du live avant toute modif |
| `fn_modifier_preferences_notifications` | `20260429180000_j23a_preferences_notifications.sql` | Prod déclare une variable supplémentaire `v_old jsonb` absente du repo ; le reste de l'écart = commentaires et espaces. | Repartir du live avant toute modif |
| `fn_obtenir_mes_preferences_notifications` | `20260429180000_j23a_preferences_notifications.sql` | Prod précise `ON CONFLICT (utilisateur_id) DO NOTHING` là où le repo a `ON CONFLICT DO NOTHING` ; le reste de l'écart = espaces. | Repartir du live avant toute modif |
| `fn_pointer_arrivee` | `20260517130400_fn_pointer_arrivee_dpae_warning.sql` | Prod filtre `type_contrat IN ('CDD','CDD','SALARIE')` (doublon CDD, CDDU absent) alors que le repo a `('CDD','CDDU','SALARIE')`. | Repartir du live avant toute modif |
| `fn_proposer_cloture_litige` | `20260328171813_3702d80f-f7e2-4085-b49f-cfdc767863aa.sql` | Corps réécrit en prod : accepte le statut EN_MEDIATION et passe le litige en EN_MEDIATION (workflow accord des parties) au lieu de le clore directement en RESOLU — repo obsolète. | Repartir du live avant toute modif |
| `fn_protect_etablissement_commercial` | `20260313130707_0a1aa64f-1637-4454-8172-8fc8ca2aedc3.sql` | Prod ajoute un bypass service_role + contexte interne (v_is_service_role / v_is_internal via app.internal) et des messages d'exception raccourcis — repo obsolète. | Repartir du live avant toute modif |
| `fn_protect_facture_honoraire_immutability` | `20260417130000_cp_litiges_1_ddl.sql` | Écart limité au texte des messages d'exception (prod sans les précisions entre parenthèses du repo), logique identique. | Repartir du live avant toute modif |
| `fn_protect_notification_update` | `20260313165936_fdc6fc77-d923-4a0e-9fc3-a1eb3f3c798c.sql` | Prod ajoute en tête des bypass service_role / auth.uid() NULL / est_admin() absents du repo — repo obsolète. | Repartir du live avant toute modif |
| `fn_proteger_document_verification` | `20260314193919_e2243a04-3c83-47ac-9e72-49b21cb9f4bb.sql` | Prod ajoute bypass service_role/auth NULL, verrouille aussi les champs IA (resultat_ia, score_confiance_ia, nom/prenom extraits) et interdit le changement de soignant_id — repo obsolète. | Repartir du live avant toute modif |
| `fn_rappel_dpae_quotidien` | `20260513170000_pr6s3_bugfixes_audit.sql` | Repo sélectionne cm.soignant_id en plus et filtre CDDU alors que prod a le doublon `('CDD','CDD','SALARIE')` sans CDDU ; le reste = espaces jsonb_build_object. | Repartir du live avant toute modif |
| `fn_rgpd_exporter_rate_limited` | `20260530240000_rgpd_export_rate_limit_relache.sql` | Prod appelle fn_rgpd_exporter_donnees_soignant(v_user_id) alors que le repo l'appelle sans argument. | Repartir du live avant toute modif |
| `fn_revoquer_contrat_service` | `20260429140000_j2_onboarding_etab_contrat_rib.sql` | Libellés différents en prod ('Aucun contrat actif à révoquer', message de succès enrichi) + formatage. | Repartir du live avant toute modif |
| `fn_signer_contrat_otp` | `20260513090000_pr1s2_signature_limits.sql` | Prod sans le cast v_ip::text (2 occurrences COALESCE) présent dans le repo. | Repartir du live avant toute modif |
| `fn_soignant_pour_etablissement` | `20260608220000_profil_soignant_consultable_annuaire.sql` | Prod ajoute les clés est_etudiant et etudiant_details au JSON de retour — repo obsolète. | Repartir du live avant toute modif |
| `fn_toggle_favori_etablissement` | `20260429320100_j5g_a_favoris_bidirectionnels.sql` | Prod passe un argument NULL supplémentaire à fn_ecrire_audit_safe (2 appels) — repo obsolète. | Repartir du live avant toute modif |
| `fn_trg_notif_admin_remboursement_manuel` | `20260530230000_remboursement_avoir_swan_auto.sql` | Prod notifie type_destinataire 'ADMIN' (fix contrainte Sprint 17) vs 'ADMIN_PLATEFORME' dans le repo | Repartir du live avant toute modif |
| `fn_update_document_verification` | `20260317234042_2ac23bbf-3439-420e-9d86-b0ff6db9c591.sql` | Prod fait l'UPDATE direct (passthrough service_role) alors que le repo DISABLE/ENABLE encore les triggers de protection | Repartir du live avant toute modif |
| `fn_upsert_token_push` | `20260313181053_eb22df22-7e62-47bc-840f-592fcde5f80e.sql` | Prod parse le token Web Push JSON (endpoint/p256dh/auth_key + COALESCE à l'upsert), absent de la version FCM simple du repo | Repartir du live avant toute modif |
| `fn_valider_code_secours` | `20260514110000_pr9s45_code_secours.sql` | Prod corrige l'antipattern record IS NOT NULL en v_presence.id IS NOT NULL (fix Sprint 17), repo obsolète | Repartir du live avant toute modif |
| `peut_exercer` | `20260512130100_pr2_matrice_v2.sql` | Liste des exercices salariés : prod ('SALARIE','CDD','CDD','VACATION') avec doublon CDD, repo garde 'CDDU' | Repartir du live avant toute modif |

### 3.2 Écarts cosmétiques (113 fonctions)

Commentaires et/ou espacement uniquement — code exécutable identique après
normalisation manuelle. Sans risque immédiat, **mais** le fichier repo reste non
identique au live : la même règle s'applique (repartir du live avant toute modif),
et ces écarts disparaîtront au squash baseline (étape 3).

| Fonction | Dernière migration repo | Résumé de l'écart |
|---|---|---|
| `dec_bloquer_modif_apres_acceptation` | `20260416150000_cp3_fix_targeted_bypass.sql` | Écart de commentaire uniquement (le repo contient un commentaire '-- Skip timing check' absent en prod), code exécutable identique. |
| `dec_calculer_finance_mission` | `20260624170000_plancher_previsionnel_garanti.sql` | Écarts de commentaires et d'espacement uniquement (commentaire PLANCHER, espaces autour des parenthèses et de ':='), logique identique. |
| `dec_mettre_a_jour_fiabilite` | `20260530210000_heures_cumulees_reelles.sql` | Écart de commentaire uniquement ('-- Heures réellement pointées' présent au repo, absent en prod), code identique. |
| `dec_notif_signature_soignant_recue` | `20260513170000_pr6s3_bugfixes_audit.sql` | Écarts de commentaires et d'espacement uniquement (commentaires supprimés en prod, espaces dans jsonb_build_object), logique identique. |
| `dec_push_contrat_a_signer` | `20260513160000_pr4s3_notifications_hardening.sql` | Écarts de commentaires et d'espacement uniquement (commentaire '-- Best-effort' et espaces dans jsonb_build_object), logique identique. |
| `dec_push_contrat_signe_complet` | `20260513160000_pr4s3_notifications_hardening.sql` | Écarts de commentaires et d'espacement uniquement (commentaires '-- Push soignant/étab' et espaces dans jsonb_build_object), logique identique. |
| `dec_verifier_docs_avant_debut` | `20260630250000_documents_gate_per_mission_acceptation.sql` | Écarts de commentaire et d'espacement uniquement (commentaire '-- RCP exigée' et espaces dans SELECT EXISTS(...)), logique identique. |
| `dec_verifier_plafond_48h` | `20260416190300_cp5b_triggers_effectif_previsionnel.sql` | Écarts de commentaires uniquement (commentaires EFFECTIF/PREVISIONNEL du repo absents en prod), code identique. |
| `dec_verifier_repos_11h` | `20260416190300_cp5b_triggers_effectif_previsionnel.sql` | Écarts de commentaires uniquement (3 commentaires EFFECTIF/PREVISIONNEL du repo absents en prod), code identique. |
| `est_admin_valide` | `20260415160000_admin_invocations.sql` | Écarts d'espacement uniquement (parenthèses COALESCE(( et false);), code identique. |
| `fn_accepter_mission` | `20260630250000_documents_gate_per_mission_acceptation.sql` | Écarts de commentaires et d'espacement uniquement (commentaire docs requis + parenthèses INSERT/jsonb repliées en prod), logique identique. |
| `fn_accepter_mission_urgence` | `20260630250000_documents_gate_per_mission_acceptation.sql` | Écarts d'espacement uniquement (parenthèses multi-lignes repliées en prod), logique identique. |
| `fn_admin_bfa_calculer` | `20260613144444_bfa_modele_contrat_par_beneficiaire.sql` | Écart de commentaires uniquement (prod contient '-- Groupes éligibles' / '-- Étabs isolés éligibles' absents du repo), code identique. |
| `fn_admin_creer_compte_employe` | `20260609200000_rbac_admin_backend.sql` | Écarts de commentaires uniquement (4 commentaires du repo absents en prod), code identique. |
| `fn_admin_creer_litige_force` | `20260417130721_fix_t18_fenetre_financier_facture_lookup.sql` | Écarts de commentaires uniquement (commentaires [FIX T18] du repo absents en prod), code identique. |
| `fn_admin_lister_externalisations` | `20260513270000_pr2s4_worker_externalisation.sql` | Écarts d'espacement uniquement (parenthèses de sous-requête), code identique. |
| `fn_admin_moderer_evaluation` | `20260411160000_rpc_drift_fixes_admin_payment_urgence.sql` | Écart de commentaires uniquement (2 commentaires présents en prod, absents du repo), code identique. |
| `fn_admin_mes_acces` | `20260610100000_fix_grants_fondateur.sql` | Écart de commentaire uniquement (commentaire '-- Fondatrice ... accès total' présent en prod, absent du repo), code identique. |
| `fn_admin_recategoriser_litige_legacy` | `20260417130718_cp7b3_recategorisation_rpc.sql` | Écart limité aux commentaires SQL — code identique une fois les commentaires retirés. |
| `fn_admin_stripe_connect_stats` | `20260415120000_fix_stripe_connect_stats.sql` | Écart de commentaires et de mise en forme uniquement — code identique à espaces près. |
| `fn_admin_suspendre_utilisateur` | `20260411160000_rpc_drift_fixes_admin_payment_urgence.sql` | Écart limité aux commentaires SQL (prod contient un commentaire absent du repo) — code identique. |
| `fn_admin_supprimer_compte_test` | `20260624200000_admin_supprimer_compte_test.sql` | Écart limité aux commentaires SQL (prod contient des commentaires absents du repo) — code identique. |
| `fn_admin_valider_etablissement` | `20260606140000_phase4_admin_revue_etablissements.sql` | Écart limité aux commentaires SQL — code identique une fois les commentaires retirés. |
| `fn_ajouter_jours_ouvres` | `20260417130709_fix10_timezone_europe_paris.sql` | Écart limité aux commentaires SQL — code identique une fois les commentaires retirés. |
| `fn_admin_valider_heures_externes` | `20260530170000_admin_validation_heures_externes.sql` | Écart limité aux commentaires SQL — code identique une fois les commentaires retirés. |
| `fn_annuler_candidature_soignant` | `20260608180000_fix_annulation_candidature_soignant_statut.sql` | Écart limité aux commentaires SQL — code identique une fois les commentaires retirés. |
| `fn_annuler_mission_soignant` | `20260608200000_bonus_urgence_acceptation_formule.sql` | Écart limité aux commentaires SQL — code identique une fois les commentaires retirés. |
| `fn_anti_seed_facture_honoraire` | `20260608170000_fix_anti_seed_exempte_admin_litige_avoir.sql` | Écart de commentaires et de mise en forme uniquement — code identique à espaces près. |
| `fn_anti_seed_mission` | `20260416200000_cp6_anti_seed_triggers.sql` | Écart limité aux commentaires SQL — code identique une fois les commentaires retirés. |
| `fn_audit_rls_strict` | `20260513180000_pr7s3_durcissement_securite.sql` | Écart de commentaires et de mise en forme uniquement — code identique à espaces près. |
| `fn_archiver_conversations_anciennes` | `20260514183300_pr4s10a_archivage_conversations_30j.sql` | Écart limité aux commentaires SQL — code identique une fois les commentaires retirés. |
| `fn_auto_facturation_mensuelle` | `20260624140000_fix_cron_auth_gates.sql` | Écart de commentaires et de mise en forme uniquement — code identique à espaces près. |
| `fn_auto_creation_litiges_presence` | `20260417130719_fix_bonus_auto_creation_cas_b_c.sql` | Écart limité aux commentaires SQL — code identique une fois les commentaires retirés. |
| `fn_auto_transitions_missions` | `20260420190001_cp_c_4_a_expiree_enum_fn.sql` | Écart limité aux commentaires SQL — code identique une fois les commentaires retirés. |
| `fn_award_badges_swipe` | `20260515140000_badges_engagement.sql` | Écart limité aux commentaires SQL — code identique une fois les commentaires retirés. |
| `fn_blocage_publication_etab` | `20260606120000_phase4_verrou_publication_finess_rattachement.sql` | Écart limité aux commentaires SQL — code identique une fois les commentaires retirés. |
| `fn_calculer_financier_mission` | `20260627160000_commission_liberal_ifm_icp_et_consolidation.sql` | Écarts de commentaires uniquement (prod plus documentée sur IFM/ICP libéral et commission 15 %), code identique. |
| `fn_calculer_remuneration_mission` | `20260627160000_commission_liberal_ifm_icp_et_consolidation.sql` | Écarts de commentaires uniquement (note IFM/ICP libéral reformulée et étendue en prod), code identique. |
| `fn_check_crons_health` | `20260628170000_monitoring_anti_faux_positif_crons_jamais.sql` | Écarts de commentaires uniquement (justification anti-faux-positifs étendue en prod), code identique. |
| `fn_check_stripe_webhook_health` | `20260624140000_fix_cron_auth_gates.sql` | Écarts d'espacement uniquement (parenthèses fn_emettre_alerte_monitoring repliées en prod), code identique. |
| `fn_check_rate_limit_ip_signature` | `20260513180000_pr7s3_durcissement_securite.sql` | Écarts de commentaires et d'espacement uniquement (commentaires rate-limit du repo absents en prod), code identique. |
| `fn_calculer_tous_documents_valides` | `20260630240000_consolider_calcul_tous_documents_valides.sql` | Écarts de commentaires et d'espacement uniquement (commentaire dispense RPPS/ADELI + parenthèses repliées en prod), code identique. |
| `fn_compteur_heures_soignant` | `20260530190000_compteur_3200h_heures_reelles.sql` | Écarts de commentaires uniquement (commentaire heures réelles/repli du repo absent en prod), code identique. |
| `fn_confirmer_email_etab` | `20260606130000_phase4_email_pro_confirmation.sql` | Écarts de commentaires uniquement (3 commentaires token/confirmation/rattachement du repo absents en prod), code identique. |
| `fn_contester_presence` | `20260411140000_rgpd_audit_gaps_phase2.sql` | Écart de commentaire uniquement ('CDDU critique' repo vs 'CDD critique' prod), code identique. |
| `fn_contacter_support` | `20260609110000_fn_contacter_support.sql` | Écart de commentaire uniquement (commentaire compte support du repo absent en prod), code identique. |
| `fn_conflit_planning_soignant` | `20260702112405_favoris_missions_garde_fous_candidature.sql` | Écarts de commentaires uniquement (commentaires conflit dur/adjacence du repo absents en prod), code identique. |
| `fn_creer_mission` | `20260606120000_phase4_verrou_publication_finess_rattachement.sql` | Écart de commentaire uniquement (commentaire contrôles de publication du repo absent en prod), code identique. |
| `fn_creer_bulletin_paie` | `20260428210000_bulletins_paie_schema.sql` | Écarts de commentaires uniquement (CDDU renommé CDD dans les commentaires prod), code identique. |
| `fn_creer_conversation_si_absente` | `20260514183100_pr1s10a_trigger_chat_acceptation_candidature.sql` | Écarts de commentaires uniquement (6 commentaires propriétaire/idempotence/audit du repo absents en prod), code identique. |
| `fn_creer_notification` | `20260628160000_fix_creer_notification_contexte_cron.sql` | Écarts de commentaires uniquement (prod ajoute la note sur le fix crons sans session), code identique. |
| `fn_creer_serie` | `20260606120000_phase4_verrou_publication_finess_rattachement.sql` | Écarts de commentaires uniquement (commentaires verrou publication/validation/max 30 du repo absents en prod), code identique. |
| `fn_declarer_fin_retroactive` | `20260416190400_cp5b_garde_fous.sql` | Écarts de commentaires uniquement (commentaires Step 1-10 du repo absents en prod), code identique. |
| `fn_demander_confirmation_email_etab` | `20260606130000_phase4_email_pro_confirmation.sql` | Écarts de commentaires uniquement (commentaires autorisation/validation/token du repo absents en prod), code identique. |
| `fn_detail_facture` | `20260411120100_fn_detail_facture_enriched.sql` | Écart de commentaire uniquement ('(lien direct)' du repo absent en prod), code identique. |
| `fn_doit_notifier` | `20260429180000_j23a_preferences_notifications.sql` | Écart limité aux commentaires : la version prod contient des commentaires explicatifs absents du repo, logique identique. |
| `fn_documents_ok_pour_mission` | `20260630250000_documents_gate_per_mission_acceptation.sql` | Écart cosmétique : commentaire sur le régime libéral et espaces dans les parenthèses absents en prod, logique identique. |
| `fn_enregistrer_numero_dpae` | `20260517125600_fn_enregistrer_numero_dpae_validation_email.sql` | Écart limité aux commentaires : la prod est dépourvue des commentaires (validation URSSAF, audit, email best-effort) du repo, logique identique. |
| `fn_enregistrer_swipe` | `20260702112405_favoris_missions_garde_fous_candidature.sql` | Écart limité aux commentaires : la prod est dépourvue des commentaires D1/D2 (favoris, garde-fous) du repo, logique identique. |
| `fn_envoyer_rappels_litiges` | `20260417130400_cp_litiges_4_cron.sql` | Écart limité aux commentaires : deux commentaires (ciblage destinataire, clé rappel) absents en prod, logique identique. |
| `fn_envoyer_otp_signature` | `20260513190000_pr9s3_integration_rate_limit_signature.sql` | Écart cosmétique : un commentaire rate-limit et des espaces dans jsonb_build_object absents en prod, logique identique. |
| `fn_est_contexte_cron_ou_admin` | `20260624140000_fix_cron_auth_gates.sql` | Écart limité à un commentaire (contexte cron/trigger) absent en prod, logique identique. |
| `fn_evaluer_coherence_pointage` | `20260517131200_search_path_immutable_4_fonctions.sql` | Écart cosmétique : espaces après parenthèse ouvrante dans les jsonb_build_object, logique identique. |
| `fn_fh_auto_audit` | `20260413140000_invoicing_module_schema.sql` | Écart cosmétique : espaces après parenthèse dans le VALUES, logique identique. |
| `fn_fenetre_contestation_ouverte` | `20260417130722_fix_t19_escalade_type_contrat_applique.sql` | Écart limité à un commentaire [FIX T19] absent en prod, logique identique. |
| `fn_externalisation_echec` | `20260513270000_pr2s4_worker_externalisation.sql` | Écart cosmétique : commentaires (PENDING_AIFE, backoff, notif admin) et espaces absents en prod, logique identique. |
| `fn_haversine_distance_m` | `20260513150000_pr3s3_gps_pointage_hardening.sql` | Écart limité à un commentaire (rayon Terre en m) absent en prod, logique identique. |
| `fn_init_proprietaire_etab` | `20260602120000_secu_etab_init_proprietaire_et_userid_enumeration.sql` | Écart limité aux commentaires : la prod contient des commentaires (appel serveur vs client) absents du repo, logique identique. |
| `fn_litige_push_notification` | `20260417130500_cp_litiges_5_sms_extension.sql` | Écart limité aux commentaires SQL (version live sans les commentaires du repo), code identique. |
| `fn_litiges_escalader_auto` | `20260417130722_fix_t19_escalade_type_contrat_applique.sql` | Écart limité aux commentaires SQL (commentaire [FIX T19] absent en prod), code identique. |
| `fn_mes_filleuls` | `20260528131300_parrainage_soignant_rpcs_prime_cash.sql` | Écart de mise en forme uniquement (espaces après virgules dans jsonb_build_object), code identique. |
| `fn_mes_revenus_connect` | `20260405220000_fix_revenus_connect_include_paiements.sql` | Écart limité aux commentaires SQL (prod contient des commentaires absents du repo), code identique. |
| `fn_messagerie_cleanup_periodique` | `20260514183200_pr3s10a_typing_presence_realtime.sql` | Écart limité aux commentaires SQL (version live sans les commentaires numérotés du repo), code identique. |
| `fn_mes_matches` | `20260627140000_fix_coeur_candidatures_matching.sql` | Écart limité aux commentaires SQL (prod a un commentaire explicatif supplémentaire sur le fix des statuts candidature), code identique. |
| `fn_modifier_filtre_sauvegarde` | `20260429250100_j23c_filtres_sauvegardes_rpcs.sql` | Écart limité aux commentaires SQL (commentaire '-- Audit toggle alerte' présent en prod seulement), code identique. |
| `fn_modifier_mon_etablissement` | `20260411130100_rgpd_audit_gaps.sql` | Écart limité aux commentaires SQL (commentaires 'Validation couleur hex' / 'Audit RGPD' présents en prod seulement), code identique. |
| `fn_ouvrir_litige_rate_limited` | `20260417130707_fix2_audit_wrapper_legacy.sql` | Surcharge legacy 2 arguments (p_mission_id, p_motif) : écart limité aux commentaires SQL, code identique. |
| `fn_ouvrir_litige_rate_limited` | `20260417130721_fix_t18_fenetre_financier_facture_lookup.sql` | Surcharge 3 arguments (avec p_type_litige) : écart limité aux commentaires SQL, code identique. |
| `fn_pointer_depart` | `20260513150000_pr3s3_gps_pointage_hardening.sql` | Écart cosmétique : le message hors-périmètre est scindé en deux littéraux concaténés dans le repo (`'… ' \|\| '(tolérance '`) vs littéral unique en prod, plus des espaces — comportement identique. |
| `fn_postuler_mission` | `20260627140000_fix_coeur_candidatures_matching.sql` | Écart limité aux commentaires SQL, code identique. |
| `fn_protect_candidature_statut` | `20260608180000_fix_annulation_candidature_soignant_statut.sql` | Écart limité aux commentaires SQL, code identique. |
| `fn_proposer_mission_soignant` | `20260630250000_documents_gate_per_mission_acceptation.sql` | Écart d'espaces/mise en forme uniquement, code identique. |
| `fn_protect_mission_financials` | `20260416170000_cp5a_colonnes_et_gel.sql` | Écart limité aux commentaires SQL, code identique. |
| `fn_protect_creneaux_si_facture` | `20260416190500_cp5b_protect_previsionnel_gel.sql` | Écart limité aux commentaires SQL, code identique. |
| `fn_rappel_pointage_arrivee` | `20260513170000_pr6s3_bugfixes_audit.sql` | Écart d'espaces/mise en forme uniquement, code identique. |
| `fn_recalculer_palier_commission` | `20260429230100_audit_fix_crons_et_fn_palier.sql` | Écart limité aux commentaires SQL, code identique. |
| `fn_recalculer_commissions_post_litige` | `20260417130716_bloc4_commission_ajustee_push.sql` | Écart limité aux commentaires SQL, code identique. |
| `fn_rechercher_aide` | `20260429160000_j22_articles_aide_schema.sql` | Écart limité aux commentaires SQL, code identique. |
| `fn_repondre_proposition` | `20260420163000_e16_d_repondre_proposition.sql` | Commentaires uniquement : 3 commentaires E16 du repo absents en prod, code identique. |
| `fn_retirer_candidature` | `20260630230000_fn_retirer_candidature.sql` | Commentaires uniquement : 2 commentaires du repo absents en prod, code identique. |
| `fn_scanner_code_pointage` | `20260624120000_pointage_gate_contrat_signe.sql` | Commentaires uniquement : 3 blocs de commentaires PONT/arrondi du repo absents en prod, code identique. |
| `fn_signaler_utilisateur` | `20260609150000_signalement_utilisateur.sql` | Formatage compacté et commentaires absents en prod, code identique. |
| `fn_signer_cession_creance` | `20260417110000_export_affactureur_schema.sql` | Commentaires uniquement : prod contient 2 commentaires absents du fichier repo, code identique. |
| `fn_soumettre_reclamation` | `20260413090000_reclamations_generales.sql` | Corps prod compacté sur une ligne sans commentaires, code identique au repo. |
| `fn_soignant_dpae_complet` | `20260607110000_sec_secdef_authz_idor.sql` | Commentaire GARDE absent et reformatage en prod, code identique. |
| `fn_soignant_score_breakdown` | `20260628140000_fn_ma_streak_et_score_breakdown.sql` | Formatage uniquement (retours à la ligne/parenthèses), code identique. |
| `fn_stripe_webhook_event_is_new` | `20260628190000_fix_idempotence_webhook_stripe_retry.sql` | Commentaires uniquement : prod porte un commentaire enrichi expliquant le bug retry Stripe, code identique. |
| `fn_supprimer_mon_compte` | `20260607120000_rgpd_suppression_pii_complete.sql` | Commentaires absents et reformatage compacté en prod, code identique. |
| `fn_sync_mission_creneaux` | `20260624170000_plancher_previsionnel_garanti.sql` | Commentaire PLANCHER PRÉVISIONNEL absent et compactage en prod, code identique. |
| `fn_toggle_pool_urgence` | `20260530200000_rcp_par_type_contrat_effectif.sql` | Commentaires uniquement : bloc RCP du repo absent en prod, code identique. |
| `fn_test_purge_mission` | `20260627150000_fn_test_purge_mission.sql` | Commentaires uniquement : prod contient un commentaire garde-fou absent du repo, code identique. |
| `fn_trg_auto_heures_majorees` | `20260417120000_correction_garantie_heures.sql` | Commentaires uniquement : bloc GREATEST du repo absent en prod, code identique. |
| `fn_trg_auto_notify_mission_urgente` | `20260626160000_fix_broadcast_urgence_secrets_push.sql` | Commentaires uniquement : 2 commentaires reformulés/ajoutés en prod, code identique. |
| `fn_trg_verifier_onboarding_etab` | `20260624220000_retirer_rib_gate_onboarding_etab.sql` | Seuls les commentaires diffèrent (code identique hors commentaires) |
| `fn_trg_valider_parrainage_etab_commission` | `20260624230000_parrainage_etab_50_50_credit_commission.sql` | Seuls les commentaires diffèrent (code identique hors commentaires) |
| `fn_update_presence` | `20260514183200_pr3s10a_typing_presence_realtime.sql` | Seuls les commentaires diffèrent (code identique hors commentaires) |
| `fn_typing_start` | `20260514183200_pr3s10a_typing_presence_realtime.sql` | Seuls les commentaires diffèrent (code identique hors commentaires) |
| `fn_update_streak_on_swipe` | `20260515140100_streaks_quotidien.sql` | Seuls les commentaires diffèrent (code identique hors commentaires) |
| `fn_user_id_pour_etablissement` | `20260602120000_secu_etab_init_proprietaire_et_userid_enumeration.sql` | Seuls les commentaires diffèrent (code identique hors commentaires) |
| `fn_verifier_documents_expirants` | `20260630240000_consolider_calcul_tous_documents_valides.sql` | Seuls les commentaires diffèrent (code identique hors commentaires) |
| `next_invoice_number` | `20260413140000_invoicing_module_schema.sql` | Écart de forme uniquement (espaces/commentaires), code identique |
| `next_avoir_number` | `20260417130300_cp_litiges_3_resolution_avoirs.sql` | Seuls les commentaires diffèrent (code identique hors commentaires) |
| `tg_candidature_acceptee_creer_conversation` | `20260514183100_pr1s10a_trigger_chat_acceptation_candidature.sql` | Seuls les commentaires diffèrent (code identique hors commentaires) |

## 4. ABSENT_DU_REPO — 184 fonctions définies en prod sans aucune trace `CREATE` dans le repo

> ⚠️ **Avertissement** : ces fonctions existent et tournent en prod mais **aucune
> migration du repo ne les crée** (pour certaines, seuls des `GRANT`/`ALTER` les
> mentionnent). Elles sont soit antérieures au début de l'historique de migrations
> (typiquement les triggers `dec_*`), soit nées d'actions MCP/Dashboard jamais
> re-capturées. **Le repo ne permet PAS de reconstruire la base** tant qu'elles ne
> sont pas capturées par le squash baseline. Toute archéologie ou modification passe
> par `db/baseline_prod_2026-07-04/functions/` ou `scripts/dump-live-def.sh` —
> chercher dans `supabase/migrations/` est inutile par construction.

### Triggers métier `dec_*` (56) — antérieurs à l'historique de migrations

- `dec_alerte_pause_obligatoire` · `dec_annuler_contrat_si_mission_annulee` · `dec_anti_double_assignation`
- `dec_antifraude_presence` · `dec_appliquer_plafond_rist` · `dec_auto_calculer_cotisations`
- `dec_auto_partager_rib` · `dec_bloquer_changement_proprio_facture` · `dec_bloquer_desinscription_missions`
- `dec_bloquer_modification_audit` · `dec_bloquer_paiement_manuel_facture` · `dec_bloquer_si_facture_impayee`
- `dec_bloquer_suppression_audit` · `dec_bonus_urgence` · `dec_calculer_duree_presence`
- `dec_calculer_net_estime` · `dec_check_coherence_apres_doc_identite` · `dec_check_coherence_apres_rpps`
- `dec_creer_conversation_assignation` · `dec_creer_partage_rib_contrat` · `dec_definir_type_paiement`
- `dec_depart_apres_arrivee` · `dec_detecter_secteur_public_etablissement` · `dec_detecter_secteur_public_facture`
- `dec_evaluer_dans_delai` · `dec_fenetre_pointage` · `dec_idempotence_facture_payee`
- `dec_incrementer_heures_plateforme` · `dec_limiter_liste_attente` · `dec_maj_compteurs_soignant`
- `dec_maj_note_moyenne_etab` · `dec_notifier_changement_mission` · `dec_penalite_annulation_tardive`
- `dec_premiere_mission` · `dec_proteger_champs_commerciaux_etab` · `dec_proteger_contenu_notification`
- `dec_proteger_donnees_financieres_mission` · `dec_proteger_journaux_audit` · `dec_proteger_presence_soignant`
- `dec_proteger_signature_contrat` · `dec_proteger_validation_documents` · `dec_rappel_evaluation`
- `dec_refuser_auto_evaluation` · `dec_refuser_chevauchement_soignant` · `dec_refuser_mission_passee`
- `dec_sanitiser_contrat` · `dec_valider_couleur_theme` · `dec_valider_paiement_facture`
- `dec_valider_type_exercice_soignant` · `dec_verifier_age_minimum` · `dec_verifier_docs_jusqua_fin`
- `dec_verifier_eligibilite_liberal` · `dec_verifier_numerotation_facture` · `dec_verifier_profession_etablissement`
- `dec_verifier_type_contrat_mission` · `dec_verifier_type_exercice_profession`

### Fonctions `fn_*` (125)

- `fn_activer_liberal` · `fn_admin_mandats_stats` · `fn_admin_valider_contrat_etablissement`
- `fn_ajouter_message_litige` · `fn_annuler_mission` · `fn_annuler_mission_etablissement`
- `fn_annuler_serie` · `fn_appliquer_remise_groupe` · `fn_auto_confirmer_honoraires`
- `fn_auto_publier_evaluation` · `fn_auto_revoke_anon_execute` · `fn_auto_terminer_missions`
- `fn_auto_valider_etablissement_siret` · `fn_badge_stats` · `fn_bloquer_delete_doc_verifie`
- `fn_calculer_bfa` · `fn_calculer_bfa_safe` · `fn_calculer_bfa_tous`
- `fn_calculer_cotisations` · `fn_calculer_heures_majorees` · `fn_calculer_heures_totales`
- `fn_calculer_taux_free_transition` · `fn_calculer_taux_free_transition_safe` · `fn_cession_existe`
- `fn_charger_demo_investisseur` · `fn_cloturer_litige` · `fn_commission_info_etablissement`
- `fn_confirmer_honoraires_retrocession` · `fn_consentir_gps` · `fn_consulter_rib_soignant`
- `fn_contester_paiement_soignant` · `fn_declarer_arret_maladie` · `fn_declarer_honoraires_retrocession`
- `fn_deposer_chorus` · `fn_detecter_teleportation` · `fn_diffuser_pool_urgence`
- `fn_ecrire_audit` · `fn_email_documents_expirants` · `fn_email_eligible_liberal`
- `fn_email_factures_impayees` · `fn_email_rappels_j1` · `fn_email_recap_hebdo`
- `fn_enregistrer_siret_liberal` · `fn_envoyer_message` · `fn_est_exclu`
- `fn_est_jour_ferie` · `fn_etablissement_pour_mission` · `fn_etablissements_avec_missions_ouvertes`
- `fn_evaluer_etablissement` · `fn_evaluer_soignant` · `fn_generer_facture`
- `fn_generer_facture_rate_limited` · `fn_generer_jours_feries` · `fn_generer_numero_contrat`
- `fn_generer_numero_contrat_safe` · `fn_generer_numero_facture` · `fn_generer_numero_note_honoraires`
- `fn_get_stripe_account_soignant` · `fn_health_check` · `fn_html_escape`
- `fn_is_valid_uuid` · `fn_litige_pour_mission` · `fn_litiges_etablissement`
- `fn_maj_activite_soignant` · `fn_marquer_messages_lus` · `fn_mes_evaluations_recues`
- `fn_mes_factures` · `fn_mes_soignants_etablissement` · `fn_messages_non_lus`
- `fn_mode_paiement_mission` · `fn_modifier_reference_paiement` · `fn_mon_bfa`
- `fn_mon_etab_alerte_cddu` · `fn_mon_profil_soignant_complet` · `fn_nettoyer_missions_fantomes`
- `fn_nettoyer_partages_rib_expires` · `fn_nettoyer_psc_sessions_expirees` · `fn_nettoyer_tokens_push`
- `fn_note_moyenne` · `fn_notifier_documents_expirants` · `fn_obtenir_conversation`
- `fn_paiements_etablissement` · `fn_pointer_debut_pause` · `fn_pointer_fin_pause`
- `fn_presences_detail_mission` · `fn_professions_liberales` · `fn_protect_facture_montants`
- `fn_protect_message_chat_update` · `fn_protect_message_mission_update` · `fn_protect_paiement_mission`
- `fn_protect_stripe_connect_onboarding` · `fn_protect_stripe_transfer` · `fn_purger_audit_ancien`
- `fn_purger_demo` · `fn_purger_gps_ancien` · `fn_recalculer_tous_paliers`
- `fn_relancer_signatures_contrats` · `fn_rgpd_purge_automatique_inactifs` · `fn_sanitiser_html`
- `fn_sauvegarder_profil` · `fn_set_user_role` · `fn_signer_contrat_etablissement`
- `fn_soignant_stripe_connect_actif` · `fn_souscrire_prevoyance` · `fn_stats_dashboard_etablissement`
- `fn_stats_rh_etablissement` · `fn_supprimer_compte_rate_limited` · `fn_terminer_mission`
- `fn_traiter_reclamation` · `fn_trg_absence_event_score` · `fn_trg_annuler_contrat_orphelin`
- `fn_trg_auto_commission_facturee` · `fn_trg_auto_facture_honoraires` · `fn_trg_coherence_statut_soignant`
- `fn_trg_desistement_garanti` · `fn_trg_email_evaluation` · `fn_trg_email_mission_terminee`
- `fn_trg_email_paiement_confirme` · `fn_trg_sms_annulation_tardive` · `fn_types_exercice_autorises`
- `fn_valider_alerte_presence` · `fn_verifier_api_key` · `fn_verifier_coherence_identite`
- `fn_verifier_coherence_publication` · `fn_verifier_rate_limit`

### Helpers rôle/session (3)

- `est_admin` · `est_soignant` · `mon_role`

## 5. Pourquoi cet audit — les deux incidents du 02/07/2026

1. **Incident enum / trigger parrainage** : un trigger a été réécrit en partant du
   fichier de migration `20260528131400` alors que la **version live avait été
   corrigée depuis** (valeurs d'enum). Résultat : **21 minutes de transitions de
   statut de mission cassées en prod**. Cause racine : un fichier repo obsolète pris
   comme source de vérité — précisément le cas des 51 fonctions du §3.1 et des 184
   du §4.
2. **Incident registre `20260702180753`** : le step « Heal » du workflow
   `deploy-supabase` a purgé du registre `supabase_migrations.schema_migrations` une
   version remote **orpheline récente** (migration appliquée via MCP dont la PR
   n'était pas encore mergée — orpheline par construction). La purge a cassé le
   deploy **suivant** (ordre out-of-order / re-application).

### Garde-fous ancrés dans CLAUDE.md (§ « Garde-fous 9.0 »)

1. **Un seul chemin d'application : le CI `deploy-supabase`.** Plus de
   `apply_migration`/`execute_sql` MCP pour du DDL en temps normal. Exception unique :
   hotfix incident prod, re-capturé en migration **le jour même** + enregistré dans
   `schema_migrations`.
2. **Toute redéfinition part de la définition LIVE** (`scripts/dump-live-def.sh` /
   `pg_get_functiondef`), jamais d'un fichier de migration du repo.
3. **Step « Heal » = fenêtre de grâce 24 h** : plus de purge des versions remote
   orphelines récentes — warning + consigne « merger la PR puis re-run ».
4. **Drift-check quotidien** (`.github/workflows/drift-check.yml`, 5h UTC) : dump du
   schéma prod diffé contre la baseline versionnée `supabase/schema/public.sql`
   (produite par `schema-snapshot.yml`). Rouge = re-snapshot (dérive légitime) ou
   re-capture en migration (dérive sauvage).
5. **Baseline de vérité** : `db/baseline_prod_2026-07-04/` + ce document. Toute
   archéologie de fonction commence là, pas dans les migrations historiques.

## 6. Limites de cet audit (note honnête)

- **Diff textuel normalisé, pas sémantique** : la normalisation replie les espaces
  mais ne parse pas le SQL. Des écarts de commentaires, de quoting
  (`$$` vs `$function$`), de casse de mots-clés ou de qualification de schéma peuvent
  produire des **faux positifs DIFFERENT** — c'est pourquoi 113 des 164 DIFFERENT ont
  été reclassés « cosmétiques » après lecture humaine des agents. À l'inverse, un
  faux négatif MATCH est improbable mais pas exclu (normalisation trop agressive sur
  un littéral de chaîne).
- **Le classement code réel / cosmétique du §3 est un jugement d'agent** par lecture
  des diffs, pas une preuve formelle. En cas de doute sur une fonction précise :
  relire le diff brut dans `db/baseline_prod_2026-07-04/drift/slice_0*.json`.
- **Les surcharges** (overloads, ex. `fn_admin_resoudre_litige` 5 vs 6 params,
  `fn_ouvrir_litige_rate_limited` 2 vs 3 args) sont appariées par signature ; un
  overload prod sans équivalent repo apparaît en DIFFERENT ou ABSENT selon la tranche.
- **Périmètre fonctions uniquement** : structure, policies RLS, grants, cron et edge
  functions sont capturés (snapshot) mais **pas diffés** ici.
- **Cet audit est une photographie, pas la réconciliation.** L'étape 3 du chantier
  9.0 — le **squash baseline** (`supabase db dump` via CI → `supabase/schema/public.sql`
  + drift-check quotidien) — reste l'unique moyen de rendre le repo reconstructible
  et de faire disparaître mécaniquement les 164 DIFFERENT et 184 ABSENT ci-dessus.
