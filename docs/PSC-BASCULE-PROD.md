# Pro Santé Connect — Bascule production

> **Statut** : code prod-ready. En attente des credentials ANS (`PSC_CLIENT_ID` + `PSC_CLIENT_SECRET`).
> **Mode** : mono-environnement, pas de phase sandbox prévue. `PSC_ENVIRONMENT=production` est déjà fixé.

---

## URLs déclarées à l'ANS (formulaire de demande prod)

Ces 3 URLs ont été soumises à l'ANS dans le dossier de raccordement. Elles doivent rester **strictement identiques** au code et aux secrets Supabase. Toute modification (casse, slash final, sous-domaine) → rejet PSC.

| Champ ANS | Valeur exacte |
|---|---|
| URL du service | `https://jolene.app/connexion` |
| URL de redirection (`redirect_uri`) | `https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/psc-callback` |
| URL de logout (`post_logout_redirect_uri`) | `https://jolene.app/connexion?logout=psc` |

---

## Secrets Supabase

Configurés dans **Project Settings → Edge Functions → Secrets** sur le projet `flripxtsyegjshnhzjkz`.

| Secret | Statut | Valeur |
|---|---|---|
| `PSC_ENVIRONMENT` | ✅ en place | `production` |
| `PSC_REDIRECT_URI` | ✅ en place | `https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/psc-callback` |
| `PSC_FRONTEND_URL` | ✅ en place | `https://jolene.app` |
| `PSC_CLIENT_ID` | ⏳ à remplir | (fourni par l'ANS le jour J) |
| `PSC_CLIENT_SECRET` | ⏳ à remplir | (fourni par l'ANS le jour J) |

---

## Endpoints PSC production (hardcodés dans le code)

Vérifiables à tout moment via `https://auth.esw.esante.gouv.fr/auth/realms/esante-wallet/.well-known/wallet-openid-configuration`.

| Endpoint | URL |
|---|---|
| Issuer | `https://auth.esw.esante.gouv.fr/auth/realms/esante-wallet` |
| Authorization | `https://wallet.esw.esante.gouv.fr/auth` |
| Token | `https://auth.esw.esante.gouv.fr/auth/realms/esante-wallet/protocol/openid-connect/token` |
| UserInfo | `https://auth.esw.esante.gouv.fr/auth/realms/esante-wallet/protocol/openid-connect/userinfo` |
| JWKS | `https://auth.esw.esante.gouv.fr/auth/realms/esante-wallet/protocol/openid-connect/certs` |
| End Session (logout) | `https://auth.esw.esante.gouv.fr/auth/realms/esante-wallet/protocol/openid-connect/logout` |

Le bouton **« Vérifier connexion PSC »** dans `/admin/healthcheck` compare ce hardcode au discovery OIDC à chaque vérification — si l'ANS modifie un endpoint, l'écart s'affiche.

---

## Procédure jour J — réception des credentials ANS

### 1. Préparation (5 min)

- [ ] Confirmer que l'email reçu provient bien de l'ANS et contient `PSC_CLIENT_ID` (UUID ou identifiant texte) + `PSC_CLIENT_SECRET` (chaîne longue).
- [ ] Vérifier que le `redirect_uri` indiqué dans l'email correspond **exactement** à `https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/psc-callback`. En cas d'écart : **ne rien faire**, contacter l'ANS, l'écart bloquera tous les login PSC.

### 2. Ajout des secrets dans Supabase (2 min)

Dashboard Supabase → projet `flripxtsyegjshnhzjkz` → **Edge Functions** → **Manage secrets** → **Add new secret** :

```
PSC_CLIENT_ID = <valeur reçue par email ANS>
PSC_CLIENT_SECRET = <valeur reçue par email ANS>
```

⚠️ **Ne pas modifier** `PSC_ENVIRONMENT`, `PSC_REDIRECT_URI`, `PSC_FRONTEND_URL` — ils sont déjà corrects.

### 3. Vérification automatique (1 min)

- [ ] Ouvrir https://jolene.app/admin/healthcheck (compte admin)
- [ ] Cliquer **« Vérifier connexion PSC »**
- [ ] Résultat attendu :
  ```json
  {
    "env": "production",
    "secrets_ok": true,
    "missing_secrets": [],
    "discovery_ok": true,
    "endpoints_match": true,
    "duration_ms": <500ms-2000ms>
  }
  ```
- [ ] Si `endpoints_match: false` → l'ANS a changé un endpoint, refondre les `PSC_ENDPOINTS` dans `supabase/functions/psc-authorize/index.ts`, `psc-callback/index.ts`, `psc-logout/index.ts`, `psc-test-connexion/index.ts`. Voir les détails dans `endpoints_diff[]`.

### 4. Test login (5 min)

Avec ta carte e-CPS personnelle :

- [ ] Ouvrir https://jolene.app/connexion en navigation privée
- [ ] Cliquer **« S'identifier avec Pro Santé Connect »**
- [ ] Authentification e-CPS
- [ ] Si compte **existant** : redirection vers `/soignant/tableau-de-bord`
- [ ] Si compte **nouveau** : redirection vers `/inscription/soignant/completion` (téléphone, types de contrat, mot de passe optionnel, CGU)

### 5. Test logout (2 min)

- [ ] Connecté via PSC, cliquer le bouton de déconnexion (header)
- [ ] Le navigateur doit transiter par `auth.esw.esante.gouv.fr/.../logout`
- [ ] Retour automatique sur `https://jolene.app/connexion?logout=psc`
- [ ] Toast affiché : « Déconnexion Pro Santé Connect réussie »
- [ ] L'URL est nettoyée (le param `?logout=psc` disparaît)

### 6. Validation finale (1 min)

- [ ] Re-cliquer **« S'identifier avec Pro Santé Connect »** : la page de login PSC doit redemander la carte (pas de SSO silencieux résiduel)
- [ ] Annoncer la mise en prod sur Slack #ops + email équipe

---

## Rollback en cas de problème

### Symptôme : login PSC échoue (`error=invalid_client`, `redirect_uri_mismatch`)

Cause probable : valeurs `PSC_CLIENT_ID`/`PSC_CLIENT_SECRET` saisies avec un caractère invisible (espace, retour à la ligne) lors du copier-coller.

**Action** :
1. Dashboard Supabase → Edge Functions → Secrets → supprimer `PSC_CLIENT_ID` et `PSC_CLIENT_SECRET`
2. Le bouton PSC affichera alors « Pro Santé Connect sera disponible très prochainement » (fallback `configured: false`) — **les login email/mdp continuent de fonctionner**.
3. Re-saisir les secrets en collant chaque valeur dans un éditeur texte intermédiaire pour vérifier l'absence de caractères invisibles.
4. Re-tester via `/admin/healthcheck`.

### Symptôme : tous les soignants existants ne peuvent plus se connecter

Le code email/mdp ne dépend pas de PSC — donc cette situation ne devrait pas survenir suite à la bascule. Si elle se produit, le coupable est ailleurs (RLS, table soignants, RPC `fn_get_my_role`). Voir runbooks Sentry/Supabase logs.

### Symptôme : un nouveau soignant créé via PSC voit `/inscription/soignant/completion` infini

Cause : le `update soignants` échoue silencieusement (RLS ou colonne manquante).

**Action** :
1. Vérifier les logs edge function `psc-callback` → confirmer que la création s'est bien faite
2. Vérifier la table `soignants` en SQL pour cet user_id
3. Le user peut être supprimé via Supabase Dashboard → Auth → Users si on veut qu'il recommence l'inscription

### Désactivation totale de PSC (incident grave)

Pour désactiver PSC tout en gardant le reste de l'app fonctionnel :
1. Dashboard Supabase → Edge Functions → Secrets → supprimer `PSC_CLIENT_ID`
2. Le bouton PSC bascule en mode `configured: false` immédiatement (pas de redéploiement nécessaire)
3. Les soignants déjà connectés via PSC restent connectés (la session Supabase est indépendante)
4. La déconnexion d'un user PSC fait alors un signOut local sans appeler end_session (best-effort)

---

## Architecture du flow

```
Frontend (BoutonProSanteConnect)
   │ click
   ▼
supabase.functions.invoke('psc-authorize')
   │ génère PKCE + state + nonce
   │ stocke dans psc_auth_sessions
   │ retourne authorization_url
   ▼
Navigateur → wallet.esw.esante.gouv.fr/auth?...
   │ user présente sa carte e-CPS
   ▼
PSC redirige → https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/psc-callback?code=...&state=...
   │ vérifie state + récupère code_verifier
   │ échange code → tokens (token endpoint)
   │ vérifie id_token (JWKS, issuer, audience, nonce)
   │ fetch userinfo
   │ lookup soignant par psc_sub → RPPS → email
   │ si absent : créer auth.user + soignant (isNewUser=1)
   │ sinon : update psc_sub, psc_last_login
   │ generateLink(magiclink) → token_hash
   ▼
Navigateur → https://jolene.app/auth/psc/callback?status=success&token_hash=...&new_user=...
   │ supabase.auth.verifyOtp(token_hash, magiclink)
   │ session Supabase créée
   ▼
- new_user=1 → /inscription/soignant/completion
- new_user=0 → /soignant/tableau-de-bord
```

Logout symétrique :

```
deconnexion() (AuthContext)
   │ détecte psc_sub présent → invoke('psc-logout')
   ▼
Navigateur → auth.esw.esante.gouv.fr/.../logout?client_id=...&post_logout_redirect_uri=...
   │ PSC invalide la session
   ▼
Navigateur → https://jolene.app/connexion?logout=psc
   │ signOut() Supabase local
   │ toast confirmation
   │ URL nettoyée
```

---

## Fichiers concernés

| Fichier | Rôle |
|---|---|
| `supabase/functions/psc-authorize/index.ts` | Génère l'URL OIDC authorize + PKCE |
| `supabase/functions/psc-callback/index.ts` | Échange code, lookup/création soignant, magiclink |
| `supabase/functions/psc-logout/index.ts` | Construit l'URL end_session PSC |
| `supabase/functions/psc-test-connexion/index.ts` | Diagnostic admin (secrets + discovery + endpoints match) |
| `src/components/BoutonProSanteConnect.tsx` | Bouton charte ANS (libellé, logo, couleurs) |
| `src/pages/PageConnexion.tsx` | Affiche le bouton + gère retour `?logout=psc` |
| `src/pages/InscriptionSoignant.tsx` | Affiche le bouton (étape 1, signup) |
| `src/pages/PscCallback.tsx` | Reçoit le `token_hash`, finalise la session, redirige |
| `src/pages/InscriptionSoignantCompletion.tsx` | Page de complétion après création PSC |
| `src/pages/admin/AdminHealthcheck.tsx` | Bouton « Vérifier connexion PSC » |
| `src/contexts/AuthContext.tsx` | Détecte user PSC à la déconnexion → route via psc-logout |
| `src/App.tsx` | Route `/inscription/soignant/completion`, `/admin/healthcheck` |

---

## Référentiels ANS

- Documentation technique PSC : <https://industriels.esante.gouv.fr/produits-et-services/pro-sante-connect/documentation-technique>
- Kit identité visuelle : <https://esante.gouv.fr/produits-services/pro-sante-connect>
- Spec OIDC RP-Initiated Logout 1.0 : <https://openid.net/specs/openid-connect-rpinitiated-1_0.html>
