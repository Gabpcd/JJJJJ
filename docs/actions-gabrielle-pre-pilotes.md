# Actions manuelles Gabrielle — pré-pilotes / pré-production

Date : 28 avril 2026 (audit J1.5)

Cette liste compile les actions externes (dashboards Supabase/Vercel/Stripe/CNIL/etc.)
que Gabrielle doit faire avant l'ouverture aux premiers utilisateurs réels.
Pas de code à écrire, uniquement des configurations dans des dashboards externes
ou des opérations administratives.

## P0 — Bloquants pré-pilotes (à faire AVANT 1er pilote)

### 1. Vercel — variables d'environnement

Dashboard Vercel → Project → Settings → Environment Variables → Production :

| Variable | Source | Pourquoi |
|---|---|---|
| `VITE_TURNSTILE_SITE_KEY` | dash.cloudflare.com → Turnstile | Active le captcha anti-bot (sinon widget no-op) |
| `SENTRY_AUTH_TOKEN` | Sentry → Account → API → Auth tokens (scope project) | Upload source maps prod (sinon stacks illisibles) |
| `SENTRY_ORG` | `jolene` (par défaut) | Source maps |
| `SENTRY_PROJECT` | `jolene-frontend` (par défaut) | Source maps |
| `VITE_SENTRY_DSN` | Sentry → Project Settings → Client Keys | Init runtime côté frontend |

Après ajout, `Redeploy` le dernier commit pour propagation (sinon les
variables ne s'appliquent pas).

### 2. Supabase — secrets edge functions

Dashboard Supabase → Project Settings → Edge Functions → Secrets :

| Secret | Valeur | Pourquoi |
|---|---|---|
| `TURNSTILE_SECRET_KEY` | dash.cloudflare.com | Vérifie le token Turnstile côté serveur |
| `ADMIN_INVOKE_SALT` | phrase aléatoire 30+ chars | Active edge function `admin-invoke` |
| `OPS_TEST_ADMIN_PASSWORD` | mot de passe fort 20+ chars | Compte ops-test@jolene.app |
| `ENVIRONMENT` | `production` | Bloque le préfixe RPPS test `00100` |
| `DEFACTO_WEBHOOK_SECRET` | Defacto dashboard | Vérification HMAC webhook factor |

Après ajout `OPS_TEST_ADMIN_PASSWORD` :
```sql
-- À exécuter une fois dans le SQL editor du dashboard Supabase
UPDATE auth.users
SET encrypted_password = crypt('<nouveau_mdp>', gen_salt('bf'))
WHERE email = 'ops-test@jolene.app';
```

### 3. Supabase — Backups Pro tier

Dashboard Supabase → Project Settings → Add-ons :

- [ ] Confirmer que la formule est **Pro** (≥ 25 $/mois) ou **Team**.
- [ ] Activer **Point-In-Time Recovery (PITR)** (7 jours Pro, 30 jours Team).
- [ ] Tester un PITR sur un projet **clone/staging** (Settings → Backups
      → Restore to new project) pour valider la procédure.
- [ ] Documenter le test dans `docs/procedure-backup.md` (date + résultat).

### 4. Supabase — Cron pg_cron

Dashboard Supabase → Database → Cron jobs. Ajouter :

```sql
-- Hebdomadaire dimanche 03:00 UTC : purge admin_invocations
SELECT cron.schedule('purge_admin_invocations', '0 3 * * 0',
  $$SELECT public.fn_admin_invocations_purge();$$);

-- Hebdomadaire dimanche 04:00 UTC : anonymisation GPS > 90 jours
SELECT cron.schedule('anonymiser_gps', '0 4 * * 0',
  $$SELECT public.fn_anonymiser_gps_anciennes();$$);

-- Mensuel 1er du mois 05:00 UTC : purge comptes inactifs > 2 ans
SELECT cron.schedule('purge_inactifs', '0 5 1 * *',
  $$SELECT public.fn_rgpd_purge_automatique_inactifs();$$);

-- Toutes les 30 minutes : process Stripe refunds queue (T13)
SELECT cron.schedule('process_stripe_refunds', '*/30 * * * *',
  $$SELECT public.fn_process_stripe_refunds_queue();$$);

-- Quotidien 02:00 UTC : sync Chorus statuts
SELECT cron.schedule('sync_chorus_status', '0 2 * * *',
  $$SELECT net.http_post(url := '<edge_function_url>/sync-chorus-status') $$);

-- Hebdomadaire : check cohérence financière (T diagnostic)
SELECT cron.schedule('diagnostic_coherence', '0 6 * * 1',
  $$SELECT public.fn_diagnostic_coherence_financiere();$$);
```

Vérifier l'existence des jobs : `SELECT * FROM cron.job;`

### 5. Supabase — Suppression edge functions de test

Dashboard Supabase → Edge Functions → Delete pour chaque :

- [ ] `test-invoke-generate-invoice` (P1bis v4 test, neutralisée)
- [ ] `invoke-generate-invoice-internal` (P1bis v5 test, neutralisée)

### 6. Sentry — alertes

Dashboard Sentry → Alerts → Create Alert :

- [ ] Alerte sur **erreur critique en prod** : `level:error` + `environment:production`,
      seuil 1 erreur unique en 5 min, notification email Gabrielle + Slack si configuré.
- [ ] Alerte **pic d'erreurs** : >50 events/min en 5 min consécutives.
- [ ] Alerte **erreurs RPC critiques** : tags `rpc:fn_creer_mission|generate-invoice|fn_signer_mandat_facturation`,
      seuil 5 erreurs / 10 min.
- [ ] Alerte **tentatives login échouées** : `transaction:auth.signin` + status >= 400,
      seuil 50 / 5 min (potentiel brute-force).

### 7. Cloudflare Turnstile — clés prod

Dashboard Cloudflare → Turnstile → Create Site :
- [ ] Site key (à mettre dans Vercel `VITE_TURNSTILE_SITE_KEY`)
- [ ] Secret key (à mettre dans Supabase `TURNSTILE_SECRET_KEY`)
- [ ] Hostname : `jolene.app`, `www.jolene.app`, `app.jolene.app` + dev preview Vercel
- [ ] Mode : Managed (recommandé pour anti-bot grand public)

## P1 — Avant ouverture grand public (post-pilotes)

### 8. CNIL — déclaration / DPO

- [ ] Vérifier avec avocat si **DPIA** (Data Protection Impact Assessment)
      requis (probable car données santé + suivi GPS + traitement automatisé).
- [ ] Désigner formellement un DPO (Gabrielle ou externe) auprès de la CNIL :
      cnil.fr → désignation DPO en ligne. Gratuit.
- [ ] Vérifier l'opportunité de notifier un traitement (registres internes
      suffisent en général, pas de déclaration préalable depuis 2018).

### 9. DPA — signature pilotes

- [ ] Faire relire `docs/dpa-template.md` par avocat.
- [ ] Signer DPA avec chaque établissement pilote AVANT premier flux de données.
- [ ] Conserver les DPA signés dans Drive partagé (Gabrielle).

### 10. Audit prestataires (DPF / SCC)

- [ ] Confirmer **DPF certification** active des sous-traitants USA :
      dataprivacyframework.gov/list (Stripe, Sentry, Anthropic, Resend, Twilio).
- [ ] Télécharger les DPA des sous-traitants principaux (Supabase, Vercel,
      Stripe, Cloudflare) et archiver.

### 11. Stripe Connect — compte plateforme

Dashboard Stripe :
- [ ] Activer **Stripe Connect** plateforme (Express accounts).
- [ ] Configurer les webhooks signés (DPA Stripe).
- [ ] Activer **Stripe Identity** pour KYC soignants LIBERAL (optionnel mais
      recommandé pour réduire fraude).

### 12. Resend / Twilio — comptes vérifiés

- [ ] **Resend** : vérifier domaine `jolene.app` (DKIM + SPF + DMARC) pour
      éviter spam folder. Confirmer SCC dans contrat.
- [ ] **Twilio** : vérifier domaine + numéro émetteur. Confirmer SCC.

### 13. Audit code externe

- [ ] Faire un **pen test léger** (OWASP ZAP ou équivalent) sur les endpoints
      publics (inscription, login, reset password, verify-rpps, verify-siret).
- [ ] Audit indépendant des migrations Supabase recommandé avant lancement
      public (~2 jours développeur expérimenté Postgres+RLS).

## P2 — Optimisations / nice to have

### 14. Monitoring business (optionnel)

- [ ] Dashboard métriques business :
      - Nb soignants inscrits / mois
      - Nb missions publiées / candidatures
      - Volume facturation / mois
      - NPS soignants/étabs
- [ ] Outil suggéré : Posthog (libre + tier Free généreux) ou Metabase
      auto-hébergé sur Supabase.

### 15. Backup secondaire Storage

- [ ] Configurer cron `rclone` mensuel vers un bucket S3 de secours pour le
      bucket `jolene-documents` (factures, mandats, documents soignants).
      Pas critique car factures regenerable depuis DB, mais recommandé pour
      les documents soignants (pièces d'identité, diplômes).

### 16. SOC 2 / ISO 27001 (long terme)

- [ ] Pour les pilotes hôpitaux/établissements gouvernementaux, prévoir
      audit SOC 2 Type 1 ou ISO 27001 (~6 mois, ~30k€).

## Vérifications de routine (mensuel)

| Vérification | Comment |
|---|---|
| Supabase backups OK | Dashboard → Backups → liste des 7 derniers backups quotidiens |
| Cron jobs actifs | `SELECT * FROM cron.job;` dans SQL editor |
| Sentry alertes opérationnelles | Tester en provoquant erreur de test (compte audit) |
| Stripe webhooks delivered | Dashboard Stripe → Developers → Webhooks |
| Audit logs cohérents | `SELECT count(*) FROM journaux_audit WHERE cree_le > now() - interval '30 days';` |
| Comptes audit-* fonctionnels | Login + 1 action par profession |

## Contacts urgence

- **DPO Jolene** : Gabrielle Picard, dpo@jolene.app
- **Supabase Support** : dashboard chat (Pro = SLA 24h)
- **Vercel Support** : dashboard chat (Pro = SLA 24h)
- **Stripe Support** : 24/7 dashboard
- **CNIL** : cnil.fr (notification violation art. 33)
- **Avocat santé/RGPD** : (à compléter par Gabrielle)
