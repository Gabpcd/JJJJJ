# Notifications push mobile + web — architecture

> Sprint 3 PR 4 — hardening production-grade. Audit a corrigé les
> tokens orphelins au logout + ajouté triggers DB auto-push sur
> événements contrats critiques.

## Vue d'ensemble

Jolene supporte 2 canaux push :

1. **Web Push (VAPID, RFC 8030)** — desktop + Android Chrome + iOS Safari 16.4+
   PWA installée. Utilise le Service Worker `/public/firebase-messaging-sw.js`.
2. **Native push (Capacitor)** — apps iOS (APNS) + Android (FCM) via wrapper Capacitor.

Configuration secrets requise (Supabase Vault) :
- `VAPID_PUBLIC_KEY` + `VAPID_PRIVATE_KEY` + `VAPID_SUBJECT` (Web Push)
- `FCM_SERVER_KEY` (Android, legacy — migration FCM Admin SDK pour Sprint 4+)
- `APNS_P8_KEY` + `APNS_KEY_ID` + `APNS_TEAM_ID` + `APNS_BUNDLE_ID` (iOS, Sprint 4+)

## Table `tokens_push`

```
id              uuid PK
utilisateur_id  uuid FK auth.users
token           text NOT NULL UNIQUE
plateforme      text ('web', 'ios', 'android')
endpoint        text (Web Push endpoint URL)
p256dh          text (Web Push public key)
auth_key        text (Web Push auth secret)
actif           boolean DEFAULT true
cree_le         timestamptz DEFAULT NOW()
derniere_utilisation  timestamptz DEFAULT NOW()
```

RLS : SELECT/INSERT/UPDATE/DELETE owner uniquement. service_role bypass
pour cleanup + envoi (PR 1 Sprint 3 a ajouté GRANT DELETE).

## Flow inscription token

```
1. Web : src/lib/firebase.ts → demande permission → registerServiceWorker →
   PushManager.subscribe(VAPID_PUBLIC_KEY) → endpoint + keys
   → fn_upsert_token_push(token, plateforme='web', endpoint, p256dh, auth_key)

2. Native iOS/Android : src/lib/pushNative.ts → PushNotifications.requestPermissions()
   → PushNotifications.register() → event 'registration' → token brut
   → fn_upsert_token_push(token, plateforme='ios'|'android', null, null, null)

3. UI : src/components/DemandePermissionPush.tsx
   - Sur web : modal 5s après login si Notification.permission == 'default'
   - Sur native : initNativePush appelé dans LayoutApp
```

## Flow logout (FIX PR 4 Sprint 3)

```
1. AuthContext.deconnexion() appelée
2. AVANT supabase.auth.signOut() :
   → supabase.rpc('fn_supprimer_mes_tokens_push')
   → DELETE FROM tokens_push WHERE utilisateur_id = auth.uid()
3. signOut() Supabase
4. viderCacheHorsLigne() + Sentry.setUser(null)
```

Bug pre-PR 4 : les tokens persistaient au logout. Conséquences :
- Fuites privées entre comptes sur appareil partagé
- Accumulation de tokens orphelins
- Push envoyés à l'ancien user même après logout

## Cleanup automatique

`fn_nettoyer_tokens_push()` (existait déjà) :
- DELETE tokens où `derniere_utilisation < NOW() - 90j` OR `actif = false`
- Retourne count

`pg_cron` quotidien (**ajouté par PR 4 Sprint 3**) :
```sql
SELECT cron.schedule('jolene_nettoyer_tokens_push',
  '30 3 * * *',  -- 03:30 UTC tous les jours
  $$SELECT public.fn_nettoyer_tokens_push()$$);
```

## Edge function `send-push`

`supabase/functions/send-push/index.ts` :

1. Reçoit `{ destinataire_id, type_evenement, titre, corps, data? }`
2. Vérifie `fn_doit_notifier(user_id, type)` (préférences user)
3. SELECT tokens_push WHERE utilisateur_id = destinataire_id AND actif
4. Pour chaque token :
   - Web Push (a `endpoint`) → POST RFC 8030 avec VAPID
   - FCM (token brut, plateforme = 'android') → POST FCM legacy
   - APNS (plateforme = 'ios', Sprint 4+) → POST APNS HTTP/2 avec p8 key
5. Si réponse 404/410/InvalidRegistration → DELETE le token

## Triggers DB auto-push (PR 4 Sprint 3)

Ajoutés au workflow critique de signature contrat :

### `trg_dec_push_contrat_a_signer`
- Source : AFTER INSERT contrats_mission
- Filtre : statut IN ('EN_ATTENTE_SIGNATURES', 'EN_ATTENTE_SIGNATURE')
- Action : POST send-push pour `soignant_id` avec type CONTRAT_A_SIGNER
- Complète l'email envoyé par `trg_dec_email_contrat_a_signer` (PR 7 Sprint 1)

### `trg_dec_push_contrat_signe_complet`
- Source : AFTER UPDATE OF statut contrats_mission
- Filtre : statut transition vers SIGNE_COMPLET (pas déjà SIGNE_COMPLET)
- Action : POST send-push aux 2 parties (soignant + etablissement_id) avec
  type CONTRAT_SIGNE
- Complète l'email envoyé par `trg_dec_email_contrat_signe_complet`

## Types d'événements push (enum)

Cf. migration `20260429180000_*_evenements_notification` :

| Type | Trigger source | Destinataire |
|---|---|---|
| `NOUVELLE_MISSION_MATCHANT_FILTRE` | INSERT missions OUVERTE matching alertes | soignant |
| `CANDIDATURE_RECUE` | INSERT candidatures | étab |
| `MISSION_ASSIGNEE` | UPDATE candidatures statut ACCEPTEE | soignant |
| `CONTRAT_A_SIGNER` | INSERT contrats_mission (PR 4 S3 trigger) | soignant |
| `CONTRAT_SIGNE` | UPDATE contrats_mission statut SIGNE_COMPLET (PR 4 S3) | 2 parties |
| `RAPPEL_J1_MISSION` | cron J-1 | soignant |
| `POINTAGE_MANQUANT` | cron J+1 sans pointage | soignant |
| `FACTURE_EMISE` | INSERT factures | étab |
| `PAIEMENT_RECU` | webhook Stripe / Chorus | soignant |
| `LITIGE_OUVERT` | INSERT litiges | partie adverse |
| `LITIGE_RESOLU` | UPDATE litiges statut RESOLU | parties |
| `URGENCE` | INSERT missions urgentes pool | soignants pool |

## Préférences user

Table `preferences_notifications` :
- `utilisateur_id` PK
- `email_<type>` boolean (chaque type)
- `push_<type>` boolean (chaque type)
- `sms_<type>` boolean (whitelist : OTP, urgences seulement)

`fn_doit_notifier(user_id, type, canal)` → bool : check de préférence
appelé par send-email et send-push avant envoi.

## Tests E2E (Sprint 4 roadmap)

`e2e/flows/notifications-push.spec.ts` à créer :
- Inscription → permission demandée
- Login → token enregistré (fn_upsert_token_push appelée)
- Logout → tokens supprimés (DELETE FROM tokens_push)
- Création mission urgente → push reçu < 30s
- Click notification → navigation vers `/mission/:id`
- Token 410 (FCM expiré) → cleanup auto
- Token > 90j inactif → purgé par cron

## Roadmap Sprint 4+

1. **FCM Admin SDK migration** : remplacer FCM legacy par Admin SDK + service account JSON
2. **APNS support natif iOS** : implémenter POST APNS HTTP/2 dans send-push avec p8 key
3. **Background sync** : pointages offline → sync auto au retour réseau
4. **Notification channels Android** : créer channels par type (urgence, info, paiement)
5. **iOS rich notifications** : images + actions + grouping
