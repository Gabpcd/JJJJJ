# Stratégie de lancement pilote Jolene

Mise à jour : 19/07/2026. Cette stratégie transforme les outils déjà présents
dans l'admin en une cadence opérationnelle mesurable. Elle complète
`STRATEGIE_PRODUIT_ACQUISITION.md` et ne remplace pas la recette stores de
`store-readiness.md`.

## Décision de lancement

Jolene ne doit pas ouvrir nationalement d'un coup. Le lancement se fait marché
local par marché local, un marché étant le couple **département × profession
requise par la mission**. Les premiers bassins à densifier restent Paris/92 et
Lorient/56 tant que les données réelles du cockpit ne désignent pas un meilleur
segment.

Les comptes et missions de démonstration sont conservés pour les captures et la
review des stores. Ils ne sont ni masqués ni supprimés. Le cockpit les sépare :

- **Réel** : seule vue utilisée pour une décision de lancement public ;
- **Test** : recette, démonstrations et scénarios stores ;
- **Tous** : diagnostic combiné, jamais une preuve de traction.

## Ce que l'admin permet désormais

| Besoin | Surface admin | Usage |
|---|---|---|
| Décider GO/NO-GO | Croissance → Pilotage lancement | Liquidité, conversion, qualité, filtres département/profession |
| Traiter l'acquisition | Croissance → Prospection → CRM du jour | File priorisée, attribution, relances et journal |
| Sourcer | Prospection | Annuaire Santé, FINESS, groupes, établissements et soignants sourcés |
| Convertir | Utilisateurs, Vérification établissements, Revues manuelles | Lever les blocages d'identité et de documents |
| Opérer les missions | Missions, Planning global, Alertes pointage | Publier avec l'établissement, matcher et corriger les pointages |
| Fermer la boucle financière | Finances, Impayés, Chorus Pro | Paiement soignant et encaissement de la commission |
| Protéger la qualité | Litiges, Signalements, Audit | No-show, contestations et traçabilité |

Le manque principal de l'ancienne interface était une lecture de liquidité
locale séparant le réel du test, ainsi qu'une vraie file CRM anti-oubli. Ces deux
manques sont couverts par le cockpit de lancement et le CRM automatisé.

## Seuils avant extension d'un marché

Un département/profession ne s'élargit que si la vue **Réel** atteint tous les
seuils suivants :

| Indicateur | Seuil |
|---|---:|
| Missions terminées | ≥ 5 |
| Missions pourvues | ≥ 70 % |
| Première candidature médiane | < 4 h |
| Missions terminées avec pointage complet | ≥ 95 % |
| Soignants payés | ≥ 95 % |
| Commissions encaissées | ≥ 95 % |
| Absences sans prévenir | < 3 % |
| Missions avec litige | < 5 % |

Un seuil rouge bloque l'extension géographique ou métier. Il ne bloque ni la
recette ni le service concierge auprès des premiers utilisateurs.

## Cadence quotidienne de la fondatrice

### 08 h 30 — opérations critiques, 15 minutes

1. Ouvrir **Pilotage lancement** en Réel sur 30 jours.
2. Vider les alertes : mission sans candidat depuis 24 h, pointage incomplet,
   paiement manquant, commission non encaissée.
3. Ne jamais lancer de prospection sur un segment dont les incidents financiers
   ou de pointage ne sont pas maîtrisés.

### 09 h 00 — acquisition, 45 à 60 minutes

1. Ouvrir **CRM du jour** et traiter les urgences puis les retards.
2. Priorité aux établissements : 10 appels ciblés par jour dans le marché pilote.
3. Proposer aux dix premiers établissements un accompagnement concierge : la
   première mission est publiée avec eux au téléphone.
4. Sourcer les soignants uniquement sur les professions réellement demandées
   dans le cockpit, puis compléter via groupes locaux et parrainage.
5. Marquer immédiatement le résultat de chaque action ; ne jamais conserver une
   relance dans un carnet parallèle.

### 16 h 30 — liquidité et matching, 20 minutes

1. Reprendre chaque mission sans candidat depuis 24 h.
2. Contacter manuellement les soignants vérifiés et disponibles du même marché.
3. Relancer l'établissement si une candidature n'a pas reçu de décision.
4. Vérifier que chaque mission du lendemain a son parcours de pointage prêt.

## Automatisation CRM

Le CRM génère une file idempotente toutes les heures. Un nouveau contact actif
reçoit une tâche de premier contact ; un email envoyé est journalisé et programme
une relance à J+3, puis J+7, puis J+14. Un appel sans réponse revient à J+2. Un
contact intéressé reste dans la file avec un suivi à J+1 sans être compté comme
inscrit ; seule l'action **Inscrit** alimente la conversion.

Les actions **Pas intéressé** et **STOP** désactivent définitivement la séquence
et empêchent tout nouveau contact. Les tâches et activités sont réservées aux
admins par RLS. Les emails existants envoyés via les fonctions de prospection
sont automatiquement inscrits dans le journal.

L'automatisation ne déclenche pas d'envoi froid sans validation humaine. Elle
prépare, attribue, date, priorise et trace ; Gabrielle valide l'appel, WhatsApp ou
l'email. Cette limite protège la délivrabilité, le consentement et la réputation
de Jolene au lancement.

## Cadence hebdomadaire

Chaque vendredi, lire la vue Réel par marché local :

- doubler l'effort sur les segments proches des seuils ;
- mettre en pause l'acquisition si l'offre croît sans missions ;
- renforcer le sourcing soignant si des missions restent sans candidat ;
- ne lancer un nouveau département ou une nouvelle profession qu'après deux
  semaines consécutives au vert ;
- documenter les trois causes principales de perte dans le journal CRM.

## Ce qui reste externe à l'admin

- exécuter les appels, rendez-vous et partenariats locaux ;
- produire les contenus fondatrice LinkedIn/TikTok/Instagram ;
- installer les builds stores et faire la recette sur appareils réels ;
- confirmer les intégrations externes en production (PSC, Stripe, Chorus Pro,
  push) avec de vrais comptes et de petits montants ;
- décider d'un budget publicitaire seulement après une activation saine et une
  liquidité locale démontrée.

Le signal de départ d'une campagne payante n'est pas « l'app est publiée », mais
« un marché réel remplit durablement les seuils du cockpit ».
