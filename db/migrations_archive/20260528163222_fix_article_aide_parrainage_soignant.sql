-- Fix article aide parrainage soignant : supprime +50h illégal, remplace par prime cash 50€

UPDATE public.articles_aide
SET contenu = $$Vous pouvez inviter vos collègues soignants à rejoindre Jolene avec votre **code parrainage personnel**. Chaque parrainage validé vous rapporte une **prime de 50€** versée par virement.

## Prime de parrainage : 50€ parrain + 50€ filleul

Quand votre filleul **termine sa 1ère mission** et que Jolene a encaissé **100€ de commission** grâce à ses missions :

- **50€ versés sur votre IBAN** (parrain)
- **50€ versés sur l'IBAN de votre filleul**

Le versement est effectué par virement bancaire. Renseignez votre IBAN dans **Profil → Paiements → Coordonnées bancaires**.

## Conditions de versement

Toutes les conditions suivantes doivent être remplies :

1. Le parrain a complété au moins 1 mission terminée (soignant actif)
2. Le filleul a complété au moins 1 mission terminée
3. La commission encaissée par Jolene sur les missions du filleul atteint 100€ minimum
4. Le parrain ET le filleul ont renseigné leur IBAN

## Badge Ambassadeur (3 filleuls validés)

Quand **3 de vos filleuls ont terminé leur 1ère mission** sur Jolene, vous débloquez le **badge Ambassadeur** sur votre profil :

- Visible côté établissements dans l'annuaire et la recherche soignants
- Apparaît dans vos candidatures comme un signal de confiance

## Comment partager votre code

Page **Parrainage** dans votre menu :
- Code unique format `JO-XXXXXX` (auto-généré à votre inscription)
- Lien direct `https://jolene.app?ref=VOTRE_CODE` pré-rempli pour le filleul
- QR code pour partage en personne
- Boutons partage rapide : WhatsApp, SMS, Email, LinkedIn

Le filleul qui clique sur votre lien arrive sur la page d'accueil avec le code déjà capturé — il sera **pré-rempli automatiquement** dans le champ « Code parrainage » du profil.

## Suivi de vos filleuls

Sur la page Parrainage, le tableau **Mes filleuls** affiche pour chacun :
- Son prénom et la date de son inscription
- Son statut : *En attente*, *Activé* (1ère mission faite), *Prime versée*

## Règles

- **Pas d'auto-parrainage** : vous ne pouvez pas appliquer votre propre code.
- **Un seul parrain par filleul** : un filleul ne peut pas changer de parrain.
- **Maximum 20 filleuls validés** par parrain.
- **Anti-fraude** : les parrainages suspects (même IP, même appareil) sont vérifiés manuellement.

## Articles liés

[Comment vérifier mon RPPS](/aide/comment-verifier-mon-rpps)
[Inscription soignant (libéral / salarié / mixte)](/aide/inscription-soignant-liberal-salarie-mixte)
$$,
titre = 'Parrainage : invitez vos collègues, gagnez 50€',
mis_a_jour_le = now()
WHERE slug = 'parrainage-soignant';
