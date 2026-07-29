-- J2.2.A — 5 articles seed pour le centre d'aide
-- Les 17 autres articles seront ajoutés en J2.2.B

INSERT INTO public.articles_aide (slug, titre, audience, categorie, ordre_affichage, contenu) VALUES

('inscription-soignant-liberal-salarie-mixte', 'Choisir son type d''exercice : libéral, salarié ou mixte', 'SOIGNANT', 'Inscription et profil', 10,
'## Trois types d''exercice possibles

Lors de votre inscription, vous choisissez votre type d''exercice principal :

- **LIBÉRAL** : vous facturez en honoraires, Jolene émet vos factures en votre nom (mandat de facturation art. 289 I-2 CGI). Vous êtes responsable de vos cotisations URSSAF.
- **SALARIÉ** : vous travaillez en CDDU pour l''établissement client. L''établissement est employeur, Jolene génère le bulletin de paie en son nom.
- **MIXTE** : vous pouvez accepter les deux types de missions selon votre disponibilité.

## Comment changer

Vous pouvez modifier votre type d''exercice à tout moment dans **Profil → Modifier**. Si vous passez en libéral, vous serez invité à signer le mandat de facturation.

## Liens utiles

- [Comment signer mon mandat de facturation](/aide/signer-mandat-facturation)
- [Comprendre ma facture d''honoraires](/aide/comprendre-facture-honoraires)'),

('signer-mandat-facturation', 'Comment signer mon mandat de facturation', 'SOIGNANT', 'Mandat de facturation', 20,
'## Pourquoi un mandat de facturation

Le mandat de facturation est un document légal (art. 289 I-2 CGI) qui autorise Jolene à émettre des factures **en votre nom et pour votre compte** auprès des établissements clients. Il est obligatoire pour les soignants en exercice **LIBÉRAL** ou **MIXTE**.

## Comment signer

1. Connectez-vous à votre compte
2. Allez sur **Profil → Mandat de facturation** (`/soignant/mandat-facturation`)
3. Lisez le contrat dans son intégralité (scroll obligatoire)
4. Cochez les cases d''acceptation
5. Signez avec votre tracé manuscrit
6. Cliquez sur **Signer le mandat**

## Que dit le mandat

Le mandat précise notamment :

- Vous restez le **vendeur légal** de la prestation. Jolene est juste l''émetteur technique de la facture.
- La fréquence de facturation : facture finale unique pour les missions ≤ 7 jours, factures hebdomadaires pour les missions > 7 jours.
- Jolene reverse les sommes encaissées sur votre compte bancaire, déduction faite de la commission convenue.
- Vous pouvez révoquer le mandat à tout moment (les factures déjà émises restent valides).

## Mandat v1.2

La version actuelle est **v1.2** (29 avril 2026). Si vous avez signé une version antérieure, un bandeau vous invitera à re-signer la nouvelle version.'),

('etab-contrat-service-jolene', 'Signer le contrat de service Jolene', 'ETABLISSEMENT', 'Inscription et profil', 10,
'## Pourquoi signer le contrat

Le contrat de service Jolene formalise la relation commerciale entre votre établissement et Jolene SAS. Il définit :

- L''objet : mise à disposition de la plateforme jolene.app pour publier des missions
- La nature de la relation : Jolene est intermédiaire technique, **vous restez seul employeur** pour les missions salariées
- La commission Jolene
- Les obligations de chaque partie
- Les conditions de résiliation

## Comment signer

1. Connectez-vous à votre compte étab
2. Allez sur **Finaliser mon inscription** (`/etablissement/finaliser-inscription`)
3. Étape 1 : lisez le contrat en intégralité, cochez les 2 cases (acceptation + habilitation), signez
4. Étape 2 : uploadez votre RIB

Tant que ces 2 étapes ne sont pas complétées, vous ne pouvez pas publier de missions.

## Liens utiles

- [Pourquoi déposer mon RIB](/aide/etab-deposer-rib)
- [Pourquoi je dois uploader le contrat de travail SALARIE](/aide/etab-contrat-travail-salarie)'),

('mes-droits-rgpd', 'Mes droits RGPD sur Jolene', 'COMMUN', 'RGPD et données personnelles', 10,
'## Vos droits

Le RGPD vous garantit plusieurs droits sur vos données personnelles :

- **Droit d''accès (art. 15)** : obtenir une copie de toutes vos données. Bouton **Télécharger mes données** dans **Profil → Confidentialité**.
- **Droit de rectification (art. 16)** : modifier vos données depuis votre profil.
- **Droit à l''effacement (art. 17)** : supprimer votre compte. Bouton **Supprimer mon compte** dans **Profil → Confidentialité**.
- **Droit à la portabilité (art. 20)** : récupérer vos données au format JSON via l''export RGPD.
- **Droit d''opposition (art. 21)** : contactez le DPO Jolene à support@jolene.app.

## Conservation

Certaines données sont conservées même après suppression du compte, par obligation légale :

- Factures d''honoraires : **10 ans** (art. L102 B LPF)
- Bulletins de paie : **5 ans** (art. L3243-4 CTW)
- Audit logs : **3 ans** actions utilisateur, **5 ans** actions admin (recommandation CNIL)
- Données pointage GPS : anonymisées après **90 jours**

Le reste est effacé immédiatement à votre demande de suppression.

## Plainte CNIL

Si vous estimez que Jolene ne respecte pas vos droits, vous pouvez déposer plainte auprès de la **CNIL** : [cnil.fr/plaintes](https://www.cnil.fr/plaintes).

## Contact

DPO Jolene : **support@jolene.app**'),

('contacter-support', 'Contacter le support Jolene', 'COMMUN', 'Légal', 100,
'## Avant de contacter le support

Cherchez d''abord dans le **centre d''aide** : la plupart des questions courantes y sont déjà traitées. Tapez votre question dans la barre de recherche en haut de cette page.

## Canaux de contact

- **Email général** : contact@jolene.app
- **Support technique** : support@jolene.app
- **DPO (RGPD)** : support@jolene.app
- **Litiges et incidents graves** : signalement@jolene.app

## Délai de réponse

Nous nous engageons à répondre sous **48 heures ouvrées** (lundi-vendredi, hors fériés).

## Que mettre dans votre message

Pour accélérer la résolution :

- Votre nom de compte ou identifiant
- Description claire du problème
- Captures d''écran si applicable
- Numéro de mission ou de facture concerné
- Étapes que vous avez déjà essayées

## Urgences

Pour les **urgences sécurité** (perte d''accès, fuite de données suspectée), contactez directement **support@jolene.app** avec mention "URGENT" en objet.')

ON CONFLICT (slug) DO NOTHING;
