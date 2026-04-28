# Dette technique — Jolene

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

## Hardening anti-seed-incohérent — empêcher les INSERT qui bypassent les triggers financiers

**Contexte** : 223/268 missions en base ont un `total_brut` incohérent (n'inclut pas les majorations). Toutes sont issues de seed batches Lovable. Les 17 missions créées via le flow normal (RPC + triggers) sont 100% cohérentes. Le problème : les INSERT seed bypassent `fn_calculer_financier_mission`.

**Actions proposées** :

1. **Trigger BEFORE INSERT sur `factures_honoraires`** : vérifie que `montant_ht` est dans un intervalle raisonnable autour de `mission.net_a_payer` (±1% ou ε = 0.01€). Si écart > seuil, bloquer sauf si session variable `jolene.admin_override_facture_montant` est définie avec raison. Audit trail dans `invoice_audit_log`.

2. **Trigger BEFORE INSERT sur `missions`** : vérifie que `total_brut` est cohérent avec `taux × duree + majorations` après passage par `fn_calculer_financier_mission`. En pratique : le trigger `trg_calculer_financier` fire déjà sur INSERT et recalcule. Mais un INSERT via `DISABLE TRIGGER USER` ou `COPY` pourrait bypasser. Protection supplémentaire : CHECK constraint ou trigger dédié qui détecte l'incohérence.

3. **Edge function de diagnostic périodique** (ou cron SQL) : vérifie mensuellement la cohérence missions ↔ factures_honoraires ↔ stripe_transfers. Alerte par email si écart détecté.

**Priorité** : P1 — à traiter avant lancement public (CP6 ou post-CP6)

**Date** : 2026-04-16

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

## Sub-PR 2bis — Gestion admin des taux commission

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

---

## T9 — Gel de facture par période (pas mission entière)

**Contexte** : `CP-LITIGES-2` (trigger `trg_litige_gel_degel_facture`) gèle **toutes** les factures non-PAYEE d'une mission quand un litige de catégorie `PRESENCE`, `CONDITIONS` ou `COMPORTEMENT` est ouvert. La granularité par période n'est pas possible tant que les colonnes `periode_debut` / `periode_fin` n'existent pas sur `factures_honoraires` (elles arrivent avec Partie 2 — facturation hebdomadaire libérale).

**Exemple du problème** : mission libérale de 4 semaines, soignant conteste ses heures sur la semaine 1. Aujourd'hui → factures S1, S2, S3, S4 toutes gelées. Attendu → seule S1 gelée, S2-S4 continuent.

**Action** : une fois Partie 2 livrée avec `periode_debut` / `periode_fin` :
1. Étendre `trg_litige_gel_degel_facture` pour accepter une période (lue depuis le contexte du litige — à définir : champ `periode_debut`/`periode_fin` sur `litiges`, ou déduction via `presence.pointage_arrivee_le` / `pointage_depart_le`).
2. Ne geler que les factures dont `[periode_debut, periode_fin]` chevauche la période litigieuse.
3. Exception conservée : `SECURITE_DANGER` ou `COMPORTEMENT` avec gravité confirmée par admin → gèle toute la mission (cf. audit Sub-PR 2 quater, précision 14).

**Priorité** : P1 — à traiter dès livraison Partie 2

**Date** : 2026-04-17

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

## T12 — Câblage stripe_payment_intent_id sur factures_honoraires (Stripe Connect)

**Contexte** : La colonne `factures_honoraires.stripe_payment_intent_id` a été ajoutée par CP-LITIGES-3 comme placeholder pour le refund auto (<120j) des avoirs. Actuellement, `stripe-connect-pay-mission` écrit `stripe_payment_intent_id` sur la table `stripe_transfers` (ligne 293-309) mais ne le propage PAS vers `factures_honoraires`. Résultat : `fn_admin_resoudre_litige` cas AVOIR tombera toujours sur `mode_remboursement = VIREMENT_MANUEL` même pour des factures payées via Stripe il y a moins de 120j.

**Action** : trois options à trancher en Sub-PR 3 :
- **A — Trigger propagation** : AFTER INSERT/UPDATE sur `stripe_transfers` → UPDATE `factures_honoraires.stripe_payment_intent_id = NEW.stripe_payment_intent_id WHERE mission_id = NEW.mission_id`. Simple mais couplage direct.
- **B — Edge function stripe-webhook étendu** : au webhook `checkout.session.completed` ou `payment_intent.succeeded`, faire le UPDATE factures_honoraires.
- **C — Refacto `generate-invoice`** : au moment de l'émission, lire la dernière entrée `stripe_transfers` pour cette mission et copier `stripe_payment_intent_id`.

Ma recommandation : **B** (webhook = source de vérité la plus fiable, cohérent avec stripe-webhook existant).

**Priorité** : P1 — avant Sub-PR 3 (sinon les avoirs AUTO_STRIPE ne se déclencheront jamais)

**Date** : 2026-04-17

---

## T13 — Edge function process-stripe-refunds à finaliser

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

## Plan d'attaque résiduel (2026-04-28)

Synthèse exécutive après recensement exhaustif. Items hors scope code
(consultation avocat, action manuelle Gabrielle dashboard) marqués 🔧
manuel. Tickets RÉSOLU précédés de [RÉSOLU] dans le titre.

### P1 — bloquants pré-prod / clients

| # | Ticket | Action | Charge estimée |
|---|---|---|---|
| Hardening anti-seed | Triggers cohérence factures + cron diag | Session dédiée | ~3h |
| T1 | Validation juridique planchers CCN 🔧 | Consultation avocat | externe |
| Sub-PR 2bis | Multi-étabs taux commission | Session dédiée | ~4h |
| T9 | Gel facture par période | Dépend Partie 2 facturation hebdo | bloqué |
| T12 + T13 | Stripe payment_intent + process-stripe-refunds | **Couplé**, 1 session | ~3h |
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
