# Notification d’avoir à rembourser manuellement

Le trigger historique annonçait un virement SWAN automatique dès qu’un IBAN
était présent, alors que le worker refuse cette action. Il envoyait également
vers `/admin/litiges`, qui ne sélectionne pas la liste des avoirs.

La migration ne modifie que les futures notifications : texte manuel explicite,
lien `/admin/moderation?onglet=avoirs`, suppression de la nouvelle tâche SWAN
inutile. Les événements déclencheurs, destinataires, garde des comptes TEST,
droits et anciennes notifications/actions restent inchangés. Aucun versement
ni remboursement n’est exécuté par cette correction.

## Source et portée SQL

La définition LIVE a été relue sur production et staging le 1 octobre 2026 :

| Fonction | Corps MD5 | Définition MD5 |
| --- | --- | --- |
| `fn_trg_notif_admin_remboursement_manuel()` avant | `082194c068b4978307c318a7d40caa3c` | `ad38ca7df98815b9996e60d9593f81c0` |
| La même fonction après | `5b2f553588a1c2d6ae7ef0a7dbded12f` | `03f2fff285767ce417352bfb62ef5584` |
| `fn_list_admin_user_ids()` inchangée | `e906ed6475c6d01f125d125e734988bf` | `e2525859fa4f203e559a6a22341826c0` |

La migration refuse une définition, un propriétaire, un ACL, une configuration,
un inventaire ou un trigger inattendu. `CREATE OR REPLACE` conserve les
privilèges existants : postgres et service_role uniquement. Son préflight accepte
exactement la paire d’empreintes avant ou après, pour permettre le rejeu.
Le snapshot ne change que le corps de cette fonction.

## Vérification et limites

- Analyse syntaxique locale : 4 instructions SQL et 3 corps PL/pgSQL de migration ;
  34 instructions SQL et 6 corps PL/pgSQL du test.
- `notification-remboursement-manuel.test.sql` est raccordé au job de migration
  staging sous ROLLBACK. Son exécution CI reste à constater sur la PR union.
- Le banc appelle la vraie fonction trigger et écrit dans la vraie table de
  notifications, à partir d’événements synthétiques temporaires. Il couvre
  avec/sans IBAN, insertion, transition, répétition, cas exclus, montant TTC/HT,
  administrateurs habilités et exclus, garde TEST et absence de tâche externe.
- Aucun trigger financier n’est désactivé, aucun profil TEST transformé en compte
  réel, aucun appel fournisseur effectué. Le banc ne crée pas de facture réelle :
  il ne prouve donc ni l’émission complète d’un avoir, ni son remboursement.
- La simulation frontend et sa revue sont portées par le sous-lot d’interface
  associé. La validation finale demande les deux niveaux, puis le déploiement.
