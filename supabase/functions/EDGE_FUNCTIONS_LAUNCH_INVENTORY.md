# Inventaire Edge — décision de lancement

Ce complément classe les fonctions qui envoient directement via Resend. Les
fonctions opérationnelles doivent résoudre le statut test de chaque compte avant
l'appel fournisseur et échouer fermées si cette résolution est impossible.

| Fonction | Classe lancement | Décision |
|---|---|---|
| `admin-invoke` | `SYSTEME_ADMIN_PROTEGE` | Alerte d'audit envoyée uniquement à l'équipe opérations après authentification administrateur complète et seulement pour une fonction sensible ; aucun destinataire opérationnel n'est dérivé des fixtures. |
| `avis-parrainage` | `OPERATIONNEL_PROTEGE` | Résolution fail-closed du soignant ; compte test ignoré et audité. |
| `digest-hebdo` | `OPERATIONNEL_PROTEGE` | Résolution fail-closed du soignant ; compte test ignoré et audité. |
| `relance-inactifs` | `OPERATIONNEL_PROTEGE` | Résolution fail-closed du soignant ; compte test ignoré et audité. |
| `notify-support` | `OPERATIONNEL_PROTEGE` | Résolution fail-closed de la source par UUID, mission ou email Auth avant Resend. |
| `contact-form` | `PUBLIC_INBOUND_ALLOWED` | Formulaire public entrant, protégé par Turnstile et quotas ; ce n'est pas une notification issue des données opérationnelles. |
| `sales-outreach` | `ACQUISITION_INACTIVE` | Acquisition non nécessaire au lancement : ne doit pas être planifiée ni utilisée avant décision explicite. |
| `sales-outreach-batch` | `ACQUISITION_INACTIVE` | Acquisition de masse désactivée par `growth_config.automatisations_marketing_actives != true` ; ne doit pas être planifiée. |

`sales-outreach` et `sales-outreach-batch` restent donc hors du parcours de
lancement. Leur présence dans le dépôt n'autorise ni planification ni envoi.
