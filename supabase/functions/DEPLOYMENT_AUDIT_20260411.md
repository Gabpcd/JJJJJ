# Edge functions drift follow-up

**Context** : Audit profond post-migration Lovable→Vercel (11 avril 2026). 15 edge functions ont été redéployées pour corriger un CORS stale (`app.jolene.app` → `jolene.app`) et un drift de branding (`#17A2B8` → `#E04590`).

## ✅ Redéployées avec succès (15)

| Function | Version | Correction |
|---|---|---|
| verify-rpps | v181 → v182 | CORS |
| verify-siret | v60 → v61 | CORS |
| create-invoice-payment | v183 → v184 | CORS |
| confirm-invoice-payment | v62 → v63 | CORS |
| create-mission-payment | v124 → v125 | CORS |
| setup-sepa | v123 → v124 | CORS |
| send-email | v184 → v185 | CORS + branding rose |
| yousign-create | v121 → v122 | CORS |
| send-sms | v6 → v7 | CORS |
| chorus-pro-deposit | v118 → v119 | CORS |
| email-cron | v106 → v107 | CORS |
| api-v1 | v97 → v98 | CORS |
| psc-callback | v9 → v10 | CORS |
| psc-authorize | v11 → v12 | CORS + **fix erreur de syntaxe** (duplicate `jolene.app` + ternaire orphelin dans le repo) |
| factor-request-advance | v10 → v11 | CORS |
| confirm-dpae | v48 → v49 | CORS |
| calendar-sync | v1 → v2 | CORS |

## ✅ Déjà clean (1)

| Function | Raison |
|---|---|
| factor-webhook | Webhook-only, pas de logique CORS navigateur |

## ⚠️ À décider manuellement (1)

### `verify-document` — dérive comportementale au-delà du CORS

**État** : le fichier local a supprimé le fallback Lovable AI Gateway et n'appelle plus que l'API Anthropic directe. Le code local **THROW** si `ANTHROPIC_API_KEY` n'est pas configurée (ligne 91-92).

**Risque** : si `ANTHROPIC_API_KEY` n'est pas définie côté Supabase, un redéploiement cassera la fonction pour TOUS les utilisateurs (erreur 500 sur chaque vérification de document).

**État actuel déployé** (v131) : CORS stale (`app.jolene.app`) mais logique Lovable+Anthropic fonctionne côté système (cron job toutes les 5 min, 200 OK). Les appels navigateur depuis `jolene.app` sont bloqués par CORS.

**Plan d'action recommandé** :
1. Vérifier que `ANTHROPIC_API_KEY` est bien configurée côté Supabase (Dashboard → Project Settings → Edge Functions → Secrets)
2. Si oui : redéployer depuis le repo local (`supabase/functions/verify-document/index.ts`) — la fonction Anthropic-only est l'état cible post-migration
3. Si non : ajouter la clé, puis redéployer

**Commande pour redéployer** (une fois `ANTHROPIC_API_KEY` confirmée) :
```bash
# Via le dashboard Supabase ou via l'Agent API Claude Code
deploy_edge_function verify-document --from supabase/functions/verify-document/index.ts
```

## Vérifications faites

- Grep exhaustif du repo : **zéro** occurrence de `app.jolene.app` dans `supabase/functions/` (hygiène validée)
- Grep exhaustif du repo : **zéro** occurrence de `#17A2B8` dans `supabase/functions/` après fix send-email
- Tous les fichiers locaux ont été validés avant redéploiement pour s'assurer qu'il n'y avait pas de drift supplémentaire au-delà du CORS

## À ne plus reproduire

La migration de domaine (`app.jolene.app` → `jolene.app`) a été faite côté code source mais **les edge functions n'ont pas été systématiquement redéployées**. Pour éviter ce problème à l'avenir :

1. **Add pre-deploy check** : script CI qui grep `app.jolene.app` dans les edge functions déployées et fail si détecté
2. **Automated redeploy** : hook qui redéploie automatiquement toutes les edge functions modifiées dans le repo lors d'un push sur main
3. **Single source of truth** : le repo local doit être la source de vérité, les éditions directes sur le dashboard Supabase doivent être interdites
