# Exports prospection — ACTIFS DE PRODUCTION

⚠️ **Ces données ne sont JAMAIS des données de test.** Établissements répertoriés
(~64 051), soignants répertoriés (~245 335, PII), groupes sociaux (`sales_groupes`).
Aucune purge, aucun archivage, aucune exclusion de liste ne les touche
(cf. addendum MODE AUTONOME, protection des données de prospection).

## Générer les CSV (destination : Cowork)

La PII n'est jamais tirée à travers un LLM. Export direct Postgres → CSV :

```bash
SUPABASE_DB_URL='postgres://…' node scripts/export-prospection.mjs
```

Produit ici : `etablissements.csv`, `soignants.csv`, `groupes-sociaux.csv`.

Les `.csv` sont git-ignorés (PII) — seuls ce README et le script sont versionnés.
