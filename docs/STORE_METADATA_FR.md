# Métadonnées stores — fr-FR

Version préparée le 13/07/2026 pour `Jolene 1.0 (4)` iOS et `1.0 (2)` Android.
Ce document contient uniquement des éléments publiables. Les mots de passe des
comptes de review doivent être saisis directement dans les consoles et ne
doivent jamais être ajoutés au dépôt, à une PR ou à une capture.

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

### Notes App Review

Jolene est une plateforme professionnelle de staffing en santé avec trois
rôles. Les données visibles dans les comptes ci-dessous sont des données de
démonstration destinées à la review.

Comptes à renseigner dans les champs sécurisés App Store Connect :

- soignant : `marie.lefevre@jolene-demo.dev` ;
- établissement : `etab@jolene.app` ;
- administrateur complémentaire : `admin@jolene.app`.

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

- **Tracking** : non ; aucun domaine de tracking déclaré.
- **Coordonnées liées au compte, fonctionnalité de l'app** : nom, e-mail,
  téléphone, adresse physique.
- **Informations financières liées au compte, fonctionnalité de l'app** :
  informations de paiement et autres informations financières.
- **Localisation liée au compte, fonctionnalité de l'app** : localisation
  précise, uniquement sur action volontaire.
- **Contenu utilisateur lié au compte, fonctionnalité de l'app** : photos ou
  vidéos, messages, demandes au support et autres contenus/documents.
- **Historique de recherche lié au compte** : fonctionnalité et
  personnalisation du produit.
- **Identifiants liés au compte** : identifiant utilisateur et identifiant de
  l'appareil, pour la fonctionnalité.
- **Utilisation liée au compte** : interactions produit, pour fonctionnalité et
  analytics.
- **Diagnostics liés au compte** : crashs et performances, pour fonctionnalité
  et analytics.
- **Santé et activité physique** : aucune donnée collectée.

Cette liste doit rester alignée mot pour mot avec
`ios/App/App/PrivacyInfo.xcprivacy` et être revue après toute évolution de SDK
ou de fonctionnalité.

### Data safety Google Play

Réponses globales préparées :

- données collectées : **oui** ;
- données chiffrées en transit : **oui** ;
- mécanisme de suppression : **oui**, dans l'app et via
  `https://jolene.app/supprimer-mon-compte` ;
- publicité et tracking publicitaire : **non** ;
- données de santé : **non**.

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
