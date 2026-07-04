-- J2.3.B.2.2 — Article centre d'aide : "Pourquoi je reçois des emails de bienvenue ?"
-- Explique la série J0/J1/J3/J7 + comment la désactiver via les préférences
-- notifications. 23e article du centre d'aide.

INSERT INTO public.articles_aide (slug, titre, contenu, audience, categorie, ordre_affichage, publie)
VALUES (
  'pourquoi-je-recois-emails-bienvenue',
  'Pourquoi je reçois des emails de bienvenue ?',
$$Lorsque vous créez votre compte sur Jolene, nous vous envoyons une série de **4 emails sur 7 jours** pour vous accompagner dans vos premiers pas.

## Quels emails vais-je recevoir ?

| Délai | Contenu |
|-------|---------|
| **Immédiat (J0)** | Bienvenue + premiers pas (compléter votre profil, parcourir la plateforme) |
| **+ 1 jour (J1)** | Rappel des étapes restantes pour finaliser votre profil ou votre onboarding |
| **+ 3 jours (J3)** | Conseils pour postuler à votre première mission (soignants) ou publier votre première mission (établissements) |
| **+ 7 jours (J7)** | Récap de vos progrès et opportunités à saisir |

## Ces emails sont contextuels

Si vous avez déjà accompli l'action attendue, l'email correspondant **n'est pas envoyé** (par ex. si vous avez complété votre profil avant J+1, l'email J1 est sauté). Pas de spam : on n'envoie que ce qui vous est utile.

## Comment les désactiver ?

Vous pouvez désactiver toute la série d'emails de bienvenue à tout moment :

**Soignants** : rendez-vous dans **Paramètres → Notifications** (`/soignant/parametres/notifications`).

**Établissements** : rendez-vous dans **Paramètres → Notifications** (`/etablissement/parametres/notifications`).

Dans le tableau **Préférences par événement**, trouvez la ligne **« Bienvenue / Onboarding »** et décochez la colonne **Email**. Vous pouvez aussi désactiver le canal Email globalement (en haut de la page) pour couper tous les emails non-urgents en une fois.

## Important : les notifications d'urgence ne sont pas désactivables

Pour des raisons de sécurité (annulation tardive, mission urgente, alerte de conformité), les emails et SMS d'urgence sont **toujours envoyés**, indépendamment de vos préférences.

## En savoir plus

- [Gérer mes préférences de notifications](/aide/article/preferences-notifications)
- [Inscription et profil](/aide?categorie=Inscription+et+profil)
$$,
  'COMMUN',
  'Inscription et profil',
  110,
  true
)
ON CONFLICT (slug) DO NOTHING;
