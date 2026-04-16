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

**Priorité** : CP4 — Sub-PR 1

**Date** : 2026-04-16
