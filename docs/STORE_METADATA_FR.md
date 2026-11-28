# Métadonnées stores — fr-FR

Version préparée pour le candidat de soumission `Jolene 1.0`. Les numéros de
build iOS et `versionCode` Android sont volontairement gérés au moment de la
reconstruction finale afin que ce document ne devienne pas obsolète. Il
contient uniquement des éléments publiables. Les mots de passe des
comptes de review doivent être saisis directement dans les consoles et ne
doivent jamais être ajoutés au dépôt, à une PR ou à une capture.

> **Note du 28/11/2026.** Sur l'App Store, Jolene est désormais l'app Swift
> native 2.0.0 (32) (`ios-native/`), en vente depuis le 27/11/2026 en
> publication progressive (`docs/mobile-swift/APP_STORE.md`, « État au
> 28/11/2026 »). Sur Google Play, c'est toujours la coquille Capacitor,
> en 1.0.8 (25). À la création de la version 2.0.0 par l'API, Apple a repris
> la fiche de 1.0.7 : la description en ligne est celle ci-dessous, écrite
> pour l'app web embarquée. Les écarts avec l'app native sont signalés plus
> bas, pour la prochaine mise à jour de la fiche ; rien n'a été changé chez
> Apple.

## Positionnement

- **Nom** : `Jolene`
- **Catégorie principale conseillée** : Économie et entreprise / Business
- **Catégorie secondaire conseillée sur iOS** : Médecine / Medical
- **Public** : professionnels soignants et équipes des établissements de santé
- **Avertissement fonctionnel** : service professionnel de mise en relation ;
  aucun diagnostic, conseil ou soin médical destiné aux patients

## App Store — fr-FR

| Champ | Valeur |
|---|---|
| Nom (30 caractères max.) | `Jolene` |
| Sous-titre (30 caractères max.) | `Missions santé simplifiées` |
| Texte promotionnel (170 caractères max.) | `Trouvez ou publiez une mission, signez le contrat, pointez et suivez le paiement depuis une seule application sécurisée.` |
| Mots-clés (100 octets max.) | `mission,santé,soignant,remplacement,vacation,EHPAD,clinique,hôpital,emploi,contrat` |
| URL marketing | `https://jolene.app` |
| URL support | `https://jolene.app/contact` |
| URL de confidentialité | `https://jolene.app/confidentialite` |
| Copyright | `2026 Jolene SASU` |

### Description App Store

Jolene simplifie les missions de remplacement dans les établissements de
santé, de la mise en relation au paiement.

POUR LES SOIGNANTS

• Découvrez les missions compatibles avec votre profession et vos préférences.

• Postulez simplement et suivez chaque candidature.

• Centralisez vos documents administratifs et vos contrats.

• Signez, pointez par QR code ou GPS et suivez vos revenus.

POUR LES ÉTABLISSEMENTS

• Publiez une mission et recevez des candidatures qualifiées.

• Gérez contrats, signatures, pointages et validations depuis un même espace.

• Suivez la facturation, les paiements et l'activité de votre équipe.

POUR TOUS

• Messagerie, notifications et historique centralisés.

• Données chiffrées en transit, contrôle des notifications et suppression du
compte depuis l'application.

Les modes d'exercice proposés varient selon la profession requise par la
mission et le type d'établissement. Jolene est un service professionnel de
mise en relation. L'application ne fournit ni diagnostic, ni conseil, ni soin
médical aux patients.

> **Écart relevé le 28/11/2026, à corriger à la prochaine mise à jour de la
> fiche App Store** (texte publié non modifié ici). Dans l'app iOS native
> 2.0.0, la facturation, le prélèvement SEPA, l'équipe et le pilotage de
> l'établissement ne sont pas des écrans natifs : l'onglet Compte les ouvre sur
> le site jolene.app (`ios-native/Packages/JoleneCore/Sources/JoleneCore/Etablissement/Compte/RenvoisWebEtab.swift`).
> Il en va de même pour la modification, la duplication ou l'annulation d'une
> mission et pour certains types de contrat (`config/ios-review-notes-2.0-soignant.txt`).
> La puce « Suivez la facturation, les paiements et l'activité de votre
> équipe » décrit donc le site, pas l'app iOS ; le « depuis un même espace » de
> la puce précédente n'y vaut que pour ce qui est natif, certains types de
> contrat ouvrant le site. Côté établissement, « suppression du compte depuis
> l'application » ouvre aussi la page de suppression du site (connexion
> redemandée). Sont natifs côté établissement : tableau de bord, missions,
> candidatures, présences et pointage, contrats, messagerie. Ces écarts ne
> concernent pas Google Play, dont l'app embarque le site.

### Notes App Review

**App iOS native 2.0 (mise à jour du 28/11/2026).** Le texte remis au
relecteur Apple est en anglais et versionné en deux variantes,
`config/ios-review-notes-2.0-soignant.txt` et
`config/ios-review-notes-2.0-etablissement.txt`. La lane de soumission place
en tête du champ « Notes » celle du rôle vérifié du compte de démonstration,
devant les notes de la version précédente (`docs/mobile-swift/APP_STORE.md`,
« Notes pour la revue et compte de démonstration »). Le 27/11/2026, c'est la
variante soignant qui a été écrite. Modifier ces fichiers par une PR, pas ce
document.

Ce que ces notes décrivent (libellés vérifiés dans `ios-native/` le 26/11/2026,
`docs/mobile-swift/APP_STORE.md` ; rôles et renvois relus le 28/11/2026) :

- l'app native ne sert que deux rôles : soignant (`SOIGNANT`) et établissement
  (`ADMIN_ETABLISSEMENT`), seuls rôles admis pour le compte de démonstration
  (`fastlane/ios_review_demo_account.rb`, `ROLES`). Les comptes administrateur
  et groupe sont renvoyés vers le site jolene.app ; le bloc 2.0 ne propose aucun
  compte administrateur (les notes de 1.0.7, gardées sous le séparateur, peuvent
  encore en citer un) ;
- deux comptes de revue, soignant et établissement, aux données fictives : l'un
  dans les champs « Sign-in required », l'autre dans les notes de la version
  précédente. Aucun mot de passe dans ce document ni dans le dépôt (public) ; la
  lane ne lit les identifiants de la fiche qu'en mémoire et n'en journalise
  aucun ;
- côté établissement, sont natifs le tableau de bord, les missions, les
  candidatures, les présences et le pointage, les contrats et la messagerie ;
  la facturation et d'autres actions de gestion ouvrent le site jolene.app,
  sans achat ;
- le pointage demande la position (au premier plan seulement) et un code
  affiché sur place par l'établissement ; la caméra ne sert qu'à photographier
  un document ou à scanner un code ;
- paiement, signature par SMS et Pro Santé Connect ne doivent pas être menés à
  leur terme par la revue.

**Coquille Capacitor (Google Play ; App Store jusqu'à 1.0.7).** Texte écrit
pour l'app web embarquée, qui sert trois rôles. Les mots de passe se saisissent
dans les champs sécurisés des consoles, jamais dans le dépôt.

Jolene est une plateforme professionnelle de staffing en santé avec trois
rôles. Les données visibles dans les comptes de revue sont des données de
démonstration destinées à la review.

Comptes à renseigner dans les champs sécurisés de la console :

- soignant : `marie.lefevre@jolene-demo.dev` ;
- établissement : `etab@jolene.app` ;
- administrateur complémentaire : un compte de démonstration administrateur
  (adresse retirée de ce document le 28/11/2026).

Les deux premières adresses restent citées ici parce que la migration
`supabase/migrations/20261126100100_missions_revue_store.sql` désigne les
comptes de revue par elles, et que la garde
`tests/node/revue-store-missions.node.mjs` exige qu'elles soient déjà publiques
dans ce document. Les retirer suppose une PR qui modifie cette garde.

Parcours conseillé :

1. se connecter avec le compte soignant, consulter les missions et ouvrir une
   fiche mission ;
2. vérifier candidatures, contrats, revenus et paramètres de confidentialité ;
3. se connecter avec le compte établissement, consulter le tableau de bord,
   les missions, les candidatures et la facturation ;
4. utiliser le compte administrateur uniquement si la review souhaite examiner
   les contrôles de conformité et de modération.

La caméra n'est demandée qu'au lancement volontaire du scanner QR. La
localisation précise n'est demandée que lors d'un pointage ou d'une action
explicite « me localiser ». Aucun suivi en arrière-plan n'est effectué.

Certaines actions externes (paiement réel, signature tierce, Pro Santé Connect)
ne doivent pas être finalisées par le reviewer ; les écrans et données de démo
permettent d'en vérifier le parcours sans transaction réelle.

## Google Play — fr-FR

| Champ | Valeur |
|---|---|
| Nom de l'application (30 caractères max.) | `Jolene` |
| Description courte (80 caractères max.) | `Les missions santé, du matching au paiement, dans une seule application.` |
| E-mail support | `support@jolene.app` |
| Site web | `https://jolene.app` |
| Politique de confidentialité | `https://jolene.app/confidentialite` |
| Suppression de compte | `https://jolene.app/supprimer-mon-compte` |

La description complète Google Play reprend la **Description App Store**
ci-dessus. Elle reste largement sous la limite de 4 000 caractères et ne
contient ni classement, ni promotion de prix, ni témoignage invérifiable.

## Déclarations de confidentialité

### App Privacy Apple

Source : `ios-native/Jolene/PrivacyInfo.xcprivacy`, manifeste de l'app Swift
native, celle de la version 2.0.0 soumise le 27/11/2026. Relu le 28/11/2026 :
22 types de données collectées, tous liés à l'utilisateur, aucun utilisé pour
le pistage. Il est à cette date identique, octet pour octet, à
`ios/App/App/PrivacyInfo.xcprivacy` (coquille Capacitor gelée à 1.0.7, plus
livrée sur iOS). Les réponses « Confidentialité de l'app » saisies dans App
Store Connect n'ont pas été relues (`docs/mobile-swift/LOT6_PLAN.md` §3,
action 4) ; rien n'a été modifié chez Apple.

- **Tracking** : non (`NSPrivacyTracking` faux) ; aucun domaine de tracking
  déclaré.
- **Coordonnées liées au compte, fonctionnalité de l'app** : nom, e-mail,
  téléphone, adresse physique.
- **Santé liée au compte, fonctionnalité de l'app** : déclaration du Soignant
  relative à ses vaccinations obligatoires et à sa visite de médecine du
  travail, avec date de signature. Donnée liée au compte, utilisée uniquement
  pour la fonctionnalité de conformité professionnelle. Aucun carnet de
  vaccination, certificat médical, diagnostic ni donnée de patient n'est
  demandé ou stocké.
- **Informations financières liées au compte, fonctionnalité de l'app** :
  informations de paiement et autres informations financières.
- **Localisation liée au compte, fonctionnalité de l'app** : localisation
  précise et localisation approximative.
- **Contenu utilisateur lié au compte, fonctionnalité de l'app** : photos ou
  vidéos, e-mails ou messages texte, demandes au service client, autres
  contenus de l'utilisateur.
- **Historique de recherche lié au compte** : fonctionnalité et
  personnalisation du produit.
- **Identifiants liés au compte, fonctionnalité de l'app** : identifiant
  utilisateur et identifiant de l'appareil.
- **Achats liés au compte, fonctionnalité de l'app** : historique d'achats.
- **Utilisation liée au compte** : interactions avec le produit, pour
  fonctionnalité et analytics.
- **Diagnostics liés au compte** : données de plantage, pour la fonctionnalité ;
  données de performances et autres données de diagnostic, pour fonctionnalité
  et analytics.
- **Autres données liées au compte, fonctionnalité de l'app** : autres types de
  données.
- **Activité physique** : aucune donnée collectée.

Le même manifeste déclare quatre catégories d'API à raison requise :
`UserDefaults` (`CA92.1`), horodatage des fichiers (`C617.1`), temps depuis le
démarrage (`35F9.1`) et espace disque (`E174.1`).

Cette liste suit `ios-native/Jolene/PrivacyInfo.xcprivacy` et doit être revue
après toute évolution de SDK ou de fonctionnalité de l'app native.

### Data safety Google Play

Réponses globales préparées :

- données collectées : **oui** ;
- données chiffrées en transit : **oui** ;
- mécanisme de suppression : **oui**, dans l'app et via
  `https://jolene.app/supprimer-mon-compte` ;
- publicité et tracking publicitaire : **non** ;
- données de santé : **oui** — `Health info`, liée au compte, collectée pour la
  fonctionnalité de l'application et la conformité professionnelle. Elle est
  facultative au niveau de l'application (elle ne concerne que le parcours
  Soignant), n'est ni vendue ni utilisée pour la publicité. Jolene conserve
  uniquement les deux déclarations sur l'honneur et leur date de signature,
  jamais un document médical, un diagnostic ou une donnée de patient.

Types à déclarer au minimum :

- informations personnelles : nom, e-mail, identifiant utilisateur, adresse,
  téléphone ;
- informations financières : paiement et autres informations financières ;
- localisation précise ;
- photos et vidéos ;
- fichiers et documents ;
- messages dans l'application et autres contenus utilisateur ;
- activité dans l'application : interactions et historique de recherche ;
- performances : journaux de plantage et diagnostics ;
- identifiants de l'appareil ou autres identifiants.

Pour chaque type, distinguer requis et facultatif selon le rôle. La réponse
« données partagées » doit être validée dans Play Console au regard des contrats
avec les prestataires (notamment Supabase, Stripe, Sentry, Yousign et les
services de vérification) : ne pas répondre « non » par simple déduction
technique.

## Captures et visuels à produire

Jeu éditorial conseillé, sans données personnelles réelles :

1. tableau de bord soignant — « Des missions qui vous correspondent » ;
2. fiche mission et candidature — « Postulez en quelques instants » ;
3. contrat et signature — « Un parcours administratif centralisé » ;
4. pointage QR/GPS — « Un suivi clair de chaque mission » ;
5. tableau de bord établissement — « Publiez et suivez vos besoins » ;
6. candidatures et planning — « Votre équipe, au même endroit » ;
7. facturation et paiements — « Une visibilité de bout en bout ».

Pour l'app iOS native, la scène 7 n'a pas d'écran natif côté établissement
(renvoi vers jolene.app, note du 28/11/2026 ci-dessus) : la remplacer dans le
jeu iOS. Les captures de l'app native restent à produire
(`docs/mobile-swift/LOT6_PLAN.md`, tranche T5).

Apple accepte de une à dix captures. Produire au minimum le jeu iPhone 6,9
pouces en portrait et, puisque le binaire prend en charge l'iPad, le jeu iPad
13 pouces. Google Play réutilise les mêmes scènes, complétées par une feature
graphic dédiée. Ne pas ajouter de cadre d'appareil dans les captures brutes
destinées aux consoles tant que leurs dimensions n'ont pas été validées.

## Points à ne pas publier

- mots de passe des comptes de review ;
- clés APNs, Firebase, Supabase, Stripe ou Yousign ;
- QR code de pointage actif ou lien de signature réel ;
- identité, coordonnées, documents ou montants d'un utilisateur réel ;
- promesse « toutes professions en libéral » : les règles dépendent de la
  profession requise par la mission et de l'établissement.

## Références officielles

- Apple — [App information](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information/)
- Apple — [Platform version information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/)
- Apple — [Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)
- Google Play — [Créer et configurer une application](https://support.google.com/googleplay/android-developer/answer/9859152?hl=fr)
- Google Play — [Data safety](https://support.google.com/googleplay/android-developer/answer/10787469?hl=fr)
- Google Play — [Suppression de compte](https://support.google.com/googleplay/android-developer/answer/13327111?hl=fr)
