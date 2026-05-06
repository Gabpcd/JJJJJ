# Chorus Pro / PISTE — Bascule production

Date : 2026-05-06

## État actuel

L'intégration Chorus Pro est **fonctionnellement complète** côté code et déployée
en production. L'OAuth2 PISTE fonctionne (token obtenu en ~250ms). Mais les
appels API métier retournent HTTP 403 car l'application PISTE n'a pas encore
les **scopes opérationnels** activés par l'AIFE.

**Ticket AIFE ouvert** — en attente de déblocage des scopes.

## Identifiants production

| Secret | Valeur |
|---|---|
| `PISTE_CLIENT_ID` | `6d195544-174a-425e-809e-2c846ad7f7b4` |
| `PISTE_CLIENT_SECRET` | (existant) |
| `PISTE_API_KEY` | `b6fc770c-a4f3-4935-b861-7c456c763bc1` |
| `PISTE_ENV` | `production` |
| `PISTE_OAUTH_SCOPE` | (à ajouter post-déblocage AIFE — voir ci-dessous) |
| `CHORUS_TECH_USER_LOGIN` | `support@jolene.app` |
| `CHORUS_TECH_USER_PASSWORD` | (existant) |

## Fiche raccordement Chorus Pro

- Statut : **ACTIF / SUCCÈS**
- Nom application : `Jolene` (case sensitive — match PISTE)
- Type d'utilisation : **Utilisateur d'application interne**
- Structure : JOLENE / SIRET 10330574400015

## Étapes post-déblocage AIFE

### 1. Si AIFE fournit des scopes spécifiques

Quand l'AIFE confirme que les scopes opérationnels sont activés sur l'application
PISTE Jolene, ajouter le secret Supabase Edge Functions :

```
PISTE_OAUTH_SCOPE = openid profile <liste scopes fournis par AIFE>
```

Exemples de scopes par API (extraits de la doc PISTE) :

- **Factures** : `deposerFluxFacture`, `consulterFactureParFournisseur`,
  `rechercherFactureParFournisseur`, `consulterHistoriqueFacture`, `recyclerFacture`
- **Transverses** : `consulterCR`, `consulterCRDetaille`, `rechercherDestinataire`,
  `consulterInformationSiret`
- **Structures** : `rechercherStructure`, `consulterStructureAvecTVAIntraCom`,
  `rechercherServicesStructure`, `consulterServiceStructure`
- **Utilisateurs** : `recupererRattachementsMonCompteUtilisateur`

Le code (`piste-client.ts:getAccessToken()`) lit ce secret automatiquement.
Aucune modification de code nécessaire.

### 2. Vérifier la connectivité

Admin → `/admin/chorus-pro` → bouton **"Vérifier connexion"** :
- Step 1 (Secrets) : ✅ OK
- Step 2 (OAuth2) : ✅ OK + **scope retourné doit inclure les scopes demandés**
  (pas juste `openid resource.READ`)
- Step 3 (rechercherStructure) : doit retourner JSON 200 (pas 403 body écho)
- Step 4 (Tech user) : ✅ OK

Si Step 2 retourne toujours `openid resource.READ` malgré `PISTE_OAUTH_SCOPE`,
l'AIFE n'a pas encore activé les scopes côté PISTE.

### 3. Tester un dépôt de facture réel

1. Admin → `/admin/chorus-pro` → onglet **Submissions**
2. Filtrer sur factures secteur public en statut `pending` ou `error`
3. Cliquer **Resubmit** sur une facture test
4. Vérifier que la soumission passe en status `submitted` (pas `error`)
5. Attendre 2h pour le prochain cycle `sync-chorus-status` → vérifier le statut

### 4. Vérifier la vérification de structure

1. Admin → `/admin/chorus-pro` → onglet **Config étab**
2. Cliquer **Éditer** sur un hôpital public
3. Saisir son numéro structure (SIRET) → bouton **"Vérifier"**
4. Doit retourner :
   - Le nom officiel en vert (ex: "Centre Hospitalier de Lorient")
   - La liste des codes service disponibles dans un dropdown
   - Indication "code service obligatoire" si applicable

### 5. Monitoring continu

Admin → `/admin/healthcheck` → carte **"Chorus Pro (PISTE)"** :
- Vert "Opérationnel" : OAuth + API factures OK
- Orange "Dégradé" : OAuth OK mais API en attente
- Rouge "Erreur" : credentials manquants

Sync automatique toutes les 2h via cron `sync-chorus-status` (cf. cron pg_cron prod).

## Diagnostic en cas de problème

### Erreur 403 avec body écho

Pattern typique : `{"idUtilisateurCourant":0,"parametres":...}` retourné en 403.
**Cause** : scopes opérationnels non activés par AIFE.
**Solution** : ouvrir/relancer le ticket AIFE.

### Erreur 401 NOT_JSON

Pattern : 401 avec body vide ou WWW-Authenticate header.
**Cause** : token OAuth invalide ou KeyId rejeté.
**Solution** : vérifier `PISTE_API_KEY` et `PISTE_CLIENT_ID` dans Supabase secrets.

### Erreur "Aucun scope défini"

Sur PISTE → Application → section Scopes.
**Cause** : application en mode minimal, scopes pas encore activés.
**Solution** : ticket AIFE pour activation.

## Liens utiles

- Portail PISTE : https://piste.gouv.fr
- Documentation Chorus Pro API : https://chorus-pro.gouv.fr/cpro/transverses/v1/docs
- Communauté Chorus Pro (raccordements) : https://communaute.chorus-pro.gouv.fr/documentation/aides-aux-developpeurs-api-en-mode-oauth2/
- Support PISTE : support@piste.gouv.fr
