# Chorus Pro production — statut & procédure activation

> Sprint 3 PR 9 — documentation du statut actuel et procédure post-réponse AIFE.

## Statut au 13/05/2026

**Statut** : ⏳ **En attente déblocage AIFE**

- Demande de scopes OAuth envoyée à l'AIFE : **mai 2026** (cf. ticket Gabrielle)
- Identifiants production configurés en Supabase Vault :
  - `PISTE_CLIENT_ID` = `6d195544-174a-425e-809e-2c846ad7f7b4`
  - `PISTE_CLIENT_SECRET` = (vault)
  - `PISTE_API_KEY` = `b6fc770c-a4f3-4935-b861-7c456c763bc1`
  - `PISTE_ENV` = `production`
  - `CHORUS_TECH_USER_LOGIN` = `support@jolene.app`
  - `CHORUS_TECH_USER_PASSWORD` = (vault)
- Code Jolene **100% prêt** :
  - `submit-to-chorus` edge function
  - `sync-chorus-status` edge function
  - `chorus-pro-deposit` (commission Jolene)
  - `chorus-pro-verify` (vérification structure)
  - Page admin `/admin/chorus-pro` avec onglet "Vérifier connexion"
- Symptôme actuel : **HTTP 403** sur tous les endpoints opérationnels
  car seul `openid` est activé côté PISTE.

## Scopes à activer côté AIFE (rappel)

Mail envoyé contient la valeur OAuth complète à activer :

```
openid profile
deposerFluxFacture consulterFactureParFournisseur rechercherFactureParFournisseur
consulterHistoriqueFacture recyclerFacture
rechercherStructure consulterStructureAvecTVAIntraCom
rechercherServicesStructure consulterServiceStructure
consulterCR consulterCRDetaille rechercherDestinataire consulterInformationSiret
recupererRattachementsMonCompteUtilisateur
```

## Procédure d'activation (post-réponse AIFE)

### Étape 1 — Ajouter `PISTE_OAUTH_SCOPE` en Supabase Vault

Dans Supabase Dashboard → Project Settings → Edge Functions → Secrets :

```
PISTE_OAUTH_SCOPE = "openid profile deposerFluxFacture consulterFactureParFournisseur ..."
```

(valeur complète ci-dessus)

Aucun redéploiement Jolene nécessaire — `_shared/piste-client.ts` lit la
variable à chaque appel.

### Étape 2 — Vérifier via Admin

Admin connecté → `/admin/chorus-pro` → onglet "Vérifier connexion" :

1. **Step 1 — Auth basique** : doit retourner 200 OK
2. **Step 2 — OAuth2** : doit retourner les scopes ajoutés dans le JWT
3. **Step 3 — Test API structure** : doit retourner 200 avec une structure
   réelle (SIRET test)
4. **Step 4 — Test API facture** : doit retourner 200 avec liste factures

Si toutes les étapes passent : Chorus Pro est officiellement activé.

### Étape 3 — Relancer une facture en pending

Si une facture publique était en statut `pending` (en attente d'envoi
Chorus), elle peut être relancée :

```sql
-- Identifier les factures à relancer
SELECT id, numero, statut FROM factures
WHERE etablissement_id IN (SELECT id FROM etablissements WHERE est_secteur_public)
  AND statut IN ('PENDING_CHORUS', 'ERROR_CHORUS')
ORDER BY cree_le DESC LIMIT 20;
```

```ts
// Côté admin : relance via UI
await supabase.functions.invoke('submit-to-chorus', { body: { facture_id } });
```

### Étape 4 — Monitorer via healthcheck

`/admin/healthcheck` → carte "Chorus Pro (PISTE)" doit passer au vert
(retourne le scope OAuth + dernier appel réussi).

## Tests sandbox avant production

Si l'AIFE active d'abord en **sandbox PISTE** :

1. Changer temporairement `PISTE_ENV` à `sandbox` (Supabase Vault)
2. Refaire le test "Vérifier connexion" → doit retourner 200 partout
3. Tester `submit-to-chorus` avec une facture test
4. Sync statut : doit recevoir un CR (compte rendu) dans les 24h
5. Si OK → basculer `PISTE_ENV` à `production`
6. Relancer le test "Vérifier connexion" en prod

## Plan de rollback

Si l'activation production échoue (mauvais scope, erreur AIFE, etc.) :

1. Supprimer `PISTE_OAUTH_SCOPE` du Vault
2. Le fallback `_shared/piste-client.ts:88` repasse à `openid` seul
3. Toutes les factures publiques restent en `PENDING_CHORUS` jusqu'à
   correction (pas d'impact privé Stripe)

## Notes opérationnelles

- **Délais AIFE** : la réponse à une demande de scopes peut prendre
  2-4 semaines en production. Sandbox PISTE est plus rapide.
- **Maintenance Chorus Pro** : downtime mensuel typique 2-4h en
  nuit dimanche (cf. status.chorus-pro.gouv.fr). Le code Jolene retry
  via `factor-webhook` au prochain cron.
- **Quota PISTE** : 100 req/min en production. Le `_shared/rate-limit.ts`
  protège côté Jolene.

## Liens

- Brief AIFE : `docs/CHORUS-PRO-BASCULE-PROD.md`
- Code client : `supabase/functions/_shared/piste-client.ts`
- Page admin : `src/pages/admin/AdminChorusPro.tsx`
- Healthcheck : `src/pages/admin/AdminHealthcheck.tsx`
