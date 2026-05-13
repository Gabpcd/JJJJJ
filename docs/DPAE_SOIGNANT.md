# DPAE côté soignant (Sprint 2 + Sprint 5.5 PR 10)

> Visibilité côté soignant des Déclarations Préalables à l'Embauche (DPAE) générées par l'établissement pour ses contrats CDD/CDDU/SALARIE.

## Données identité requises

Pour qu'un établissement puisse générer une DPAE depuis Net-Entreprises.fr (Option A Sprint 2), le soignant doit avoir complété :

| Champ DB `soignants.*` | Source UI |
|---|---|
| `sexe` (M/F) | `SectionDpaeIdentite.tsx` |
| `lieu_naissance_commune` | `SectionDpaeIdentite.tsx` |
| `lieu_naissance_departement` | `SectionDpaeIdentite.tsx` (si France) |
| `pays_naissance` | `SectionDpaeIdentite.tsx` |
| `nationalite` | `SectionDpaeIdentite.tsx` |
| **`numero_securite_sociale` (NIR)** | `SectionDpaeIdentite.tsx` (Sprint 5.5 PR 10) |
| `date_naissance` | `SectionProfilPrincipal.tsx` |
| `adresse_*` | `SectionProfilPrincipal.tsx` |

Avant Sprint 5.5 PR 10, le NIR était dans la liste `manquants` retournée par `fn_soignant_dpae_complet` mais **pas exposé en formulaire** → blocage utilisateur silencieux.

## RPC NIR Sprint 5.5 PR 10

`fn_maj_nir_soignant(p_nir text) RETURNS jsonb`

### Validation backend (regex strict)
```regex
^[12][0-9]{2}(0[1-9]|1[0-2])(0[1-9]|[12][0-9]|3[01]|2A|2B|9[0-9])[0-9]{6}([0-9]{2})?$
```

| Position | Signification | Format |
|---|---|---|
| 1 | Sexe | 1 (M) ou 2 (F) |
| 2-3 | Année naissance | 00-99 |
| 4-5 | Mois naissance | 01-12 |
| 6-7 | Département | 01-95, 2A, 2B, 96-99 (outre-mer) |
| 8-10 | Code INSEE commune | 001-999 |
| 11-13 | Ordre acte naissance | 001-999 |
| 14-15 | **Clé de contrôle** (optionnelle dans le UI) | 00-99 |

### Codes erreur

| Code | Cas |
|---|---|
| `NON_AUTHENTIFIE` | Pas de session |
| `NIR_REQUIS` | Vide ou null |
| `NIR_FORMAT_INVALIDE` | Regex non matchée |

## Page `/soignant/dpae` Sprint 5.5 PR 10

`src/pages/MesDPAE.tsx` — appelle `fn_mes_dpae()`.

### KPI cards
- **Total contrats CDD signés**
- **DPAE validées** (numéro URSSAF saisi)
- **En attente étab**

### Filtres tabs
- `TOUS` / `VALIDEE` / `EN_ATTENTE`

### DpaeCard par contrat
- Mission (intitulé + dates)
- Établissement
- Type contrat (CDD / CDDU / SALARIE)
- Badge statut (✅ Validée URSSAF / ⏳ En attente)
- Si validée : **numéro URSSAF copiable** + date saisie
- Si en attente : message d'alerte avec contact établissement
- Liens : "Voir la mission" / "Voir le contrat"

### RPC `fn_mes_dpae`
- STABLE, SECURITY DEFINER
- Join `contrats_mission` + `missions` + `etablissements`
- Filtre : `soignant_id = auth.uid()` + type CDD/CDDU/SALARIE + statut `SIGNE_*`
- Retour `{ success: true, dpae: [...] }`

## Workflow complet DPAE Option A (Sprint 2)

1. **Soignant** : complète son profil DPAE (identité + NIR).
2. **Étab** : signe le contrat avec soignant → contrat `SIGNE_COMPLET`.
3. **Étab** : accède au composant `DPAEStatus.tsx` dans `ContratMission.tsx` → génère le payload pré-rempli via `fn_generer_donnees_dpae`.
4. **Étab** : copie/colle sur net-entreprises.fr, soumet la DPAE.
5. **Étab** : saisit le numéro URSSAF retour via `fn_enregistrer_numero_dpae`.
6. **Soignant** : retrouve la DPAE validée dans `/soignant/dpae` avec numéro URSSAF affiché.

## Audit Sprint 5.5

- **PR 10** (#143) — Fix P0-12 (page DPAE soignant manquante) + P0-13 (NIR absent UI).

## Sécurité

- NIR stocké en clair côté DB mais **accès restreint** par RLS au soignant lui-même + étab via fn_generer_donnees_dpae.
- Pas de transmission au front via JSON brut hors `fn_generer_donnees_dpae` (côté étab).
- Audit `DONNEES_PERSO_MODIFICATION` à chaque update NIR.
