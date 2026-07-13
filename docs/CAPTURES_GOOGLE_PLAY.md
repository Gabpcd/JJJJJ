# Captures Google Play

Le script `npm run screenshots:play` produit les huit mêmes scènes Jolene dans
les trois formats Google Play : téléphone en PNG **1080×1920**, tablette
7 pouces en **1920×1080** et tablette 10 pouces en **1920×1080**. Les fichiers
sont écrits dans `artifacts/google-play/phone/`,
`artifacts/google-play/tablet-7/` et `artifacts/google-play/tablet-10/`
(dossiers ignorés par Git).

Les quatre identifiants sont obligatoires et lus uniquement depuis
l'environnement :

- `JOLENE_STORE_SOIGNANT_EMAIL`
- `JOLENE_STORE_SOIGNANT_PASSWORD`
- `JOLENE_STORE_ETAB_EMAIL`
- `JOLENE_STORE_ETAB_PASSWORD`

Après les avoir exportés depuis un gestionnaire de secrets, lancer :

```sh
npm run screenshots:play
```

Options : `BASE_URL` (défaut `https://jolene.app`), `OUTPUT_DIR` (hors dépôt
ou sous `artifacts/`), `CAPTURE_FORMATS` (`all` par défaut, ou une liste parmi
`phone,tablet-7,tablet-10`) et `HEADLESS=false` si Turnstile affiche un
challenge. Exemple ciblé :

```sh
CAPTURE_FORMATS=phone,tablet-10 npm run screenshots:play
```

Le script ne sauvegarde aucun état d'authentification et ne capture jamais la
page de connexion. Les données démo visibles ne sont ni masquées ni supprimées.
Si le navigateur local manque, l'installer avec `npx playwright install chromium`.

Vérification sans compte ni navigateur :

```sh
npm run screenshots:play:check
```
