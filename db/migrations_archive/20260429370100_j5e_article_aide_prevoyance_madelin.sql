-- J5.E — Article 28 : prevoyance-madelin (audience SOIGNANT, catégorie Inscription et profil)

INSERT INTO public.articles_aide (slug, titre, contenu, audience, categorie, ordre_affichage, publie)
VALUES (
  'prevoyance-madelin',
  'Prévoyance Madelin : à quoi ça sert et où en est le programme Jolene',
$$La **prévoyance Madelin** est une assurance dédiée aux travailleurs indépendants qui couvre les **arrêts de travail, l'invalidité et le décès**. C'est l'équivalent libéral de la prévoyance des salariés. Voici l'essentiel pour comprendre — et où en est le programme Jolene.

## Pourquoi souscrire une prévoyance ?

En tant que soignant libéral, vous êtes votre propre garantie : si vous tombez malade ou êtes accidenté, **vos revenus s'arrêtent**. La sécurité sociale verse des indemnités journalières (IJSS) limitées (≈ 25-50 €/jour selon votre statut), bien inférieures à votre revenu réel.

La prévoyance Madelin **complète ces IJSS** pour vous garantir un revenu de remplacement à hauteur de 30 à 80 % de votre revenu mensuel, pendant toute la durée de l'arrêt.

## Avantage fiscal Madelin

Les cotisations Madelin sont **déductibles du revenu imposable BNC** dans la limite d'un plafond annuel :

- **Plafond 2026** : ≈ 3,75 % du PASS + 7 % de votre revenu (capé à 8 % du PASS)
- **Concrètement** : si vous payez 100 €/mois de prévoyance, l'État rembourse une partie via réduction d'impôts (≈ 30-45 % selon votre tranche marginale)

## 3 niveaux types de couverture

Le marché propose généralement 3 niveaux :

| Niveau | Taux remplacement | Pour qui ? |
|--------|------------------|------------|
| **Bronze** | 30 % | Couverture de base, démarrage |
| **Argent** | 50 % | Couverture intermédiaire (recommandée) |
| **Or** | 80 % | Hauts revenus, foyer dépendant de votre revenu |

⚠️ Ces niveaux sont **indicatifs**. Les contrats finaux pourront proposer des paliers différents (35/55/75 % par exemple) selon le partenaire retenu.

## Calculateur intégré

La page **Prévoyance** (`/soignant/prevoyance`) propose un **calculateur revenu remplacé** :
- Vous saisissez votre revenu mensuel net libéral
- Vous choisissez un niveau Bronze/Argent/Or
- Vous voyez immédiatement la perte de revenu mensuelle, la couverture estimée, et le reste à votre charge

Utile pour estimer votre besoin avant le lancement officiel.

## Où en est le programme Jolene ?

🚧 **Bientôt disponible.** Nous sommes en cours de finalisation d'un **partenariat avec un assureur santé spécialisé indépendants**. L'objectif :

- Offrir des contrats Madelin **négociés au tarif groupe Jolene** (potentiellement -10 à -20 % vs marché)
- Souscription **100 % en ligne** depuis votre espace
- Subvention Jolene partielle en bonus pour les premiers inscrits
- **Bonus +3 points fiabilité** une fois la couverture active

## Liste d'attente

Vous pouvez vous inscrire dès maintenant à la **liste d'attente** depuis la page Prévoyance. Indiquez votre email + niveau préféré (ou Indifférent), et vous serez prévenu·e en avant-première dès le lancement.

L'inscription à la liste d'attente est :
- **Gratuite** : aucune cotisation prélevée
- **Sans engagement** : vous pouvez vous désinscrire à tout moment
- **Confidentielle** : votre email n'est utilisé que pour le lancement, jamais cédé

## Articles liés

[Comprendre votre score de fiabilité](/aide/mes-droits-rgpd-soignant)
[Inscription soignant (libéral / salarié / mixte)](/aide/inscription-soignant-liberal-salarie-mixte)
$$,
  'SOIGNANT',
  'Inscription et profil',
  160,
  true
)
ON CONFLICT (slug) DO UPDATE SET
  contenu = EXCLUDED.contenu,
  titre = EXCLUDED.titre,
  audience = EXCLUDED.audience,
  categorie = EXCLUDED.categorie,
  publie = true,
  mis_a_jour_le = now();
