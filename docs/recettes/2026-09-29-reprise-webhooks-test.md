# Reprise contrôlée du raccordement Stripe TEST

Le run 36488815863 a créé `we_1UKmSiEVhQ7cb53WAuAljU47` puis a rejeté la
réponse : Stripe TEST avait ajouté `transfer.canceled` aux événements demandés.
Aucune signature n'a été installée, aucun paiement créé. Le handler conserve
son allow-list : cet événement supplémentaire reste ignoré.

Le configurateur accepte uniquement cet ajout observé côté plateforme ; les
événements manquants, inconnus ou dupliqués restent rejetés. Le mode normal
refuse toujours une configuration existante.

La reprise est explicite (run d'origine et ID du webhook plateforme). Elle
vérifie le compte TEST, le projet staging, les métadonnées, la configuration,
l'absence d'une seconde destination et de secrets préexistants, puis l'âge
strictement inférieur à 23 heures. Elle rejoue exactement le POST initial avec
sa clé d'idempotence et vérifie que Stripe renvoie le même ID. Elle crée ensuite
la destination Connect, installe deux signatures distinctes et vérifie les
signatures correctes et croisées avec un événement sans effet métier.

Référence : https://docs.stripe.com/api/idempotent_requests — conservation
pendant au moins 24 heures, mêmes paramètres, réponse initiale rejouée. Au-delà
de la fenêtre prévue, ne pas relancer avec une nouvelle clé ni supprimer un
webhook automatiquement : inspection manuelle nécessaire.

Le run de cohortes 36489141363 a aussi échoué : le SIRET fictif fixe était déjà
utilisé par la fixture persistante. Le SQL choisit désormais un identifiant
fictif libre dans une plage bornée et annule toujours toute la transaction.
Aucun acteur existant, trigger, droit de publication ou garde financier modifié.

Validation : 47 tests Node passent et `tsc -b` passe. La transaction SQL corrigée
passe sur le staging existant. Ces contrôles de configuration ne constituent
pas la recette frontend paiement → remboursement. Cette recette reste à faire,
avec des preuves reliées aux mêmes objets et montants Stripe/backend/interface.
