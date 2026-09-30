# Recette Explorer : conserver l’arrivée de l’inscription

Base `a2157887`, lot distinct de #1000. Le seul changement de scénario concerne
« SOIGNANT — Explorer peuplé, détail et retour sans candidature automatique ».

## Constat limité

Dans la trace ciblée `/private/tmp/jolene-ipad-02444866-trace-ciblee/trace.zip`,
l’inscription avait déjà atteint `/soignant/recherche-missions`. Le scénario
appelait ensuite `aller()` vers cette même URL, ce qui relançait un document :

- `call@40020`, `goto`, début **684831,979 ms** ;
- événement `pageError` WebKit à **684852,250 ms**, soit **20,271 ms** après ;
- `goBack` `call@40216` à **691372,642 ms**, beaucoup plus tard.

La trace prouve cette navigation document redondante et cette chronologie.
Elle ne prouve pas la cause profonde de l’erreur WebKit, ni un défaut CORS ou
un correctif produit. Aucun changement de code applicatif n’est fait ici.

## Changement

Après `entrer(page, 'inscription')`, le scénario appelle `aller()` uniquement
si le pathname courant n’est pas déjà celui d’Explorer, puis affirme l’URL.
Si l’inscription y est arrivée, son interface courante est conservée. Le chemin
alternatif vers Explorer reste disponible lorsque l’inscription arrive au
tableau de bord.

Une comparaison du fichier contre la base confirme cette substitution unique :
les assertions métier, les captures, `goBack`, la conservation de l’onglet Liste,
l’absence de candidature automatique et les gardes `unknown=[]` / `errors=[]`
sont identiques. Aucun filtre d’erreur, temporisation ou réessai ajouté. Le helper
commun `entrer`/`aller` et la configuration Playwright restent inchangés.

## Vérification locale

Le scénario corrigé passe **5/5 au premier essai**, retries=0 :

| Format | Moteur local | Appels API fictifs | Erreurs JS / inconnus |
|---|---|---:|---|
| iPad portrait | WebKit | 36 | 0 / 0 |
| iPad paysage | WebKit | 36 | 0 / 0 |
| iPhone | WebKit | 36 | 0 / 0 |
| Android | Chrome | 36 | 0 / 0 |
| Ordinateur | Chrome | 37 | 0 / 0 |

Source exacte servie par Vite local sur 18461, sans build ni installation,
API fictive same-origin, aucune connexion Supabase réelle. Police système du
mode natif de recette, WebSockets fermés par le helper existant. L’indicateur
notifications dégradées reste attendu dans ce banc. Les captures Explorer des
cinq formats ont été relues ; les captures du détail et snapshots ARIA sont
également conservés. Les assertions exécutent ouverture/fermeture du dialogue,
vue Liste, détail complet, retour arrière et contrôle d’absence de candidature.
Le serveur local est arrêté après la recette.

Preuves :

- `/private/tmp/jolene-explorer-navigation-conditionnelle-5formats/results.json`
  SHA256 `b78c566153917a8a759393c6cac3152dfda02bbbe4752d6052e7e9c963873e1b` ;
- `/private/tmp/jolene-explorer-navigation-conditionnelle-validation.json`
  contient les cinq résultats et compteurs, sans données réelles ;
- `tsc -b` vert. Le contrôle TypeScript isolé spec/helper retourne TS2769
  sur le `page.on` à événements union du helper ligne 39, inchangé : même
  diagnostic reproduit sur les deux fichiers extraits de la base `a2157887`.
  Ce défaut de typage préexistant n’est pas corrigé dans ce lot ; les logs
  `...-e2e-types.txt` et `...-e2e-types-base.txt` sont conservés dans `/private/tmp` ;
- `git diff --check` vert ; relecture croisée indépendante du diff, helper,
  trace et empreinte des résultats : aucun finding, sans relance de tests.
  Ce contrôle ciblé n’est pas une revue B8 fraîche.

Il s’agit d’une simulation frontend locale, sans appareil physique ni backend
réel. Un succès ciblé ne démontre pas la stabilité de toute la matrice CI ni
l’explication profonde de l’incident WebKit original.
