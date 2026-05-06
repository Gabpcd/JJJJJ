# Module — Série d'emails d'onboarding J0–J7

## Vue d'ensemble

À chaque inscription d'un soignant ou d'un établissement, Jolene planifie une **série de 4 emails** envoyés sur les 7 premiers jours pour accompagner l'utilisateur dans la prise en main de la plateforme :

| Étape | Délai | Audience SOIGNANT | Audience ÉTAB |
|------|------|-------------------|---------------|
| `J0` | immédiat | Bienvenue détaillée + premiers pas | Bienvenue détaillée + premiers pas |
| `J1` | + 1 jour | Compléter votre profil | Signer contrat + uploader RIB |
| `J3` | + 3 jours | Postuler à votre 1ère mission | Publier votre 1ère mission |
| `J7` | + 7 jours | Récap profil et opportunités | Récap missions + candidatures |

**Pourquoi** : activation utilisateur sur les 7 premiers jours = phase critique de l'onboarding. Chaque email est conditionnel : si l'utilisateur a déjà accompli l'action attendue, l'email est skipped (pas d'email inutile).

**Quand** : `J0` est envoyé immédiatement à l'inscription, puis `J+1`, `J+3`, `J+7` via cron quotidien à 8 h Paris.

---

## Architecture

### Table `serie_email_envois`

```
id              uuid PK
utilisateur_id  uuid FK auth.users
serie           enum SOIGNANT_ONBOARDING | ETAB_ONBOARDING
etape           enum J0 | J1 | J3 | J7
planifie_le     timestamptz
envoye_le       timestamptz
skip_raison     text
statut          enum PLANIFIE | ENVOYE | SKIPPED | ERREUR
erreur_message  text
tentatives      integer (max 3)
UNIQUE (utilisateur_id, serie, etape)
```

Index partiel `idx_serie_email_a_traiter` sur `(statut, planifie_le) WHERE statut='PLANIFIE'` pour scanner rapidement les rows à traiter.

### RPCs

- **`fn_planifier_serie_onboarding(utilisateur_id, serie)`** — appelée par `register-soignant` et `register-etablissement` après création du compte. INSERT 4 rows (J0=now, J1=+1d, J3=+3d, J7=+7d) en `PLANIFIE`. `ON CONFLICT DO NOTHING` (idempotente).
- **`fn_verifier_skip_serie_onboarding(envoi_id) → jsonb`** — appelée par le cron pour chaque row. Retourne `{skip:bool, raison:text}` selon l'état utilisateur courant (pas au moment de la planification).
- **`fn_obtenir_donnees_template_serie(envoi_id) → jsonb`** — retourne les variables dynamiques à passer à `send-email` (prénom, nom, profession, nb_missions_actives, etc.).
- **`fn_lire_secret_cron() → text`** — expose le secret service_role stocké en vault, callable uniquement par service_role (utilisé par les edge functions pour valider les bearer tokens des cron jobs avec le nouveau format JWT asymétrique `sb_secret_…`).

### Edge function `email-cron`

- Schedule : `cron.job` quotidien `0 8 * * *` (8 h UTC = 10 h Paris été / 9 h Paris hiver — rajuster si besoin).
- Auth : Bearer token = legacy JWT (`SUPABASE_SERVICE_ROLE_KEY`) OU nouveau secret asymétrique (`SUPABASE_SECRET_KEY`) OU secret en vault (via `fn_lire_secret_cron`).
- Pour chaque row `PLANIFIE` avec `planifie_le ≤ now()` et `tentatives < 3` (limit 50 par run) :
  1. **Skip métier** — appel `fn_verifier_skip_serie_onboarding`. Si `skip:true` → `UPDATE statut='SKIPPED' + skip_raison` + audit `SERIE_EMAIL_SKIPPED`.
  2. **Skip prefs** — appel `fn_doit_notifier(user, 'SERIE_ONBOARDING', 'EMAIL')`. Si `false` → SKIPPED `NOTIFICATION_DESACTIVEE` + audit.
  3. **Variables dynamiques** — `fn_obtenir_donnees_template_serie`.
  4. **Envoi** — `sb.functions.invoke('send-email', { type: 'SERIE_<SOIGNANT|ETAB>_<J0|J1|J3|J7>', destinataire_id, data })`.
  5. **Succès** — `UPDATE statut='ENVOYE' + envoye_le + tentatives++` + audit `SERIE_EMAIL_ENVOYE`.
  6. **Erreur** — `tentatives++`. Si `tentatives < 3` → `statut='PLANIFIE'` (retry au prochain cron). Si `tentatives = 3` → `statut='ERREUR'` + audit `ADMIN_ACTION` avec `event='SERIE_EMAIL_ERREUR_DEFINITIVE'`.

---

## Conditions de skip détaillées

### SOIGNANT_ONBOARDING

| Étape | Critère skip | Raison retournée |
|------|------------|------------------|
| `J0` | jamais skip | — |
| `J1` | `tous_documents_valides` ET `rpps_verifie` (ou profession AS/AES) ET (`type_exercice=SALARIE` OU `mandat_facturation_signe`) | `PROFIL_DEJA_COMPLET` |
| `J3` | au moins 1 candidature existante | `CANDIDATURE_DEJA_EFFECTUEE` |
| `J3` | J1 SKIPPED avec `skip_raison='NOTIFICATION_DESACTIVEE'` | `NOTIFICATIONS_DESACTIVEES_J1` (cascade) |
| `J7` | au moins 1 mission `ASSIGNEE`/`EN_COURS`/`TERMINEE` | `MISSION_DEJA_ASSIGNEE` |

### ETAB_ONBOARDING

| Étape | Critère skip | Raison retournée |
|------|------------|------------------|
| `J0` | jamais skip | — |
| `J1` | `contrat_service_signe=true` ET `rib_s3_key` non-NULL et ≠ `'legacy/auto-backfill'` | `ONBOARDING_DEJA_COMPLET` |
| `J3` | au moins 1 mission publiée | `MISSION_DEJA_PUBLIEE` |
| `J7` | au moins 1 candidature reçue sur une mission de l'étab | `CANDIDATURE_DEJA_RECUE` |

**Cascade** : si `NOTIFICATION_DESACTIVEE` à J1, alors `J3` ne ré-essaie pas (raison `NOTIFICATIONS_DESACTIVEES_J1`).

---

## Retry et erreurs

- **Cap 3 tentatives**. Une fois `tentatives = 3`, le row passe `statut='ERREUR'` définitif et n'est plus repris (filtre cron `lt('tentatives', 3)`).
- À chaque erreur définitive, audit `journaux_audit` : `action='ADMIN_ACTION'`, `details.event='SERIE_EMAIL_ERREUR_DEFINITIVE'`, `details.error=<message>`.
- Diagnostic : `SELECT id, statut, tentatives, erreur_message, skip_raison FROM serie_email_envois WHERE statut='ERREUR' ORDER BY mis_a_jour_le DESC LIMIT 20;`

---

## Variables dynamiques par template

`fn_obtenir_donnees_template_serie` enrichit le payload `data` envoyé à `send-email` :

### SOIGNANT_ONBOARDING
- Toutes étapes : `prenom`, `nom`, `profession`, `lien_dashboard`
- `J3` : ajoute `nb_missions_actives` (count missions `OUVERTE`)
- `J7` : ajoute `nb_candidatures` (count candidatures du soignant)

### ETAB_ONBOARDING
- Toutes étapes : `nom_etablissement`, `type_etablissement`, `contrat_signe`, `lien_dashboard`
- `J3`/`J7` : ajoute `nb_missions_publiees`
- `J7` : ajoute `nb_candidatures_recues`

---

## Comment ajouter un nouveau template série

1. Ajouter l'étape à l'enum `serie_onboarding_etape` (migration).
2. Mettre à jour `fn_planifier_serie_onboarding` pour INSERT le row à la planification.
3. Compléter `fn_verifier_skip_serie_onboarding` avec la logique skip de la nouvelle étape.
4. Compléter `fn_obtenir_donnees_template_serie` si besoin de variables dynamiques.
5. Ajouter le type au whitelist `ALLOWED_TYPES` de `send-email/index.ts` + ajouter la fonction `buildEmailContent` correspondante.
6. Ajouter le mapping dans `TYPE_TO_EVENT` pour que `fn_doit_notifier` route vers `SERIE_ONBOARDING`.
7. Redéployer `send-email` puis ajouter un test E2E.

---

## Préférences utilisateur

L'utilisateur peut désactiver les emails de la série dans `/soignant/parametres/notifications` (ou `/etablissement/...`) :
- Toggle "Bienvenue / Onboarding" pour le canal "Email" → désactive toute la série.
- Désactiver le canal "Email" globalement → désactive tout (sauf `URGENCE`).

`fn_doit_notifier` retourne `false` dans les deux cas. Le cron skip avec raison `NOTIFICATION_DESACTIVEE` + audit.

---

## Debugging

### Pourquoi un email n'a pas été envoyé ?

```sql
SELECT id, serie, etape, statut, skip_raison, tentatives, erreur_message,
       planifie_le, envoye_le, mis_a_jour_le
FROM serie_email_envois
WHERE utilisateur_id = '<user_id>'
ORDER BY etape;
```

Interprétation :
- `statut='SKIPPED'` + `skip_raison='PROFIL_DEJA_COMPLET'` → l'utilisateur avait déjà fini son onboarding au moment de l'envoi.
- `statut='SKIPPED'` + `skip_raison='NOTIFICATION_DESACTIVEE'` → l'utilisateur a désactivé les emails dans ses préférences.
- `statut='ERREUR'` + `tentatives=3` → 3 échecs successifs. Voir `erreur_message` et chercher dans `journaux_audit` les détails.
- `statut='PLANIFIE'` + `planifie_le` futur → pas encore l'heure.
- `statut='PLANIFIE'` + `planifie_le` passé → cron pas encore passé OU cron en panne (vérifier dernier run dans `cron.job_run_details WHERE jobid=<id>`).

### Monitoring

```sql
-- Distribution des statuts sur les 30 derniers jours
SELECT statut, count(*) AS n
FROM serie_email_envois
WHERE cree_le >= now() - interval '30 days'
GROUP BY statut ORDER BY n DESC;

-- Top raisons de skip
SELECT skip_raison, count(*) AS n FROM serie_email_envois
WHERE statut='SKIPPED' GROUP BY skip_raison ORDER BY n DESC;

-- Taux d'erreur par étape
SELECT etape, count(*) FILTER (WHERE statut='ERREUR') AS erreurs,
       count(*) AS total, round(100.0 * count(*) FILTER (WHERE statut='ERREUR') / count(*), 2) AS pct
FROM serie_email_envois
WHERE cree_le >= now() - interval '7 days'
GROUP BY etape ORDER BY etape;
```

---

## Tests E2E (J2.3.B.2.2)

9 scénarios validés sur la production live (project Jolene) :

| # | Scénario | Résultat |
|---|----------|----------|
| S1 | J0 immédiat → ENVOYE | ⚠ Cron pickup OK, send-email 400 (templates non déployés en prod, voir _Action Gabrielle_) |
| S2 | J1 envoyé si profil incomplet | ⚠ idem |
| S3 | J1 SKIPPED si profil complet (`PROFIL_DEJA_COMPLET`) | ✅ |
| S4 | Cascade J3 SKIPPED si J1 SKIPPED `NOTIFICATION_DESACTIVEE` (raison `NOTIFICATIONS_DESACTIVEES_J1`) | ✅ |
| S5 | SKIPPED `NOTIFICATION_DESACTIVEE` si pref désactivée | ✅ |
| S6 | Rattrapage retard 5 jours (cron pickup OK même `planifie_le=now()-5d`) | ✅ |
| S7 | Retry après échec temporaire (tentatives 1→2 puis 2→3) | ✅ (mécanisme retry validé via 4 cron runs successifs) |
| S8 | Cap 3 tentatives → `statut='ERREUR'` + audit `ADMIN_ACTION` `SERIE_EMAIL_ERREUR_DEFINITIVE` | ✅ |
| S9 | Symétrique étab : J0 ENVOYE, J1 `ONBOARDING_DEJA_COMPLET`, J3 `MISSION_DEJA_PUBLIEE`, J7 `CANDIDATURE_DEJA_RECUE` | ✅ (J1/J3/J7 skips ; J0 idem S1) |

**Bugs prod découverts pendant les tests E2E + corrigés dans la session** :

1. **Auth 401** : `email-cron` n'acceptait que le legacy JWT, alors que `pg_cron` envoie désormais le secret asymétrique (`sb_secret_…`) stocké en vault. Cron silencieusement HS depuis le switch JWT (rappels J-1 contrat de travail aussi). Fix : `email-cron` accepte legacy + nouveau format + secret vault via `fn_lire_secret_cron`. `send-email` patché de la même façon.
2. **GRANT manquant** : `service_role` n'avait pas `SELECT` sur `serie_email_envois` ni `INSERT` sur `journaux_audit`. Le cron faisait des queries sans erreur visible mais retournait des résultats vides et n'écrivait pas d'audit. Fix : migrations `j23b22_grant_select_serie_email` + `j23b22_grant_audit_service_role`.

**Action Gabrielle restante** : redéployer `send-email` (>70 KB, hors MCP) avec les 8 templates `SERIE_*` whitelistés et les fixes auth (legacy + nouveau format + vault). Sans ce redéploiement, S1/S2/S6/S9-J0 (envoi réel) restent KO en prod.
