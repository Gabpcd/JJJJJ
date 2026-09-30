## SOIGNANT-original-apres-reload-aria

```yaml
- main:
  - button "← Retour"
  - img
  - heading "Contrat SIM-2026-0001" [level=1]
  - paragraph: "Statut : ✅ Signé"
  - button "Télécharger le contrat":
    - img
    - text: Télécharger le contrat
  - button "Imprimer":
    - img
    - text: Imprimer
  - paragraph:
    - img
    - text: Document officiel figé le 24/09/2026 à 08:55 — empreinte aaaaaaaa…aaaa
  - heading "Original synthétique signé" [level=2]
  - paragraph: "Texte historique : 10h/jour (L3121-18)"
  - heading "Signatures" [level=3]
  - img
  - text: "Établissement : ✅ Signé"
  - img
  - text: "Soignant(e) : ✅ Signé"
  - paragraph: ✅ Vous avez déjà signé ce contrat
  - paragraph: Contrat de prestation entre l’établissement et le professionnel libéral. Signature électronique simple. Les montants prévisionnels sont régularisés selon les heures validées et les éventuelles corrections contradictoires.
- region "Notifications alt+T"
- region "Notifications"
```

## SOIGNANT-original-manquant-aria

```yaml
- main:
  - button "← Retour"
  - paragraph: ⏳ L'autre partie a déjà signé
  - paragraph: Vous pouvez signer maintenant. Le contrat devient complet dès que les deux signatures sont enregistrées, quel que soit leur ordre.
  - timer:
    - img
    - paragraph: Signature à finaliser sous72h 00m 00s
  - img
  - heading "Contrat SIM-2026-0001" [level=1]
  - paragraph: "Statut : ⏳ En attente de signatures"
  - button "Télécharger le contrat" [disabled]:
    - img
    - text: Télécharger le contrat
  - button "Imprimer":
    - img
    - text: Imprimer
  - paragraph: Le document signé d’origine est indisponible. Aucune reconstitution automatique n’est effectuée.
  - heading "Signatures" [level=3]
  - img
  - text: "Établissement : ✅ Signé"
  - img
  - text: "Soignant(e) : ⏳ En attente"
  - heading "Votre signature" [level=3]
  - paragraph: "Choisissez votre mode de signature :"
  - radiogroup:
    - radio "📱 Signature électronique OTP SMS RECOMMANDÉE Code SMS à 6 chiffres + horodatage + hash document. Conforme art. 1366-1367 Code civil." [checked]:
      - img
    - text: 📱 Signature électronique OTP SMS RECOMMANDÉE
    - paragraph: Code SMS à 6 chiffres + horodatage + hash document. Conforme art. 1366-1367 Code civil.
    - radio "✍️ Signature manuscrite (canvas) Signez directement sur votre écran"
    - text: ✍️ Signature manuscrite (canvas)
    - paragraph: Signez directement sur votre écran
  - img
  - paragraph: Signature électronique sécurisée
  - paragraph: Recevez un code à 6 chiffres par SMS et saisissez-le ci-dessous pour signer. La signature inclut horodatage, IP et hash SHA-256 du document (preuve juridique art. 1366 Code civil).
  - checkbox "J'ai lu l'intégralité du contrat affiché ci-dessus et j'accepte ses termes." [checked]
  - text: J'ai lu l'intégralité du contrat affiché ci-dessus et j'accepte ses termes.
  - button "Recevoir le code SMS pour signer" [disabled]
  - paragraph: Contrat de prestation entre l’établissement et le professionnel libéral. Signature électronique simple. Les montants prévisionnels sont régularisés selon les heures validées et les éventuelles corrections contradictoires.
- region "Notifications alt+T"
- region "Notifications"
```

## SOIGNANT-rendu-refuse-aria

```yaml
- main:
  - button "← Retour"
  - timer:
    - img
    - paragraph: Signature à finaliser sous72h 00m 00s
  - img
  - heading "Contrat SIM-2026-0001" [level=1]
  - paragraph: "Statut : ⏳ En attente de signatures"
  - button "Télécharger le contrat":
    - img
    - text: Télécharger le contrat
  - button "Imprimer":
    - img
    - text: Imprimer
  - paragraph: Le document original n'était pas stocké ; cette version a été reconstituée automatiquement à partir des données de la mission.
  - heading "Contrat SIM-2026-0001" [level=1]
  - paragraph:
    - strong: "Type :"
    - text: LIBERAL
  - paragraph: Version reconstituée automatiquement à partir des données de mission enregistrées.
  - heading "Établissement" [level=2]
  - paragraph:
    - strong: Clinique Simulation
    - text: "SIRET : 00000000000000 Adresse : 2 rue de la Simulation, 75001, Paris Email : etablissement-mission@example.invalid Téléphone : +33600000002"
  - heading "Soignant·e" [level=2]
  - paragraph:
    - strong: Recette
    - text: "Profession : MEDECIN RPPS : 10000000001"
  - heading "Mission concernée" [level=2]
  - paragraph:
    - strong: Mission médecin — recette intégrale
    - text: "Service : Consultations Début : 24/09/2026 à 09:00 Fin : 24/09/2026 à 17:00 Durée prévue : 8 h Taux horaire : 80.00 €"
  - heading "Signatures" [level=2]
  - list:
    - listitem: "Établissement : en attente"
    - listitem: "Soignant·e : en attente"
  - heading "Signatures" [level=3]
  - img
  - text: "Établissement : ⏳ En attente"
  - img
  - text: "Soignant(e) : ⏳ En attente"
  - heading "Votre signature" [level=3]
  - alert: Le document contractuel final n’a pas pu être préparé. Edge Function returned a non-2xx status code Réessayez avant de signer.
  - paragraph: "Choisissez votre mode de signature :"
  - radiogroup:
    - radio "📱 Signature électronique OTP SMS RECOMMANDÉE Code SMS à 6 chiffres + horodatage + hash document. Conforme art. 1366-1367 Code civil." [checked]:
      - img
    - text: 📱 Signature électronique OTP SMS RECOMMANDÉE
    - paragraph: Code SMS à 6 chiffres + horodatage + hash document. Conforme art. 1366-1367 Code civil.
    - radio "✍️ Signature manuscrite (canvas) Signez directement sur votre écran"
    - text: ✍️ Signature manuscrite (canvas)
    - paragraph: Signez directement sur votre écran
  - img
  - paragraph: Signature électronique sécurisée
  - paragraph: Recevez un code à 6 chiffres par SMS et saisissez-le ci-dessous pour signer. La signature inclut horodatage, IP et hash SHA-256 du document (preuve juridique art. 1366 Code civil).
  - checkbox "J'ai lu l'intégralité du contrat affiché ci-dessus et j'accepte ses termes." [checked]
  - text: J'ai lu l'intégralité du contrat affiché ci-dessus et j'accepte ses termes.
  - button "Recevoir le code SMS pour signer" [disabled]
  - paragraph: Contrat de prestation entre l’établissement et le professionnel libéral. Signature électronique simple. Les montants prévisionnels sont régularisés selon les heures validées et les éventuelles corrections contradictoires.
- region "Notifications alt+T"
- region "Notifications"
```

## SOIGNANT-reprise-figee-aria

```yaml
- main:
  - button "← Retour"
  - timer:
    - img
    - paragraph: Signature à finaliser sous72h 00m 00s
  - img
  - heading "Contrat SIM-2026-0001" [level=1]
  - paragraph: "Statut : ⏳ En attente de signatures"
  - button "Télécharger le contrat":
    - img
    - text: Télécharger le contrat
  - button "Imprimer":
    - img
    - text: Imprimer
  - paragraph:
    - img
    - text: Document officiel figé le 24/09/2026 à 08:55 — empreinte bbbbbbbb…bbbb
  - heading "Nouveau document autorisé" [level=2]
  - paragraph: Rendu synthétique figé.
  - heading "Signatures" [level=3]
  - img
  - text: "Établissement : ⏳ En attente"
  - img
  - text: "Soignant(e) : ⏳ En attente"
  - heading "Votre signature" [level=3]
  - paragraph: "Choisissez votre mode de signature :"
  - radiogroup:
    - radio "📱 Signature électronique OTP SMS RECOMMANDÉE Code SMS à 6 chiffres + horodatage + hash document. Conforme art. 1366-1367 Code civil." [checked]:
      - img
    - text: 📱 Signature électronique OTP SMS RECOMMANDÉE
    - paragraph: Code SMS à 6 chiffres + horodatage + hash document. Conforme art. 1366-1367 Code civil.
    - radio "✍️ Signature manuscrite (canvas) Signez directement sur votre écran"
    - text: ✍️ Signature manuscrite (canvas)
    - paragraph: Signez directement sur votre écran
  - img
  - paragraph: Signature électronique sécurisée
  - paragraph: Recevez un code à 6 chiffres par SMS et saisissez-le ci-dessous pour signer. La signature inclut horodatage, IP et hash SHA-256 du document (preuve juridique art. 1366 Code civil).
  - checkbox "J'ai lu l'intégralité du contrat affiché ci-dessus et j'accepte ses termes."
  - text: J'ai lu l'intégralité du contrat affiché ci-dessus et j'accepte ses termes.
  - button "Recevoir le code SMS pour signer" [disabled]
  - paragraph: Contrat de prestation entre l’établissement et le professionnel libéral. Signature électronique simple. Les montants prévisionnels sont régularisés selon les heures validées et les éventuelles corrections contradictoires.
- region "Notifications alt+T"
- region "Notifications"
```
