BEGIN;

-- L'aide publiée décrivait encore l'ancien dossier obligatoire à l'inscription.
-- Corriger uniquement ces quatre articles existants, sans republier un article
-- retiré, changer un contrat/tarif, ni toucher aux règles de candidature.
UPDATE public.articles_aide AS article
SET titre = revision.titre,
    contenu = revision.contenu,
    mis_a_jour_le = now()
FROM (VALUES
  ('etab-comment-m-inscrire', 'Comment m''inscrire en tant qu''établissement',
  $aide$## Créer votre compte

Renseignez votre email, un mot de passe de 8 caractères minimum et le nom de votre établissement. Consultez et acceptez les conditions affichées, puis terminez la vérification de sécurité. Si une confirmation par email vous est demandée, ouvrez le lien reçu pour continuer.

Aucun SIRET ni document n'est demandé pour cette première étape.

## Explorer et préparer une mission

Une fois connecté, vous accédez à votre espace et à ses onglets. Vous pouvez découvrir l'interface et ouvrir le formulaire de mission avant de compléter votre dossier.

Préparez les informations de votre première mission. Lorsque l'application vous propose de compléter votre inscription, votre brouillon est conservé pour reprendre ensuite.

## Compléter le dossier avant de publier

La préparation d'une mission ne la rend pas visible aux soignants. Avant sa publication, complétez les informations de votre établissement et les étapes indiquées dans votre espace : coordonnées, SIRET, vérifications et documents applicables, notamment le contrat de service et le RIB lorsqu'ils sont demandés.

Suivez l'état affiché dans l'application. Un compte créé ou un brouillon enregistré ne signifie pas que l'établissement est déjà autorisé à publier. Si une vérification est en attente ou si une erreur apparaît, vous pouvez continuer à naviguer et reprendre le dossier plus tard.

## Liens utiles

- [Créer mon compte établissement](/inscription/etablissement)
- [Préparer et publier ma première mission](/aide/etab-publier-premiere-mission)
- [Signer le contrat de service Jolene](/aide/etab-contrat-service-jolene)
- [Pourquoi déposer mon RIB](/aide/etab-pourquoi-deposer-rib)$aide$),
  ('inscription-soignant-liberal-salarie-mixte', 'Créer mon compte soignant et compléter mon profil',
  $aide$## Créer votre compte

Avec votre email, renseignez un mot de passe de 8 caractères minimum et votre profession. Consultez et acceptez les conditions affichées, puis terminez la vérification de sécurité. Si une confirmation par email vous est demandée, ouvrez le lien reçu pour continuer.

Pro Santé Connect est aussi proposé aux professionnels qui disposent des moyens d'identification correspondants.

## Découvrir l'application sans remplir tout le dossier

Une fois connecté, vous pouvez parcourir les missions et les autres onglets de votre espace. Aucun document n'est à préparer pour la création du compte. Même si aucune mission ne correspond à votre recherche, vous pouvez modifier vos critères et continuer à naviguer.

## Compléter votre profil quand vous souhaitez candidater

Ouvrez une mission qui vous intéresse, puis choisissez l'action de candidature. Si des informations manquent, l'application vous guide vers les éléments à compléter. Vous pouvez aussi préparer votre profil et vos documents depuis votre espace avant cette étape, si vous le souhaitez.

Les informations et vérifications demandées dépendent de votre situation et de la mission. La création du compte ne vaut pas validation du dossier professionnel.

## Comprendre le contrat d'une mission

Le formulaire de création du compte ne vous demande pas de choisir un statut libéral, salarié ou mixte. Consultez le régime et les conditions indiqués sur chaque mission ; le type de contrat ne découle pas d'un simple choix au moment de l'inscription.

- [Comment le contrat d'une mission est-il déterminé ?](/aide/modes-exercice-missions)
- [Comment candidater à une mission](/aide/comment-candidater-mission)
- [Créer mon compte soignant](/inscription/soignant)$aide$),
  ('comment-candidater-mission', 'Comment candidater à une mission',
  $aide$## Explorer les missions

Ouvrez l'onglet **Missions** de votre espace. Ajustez les filtres proposés et consultez les résultats en liste ou en swipe. Si aucun résultat ne correspond à vos critères, vous pouvez élargir la recherche et continuer à utiliser les autres onglets.

Vous pouvez explorer avec un compte incomplet. Le dossier se complète lorsque vous souhaitez candidater, ou plus tôt depuis votre espace si vous le préférez.

## Ouvrir le détail et candidater

- Consultez le lieu, les dates, les créneaux, la rémunération, le type de contrat et les conditions de la mission.
- Utilisez l'action de candidature affichée sur la mission.
- Si votre profil doit être complété, suivez les étapes indiquées puis reprenez la mission.
- Vérifiez le récapitulatif et confirmez votre choix. Attendez la confirmation affichée avant de considérer votre candidature comme envoyée.

L'application indique les informations manquantes et les éventuels motifs de refus. Les pièces et vérifications requises dépendent de votre profession, de votre situation et de la mission. Une candidature envoyée n'est pas une affectation confirmée.

## Suivre la suite

Retrouvez l'état de votre candidature et les actions disponibles dans votre espace. Si vous êtes retenu, le détail de la mission regroupe les étapes suivantes, dont le contrat, le planning et les présences.

Pour retirer une candidature ou annuler une mission, utilisez l'action proposée et consultez les conditions affichées avant de confirmer.

## Liens utiles

- [Créer mon compte et compléter mon profil](/aide/inscription-soignant-liberal-salarie-mixte)
- [Comment le contrat d'une mission est-il déterminé ?](/aide/modes-exercice-missions)
- [Comment fonctionne le pointage](/aide/comment-fonctionne-pointage)$aide$),
  ('etab-publier-premiere-mission', 'Préparer et publier ma première mission',
  $aide$## Préparer avant de compléter votre dossier

Depuis votre espace établissement, ouvrez **Publier une mission**. Le formulaire est accessible dès la création du compte : vous pouvez préparer votre besoin avant de remplir tout le dossier de l'établissement.

Lorsque l'application vous demande de compléter l'inscription, les informations de votre brouillon sont conservées pour reprendre la préparation ensuite. Un brouillon n'est pas une mission publiée.

## Décrire votre besoin

- Indiquez l'intitulé, la profession recherchée, le service et les informations utiles aux candidats.
- Renseignez les dates, créneaux et pauses dans les champs prévus.
- Consultez les types de contrat proposés pour cette mission, les conditions associées et la rémunération affichée.
- Relisez le récapitulatif avant de poursuivre.

Les options disponibles dépendent de la mission et de votre établissement. Ne déduisez pas une autorisation de publication de la seule présence du formulaire.

## Finaliser puis publier

Complétez les informations et vérifications demandées dans votre espace établissement. En cas d'étape manquante, de vérification en attente ou d'erreur, l'application vous indique ce qui empêche la publication.

Une fois les prérequis remplis, reprenez votre mission, vérifiez les informations puis confirmez la publication. Attendez la confirmation de l'application et retrouvez la mission dans votre espace.

## Suivre les candidatures

Ouvrez le détail de la mission puis **Candidatures** pour consulter les candidatures reçues et les actions disponibles. La publication ne garantit pas un nombre de réponses ni un délai de recrutement.

## Liens utiles

- [Créer mon compte établissement](/aide/etab-comment-m-inscrire)
- [Comment le contrat d'une mission est-il déterminé ?](/aide/modes-exercice-missions)
- [Comprendre la commission Jolene](/aide/etab-comprendre-commission-jolene)$aide$)
) AS revision(slug, titre, contenu)
WHERE article.slug = revision.slug;

COMMIT;
