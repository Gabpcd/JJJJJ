# Captures Google Play

Le script `npm run screenshots:play` produit huit captures mobiles Jolene en
PNG **1080×1920** dans `artifacts/google-play/` (dossier ignoré par Git). Il
utilise Chromium avec un viewport 360×640 et une densité de pixels de 3.

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
ou sous `artifacts/`) et `HEADLESS=false` si Turnstile affiche un challenge.
Le script ne sauvegarde aucun état d'authentification et ne capture jamais la
page de connexion. Les données démo visibles ne sont ni masquées ni supprimées.
Si le navigateur local manque, l'installer avec `npx playwright install chromium`.

Vérification sans compte ni navigateur :

```sh
npm run screenshots:play:check
```
