# Captures Google Play et App Store

Le script `npm run screenshots:play` produit les huit mêmes scènes Jolene dans
les trois formats Google Play : téléphone en PNG **1080×1920**, tablette
7 pouces en **1920×1080** et tablette 10 pouces en **1920×1080**. Les fichiers
sont écrits dans `artifacts/google-play/phone/`,
`artifacts/google-play/tablet-7/` et `artifacts/google-play/tablet-10/`.
`npm run screenshots:app-store` produit aussi les formats Apple exacts : iPhone
6,5 pouces **1284×2778**, iPhone 6,9 pouces **1320×2868** et iPad 13 pouces
portrait **2064×2752** / paysage **2752×2064**, sous `artifacts/app-store/`.
Tous ces dossiers sont ignorés par Git.

Toujours relancer le script après le dernier déploiement de production : les
captures ne doivent pas provenir d'un build antérieur aux corrections soumises.
Le script produit les captures d'écran uniquement ; l'icône de fiche 512×512 et
la feature graphic 1024×500 restent deux visuels distincts à vérifier dans Play
Console.

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
ou sous `artifacts/`), `CAPTURE_STORE` (`google-play` par défaut ou
`app-store`), `CAPTURE_FORMATS` (`all` par défaut, ou une liste de formats du
store sélectionné) et `HEADLESS=false` si Turnstile affiche un challenge.
Exemples :

```sh
CAPTURE_FORMATS=phone,tablet-10 npm run screenshots:play
npm run screenshots:app-store
```

Le script ne sauvegarde aucun état d'authentification et ne capture jamais la
page de connexion. Les données démo visibles ne sont ni masquées ni supprimées.
Si le navigateur local manque, l'installer avec `npx playwright install chromium`.

Vérification sans compte ni navigateur :

```sh
npm run screenshots:play:check
npm run screenshots:app-store:check
```
