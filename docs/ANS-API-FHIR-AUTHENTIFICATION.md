# Authentification mTLS — API FHIR Annuaire Santé (ANS)

> **Statut** : préparation. Cert + clé générés, code prêt, déploiement en
> attente de validation ANS de la souscription au plan Standard.

## 🎯 Objectif

L'edge function `verify-rpps` interroge actuellement l'API FHIR de l'ANS
(`https://gateway.api.esante.gouv.fr/fhir/v1/Practitioner`) en mode anonyme.
Souscrire au plan Standard donne :
- meilleur taux de disponibilité
- accès aux données complètes des praticiens
- support officiel ANS

En contrepartie, l'ANS exige une authentification **mTLS** : chaque requête
doit présenter un certificat client X.509, en plus d'un Client ID transmis
en header.

---

## 🔑 Génération de la paire clé/certificat

**Date de génération** : 2026-05-06
**Validité** : 730 jours → **expiration le 2028-05-05**
**Algorithme** : RSA 2048 bits, signature SHA-256

### Commande utilisée

```bash
mkdir -p .secrets-ans
openssl req -x509 -newkey rsa:2048 -sha256 -days 730 -nodes \
  -keyout .secrets-ans/jolene-ans-private.key \
  -out .secrets-ans/jolene-ans-cert.pem \
  -subj "/C=FR/ST=Paris/L=Paris/O=Jolene SASU/OU=Jolene App/CN=jolene.app/emailAddress=support@jolene.app"
```

### Subject

```
C  = FR
ST = Paris
L  = Paris
O  = Jolene SASU
OU = Jolene App
CN = jolene.app
emailAddress = support@jolene.app
```

### Empreinte SHA-256 (à confirmer dans le portail ANS)

```
49:91:64:59:96:6E:D6:E3:A5:BB:DA:49:EB:DD:A9:AD:B4:E2:3A:35:82:E0:7F:A2:98:EB:50:B6:9D:6F:E8:EF
```

---

## 📁 Fichiers générés

| Fichier | Rôle | Confidentialité |
|---|---|---|
| `.secrets-ans/jolene-ans-cert.pem` | Certificat public X.509 | ⚠️ À coller dans le formulaire ANS |
| `.secrets-ans/jolene-ans-private.key` | Clé privée RSA 2048 | 🔒 **NE JAMAIS partager** |

Les deux fichiers sont exclus du repo via `.gitignore` (règle `.secrets-ans/`).

### Sauvegarde recommandée

- **Coffre-fort 1Password** ou équivalent : importer les 2 fichiers
- **Backup chiffré** sur disque externe au bureau (chiffrement disque entier)
- ❌ Ne jamais envoyer la clé privée par email, Slack, ou la stocker en clair sur un cloud non-chiffré

**Sans la clé privée, le certificat est inutile** — il n'est pas régénérable
par l'ANS, on devrait recommencer le cycle de souscription.

---

## 🆔 Client ID proposé

```
jolene-app-prod
```

Stable, alphanumérique + tirets, explicite. À déclarer à l'ANS dans le formulaire
de souscription, à conserver en secret Supabase comme `ESANTE_CLIENT_ID`.

---

## 🔐 Secrets Supabase à configurer le jour J

Une fois la souscription validée, dans **Supabase Dashboard → Project
`flripxtsyegjshnhzjkz` → Edge Functions → Manage secrets** :

| Secret | Valeur | Source |
|---|---|---|
| `ESANTE_CLIENT_ID` | `jolene-app-prod` | (choix Jolene) |
| `ESANTE_CLIENT_CERT` | Contenu intégral de `jolene-ans-cert.pem` (toutes les lignes, y compris `-----BEGIN/END-----`) | Cert généré ci-dessus |
| `ESANTE_CLIENT_KEY` | Contenu intégral de `jolene-ans-private.key` (toutes les lignes, y compris `-----BEGIN/END-----`) | Clé générée ci-dessus |

⚠️ Chaque secret doit être collé **avec les retours à la ligne** entre les balises
BEGIN et END. Supabase préserve les `\n`.

---

## ⚙️ Diff à appliquer dans `verify-rpps/index.ts` (jour J)

### Limitation Supabase Edge Functions

**`Deno.createHttpClient` n'est pas exposé dans le runtime Supabase Edge Functions**
(basé sur edge-runtime, pas Deno standalone). Le `fetch` natif n'a pas non
plus d'option pour fournir un certificat client.

**Conséquence** : on ne peut pas faire le mTLS directement depuis l'edge function.

### Solution : proxy mTLS

Déployer un proxy minimal **hors de Supabase** qui fait l'appel mTLS, exposé
à l'edge function via une URL et une clé d'API partagée.

**Options recommandées** (par ordre de simplicité) :

#### Option A — Vercel Function Node.js (recommandée)

Le repo Jolene est déjà déployé sur Vercel pour le frontend. Ajouter une
function serverless Node.js qui fait le mTLS, dans `api/ans-fhir-proxy.ts` :

```typescript
// api/ans-fhir-proxy.ts (Vercel Node.js function)
import https from 'node:https';
import type { VercelRequest, VercelResponse } from '@vercel/node';

export default async function handler(req: VercelRequest, res: VercelResponse) {
  // Auth : header partagé avec Supabase Edge
  const proxySecret = process.env.ANS_PROXY_SECRET || '';
  const incoming = req.headers['x-proxy-secret'];
  if (!proxySecret || incoming !== proxySecret) {
    return res.status(401).json({ error: 'Non autorisé' });
  }

  const { rpps } = req.query;
  if (!rpps || !/^\d{11}$/.test(rpps as string)) {
    return res.status(400).json({ error: 'rpps invalide' });
  }

  // mTLS via https.Agent
  const agent = new https.Agent({
    cert: process.env.ESANTE_CLIENT_CERT!.replace(/\\n/g, '\n'),
    key: process.env.ESANTE_CLIENT_KEY!.replace(/\\n/g, '\n'),
  });

  const upstream = await fetch(
    `https://gateway.api.esante.gouv.fr/fhir/v1/Practitioner?identifier=${rpps}&_format=json`,
    {
      headers: {
        'Accept': 'application/fhir+json',
        'User-Agent': 'Jolene/1.0',
        'X-Gravitee-Api-Key': process.env.ESANTE_CLIENT_ID!,
      },
      // @ts-expect-error : Node fetch accepte agent via undici
      agent,
    } as any,
  );

  const body = await upstream.text();
  res.status(upstream.status).setHeader('Content-Type', 'application/fhir+json').send(body);
}
```

Secrets Vercel à configurer : `ANS_PROXY_SECRET` (UUID aléatoire), `ESANTE_CLIENT_ID`,
`ESANTE_CLIENT_CERT`, `ESANTE_CLIENT_KEY`.

#### Diff côté Supabase Edge Function

Dans `supabase/functions/verify-rpps/index.ts`, remplacer le bloc fetch direct
par un appel au proxy Vercel :

```diff
   const FHIR_BASE = 'https://gateway.api.esante.gouv.fr/fhir/v1';
-  const url = `${FHIR_BASE}/Practitioner?identifier=${rpps}&_format=json`;
-
-  const response = await fetchWithTimeout(url, {
-    headers: {
-      'Accept': 'application/fhir+json',
-      'User-Agent': 'Jolene/1.0',
-    },
-  }, 8000);
+
+  // Plan B : si secrets ANS configurés, on passe par le proxy mTLS Vercel.
+  // Plan A (legacy) : fallback fetch direct anonyme tant que la souscription
+  // ANS n'est pas validée.
+  const proxyUrl = Deno.env.get('ESANTE_PROXY_URL'); // ex: https://jolene.app/api/ans-fhir-proxy
+  const proxySecret = Deno.env.get('ESANTE_PROXY_SECRET');
+
+  let response: Response;
+  if (proxyUrl && proxySecret) {
+    response = await fetchWithTimeout(`${proxyUrl}?rpps=${encodeURIComponent(rpps)}`, {
+      headers: {
+        'Accept': 'application/fhir+json',
+        'User-Agent': 'Jolene/1.0',
+        'x-proxy-secret': proxySecret,
+      },
+    }, 8000);
+  } else {
+    // Fallback : appel direct anonyme (rate-limit ANS, aléatoire)
+    response = await fetchWithTimeout(`${FHIR_BASE}/Practitioner?identifier=${rpps}&_format=json`, {
+      headers: {
+        'Accept': 'application/fhir+json',
+        'User-Agent': 'Jolene/1.0',
+      },
+    }, 8000);
+  }
```

Les secrets Supabase changent légèrement (le cert/clé restent côté Vercel) :

| Secret Supabase | Valeur |
|---|---|
| `ESANTE_PROXY_URL` | `https://jolene.app/api/ans-fhir-proxy` (route Vercel) |
| `ESANTE_PROXY_SECRET` | UUID aléatoire (`uuidgen` ou `openssl rand -hex 32`) |

#### Option B — Cloud Run / Render / Fly.io

Container Node.js dédié si Vercel functions est trop limité (timeout 10s).
Plus complexe à mettre en place, à n'envisager que si l'ANS répond très lentement.

#### Option C — Tester `Deno.createHttpClient` dans Supabase

Avant de déployer le proxy, tester directement dans une edge function :

```typescript
// @ts-expect-error : Deno.createHttpClient n'est pas typé partout
const client = Deno.createHttpClient({
  certChain: Deno.env.get('ESANTE_CLIENT_CERT'),
  privateKey: Deno.env.get('ESANTE_CLIENT_KEY'),
});
const r = await fetch('https://gateway.api.esante.gouv.fr/fhir/v1/...', { client } as any);
```

Si l'edge function ne crash pas au déploiement et que la requête répond,
**c'est la solution la plus simple** (pas de proxy à maintenir). Si crash
ou erreur "Deno.createHttpClient is not a function", basculer Option A.

---

## 🔄 Procédure de renouvellement (à 24 mois)

À partir de **2028-04-01** (1 mois avant expiration) :

1. Régénérer une nouvelle paire avec la même commande openssl ci-dessus
   (changer le nom de fichier, ex. `jolene-ans-cert-v2.pem`)
2. Mettre à jour le certificat dans le portail ANS via le formulaire de
   modification (pas une nouvelle souscription)
3. Une fois validé, mettre à jour `ESANTE_CLIENT_CERT` et `ESANTE_CLIENT_KEY`
   dans Supabase ET dans Vercel
4. Vérifier via `/admin/healthcheck` : déclencher un test de `verify-rpps`
   sur un RPPS connu, doit retourner trouve=true
5. Archiver l'ancienne paire dans 1Password avec date d'expiration (utile
   pour debug d'historique RPPS verifié)

⚠️ **Pas de rollover automatique** côté ANS : si on ne renouvelle pas avant
expiration, les appels FHIR retournent `400 Bad Request` (cert expiré) et
les inscriptions soignants RPPS sont cassées le temps du renouvellement.

**Calendrier de rappel** :
- 2028-03-01 : Sentry alert configurée pour échec mTLS
- 2028-04-01 : Début du process de renouvellement
- 2028-05-05 : Date limite

---

## 🔗 Liens utiles

- [Documentation API FHIR Annuaire Santé](https://ansforge.github.io/annuaire-sante-fhir-documentation/)
- [Portail souscription ANS](https://gateway.api.esante.gouv.fr/)
- [Spec mTLS RFC 8705](https://datatracker.ietf.org/doc/html/rfc8705)
