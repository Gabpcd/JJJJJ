# Pilote documentaire F1 staging — candidat exécutable, activation bloquée

Ce lot contient le runner complet, ses deux templates SQL et son workflow manuel.
Il ne modifie aucun produit et n'a effectué aucune mutation cloud. Le contrat
`f1-cloud-readiness.json` reste `ready:false` : il faut une revue, la fusion et
le déploiement des correctifs avant de renseigner les preuves d'activation.
Les tests Node sont raccordés à Validate PR, sans credentials et indépendamment
du gate du workflow manuel.

## Parcours et effets bornés

Destination unique : `mejpriaetwgtcstbgfid`. Workflow manuel sur main exact,
SHA d'approbation égal au SHA checkout et au main GitHub relu avant Auth,
verrou `jolene-supabase-staging-writes`, timeout job 35 min. Aucun reset,
sync, migration produit, déploiement, webhook ou rotation de secret.
Le premier step fixe l’origine temporelle ; installations et build sont bornés
avant toute fixture. Juste avant Auth, le runner exige encore 19 minutes sur les
35 : pilote borné à 14 minutes, étape always à 4 minutes et marge de preuve.
La clôture limite chacun de ses appels HTTP à 20 s (huit Auth et deux SELECT au
maximum). Aucun Promise.race ni finalisation parallèle à une tâche UI en cours.
Un arrêt forcé du runner reste un échec ambigu qui nécessite le contrôle indépendant.

Le manifeste privé est écrit et synchronisé avant le premier effet. Il réserve
sept UUID (S/E/admin, mission, équipe, litige, présence) et trois identités
confirmées `example.invalid`, TEST et marquées par run/SHA. Seuls S/E se connectent
à l'UI ; l'admin SQL n'a aucune session navigateur. Les claims admin, le mandat
et l'historique sont synthétiques, sans preuve de signature humaine, MFA,
qualification, attribution ou pointage réel. Les profils restent non vérifiés,
l'établissement EN_ATTENTE sans droit de publication.

1. Préflight indépendant des sources, catalogue, Edge et canaux ; trois créations
   Auth sans invitation, puis le SQL `prepare.sql` exact et revu.
2. Mission libérale EN_COURS : deux créneaux prévisionnels de 4 h sur deux semaines,
   un effectif historique fermé de 4 h. Première facture hebdomadaire : 80 €
   (4 × 20), commission 12 € HT, mission globale 160 € / 24 € de commission HT.
3. Un seul POST réel `generate-invoice` pour l'original, puis lecture indépendante
   des lignes, de l'unique version documentaire et des métadonnées Storage.
4. Correction canonique `ANNULER_REEMETTRE`, payload UI 4 h / taux 18. Présence
   synthétique de 4 h réservée, créée sans arrivée/départ/validation ; lien litige
   et heures ajustées 4 vérifiés. Original REMPLACEE, nouvelle FACTURE 72 €,
   commission d'origine REMPLACEE et nouvelle commission 10,80 HT / 2,16 TVA /
   12,96 TTC. Mission globale attendue 144 € / 21,60 HT, indépendamment des RPC.
5. Un seul POST de génération du remplacement. Deux XML 380, aucun avoir 381,
   paiement, passage PAYEE ou TERMINEE. Heures seules et finale sont hors périmètre.
6. Dix contextes isolés (deux rôles × cinq formats) : stockage vierge, refus
   du bandeau via le vrai bouton « Refuser », vrai formulaire, lien SPA
   du dashboard, les DEUX factures puis quatre téléchargements PDF par contexte
   (originale/remplacement avant/après recharge), soit 40 PDF. Aucune génération
   depuis l'UI. Les navigations HTML sont une avant recharge et deux après : cela
   ne désigne pas le nombre de factures.
7. Huit lectures Storage authentifiées supplémentaires : PDF/XML × deux pièces ×
   deux rôles. SHA256/taille/MIME, analyse XML structurée, rendu/analyse PDF.js
   des vrais octets. L'XML n'a pas de bouton produit : sa preuve reste API.
8. Tous contextes et tâches réseau sont fermés avant logout global et ban des
   trois Auth du manifeste. `finally` et étape CI `always` obtiennent un SELECT
   neuf même après erreur. Factures, commissions, versions, audit, mandat,
   présence synthétique et objets Storage sont conservés ; aucun DELETE financier.

Chaque effet possède une intention durable privée avant appel. Timeout/réponse
perdue reste ambigu, sans retry ni nouvelle génération. La reprise finalize ne
rejoue pas une finalisation déjà tentée : elle lit l'état et signale l'incertitude.
Un runner détruit sans finalisation exige une intervention ciblée à partir du
run/SHA et du marqueur propriétaire ; aucun nettoyage global/prefixe n'est fourni.
Les JWT émis restent des jetons stateless jusqu'à expiration : ban, logout et
zéro session ne prouvent pas une révocation cryptographique instantanée de tous
les JWT. Les fichiers privés restent sur le runner éphémère et ne sont pas publiés.

## Réseau et contrôle des conséquences

La route navigateur transmet les vraies réponses Auth/REST/Storage sans mock.
Corps des écritures et IDs sont exacts, budgets propres à chaque contexte.
Les téléchargements signés peuvent ne pas porter Authorization : seule l'URL
exacte reçue du POST de signature autorisé est acceptée. Aucun envoi de message,
invitation, paiement, validation de présence ou note n'est autorisé.

Le chat monté dans les détails a des effets réels explicitement admis : une
conversation propre au couple et à la mission, zéro message, deux presence_status,
zéro typing. Chaque contexte appelle au plus deux ouvertures/marquages et dix
updates de présence ; les lectures sont bornées aux objets synthétiques. Les
appels de tableau de bord ajoutent cinq audits connexion par rôle et cinq audits
de consultation établissement, comparés à l'état avant UI. Les WebSockets sont
fermés volontairement : l'indicateur d'alerte près de la cloche n'est pas masqué.
Ce lot ne valide ni Realtime, ni push, ni messagerie interactive.

Le litige initie exactement UNE requête interne pg_net vers notify-support staging.
Le catalogue exige queue vide avant Auth et chaque transaction. Prepare exige
encore zéro queue ; correction exige la queue totale de taille un, l'URL et le
corps exacts, puis capture son ID avant COMMIT. La réponse doit être 200, sans
erreur/timeout, `success/skipped=true,reason=test_account`. Quatre skips email
TEST et un skip support sont rapprochés ; aucune queue email ou retry financier.
La génération pg_net est interdite : generate_invoice_url doit rester absente et
le reçu canonique ne doit contenir aucun request ID de génération.

Les SELECT vérifient séparément paiements_escrow, paiements_soignant,
paiements_mission et stripe_transfers à zéro. Les factures honoraires et commissions
sont reliées par les IDs exacts, montants/statuts/périodes. L'original et sa version
restent identiques (hors passage REMPLACEE), puis les empreintes des deux ensembles
financiers, versions et invoice_audit_log restent identiques après l'UI/finalisation.
Toute dérive catalogue ou concurrence externe observée fait échouer ; elle n'est
pas absorbée en rafraîchissant automatiquement les empreintes.

## Preuve expurgée et préconditions restantes

Le dépôt est public. Seuls `result.json`, `finalization.json` fermés et les portions documentaires PNG
synthétiques sont téléversables. Aucun manifeste, mot de passe, session, URL signée,
corps SQL/API, PDF texte, HAR, trace ou log fournisseur. Les durées génération et
40 téléchargements frontend + 8 lectures Storage sont des observations ; aucun
seuil de capacité nationale n'est inventé. Le rapport valide la matrice exhaustive
format/rôle/slot/reload, les hashes et tailles contre les lectures Storage.
La clôture conserve le nombre exact d’Auth propres bannis, zéro session/admin
actif et le booléen de rétention financière vérifiée. Une préparation partielle
ne devient pas une preuve de rétention complète. Les échecs de clôture et de
vérification restent distincts, codés et bloquants, même si le SELECT suivant passe.

Le diagnostic conserve phase locale, rôle, format, catégorie, chemin de route
connu sans valeurs/query, statut et temps relatif, empreinte d'exception. Les
noms de route inconnus sont `other`. Toutes erreurs restent bloquantes. Les copies
privées et la projection publique fermée ne contiennent pas d'identité ni de secret.

Avant activation, après fusion :

- Attendre aussi le correctif heures seules en cours, sans élargir le pilote
  4 h / taux 18 à ce cas. Vérifier le déploiement staging du correctif commission, helper MD5
  `c793ac81eaef0fe18fb5920c9264c675` (déjà exigé AVANT Auth puis dans SQL).
  Revoir le vrai delta depuis les relevés anciens, puis fixer les trois empreintes
  routines/ACL, triggers public/private/Auth/Storage et colonnes/defaults.
- Actualiser generate-invoice par le chemin manuel relu, sans reset/webhook.
  Le staging observé avant ce lot reste v15 ; ce n'est pas le générateur corrigé.
  Fixer version/JWT/ezbr_sha256 exacts de generate-invoice, send-email, notify-support,
  après vérification des sources/classification TEST. Ne pas réutiliser une
  ancienne empreinte simplement parce que le nom de fonction correspond.
- Fixer les SHA256 des cinq sources produit contrôlées par loadContractF1 ; le
  checkout propre et le build doivent correspondre au main exact approuvé.
  Vérifier aussi les fichiers du générateur/font et leur bundle déployé dans la
  revue de source ; le blob TS seul ne prouve pas son déploiement cloud.
- Réexaminer Auth (aucun hook externe/SMTP personnalisé, emails de sécurité off),
  canaux TEST, bucket privé et policies Storage donnant S/E leurs seuls documents,
  rétention et finalisation. Les booléens de readiness sont un contrat de revue,
  pas une sonde dynamique du plan de contrôle Auth.
- Exiger zéro cron actif/en cours, queue pg_net vide, URL régénération absente et
  destination support exacte. Ces conditions sont vérifiées à nouveau à l'exécution.
- Revue indépendante du paquet et de ces valeurs avant tout dispatch main séparé.
  La CI SQL réelle verte du correctif n'est pas l'exécution des deux templates
  cloud avec Auth/Storage/Edge ; leurs parseurs locaux ne remplacent pas ce pilote.

Le workflow ne peut exister en dispatch avant sa fusion. Il ne prend aucune ref
PR. Après activation revue sur main, la commande technique est :
`gh workflow run f1-cloud-staging.yml --ref main -f approved_sha=<SHA-main-revu>`.
Ce document n'autorise pas son lancement. Un échec impose diagnostic et nouvelle
coordination, jamais un rerun automatique.

## Validation locale du candidat

73 tests Node hors réseau ; un test navigateur PDF.js réel sur les octets produits
par le vrai handler en IO simulées ; parse pglast de 28 statements et 6 blocs DO,
actionlint et typecheck E2E ciblé. La navigation locale utilise le build UI
6bc862cc91e5f5a989cfc165b803964f596defb2 servi sur 18483, distinct du handler Node
corrigé utilisé pour les octets PDF/XML. Dix parcours verts depuis un stockage vierge, 40 PDF, 80 captures par portions,
zéro requête non couverte par le contrat réseau, zéro erreur console/page.
Chaque bouton PDF reçoit un clic normal après défilement dans le viewport
habituel. Les portions titre/totaux/originale/remplacement sont cadrées après
défilement réel et un hit-test de leurs quatre coins ; aucune barre fixe ni CSS
n’est masquée. Les premières captures de carte longue conservées pouvaient être
partiellement recouvertes ; elles ne constituent pas les captures finales.

Les réponses Auth/REST/Storage de cette simulation sont fictives, le futur pilote
connecté n'en fabrique aucune. L'ancien helper de simulation a été réutilisé sans
modifier le produit. Les premières erreurs de préparation sont conservées hors
patch : ESM du dossier, CORS de pagination, métadonnées maybeSingle et référentiel
documents manquant, ainsi qu’une passe interrompue après un probe loopback
non autorisé par le sandbox. Elles ne sont pas comptées parmi les dix succès finaux.
Pas d'Edge cloud, SQL réel du candidat, paiement, fournisseur, XSD/Schematron,
conformité PDF-A/Factur-X hybride, restauration ou appareil physique prouvé ici.
