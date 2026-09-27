# Commande Chorus exécutable et portée des preuves

Contrôle du 27 septembre 2026. Aucun appel prestataire, dépôt de facture, email ou SMS.

## Commande locale disponible

```sh
npm run test:chorus:static
```

Elle exécute les cinq assertions de `tests/invoicing/weekly-pointage-chorus-hardening.test.ts` avec `vitest.invoicing.config.ts`. Ces assertions lisent les sources SQL/TypeScript et contrôlent des invariants de pointage, facturation, rapprochement et accès Chorus. Elles ne se connectent à aucune base ni API. Elles ne prouvent ni une migration réellement exécutée, ni un dépôt, ni une réception Chorus.

L'ancien nom `test:chorus:sandbox` a été retiré : il visait `tests/invoicing/chorus-submission.test.ts`, absent du dépôt. La configuration Vitest par défaut exclut également `tests/invoicing/` ; la configuration dédiée est donc nécessaire même pour le fichier existant.

Vérification locale : **5/5 assertions réussies**, aucun test ignoré. Le fichier de verrouillage des dépendances reste inchangé.

## Ce qui ne constitue pas un remplacement

`scripts/activate-chorus.ts` n'a pas été lancé. Il permet de viser la production, tente un dépôt et considère certains rejets HTTP 400/422 comme un résultat positif. Son intitulé et son verdict ne constituent pas une preuve de facture acceptée en sandbox. Les scripts SQL historiques `tests/chorus/` ne prouvent pas davantage une réponse prestataire : ils testent des données préparées et désactivent l'arrêt sur erreur.

## Portée d’une future recette prestataire

Cette commande statique ne vérifie pas la configuration ni le fonctionnement des prestataires dans un environnement déployé.

Les protections de cohorte ignorent volontairement les comptes/sources de test dans `send-sms`, `send-email` et `send-push`. Configurer une clé seule ne suffirait donc pas à prouver une livraison. Une recette prestataire nécessite :

- un transport de capture ou des destinataires de test autorisés, avec reçu observable et absence de `skipped` ;
- une identité PSC de recette autorisée et cohérente, des accès ANS de test et les documents correspondants ;
- pour Chorus, un environnement séparé identifié comme sandbox, des structures/droits et factures de test autorisés, puis un identifiant réel de dépôt accepté et le statut de cette même facture ;
- les versions exactes des Edge testées et une vérification des préférences, du destinataire, du lien reçu et de l'idempotence.

Ces prérequis ne sont pas remplacés par une lecture d'OTP en base ou une modification de la cohorte de test. L'authentification Supabase et son SMTP sont une couche distincte : cette commande ne mesure pas leur délivrabilité.

**Cette commande n’apporte pas de preuve prestataire complète en staging et ne diagnostique pas la production.** Les simulations UI et tests statiques conservent leur portée propre.
