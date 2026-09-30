# F1 — échéance hebdomadaire sous transaction annulée

Ce lot ajoute une seule suite SQL à la liste existante de `validate-pr` et une
simulation des deux écrans de facturation. Aucun mode manuel, nouveau runner,
cron F, Edge, Storage, paiement, remboursement ou fournisseur n'est exécuté.
Le scénario de charge F et son ancien seed restent désactivés.

## Exécution prévue

`tests/security/facturation-hebdomadaire-f1.test.sql` passe dans le job
`Migrations + sécurité SQL (transaction annulée)` : cible staging exacte,
verrou `jolene-supabase-staging-writes`, migrations PR et savepoint par suite,
puis ROLLBACK. Le déclenchement existant exige une PR avec migration ; une PR
contenant seulement ce test ne l'exécute pas. Aucun workflow n'est lancé par
ce lot. Intégrer le test au lot de migrations relu avant la preuve distante.

La fixture utilise les branches de maintenance SQL existantes, sans désactiver
un trigger ni poser de GUC de contournement. Deux lignes Auth sont insérées en
SQL sous rollback, sans session, mot de passe ou appel Auth HTTP. Le garde
refuse tout trigger utilisateur INSERT sur auth.users et tout cron actif.
Un IDE LIBERAL test sans vérifications, un établissement CLINIQUE_PRIVEE test
EN_ATTENTE et des canaux de notification tous false sont créés. Aucun document,
SIRET vérifié, mandat, validation de TVA ou attribution applicative n'est créé.

La mission synthétique commence EN_COURS, déjà affectée par la branche SQL de
maintenance, avec un créneau futur de quatre heures. Son créneau est déplacé
vers la semaine passée puis un second créneau futur et un effectif fermé sont
insérés via les vrais triggers. Le passé direct à l'INSERT reste interdit.
Les dates suivent la semaine du serveur UTC et évitent les jours fériés sans
modifier le calendrier. Cette préparation ne prouve pas le parcours temporel
réel d'une mission ni son éligibilité documentaire.

## Assertions

- Snapshot indépendant : deux créneaux de quatre heures à20€, net160€, pas
  d'IFM/ICP ; commission globale24€ HT +4,80€ TVA =28,80€ TTC.
- Semaine passée : effectif fermé4h, ratio0,5 et honoraires80€. Pointage ouvert
  et montant inventé81€ refusés ; aucune neutralisation du garde anti-seed.
- Une facture originale intermédiaire BROUILLON est émise avec deux références
  fictives non vides. Le test ne crée ni ne lit d'octets PDF/XML.
- Commission12€ HT +2,40€ TVA =14,40€ TTC ; le second appel retourne le même ID
  et une seule ligne, sans modifier la mission. La réémission est refusée.
- Refus du rôle non-service, de référence XML vide et de période chevauchante.
- Deux notifications non expédiées, exactement trois audits honoraires,
  aucun email, remboursement, cession, escrow ou override de fixture.
- Une sentinelle JF101 exacte annule le sous-bloc ; les zéros Auth, profils,
  mission/créneaux, finances, notifications, préférences, audits, conformité et
  suivi_conversion_3200h sont ensuite vérifiés. Aucun journal n'est supprimé.

Les corps staging lus le30/09 à15:52/15:54 puis16:38 montrent les branches
externes inactives : non urgente, statut inchangé, FACTURE/ORIGINALE, privée,
intermédiaire, defacto_opt_in=false, litige NULL, jamais PAYEE ou AVOIR.
La resynchronisation écrit aussi les compteurs du profil et le suivi3200h ;
conformité/suivi n'ont pas de triggers. Les IDs observés utilisent UUID, sans
séquence sur ce périmètre. Les catalogues lisibles sont conservés dans
`/private/tmp/jolene-F1-catalogue-{lecture,complement,transitif,compteurs,compteurs-suite}-20260930.json`.

Le défaut conditionnel SD/JOL du trigger de numérotation est traité dans un lot
produit distinct. Ce test ne le contourne pas et peut échouer s'il reste
atteignable sur le catalogue d'exécution. Il ne vérifie ni allocation concurrente
des numéros, ni isolation multi-session, ni mandat/TVA/qualification, ni livraison
de documents, ni résultat Stripe/Chorus/Defacto, ni capacité nationale.

## Preuves locales et reste à faire

Pglast accepte8 instructions SQL et1 bloc PL/pgSQL ;7 listes de colonnes INSERT
sont comparées au catalogue lu. Actionlint, `tsc -b`,17guards et diffcheck passent.
Relecture croisée bornée du SQL sans P1/P2, distincte d'une revue B8. Aucun SQL
de cette suite n'a encore été exécuté dans PostgreSQL.

`e2e/recette-complete-facturation-f1.spec.ts` simule un honoraire80€ à vérifier
et une commission14,40€ avec période visible, pour soignant et établissement,
avant/après reload. Tous les WebSockets métier restent fermés ; aucun paiement,
validation, téléchargement ou appel fournisseur n'est cliqué. Toutes les
erreurs console/page et requêtes inconnues restent bloquantes.

Les tentatives de préparation Vite sont conservées, pas présentées comme une
recette finale : deux passes desktop0/2 (HMR/date longue), puis cinq formats5/10
(deux libellés mobiles différents et trois erreurs HMR). L'assertion reconnaît
les deux libellés existants « Valider »/« Tout est correct ». L'exception HMR
provisoire a été retirée ; la preuve finale doit utiliser un build compilé de
l'intégration complète. Le typecheck E2E de cette ancienne branche rencontre
le TS2769 du helper déjà corrigé séparément par941d04e1 ; ce correctif n'est pas
dupliqué ici. Rejouer le typecheck et les10 cas sur le SHA d'intégration annoncé
avant de déclarer les cinq formats validés pour F1.

Préparation filtrée : dossier racine
`audits/2026-09-30-preparation-nationale/f1-sql-preparation/`, avec manifeste
SHA256. Aucun push, dispatch ou nouvelle exécution staging n'est effectué.
