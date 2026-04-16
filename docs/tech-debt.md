# Dette technique — Jolene

## Accès direct à factures_honoraires à remplacer par RPC SECURITY DEFINER

**Fichier** : `src/pages/MesFacturesHonoraires.tsx:67-71`

**Contexte** : Le composant fait un `.from('factures_honoraires').select('*').eq('id', factureId)` direct depuis le client Supabase (role `authenticated`). Avant le hotfix GRANTs (20260415110000), cette requête échouait silencieusement (masquée par `maybeSingle()` qui retournait `null` au lieu de remonter le 403).

Le GRANT corrige le symptôme (la requête passe maintenant), mais le pattern n'est pas idéal : le SELECT direct expose la structure de la table au client et contourne la couche d'abstraction RPC.

**Action** : Refactorer `MesFacturesHonoraires.tsx` pour utiliser `fn_mes_factures_honoraires` (qui existe déjà et est SECURITY DEFINER) partout, y compris pour le détail d'une facture individuelle. Ajouter un paramètre `p_facture_id` optionnel à la RPC pour le cas détail.

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
