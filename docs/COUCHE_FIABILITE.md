# Couche fiabilité — monitoring vivant + contrat front ↔ back

Objectif : empêcher qu'une fonctionnalité meure **silencieusement** en prod. Deux
volets complémentaires.

## A. Monitoring vivant (alerting des crons)

`fn_check_crons_health()` (cron horaire `monitoring-health-check-hourly`) émet des
alertes dans `alertes_systeme` via `fn_emettre_alerte_monitoring()`.

**Incident** : `fn_emettre_alerte_monitoring` avait un garde strict
`est_admin() OR service_role` qui lève `42501` en contexte `pg_cron` (où
`auth.uid()` est NULL). Résultat : la fonction de health-check avortait au premier
cron en échec → **0 alerte émise**, alerting silencieusement mort.

**Fix** (`20260628150000`) : garde aligné sur `fn_est_contexte_cron_ou_admin()`.
Le monitoring émet de nouveau (4 alertes réelles au redéploiement).

**Bug surfacé immédiatement** par le monitoring restauré
(`20260628160000`) : `fn_creer_notification` rejetait `auth.uid() IS NULL`, ce qui
cassait **tous les crons** appelant la fonction (`relance-candidatures-en-attente`
échouait chaque jour à 09:00). `anon` n'ayant pas le GRANT EXECUTE, ce garde ne
protégeait contre aucun appelant non fiable → aligné sur le même pattern.

**Anti faux-positifs** (`20260628170000`) : le monitoring émettait des
`CRON_RETARD « jamais »` pour des crons mensuels/annuels n'ayant pas encore atteint
leur première échéance (auto-facturation-mensuelle, recalculer-paliers-commission,
calculer-bfa-annuel) → bruit qui noie les vraies alertes. Désormais un cron jamais
exécuté n'alerte que si son intervalle attendu est ≤ 2 jours (assez fréquent pour
avoir déjà dû tourner). Un échec réel reste capté dès la 1ʳᵉ exécution.

> Note : `auto-facturation-mensuelle` (`0 2 1 * *`, fix auth `20260624140000`) fera
> sa première exécution le 1er du mois et traite **toutes** les missions `TERMINEE`
> non facturées → rattrape automatiquement le backlog, pas de perte.

## B. Contrat front ↔ back (CI anti-raccord mort)

`scripts/check-contrat-frontend-backend.mjs` (job CI `Contrat front ↔ back` dans
`validate-pr.yml`, ou `npm run check:contrat`).

Extrait de `src/` **tout** `.rpc('x')`, `.functions.invoke('x')`,
`.storage.from('x')` puis vérifie que chaque référence existe dans
**l'état prod ∪ les objets définis dans le repo** :

| Référence | Existe si présent dans… |
|---|---|
| RPC | `pg_proc` (prod) **∪** `CREATE FUNCTION` des migrations du repo |
| Edge function | slugs déployés (Management API) **∪** `supabase/functions/<slug>` |
| Bucket storage | `storage.buckets` (prod) **∪** inserts/`create_bucket` des migrations |

L'union évite les faux positifs quand une PR ajoute le backend **et** le frontend
dans le même commit. Le job **échoue (exit 1)** si une référence n'existe nulle
part — exactement la classe de bug qui avait tué `fn_ma_streak`,
`fn_soignant_score_breakdown` et les buckets `factures-honoraires` / `avoirs`
(références frontend sans backend correspondant, invisibles jusqu'au clic
utilisateur).

Introspection prod : Management API (`SUPABASE_ACCESS_TOKEN` + `SUPABASE_PROJECT_REF`).
Si les secrets manquent, le job **avertit et passe** (jamais de faux négatif).
En local : `CONTRAT_INTROSPECTION_FILE=…json` ou exécution repo-seul (informatif).

Allowlist : `fn_xxx` (placeholder de doc JSDoc, pas un vrai appel).
