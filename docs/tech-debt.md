# Dette technique — Jolene

## Itération 1 audit pré-lancement — 13 fixes (2026-05-03)

13 fixes appliqués suite à l'audit fonctionnel exhaustif (cf. `docs/audit-fonctionnel-pre-lancement.md`). Tests E2E post-fix : B.8, B.10, C, B.6 validés. Migrations 20260429480000 → 20260429530000.

**Tech-debt restant** :
- B.2 : 7 fonctions ACOS dans pool urgence (fn_matching_soignants, fn_recommander_soignants, fn_pool_urgence_etablissement, fn_soignants_urgence, fn_matcher_soignants_mission, dec_antifraude_presence, fn_detecter_teleportation). Refactor unification Haversine reporté — risque > gain epsilon (Haversine et ACOS donnent des distances équivalentes à <10m près sur < 100km). Cible : Q3 2026 si justification métier.
- B.4 : Toast SIRET ALERTE non-persistante côté UI étab. Fix front-end nécessaire dans `InscriptionEtablissement.tsx` (ajouter toast dans dashboard). À reporter Gabrielle.
- Cohérence enum `EXPIREE` (statut_mission) non utilisée dans transitions. À cleaner ou documenter.
- `factures_honoraires.stripe_payment_intent_id` pas UNIQUE → idempotence Stripe webhook à confirmer côté code TS edge function.

---

## Refonte scoring + médiation litiges complète (2026-05-03)

**Refonte.A → E** livrée et testée (19/19 PASS E2E). Voir docs `module-scoring-v2.md`, `notation-bidirectionnelle.md`, `mediation-litiges.md`.

**Bug prod-critique trouvé en E2E (E.4 S19) — fixé** : `fn_admin_trancher_litige` utilisait `p_action='MISSION_LITIGE'` non présent dans `journaux_audit_action_check`. Migration `20260429430000_refonte_e_4_fix_litige_admin_tranche.sql` ajoute action `LITIGE_ADMIN_TRANCHE` + patch RPC.

**Cleanup v1 livré** (Refonte.E.3, migration `20260429440000_refonte_e_3_cleanup_scoring_v1_inline.sql`) : retiré le calcul score v1 inline dans `dec_mettre_a_jour_fiabilite` (formule `50 + bonus - malus` heuristique). v2 prend complètement le relais via `fn_calculer_score_fiabilite_v2`. Les compteurs (`total_missions_terminees`, `heures_cumulees`, etc.) et la logique badge Ambassadeur restent dans le trigger (utilisés par v2).

### Tech-debt soulevée par la refonte

| Item | Priorité | Cible |
|---|---|---|
| **Composantes ponctualité + réactivité** : poids 15% + 10% mais sources données pas branchées (toujours inactives, redistribuées) | P1 | Q3 2026 |
| **Epsilon floating-point seuil 70** : score `69.999...` (affiché 70.00) classé ARGENT au lieu de OR. À fixer dans `fn_determiner_niveau` ou arrondir avant comparaison | P2 | Q3 2026 |
| **Compteur dénormalisé `total_missions_terminees`** : `fn_calculer_score_fiabilite_v2` se fie à cette colonne maintenue par trigger `dec_mettre_a_jour_fiabilite`. Refactor possible : utiliser `COUNT(*)` direct dans v2 | P3 | Optionnel |
| **Suppression colonne `evaluations` legacy** : table conservée pour historique, à archiver/supprimer dans 6 mois si plus d'usage | P3 | Novembre 2026 |
| **Suppression statuts litiges legacy** (`EN_MEDIATION`, `RESOLU_SOIGNANT`, `RESOLU_ETABLISSEMENT`, `RESOLU_ADMIN`). À retirer du `litiges_statut_check` après migration des litiges historiques | P3 | Novembre 2026 |
| **Suppression RPCs litige legacy** (`fn_demander_mediation_litige`, `fn_cloturer_litige`) — plus appelées par UI Refonte.E.1, à supprimer dans 6 mois | P3 | Novembre 2026 |
| **Page admin modération notations** : RPCs `fn_signaler_notation` + `fn_admin_masquer_notation` prêtes, page UI à créer | P2 | Q3 2026 |
| **Email admin "litige basculé revue"** : actuellement seules les parties sont notifiées | P2 | Selon usage |

---

## J5.E — Prévoyance Madelin : RPC interne dépréciée (2026-05-02)

**Contexte** : J5.E refonte page Prévoyance en mode "liste d'attente" (pas de partenariat April actif, décision business). L'ancienne RPC `fn_souscrire_prevoyance` + tables `plans_prevoyance` + `souscriptions_prevoyance` ne sont plus appelées depuis la nouvelle UI.

**État actuel** :
- `PrevoyanceSoignant.tsx` n'appelle plus `fn_souscrire_prevoyance` (utilise `fn_inscrire_liste_attente_prevoyance` via la nouvelle table `prevoyance_liste_attente`).
- RPC `fn_souscrire_prevoyance` reste en DB (toujours callable via `types.ts`/admin direct, mais aucun frontend ne l'appelle).
- Tables `plans_prevoyance` et `souscriptions_prevoyance` conservées (potentielle réactivation rapide si un partenariat se concrétise).

**Action si non réactivé d'ici novembre 2026 (6 mois)** :
1. `DROP FUNCTION public.fn_souscrire_prevoyance(uuid) CASCADE`
2. `DROP TABLE public.souscriptions_prevoyance` puis `DROP TABLE public.plans_prevoyance`
3. Retirer la colonne `soignants.prevoyance_inscrit` (et 2 colonnes adjacentes `prevoyance_fournisseur`, `prevoyance_numero_contrat`) — adapter le bonus +3 pts de fiabilité dans la formule de `dec_mettre_a_jour_fiabilite` (le bonus ne s'applique plus).
4. Supprimer aussi la mention "+3 points fiabilité" dans la page Prévoyance (déjà retirée dans la refonte J5.E si non réactivé).

**Priorité** : P3 — review novembre 2026.

**Date** : 2026-05-02

---

> **Bilan 2026-04-28 (session "corrige tous les tickets")** : audit
> exhaustif des sections ci-dessous + corrections rapides sur l'audit
> UX soignant (3 derniers `.single()` migrés, raccourcis paie/facturation
> dans profil, redirects orphelins déjà en place). Modules paie + facturation
> complétés (cf. docs/module-bulletin-paie.md et module-facturation.md).
> Reste ~15 P1/P2 lourds documentés ci-dessous (T11, T12+T13, T7,
> Sub-PR 2bis, etc.) — chaque ticket = 1 session dédiée car volume
> >2h chacun. Voir Plan d'attaque en bas du fichier.

## [RÉSOLU] Accès direct à factures_honoraires (2026-04-28)

**Fichier** : `src/pages/MesFacturesHonoraires.tsx:67-71`

**Contexte** : Le composant fait un `.from('factures_honoraires').select('*').eq('id', factureId)` direct depuis le client Supabase (role `authenticated`). Avant le hotfix GRANTs (20260415110000), cette requête échouait silencieusement (masquée par `maybeSingle()` qui retournait `null` au lieu de remonter le 403).

Le GRANT corrige le symptôme (la requête passe maintenant), mais le pattern n'est pas idéal : le SELECT direct expose la structure de la table au client et contourne la couche d'abstraction RPC.

**Action** : Refactorer `MesFacturesHonoraires.tsx` pour utiliser `fn_mes_factures_honoraires` (qui existe déjà et est SECURITY DEFINER) partout, y compris pour le détail d'une facture individuelle. Ajouter un paramètre `p_facture_id` optionnel à la RPC pour le cas détail.

**Statut 2026-04-28** : `MesFacturesHonoraires.tsx` utilise désormais
exclusivement `fn_mes_factures_honoraires` RPC (vérifié grep). Restent
3 accès directs à `factures_honoraires` dans : `FactureHonorairesCard`
(lecture par mission_id, RLS-protégé), `AvoirsList` (admin only),
`facture-honoraires-pdf.ts` (lecture pour génération PDF). Acceptable
en l'état car protégés par RLS soignant_id=auth.uid().

**Priorité** : Post-PR3

**Date** : 2026-04-15

---

## Activer admin-invoke en prod — secrets manquants

**Contexte** : L'edge function `admin-invoke` est déployée et le code est complet (3-layer auth, allowlist, rate limit, audit, notifications). Mais elle est inutilisable sans 2 Supabase Secrets :
- `ADMIN_INVOKE_SALT` : sel pour le hash X-Admin-Confirm
- `OPS_TEST_ADMIN_PASSWORD` : mot de passe du compte ops-test@jolene.app

**Action** : Gabrielle ajoute les 2 secrets dans le dashboard Supabase → Project Settings → Edge Functions → Secrets :
1. `ADMIN_INVOKE_SALT` : n'importe quelle phrase longue aléatoire (30+ chars)
2. `OPS_TEST_ADMIN_PASSWORD` : un mot de passe fort de 20+ chars, puis mettre à jour le hash via `UPDATE auth.users SET encrypted_password = crypt('<nouveau_mdp>', gen_salt('bf')) WHERE email = 'ops-test@jolene.app'`

Instructions détaillées dans `/docs/admin-invoke.md`.

**Priorité** : P2 — à traiter avant PR4

**Date** : 2026-04-16

---

## Supprimer les edge functions proxy de test

**Contexte** : Deux fonctions proxy temporaires restent en prod (neutralisées, verify_jwt=true + 403) :
- `test-invoke-generate-invoice` (P1bis v4 test)
- `invoke-generate-invoice-internal` (P1bis v5 test)

**Action** : Les supprimer via le dashboard Supabase → Edge Functions → Delete pour chacune.

**Priorité** : P3 — nettoyage

**Date** : 2026-04-16

---

## CP4 — fn_calculer_financier_mission doit utiliser mission_creneaux

**Fichier** : trigger `fn_calculer_financier_mission` (migration `20260315170131`)

**Contexte** : Le trigger financier calcule `duree_heures` via `COALESCE(NEW.duree_heures, EXTRACT(EPOCH FROM (fin_le - debut_le)) / 3600.0)`. Quand le sync trigger envoie une valeur non-NULL (cas normal multi-créneaux), le COALESCE la conserve — OK. Mais quand toutes les créneaux sont des pauses, le sync envoie `duree_heures = NULL`, et le fallback recalcule le span brut `(fin_le - debut_le)` — **incorrect**.

**Bug vérifié en prod** : mission avec 2 créneaux pauses (7h-12h + 14h-19h) → `duree_heures = 12h` (span) au lieu de `0h` (somme non-pauses).

**Action** : Modifier `fn_calculer_financier_mission` pour lire directement `mission_creneaux` :
```sql
SELECT COALESCE(SUM(EXTRACT(EPOCH FROM (fin - debut)) / 3600.0), 0)
INTO v_duree
FROM mission_creneaux
WHERE mission_id = NEW.id AND NOT est_pause;
```
Supprimer le fallback `COALESCE(NEW.duree_heures, span)`.

**Priorité** : CP4 — Sub-PR 1 — **RÉSOLU** (migration `20260416160000`)

**Date** : 2026-04-16

---

## CP5 — fn_trg_auto_heures_majorees utilise le span au lieu des créneaux

**Fichier** : trigger `fn_trg_auto_heures_majorees` (fires on UPDATE OF debut_le, fin_le)

**Contexte** : Le trigger auto-détecte les heures nuit/dimanche/férié à partir du span `debut_le`/`fin_le` (colonnes dénormalisées). Avec le multi-créneaux, le span inclut les pauses. Résultat : des heures de nuit sont détectées même pour des missions all-pauses.

**Bug vérifié** : test C (CP4) — mission all-pauses (7h-12h + 14h-19h, les deux en pause) → `heures_nuit = 1`, `montant_majoration_nuit = 6.25€`, `total_brut = 6.25€` au lieu de 0€. Le résidu 6.25€ = 1h nuit × 25€/h × 25% majoration. Source unique : `fn_trg_auto_heures_majorees`.

**Action** : Modifier `fn_trg_auto_heures_majorees` pour itérer sur `mission_creneaux WHERE NOT est_pause` et calculer les majorations par créneau effectif. À corriger en même temps que les 3 autres triggers documentés dans `/docs/triggers-migration-checklist.md` :
- `dec_refuser_chevauchement_soignant` (faux positifs multi-créneaux)
- `dec_verifier_plafond_48h` (surestimation)
- `dec_verifier_repos_11h` (repos calculé sur span pas sur dernier créneau effectif)

**Priorité** : CP5 — Sub-PR 1

**Date** : 2026-04-16

---

## Recalcul post-facturation peut créer des écarts

**Contexte** : Les valeurs `missions.net_a_payer` et `factures_honoraires.montant_ht` divergent déjà (écarts de 3€ à 68€ sur les données test). La facture est calculée au moment de la génération par `generate-invoice` et est ensuite immutable. Les missions peuvent être recalculées ultérieurement par les triggers.

**Règle** : ne JAMAIS recalculer financièrement une mission déjà facturée via un bulk update ou un sync de créneau. Le trigger `trg_protect_creneaux_facture` empêche la modification des créneaux sur les missions facturées. Toute correction post-facture passe par le flow annulation → correction → refacturation avec audit trail (session vars `jolene.admin_correction_mission_id` + `jolene.admin_correction_reason`).

**Priorité** : Documentation — pas d'action code

**Date** : 2026-04-16

---

## [RÉSOLU] Hardening anti-seed-incohérent (2026-04-28)

**Contexte** : 223/268 missions en base ont un `total_brut` incohérent (n'inclut pas les majorations). Toutes sont issues de seed batches Lovable. Les 17 missions créées via le flow normal (RPC + triggers) sont 100% cohérentes. Le problème : les INSERT seed bypassent `fn_calculer_financier_mission`.

**Actions proposées** :

1. **Trigger BEFORE INSERT sur `factures_honoraires`** : vérifie que `montant_ht` est dans un intervalle raisonnable autour de `mission.net_a_payer` (±1% ou ε = 0.01€). Si écart > seuil, bloquer sauf si session variable `jolene.admin_override_facture_montant` est définie avec raison. Audit trail dans `invoice_audit_log`.

2. **Trigger BEFORE INSERT sur `missions`** : vérifie que `total_brut` est cohérent avec `taux × duree + majorations` après passage par `fn_calculer_financier_mission`. En pratique : le trigger `trg_calculer_financier` fire déjà sur INSERT et recalcule. Mais un INSERT via `DISABLE TRIGGER USER` ou `COPY` pourrait bypasser. Protection supplémentaire : CHECK constraint ou trigger dédié qui détecte l'incohérence.

3. **Edge function de diagnostic périodique** (ou cron SQL) : vérifie mensuellement la cohérence missions ↔ factures_honoraires ↔ stripe_transfers. Alerte par email si écart détecté.

**Priorité** : P1 — à traiter avant lancement public (CP6 ou post-CP6)

**Date** : 2026-04-16

**Résolution 2026-04-28** :

Audit MCP : actions 1 et 2 sont **déjà en place** en prod (découvertes
en testant) :

- `fn_anti_seed_facture_honoraire` (trigger BEFORE INSERT/UPDATE sur
  `factures_honoraires`) : bloque si `montant_ht` diverge de
  `mission.net_a_payer` de plus de 0.50€. Bypass via contexte
  `jolene.generate_invoice_context='true'` ou override admin
  `jolene.admin_seed_override_reason`. Les overrides sont audités
  (`OVERRIDE_ANTI_SEED` dans `journaux_audit`).

- `fn_anti_seed_mission` (trigger sur `missions`) : vérifie que
  `total_brut`/`net_a_payer` sont cohérents avec `taux × heures +
  majorations` ET que `taux`/`heures` sont renseignés. Mêmes
  mécanismes de bypass.

Action 3 ajoutée par migration
`20260428240000_hardening_anti_seed_incoherent.sql` :
- RPC `fn_diagnostic_coherence_financiere()` SECURITY DEFINER
  admin-only retourne JSONB :
  - `missions_incoherentes` : count + échantillon (10) des missions
    où `total_brut` diverge de l'attendu calculé.
  - `factures_ecart_mission` : count + échantillon des factures
    `FACTURE` non-BROUILLON/REMPLACEE/ANNULEE où `montant_ht` diverge
    de `mission.net_a_payer` de plus de max(1%, 1€).
  - `stripe_transfers_orphelins` : count + échantillon des transferts
    pointant vers une mission qui n'a pas de FACTURE active.
- Test instantané sur la prod (28/04/2026) : `missions_incoherentes=3`
  (les 3 missions audit-* test seed historiques), `factures=0`,
  `transfers=0`.

Pour activer un cron mensuel, Gabrielle peut programmer l'appel via
Supabase Dashboard → Database → Cron jobs ou via une edge function
dédiée qui appelle la RPC + envoie un email aux admins si non-zéro.

---

## T1 — Validation juridique planchers CCN pré-lancement

**Contexte** : CP5a retient des planchers prudents (nuit >= 25%, dimanche >= 25%, férié >= 50%) calibrés au-dessus des minima CCN FHP n°2264 art. 82.1/82.2, sans validation juridique formelle. Le calibrage couvre a priori FHP, FEHAP, CCU, Croix-Rouge, FPH, mais n'a pas été confirmé par un avocat spécialisé santé.

**Action** : Consultation avocat santé (budget estimé 1500–2500€, ~2h) avec brief préparé :
1. Les planchers 25/25/50 couvrent-ils toutes les CCN santé visées (FHP, FEHAP, CCU, CRF, FPH) ?
2. Si une convention exige plus, de combien ? Faut-il un plancher par CCN ?
3. Quelles mentions obligatoires sur la facture honoraires soignant (mandat art. 289 I-2 CGI) ?
4. Quel risque de requalification URSSAF salarié déguisé dans le modèle Jolene ?

**Priorité** : P1 — bloquant go-live public

**Date** : 2026-04-16

---

## T2 — Automatiser détection divergence backfill

**Contexte** : La vérification pré-backfill CP5a (section 1.4) liste les taux pour inspection manuelle. Suffisant pour ~10 missions organiques actuelles.

**Action** : Pour volumes supérieurs (>100 missions organiques), automatiser le calcul `total_brut` recalculable à partir des taux backfillés vs `total_brut` stocké. Script SQL ou edge function qui compare et alerte si écart > 0.01€.

**Priorité** : P3 — avant 1000 missions en base

**Date** : 2026-04-16

---

## T3 — Audit trail modifications description post-gel

**Contexte** : CP5a décision Gabrielle — `description` n'est pas bloqué après gel (ajouts logistiques légitimes : "blouse fournie sur place", "entrée parking B", corrections typo). Mais les modifications post-assignation doivent être traçables pour audit.

**Action** : Logger toute modification de `missions.description` quand `fige_le IS NOT NULL` dans une table d'audit (ex: `mission_audit_log`). Payload : `old_description`, `new_description`, `modified_by`, `modified_at`.

**Priorité** : P3

**Date** : 2026-04-16

---

## T4 — Notifier le soignant si service modifié post-gel

**Contexte** : CP5a décision Gabrielle — `service` n'est pas bloqué après gel (réaffectation service légitime en étab santé). Mais le soignant doit être informé du changement.

**Action** : Envoyer un email/SMS au soignant assigné quand `missions.service` est modifié et `fige_le IS NOT NULL`. Message type : "Votre mission [intitule] du [date] a été déplacée du service [ancien] au service [nouveau]."

**Priorité** : P3

**Date** : 2026-04-16

---

## T5 — Phase 2 sync + JWT context pour heures majorées

**Contexte** : La Phase 2 du sync trigger (`jolene.sync_in_progress = false`, UPDATE duree_heures) déclenche `fn_trg_auto_heures_majorees` qui recalcule les heures nuit/dimanche/férié. Mais `dec_proteger_mission_soignant` (#14) freeze ces champs si le caller n'est pas admin/etab (vérifie `est_admin()` via JWT). En prod OK (UI authenticated = etab/admin). En batch/migration sans JWT, les heures majorées ne se propagent pas.

**Action** : Documenter dans `/docs/bulk-updates-playbook.md` : toute modification de créneaux en batch doit être précédée de `SELECT set_config('request.jwt.claims', '{"sub": "<admin_id>", "role": "authenticated"}', true)`.

**Priorité** : P3

**Date** : 2026-04-16

---

## T6 — Test plafond 48h avec heures externes déclarées

**Contexte** : Le trigger `dec_verifier_plafond_48h` refondé en CP5a lit `attestations_heures_externes.heures_salarie` pour les heures travaillées hors Jolene. Actuellement 0 attestations en base → `v_heures_externes = 0` systématiquement. Le trigger est testé uniquement avec des heures Jolene (test 4c-blocage : 55h > 48h).

**Action** : Quand Jolene intègre un import d'heures externes (API étab, déclaration soignant), ajouter un test avec `heures_salarie > 0` pour vérifier que le cumul Jolene + externes est correctement calculé.

**Priorité** : P3

**Date** : 2026-04-16

---

## T7 — Cron détection créneaux effectifs jamais fermés

**Contexte** : CP5b risque R4 — un soignant peut ouvrir un créneau effectif (scan OUVERTURE) puis ne jamais scanner la FERMETURE. Le créneau reste `fin IS NULL` indéfiniment. Le flow `fn_declarer_fin_retroactive` permet la correction manuelle, mais il n'y a pas de détection automatique.

**Action** : Edge function schedulée (pg_cron ou Supabase cron) qui détecte `mission_creneaux WHERE type_creneau = 'EFFECTIF' AND fin IS NULL AND debut < now() - INTERVAL '24 hours'`. Envoyer notification au soignant + flaguer `validation_etab_requise` sur les scans associés.

**Priorité** : P2

**Date** : 2026-04-16

---

## T8 — Batch recalc financials pour les 265 missions existantes

**Contexte** : CP5b Step 4 a découvert que `trg_auto_heures_majorees` ne fireait que sur `UPDATE OF debut_le, fin_le` — pas sur changement de créneau (via sync). Résultat : quand `fn_calculer_financier_mission` fire sur changement de `duree_heures`, il utilise `heures_*` stales.

Le test T5 a révélé que 2/3 missions sample avaient `total_brut` incorrect (majorations dimanche/férié manquantes dans total_brut alors que `heures_dim/ferie` étaient non-nuls).

Étendu en Step 4 : `trg_auto_heures_majorees` fire maintenant sur `UPDATE OF debut_le, fin_le, duree_heures`. Mais les 265 missions existantes ont encore des `total_brut` stales.

**Action** : Script SQL qui force un recalc sur toutes les missions :
```sql
-- Force recalc via no-op UPDATE on duree_heures (fires auto_heures + calculer_financier)
UPDATE missions SET duree_heures = duree_heures WHERE statut != 'OUVERTE';
```

Attention : ne PAS toucher les missions facturées (trigger `trg_protect_creneaux_facture` pourrait bloquer). Filtrer par absence de facture émise, ou utiliser bypass admin.

**Priorité** : P3 — Les 265 missions test seront purgées en CP6. Recalcul batch uniquement nécessaire si des missions test sont conservées post-purge.

**Date** : 2026-04-16

---

## [RÉSOLU] Sub-PR 2bis — Gestion admin des taux commission (2026-04-28)

**Contexte** : Le taux commission est aujourd'hui fixé par `etablissements.taux_commission_negocie` (défaut 15%). Aucune gestion multi-étabs/groupe ni UI admin de modification. Bloquant avant acceptation de clients multi-établissements sous contrat-cadre.

**Scope** :
- Table `groupes_etablissements` (nom, siret, taux_commission_negocie, contrat_debut, contrat_fin)
- Colonne `etablissements.groupe_id` (FK nullable)
- Règle cascade : `missions.taux_commission_fige` au gel = `COALESCE(etab.taux_commission_negocie, groupe.taux_commission_negocie, 15)`
- UI admin dans dashboard : liste étabs/groupes, modification taux avec raison, audit log
- Audit des changements de taux dans `journaux_audit`
- Application : nouveaux taux impactent seulement les futures missions (gel existant préservé)

**Priorité** : P1 — à faire avant acceptation de clients multi-étabs

**Date** : 2026-04-16

**Résolution 2026-04-28** : migration
`20260428250000_subpr2bis_taux_commission_groupes.sql` :

- Colonnes ajoutées sur `groupes_sante` : `taux_commission_negocie`
  (CHECK 0..100), `contrat_debut`, `contrat_fin`.
- Modification de `fn_geler_mission_a_assignation` pour cascade
  STRICTE `etab.taux_commission_negocie > groupe.taux_commission_negocie
  > 15` (correction d'un piège : `missions.taux_commission` a un
  default 15.00 qui aurait court-circuité la cascade groupe ; le
  trigger ignore désormais ce champ et lit directement la cascade).
- Audit `GEL_APPLIED` enrichi avec `taux_commission_source`
  (`etablissement` | `groupe` | `defaut_15`).
- RPC `fn_admin_modifier_taux_commission(p_etablissement_id?,
  p_groupe_id?, p_nouveau_taux, p_raison)` : guard admin + raison
  obligatoire + audit `TAUX_COMMISSION_MODIFIE` + bornes 0..100.
- RPC `fn_admin_lister_taux_commission()` : retourne JSONB groupes +
  établissements avec taux résolu et source pour la page admin.
- Page UI `/admin/taux-commission` (`AdminTauxCommission.tsx`) :
  liste groupes + établissements avec source colorée
  (Étab/Groupe/Défaut), modal d'édition avec champ raison
  obligatoire, lien dans sidebar Finances.

**Tests SQL via MCP** (3 cas cascade + 1 listing + 4 guards) :
1. Cascade etab > groupe : étab=8% → fige 8%. PASS.
2. Cascade groupe : étab=NULL, groupe=10% → fige 10%. PASS.
3. Cascade défaut : étab=NULL, groupe=NULL → fige 15%. PASS.
4. RPC `fn_admin_lister_taux_commission` retourne `success:true`. PASS.
5. Guards : non-admin → "Admin requis", raison vide → "Raison
   obligatoire", taux >100 → "hors bornes", les deux IDs → "exactement
   un".

**Application** : conformément à la spec, les changements de taux
n'impactent que les **futures missions assignées**. Les missions déjà
gelées (`fige_le IS NOT NULL`) conservent leur `taux_commission_fige`
historique intact.

---

## [RÉSOLU] T9 — Gel de facture par période (2026-04-29)

**Contexte initial** : `CP-LITIGES-2` (trigger `trg_litige_gel_degel_facture`) gèle **toutes** les factures non-PAYEE d'une mission quand un litige de catégorie `PRESENCE`, `CONDITIONS` ou `COMPORTEMENT` est ouvert. La granularité par période n'est pas possible tant que les colonnes `periode_debut` / `periode_fin` n'existent pas sur `factures_honoraires` (elles arrivent avec Partie 2 — facturation hebdomadaire libérale).

**Exemple du problème** : mission libérale de 4 semaines, soignant conteste ses heures sur la semaine 1. Aujourd'hui → factures S1, S2, S3, S4 toutes gelées. Attendu → seule S1 gelée, S2-S4 continuent.

### Pourquoi T9 dans sa forme définitive est BLOQUÉ par Partie 2

Audit DB confirmé le 2026-04-28 :
1. `factures_honoraires` n'a **pas** de colonnes `periode_debut` / `periode_fin` (elles arriveraient avec Partie 2).
2. Aucune table `facturation_periodes` n'existe — le découpage hebdomadaire n'est pas modélisé.
3. Modèle actuel = **1 facture par mission** (FK directe `factures_honoraires.mission_id`, contrainte UNIQUE sur les factures FACTURE). Il n'y a structurellement pas plusieurs factures à filtrer par chevauchement de période.
4. `generate-invoice` produit 1 facture pour la mission entière, pas une par semaine.
5. `litiges` n'a pas de colonnes `periode_*` non plus — il n'y a aucun moyen de stocker la période litigieuse côté contexte du litige.

Tant que ces 5 points ne sont pas livrés (Partie 2), filtrer par chevauchement de période n'a pas d'objet.

### Amélioration intermédiaire livrée (2026-04-28)

Migration `20260428260000_t9_gel_facture_scope.sql` — permet à l'admin de moduler **manuellement** le scope du gel sans attendre Partie 2 :

- Colonne `litiges.gel_facture_scope text NOT NULL DEFAULT 'MISSION_ENTIERE'` avec CHECK :
  - `MISSION_ENTIERE` (défaut, comportement historique)
  - `FACTURE_UNIQUE` (force gel uniquement de `litige.facture_id`, même pour PRESENCE/CONDITIONS/COMPORTEMENT)
  - `AUCUN` (litige informatif/réputationnel, pas de gel financier)
- `fn_trg_litige_gel_degel_facture` mis à jour pour respecter le scope (FINANCIER reste sur `facture_id` ; les 3 autres catégories suivent le scope).
- RPC `fn_admin_modifier_gel_scope_litige(p_litige_id, p_nouveau_scope, p_raison)` SECURITY DEFINER admin-only :
  - Validation guard admin + scope autorisé + raison obligatoire.
  - Dégèle les factures actuellement gelées par le litige puis re-gèle selon le nouveau scope (atomique).
  - Audit `LITIGE_GEL_SCOPE_MODIFIE` via `fn_ecrire_audit_safe`.

### Action restante (post-Partie 2)

Quand Partie 2 sera livrée :
1. Ajouter une 4ᵉ valeur `'PERIODE_LITIGIEUSE'` au CHECK `litiges_gel_facture_scope_check`.
2. Ajouter colonnes `periode_debut` / `periode_fin` sur `litiges` (ou déduction via `presence.pointage_arrivee_le` / `pointage_depart_le`).
3. Étendre `fn_trg_litige_gel_degel_facture` pour la branche `PERIODE_LITIGIEUSE` : ne geler que les factures dont `[periode_debut, periode_fin]` chevauche `[litige.periode_debut, litige.periode_fin]`.
4. Exception conservée : `SECURITE_DANGER` ou `COMPORTEMENT` avec gravité confirmée par admin → gèle toute la mission (cf. audit Sub-PR 2 quater, précision 14).

**Priorité** : P1 — amélioration intermédiaire LIVRÉE, scope définitif reste à traiter dès livraison Partie 2

**Date** : 2026-04-17 (création) / 2026-04-28 (amélioration intermédiaire)

---

## T10 — Évaluer rate limit litiges : 3/heure vs 3/24h

**Contexte** : Le code `fn_ouvrir_litige_rate_limited` applique historiquement 3 litiges par heure par entité. L'audit Sub-PR 2 quater proposait 3/24h. Après discussion, le code actuel (3/heure) est conservé pour ne pas casser les scénarios admin/support légitimes. La clé seed a été renommée de `rate_limit_litiges_par_24h` en `rate_limit_litiges_par_heure` par cohérence (CP-LITIGES-2 FIX-A).

**Action** : si les feedbacks utilisateurs révèlent des abus (spam 3/heure × 24h = 72/jour), ouvrir à 3/24h en :
1. Renommant à nouveau la clé en `rate_limit_litiges_par_24h` (valeur 3).
2. Modifiant le WHERE `cree_le > NOW() - INTERVAL '1 hour'` → `'24 hours'` dans `fn_ouvrir_litige_rate_limited`.
3. Reconsidérer en parallèle les exceptions `SECURITE_DANGER` (toujours autoriser même après rate limit).

**Priorité** : P3 — attendre retours terrain

**Date** : 2026-04-17

---

## T11 — Audit exhaustif des objets SQL fantômes (types.ts vs migrations)

**Contexte** : Pendant CP-LITIGES-3, j'ai découvert que `fn_admin_resoudre_litige` était référencée dans `src/integrations/supabase/types.ts:4455` (et appelée depuis `AdminModeration.tsx`) sans qu'aucune migration locale ne la crée. Inversement, `types.ts` ne reflète pas toujours les colonnes ajoutées par des migrations récentes (ex: `factor_id`, `chorus_*` de `20260413140000`). Ces décalages créent deux risques :
1. Des fonctions SQL actives en prod sans historique git → impossibilité de reconstruire l'état depuis zéro.
2. Des colonnes absentes de types.ts → le frontend ne peut pas les utiliser correctement.

**Action** :
1. Écrire un script `scripts/audit-phantom-objects.ts` qui :
   - Parse `types.ts` pour extraire toutes les fonctions référencées + leurs signatures.
   - Grep toutes les migrations pour trouver les `CREATE FUNCTION` / `ALTER TABLE ADD COLUMN`.
   - Compare les deux listes et remonte les écarts (fonctions orphelines, colonnes manquantes).
2. Pour chaque objet fantôme identifié : créer une migration de "retro-engineering" qui reconstitue l'état.
3. Régénérer `types.ts` depuis la prod via `supabase gen types typescript` après chaque migration majeure.

**Priorité** : P2 — avant Sub-PR 3 (consolidation)

**Date** : 2026-04-17

---

## [RÉSOLU] T12 — Câblage stripe_payment_intent_id sur factures_honoraires (2026-04-28)

**Contexte** : La colonne `factures_honoraires.stripe_payment_intent_id` a été ajoutée par CP-LITIGES-3 comme placeholder pour le refund auto (<120j) des avoirs. Actuellement, `stripe-connect-pay-mission` écrit `stripe_payment_intent_id` sur la table `stripe_transfers` (ligne 293-309) mais ne le propage PAS vers `factures_honoraires`. Résultat : `fn_admin_resoudre_litige` cas AVOIR tombera toujours sur `mode_remboursement = VIREMENT_MANUEL` même pour des factures payées via Stripe il y a moins de 120j.

**Action** : trois options à trancher en Sub-PR 3 :
- **A — Trigger propagation** : AFTER INSERT/UPDATE sur `stripe_transfers` → UPDATE `factures_honoraires.stripe_payment_intent_id = NEW.stripe_payment_intent_id WHERE mission_id = NEW.mission_id`. Simple mais couplage direct.
- **B — Edge function stripe-webhook étendu** : au webhook `checkout.session.completed` ou `payment_intent.succeeded`, faire le UPDATE factures_honoraires.
- **C — Refacto `generate-invoice`** : au moment de l'émission, lire la dernière entrée `stripe_transfers` pour cette mission et copier `stripe_payment_intent_id`.

Ma recommandation : **B** (webhook = source de vérité la plus fiable, cohérent avec stripe-webhook existant).

**Priorité** : P1 — avant Sub-PR 3 (sinon les avoirs AUTO_STRIPE ne se déclencheront jamais)

**Date** : 2026-04-17

**Résolution 2026-04-28 (option B simplifiée — trigger SQL, plus
robuste qu'un appel webhook)** :
- Migration `20260428230000_t12_propagate_stripe_payment_intent.sql`.
- Trigger `trg_propage_stripe_payment_intent` AFTER INSERT OR UPDATE
  OF stripe_payment_intent_id, mission_id sur stripe_transfers.
- Fonction `fn_propage_stripe_payment_intent_trg` SECURITY DEFINER
  qui propage `stripe_transfers.stripe_payment_intent_id` →
  `factures_honoraires.stripe_payment_intent_id` via `mission_id`
  (note : `stripe_transfers.facture_id` pointe vers `factures` —
  commission Jolene → étab — pas vers `factures_honoraires`,
  d'où la jointure par `mission_id`).
- Filtre sur `type_document='FACTURE'` (pas les AVOIRs).
- Backfill exécuté pour les `stripe_transfers` existants qui
  avaient un PI mais n'avaient pas propagé.
- L'immutabilité `factures_honoraires` post-EMISE NE bloque PAS
  `stripe_payment_intent_id` (vérifié dans
  `fn_protect_facture_honoraire_immutability`).

Tests SQL via MCP (compte audit-medecin LIBERAL) :
1. INSERT stripe_transfer avec PI → FACTURE reçoit le PI, AVOIR
   sur même mission reste NULL. PASS.
2. UPDATE stripe_transfer pour ajouter le PI a posteriori →
   propagation immédiate. PASS.

---

## [RÉSOLU] T13 — Edge function process-stripe-refunds à finaliser (2026-04-28)

**Contexte** : CP-LITIGES-4 livre un squelette d'edge function `process-stripe-refunds` qui :
- Authentifie par `service_role`.
- Log un ping de monitoring (heartbeat).
- Ne consomme PAS encore la queue `stripe_refunds_queue`.

Cette fonction sera consommée une fois que T12 aura rempli `stripe_payment_intent_id` sur factures_honoraires, pour transformer les avoirs `AUTO_STRIPE` en vraies transactions Stripe.

**Action** :
1. Dans la function, ajouter : `SELECT * FROM stripe_refunds_queue WHERE statut = 'EN_ATTENTE' ORDER BY cree_le LIMIT 20` (batch).
2. Pour chaque ligne : appeler Stripe API `refunds.create({ payment_intent, amount, reason: 'requested_by_customer', metadata: { avoir_id } })`.
3. UPDATE queue : `statut='TRAITE'`, `stripe_refund_id`, `traite_le=NOW()`. Sur erreur : `statut='ECHEC'`, `erreur=msg`, `tentatives=tentatives+1`.
4. UPDATE `factures_honoraires SET statut='REMBOURSE', date_remboursement=NOW(), reference_remboursement=stripe_refund_id WHERE id = avoir_id`.
5. Ajouter un schedule Supabase dashboard (ex: toutes les 30 min).

**Priorité** : P1 — couplé à T12

**Date** : 2026-04-17

**Résolution constatée 2026-04-28** : la fonction `process-stripe-refunds`
(version 85 actuellement déployée) est en réalité **entièrement
implémentée** depuis CP-STRIPE-5 (H3+A21/T13). Audit du code source
côté Supabase confirme :
- Auth Bearer service_role.
- SELECT EN_ATTENTE avec `tentatives < MAX (3)` et
  `dernier_essai_le.lt now() - 15min` (anti-burst).
- Lock atomique `EN_ATTENTE → EN_COURS` par UPDATE conditionnel
  (idempotent multi-cron).
- `stripe.refunds.create({ payment_intent, amount, reason, metadata })`
  avec metadata `avoir_id`, `facture_origine_id`, `queue_id`,
  `source: 'jolene_refunds_cron'`.
- Gestion erreurs : permanents (`payment_intent_unexpected_state`,
  `amount_too_large`, `charge_disputed`, `charge_expired`,
  `missing_source`, `resource_missing`, `StripeAuthenticationError`)
  → ECHEC + alert admin via send-email type
  `REFUND_ECHEC_ADMIN`. Retryables → EN_ATTENTE + tentatives+1.
- Idempotence Stripe via `charge_already_refunded` → TRAITE.
- 3e tentative échouée → ECHEC permanent + alert admin.
- Audit trail `FINANCE_REFUND_TRAITE_IDEMPOTENT` /
  `FINANCE_REFUND_ECHEC` / `FINANCE_REFUND_RETRY` via
  `fn_ecrire_audit_safe`.
- Webhook `charge.refunded` (CP-STRIPE-4) fait UPDATE TRAITE
  idempotent en filet de sécurité.

Action restante côté Gabrielle : configurer le **schedule cron**
(Supabase Dashboard → Project → Edge Functions → process-stripe-refunds
→ Schedule, par ex. `*/30 * * * *`). Sans cron, la queue ne sera
consommée que par appel manuel. Couplé à T12 (résolu) : les avoirs
AUTO_STRIPE peuvent désormais cibler le bon `stripe_payment_intent_id`.

---

## T14 — Regen PDF/XML avoir : passer en déclenchement direct ✅ RÉSOLU

**Contexte** : CP-LITIGES-6 câble la regénération des PDF/XML (factures ajustées + avoirs) via le cron quotidien `litige-escalation-cron` qui scanne `factures_honoraires.pdf_a_regenerer = TRUE`. Inconvénient : si un admin résout un litige à 09h, le PDF de l'avoir ne sera disponible que le lendemain à 08h UTC.

**Action** : passer à un déclenchement direct en appelant `generate-invoice` depuis `fn_admin_resoudre_litige` (CP3) via `pg_net.http_post`. Vérifier d'abord que `pg_net` est disponible sur l'instance Supabase. Alternative : appel côté frontend admin juste après le RPC `fn_admin_resoudre_litige` (moins robuste car dépend du client). Conserver le scan cron comme filet de sécurité en cas d'échec du direct.

**Priorité** : P2 — amélioration UX (résolution pas bloquante mais délai frustrant)

**Date** : 2026-04-17

**Résolution (CP-LITIGES-7a FIX 18, migration `20260417130712_fix18_pg_net_regen_immediat.sql`)** :
- `CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions` (v0.19.5 déjà installée).
- Helper `fn_trigger_regen_pdf_immediate(UUID) RETURNS BIGINT` : lit URL depuis `parametres_litiges.generate_invoice_url`, clé depuis `vault.decrypted_secrets.service_role_key`, appelle `net.http_post` async. Retourne `request_id` ou `NULL` si config absente (dégradation gracieuse).
- `fn_admin_resoudre_litige` : appel direct après chaque UPDATE `pdf_a_regenerer=TRUE` (3 sites : RECALCUL, ANNULER_REEMETTRE, AVOIR). `request_id` consigné dans audit RGPD via nouveau champ JSONB `regen_pdf_request_ids`, également retourné par la RPC.
- Edge function `generate-invoice` : regex `/^admin_resoudre_litige_immediate$/` ajoutée aux `VALID_REASON_PATTERNS`.
- Cron `litige-escalation-cron` conservé en filet de sécurité : filtre `modifie_le < NOW() - INTERVAL '1 hour'` dans `fn_lister_factures_a_regenerer` pour ne pas doubler les appels en vol.

---

## T15 — Type email `RELANCE_FACTURE` orphelin (emails impayés perdus) ✅ RÉSOLU

**Contexte** : `src/pages/admin/AdminImpayees.tsx` (bouton "Relance" admin) envoyait `type: 'RELANCE_FACTURE'` à `send-email`. Ce type était whitelisté dans `ALLOWED_TYPES` de `send-email/index.ts` mais AUCUN `case` ne le rendait → `renderTemplate` renvoyait `null` et l'email n'était jamais envoyé. Seul `RAPPEL_FACTURE` (convention dominante `RAPPEL_*`) avait un template valide. Bug silencieux : aucune erreur visible, juste pas d'email aux étabs impayés. Identifié lors de l'audit CP-LITIGES-7a FIX 0 (registre templates).

**Action** : aligner sur la convention `RAPPEL_*`. `AdminImpayees.tsx` → envoie `RAPPEL_FACTURE` avec data keys conformes au template (`numero`, `facture_id`, `montant_ttc`, `date_echeance`). `RELANCE_FACTURE` retiré de `ALLOWED_TYPES`. Requête historique `notifications.type` étendue à `['RAPPEL_FACTURE', 'RELANCE_FACTURE']` pour conserver le comptage des relances pré-fix.

**Priorité** : P1 — bug de fonctionnalité admin, relances jamais parties.

**Date** : 2026-04-17

**Résolution (post-CP-LITIGES-7a)** :
- `src/pages/admin/AdminImpayees.tsx` : `type: 'RAPPEL_FACTURE'` + data keys alignés sur le template.
- `supabase/functions/send-email/index.ts` : `RELANCE_FACTURE` retiré de `ALLOWED_TYPES`.
- `tests/litiges/templates-structure.test.ts` : ajout `RAPPEL_FACTURE` + régression `RELANCE_FACTURE` interdit.
- `docs/templates-email-jolene.md` : section "Convention de nommage — rappels" + note historique.

---

## [RÉSOLU] T18 — fn_ouvrir_litige_rate_limited : fenêtres F2/F3 ineffectives

**Contexte** : `fn_ouvrir_litige_rate_limited` passait `p_facture_id=NULL` à `fn_fenetre_contestation_ouverte` pour tous les types, rendant les fenêtres F2 (48h libéral post-émission) et F3 (60j salarié post-paiement) totalement ineffectives pour `DESACCORD_MONTANT_FACTURE`, `FRAIS_COMPLEMENTAIRES` et `NON_PAIEMENT`. Un soignant pouvait contester une facture émise il y a 1 an sans aucun blocage.

**Impact** : faille métier critique — les règles de prescription financière n'étaient pas appliquées.

**Résolution** : migration `20260417130721_fix_t18_fenetre_financier_facture_lookup.sql`
- `fn_ouvrir_litige_rate_limited` : lookup `factures_honoraires WHERE mission_id AND statut <> 'BROUILLON'` pour types financiers, passage du `v_facture_id` résolu à `fn_fenetre_contestation_ouverte` + stockage dans `litiges.facture_id`.
- `fn_admin_creer_litige_force` : même lookup pour consistance + alimentation du trigger de gel facture.
- Tests : `tests/litiges/fix-t18-fenetre-financier.test.sql` — 5 scénarios (libéral <48h OK, >48h KO, salarié <60j OK, >60j KO, pas de facture → erreur).

**Statut** : RÉSOLU

**Date** : 2026-04-20

---

## [RÉSOLU] T19 — fn_litiges_escalader_auto + fenêtre contestation : flag global au lieu du contrat figé

**Contexte** : `fn_litiges_escalader_auto` et `fn_fenetre_contestation_ouverte` lisaient `soignants.est_salarie_etablissement` (flag global du profil) pour déterminer le délai applicable (72h libéral vs 5 j.o. salarié pour escalade ; 48h vs 60j pour contestation facture). Pour un profil MIXTE — soignant salarié dans étab A et libéral dans étab B — ce flag global est faux pour la mission concernée → délais incorrects (72h appliqué à du salarié, ou 5 j.o. à du libéral).

**Impact** : faille métier : escalades trop tardives ou trop précoces selon l'inversion ; même type d'incohérence sur les fenêtres de contestation factures.

**Résolution** : migration `20260417130722_fix_t19_escalade_type_contrat_applique.sql`
- Lecture prioritaire de `missions.type_contrat_applique` (enum `LIBERAL`/`SALARIE`, figé à l'assignation par FIX 3).
- Fallback documenté sur `soignants.est_salarie_etablissement` quand la colonne mission est NULL (missions antérieures au FIX 3 non backfillées) — préserve la rétrocompat.
- Application cohérente dans les deux RPCs (escalade + fenêtre).
- Tests : `tests/litiges/fix-t19-escalade-type-contrat.test.sql` — 3 scénarios (mission LIBERAL prime sur flag SALARIE, mission SALARIE prime sur flag LIBERAL, mission NULL → fallback flag).

**Statut** : RÉSOLU

**Date** : 2026-04-20

---

## [RÉSOLU] T20 — fn_cloturer_litige_mutuel sans audit RGPD

**Contexte** : `fn_cloturer_litige_mutuel` ne traçait aucune entrée dans `journaux_audit` lors de l'accord individuel (soignant ou étab) ni lors de la clôture amiable bilatérale. Incohérent avec les autres RPCs litiges (`fn_ouvrir_litige_rate_limited` → `LITIGE_OUVERTURE`, `fn_admin_resoudre_litige` → `LITIGE_RESOLUTION`, etc.).

**Impact** : conformité RGPD réduite — impossible de retracer une clôture amiable dans les journaux d'audit.

**Résolution** : migration `20260417130723_fix_t20_audit_cloture_amiable.sql`
- Après chaque accord individuel : audit `LITIGE_ACCORD_CLOTURE` avec partie + état des accords précédents.
- Si le 2e accord déclenche la résolution : audit `LITIGE_CLOTURE_AMIABLE` avec flag `cloture_par_accord_bilateral`.
- `fn_litiges_escalader_auto` déjà couvert (`LITIGE_ESCALADE_AUTO` dans CP-LITIGES-4/FIX T19).
- Tests : `tests/litiges/fix-t20-audit-cloture.test.sql` — 2 scénarios (1 accord → 1 audit, 2e accord → 2e audit + clôture audit).

**Statut** : RÉSOLU

**Date** : 2026-04-20

---

## Warmup réputation Outlook (1-3 mois passive) — 2026-04-29

**Statut** : passif, attente naturelle.

Le domaine `jolene.app` (créé avril 2026) arrive en spam Outlook /
Hotmail / Live malgré une auth complète (SPF + DKIM Resend × 3 +
DMARC strict + sender humain `bonjour@jolene.app`). Pas un bug —
réputation stricte des fournisseurs Microsoft envers les nouveaux
domaines. Comptez 1 à 3 mois pour normalisation.

**Mitigations en place** (J2.3.C, commits 8c35e439 + ce commit) :
- Page `/inscription/succes` post-inscription qui prévient les users
  Outlook + donne actions concrètes (marquer non-spam, ajouter contact,
  règle Outlook).
- Article centre d'aide `je-n-ai-pas-recu-d-email`.
- Footer email enrichi (mention "vous recevez parce que…", lien
  préférences notifs, RCS Paris, contact DPO).
- Doc `docs/deliverability-warmup.md` avec plan détaillé court / moyen /
  long terme + actions à faire si problème persiste après 6 mois.

**À faire si pas résolu après juillet 2026** :
- Inscription SNDS Microsoft (https://sendersupport.olc.protection.outlook.com/snds/)
- Investigation headers + content email
- En dernier recours : changement provider (Postmark) — surtout PAS
  changer de domaine.

---

## Plan d'attaque résiduel (2026-04-28)

Synthèse exécutive après recensement exhaustif. Items hors scope code
(consultation avocat, action manuelle Gabrielle dashboard) marqués 🔧
manuel. Tickets RÉSOLU précédés de [RÉSOLU] dans le titre.

### P1 — bloquants pré-prod / clients

| # | Ticket | Action | Charge estimée |
|---|---|---|---|
| Hardening anti-seed (RÉSOLU 2026-04-28) | Triggers anti-seed factures+missions DÉJÀ en place + RPC diagnostic ajoutée. Cron mensuel reste manuel Gabrielle. | — | — |
| T1 | Validation juridique planchers CCN 🔧 | Consultation avocat | externe |
| Sub-PR 2bis (RÉSOLU 2026-04-28) | Multi-étabs taux commission | Cascade etab>groupe>15 + RPC admin + UI /admin/taux-commission | — |
| T9 (RÉSOLU 2026-04-29) | Gel facture par période | Partie 2 livrée : PERIODE_LITIGIEUSE au CHECK + colonnes periode_* litiges + trigger gel par chevauchement factures hebdo. | — |
| T12 (RÉSOLU 2026-04-28) | Stripe payment_intent propagation | Trigger SQL stripe_transfers→factures_honoraires (option B simplifiée). Backfill exécuté. | — |
| T13 (RÉSOLU 2026-04-28) | process-stripe-refunds finalisée | Constat : fn déjà implémentée v85 (auth, lock atomique, retry, idempotence, alert admin, audit). Reste action manuelle Gabrielle : configurer schedule cron `*/30 * * * *`. | manuel cron |
| T15 (RÉSOLU) | RELANCE_FACTURE → RAPPEL_FACTURE | — | — |

### P2 — qualité / robustesse

| # | Ticket | Action | Charge |
|---|---|---|---|
| #2 | Activer admin-invoke 🔧 | 2 secrets Supabase + UPDATE auth.users | manuel Gabrielle |
| T7 | Cron créneaux jamais fermés | Edge function + pg_cron | ~1h |
| T11 | Audit objets SQL fantômes | Script + migrations retro | ~2h |
| T14 (RÉSOLU) | Regen PDF/XML avoir direct | — | — |
| T18-T20 (RÉSOLU) | 3 fixes litiges | — | — |

### P3 — nettoyage / améliorations

| # | Ticket | Action | Charge |
|---|---|---|---|
| #3 | Supprimer edge fns proxy test 🔧 | Manuel dashboard Supabase | manuel |
| T2 | Auto détection divergence backfill | Script SQL/edge | ~1h |
| T3 | Audit modif description post-gel | Trigger + log table | ~1h |
| T4 | Notif soignant si service modifié post-gel | Trigger + edge send-email | ~1h |
| T5 | Documentation JWT context bulk update | docs/bulk-updates-playbook.md | ~30min |
| T6 | Test plafond 48h heures externes | Test SQL future | bloqué |
| T8 | Batch recalc 265 missions | Script SQL one-shot | ~30min |
| T10 | Rate limit 3/h vs 3/24h | Décision + migration | retours terrain |

### Fixes UX soignant audit (2026-04-26 → 28)

- ✅ `.single()` → `.maybeSingle()` sur 12+ pages soignant (3 derniers
  fixés cette session : DocumentsSoignant, PageParrainage,
  DetailPresencesMission cf. note ci-dessous)
- ✅ Bug "pharmacien fantôme" Dashboard (fixé via import
  getLabelProfession + branches conditionnelles)
- ✅ Redirect `/soignant/parcours-3200h` → `/passer-en-liberal` (en place)
- ✅ Guard `statut_liberal` sur ChargesSociales (en place)
- ✅ Guard `!soignant` sur PrevoyanceSoignant (en place ; pas besoin
  de filtrer par type_exercice : la prévoyance s'applique à tous)
- ✅ Triplon "Complétez profil" Dashboard : refactor BandeauCompletionProfil
  utilisé partout — fait dans une session précédente
- 🔄 R3 Dashboard refondu (OnboardingStepper unifié) : reste à faire,
  ~4-5h
- 🔄 R4 Page Parametres soignant tabulée : reste à faire, ~3-4h

### Note `DetailPresencesMission.tsx:105`

`.single()` sur `soignants` filtré par `mission.soignant_assigne_id`
(non NULL garanti par le contexte d'usage). Crash possible uniquement
si la mission est lue en parallèle d'une suppression du soignant
(scénario rare). Laissé en `.single()` faute de cas d'erreur observé,
à migrer si remontée en logs Sentry.

### Limitations P3 modules paie + facturation

- PDF mandat + bulletin **client-only** (jsPDF). Pour archivage
  cryptographiquement signé Storage, prévoir edge function future qui
  upload sur `bulletins-paie/{soignant_id}/{numero}.pdf` /
  `mandats_facturation_signatures.pdf_url`.
- UI Convention collective dans ProfilEtablissement (P2, admin saisit
  via SQL pour MVP).
- Préavis 30j révocation mandat : engagement contractuel ; technique
  reste immédiat (pas de blocage prévu).
