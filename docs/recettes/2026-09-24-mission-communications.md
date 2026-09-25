# Recette simulée mission et communications — 24 septembre 2026

## Portée

Recette du frontend réel dans Playwright, avec réponses API fictives et état partagé entre deux contextes authentifiés. Aucun compte, SMS, email, notification, virement ou paiement réel n'est créé. Les API inconnues retournent une erreur 501 et font échouer le contrôle final ; les requêtes hors localhost sont bloquées et journalisées. Les seuls hints HTML `preconnect`/`dns-prefetch` sont retirés pour éviter les connexions anticipées qui échappent au routage HTTP. WebSockets fermés, service workers bloqués, aucun globalSetup, un worker, zéro retry automatique.

La matrice finale a réussi : **55/55 tests, zéro ignoré, zéro échec, zéro flaky**, en 9 min 10 s sur le build statique local `http://127.0.0.1:8892`, le 24 septembre 2026. Chaque scénario s'exécute une seule fois, sans retry automatique.

| Format | Moteur et viewport | Résultat |
| --- | --- | --- |
| iPad portrait | WebKit 820×1180 | 11/11 |
| iPad paysage | WebKit 1180×820 | 11/11 |
| iPhone | WebKit 390×844 | 11/11 |
| Android | Chromium 412×839 | 11/11 |
| Ordinateur | Chromium 1440×900 | 11/11 |

Les 55 journaux ont été relus automatiquement : aucune API inconnue, aucune erreur JavaScript. Les tentatives externes vers Google Fonts et Stripe.js ont été bloquées. Résultat complet local : `/private/tmp/jolene-recette-mission-communications-final8892/results.json` ; [résumé des 55 cas](2026-09-24-mission-communications-resultats.json).

Après alignement du seul champ de fixture `heures` sur la définition SQL de Facturation, le parcours libéral complet a été rejoué en ordinateur : **1/1 réussi**, en 30,2 s. Résultat : `/private/tmp/jolene-recette-mission-alignement-final8892/results.json`. Ce recontrôle ne s'ajoute pas aux 55 scénarios distincts de la matrice.

## Scénarios et assertions

| Scénario | Gestes vérifiés et résultat attendu |
| --- | --- |
| Mission médecin libéral en clinique | Ouvrir le détail, vérifier et confirmer la candidature ; doubleclic créant une seule candidature avec créneaux exacts ; accepter côté établissement, état ASSIGNEE et contrat créé. |
| Deux signatures OTP | Consentement requis ; un SMS simulé par signataire ; saisie réelle dans l'UI ; statuts SIGNE_SOIGNANT puis SIGNE_COMPLET ; certificat affichant les deux validations et PDF effectivement téléchargé. |
| Pointage | Code incorrect refusé et message actionnable ; arrivée 09h00, pause 13h00, reprise 13h30, départ 17h00 : deux segments effectifs de 4h et 3h30 ; validation et notation établissement, puis clôture par confirmation UI. |
| Facture et revenus | Après clôture/validation, injection explicite de la réponse serveur d'émission ; facture SIM-HON-2026-0001, montant 640 €, présente dans Mes gains et Facturation établissement, régime «Contrat libéral». |
| Erreurs de signature | Session expirée, 503 à l'envoi, OTP incorrect avec tentatives restantes, OTP expiré, renvoi puis doubleclic sur signature : une seule signature enregistrée. |
| Mission salariée | Contrat SALARIE même si profil libéral ; panneau DPAE, préparation fictive, numéro incorrect refusé, numéro fictif enregistré, deux signatures OTP et certificat. Ce cas ne prétend pas couvrir l'émission de paie. |
| Notifications, deux rôles | 503 distinct d'une liste vide, reprise ; échec marquage lu conservant l'état non lu ; échec suppression conservant la notification ; suppression réussie produisant ensuite l'état vide. |
| Conversations, deux rôles | 503 de liste et 503 des identités présentés comme erreurs récupérables ; reprise sans faux interlocuteur Jolene ; recherche, ouverture, lecture, retour et archives en lecture seule. |
| Historique, deux rôles | 503 distinct de «Aucun message» ; reprise conservant l'URL de conversation ; message fictif retrouvé. Aucun envoi de message. |

640 € correspond au plancher prévisionnel 8h×80 €. La mission prévoit 09h–17h sans pause prévue ; les 7h30 effectives ne diminuent pas ce plancher. Sources locales lues : `CLAUDE.md:346`, `supabase/schema/public.sql:1280` et `supabase/schema/public.sql:57552`. La durée `heures` de la réponse Facturation a été alignée à 8h, car cette RPC calcule la durée bornée par la période de facture (`supabase/schema/public.sql:43722`), distincte des 7h30 effectives. Ces fonctions SQL ne sont pas exécutées par cette recette.

## Corrections produit issues des constats

- `PointageRotatifSoignant.tsx` : le code invalide/expiré donne maintenant une consigne utile pour demander le code actuel à l'établissement.
- `PageNotifications.tsx` : erreur de chargement et bouton Réessayer ; aucune fausse notification lue après échec de mise à jour ; réponses obsolètes ignorées au démontage.
- `PageMessagerie.tsx` : erreurs récupérables pour liste, identités et historique ; passage liste/fil sur les écrans inférieurs à 1024px, largeur de liste bornée et panneau de fil réductible. Le contrôle vérifie aussi que le bouton Envoyer n'est pas coupé par un ancêtre en overflow.

Les trois faux états vides ont été reproduits avant correction : traces, captures et ARIA dans `/private/tmp/jolene-recette-communications-before`. Le clipping iPad a été identifié sur la capture d'un test métier pourtant vert ; il est corrigé puis revérifié par capture et assertion géométrique.

## Preuves et limites

Fichiers tests : `e2e/recette-complete-mission.spec.ts`, `e2e/recette-complete-communications.spec.ts` ; fixtures strictes dans `e2e/helpers/recette-complete-mission.ts` et `e2e/helpers/recette-complete-communications.ts`.

Chaque étape importante conserve une capture, un instantané ARIA et un journal des réponses/actes simulés. Les fichiers PDF de certificats sont conservés avec les résultats.

Captures iPad inspectées :

- [Messagerie avant correction : bord droit coupé](assets/2026-09-24-mission-communications/messagerie-ipad-portrait-avant.png)
- [Messagerie après correction : fil et bouton Envoyer complets](assets/2026-09-24-mission-communications/messagerie-ipad-portrait-apres.png)
- [Messagerie en paysage : liste et fil côte à côte](assets/2026-09-24-mission-communications/messagerie-ipad-paysage.png)
- [Certificat des deux signatures](assets/2026-09-24-mission-communications/mission-certificat-ipad-portrait.png)
- [Deux segments effectifs avec pause de trente minutes](assets/2026-09-24-mission-communications/mission-pointages-ipad-portrait.png)
- [Facture de 640 € dans l'espace établissement](assets/2026-09-24-mission-communications/mission-facture-ipad-portrait.png)

Cette recette prouve les transitions et rendus frontend face aux réponses simulées. Elle ne valide pas les règles SQL/RLS, la délivrance SMS/email/push, la génération serveur asynchrone des factures, les commissions, Stripe/webhooks, les virements, les bulletins salariés ni un binaire natif distribué. L'inscription et le login sont couverts par les autres lots ; ici les deux sessions sont initialisées dans la fixture.

Contrôles déjà exécutés : typecheck `tsc -b` réussi ; garde messagerie existante Vitest 7/7 ; découverte communications 12/12 desktop+iPad ; contrôle responsive rempli 6/6 ; probe métier statique iPad 3/3. Ces nombres sont distincts de la matrice finale.
