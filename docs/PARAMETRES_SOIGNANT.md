# Paramètres soignant unifiés (Sprint 5.5 PR 5 + PR 6 + PR 7)

> Page parente `/soignant/parametres` consolidant les paramètres soignant éparpillés dans Profil/Préférences/Confidentialité + sous-routes.

## Structure

`src/pages/PageParametresSoignant.tsx` (lazy import dans `App.tsx`).

### Navigation rapide (en tête)

Deux raccourcis vers les sous-pages existantes :
- **Notifications** → `/soignant/parametres/notifications`
- **Recherches sauvegardées** → `/soignant/parametres/recherches-sauvegardees`

### Sections (sidebar + contenu)

| # | Section | Contenu actuel |
|---|---|---|
| 1 | **Mon compte** | Email read-only + téléphone (mention édition profil) + `ChangementMotDePasse` (PR 6) |
| 2 | **Identité et documents** | Description + CTA vers `/soignant/profil` |
| 3 | **Préférences mission** | CTA vers `/soignant/profil?tab=preferences` + bloc **suivi GPS** avec `ConsentementPingGps` (PR 7) |
| 4 | **Disponibilités et calendrier** | CTAs vers planning + recherches sauvegardées |
| 5 | **Données personnelles (RGPD)** | CTA vers `/soignant/profil?tab=confidentialite` (export/suppression) |
| 6 | **Paramètres avancés** | Mode sombre (auto), langue (FR uniquement) |

### Deeplink

Support `?section=preferences` etc. pour navigation directe vers une section.

## Section "Mon compte" : changement mot de passe (PR 6)

Composant : `src/components/soignant/ChangementMotDePasse.tsx`.

### Critères force MDP
| Critère | Validation |
|---|---|
| Longueur | ≥ 12 caractères |
| Majuscule | au moins 1 |
| Minuscule | au moins 1 |
| Chiffre | au moins 1 |
| Spécial | au moins 1 (`[^A-Za-z0-9]`) |

Jauge horizontale colorée + label texte (Très faible → Excellent).

### Workflow sécurisé

1. **Vérif ancien MDP** : `supabase.auth.signInWithPassword({ email, password: ancien })` silencieux. Si erreur → "Ancien mot de passe incorrect".
2. **Update** : `supabase.auth.updateUser({ password: nouveau })`.
3. **Audit** : `fn_ecrire_audit_safe` action `DONNEES_PERSO_MODIFICATION` (`MOT_DE_PASSE_MODIFIE` absent de l'enum CHECK).
4. Toggle visibilité ancien/nouveau (Eye/EyeOff).
5. Reset des 3 champs après succès.

## Section "Préférences mission" : ping GPS background (PR 7)

Wiring du composant `ConsentementPingGps.tsx` (Sprint 4.5 PR 10).

### Bloc dédié
- Titre "Suivi GPS pendant les missions" + icône MapPin
- Description : finalité (fiabilité pointage + résolution litige), rétention 30j, opt-in révocable
- `ConsentementPingGps` inline :
  - Utilise `aConsenti()` + `setConsentement()` (`src/lib/background-geoloc.ts`)
  - Affichage explicite des finalités RGPD
  - Toggle révocable à tout moment

### Audit
Chaque changement déclenche `RGPD_CONSENTEMENT_DONNE` côté backend (cf. Sprint 4.5).

## Routes App.tsx

```
/soignant/parametres                    → PageParametresSoignant (lazy)
/soignant/parametres/notifications      → PageParametresNotifications (existant)
/soignant/parametres/recherches-sauvegardees → PageRecherchesSauvegardees (existant)
```

## Audit Sprint 5.5

- **PR 5** (#138) : page parente + 6 sections + nav rapide
- **PR 6** (#139) : `ChangementMotDePasse` intégré section "Mon compte"
- **PR 7** (#140) : `ConsentementPingGps` wiring section "Préférences mission"

Fix global : **P0-3 audit Sprint 5** "Pas de page parente `/soignant/parametres`".
