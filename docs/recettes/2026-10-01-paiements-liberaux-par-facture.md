# Paiement libéral depuis une pièce identifiée — 1er octobre 2026

Base : `1913e57b3835c2aa75dd252769867a518e12727a`. Correction frontend distincte des gardes SQL et Connect, sans migration ni recalcul financier.

Sur le détail d’une mission libérale assignée, EN_COURS ou TERMINEE, le composant de paiement oriente l’établissement vers Facturation avec `tab=missions-a-payer&mission=<id>`. Il ne transmet plus l’estimation globale de mission à une déclaration ou à Stripe. La route et les permissions établissement existantes restent nécessaires ; ce lien n’est pas monté dans la vue admin. La vue soignant reste inchangée.

Facturation conserve sa source documentaire `fn_obligations_financieres`. Le filtre ne concerne que la liste des échéances soignants ; les indicateurs et l’historique restent explicitement globaux. Le filtre survit au rechargement et au retour Stripe, et son retrait est visible. Une ligne libérale sans facture identifiée, ou avec régime inconnu, ne permet aucun règlement. Un retour Stripe sans référence de facture reste en attente de rapprochement ; il ne peut plus être confirmé par le dernier transfert global d’une autre période. Le retour nominal vérifie la référence de facture et la mission.

L’historique actif est lu sous les RLS existantes, pour les missions des obligations uniquement : projection `id, mission_id, facture_honoraire_id, statut`, statuts DECLARE/CONFIRME/CONTESTE/RESOLU, lots de 100 missions, pages de 200 lignes triées par ID. Le compteur exact doit rester stable, les IDs uniques et chaque ligne conforme. Les limites de 1 000 missions / 10 000 lignes, une page manquante, un compteur absent ou une erreur ferment l’écran avec reprise, sans résultat financier partiel. Elles bornent cette lecture ; elles ne constituent pas une preuve de capacité nationale.

Une ligne active sans facture entraîne « À rapprocher » pour sa mission libérale. Le montant de la pièce reste consultable, mais il n’est pas présenté comme un nouveau solde dû ; les agrégats concernés ne présentent aucun total payable. Aucune attribution automatique ni soustraction n’est effectuée. Les messages `LIBERAL_FACTURE_REQUISE` et `PAIEMENT_HISTORIQUE_A_RAPPROCHER` orientent vers la pièce ou le rapprochement. Une lecture de mode invalide ne devient jamais un mode salarié par défaut.

Le salarié conserve la saisie du net du bulletin officiel, le refus des paiements partiels et l’escrow existant. Les arrêts maladie, les copies officielles, les calculs, le RPC des obligations et `paiementsData` ne sont pas modifiés.

## Vérifications locales

- 94 tests unitaires ciblés : composant paiement, permissions/scope, refus de déclaration, messages et 21 cas de pagination/validation.
- Typecheck applicatif et typecheck ciblé E2E verts ; build web compilé sur API loopback fictive, sans télémétrie distante.
- 25 scénarios Playwright, un seul worker, zéro retry/skip : cinq cas sur iPhone, Android, iPad portrait, iPad paysage et ordinateur.
- Virement TERMINEE et Connect EN_COURS : vraie navigation vers les pièces 60 et 80 euros de deux semaines closes distinctes, ancienne facture REMPLACEE exclue, sélection et payload de la facture 60, Annuler sans effet, refus serveur affiché, rechargement et retrait du filtre. L’estimation 160 ne devient jamais un ordre libéral.
- Retour Connect simulé avec facture : réponse ECHOUE vérifiée par lecture ciblée ; sans facture : attente explicite et aucun lookup global. Aucun paiement fournisseur n’est exécuté.
- Historique : 201 lignes avec la ligne sans pièce en seconde page ; page omise → erreur et Réessayer ; pages complètes après rapprochement fictif → actions disponibles ; pièce absente → actions refusées.
- Salarié : champs du bulletin initialement vides, geste de déclaration partielle refusé avant RPC, montant exact saisissable ; escrow conservé après rechargement.
- Le scénario documentaire qui déclenchait auparavant un paiement mission-only sans facture est remplacé par son refus avant Edge. Le vrai handler documentaire exécuté dans son banc local conserve son témoin Unicode 422 et zéro upload/émission ; aucune invocation cloud.

Preuves : `/private/tmp/jolene-paiements-liberaux-preuves-20261001/validation.json`, `matrice-finale/results.json`, 35 captures PNG et `SHA256SUMS`. Le manifeste distingue sources, build servi et journaux. Les premiers rouges sont conservés : modale d’évaluation non fermée dans le scénario initial, ressources externes non encore neutralisées et assertion de bouton salarié désactivé alors que le comportement conservé refuse au clic. Ils ne sont pas comptés dans la passe finale.

Le réseau Auth/REST/Edge est explicitement simulé. Les ressources Google Fonts et le script Stripe sont neutralisés localement ; les autres destinations externes sont refusées. Le seul log navigateur attendu dans le cas négatif est vérifié exactement : refus de l’historique incomplet. Aucun email, SMS ou signature n’est déclenché. Les WebSockets sont fermés : l’indicateur de notifications peut signaler cette coupure, et Realtime/push ne sont pas validés. Les captures sont des vues normales, sans CSS masqué ; une carte longue peut être partiellement hors champ, tandis que les gestes sont exécutés dans le viewport.

Il reste nécessaire d’intégrer les gardes backend, de passer la revue et la CI de l’union, puis d’exécuter séparément les circuits fournisseurs TEST autorisés. Cette simulation ne prouve ni paiement réel, ni appareil physique, ni capacité en charge.
