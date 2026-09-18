# Inscription progressive — recette du 18 septembre 2026

## Comportement

Le compte Auth se crée avec email, mot de passe et profession (soignant) ou nom (établissement), avec les conditions existantes. Un brouillon privé réserve la famille de compte sans créer de profil métier ni accorder les droits correspondants.

Le soignant découvre les missions puis complète son profil pour candidater. L’établissement prépare un brouillon privé, complète son identité et suit les vérifications existantes avant publication. La création habituelle d’une mission reprend ce brouillon, y compris la date seule ou des horaires partiels. Les horaires restent en Europe/Paris quel que soit le fuseau du téléphone.

Les erreurs de validation ou de réseau conservent le compte et la saisie enregistrée. Les documents, RPPS/SIRET/FINESS, autorisations et règles de candidature/publication gardent leurs contrôles serveur.

## Vérifications

- Migration et suite SQL : exécution réelle sur jolene-staging dans une transaction annulée, puis CI SQL complète verte. Isolation entre comptes, famille immutable, rôle absent avant complétion, champs interdits, suspension et propriété des claims vérifiés.
- Vingt tests des handlers serveur réels avec transport simulé : validation refusée, compte historique, compte progressif, réservation, réponses de finalisation perdues et retry.
- Revue backend et frontend indépendantes : verdicts CLÔTURABLE après correction des constats.
- Tests React/helpers : compte minimal, confirmation, reprise, captcha à usage unique, erreurs conservant la session, contrats restaurés et préférences PSC facultatives.
- Callback : les trois formats Supabase sont consommés explicitement, y compris WebView déjà ouvert, double effet et nouveau lien après expiration. Secrets retirés de l’URL.
- App complète avec API de recette locale : création des deux types de compte, découverte, profil différé, panne du brouillon puis retry, rechargement, déconnexion/reconnexion, complétion établissement et transfert de la garde 20:00–08:00 dans la création habituelle de mission.
- Navigateurs : établissement 390×844 et 1440×900 ; audit axe sans violation sur le compte établissement ; aucune erreur JavaScript sur les deux parcours contrôlés.
- Simulateur iPhone 16 Pro Max iOS 18.6 / Safari : comptes soignant et établissement, découverte des missions, dossier différé et brouillon conservé au rechargement.
- TypeScript, build Vite, 17 garde-fous et suite Vitest passent. Les tests E2E historiques ont été adaptés aux nouveaux écrans ; les parcours de comptes neufs gardent leurs véritables appels Auth et Edge dans la CI.

Les données locales de recette sont simulées ; elles ne sont pas présentées comme une preuve de création de compte en production. Les suites SQL et CI couvrent séparément le vrai serveur.

## Déploiement

1. Fusionner et déployer le serveur avant les écrans (PR 961).
2. Vérifier les nouvelles RPC et les deux Edge Functions déployées.
3. Fusionner le frontend après ses checks, puis vérifier le SHA et les écrans publics sur jolene.app.

L’URL exacte `https://jolene.app/inscription/confirmer` a été ajoutée à la liste des redirections Auth autorisées, en conservant les entrées existantes. La configuration de confirmation email et de captcha n’a pas été modifiée.

La mise à jour web ne remplace pas le bundle des versions iOS/Android déjà installées ; leur distribution nécessite un nouveau binaire Store.
