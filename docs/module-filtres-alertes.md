# Module — Filtres sauvegardés + alertes nouvelles missions/soignants

## Vue d'ensemble

Permet aux soignants et établissements de **sauvegarder leurs critères
de recherche** et d'activer des **alertes email automatiques** quand
de nouveaux résultats matchent leurs critères.

| Audience                          | Page de recherche                | Alertes |
|-----------------------------------|----------------------------------|---------|
| `SOIGNANT_RECHERCHE_MISSIONS`     | `/soignant/recherche-missions`   | ✅ |
| `ETAB_RECHERCHE_SOIGNANTS`        | _(pas encore créée — J5 Différenciation)_ | ⚠️ |

**Pourquoi** : permettre à l'utilisateur de retrouver rapidement ses
recherches fréquentes + d'être notifié dès qu'un nouveau match apparaît
sans avoir à revisiter la plateforme.

---

## Architecture

### Schéma DB

```
filtres_sauvegardes
  id              uuid PK
  utilisateur_id  uuid FK auth.users  (ON DELETE CASCADE)
  nom             text  CHECK length 1-100
  audience        enum  SOIGNANT_RECHERCHE_MISSIONS | ETAB_RECHERCHE_SOIGNANTS
  filtres         jsonb (cf. schéma ci-dessous)
  alerte_active   boolean
  frequence_alerte enum IMMEDIATE | QUOTIDIENNE | HEBDOMADAIRE
  dernier_check_le timestamptz
  nb_resultats_dernier_check integer
  cree_le, mis_a_jour_le
  UNIQUE (utilisateur_id, nom)
```

Index partiel `idx_filtres_sauvegardes_alerte_cron` sur
`(alerte_active, frequence_alerte, dernier_check_le) WHERE alerte_active = true`
pour scanner rapidement les filtres à évaluer.

### Schéma jsonb `filtres`

#### SOIGNANT_RECHERCHE_MISSIONS
```json
{
  "profession": "IDE",
  "rayonKm": 50,
  "tauxMin": 25,
  "typeContrat": "TOUS",
  "urgentesOnly": false,
  "horaire": "TOUS",
  "villeRecherche": ""
}
```

#### ETAB_RECHERCHE_SOIGNANTS
```json
{
  "profession": "IDE",
  "experience_min_annees": 2,
  "note_minimum": 4,
  "type_exercice": "LIBERAL",
  "rayon_km": 30
}
```
_(Schéma indicatif — la page de recherche soignants étab n'est pas
encore implémentée. À finaliser en J5.)_

### Critères de match (côté DB)

`fn_compter_nouveaux_pour_filtre(filtre_id, since)` parse le jsonb et
exécute :

#### SOIGNANT_RECHERCHE_MISSIONS
```sql
SELECT count(*) FROM missions m
WHERE m.statut = 'OUVERTE'
  AND m.cree_le > since
  AND (profession IS NULL OR m.profession_requise = profession)
  AND COALESCE(m.taux_horaire_base, 0) >= tauxMin
  AND (NOT urgentesOnly OR COALESCE(m.est_urgente, false) = true);
```

⚠️ Le matching DB est **plus simple** que le matching frontend qui
calcule en JS la distance géo (rayonKm/villeRecherche) + le filtre
horaire (jour/nuit/weekend) sur `m.debut_le`. Pour l'alerte cron,
on filtre sur les critères "durs" stockables en DB (profession + taux
+ urgentes). L'utilisateur voit la liste précise quand il clique sur
le lien dans l'email.

### RPCs

| RPC | Auth | Description |
|---|---|---|
| `fn_creer_filtre_sauvegarde(nom, audience, filtres, alerte_active, frequence_alerte)` | authenticated | INSERT + audit FILTRE_CREE + ALERTE_ACTIVEE. Limite 20 filtres/user. |
| `fn_lister_mes_filtres_sauvegardes(audience?)` | authenticated | Retourne JSONB array des filtres du user (filtre par audience optionnel). |
| `fn_modifier_filtre_sauvegarde(id, nom?, alerte_active?, frequence_alerte?)` | authenticated | UPDATE + audit FILTRE_MODIFIE + ALERTE_ACTIVEE/DESACTIVEE si toggle. Le `filtres jsonb` n'est pas modifiable (créer un nouveau). |
| `fn_supprimer_filtre_sauvegarde(id)` | authenticated | DELETE + audit FILTRE_SUPPRIME. |
| `fn_compter_nouveaux_pour_filtre(filtre_id, since)` | service_role | Helper pour compter les nouveaux résultats. |
| `fn_obtenir_apercu_filtre(filtre_id, since, limit)` | service_role | Top N résultats pour preview email. RGPD : étab voit prénom + initiale uniquement. |
| `fn_evaluer_alertes_filtres(p_frequence?)` | service_role | Boucle sur filtres éligibles, UPDATE state, retourne liste matchant. |

### Fenêtres d'évaluation

| Fréquence | Condition d'éligibilité | Latence max |
|---|---|---|
| `IMMEDIATE` | `dernier_check_le < now() - 55 minutes` | 1 heure |
| `QUOTIDIENNE` | `dernier_check_le < now() - 23 hours` | 24 heures |
| `HEBDOMADAIRE` | `dernier_check_le < now() - 6 days 23 hours` | 7 jours |

**Note** : `IMMEDIATE` n'est pas du temps réel mais une **vérification
horaire** (latence max 1 h). Choix pragmatique pour éviter un trigger
AFTER INSERT sur `missions` qui ralentirait chaque création de mission.
Pour activer un cron horaire dédié IMMEDIATE, voir section **Cron**.

### Templates email

| Type Resend | Audience | Sujet |
|---|---|---|
| `NOUVELLES_MISSIONS_FILTRE` | soignant | "[X] nouvelle(s) mission(s) match votre recherche '[nom_filtre]'" |
| `NOUVEAUX_SOIGNANTS_FILTRE` | étab | "[X] nouveau(x) soignant(s) match votre recherche '[nom_filtre]'" |

Variables passées par `email-cron` :
- `nom_filtre`, `count`
- SOIGNANT : `prenom`, `missions[]` (max 5 : intitulé, étab, ville, taux, urgente)
- ETAB : `nom_etab`, `soignants[]` (max 5 : prénom + initiale, profession, note)

Si `count > 5`, le template affiche "+ X autres" et un bouton "Voir
toutes les missions/soignants" qui pointe vers la page de recherche
correspondante.

Mapping `TYPE_TO_EVENT` dans send-email :
- `NOUVELLES_MISSIONS_FILTRE` → `NOUVELLE_MISSION_MATCHANT_FILTRE`
- `NOUVEAUX_SOIGNANTS_FILTRE` → `NOUVEAU_SOIGNANT_MATCHANT_FILTRE`

`fn_doit_notifier(user, evt, EMAIL)` vérifie les préférences
notifications avant l'envoi. Si désactivé → audit `NOTIFICATION_SKIPPED`,
pas d'email.

### Cron

`email-cron-daily` (8h Paris) appelle `fn_evaluer_alertes_filtres(NULL)`
qui traite **toutes les fréquences** confondues (la fenêtre filtre
par elle-même).

Pour vraiment activer `IMMEDIATE` (latence 1 h au lieu de 24 h),
**Gabrielle doit créer un cron horaire** :

```sql
SELECT cron.schedule('alertes-filtres-immediate-hourly', '0 * * * *', $$
SELECT net.http_post(
  url := 'https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/email-cron',
  headers := jsonb_build_object(
    'Content-Type', 'application/json',
    'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1)
  ),
  body := '{}'::jsonb,
  timeout_milliseconds := 60000
);
$$);
```

Sans ce cron, IMMEDIATE attend le run quotidien de 8 h Paris (latence
réelle = 24 h max).

---

## Flow d'envoi (E2E)

```
1. UI utilisateur sauvegarde filtre via fn_creer_filtre_sauvegarde
   (ou modifie via fn_modifier).
2. Cron (8h Paris OU horaire) → invoke email-cron edge function.
3. email-cron appelle fn_evaluer_alertes_filtres(NULL)
   → retourne (filtre_id, utilisateur_id, audience, nom, nb_nouveaux)
   pour chaque filtre éligible avec >0 nouveaux résultats.
4. Pour chaque match :
   a. fn_obtenir_apercu_filtre(filtre_id, '1970-01-01', 5)
      → top 5 résultats au format jsonb pour le template.
   b. Récupère prénom (soignant) ou nom_etab (étab) depuis la table.
   c. invoke send-email avec type SERIE_FILTRE approprié.
   d. send-email vérifie fn_doit_notifier (canal EMAIL) :
      • si désactivé → audit NOTIFICATION_SKIPPED + return 200 silent
      • sinon → Resend API + INSERT emails_envoyes
   e. cron : si invoke success → INSERT audit ALERTE_ENVOYEE
            sinon → log erreur + continue (best-effort, n'arrête pas
                    le batch).
5. fn_evaluer_alertes_filtres a déjà UPDATE dernier_check_le + 
   nb_resultats_dernier_check côté DB → idempotence (le filtre ne
   sera pas re-eval avant la prochaine fenêtre).
```

---

## Limites

- **Max 20 filtres** par utilisateur (validé par RPC `fn_creer_filtre_sauvegarde`).
- **IMMEDIATE = check horaire**, pas trigger temps réel.
- **Matching DB simplifié** : profession + taux + urgentes seulement.
  Pas de matching distance géo en DB (calculé en JS côté frontend).
- **Page de recherche soignants étab** : pas encore implémentée. Les
  étabs peuvent gérer/supprimer leurs filtres existants via
  `/etablissement/parametres/recherches-sauvegardees`, mais la création
  pratique est limitée à l'absence de page de recherche associée.
  À finaliser en J5 Différenciation.
- **Cron horaire IMMEDIATE** : à activer manuellement par Gabrielle (cf.
  section Cron). Sans ça, IMMEDIATE = 24 h max comme QUOTIDIENNE.

---

## Cohérence avec d'autres modules

- **J2.3.A — Préférences notifications** : `fn_doit_notifier` est
  appelée avant chaque envoi via `TYPE_TO_EVENT[type] → type_evenement`.
  L'utilisateur peut désactiver `NOUVELLE_MISSION_MATCHANT_FILTRE`
  (canal EMAIL) pour ne plus recevoir d'alertes filtres.
- **J2.3.B — Série email J0/J1/J3/J7** : indépendant. Mêmes audits,
  même cron, même `send-email`.

---

## Debug : pourquoi mon alerte n'a pas été envoyée ?

Requêtes SQL utiles :

```sql
-- 1. Vérifier que le filtre existe + alerte active
SELECT id, nom, alerte_active, frequence_alerte,
  dernier_check_le, nb_resultats_dernier_check
FROM filtres_sauvegardes
WHERE utilisateur_id = '<user_id>' ORDER BY mis_a_jour_le DESC;
```

Interprétation :
- `alerte_active = false` → l'utilisateur a désactivé l'alerte.
- `dernier_check_le` récent (<23 h pour QUOTIDIENNE) → pas encore re-eval.
- `dernier_check_le` ancien + `nb_resultats_dernier_check = 0` →
  eval a tourné mais aucun match. Pas d'email attendu.

```sql
-- 2. Vérifier les audits récents
SELECT action, details, cree_le FROM journaux_audit
WHERE id_ressource = '<filtre_id>'::text OR (action='NOTIFICATION_SKIPPED' AND id_ressource = '<user_id>')
ORDER BY cree_le DESC LIMIT 20;
```

Si on voit `NOTIFICATION_SKIPPED` avec `raison = 'preference_user_off'` :
l'utilisateur a désactivé `NOUVELLE_MISSION_MATCHANT_FILTRE` (EMAIL)
dans ses préférences globales.

```sql
-- 3. Vérifier les emails envoyés récents
SELECT type, sujet, destinataire_email, statut, erreur, cree_le
FROM emails_envoyes
WHERE destinataire_id = '<user_id>'
  AND type IN ('NOUVELLES_MISSIONS_FILTRE','NOUVEAUX_SOIGNANTS_FILTRE')
ORDER BY cree_le DESC LIMIT 10;
```

Si `statut = 'ERREUR'` : voir le champ `erreur` (problème Resend ou
template).

```sql
-- 4. Vérifier les runs cron récents (gabrielle.pcd@outlook.com pour mémoire)
SELECT j.jobname, r.start_time, r.status, r.return_message
FROM cron.job_run_details r
JOIN cron.job j ON j.jobid = r.jobid
WHERE j.jobname LIKE '%email-cron%' OR j.jobname LIKE '%alertes%'
ORDER BY r.start_time DESC LIMIT 10;
```

---

## Tests E2E (résultats J2.3.C.3)

| # | Scénario | Résultat |
|---|----------|----------|
| S1 | Création filtre via RPC | ✅ |
| S2 | Limite 20 filtres bloque le 21e | ✅ |
| S3 | Modification (nom + fréquence) | ✅ |
| S4 | Suppression | ✅ |
| S5 | Lister via fn_lister | ✅ |
| S6 | Eval QUOTIDIENNE 0 nouveaux → check_recent OK, pas d'email | ✅ |
| S7 | Eval QUOTIDIENNE avec match → email envoyé + audit ALERTE_ENVOYEE | ✅ |
| S8 | Email réel reçu Outlook | ⚠️ Fix send-email validé (200 OK direct), test inscription FE bloqué côté Gabrielle |
| S9 | 2e eval sans nouvelle mission → skip silencieux | ✅ (filtre dans fenêtre 23h) |
| S10 | HEBDOMADAIRE éligible (dernier_check > 6d23h) | ✅ |
| S11 | HEBDOMADAIRE pas encore (3 jours) | ✅ skip |
| S12 | IMMEDIATE eval (>55min) | ✅ |
| S13 | Skip notification désactivée → audit NOTIFICATION_SKIPPED | ✅ |
| S14 | Alerte off → pas eval | ✅ |
| S15 | Cascade DELETE FK auth.users → filtres_sauvegardes | ✅ (validé via constraint) |
| S16 | RLS cross-tenant → 0 rows | ✅ |
| S17 | Sans auth → rejet | ⚠️ Test JWT context dans MCP non strict, code path validé via `IF v_uid IS NULL` |
| S18 | Filtre `urgentesOnly=true` match mission urgente | ✅ |
| S19 | Cron continue après erreur send-email | ⚠️ try/catch en place dans cron, scénario forcé difficile |
| S20 | Perf 10 filtres en boucle | ✅ |
| S21 | Pages dédiées RLS étab | ✅ (composant unifié, RLS table OK) |

**Bug découvert + corrigé pendant les tests** :
- `auth.admin.getUserById` régression côté Supabase platform avec
  `sb_secret_…` bearer. Tous les emails retournaient 404 "Destinataire
  introuvable". Fix : changer l'ordre de fallback dans `send-email` →
  d'abord `soignants.email`, puis `etablissements.email_contact`,
  puis `auth.admin.getUserById` en dernier recours.
  Commit `c26594fb`.
