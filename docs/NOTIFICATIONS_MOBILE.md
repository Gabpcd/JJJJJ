# Notifications web et mobiles — architecture

La procédure de configuration stores est détaillée dans
`docs/PUSH_NATIVE_FINAL.md`.

## Canaux

| Canal | Enregistrement | Envoi |
|---|---|---|
| Web | abonnement Push API + clés VAPID | Web Push RFC 8030 |
| iOS natif | token APNs via `@capacitor/push-notifications` | APNs HTTP/2 direct |
| Android natif | token FCM via `@capacitor/push-notifications` | FCM HTTP v1 |

Les plateformes sont stockées en majuscules (`WEB`, `IOS`, `ANDROID`) dans
`tokens_push`. L'upsert est effectué par `fn_upsert_token_push`.

## Cycle de vie natif

`AuthContext` appelle `initNativePush` pour toute session active : formulaire,
restauration au lancement, Pro Santé Connect ou biométrie. Le module :

1. vérifie/demande la permission ;
2. pose les listeners avant `register()` ;
3. enregistre le token du transport natif ;
4. affiche l'événement foreground ;
5. valide et route un tap vers une route existante du rôle courant.

Au logout, `fn_supprimer_mes_tokens_push` est appelé avant `signOut`, puis les
listeners natifs sont retirés. Cela évite la réception croisée sur un appareil
partagé.

## Envoi serveur

`supabase/functions/send-push/index.ts` vérifie l'appelant, les préférences du
destinataire et les limites de débit, puis choisit le transport d'après
`plateforme`. Les tokens expirés ou désinscrits sont désactivés/supprimés.

Secrets :

- Web : `VAPID_PUBLIC_KEY`, `VAPID_PRIVATE_KEY`, `VAPID_SUBJECT` ;
- iOS : `APNS_KEY_P8`, `APNS_KEY_ID`, `APNS_TEAM_ID`, avec
  `APNS_BUNDLE_ID=app.jolene` ;
- Android : `FIREBASE_SERVICE_ACCOUNT_JSON` et, pour l'app,
  `android/app/google-services.json`.

## Routage et présentation

Les liens externes sont refusés ; seuls les chemins internes et les URL HTTPS
Jolene sont acceptés. Les types candidature, mission, contrat, facture, DPAE,
litige et urgence sont routés vers les écrans soignant, établissement ou admin
appropriés.

iOS présente alerte, badge et son au premier plan. Android possède six canaux :
urgence, information, paiement, messagerie, signature et pointage. Le serveur
envoie `sound: default` et le channel id attendu.

## Recette

- permission acceptée/refusée ;
- token présent et plateforme correcte ;
- notification premier plan, arrière-plan et app tuée ;
- tap vers la bonne route et le bon rôle ;
- logout/changement de compte sans fuite ;
- invalidation d'un token expiré ;
- validation TestFlight et Play Internal sur appareils réels.
