# Incident response — Jolene

Date : 2026-05-03

## 1. Identifier un incident

### Signaux automatiques

- **Page `/admin/status`** : tableau de bord santé temps réel
  - Alertes actives en haut
  - Crons en échec / retard
  - Stripe webhooks taux d'erreur
- **Sentry front-end** (action Gabrielle pour activer projet) : erreurs JS utilisateur
- **Cron monitoring-health-check-hourly** : check toutes les heures, écrit dans `alertes_systeme`
- **Logs Supabase** : `cron.job_run_details`, edge functions logs, postgres logs

### Signaux humains

- Email à `bonjour@jolene.app`
- Réclamation utilisateur via `/aide` ou page contact
- Litige sur Stripe Dashboard
- Email Resend (bounce, blocked)

## 2. Process de réponse

### Étape 1 — Identifier l'impact (5 min)

1. Aller sur `/admin/status` — vérifier alertes actives
2. Compter utilisateurs affectés (RPC `fn_admin_health_check` → stats temps réel)
3. Classer la sévérité :
   - **CRITICAL** : missions assignées impactées, paiements échoués, données corrompues, RGPD
   - **WARNING** : feature dégradée mais workaround existe
   - **INFO** : cosmétique ou peu d'utilisateurs

### Étape 2 — Communiquer (10 min)

| Sévérité | Canal | Délai |
|---|---|---|
| CRITICAL | Email tous users affectés + statut sur `/admin/status` | < 30 min |
| WARNING | Email users affectés OU notif in-app | < 2 h |
| INFO | Aucun (corriger silencieusement) | — |

Template email incident :
```
Sujet : [Jolene] Incident technique — [titre]

Bonjour,

Nous rencontrons actuellement [description].
Impact : [X missions / Y utilisateurs concernés].
Workaround : [si applicable].
ETA fix : [estimation].

Nous vous tiendrons informé. Pour toute question : bonjour@jolene.app

L'équipe Jolene
```

### Étape 3 — Fixer

1. Reproduire localement si possible
2. Code fix → tests → commit + push
3. Pour DB : migration via MCP `apply_migration`
4. Pour edge function : commit + redéploiement (CLI `supabase functions deploy` ou Dashboard)
5. Pour frontend : commit + push → redéploiement Vercel auto

### Étape 4 — Postmortem (24 h max)

Créer fichier `docs/postmortem-YYYY-MM-DD-titre.md` avec :
- Timeline détaillée
- Cause racine
- Impact final (users, financier)
- Action immédiate prise
- Actions long-terme pour éviter récurrence
- Personnes impliquées

## 3. Contacts d'urgence

### Support fournisseurs

| Service | Contact | URL dashboard |
|---|---|---|
| Anthropic API (Claude) | support@anthropic.com | https://console.anthropic.com |
| Supabase | support@supabase.io | https://supabase.com/dashboard/project/flripxtsyegjshnhzjkz |
| Stripe | https://support.stripe.com | https://dashboard.stripe.com |
| Resend (email) | https://resend.com/contact | https://resend.com/emails |
| Twilio (SMS) | https://help.twilio.com | https://console.twilio.com |
| Vercel | https://vercel.com/help | https://vercel.com/dashboard |
| Sentry | https://sentry.io/help | https://sentry.io |

### Côté Jolene

- **Gabrielle** (founder) : décision business + actions externes (Vercel envs, Stripe KYC, etc.)
- **Claude Code** (cette session) : tech support DB / edge functions / migrations

## 4. Procédures rollback

### Edge function

Via Dashboard Supabase :
1. https://supabase.com/dashboard/project/flripxtsyegjshnhzjkz/functions
2. Sélectionner la fonction → onglet "Versions"
3. "Rollback to this version" sur la version précédente

Via CLI :
```bash
supabase functions deploy <function-name> --project-ref flripxtsyegjshnhzjkz \
  --import-map ./supabase/import_map.json
# (déploie le code Git actuel — utiliser git checkout <commit> avant)
```

### DB migration

PostgreSQL ne supporte pas le rollback automatique. Pour annuler une migration :

1. Identifier la migration problématique (`SELECT * FROM supabase_migrations.schema_migrations ORDER BY version DESC LIMIT 5;`)
2. Écrire une migration inverse manuellement (DROP / ALTER pour annuler)
3. Si DROP risqué : préférer un fix forward (correction)
4. Restaurer un backup PITR via Supabase Dashboard si dégât majeur (https://supabase.com/dashboard/project/flripxtsyegjshnhzjkz/database/backups)

### Vercel deploy

1. https://vercel.com/<team>/jolene/deployments
2. Sélectionner un deployment précédent qui marchait
3. "Promote to Production"

### Cron (pg_cron)

Désactiver un cron problématique sans le supprimer :
```sql
SELECT cron.unschedule('<jobname>');
-- ou :
UPDATE cron.job SET active = false WHERE jobname = '<jobname>';
```

## 5. Outils internes

### Health check

```sql
SELECT public.fn_admin_health_check();
```

Retourne JSON complet : crons santé, webhook stripe, alertes actives, stats temps réel, logs 24h.

### Alerte manuelle

```sql
SELECT public.fn_emettre_alerte_monitoring(
  'INCIDENT_MANUEL', 'CRITICAL', 'admin',
  'Description de l''incident',
  '{"context": "..."}'::jsonb
);
```

### Résoudre une alerte

Via UI : `/admin/status` → bouton "Résoudre" sur l'alerte.
Via SQL : `UPDATE alertes_systeme SET resolu_le = NOW() WHERE id = '<id>';`

## 6. Tech-debt monitoring

| Item | Action requise |
|---|---|
| Email envoi alertes critiques | Brancher `fn_emettre_alerte_monitoring` à un envoi email automatique (template `ALERTE_MONITORING_ADMIN` à créer dans send-email + cron qui pull alertes non envoyées) |
| Sentry projet `jolene-frontend` | Action Gabrielle : créer projet sur https://sentry.io org `jolene` + configurer `SENTRY_AUTH_TOKEN`, `SENTRY_ORG`, `SENTRY_PROJECT` en variables Vercel |
| Healthcheck Twilio | Pas de monitoring SMS automatique — à ajouter quand SMS volume > 10/jour |
| Healthcheck Resend | Idem email — Resend Dashboard à check manuellement |
| Logflare integration | Optionnel : centraliser tous les logs Supabase + edge functions |

## 7. Historique incidents

Format : `docs/postmortem-YYYY-MM-DD-titre.md`

Liste des postmortems existants (à mettre à jour à chaque incident) :
- _aucun pour le moment_
