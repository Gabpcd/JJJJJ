# Audit stack existante Jolene

Date : 2026-04-28
Branche : `audit/stack-existante`
Méthodologie : audit READ-ONLY (lecture code + grep + listing edge
functions). Aucun fix ce jour.

## Stack Jolene — état actuel

### Outils déjà en place et opérationnels

| Outil      | Usage                                                        | Fichiers/Config                                                                                                                                            |
| ---------- | ------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Sentry     | Erreur tracking client + Replay sur erreur + Session 0%      | `@sentry/react@^10.46.0` ; init `src/main.tsx` ; helper `src/lib/sentry.ts` ; ErrorBoundary `src/components/SentryErrorFallback.tsx` ; DSN `VITE_SENTRY_DSN` |
| Resend     | 41 templates email transactionnels                           | `supabase/functions/send-email/index.ts` ; secret `RESEND_API_KEY` ; from `noreply@jolene.app` ; logging table `emails_envoyes`                            |
| Twilio     | 2 types SMS (mission urgente, annulation tardive) + custom   | `supabase/functions/send-sms/index.ts` ; secrets `TWILIO_ACCOUNT_SID/AUTH_TOKEN/PHONE_NUMBER` ; logging table `sms_envoyes`                                |
| Stripe     | Paiements + Connect (soignants libéraux) + SEPA + Webhooks   | 10 edge functions Stripe ; package `@stripe/stripe-js@^8.9.0` + `@stripe/react-stripe-js@^5.6.1` ; secrets `STRIPE_SECRET_KEY` + `STRIPE_WEBHOOK_SECRET`   |
| YouSign    | Signature électronique des contrats (API v3)                 | `supabase/functions/yousign-create/index.ts` ; secrets `YOUSIGN_API_KEY` + `YOUSIGN_BASE_URL`                                                              |
| Chorus-Pro | Dépôt factures secteur public français                       | `chorus-pro-deposit`, `submit-to-chorus`, `sync-chorus-status` ; secrets `CHORUS_PRO_*` + `CHORUS_TECH_USER_*`                                             |
| Piste      | API publique partenaires (test creds)                        | `test-piste-credentials` ; secrets `PISTE_API_KEY/CLIENT_ID/CLIENT_SECRET/ENV`                                                                             |
| Defacto    | Affacturage (avance trésorerie) + webhook                    | `factor-request-advance`, `factor-webhook` ; secrets `DEFACTO_API_KEY/URL/WEBHOOK_SECRET`                                                                  |
| ProSantéConnect (PSC) | OAuth2/OIDC PKCE pour login professionnels santé   | `psc-authorize`, `psc-callback` ; secrets `PSC_CLIENT_ID/CLIENT_SECRET/REDIRECT_URI/ENVIRONMENT`                                                           |
| FHIR ANS   | Vérification RPPS via Annuaire Santé officiel                | `verify-rpps` ; pas de clé (API publique gateway.api.esante.gouv.fr)                                                                                       |
| Web Push (VAPID) | Notifications push natives RFC 8030 (sans Firebase)    | `send-push` ; secrets `VAPID_PRIVATE_KEY` + `VAPID_PUBLIC_KEY` + `VAPID_SUBJECT`                                                                           |
| Vercel     | Hosting + CDN + headers sécurité (HSTS 2 ans, X-Frame-Options, Permissions-Policy) | `vercel.json` ; cache-control immuable assets 1 an                                                                                  |
| Capacitor  | Wrapper mobile iOS/Android (16 packages @capacitor/*)        | `@capacitor/core@^8.2.0` + plugins (camera, push, biometric, etc.)                                                                                         |
| Supabase Auth | Authentification (email/password + signOut + RLS)         | `src/contexts/AuthContext.tsx` ; rôle via RPC `fn_get_my_role` ; audit `fn_audit_connexion`                                                                |

### Outils installés mais non configurés / partiels

| Outil               | État                                                                     | Action requise                                                                                |
| ------------------- | ------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------- |
| Sentry source maps  | Init OK, mais source maps non uploadées au build (vite.config.ts vide)   | Ajouter `@sentry/vite-plugin` pour stack traces lisibles en prod                              |
| Sentry Replay       | sessionSampleRate=0, onErrorSampleRate=100                               | Ajuster si besoin de replay session pour debug UX (pas urgent)                                |
| Calendar sync       | OAuth2 non configuré (dry-run uniquement)                                | Configurer Google/Microsoft OAuth si on veut sync sortante effective                          |
| Firebase            | Présent en dépendance (`firebase@^12.10.0`) mais aucun import dans `src/`| Soit retirer la dépendance, soit l'utiliser (sinon = poids bundle inutile)                    |
| Rate limiting       | Présent sur 5/38 edge functions (verify-rpps, register-*, admin-invoke)  | Étendre aux 32 autres si pertinent (au moins endpoints publics : send-email, generate-invoice)|
| Resend domain       | Uniquement `jolene.app` configuré (pas `soindirect.com`)                 | Vérifier domaine `soindirect.com` dans Resend si on veut envoyer depuis ce domaine            |

### Outils absents et utiles

| Besoin                      | Outil suggéré                          | Priorité | Justification                                                                              |
| --------------------------- | -------------------------------------- | -------- | ------------------------------------------------------------------------------------------ |
| Captcha anti-bot            | Cloudflare Turnstile (gratuit)         | P1       | Aucun captcha sur signup/login. Risque automatisation comptes, abus inscriptions.          |
| WAF / DDoS protection       | Cloudflare proxy (DNS) ou Vercel Pro   | P2       | Vercel a un CDN basique mais pas de WAF. Cloudflare gratuit ajouterait protection couche 7.|
| Analytics produit           | PostHog (open-source, gratuit ≤1M/mo) | P2       | Aucun analytics (mixpanel, posthog, etc.). Visibilité parcours user = 0.                   |
| Session replay debug        | PostHog Replay ou Sentry Replay (déjà installé !) | P3 | Sentry Replay est déjà là à 100% on-error : suffisant pour debug bug critiques.            |
| Observabilité backend       | Logflare (Supabase natif) ou Datadog   | P3       | Logs Supabase visibles via dashboard mais pas centralisés long terme.                      |
| Status page publique        | BetterStack/Instatus                   | P3       | Pas obligatoire mais rassurant pour les établissements clients.                            |
| 2FA / TOTP                  | Supabase Auth MFA                      | P2       | Aucune 2FA visible. Comptes admin et étabs sensibles sans second facteur.                  |
| Bug bounty / pentests       | Externe                                | P3       | Pas urgent tant que pas en hyper-croissance.                                               |

### Edge functions — couverture rate-limit

**5 fonctions protégées (rate-limit IP) :**
- `verify-rpps` : 10 req/min
- `register-soignant` : 5 req/10 min
- `register-etablissement` : 5 req/10 min
- `admin-invoke` : 20/admin/h + 100 global/h + advisory lock
- `_shared/stripe-errors.ts` : référence STRIPE_RATE_LIMIT (gestion d'erreur, pas implémentation)

**33 fonctions sans rate-limit** (liste partielle des plus exposées) :
- `send-email`, `send-sms`, `send-push`
- `verify-document`, `verify-siret`
- `create-mission-payment`, `create-invoice-payment`, `confirm-invoice-payment`
- `stripe-webhook` (signature vérifiée donc OK)
- `factor-webhook` (idem)
- `chorus-pro-deposit`, `submit-to-chorus`, `sync-chorus-status`
- `generate-invoice`, `email-cron`, `litige-escalation-cron`
- `psc-authorize`, `psc-callback`
- `setup-sepa`, `sepa-auto-charge`
- `stripe-connect-onboard`, `stripe-connect-pay-mission`, `stripe-connect-status`
- `set-user-claims`, `confirm-dpae`, `process-stripe-refunds`
- `health-check`, `api-v1`, `calendar-feed`, `calendar-sync`
- `yousign-create`, `test-piste-credentials`

### Secrets edge functions configurés (référencés dans le code)

Catégorie | Secrets
---|---
Supabase | `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_ENV`
Environnement | `ENVIRONMENT`, `APP_URL`
Stripe | `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`
Resend | `RESEND_API_KEY`
Twilio | `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, `TWILIO_PHONE_NUMBER`, `SMS_PREFIX_DEFAULT`, `SMS_PREFIX_OVERRIDES`
YouSign | `YOUSIGN_API_KEY`, `YOUSIGN_BASE_URL`
Chorus-Pro | `CHORUS_PRO_CLIENT_ID`, `CHORUS_PRO_CLIENT_SECRET`, `CHORUS_PRO_SANDBOX`, `CHORUS_TECH_USER_LOGIN`, `CHORUS_TECH_USER_PASSWORD`
Piste | `PISTE_API_KEY`, `PISTE_CLIENT_ID`, `PISTE_CLIENT_SECRET`, `PISTE_ENV`
Defacto (factoring) | `DEFACTO_API_KEY`, `DEFACTO_API_URL`, `DEFACTO_WEBHOOK_SECRET`, `FACTOR_PROVIDER`, `FACTOR_MARGE_JOLENE`
ProSantéConnect | `PSC_CLIENT_ID`, `PSC_CLIENT_SECRET`, `PSC_ENVIRONMENT`, `PSC_FRONTEND_URL`, `PSC_REDIRECT_URI`
Web Push | `VAPID_PRIVATE_KEY`, `VAPID_PUBLIC_KEY`, `VAPID_SUBJECT`
Anthropic | `ANTHROPIC_API_KEY` (usage isolé, à investiguer)
Firebase | `FCM_SERVER_KEY` (legacy, projet utilise VAPID)
Identité Jolene | `JOLENE_ADDRESS`, `JOLENE_CITY`, `JOLENE_EMAIL`, `JOLENE_POSTAL_CODE`, `JOLENE_SIRET`
Admin sécurité | `ADMIN_INVOKE_SALT`

### Recommandations

**À activer/configurer dès maintenant :**
1. **Captcha Cloudflare Turnstile** sur les formulaires d'inscription
   (`InscriptionSoignant`, `InscriptionEtablissement`) et sur le login.
   Risque actuel : automatisation, comptes spam, brute-force.
2. **Sentry source maps** via `@sentry/vite-plugin` pour rendre les
   stack traces de production lisibles (sinon Sentry sert à 50%).
3. **Étendre rate-limit IP** aux endpoints publics non protégés :
   `send-email` (envoi emails sortants), `verify-document`,
   `verify-siret`, `generate-invoice`, `health-check` (DDoS-bait).

**À planifier :**
4. **2FA TOTP** via Supabase Auth MFA pour les comptes admin et les
   établissements (factures = cible attractive).
5. **PostHog** (gratuit ≤1M events/mois) pour mesurer le parcours
   utilisateur et identifier les frictions UX. Aucun analytics
   actuellement = aucune donnée pour optimiser le funnel.
6. **Domaine `soindirect.com` Resend** : à vérifier dans le dashboard
   Resend si on prévoit d'envoyer depuis ce domaine.

**À nettoyer :**
7. **Firebase** : `firebase@^12.10.0` est dans `package.json` mais
   aucun import dans `src/`. Soit l'utiliser (push iOS via FCM), soit
   le retirer pour alléger le bundle.
8. **`FCM_SERVER_KEY`** secret legacy : Web Push utilise VAPID
   directement, FCM_SERVER_KEY n'est plus nécessaire si la migration
   VAPID est complète. À vérifier puis retirer.
9. **`calendar-sync`** : OAuth2 non configuré (dry-run uniquement).
   Soit configurer Google/Microsoft OAuth, soit retirer la fonction
   tant qu'elle n'est pas utilisée.

**À documenter :**
10. **`ANTHROPIC_API_KEY`** : présent dans les secrets mais usage
    inconnu. Vérifier dans quelle edge function et pourquoi (probablement
    Claude pour analyse documents ou support).
