# Diagnostic financier documentaire — 1 octobre 2026

Le bouton admin « Lancer le diagnostic » échouait sur `column mc.fin_le does not exist`. La table `mission_creneaux` porte `debut` et `fin`. En outre, comparer une pièce rectifiée au planning courant ou au montant global d'une mission aurait produit des alertes trompeuses après une correction documentaire.

## Comportement retenu

Le contrôle des honoraires compare chaque facture active à ses propres heures et taux figés, avec l'arrondi monétaire et le seuil d'écart du diagnostic existant. Deux pièces de 60 € et 80 € ne se comparent jamais à l'estimation globale de 160 €. Un montant de 90 € avec les données figées 4 h × 20 € est signalé avec un écart de 10 €.

Les avoirs et compléments sont des deltas monétaires : ce contrôle ne prétend pas les vérifier à partir d'une quantité et d'un taux. Ils sont affichés comme non vérifiables, de même que les pièces dont les données figées manquent ou sont invalides. Les brouillons, pièces en génération, remplacées, annulées et erreurs de génération sont exclus. Une pièce non vérifiable interdit la conclusion générale verte. La distinction est explicite dans l'interface.

Un échec du serveur ou un résultat ancien/incomplet affiche un message français persistant avec « Réessayer le diagnostic ». Aucun détail SQL n'est exposé. Le frontend ne recalcule aucun montant. Les contrôles des agrégats de mission et des transferts orphelins conservent leur logique antérieure ; leur périmètre n'est pas étendu par ce lot. Les autres cartes et actions admin sont inchangées.

## Source et droits

Les métadonnées de production et de staging ont été lues sans données utilisateur. Le corps initial de `fn_diagnostic_coherence_financiere()` est identique sur les deux environnements : `ba4548f1a05a18f976eee4404039e0fc` ; définition `6b17b9eb7fca289c92f80405fdb5c812`. Le corps proposé est `c5b97d5373199cf3c7f7d44b661efb73`, définition `4e60ff931ff08d6759036d51f0ca0894`.

La migration exige le corps, le propriétaire, la stabilité, le contexte de recherche, l'ACL exacte et la ligne d'inventaire attendus. Elle conserve la garde admin, ne change aucun droit et ne modifie aucun montant financier. Le snapshot du dépôt contient le même corps. Le résultat conserve les clés historiques pour les consommateurs existants ; l'écran modifié exige les informations documentaires complètes avant tout affichage de cohérence.

## Vérification locale et témoin SQL

Le vrai frontend a été compilé puis servi localement avec des réponses simulées. Les trois parcours vérifient une erreur HTTP, le message persistant après fermeture/réouverture du panneau, le refus d'une ancienne réponse, la reprise, puis le résultat après rechargement. Les trois états sont absence d'écart documentaire, avoir non vérifiable et écart 90/80. Les cinq formats sont iPhone, Android, iPad portrait, iPad paysage et ordinateur. Les captures et résultats détaillés sont conservés hors dépôt dans `/private/tmp/jolene-admin-diagnostic-coherence-20261001`.

Le banc ferme les requêtes inconnues et les fenêtres secondaires, refuse les redirections et ne simule aucune écriture. Les références de compte sont fictives. Le service worker est rendu indisponible dans cette simulation ; aucune erreur ou alerte console n'est filtrée. L'unique erreur HTTP 400 par scénario est celle provoquée volontairement pour vérifier la reprise. Il n'y a ni diagnostic cloud, ni paiement, ni remboursement, ni notification externe.

Résultats finaux : 16 tests unitaires, 91 tests Node du contrôleur et du raccord, les 17 garde-fous, `tsc -b`, build Vite, actionlint et parseurs SQL/PLpgSQL verts. La campagne `matrice-cadree-finale` passe 15/15 sans retry, skip ou flaky en 52,6 secondes, avec 45 captures. Elle ferme la notification par son vrai bouton, place le résultat dans le viewport et vérifie qu'il n'est pas occulté. Des captures représentatives des cinq formats ont été relues. Les premières tentatives de harnais et la première campagne verte, moins bien cadrée sur iPad paysage, sont conservées séparément ; aucun correctif produit n'a été nécessaire entre ces campagnes.

Le témoin SQL réutilise le seed F141 déjà existant : deux périodes de 4 h, correction de la première à 3 h, puis deuxième période intermédiaire ou finale après la vraie RPC de clôture. Il invoque le vrai diagnostic sous le rôle admin applicatif, refuse soignant et anonyme, crée un avoir de 20 € par la vraie résolution de litige et vérifie séparément une pièce incohérente de 90 €. Les références PDF/XML sont fictives. L'avoir manuel peut créer des notifications admin transactionnelles ; la clôture crée deux entrées email transactionnelles. Aucune transaction n'est validée, les crons doivent être inactifs et aucun fournisseur n'est appelé.

Le raccord CI conserve les 53 suites historiques dans leur ordre et ajoute ce témoin en 54e suite. Un SELECT indépendant avant/après, exécuté aussi en cas d'échec, compare 26 compteurs, les corps/droits, les triggers, l'inventaire et les résidus du préfixe réservé F171. Les identifiants techniques générés sont contrôlés via leurs liens aux missions/pièces du test.

Au gel local, les tests unitaires, les simulations et les parseurs ne prouvent pas encore l'exécution de la migration ou du témoin sur PostgreSQL staging. Cette preuve devra être obtenue par CI sous rollback, après la revue indépendante. Aucun déploiement, appareil physique, fournisseur de test ou validation juridique n'est revendiqué par ce lot.

La revue indépendante de V11 a couvert la migration et son identité au snapshot, les gardes, les cas SQL et leurs effets transitifs, les contrôles avant/après et le raccord CI, puis le helper de validation et le bloc admin. Son renfort sur les collisions et les résidus des nouveaux identifiants a été appliqué. Le verdict source est clôturable pour intégration et CI ; le rapport est conservé avec les preuves et sera rattaché au commit final.
