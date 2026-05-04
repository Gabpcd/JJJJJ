# Migrations Supabase — règles strict

Date : 2026-05-03

## Règle d'or

**Toutes les migrations DOIVENT être créées dans `supabase/migrations/` AVANT
d'être appliquées.** Pas d'application directe en prod via MCP `apply_migration`
ou autre outil hors-CLI sauf cas exceptionnel documenté ci-dessous.

## Workflow standard (à utiliser)

1. Créer le fichier `supabase/migrations/YYYYMMDDHHmmss_description.sql`
2. Tester en local : `supabase db reset` puis `supabase migration up`
3. Commit + push sur `main`
4. Le workflow `.github/workflows/deploy-supabase.yml` applique automatiquement
   en prod via `supabase db push`
5. La version est ajoutée à `supabase_migrations.schema_migrations` (tracking)

## Cas exceptionnels (`apply_migration` MCP)

L'utilisation de l'outil MCP `apply_migration` est tolérée pour :
- **Hotfix urgent** : correction critique impossible à déployer via CI
- **Tâche de seed/cleanup destructive** : nécessite service_role direct
  (ex: hash bcrypt password, manipulation `auth.users`, cron one-shot)

**Obligation post-fix** :
1. Créer le fichier `supabase/migrations/YYYYMMDDHHmmss_description.sql`
   avec le SQL appliqué
2. Insérer la version dans schema_migrations pour synchro :
   ```sql
   INSERT INTO supabase_migrations.schema_migrations (version, name)
   VALUES ('20260503050000', 'description')
   ON CONFLICT (version) DO NOTHING;
   ```
3. Commit + push immédiatement

Sinon le workflow `deploy-supabase.yml` détecte l'orphelin et :
- **Local sans remote** : tente de rejouer la migration → peut fail si DDL
  système (ex: `auth.users`)
- **Remote sans local** : marque comme reverted + push (perte de tracking)

## Heal automatique du workflow

Le workflow `deploy-supabase.yml` (step "Heal schema_migrations drift")
nettoie automatiquement les **orphan remote migrations** (présentes en
prod mais pas dans le repo). Cela évite que `supabase db push` plante avec
"Remote migration versions not found in local migrations directory".

Pour les migrations **locales sans remote** (= jamais appliquées), le push
les applique normalement.

## Conventions

- **Timestamp** : `YYYYMMDDHHmmss` ou `YYYYMMDDxxxxxx` (séries Lovable
  historiques) — toujours croissant, pas de collision
- **Nom** : `snake_case` descriptif court (`fix_X`, `add_Y`, `seed_Z`)
- **Idempotence** : préférer `CREATE OR REPLACE`, `IF NOT EXISTS`,
  `ON CONFLICT DO UPDATE` pour pouvoir rejouer sans casser
- **DO blocks** : pour la logique conditionnelle complexe
- **Pas de DROP destructif** sans backup préalable

## Vérifier le diff prod ↔ local

```bash
# Versions remote (en prod)
supabase migration list --remote

# Versions locales
ls supabase/migrations/*.sql | xargs -n1 basename | awk -F_ '{print $1}'

# Diff
diff <(supabase migration list --remote | awk '{print $1}') \
     <(ls supabase/migrations/*.sql | xargs -n1 basename | awk -F_ '{print $1}')
```

## Action externe en cas de drift persistant

Si le workflow `deploy-supabase.yml` échoue malgré le heal step, contacter
Gabrielle qui peut :
1. Inspecter `schema_migrations` via Supabase Dashboard → SQL Editor
2. `INSERT` ou `DELETE` manuel pour synchroniser
3. Re-trigger le workflow via GitHub UI
