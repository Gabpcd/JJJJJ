# Adaptateur média Documents — préparation SDK57

Ce dossier est préparé hors de PR1091. Aucun paquet n’a été installé, aucun test ou
build n’a été lancé et aucune caméra, bibliothèque, requête métier ou URL réelle n’a
été ouverte. Les tests présents sont des doubles des ports natifs ; ils ne constituent
pas une preuve de fonctionnement iOS/Android.

## Intégration

Après intégration du lot Documents et de `ui/documents/adapters.ts`, ajouter les versions
SDK57 proposées par `expo/bundledNativeModules.json` :

```json
{
  "expo-document-picker": "~57.0.3",
  "expo-image-picker": "~57.0.20",
  "expo-file-system": "~57.0.7",
  "expo-web-browser": "~57.0.3"
}
```

`expo-crypto` est déjà utilisé par le pilote. Ajouter la configuration suivante au
moment de l’intégration native, sans lancer de livraison mobile implicitement :

```json
{
  "plugins": [["expo-image-picker", {
    "cameraPermission": "Jolene utilise l’appareil photo pour photographier le document que vous choisissez de transmettre.",
    "photosPermission": "Jolene utilise la photo que vous sélectionnez pour votre justificatif.",
    "microphonePermission": false
  }]]
}
```

Factory synchrone : `createExpoDocumentMediaAdapter({scope:{userId,epoch},isCurrent})`
(alias `createExpoDocumentMedia`) retourne le contrat
UI `pick/release/open` plus `prepare/dispose`. L’instance appartient au runtime du compte,
et ne doit jamais être partagée entre epochs. `isCurrent` doit lire la session actuelle,
pas une fermeture capturant le compte initial. Appeler `prepare()` à l’admission du compte,
gérer son erreur, puis `dispose()` au changement d’epoch/déconnexion. Le marquage de
disposition est synchrone avant le premier `await`. Le rejet éventuel du nettoyage doit
être signalé et repris ; ne pas le transformer en confirmation de purge.

Une annulation de formulaire libère son `DocumentSelection` par `release`. Ce dernier
refuse implicitement tout objet de sélection appartenant à une autre instance ; une URI
fournie arbitrairement par l’écran n’entraîne aucune suppression. L’UI conserve sa gestion
de demande/abort et ne déclenche jamais d’upload à la sélection ou à la reprise Android.
Le journal d’upload reste une dépendance séparée, liée à l’utilisateur.

## Ce que le code prépare

- Fichier : `DocumentPicker.getDocumentAsync` avec `copyToCacheDirectory:true`, un seul
  fichier, types PDF/JPEG/PNG/WebP. Lecture via `File.size` puis `File.arrayBuffer`, taille
  réellement lue et signature binaire revérifiées par le même utilitaire que le web.
- Caméra : autorisation demandée uniquement au geste caméra. Bibliothèque : sélecteur
  système, sans demande d’accès global à toutes les photos.
- ImagePicker : `base64:true`, JPEG réellement décodé et signature contrôlée, maximum
  10 Mio après décodage. L’URI peut être HEIC/AVIF ; aucun changement de suffixe sur ce
  fichier ne prétend le convertir. C’est une nouvelle copie JPEG produite depuis les
  octets JPEG exposés par Expo. Pas d’audio, vidéo, édition ou sélection multiple.
- Copies : dossier privé aléatoire sous cache, sans nom personnel ; création sans
  écrasement, octets contrôlés. Les URI fraîches des pickers sont enregistrées pour
  purge seulement si elles sont strictement dans le cache de l’app. Les originaux
  externes et `content://` ne sont jamais supprimés. Chaque copie suivie est purgée
  au relâchement/disposition ou après une réponse native tardive ; aucun dossier cache
  global ni contenu d’une autre instance n’est supprimé récursivement.
- Annulation/session : un résultat tardif ne devient pas un brouillon du nouveau compte.
  Un verrou partagé empêche d’empiler un nouveau sélecteur tant que l’ancien est ouvert.
  Aucune API d’envoi ou clé d’authentification n’existe dans cet adaptateur.
- Android `getPendingResultAsync` : consommé et écarté avant une première sélection.
  Sans liaison persistée fiable à la session d’origine, ce résultat ne peut ni devenir
  un brouillon ni provoquer un upload. Ses fichiers ne sont pas supprimés à l’aveugle.
- Consultation : dernier contrôle de l’origine STAGING, du bucket, du chemin du compte,
  du type PDF/image et de l’expiration (5 secondes de marge, 1 heure maximum), puis
  transfert de **l’URL exacte** à Safari View Controller ou Chrome Custom Tabs via
  `expo-web-browser`. Aucun JWT fourni au navigateur, aucune URL conservée/journalisée,
  aucun préchargement ni réécriture du lien. L’écran utilise « Ouvrir le document ».

## Limites explicites

1. Safari/Chrome est une vue système dédiée au document ; ce n’est ni un lecteur PDF
   interne ni une WebView affichant Jolene. Sur Android, `opened` prouve uniquement
   l’ouverture de la vue ; un PDF peut nécessiter un téléchargement ou une application
   du système. Il reste à observer un PDF et une image réels sur chaque système.
2. `dismissBrowser()` est disponible seulement sur iOS. L’abort/disposition le demande
   si cette instance possède la vue ouverte. Une présentation iOS encore en transition
   peut refuser cette fermeture ; la reprise est invalide côté application, sans
   garantie que l’OS ait fermé sa vue. Android ne fournit pas d’API de fermeture de
   Custom Tabs : le document déjà remis au navigateur peut rester affiché jusqu’à la
   fermeture par l’utilisateur. Ne pas annoncer une révocation immédiate d’un document
   déjà rendu/copié. Le lien temporaire garde les garanties du serveur.
3. Les sélecteurs OS n’offrent pas d’annulation programmée uniforme. Fermer/quitter le
   formulaire invalide le résultat et nettoie les copies à son retour, mais ne peut pas
   promettre de fermer instantanément une feuille caméra/bibliothèque encore à l’écran.
4. Un arrêt brutal du processus peut laisser des copies dans le cache géré par l’OS.
   Aucun balayage aveugle de ce cache n’est effectué au redémarrage. Les résultats Android
   récupérés sans provenance fiable sont écartés ; l’utilisateur sélectionne à nouveau.
5. Un ancien original dont le MIME est absent (`application/octet-stream`) n’est pas
   ouvert par cette politique. Le gateway conserve fidèlement la valeur serveur ; il
   faut traiter ce cas avant d’annoncer la consultation universelle des anciennes pièces.
6. Aucun document de santé supplémentaire, consentement, contrat, signature ou DPAE
   n’est ajouté ici. Les règles d’upload/identité restent celles du lot Documents.
7. Après intégration : typecheck, tests ciblés, revue indépendante, frontend sur iPhone,
   Android, iPad portrait/paysage, puis fichiers/permissions réels et reprise Android.
   Caméra et bibliothèque requièrent aussi une observation sur appareil physique.

## Tests préparés, non exécutés

`media.node.test.ts` couvre les limites binaires/JPEG, chemins de cache, compte et TTL du
lien, permissions au geste, annulation, purge des copies (y compris ImagePicker), session
remplacée, résultats Android écartés, verrou de présentation, absence de fuite d’URL dans
les erreurs et fermeture iOS demandée. Les SDK Expo sont remplacés par des ports fictifs.

Après intégration, depuis `mobile-native` :
`node --import tsx --test src/media/documents/media.node.test.ts`

## Sources primaires SDK57

- https://docs.expo.dev/versions/v57.0.0/sdk/document-picker/
- https://docs.expo.dev/versions/v57.0.0/sdk/imagepicker/
- https://docs.expo.dev/versions/v57.0.0/sdk/filesystem/
- https://docs.expo.dev/versions/v57.0.0/sdk/webbrowser/
- https://github.com/expo/expo/tree/sdk-57/packages/expo-file-system/src
- https://github.com/expo/expo/blob/sdk-57/packages/expo-web-browser/src/WebBrowser.types.ts
