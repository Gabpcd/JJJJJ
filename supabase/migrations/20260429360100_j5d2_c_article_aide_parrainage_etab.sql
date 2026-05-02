-- J5.D.2.C — Article 27 : parrainage-etablissement (audience ETABLISSEMENT)

INSERT INTO public.articles_aide (slug, titre, contenu, audience, categorie, ordre_affichage, publie)
VALUES (
  'parrainage-etablissement',
  'Parrainez un autre établissement et gagnez 100€ de crédit',
$$En tant qu'établissement, vous pouvez recommander Jolene à un confrère et **gagner 100€ de crédit Jolene** par établissement filleul validé, déduit de votre prochaine facture commission.

## Comment ça marche

1. Allez dans **Parrainage** dans votre menu (ou directement `/etablissement/parrainage`)
2. Récupérez votre **code unique format `ETB-XXXXXX`** (généré automatiquement à votre inscription)
3. Partagez votre code ou votre lien `https://jolene.app?ref=ETB-VOTRECODE` avec un confrère établissement
4. Le filleul s'inscrit, signe son contrat de service Jolene, applique votre code dans sa page parrainage
5. Dès que le filleul publie sa **1ère mission qui passe à `ASSIGNEE` ou `TERMINEE`**, le parrainage est **validé**
6. Vous recevez automatiquement **100€ de crédit** ajouté à votre compte (notification in-app)
7. Le crédit est déduit de votre **prochaine facture commission Jolene** (admin l'applique manuellement pour l'instant ; intégration auto generate-invoice prévue prochaine itération)

## Conditions de validation

Pour que le parrainage soit validé :

- **Filleul a signé son contrat de service** Jolene (`contrat_valide = true`)
- **Filleul a au moins 1 mission `ASSIGNEE` ou `TERMINEE`** (preuve d'utilisation réelle de la plateforme)
- **Filleul n'a pas déjà été parrainé** (anti-doublon SIRET)
- **Vous n'avez pas atteint le cap** de 10 parrainages validés

## Limites & règles

- **Cap de 10 parrainages validés par établissement parrain.** Au-delà, les nouvelles applications de votre code ne déclenchent plus de crédit (mais sont quand même tracées).
- **Anti-abus SIRET** : un même SIRET filleul ne peut bénéficier que d'un seul parrainage validé. Si vous parrainez plusieurs entités du même SIRET, seul le premier compte.
- **Anti-fraude** : si vous validez plus de 5 parrainages dans le même mois, un audit automatique est déclenché pour revue admin (`PARRAINAGE_ETAB_ANOMALIE`).
- **Pas d'auto-parrainage** : vous ne pouvez pas appliquer votre propre code.
- **Application unique** : une fois un code parrainage appliqué, vous ne pouvez plus en changer.

## Badge Super Ambassadeur

À partir de **5 parrainages validés**, vous obtenez le badge **🏆 Super Ambassadeur** visible sur votre page parrainage. C'est un badge cosmétique de reconnaissance, sans avantage supplémentaire.

## Tableau de bord parrainage

Sur votre page parrainage, vous voyez :
- Votre **code unique** + lien partage avec QR code
- Boutons **partage** : LinkedIn, Email, WhatsApp
- **Compteurs** : filleuls inscrits, parrainages validés (X/10), crédits disponibles en €
- **Liste des filleuls** : nom, ville, statut (En attente / Validé / Expiré), crédit gagné
- **Liste des crédits** : montant, date, statut (À appliquer / Appliqué le DATE)

## Application des crédits sur facture

Pour le moment, les crédits sont **enregistrés automatiquement** dès la validation du parrainage et **stockés en attente d'application**. Lors de votre prochaine facture commission Jolene, l'administration applique manuellement le crédit (déduction sur le `montant_ht` et `montant_ttc`).

L'**intégration automatique dans `generate-invoice`** est prévue dans une prochaine itération. Vos crédits ne sont jamais perdus : ils restent valables sans limite de temps tant qu'ils ne sont pas appliqués.

## Articles liés

[Comment publier votre première mission](/aide/etab-publier-premiere-mission)
[Comprendre la commission Jolene](/aide/etab-comprendre-commission-jolene)
$$,
  'ETABLISSEMENT',
  'Inscription et profil',
  150,
  true
)
ON CONFLICT (slug) DO UPDATE SET
  contenu = EXCLUDED.contenu,
  titre = EXCLUDED.titre,
  audience = EXCLUDED.audience,
  categorie = EXCLUDED.categorie,
  publie = true,
  mis_a_jour_le = now();
