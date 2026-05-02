-- J5.D.1 — Article 26 : parrainage-soignant (audience SOIGNANT, catégorie Inscription et profil)

INSERT INTO public.articles_aide (slug, titre, contenu, audience, categorie, ordre_affichage, publie)
VALUES (
  'parrainage-soignant',
  'Parrainage : invitez vos collègues, gagnez des avantages',
$$Vous pouvez inviter vos collègues soignants à rejoindre Jolene avec votre **code parrainage personnel**. Chaque parrainage validé vous rapporte des avantages concrets sur la plateforme.

## Avantages immédiats à l'inscription du filleul

Dès que votre filleul **applique votre code à l'inscription** :

- **+50 heures cumulées sur votre compteur** (utile pour le seuil 3 200 h installation libérale)
- **+50 heures cumulées sur le compteur de votre filleul** également (gagnant-gagnant)

Le bonus est appliqué automatiquement au moment où votre filleul saisit votre code dans son profil.

## Badge Ambassadeur (3 filleuls validés)

Quand **3 de vos filleuls ont terminé leur 1ère mission** sur Jolene, vous débloquez automatiquement le **badge Ambassadeur** sur votre profil. Le badge :

- Est visible côté établissements dans l'annuaire et la recherche soignants
- Apparaît dans vos cartes profil et candidatures comme un signal de confiance
- Reste actif définitivement (pas de période d'expiration)

Vous recevez une notification in-app et email dès le déblocage.

## Comment partager votre code

Page **Parrainage** dans votre menu :
- Code unique format `JO-XXXXXX` (auto-généré à votre inscription)
- Lien direct `https://jolene.app?ref=VOTRE_CODE` pré-rempli pour le filleul
- QR code pour partage en personne
- Boutons partage rapide : WhatsApp, SMS, Email, LinkedIn

Le filleul qui clique sur votre lien arrive sur la page d'accueil avec le code déjà capturé en session — il sera **pré-rempli automatiquement** dans le champ « Code parrainage » du wizard de complétion de profil.

## Comment savoir si mon filleul a validé ?

Sur la page Parrainage, votre tableau **Mes filleuls** affiche pour chacun :
- Son prénom et la date de son inscription
- Son statut : *Inscrit* (compte créé) ou *1ère mission faite* (validé)

Le compteur en haut affiche :
- **Filleuls inscrits** : tous ceux qui ont appliqué votre code
- **Missions terminées** : filleuls comptés comme validés pour le badge

## Limites & règles

- **Pas de récompense financière directe** : le parrainage Jolene est un système de recommandation conforme à la réglementation (pas de versement d'argent au parrain).
- **Pas d'auto-parrainage** : vous ne pouvez pas appliquer votre propre code.
- **Code unique par soignant** : chaque parrainage doit être un soignant différent.
- **Application possible une seule fois** : un filleul ne peut pas changer de parrain une fois son code appliqué.

## Que se passe-t-il si je ne saisis pas le code à l'inscription ?

Vous pouvez le saisir plus tard dans votre **profil → onglet Parrainage**, tant que vous n'avez **pas encore terminé une mission**. Une fois la 1ère mission terminée, le code n'est plus modifiable (pour éviter la fraude rétroactive).

## Articles liés

[Comment vérifier mon RPPS](/aide/comment-verifier-mon-rpps)
[Inscription soignant (libéral / salarié / mixte)](/aide/inscription-soignant-liberal-salarie-mixte)
$$,
  'SOIGNANT',
  'Inscription et profil',
  140,
  true
)
ON CONFLICT (slug) DO UPDATE SET
  contenu = EXCLUDED.contenu,
  titre = EXCLUDED.titre,
  audience = EXCLUDED.audience,
  categorie = EXCLUDED.categorie,
  publie = true,
  mis_a_jour_le = now();
