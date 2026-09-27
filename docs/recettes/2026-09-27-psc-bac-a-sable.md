# Pro Santé Connect — adresses du bac à sable

Le 27 septembre 2026, la documentation technique ANS et les métadonnées OIDC
publiques confirment les hôtes `auth.bas.psc.esante.gouv.fr` et
`wallet.bas.psc.esante.gouv.fr` pour le bac à sable. L'ancien hôte
`auth.bas.esw.esante.gouv.fr`, présent dans les quatre fonctions PSC de Jolene,
ne résout plus lors du contrôle.

Les douze adresses du bac à sable sont corrigées dans l'autorisation, le
callback, la déconnexion et le diagnostic. Les adresses de production restent
strictement inchangées : `auth.esw.esante.gouv.fr` et `wallet.esw.esante.gouv.fr`.
Les contrôles d'identité, de signature, d'issuer, d'audience, de nonce et de
rattachement au compte ne sont pas modifiés.

La liste des hôtes autorisés côté navigateur et application native remplace
également les deux anciens hôtes du bac à sable. Sans cet alignement, Jolene
refuserait d'ouvrir les nouvelles URL. Les anciennes adresses et les domaines
externes restent refusés ; aucun domaine générique n'est autorisé.

Vérifications réalisées :

- Discovery public HTTP 200 sur les environnements production et bac à sable.
- Les 24 adresses utilisées par les quatre fonctions correspondent exactement
  aux métadonnées de leur environnement (issuer, autorisation, token, JWKS,
  UserInfo et déconnexion).
- Les dix tests existants de sécurité et de navigation PSC réussissent.
- Aucune authentification professionnelle ni aucun échange de code/token n'a
  été effectué : ces contrôles ne prouvent pas encore un parcours PSC complet.

Pour la recette authentifiée, utiliser un client ANS de bac à sable et une
identité officielle de test créée dans EDIT. Ne pas configurer une identité de
test sur la production ni assimiler une découverte OIDC à une connexion réussie.

Sources officielles consultées le 27 septembre 2026 :

- [Documentation technique PSC](https://esante.gouv.fr/ens/offre/pro-sante-connect/documentation-technique)
- [Discovery du bac à sable](https://auth.bas.psc.esante.gouv.fr/auth/realms/esante-wallet/.well-known/wallet-openid-configuration)
- [Discovery de production](https://auth.esw.esante.gouv.fr/auth/realms/esante-wallet/.well-known/wallet-openid-configuration)
- [Identités de test EDIT](https://esante.gouv.fr/ens/offre/pro-sante-connect/edit-gestion-identites)
