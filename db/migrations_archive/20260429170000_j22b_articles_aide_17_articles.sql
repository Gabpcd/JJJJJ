-- J2.2.B — 17 articles d'aide (batches 1-6) appliqués via MCP
-- Source de vérité : tracking dans Git + schema_migrations.

INSERT INTO public.articles_aide (slug, titre, audience, categorie, ordre_affichage, contenu) VALUES
('comment-verifier-mon-rpps', 'Comment vérifier mon numéro RPPS', 'SOIGNANT', 'Inscription et profil', 15, $JOLENE_DOC$## Qu'est-ce que le RPPS

Le **RPPS** (Répertoire Partagé des Professionnels de Santé) est un identifiant unique à 11 chiffres délivré par l'Agence du Numérique en Santé (ANS). Il remplace progressivement l'ADELI depuis 2022 et est obligatoire pour exercer en France pour la plupart des professions de santé.

## Qui doit avoir un RPPS sur Jolene

- **Obligatoire** : médecin, IDE, IADE, IBODE, sage-femme, kiné, orthophoniste, ergothérapeute, psychomotricien, pharmacien, manipulateur radio, diététicien, podologue.
- **Non requis** : aide-soignant (AS), accompagnant éducatif et social (AES), préparateur en pharmacie. Ces professions ne sont pas inscrites au RPPS — Jolene vérifie alors le diplôme manuellement.

## Vérification automatique à l'inscription

À l'étape 2 du wizard d'inscription, Jolene appelle l'API officielle de l'ANS pour vérifier :

1. Que votre numéro RPPS existe
2. Qu'il correspond bien à votre **prénom + nom**
3. Que la profession déclarée correspond à votre profession enregistrée à l'ANS

Si tout concorde, votre profil est marqué **RPPS vérifié**. Sinon, l'inscription est bloquée avec un message explicite.

## Hiérarchie des professions

Certaines professions sont des **sur-spécialisations** d'une autre :

- **IBODE** (Infirmier de Bloc Opératoire) → diplôme additionnel après IDE
- **IADE** (Infirmier Anesthésiste) → diplôme additionnel après IDE

Sur Jolene, un IBODE/IADE peut **automatiquement candidater à des missions IDE** (mais l'inverse n'est pas possible). C'est la « hiérarchie des professions » : votre profession exacte vous donne accès aux missions de niveau égal ou inférieur dans votre domaine.

## Que faire si mon RPPS n'est pas reconnu

Plusieurs cas possibles :

- **Vous avez fait une faute de frappe** : vérifiez les 11 chiffres. Pas d'espace ni de tiret.
- **Votre RPPS est récent** (< 30 jours) : l'API ANS met parfois quelques semaines à se mettre à jour.
- **Votre prénom/nom ne correspond pas** : vous avez peut-être saisi un nom marital qui ne figure pas à l'ANS, ou inversement. Utilisez le nom enregistré officiellement.
- **Vous êtes étudiant** : seules les professions diplômées sont acceptées. Une fois votre DE obtenu, votre RPPS sera attribué automatiquement.

Si après ces vérifications le problème persiste, contactez **support@jolene.app** avec votre numéro RPPS et une copie de votre diplôme.

## Spécialités médicales

Pour les **médecins**, vous pouvez préciser une spécialité (cardiologue, pédiatre, etc.) parmi la nomenclature ANS. Cette spécialité conditionne les missions accessibles : un cardiologue verra par défaut les missions cardiologie, mais pourra aussi candidater aux missions « médecin généraliste » si l'option « accepter missions généralistes » est cochée.

## Liens utiles

- [Choisir son type d'exercice : libéral, salarié ou mixte](/aide/inscription-soignant-liberal-salarie-mixte)
- [Comment signer mon mandat de facturation](/aide/signer-mandat-facturation)$JOLENE_DOC$),

('comment-candidater-mission', 'Comment candidater à une mission', 'SOIGNANT', 'Missions', 10, $JOLENE_DOC$## Trouver des missions

Allez sur **Missions** dans la barre de navigation. La page liste toutes les missions ouvertes correspondant à votre profession (avec ouverture aux IBODE/IADE pour les missions IDE).

## Filtres disponibles

- **Distance** : rayon en km depuis votre adresse (par défaut 50 km)
- **Taux horaire minimum** : filtrer les missions à partir d'un certain montant brut
- **Type de contrat** : libéral, salarié, vacation, ou tous
- **Urgence** : missions urgentes uniquement
- **Horaire** : jour, nuit, weekend, ou tous
- **Ville** : recherche libre

Vous pouvez basculer entre vue **Liste** et vue **Carte** (Leaflet/OpenStreetMap) pour visualiser les missions sur une carte.

## Postuler

1. Cliquez sur une mission qui vous intéresse
2. Lisez le détail (intitulé, service, dates, taux, prérequis)
3. Cliquez sur **Postuler**
4. Vous pouvez ajouter un message court à l'attention de l'établissement (optionnel)

Votre candidature est immédiatement transmise à l'établissement.

## Conditions pour postuler

Vous devez avoir :

- **Tous vos documents valides** : diplôme, identité, RCP (responsabilité civile professionnelle) si applicable. Si un document expire pendant la mission, vous serez bloqué.
- **Un compte vérifié** : RPPS validé, profil complet
- **Un mandat de facturation signé** si vous êtes en libéral
- **Pas de chevauchement** avec une autre mission déjà acceptée
- **Le repos légal** de 11 heures consécutives entre 2 missions
- **Le plafond 48h hebdomadaires** respecté

## Que se passe-t-il après

L'établissement reçoit votre candidature et peut :

- **Accepter** : vous recevez une notification, la mission devient ASSIGNÉE. Vous recevez un email + push.
- **Refuser** : vous recevez un message expliquant le motif si l'établissement en a fourni un.
- **Vous proposer une mission** spontanément (mode chasseur de tête) : vous voyez une carte « Proposition reçue » sur votre dashboard, vous pouvez accepter ou décliner.

## Annuler ma candidature

Tant que la mission est encore en statut OUVERTE, vous pouvez retirer votre candidature depuis le détail de la mission. Une fois la mission ASSIGNÉE à vous, l'annulation devient une **annulation de mission** soumise à pénalités selon le délai (cf. CGU).

## Liens utiles

- [Comment fonctionne le pointage](/aide/comment-fonctionne-pointage)
- [Comment ouvrir un litige](/aide/comment-ouvrir-litige)$JOLENE_DOC$),

('comment-fonctionne-pointage', 'Comment fonctionne le pointage', 'SOIGNANT', 'Pointage et présence', 10, $JOLENE_DOC$## Pourquoi pointer

Le pointage prouve votre présence effective sur la mission. Il sert à :

- Calculer votre rémunération (heures réellement travaillées)
- Justifier votre activité auprès de l'établissement et des organismes sociaux
- Détecter les fraudes (pointage à distance, etc.)

## Le code de pointage

À l'assignation, l'établissement reçoit un **code à 6 chiffres** unique pour chaque mission. Ce code est affiché dans son tableau de bord et sur le détail de la mission côté étab.

## Pointage d'ouverture

À votre arrivée :

1. Demandez le code à l'établissement
2. Sur l'app Jolene, allez sur la mission et cliquez **Pointer mon arrivée**
3. Saisissez le code à 6 chiffres
4. L'app capture votre **position GPS** (consentement obligatoire à l'inscription)
5. Pointage validé : vous voyez un tampon « Arrivée enregistrée » avec date, heure, et précision GPS

## Pointage de fermeture

À votre départ : même procédure, bouton **Pointer mon départ**.

## Garde-fous GPS

Jolene compare votre position GPS à l'adresse de l'établissement :

- **< 200 m** : valide, pointage accepté
- **200-500 m** : alerte mais accepté (peut être contesté par l'établissement)
- **> 500 m** : alerte forte, pointage marqué « hors périmètre ». L'établissement peut bloquer votre paiement.
- **Téléportation** (changement de position incohérent en quelques secondes) : alerte fraude détectée.

## Créneaux multiples (pause de mission)

Pour les missions longues avec pause repas non rémunérée :

1. Pointage d'ouverture le matin
2. Pointez la **pause** quand vous arrêtez
3. Pointez la **fin de pause** quand vous reprenez
4. Pointage de fermeture le soir

Jolene calcule alors **2 créneaux effectifs** (matin + après-midi) et déduit la pause de la rémunération.

## Oubli de pointage

Si vous oubliez de pointer votre départ avant de partir :

- Vous avez **24 heures** pour faire une **déclaration rétroactive** depuis l'app (bouton « Déclarer la fin de mission »).
- Au-delà, l'établissement doit valider manuellement vos heures depuis son interface.

## Que faire en cas de problème

- **Code non reconnu** : assurez-vous que la mission est en statut ASSIGNEE/EN_COURS. Demandez à l'étab de re-générer un code (depuis son interface).
- **GPS imprécis (intérieur, sous-sol)** : Jolene tolère jusqu'à 50 m de précision. Si pire, sortez quelques secondes pour avoir un signal.
- **Pas de réseau** : la requête est mise en file d'attente locale et envoyée dès que possible (mode hors-ligne).

## Données GPS et confidentialité

Votre position est utilisée **uniquement** pour valider le pointage. Elle est anonymisée automatiquement après **90 jours** (cron `fn_anonymiser_gps_anciennes`). Vous pouvez retirer votre consentement à tout moment dans **Profil → Confidentialité**.

## Liens utiles

- [Comment candidater à une mission](/aide/comment-candidater-mission)
- [Comment ouvrir un litige](/aide/comment-ouvrir-litige)
- [Mes droits RGPD](/aide/mes-droits-rgpd)$JOLENE_DOC$),

('comprendre-ma-facture-honoraires', 'Comprendre ma facture d''honoraires', 'SOIGNANT', 'Facturation et paiement', 30, $JOLENE_DOC$## Qui émet la facture

Pour vos missions en exercice **LIBÉRAL**, Jolene émet la facture **en votre nom et pour votre compte**, en qualité de mandataire de facturation au sens de l'**article 289 I-2 du Code général des impôts**. C'est légal et reconnu fiscalement.

Vous restez le **vendeur juridique** de la prestation. La facture mentionne :
- Vos coordonnées (nom, prénom, RPPS, SIRET libéral, adresse)
- Les coordonnées de l'établissement débiteur
- La mention obligatoire « *Facture émise par JOLENE SAS en qualité de mandataire de facturation au sens de l'article 289 I-2 du CGI* »
- La mention TVA : « *TVA non applicable — art. 261, 4-1° du CGI* » (les soins paramédicaux et médicaux libéraux sont exonérés de TVA)

## Numérotation

Format : `JOL-{SIRET8}-{ANNEE}-{SEQ5}` — exemple : `JOL-82234567-2026-00042`. La séquence est continue par soignant : la facture #00042 sera suivie de la #00043 pour vos prochaines missions.

## Stratégie hebdomadaire vs finale unique

Selon la durée de la mission, deux modes de facturation sont possibles. La stratégie est figée à l'assignation et ne peut pas changer après.

### Mission ≤ 7 jours : facture finale unique

Vous recevez **une seule facture** émise après la terminaison de la mission, couvrant l'intégralité de la période. C'est le cas le plus courant.

### Mission > 7 jours : factures hebdomadaires + finale partielle

Vous recevez **une facture chaque dimanche** pour la semaine ISO écoulée (lundi-dimanche), plus une **facture finale partielle** quand la mission se termine en milieu de semaine. Cela vous permet d'être payé au fil de l'eau plutôt qu'attendre 3 semaines.

Exemple mission 14 jours du lundi 4 au dimanche 17 :
- Facture S15 émise lundi 11 (couvre 4-10/05)
- Facture S16 émise lundi 18 (couvre 11-17/05) — c'est la facture finale

Chaque facture mentionne **le cumul** déjà facturé sur la mission pour visibilité.

## Composition

Une facture détaille :

- **Heures travaillées** (depuis votre pointage validé)
- **Taux horaire de base** (figé à l'assignation)
- **Majorations** : nuit, dimanche, jour férié (taux figés depuis l'établissement)
- **Total HT** (= TTC pour les pros exonérés de TVA)
- **Date d'émission** et **date d'échéance** (30 jours par défaut)

## Paiement

L'établissement paie via Stripe Connect (carte ou SEPA) directement sur la plateforme. Jolene reverse les sommes sur votre IBAN (configuré dans **Profil → Paiements**), déduction faite de la commission convenue.

Délai de paiement habituel : **30 jours** maximum après émission. Si vous voulez être payé plus vite (J+2), activez l'option **Defacto** (cf. article dédié).

## PDF + Factur-X

Chaque facture est livrée en **PDF + XML Factur-X (EN16931 BASIC WL)** — format conforme à la facturation électronique obligatoire. Téléchargeable depuis **Mes factures d'honoraires**.

## Si la mission est en litige

La facture est mise en statut **EN_ATTENTE_LITIGE** (gel partiel ou total selon le scope). Le paiement est suspendu jusqu'à résolution. Cf. [Comment ouvrir un litige](/aide/comment-ouvrir-litige).

## Liens utiles

- [Comment signer mon mandat de facturation](/aide/signer-mandat-facturation)
- [Defacto et le paiement J+2](/aide/defacto-paiement-j2)$JOLENE_DOC$),

('comprendre-mon-bulletin-paie', 'Comprendre mon bulletin de paie', 'SOIGNANT', 'Bulletin de paie', 10, $JOLENE_DOC$## Qui émet le bulletin

Pour les missions en **CDDU (contrat à durée déterminée d'usage)** ou autre contrat salarié, l'**établissement est votre seul employeur**. Jolene génère le bulletin de paie automatiquement **au nom de l'établissement**, conformément à l'**article R3243-1 du Code du travail**.

Cela signifie :
- L'établissement assume toutes les obligations légales d'employeur (URSSAF, retraite, prévoyance, etc.).
- Jolene est un service automatisé qui calcule cotisations et net à payer, mais la responsabilité finale incombe à l'établissement.
- Si vous avez un litige sur votre paie, contactez d'abord l'établissement — Jolene peut intervenir comme tiers de bonne foi.

## Composition du bulletin

Conformément à l'article R3243-1, votre bulletin contient :

### Identification
- Vos nom, prénom, NIR (numéro de sécurité sociale)
- Identité de l'employeur (établissement) : nom, SIRET, adresse, convention collective
- Période : dates de début et fin de mission
- Numéro unique : `BP-{SIRET8}-{ANNEE}-{SEQ5}`

### Brut
- Heures travaillées × taux horaire
- Majorations nuit/dimanche/férié si applicable
- **Salaire brut** total

### Cotisations salariales (déduites du brut)
- **CSG déductible** : 6,80 % (sur 98,25 % du brut)
- **CSG non déductible** : 2,40 %
- **CRDS** : 0,50 %
- **Sécurité Sociale Vieillesse** plafonnée + déplafonnée
- **Retraite complémentaire** AGIRC-ARRCO T1 et T2
- **CEG** (Contribution d'Équilibre Général)

### Cotisations patronales (à la charge de l'établissement, indiquées pour info)
- SS maladie 13,05 %, allocations familiales 5,25 %, accidents du travail 1 %, FNAL, formation pro, transport...

### IFM et ICP (CDDU spécifiques)
- **IFM** (Indemnité de Fin de Mission) : **10 % du brut** versée à la fin du contrat (article L1243-8 CTW). Compense la précarité du CDDU.
- **ICP** (Indemnité Compensatrice de Congés Payés) : **10 % du (brut + IFM)** (article L3141-22 CTW). Compense les congés non pris.

### Net à payer
**Net avant impôt** = Brut − Cotisations salariales + IFM + ICP

L'impôt sur le revenu (prélèvement à la source) est appliqué selon votre taux personnalisé fourni par la DGFiP.

## Cumul annuel

En bas du bulletin, vous voyez le **cumul depuis le 1er janvier** : brut, cotisations sal./pat., IFM, ICP, net. Pratique pour suivre votre revenu fiscal.

## Téléchargement PDF

Tous vos bulletins sont accessibles dans **Mes bulletins de paie**. Cliquez **PDF** pour télécharger un bulletin conforme R3243-1 (mentions obligatoires, signature électronique, etc.).

## NIR (numéro de sécurité sociale)

Votre NIR est obligatoire sur le bulletin. Renseignez-le dans **Profil → Paie et facturation → NIR**. Donnée chiffrée, accessible uniquement à vous et à l'admin Jolene. Format : 13 chiffres (sans clé) ou 15 (avec clé).

## Conservation

Vos bulletins sont conservés **5 ans minimum côté employeur** (article L3243-4 CTW) et **indéfiniment côté salarié**. Téléchargez et archivez systématiquement vos bulletins.

## Liens utiles

- [Choisir son type d'exercice](/aide/inscription-soignant-liberal-salarie-mixte)
- [Comprendre ma facture d'honoraires](/aide/comprendre-ma-facture-honoraires)$JOLENE_DOC$),

('defacto-paiement-j2', 'Defacto et le paiement J+2', 'SOIGNANT', 'Facturation et paiement', 40, $JOLENE_DOC$## Qu'est-ce que Defacto

**Defacto** est un partenaire d'affacturage (factor) qui rachète vos factures dès leur émission. Vous êtes payé en **48 heures** au lieu d'attendre les 30 jours habituels du paiement par l'établissement.

C'est utile si :
- Vous avez besoin de trésorerie rapide
- Vous ne voulez pas vous soucier des relances en cas d'impayé
- Vous préférez la sécurité d'un paiement garanti

## Comment ça marche

1. Une mission libérale est terminée → Jolene émet votre facture
2. Si l'opt-in Defacto est activé : Jolene cède automatiquement la facture à Defacto au moment de son émission (statut EMISE)
3. Defacto vous verse **le montant net** sous **48 heures** sur votre IBAN
4. Defacto se charge ensuite d'encaisser le paiement de l'établissement (à 30 jours)

## Frais

Defacto prélève une **commission d'environ 1 à 3 %** du montant TTC de la facture, selon votre profil et le risque-débiteur de l'établissement. Le détail des frais vous est communiqué avant la première cession.

Exemple : facture de 1 000 € HT → vous recevez environ 970-990 € sur votre compte sous 48h, contre 1 000 € à 30 jours sans Defacto.

## Activer ou désactiver l'opt-in

Le choix est **global** : vous activez Defacto pour **toutes vos futures factures** ou aucune.

### À l'inscription
Lors de votre inscription en libéral, vous voyez deux options :
- **Paiement étab 30 jours** (par défaut, 0 frais)
- **Paiement rapide J+2 Defacto** (1-3 % de frais)

### À tout moment depuis votre profil
Allez sur **Profil → Paie et facturation → Paiement rapide J+2**. Bascule du toggle :
- **Activé** → toutes vos prochaines factures EMISE seront cédées automatiquement
- **Désactivé** → vos prochaines factures seront payées par l'établissement à 30 jours

Le changement n'affecte que les factures **futures**. Les factures déjà cédées suivent leur cours normal.

## Sécurité

- Defacto est un acteur français régulé (agrément ACPR)
- Cession formalisée par signature électronique de la convention de cession (signature canvas Jolene + IP + UA)
- Vous pouvez télécharger toutes vos cessions signées depuis **Mes avances**

## Limites

- Defacto peut **refuser** une cession si l'établissement présente un risque de défaut élevé. Dans ce cas, vous repassez sur le paiement à 30 jours pour cette facture.
- En cas de **litige** sur la facture, la cession est suspendue jusqu'à résolution.
- Les missions en **secteur public** (Chorus Pro) ne sont pas éligibles à Defacto (paiement Trésor Public garanti).

## Suivi de mes avances

Allez sur **Mes avances** pour voir :
- Le statut de chaque cession (En attente / Financée / Recouvrée)
- Les frais Defacto et le net reçu
- L'historique de vos demandes

## Liens utiles

- [Comprendre ma facture d'honoraires](/aide/comprendre-ma-facture-honoraires)
- [Comment signer mon mandat de facturation](/aide/signer-mandat-facturation)$JOLENE_DOC$),

('comment-ouvrir-litige', 'Comment ouvrir un litige', 'SOIGNANT', 'Litiges', 10, $JOLENE_DOC$## Quand ouvrir un litige

Un litige est une procédure formelle pour contester un point d'une mission. Vous pouvez en ouvrir un dans 4 catégories :

- **FINANCIER** : désaccord sur le montant facturé / payé (ex : heures comptées en moins, taux erroné, majoration nuit oubliée)
- **PRESENCE** : désaccord sur le pointage (heures réellement travaillées, retard contesté, oubli de pointage)
- **CONDITIONS** : non-respect des conditions de mission (matériel manquant, encadrement insuffisant, profession différente du brief)
- **COMPORTEMENT** : problème comportemental grave côté établissement (harcèlement, discrimination, mise en danger)

## Fenêtres de contestation

Chaque type de litige a un délai légal pour être ouvert. Au-delà, vous ne pouvez plus contester.

| Type de litige | Délai | Article |
|---|---|---|
| **F1** Contestation pointage | **48 heures** après fin de mission | CGU art. 8 |
| **F2** Contestation facture libéral | **48 heures** après émission facture | CGU art. 9 |
| **F3** Contestation paiement salarié | **60 jours** après date paiement prévue | Code travail (prescription salaires) |
| **Sécurité grave** (danger immédiat) | **Pas de délai** | — |

## Comment ouvrir un litige

1. Allez sur le **détail de la mission** concernée
2. Cliquez sur le bouton **Contester** (visible si vous êtes dans la fenêtre)
3. Sélectionnez la **catégorie** (FINANCIER / PRESENCE / CONDITIONS / COMPORTEMENT)
4. Décrivez précisément le problème (date, heure, faits)
5. Joignez si possible **photos, captures, documents** justificatifs
6. Cliquez **Ouvrir le litige**

L'établissement reçoit immédiatement une notification + email.

## Gel de la facture pendant litige

Si une facture est concernée par votre litige, elle passe en statut **EN_ATTENTE_LITIGE** : le paiement est suspendu.

Le **scope de gel** dépend du type :
- **FINANCIER** : seule la facture pointée est gelée
- **PRESENCE / CONDITIONS / COMPORTEMENT** : par défaut toutes les factures non-payées de la mission. Mais l'admin peut moduler le scope (`MISSION_ENTIERE`, `FACTURE_UNIQUE`, `AUCUN`, ou `PERIODE_LITIGIEUSE` pour les missions hebdomadaires).

Une fois le litige résolu, le gel est levé et le paiement reprend.

## Processus de résolution

1. **OUVERT** : litige créé, étab notifié
2. **EN_DISCUSSION** : échanges entre vous et l'étab via la messagerie litige
3. **EN_MEDIATION** : si désaccord persistant, l'admin Jolene intervient comme tiers neutre
4. **RESOLU** (par soignant, étab ou admin) : décision actée, paiement débloqué
5. **CLOTURE** : litige fermé, audit final

Vous recevez des **rappels** automatiques si le litige reste ouvert (J+1, J+3, J+5).

## Exemple concret

Mission de 8h prévues, vous avez pointé 7h45 (15 min de retard à l'ouverture). L'étab valide 7h45. Vous estimez avoir travaillé en réalité 8h (vous étiez là mais avez oublié de pointer dès l'entrée).

→ Ouvrir un **litige PRESENCE** dans les 48h après la fin, joindre votre badge d'accès ou témoignage. Si l'établissement valide, vos heures et votre paiement sont ajustés.

## Rate limit

Pour éviter les abus, vous pouvez ouvrir maximum **3 litiges par heure** par mission/établissement. Largement suffisant pour les cas légitimes.

## Liens utiles

- [Comment fonctionne le pointage](/aide/comment-fonctionne-pointage)
- [Comprendre ma facture d'honoraires](/aide/comprendre-ma-facture-honoraires)$JOLENE_DOC$),

('mes-droits-rgpd-soignant', 'Mes droits RGPD en tant que soignant', 'SOIGNANT', 'RGPD et données personnelles', 20, $JOLENE_DOC$## Données collectées par Jolene

En tant que soignant inscrit, Jolene collecte :

- **Identité** : nom, prénom, date de naissance, photo profil
- **Contact** : email, téléphone, adresse postale
- **Professionnel** : RPPS, ADELI (legacy), profession, spécialités, types de contrat acceptés, expérience
- **Documents** : diplômes, identité, RCP, attestations vaccinales (vérifiés par admin Jolene)
- **Bancaires** : IBAN last4, identifiants Stripe Connect
- **Activité** : missions, candidatures, pointage GPS, évaluations, factures, bulletins
- **Communication** : messages, notifications, emails, SMS

Tout est stocké en France (Supabase Paris, AWS eu-west-3) avec chiffrement AES-256.

## Vos 6 droits RGPD

### 1. Droit d'accès (article 15)

Vous pouvez exporter **toutes vos données** au format JSON portable. Allez dans **Profil → Confidentialité → Télécharger mes données**.

L'export contient **21 catégories** : profil, missions, candidatures, présences, factures, bulletins, cotisations, mandats, cessions, paiements, contrats, documents, évaluations données et reçues, messages, notifications, partages RIB, parrainages.

Le NIR (numéro de sécurité sociale) est **exclu** de l'export par sécurité (donnée identifiante particulière).

Limite : **2 exports par jour** par soignant.

### 2. Droit de rectification (article 16)

Modifier vos données depuis **Profil → Modifier**. Pour le RPPS et l'identité, contactez le support si la rectification est bloquée (cohérence vérification).

### 3. Droit à l'effacement (article 17)

Bouton **Supprimer mon compte** dans **Profil → Confidentialité**. Confirmation par saisie « SUPPRIMER ».

**Conséquences** :
- Votre profil est anonymisé immédiatement (prénom = « Soignant », nom = « Supprimé », email pseudonymisé, RPPS/ADELI/IBAN supprimés)
- Vos pointages GPS sont anonymisés
- Vos messages deviennent « [Message supprimé] »
- Vos cotisations sociales et conversions libéral sont effacées
- Vos **factures d'honoraires** sont **conservées 10 ans** (obligation légale article L102 B LPF, traçabilité fiscale)
- Vos **bulletins de paie** sont **conservés 5 ans** côté employeur (article L3243-4 CTW)
- Audit trail RGPD_SUPPRESSION_COMPTE écrit dans journaux_audit

Limite : **1 suppression par jour** (rate limit anti-erreur).

### 4. Droit à la portabilité (article 20)

L'export JSON ci-dessus respecte le format portable réutilisable par vous ou un autre service.

### 5. Droit d'opposition (article 21)

Pour vous opposer à un traitement spécifique (ex : ne plus recevoir de SMS), désactivez les options dans **Profil → Préférences**. Pour une opposition globale, contactez le DPO.

### 6. Droit à la limitation (article 18)

Pour limiter temporairement le traitement de vos données (ex : enquête en cours), contactez le DPO Jolene.

## DPO Jolene

**support@jolene.app** — Délai de réponse 1 mois maximum (RGPD article 12.3).

## Plainte CNIL

Si Jolene ne respecte pas vos droits, vous pouvez porter plainte auprès de la **CNIL** : [cnil.fr/plaintes](https://www.cnil.fr/plaintes).

## Conservation détaillée

| Donnée | Durée | Base légale |
|---|---|---|
| Compte actif | Durée du contrat | Contrat |
| Compte supprimé (anonymisé) | 3 ans | Obligation santé |
| Factures honoraires | 10 ans | Art. L102 B LPF |
| Bulletins paie | 5 ans | Art. L3243-4 CTW |
| Pointage GPS | 90 jours puis anonymisé | Anti-fraude |
| Audit logs | 3 à 5 ans | Recommandation CNIL |

## Sécurité

Voir [Comment Jolene assure la sécurité](/aide/comment-jolene-assure-securite) pour les mesures techniques (RLS, chiffrement, audit append-only, etc.).$JOLENE_DOC$),

('etab-comment-m-inscrire', 'Comment m''inscrire en tant qu''établissement', 'ETABLISSEMENT', 'Inscription et profil', 5, $JOLENE_DOC$## Vue d'ensemble

L'inscription d'un établissement sur Jolene se fait en **2 grandes phases** :

1. **Création du compte** (5 minutes) : email, SIRET, type d'établissement, adresse, contact
2. **Finalisation de l'onboarding** (10 minutes) : signature du contrat de service Jolene + dépôt du RIB

Tant que les 2 phases ne sont pas complètes, vous ne pouvez **pas publier de missions** : un trigger DB bloque la création (`fn_trg_verifier_onboarding_etab`) avec un message clair.

## Phase 1 — Création du compte

### Étape 1 : identifiants
- **Email professionnel** + mot de passe (8 caractères minimum, mélange majuscules/minuscules/chiffres/spéciaux)
- Acceptation des **CGU + CGV + politique de confidentialité** (cases à cocher obligatoires, audit RGPD enregistré)

### Étape 2 : profil établissement
- **SIRET 14 chiffres** (validation Luhn locale + vérification temps réel via API officielle INSEE/recherche-entreprises.api.gouv.fr)
  - Si SIRET trouvé + actif + secteur santé (NAF 86.xx, 87.xx, 88.xx, 47.73Z) → **vérification automatique**, vous pouvez publier dès le compte créé.
  - Sinon → statut `EN_ATTENTE` avec validation manuelle par l'admin Jolene sous 24h ouvrées.
- **FINESS** ou numéro de licence (optionnel selon type)
- **Type d'établissement** : clinique privée, hôpital public, EHPAD, HAD, pharmacie d'officine, centre de santé, etc.
- **Adresse complète** + géolocalisation auto (utilisée pour le rayon de recherche soignants)
- **Email + téléphone** de contact
- **Captcha Turnstile** Cloudflare anti-bot

L'email de bienvenue **BIENVENUE_ETABLISSEMENT** est envoyé automatiquement après validation.

## Phase 2 — Finalisation de l'onboarding

À la première connexion, un **bandeau persistant** s'affiche en haut de chaque page : « Votre inscription n'est pas finalisée. [Compléter maintenant] ». Cliquez pour aller sur `/etablissement/finaliser-inscription`.

### Étape 1 — Contrat de service Jolene
1. Lecture intégrale du contrat (scroll obligatoire jusqu'en bas)
2. 2 cases à cocher :
   - « J'ai lu et j'accepte le contrat de service Jolene »
   - « Je certifie être habilité à engager mon établissement »
3. **Signature canvas** (tracé manuscrit, ≥ 2 traits validés)
4. Au submit : `fn_signer_contrat_service` enregistre la signature avec hash SHA-256 du texte + IP + user-agent + timestamp. Audit `CONTRAT_SIGNE`.

### Étape 2 — Dépôt du RIB
1. Upload PDF, JPG ou PNG (max 5 Mo)
2. Stockage sécurisé Supabase Storage privé (`jolene-documents/etablissements/{etab_id}/rib.{ext}`)
3. Accessible uniquement par l'admin Jolene via signed URLs 1h

Une fois les 2 étapes complétées, redirection automatique vers le dashboard, toast « Inscription finalisée ».

## Que se passe-t-il si vous tentez de créer une mission avant onboarding

Le trigger `fn_trg_verifier_onboarding_etab` lève une exception SQL avec un message clair :

> *Inscription incomplète : vous devez signer le contrat de service Jolene avant de publier des missions. Rendez-vous sur /etablissement/finaliser-inscription.*

Idem si le RIB n'est pas uploadé.

## Vérification SIRET en cas d'échec

Si l'API INSEE ne reconnaît pas votre SIRET (récent, non encore actif, cas particulier) :
- Votre compte est créé en statut `EN_ATTENTE`
- L'admin Jolene vérifie manuellement sous 24h ouvrées (vérification via document Kbis / J3 si nécessaire)
- Vous recevez un email à validation

## Liens utiles

- [Signer le contrat de service Jolene](/aide/etab-contrat-service-jolene)
- [Pourquoi déposer mon RIB](/aide/etab-pourquoi-deposer-rib)
- [Pourquoi je dois uploader le contrat de travail SALARIE](/aide/etab-pourquoi-uploader-contrat-travail)$JOLENE_DOC$),

('etab-pourquoi-deposer-rib', 'Pourquoi déposer mon RIB', 'ETABLISSEMENT', 'Inscription et profil', 20, $JOLENE_DOC$## À quoi sert votre RIB

Votre RIB (Relevé d'Identité Bancaire) est nécessaire pour les **opérations de paiement** entre votre établissement et Jolene SAS, principalement :

- **Encaissement de la commission Jolene** sur chaque mission réalisée par votre intermédiaire
- **Reversements** éventuels (avoirs, régularisations)
- **Facturation Chorus Pro** pour les établissements du secteur public

Le dépôt du RIB est **obligatoire** pour publier des missions sur la plateforme. Tant qu'il n'est pas fourni, le trigger DB `fn_trg_verifier_onboarding_etab` bloque toute création de mission.

## Comment c'est stocké

Votre RIB est stocké dans le **bucket Supabase Storage privé `jolene-documents`**, dans le sous-dossier `etablissements/{votre_etab_id}/rib.{ext}`.

**Accès :**
- Vous-même : oui, depuis votre profil
- Admin Jolene : oui, via signed URLs temporaires (1 heure max)
- Soignants : non, jamais
- Tiers : non, jamais

Le bucket est privé : aucune URL publique ne pointe sur votre RIB. Toute lecture passe par une URL signée temporaire générée à la demande.

## Format accepté

- **Types MIME** : PDF, JPG, PNG
- **Taille max** : 5 Mo
- **Recommandation** : PDF lisible (haute qualité). Pas de scan trop compressé.

L'upload est validé côté front (taille + type) et côté serveur (RLS étab + admin uniquement).

## Aucun débit automatique sans mandat

Important : déposer votre RIB **n'autorise pas Jolene à débiter votre compte**. Pour qu'un prélèvement automatique soit possible, vous devez signer un **mandat SEPA** distinct depuis votre profil Stripe Connect (article séparé sur le règlement des commissions).

Sans mandat SEPA, les commissions Jolene sont facturées avec **paiement à 30 jours** par virement classique de votre part vers Jolene SAS.

## Données chiffrées

Tous les fichiers du bucket `jolene-documents` sont chiffrés au repos (AES-256, géré par Supabase / AWS RDS). En transit, accès via TLS 1.3 uniquement.

## Modifier votre RIB

Vous pouvez remplacer votre RIB à tout moment depuis `/etablissement/finaliser-inscription` (l'upload écrase l'ancien fichier). L'ancien RIB est supprimé physiquement du bucket. Audit `DOCUMENT_TELEVERSEMENT` enregistré.

## Conformité RGPD

Votre RIB est une **donnée personnelle de l'établissement** (pas une donnée santé). Il est conservé tant que votre compte est actif. À la suppression du compte, le RIB est effacé du bucket dans les 30 jours, sauf litige financier en cours nécessitant sa rétention.

## Liens utiles

- [Comment m'inscrire en tant qu'établissement](/aide/etab-comment-m-inscrire)
- [Comprendre la commission Jolene](/aide/etab-comprendre-commission-jolene)
- [Comment Jolene assure la sécurité](/aide/comment-jolene-assure-securite)$JOLENE_DOC$),

('etab-pourquoi-uploader-contrat-travail', 'Pourquoi je dois uploader le contrat de travail SALARIE', 'ETABLISSEMENT', 'Missions', 30, $JOLENE_DOC$## Le principe juridique : vous êtes seul employeur

Pour les missions en exercice **SALARIE** (typiquement CDDU, contrat à durée déterminée d'usage), votre établissement est **seul employeur** du soignant. Jolene n'est qu'un intermédiaire technique fournissant la plateforme.

C'est explicitement prévu à l'**article 2.2 du contrat de service Jolene** que vous avez signé :

> *Pour les soignants en exercice salarié (CDDU notamment), l'Établissement demeure SEUL EMPLOYEUR du soignant. Jolene n'est en aucun cas employeur des soignants. L'Établissement assume l'intégralité des obligations légales afférentes à la qualité d'employeur, notamment le respect du Code du travail, la déclaration aux organismes sociaux, et la responsabilité de la sécurité du soignant pendant la mission.*

## Risque de requalification URSSAF

Sans contrat de travail signé entre vous et le soignant, l'URSSAF ou les Prud'hommes pourraient considérer que **Jolene est l'employeur de fait**. Cela exposerait Jolene à une requalification en société de portage / travail temporaire (qu'elle n'est pas) et **vous exposerait à des sanctions** :

- Cotisations URSSAF non versées récupérées avec majorations
- Indemnités de requalification au profit du soignant
- Risque pénal en cas de récidive

C'est pourquoi l'article 5.2 du contrat de service vous oblige à fournir un contrat de travail signé pour chaque mission salariée.

## Article 5.2 du contrat de service

> *L'Établissement s'engage à uploader sur la plateforme une copie signée du contrat de travail conclu avec le soignant pour chaque mission salariée, au plus tard le premier jour de la mission.*

## Format du contrat

Le contrat doit être un **CDDU** (ou CDD selon votre cas) conforme au Code du travail :
- Identité des deux parties (étab + soignant)
- Motif du recours (ex : « remplacement temporaire d'un agent absent »)
- Durée précise (date début + fin)
- Salaire brut horaire + total
- Convention collective applicable (FHP, FEHAP, CCU, FPH...)
- Signature des deux parties

Format de fichier : **PDF uniquement**, **max 10 Mo**.

## Comment uploader

Sur le **détail de la mission** côté étab, dès qu'un soignant est assigné et que la mission est en SALARIE, un bloc « Contrat de travail à déposer » apparaît :

1. Cliquez sur l'input file
2. Sélectionnez le PDF
3. Cliquez **Déposer**
4. Le contrat est uploadé sur Supabase Storage (bucket `jolene-documents/contrats-travail/{mission_id}/contrat.pdf`)
5. Une row `contrats_travail_missions` est créée avec date, taille, uploader
6. Le **soignant est automatiquement notifié** (in-app + email `CONTRAT_TRAVAIL_DEPOSE`)
7. Audit `DOCUMENT_TELEVERSEMENT` enregistré

## Remplacer le contrat

Si une erreur ou avenant : bouton **Remplacer**. Nouveau fichier upload, ancien écrasé. Audit `contrat_travail_remplace`.

## Rappel automatique J-1 si oubli

Si la mission débute dans **moins de 36 heures** et qu'aucun contrat n'a été uploadé, le cron `email-cron` envoie quotidiennement :

- Un email **CONTRAT_TRAVAIL_RAPPEL_ETAB** à votre établissement
- Un email **CONTRAT_TRAVAIL_MANQUANT_SOIGNANT** au soignant pour qu'il puisse vous contacter

L'envoi est **idempotent** (1 fois max par jour par mission, table `rappels_contrat_travail`).

## Côté soignant

Le soignant peut **télécharger son contrat** (signed URL 1h) depuis le détail de sa mission. Si pas encore uploadé J-1 du début, il voit un warning « Votre établissement n'a pas encore déposé votre contrat de travail. Vous pouvez le contacter pour le rappeler. »

## Important

L'upload est **votre responsabilité**, pas celle de Jolene. Jolene **n'empêche pas** la mission de démarrer si le contrat n'est pas uploadé (juste alerte) — c'est à vous d'assumer ce risque légal.

## Liens utiles

- [Signer le contrat de service Jolene](/aide/etab-contrat-service-jolene)
- [Publier ma première mission](/aide/etab-publier-premiere-mission)$JOLENE_DOC$),

('etab-publier-premiere-mission', 'Publier ma première mission', 'ETABLISSEMENT', 'Missions', 10, $JOLENE_DOC$## Prérequis

Avant de pouvoir publier, vérifiez que votre [inscription est finalisée](/aide/etab-comment-m-inscrire) : contrat de service signé + RIB déposé. Sans ça, le bouton « Publier » est bloqué et un trigger DB lève `Inscription incomplète`.

## Créer la mission

Allez sur **Missions → Publier une mission** (`/etablissement/missions/creer`).

### Informations générales
- **Intitulé** : court et descriptif (« Remplacement IDE service cardio »)
- **Profession requise** : IDE, IBODE, IADE, médecin, kiné, sage-femme, AS, AES... La hiérarchie pro fonctionne (un IDE peut accepter une mission AS si vous l'autorisez).
- **Spécialité médicale** (médecins uniquement) : code ANS (cardiologue, pédiatre, etc.)
- **Service** : oncologie, pédiatrie, urgences, MCO, EHPAD, etc.
- **Description** : contexte, équipe, matériel, particularités. Plus c'est précis, plus vos candidatures seront pertinentes.

### Type de contrat
Choisissez **LIBERAL** ou **SALARIE**. C'est figé à l'assignation et impacte beaucoup :

| Aspect | LIBERAL | SALARIE |
|---|---|---|
| Document légal | Mandat de facturation soignant | Contrat de travail CDDU à uploader par vous |
| Émission rémunération | Facture honoraires Jolene | Bulletin de paie Jolene au nom étab |
| Cotisations sociales | URSSAF du soignant | URSSAF établissement (employeur) |
| Délai paiement | Jusqu'à 30 j (ou J+2 si soignant Defacto) | Selon paie habituelle étab |

### Dates et créneaux
- **Date début + date fin** : timestamps précis (timezone Europe/Paris)
- **Créneaux multiples** possibles : pause repas non rémunérée détectée automatiquement. Indiquez « pause 12h-13h » dans la description ou ajoutez un créneau dédié.

### Tarification
- **Taux horaire de base** brut : libre, mais respectez les minima conventionnels de votre CCN
- **Majorations** automatiques selon les paramètres de votre étab (figées à l'assignation) :
  - **Nuit** : minimum 25 % (plancher Jolene). Configurable par étab.
  - **Dimanche** : minimum 25 %
  - **Jour férié** : minimum 50 %
- **Heures de nuit** : par défaut 21h-06h. Configurable au niveau étab.

Le **total brut estimé** est affiché en temps réel pour anticiper le coût.

## Validation et publication

Cliquez **Publier**. Trigger DB vérifie :
- Onboarding étab finalisé ✓
- Profession compatible avec votre type d'étab (`dec_verifier_profession_etablissement`)
- Type de contrat compatible (`dec_verifier_type_contrat_mission`)
- Pas de mission passée (date début ≥ aujourd'hui)
- Pas de chevauchement avec une mission déjà ouverte du même intitulé

Mission créée en statut `OUVERTE`. Visible immédiatement par les soignants compatibles dans leur recherche.

## Recevoir des candidatures

Vous recevez un **email + push** à chaque candidature. Allez sur le détail de la mission, onglet **Candidatures** :

- Profil soignant (RPPS vérifié, expérience, note moyenne, distance)
- Message éventuel
- Bouton **Accepter** ou **Refuser** (motif optionnel)

Acceptation = assignation. Le soignant est notifié immédiatement.

## Mode urgent

Cochez **Mission urgente** pour publier dans le pool d'urgence : alertes push SMS aux soignants disponibles dans le rayon, candidatures généralement reçues en quelques minutes.

## Annulation

Tant que la mission est OUVERTE : annulation libre, pas de pénalité. Une fois ASSIGNEE, l'annulation tardive peut entraîner des pénalités selon la fenêtre (cf. CGU art. 7).

## Liens utiles

- [Pourquoi je dois uploader le contrat de travail SALARIE](/aide/etab-pourquoi-uploader-contrat-travail)
- [Comprendre la commission Jolene](/aide/etab-comprendre-commission-jolene)
- [Comment résoudre un litige](/aide/etab-resoudre-litige)$JOLENE_DOC$),

('etab-comprendre-commission-jolene', 'Comprendre la commission Jolene', 'ETABLISSEMENT', 'Facturation et paiement', 10, $JOLENE_DOC$## Principe

En contrepartie du service rendu (mise à disposition de la plateforme, mandat de facturation, bulletin de paie automatisé, support, etc.), Jolene perçoit une **commission** sur chaque mission réalisée par votre intermédiaire.

Cette commission est due par votre établissement à Jolene SAS. Elle est définie dans l'**article 4 du contrat de service** que vous avez signé.

## Taux de commission

### Taux par défaut
**15 %** du montant brut total de la mission (taux standard contractuel).

### Cascade de résolution
Le taux applicable suit cette cascade au moment de l'assignation :

1. **Taux établissement** (`etablissements.taux_commission_negocie`) — si vous avez négocié un taux personnalisé avec Jolene
2. **Taux groupe santé** (`groupes_sante.taux_commission_negocie`) — si votre étab appartient à un groupe avec accord-cadre
3. **Défaut 15 %** — si ni taux étab ni taux groupe

Le taux est consultable dans **Profil → Paramètres financiers**.

### Figement à l'assignation
Le taux est **figé** au moment de l'assignation du soignant à la mission (colonne `missions.taux_commission_fige`). Toute renégociation ultérieure n'affecte que les **futures missions**, pas les missions déjà assignées.

## Calcul

```
Commission HT = Montant brut total mission × Taux commission
```

Le **montant brut total** inclut :
- Heures travaillées × taux horaire de base
- + Majorations nuit / dimanche / férié

Exemple : mission 8h à 25 €/h dont 2h de nuit avec majoration 25 % :
- Brut = 6×25 + 2×25×1,25 = 150 + 62,50 = **212,50 €**
- Commission 15 % = **31,87 € HT**

TVA applicable Jolene : **20 %** standard (Jolene est une SASU non exonérée pour ses prestations de service).

## Fréquence de facturation

Selon votre configuration de paiement :

### Sans Stripe Connect (mode classique)
- **Facturation mensuelle** consolidée le 1er du mois suivant
- 1 facture regroupant toutes les commissions du mois
- Payable à 30 jours par virement bancaire vers Jolene SAS

### Avec Stripe Connect activé
- **Facturation hebdomadaire** automatique (cron `fn_auto_facturation_mensuelle` adapté)
- 1 facture par semaine ISO échue
- Prélèvement automatique sur votre carte/IBAN Stripe sous 7 jours

### Mode mission par mission (en option)
Si configuré (`mode_facturation = PAR_MISSION`), une facture est générée à chaque mission terminée. Utile pour les groupes ou EHPAD qui veulent un suivi détaillé.

## Délai de paiement

**30 jours date d'émission** par défaut (article 4.5 contrat de service). Configurable par négociation.

Au-delà de 30 jours : email de relance automatique (J+7), puis blocage de publication de nouvelles missions à J+21 (article 5.1 contrat). Réactivation immédiate à régularisation.

## Téléchargement des factures

Allez sur **Finances → Factures de commission**. Chaque facture est en PDF + XML Factur-X (conforme facturation électronique). Vous pouvez aussi consulter l'historique de prélèvements Stripe si applicable.

## Avoir / régularisation

En cas de litige résolu en faveur du soignant ou d'ajustement post-mission, Jolene émet un **avoir** (type_document = `AVOIR`) qui se déduit de la prochaine facture.

## Liens utiles

- [Pourquoi déposer mon RIB](/aide/etab-pourquoi-deposer-rib)
- [Publier ma première mission](/aide/etab-publier-premiere-mission)
- [Comment résoudre un litige](/aide/etab-resoudre-litige)$JOLENE_DOC$),

('etab-resoudre-litige', 'Comment résoudre un litige', 'ETABLISSEMENT', 'Litiges', 10, $JOLENE_DOC$## Quand un litige est ouvert contre vous

Vous recevez immédiatement un **email + push** dès qu'un soignant ouvre un litige sur une mission ou facture vous concernant. Le détail apparaît également sur votre dashboard sous la rubrique **Litiges actifs**.

## Catégories de litiges

| Catégorie | Sujet typique |
|---|---|
| **FINANCIER** | Désaccord sur facture (montant, heures comptées) |
| **PRESENCE** | Pointage, retard, oubli, durée mission |
| **CONDITIONS** | Matériel, encadrement, profession différente du brief |
| **COMPORTEMENT** | Harcèlement, discrimination, mise en danger |

Chaque catégorie a son propre flow de résolution, ses fenêtres de contestation et ses conséquences.

## Vos fenêtres de contestation côté étab

Vous pouvez vous-même initier un litige côté étab dans certains cas :

| Fenêtre | Sujet | Délai |
|---|---|---|
| **F2** | Contestation facture libéral émise par Jolene | **48 heures** après émission |
| **F3** | Contestation paiement salarié contesté par soignant | **60 jours** après date paiement |
| **Sécurité** | Comportement soignant (vol, faute professionnelle) | Sans délai |

Au-delà : impossible d'ouvrir un litige (statut figé, prescription).

## Gel de la facture pendant le litige

Lorsqu'un litige financier ou présence est ouvert, la facture concernée passe en statut **EN_ATTENTE_LITIGE** : le paiement est suspendu jusqu'à résolution.

Le **scope de gel** dépend du type et peut être modulé par l'admin :

- **MISSION_ENTIERE** (par défaut) : toutes les factures non-payées de la mission sont gelées
- **FACTURE_UNIQUE** : uniquement la facture pointée par le litige
- **PERIODE_LITIGIEUSE** (missions hebdomadaires > 7 jours) : seules les factures dont la période chevauche la période litigieuse sont gelées
- **AUCUN** : litige informatif, pas de gel financier

L'admin peut modifier le scope via la RPC `fn_admin_modifier_gel_scope_litige` avec audit `LITIGE_GEL_SCOPE_MODIFIE` et raison obligatoire.

## Processus de résolution

1. **OUVERT** → vous êtes notifié, vous pouvez répondre via la **messagerie litige** (in-app)
2. **EN_DISCUSSION** → échanges directs avec le soignant. Apportez vos preuves (planning, badge, témoignages)
3. **EN_MEDIATION** → si pas d'accord sous 5 jours, l'admin Jolene intervient comme tiers neutre
4. **RESOLU_ETABLISSEMENT** ou **RESOLU_SOIGNANT** ou **RESOLU_ADMIN** → décision actée, paiement débloqué ou ajustement effectué
5. **CLOTURE** → litige fermé, audit final, factures dégelées (statut `LITIGE_RESOLU_CONFIRME`)

## Conséquences possibles

Selon la résolution :
- **Paiement maintenu** (vous aviez raison) → la facture est dégelée, paiement normal
- **Avoir émis** au profit du soignant → ajustement sur facture suivante
- **Régularisation sociale** (cas SALARIE) → email `REGULARISATION_SOCIALE_REQUISE`, ajustement bulletin
- **Avoir + régulation commission** → la commission Jolene est aussi ajustée si la base brute change

## Ouvrir un litige depuis votre côté

Sur le détail de la mission ou facture, cliquez **Contester** :

1. Sélectionnez la catégorie
2. Décrivez précisément (date, heure, faits)
3. Joignez photos / captures / documents si pertinent
4. Ouvrir

Le soignant est immédiatement notifié, le processus de résolution démarre.

## Limites

- **3 litiges max par heure** par mission (anti-spam)
- Toute action sur litige est **auditée** dans `journaux_audit`
- Les rappels J+1, J+3, J+5 sont envoyés automatiquement si le litige reste ouvert sans activité

## Liens utiles

- [Comment gérer une absence soignant](/aide/etab-gerer-absence-soignant)
- [Comprendre la commission Jolene](/aide/etab-comprendre-commission-jolene)$JOLENE_DOC$),

('etab-gerer-absence-soignant', 'Comment gérer une absence soignant', 'ETABLISSEMENT', 'Pointage et présence', 20, $JOLENE_DOC$## Quand on parle d'absence

Une « absence soignant » couvre plusieurs cas : le soignant ne s'est pas présenté, ne s'est pas pointé, est parti avant la fin, ou il y a un désaccord entre vous et lui sur les heures réellement travaillées. Jolene distingue 4 cas avec des traitements différents.

## CAS A — Pointage partiel ou intégral existant

Le soignant s'est pointé à l'ouverture (et/ou à la fermeture). Une partie ou l'ensemble des heures sont validées. Mais les heures effectives sont **inférieures aux heures prévisionnelles** (CP5a Jolene applique la règle `GREATEST(prev, eff)` pour le calcul de la rémunération).

**Traitement automatique** : la facture est générée sur le **plancher prévisionnel** ou les heures effectives, selon ce qui est le plus haut. Si le soignant conteste, il ouvre un litige PRESENCE depuis sa mission.

Aucune action étab requise. Vous pouvez consulter le détail dans **Mission → Pointages**.

## CAS B — Aucun pointage + créneaux prévisionnels + mission passée

C'est l'**ambiguïté principale** : le soignant n'a pas pointé du tout, mais des créneaux prévisionnels existent et la mission est censée être terminée.

→ **Pas de facture auto-générée**. Le système attend votre intervention.

Une alerte UI apparaît sur le détail de la mission côté étab : « Le soignant n'a pas pointé. Que s'est-il passé ? » avec 2 boutons :

- **Le soignant ne s'est pas présenté → ABSENCE_CONFIRMEE**
  - RPC `fn_resoudre_absence_mission(mission_id, 'ABSENCE_CONFIRMEE', motif)`
  - Mission passe en statut `ABSENCE`
  - Pas de facture, pas de paiement
  - Score de fiabilité du soignant **ajusté à la baisse** (penalité absence non signalée)
  - Audit `MISSION_ABSENCE_CONFIRMEE`

- **Le soignant a travaillé mais a oublié de pointer → OUBLI_POINTAGE_VALIDE**
  - RPC `fn_resoudre_absence_mission(mission_id, 'OUBLI_POINTAGE_VALIDE', motif)`
  - Vous validez les heures prévisionnelles comme effectives
  - Facture générée normalement (ou bulletin paie si SALARIE)
  - Pas d'impact sur le score soignant
  - Audit `OUBLI_POINTAGE_VALIDE_ETAB`

## CAS C — Mission déjà en statut ABSENCE

Le soignant ou un admin a déjà acté l'absence avant que vous interveniez. La mission est verrouillée. **Aucune action possible**.

Si erreur (mission marquée ABSENCE par erreur), contactez **support@jolene.app** avec preuves : un admin peut rouvrir la mission via override avec audit.

## CAS D — Départ anticipé non signalé

Pointage d'ouverture présent, mais pas de pointage de fermeture, et la mission est terminée depuis 24h+. Soit le soignant est parti tôt sans signaler, soit il a oublié de pointer en partant.

Alerte UI étab : « Pointage de fermeture manquant. Que s'est-il passé ? » avec 2 boutons :

- **Le soignant est parti tôt → DEPART_ANTICIPE_CONFIRME**
  - RPC `fn_resoudre_absence_mission(mission_id, 'DEPART_ANTICIPE_CONFIRME', heure_depart_reelle)`
  - Heures effectives recalculées selon votre estimation
  - Pénalité score soignant
  - Facture sur les heures effectives uniquement

- **Le soignant a travaillé jusqu'au bout mais a oublié de pointer → OUBLI_POINTAGE_CONFIRME_ETAB**
  - Vous confirmez les heures prévisionnelles
  - Pas d'impact score
  - Facture normale

## Impact facturation

| Résolution | Facture libéral | Bulletin paie SALARIE |
|---|---|---|
| ABSENCE_CONFIRMEE | Aucune | Aucun |
| OUBLI_POINTAGE_VALIDE / CONFIRME_ETAB | Normale (prévisionnel ou effectif validé) | Normale |
| DEPART_ANTICIPE_CONFIRME | Heures effectives uniquement | Heures effectives uniquement |

## Impact score fiabilité soignant

`soignants.score_fiabilite` est ajusté automatiquement :

- **ABSENCE_CONFIRMEE** : −20 points
- **DEPART_ANTICIPE_CONFIRME** : −10 points
- **OUBLI_POINTAGE_VALIDE** : 0 (pas de pénalité)

Le score impacte la priorité dans les recherches futures et la confiance des étabs.

## Liens utiles

- [Comment fonctionne le pointage](/aide/comment-fonctionne-pointage) (côté soignant)
- [Comment résoudre un litige](/aide/etab-resoudre-litige)$JOLENE_DOC$),

('comment-jolene-assure-securite', 'Comment Jolene assure la sécurité de vos données', 'COMMUN', 'RGPD et données personnelles', 20, $JOLENE_DOC$## Vue d'ensemble

Jolene traite des données sensibles : santé indirectement (RPPS, profession), financières (RIB, IBAN, montants), pointage GPS, identité. La sécurité est une priorité absolue : on en parle ici sans jargon technique inutile.

## Hébergement en France / UE

Toutes les données sont hébergées chez **Supabase**, infrastructure **AWS Paris** (eu-west-3). Aucune donnée n'est transférée hors UE par défaut. Les sous-traitants extra-UE (Anthropic pour OCR docs, Stripe USA backup, Resend, Twilio, Sentry) sont encadrés par les **Standard Contractual Clauses** (SCC) RGPD et la décision d'adéquation **Data Privacy Framework** (CE 10/07/2023).

## Chiffrement

- **Au repos** : chiffrement AES-256 (Supabase RDS / AWS S3)
- **En transit** : TLS 1.3 obligatoire (HTTP rejeté sur jolene.app)
- **Bucket Storage privé** : tous les fichiers (RIB, contrats, factures, photos) accessibles uniquement par signed URLs temporaires (1 heure max)

## Row Level Security (RLS) Postgres

Toutes les **87 tables** de la base de données ont des politiques RLS strictes. Cela signifie que même un attaquant qui réussirait à exécuter une requête SQL côté client ne pourrait pas accéder aux données d'un autre utilisateur. Par exemple :

- Un soignant ne voit que ses propres factures, missions, messages
- Un établissement ne voit que ses propres soignants assignés
- Les administrateurs ont des accès supplémentaires audités

Tests cross-tenant 16/16 PASS sur les comptes audit (cf. `docs/audit-rls.md`).

## Audit log append-only

Toutes les actions sensibles sont tracées dans deux tables :

- **`journaux_audit`** : actions utilisateur et admin (3-5 ans de conservation, recommandation CNIL)
- **`invoice_audit_log`** : modifications sur les factures (10 ans, obligation fiscale L102 B LPF)

Les logs sont **append-only** : impossibles à modifier ou supprimer même par un admin (triggers DB `trg_ial_no_delete`, `trg_ial_no_update`).

## Sauvegardes

**Supabase Pro tier** : sauvegardes quotidiennes automatiques + Point-In-Time Recovery (PITR) sur 7 jours.

- **RPO** (Recovery Point Objective) : 5 minutes
- **RTO** (Recovery Time Objective) : 4 heures
- Test PITR trimestriel sur projet clone

Détail : `docs/procedure-backup.md`.

## Anti-bot et anti-fraude

- **Captcha Cloudflare Turnstile** sur l'inscription, le login, le reset password, la vérification RPPS
- **Rate-limiting** sur les edge functions sensibles (5 inscriptions / 10 min / IP, 3 litiges / heure / mission, etc.)
- **Triggers anti-seed** sur factures et missions : refusent les INSERT incohérents (montants vs durée)
- **Détection fraude pointage** GPS : alerte téléportation, alerte hors périmètre

## Authentification

- **Mot de passe** : 8 caractères minimum, mélange majuscules/minuscules/chiffres/spéciaux
- **MFA** disponible (TOTP, à activer dans le profil)
- **JWT Supabase** courte durée (1h) avec refresh token
- **Pro Santé Connect** disponible pour les soignants (e-CPS / CPS)

## Monitoring d'erreurs

**Sentry** capture toutes les erreurs runtime côté frontend et edge functions. Source maps prod uploadées pour symbolisation. Alertes admin sur erreurs critiques.

## Notifications sécurisées

- **Web Push VAPID** (RFC 8030) pour les notifications navigateur (pas de Firebase Cloud Messaging par défaut)
- **Email Resend** avec DKIM + SPF + DMARC vérifiés sur jolene.app
- **SMS Twilio** uniquement pour urgences (mission urgente, litige, problème pointage)

## Supprimer mon compte

À tout moment dans **Profil → Confidentialité → Supprimer mon compte**. Anonymisation immédiate de toutes les données identifiantes, conservation des données légalement obligatoires (factures, audit) pour les durées réglementaires.

## Plainte

Si vous estimez que Jolene ne respecte pas vos droits :
- **DPO Jolene** : support@jolene.app
- **CNIL** : cnil.fr/plaintes

## Liens utiles

- [Mes droits RGPD](/aide/mes-droits-rgpd)
- [Mes droits RGPD soignant](/aide/mes-droits-rgpd-soignant)$JOLENE_DOC$),

('cgu-jolene', 'Résumé des CGU Jolene', 'COMMUN', 'Légal', 50, $JOLENE_DOC$## Pourquoi cet article

Cet article résume les Conditions Générales d'Utilisation (CGU) Jolene en langage simple. Pour la version juridique intégrale, consultez [/legal/cgu](/legal/cgu).

En cas de divergence entre ce résumé et la version intégrale, **la version intégrale fait foi**.

## Qui peut s'inscrire

**Soignants** : professionnels de santé majeurs (18 ans minimum), titulaires d'un diplôme reconnu, inscrits à leur ordre quand applicable. RPPS vérifié pour la plupart des professions, diplôme + identité pour AS/AES/préparateurs en pharmacie.

**Établissements** : structures de santé légalement constituées en France, autorisées à employer ou faire intervenir des professionnels de santé (cliniques privées, EHPAD, hôpitaux publics, HAD, pharmacies d'officine, centres de santé, etc.). SIRET valide vérifié contre INSEE.

## Modèle économique

Jolene perçoit une **commission** sur chaque mission réalisée par votre intermédiaire (taux par défaut 15 %, négociable par étab ou groupe santé). La commission est :

- Due par l'**établissement** (pas par le soignant)
- Calculée sur le **montant brut total** de la mission
- Figée à l'assignation
- Facturée mensuellement ou hebdomadairement selon votre configuration
- Payable à 30 jours date d'émission

Pour les soignants : pas de frais sauf option Defacto J+2 (~1-3 % de commission factor).

## Vos droits utilisateur

**RGPD complet** :
- Accès à toutes vos données (export JSON 21 catégories pour soignants)
- Rectification depuis votre profil
- Suppression compte (anonymisation immédiate, conservation légale factures 10 ans)
- Portabilité (export JSON portable)
- Opposition (préférences notifications, contact DPO)

Cf. [Mes droits RGPD](/aide/mes-droits-rgpd).

## Vos obligations utilisateur

**Soignants** :
- Fournir des informations **exactes** (RPPS, identité, diplômes, IBAN)
- Maintenir vos documents à jour (RCP, attestations)
- Respecter le Code du travail (repos, plafond hebdo) et la déontologie de votre profession
- Pointer honnêtement vos heures
- Déclarer vos revenus (URSSAF si libéral, fiscalité personnelle)

**Établissements** :
- Fournir des informations exactes (SIRET, raison sociale)
- Décrire les missions sincèrement (taux, conditions, matériel)
- Respecter les minima conventionnels (CCN applicable + planchers Jolene 25/25/50 %)
- Déclarer les heures réellement travaillées dans les 48h
- Pour SALARIE : être employeur en bonne et due forme, uploader le contrat de travail (cf. article dédié)
- Payer les sommes dues (commissions Jolene, salaires soignants, factures honoraires)

## Responsabilité

**Jolene** est :
- Intermédiaire technique (mise à disposition de la plateforme)
- Mandataire de facturation pour les libéraux (art. 289 I-2 CGI)
- Service automatisé de bulletin de paie pour les salariés (art. R3243-1 CTW)

Jolene **n'est pas** :
- Employeur des soignants (les étabs sont seuls employeurs SALARIE)
- Société de portage salarial
- Entreprise de travail temporaire
- Garante de la qualité des prestations effectuées par les soignants

La responsabilité de Jolene est plafonnée selon les conditions du contrat de service avec votre étab (article 9 du contrat) ou des CGU pour les soignants.

## Modifications

Jolene peut modifier les CGU à tout moment. Toute modification substantielle est notifiée par email avec **préavis de 30 jours** et requiert une nouvelle acceptation électronique pour continuer à utiliser la plateforme. Si vous n'acceptez pas, vous pouvez résilier votre compte sans pénalité.

## Résiliation

- **Soignant** : suppression libre du compte à tout moment (anonymisation immédiate, conservation factures 10 ans)
- **Établissement** : résiliation avec préavis 30 jours (article 8.2 contrat). Manquement grave → résiliation immédiate après mise en demeure 8 jours non suivie d'effet.

## Droit applicable

Droit français. **Tribunaux compétents : Paris**.

## Pour aller plus loin

- [Conditions générales d'utilisation intégrales](/legal/cgu)
- [Politique de confidentialité](/legal/confidentialite)
- [Mentions légales](/legal/mentions-legales)
- [Contacter le support](/aide/contacter-support)$JOLENE_DOC$)
ON CONFLICT (slug) DO NOTHING;
