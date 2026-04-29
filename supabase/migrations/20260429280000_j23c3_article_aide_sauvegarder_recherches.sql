-- J2.3.C.3 — Article centre d'aide : "Sauvegarder mes recherches et activer des alertes"
-- Article 25 (audience COMMUN, catégorie Missions). Cf. docs/module-filtres-alertes.md.

INSERT INTO public.articles_aide (slug, titre, contenu, audience, categorie, ordre_affichage, publie)
VALUES (
  'sauvegarder-recherches-alertes',
  'Sauvegarder mes recherches et activer des alertes',
$$Vous pouvez **sauvegarder vos critères de recherche** sur Jolene et recevoir des **alertes email automatiques** dès que de nouveaux résultats matchent vos critères.

## À quoi ça sert ?

- **Retrouver rapidement** vos recherches fréquentes (au lieu de re-saisir les filtres à chaque fois)
- **Être notifié dès qu'une nouvelle mission/un nouveau soignant correspond** à vos critères, sans avoir à revenir sur la plateforme

## Comment sauvegarder une recherche ?

### Côté soignant (recherche missions)

1. Allez sur **Recherche missions** (`/soignant/recherche-missions`).
2. Filtrez selon vos critères (profession, ville, taux horaire, urgence, etc.).
3. Cliquez sur **Sauvegarder cette recherche** en haut de la page.
4. Dans la modal : donnez un nom à votre recherche (ex. *"IDE Paris > 25 €/h"*), activez ou non les alertes, choisissez la fréquence.
5. Cliquez **Enregistrer**.

### Côté établissement (recherche soignants)

⚠️ La page de recherche soignants côté établissement arrive prochainement. Vous pouvez gérer/supprimer vos filtres existants dans **Paramètres → Mes recherches sauvegardées**, mais la création de nouveaux filtres pour cette audience est limitée pour l'instant.

## Fréquences d'alertes disponibles

| Fréquence | Latence max | Recommandé pour |
|-----------|-------------|-----------------|
| **Immédiat** | 1 heure (vérification horaire) | Missions urgentes, recherches très ciblées |
| **Quotidien** | 24 heures (1 email à 8 h Paris) | Recherches générales, profil régulier |
| **Hebdomadaire** | 7 jours (1 email par lundi) | Recherches passives, faible volume |

L'alerte n'envoie un email **que si de nouveaux résultats matchent** vos critères depuis le dernier check. S'il n'y a rien de nouveau, vous ne recevez pas d'email — pas de spam.

## Limite : 20 recherches par utilisateur

Vous pouvez sauvegarder **maximum 20 recherches** par compte. Au-delà, vous devrez en supprimer pour en créer de nouvelles. Cette limite évite la sur-sollicitation et garde votre liste lisible.

## Gérer vos recherches sauvegardées

Page dédiée :
- Soignant : `/soignant/parametres/recherches-sauvegardees`
- Établissement : `/etablissement/parametres/recherches-sauvegardees`

Vous y trouverez la liste de toutes vos recherches avec, pour chacune :
- Son nom, sa fréquence, le nombre de nouveaux résultats au dernier check
- Boutons **Activer/Désactiver alerte**, **Modifier**, **Supprimer**
- Bouton **Aller à la recherche** qui réapplique automatiquement les filtres dans la page de recherche correspondante

## Désactiver les alertes

Vous avez **3 niveaux** de désactivation :

1. **Pour une seule recherche** : décocher la cloche dans la liste, ou décocher l'alerte dans l'écran Modifier.
2. **Pour toutes les alertes filtres email** : Paramètres → Notifications → décocher *Nouvelles missions matchant un filtre* / *Nouveaux soignants matchant un filtre* dans la colonne Email.
3. **Pour tous les emails non-urgents** : Paramètres → Notifications → désactiver le canal Email globalement.

Note : les emails d'urgence (mission ASSIGNEE, litige escaladé, paiement échec, etc.) ne sont **jamais désactivables** — ce sont des notifications transactionnelles obligatoires.

## Cohérence avec vos préférences notifications

Les alertes filtres respectent toujours vos préférences notifications globales (J2.3.A). Si vous désactivez le type d'événement *Nouvelle mission matchant un filtre* (canal Email) dans Paramètres → Notifications, **aucune alerte filtre ne vous sera envoyée par email**, même si vous avez activé l'alerte sur le filtre.

## Article lié

[Pourquoi je reçois des emails de bienvenue](/aide/pourquoi-je-recois-emails-bienvenue)
[Je n'ai pas reçu d'email de Jolene](/aide/je-n-ai-pas-recu-d-email)
$$,
  'COMMUN',
  'Missions',
  130,
  true
)
ON CONFLICT (slug) DO UPDATE SET
  contenu = EXCLUDED.contenu,
  titre = EXCLUDED.titre,
  audience = EXCLUDED.audience,
  categorie = EXCLUDED.categorie,
  publie = true,
  mis_a_jour_le = now();
