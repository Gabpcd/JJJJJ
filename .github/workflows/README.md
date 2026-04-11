# GitHub Actions — Jolene CI/CD

3 workflows pour garantir que l'état réel de la prod reflète toujours le
contenu du repo. Mis en place après l'audit post-migration Lovable→Vercel
d'avril 2026 qui a révélé ~30 bugs de drift silencieux.

## 📋 Workflows

### 1. `deploy-supabase.yml` — Déploiement automatique
**Trigger** : push sur `main` qui touche `supabase/**`
**Action** :
- Applique les migrations SQL pending (`supabase db push`)
- Redéploie toutes les edge functions (une par une, depuis `supabase/functions/*/index.ts`)

C'est l'équivalent de ce que Lovable faisait automatiquement. Sans ce workflow, les edge functions et migrations restent figées en prod pendant que le repo évolue — c'est exactement ce qui a causé le drift post-migration.

### 2. `validate-pr.yml` — Validation qualité + drift detection
**Trigger** : PR vers `main` + push sur `main`
**Jobs** :
- **typecheck-and-build** : `tsc --noEmit` + `npm run build`, échoue si TS errors
- **drift-detection** : grep bloquant de `app.jolene.app` dans les edge functions, warning sur `#17A2B8`, erreur si imports Lovable résiduels
- **supabase-advisors** (push main seulement) : query les advisors sécurité Supabase, échoue si ERROR level

### 3. `schema-snapshot.yml` — Surveillance des modifs manuelles
**Trigger** : tous les lundis 6h UTC + manuel
**Action** :
- Dump le schéma `public` de Supabase via `supabase db dump`
- Compare avec le dernier snapshot committé
- Si différent, crée automatiquement une PR avec le nouveau dump

Permet de repérer les modifications manuelles faites directement via le dashboard Supabase (qui ne passent pas par les migrations et sont donc invisibles).

## 🔑 Secrets GitHub à configurer

Dans **Settings → Secrets and variables → Actions → New repository secret** :

| Secret | Valeur | Où le trouver |
|---|---|---|
| `SUPABASE_ACCESS_TOKEN` | Token personnel de Gabrielle | [Dashboard Supabase → Account → Access Tokens](https://supabase.com/dashboard/account/tokens) |
| `SUPABASE_PROJECT_REF` | `flripxtsyegjshnhzjkz` | Project Settings → General → Reference ID |
| `SUPABASE_DB_PASSWORD` | Mot de passe DB | Project Settings → Database → Connection String → « Reset database password » si oublié |

### Créer le token d'accès

1. Aller sur https://supabase.com/dashboard/account/tokens
2. Cliquer « Generate new token »
3. Nom suggéré : `github-actions-jolene`
4. Copier le token (affiché une seule fois)
5. Coller dans le secret GitHub `SUPABASE_ACCESS_TOKEN`

### Configurer les 3 secrets GitHub

Via CLI :
```bash
gh secret set SUPABASE_ACCESS_TOKEN --body "sbp_..."
gh secret set SUPABASE_PROJECT_REF --body "flripxtsyegjshnhzjkz"
gh secret set SUPABASE_DB_PASSWORD --body "..."
```

Ou via l'UI GitHub : Settings → Secrets and variables → Actions → New repository secret.

## 🧪 Tester les workflows

### Tester le déploiement Supabase en local
```bash
# Installer le CLI
npm install -g supabase

# S'authentifier
supabase login

# Linker le projet
supabase link --project-ref flripxtsyegjshnhzjkz

# Voir les migrations pending
supabase db diff

# Déployer une fonction en particulier
supabase functions deploy verify-rpps
```

### Déclencher manuellement un workflow
Dans l'UI GitHub : **Actions → sélectionner le workflow → Run workflow**.

## 🛡️ Ce que ces workflows empêchent

| Régression évitée | Mécanisme |
|---|---|
| Edge function non redéployée après modif du repo | `deploy-supabase.yml` redéploie sur chaque push |
| Migration SQL oubliée | `supabase db push` applique les migrations pending |
| Schéma modifié via dashboard sans migration | `schema-snapshot.yml` crée une PR hebdomadaire si différence |
| `app.jolene.app` hardcodé dans le code (legacy Lovable) | `validate-pr.yml` bloque la PR |
| Imports Lovable résiduels | `validate-pr.yml` bloque la PR |
| Nouvelle vulnérabilité RLS (missing policy, etc.) | `validate-pr.yml` query les advisors Supabase |
| Erreur TypeScript non détectée | `validate-pr.yml` lance `tsc --noEmit` |

## 🚨 Si un workflow échoue

1. **`deploy-supabase` échoue** → vérifier que les 3 secrets sont bien configurés. Checker les logs de l'étape qui a échoué (souvent un problème de password DB ou de token expiré).
2. **`validate-pr` drift-detection échoue** → un pattern Lovable legacy a été réintroduit. Identifier le fichier, fixer et re-push.
3. **`schema-snapshot` crée une PR** → examiner les diffs. Si c'est attendu (migration récente), merger. Si c'est inattendu (modif manuelle via dashboard), investiguer avec l'équipe.
