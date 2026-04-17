# Templates email Jolene — registre de référence

Document de référence listant **tous les templates email** rendus par
`supabase/functions/send-email/index.ts` (`renderTemplate` switch). Toute
création de template doit passer par la checklist "Ajouter un template"
ci-dessous pour éviter les doublons.

Source de vérité : `supabase/functions/send-email/index.ts` — `ALLOWED_TYPES`
(l.78-94) + switch `renderTemplate` (l.104-656). En cas de divergence entre
cette doc et le code, **le code prime** — mettre la doc à jour dans le même
commit.

## Règle anti-doublons

> **Avant d'ajouter un nouveau template, vérifier ce registre.** Si un
> template couvre déjà le cas d'usage (même destinataire, même contexte),
> l'étendre via ses variables `data.*` plutôt que d'en créer un second.
>
> Les noms sont **uppercase snake_case** et **préfixés par domaine**
> (`MISSION_`, `FACTURE_`, `LITIGE_`, etc.). Cohérence obligatoire.

## Registre des templates

### Onboarding / comptes

| Nom                          | Destinataire  | Sujet                                              |
| ---------------------------- | ------------- | -------------------------------------------------- |
| `BIENVENUE_SOIGNANT`         | soignant      | Bienvenue sur Jolene ! 🎉                          |
| `BIENVENUE_ETABLISSEMENT`    | établissement | Bienvenue sur Jolene !                             |

### Missions

| Nom                             | Destinataire  | Sujet                                         |
| ------------------------------- | ------------- | --------------------------------------------- |
| `MISSION_ACCEPTEE_SOIGNANT`     | soignant      | Mission confirmée : `{mission}`               |
| `MISSION_ACCEPTEE_ETABLISSEMENT`| établissement | Mission acceptée : `{mission}`                |
| `RAPPEL_MISSION`                | soignant      | Rappel : mission demain — `{mission}`         |
| `MISSION_TERMINEE`              | soignant      | Mission terminée : `{mission}`                |
| `MISSION_URGENTE`               | soignant      | 🚨 Mission urgente : `{mission}`              |
| `MISSION_PROPOSEE`              | soignant      | Mission proposée : `{mission}`                |
| `MISSION_NON_POURVUE`           | établissement | Mission non pourvue — `{mission}`             |

### Contrats

| Nom                | Destinataire          | Sujet                               |
| ------------------ | --------------------- | ----------------------------------- |
| `CONTRAT_A_SIGNER` | soignant              | Contrat à signer : `{mission}`      |
| `CONTRAT_SIGNE`    | soignant + étab       | Contrat signé : `{mission}`         |

### Facturation / paiements

| Nom                    | Destinataire  | Sujet                                             |
| ---------------------- | ------------- | ------------------------------------------------- |
| `FACTURE_EMISE`        | établissement | Facture `{numero}` — Jolene                       |
| `FACTURE_PAYEE`        | établissement | Paiement confirmé — Facture `{numero}`            |
| `RAPPEL_FACTURE`       | établissement | Rappel : facture `{numero}` en attente            |
| `PAIEMENT_CONFIRME`    | établissement | Paiement confirmé — `{montant}` €                 |
| `PAIEMENT_RAPIDE_RECU` | soignant      | Paiement rapide reçu 💸                           |

### Documents

| Nom                 | Destinataire | Sujet                                  |
| ------------------- | ------------ | -------------------------------------- |
| `DOCUMENT_EXPIRANT` | soignant     | Document expirant : `{type_document}`  |
| `RAPPEL_DOCUMENTS`  | soignant     | Complétez votre dossier sur Jolene     |

### Évaluation / engagement / éligibilité

| Nom                | Destinataire | Sujet                                          |
| ------------------ | ------------ | ---------------------------------------------- |
| `EVALUATION_RECUE` | soignant     | Nouvelle évaluation reçue — `{note}`/5         |
| `ELIGIBLE_LIBERAL` | soignant     | Vous êtes éligible au passage en libéral ! 🎉  |
| `RECAP_HEBDO`      | soignant     | Votre récap hebdomadaire — Jolene              |

### Litiges (CP-LITIGES-5 + 7a)

| Nom                             | Destinataire         | Sujet                                                |
| ------------------------------- | -------------------- | ---------------------------------------------------- |
| `LITIGE_OUVERTURE`              | partie opposée       | Un litige a été ouvert sur votre mission du `{date}` |
| `LITIGE_NOUVEAU_MESSAGE`        | partie opposée       | Nouveau message sur votre litige                     |
| `LITIGE_ESCALADE_ADMIN`         | admin                | 🚨 Litige escaladé — action requise                  |
| `LITIGE_MEDIATION_PRIORITAIRE`  | admin                | 🚨 Litige en médiation depuis > `{n}` jours          |
| `LITIGE_RESOLU_AJUSTE`          | soignant + étab      | Litige résolu — ajustement appliqué                  |
| `LITIGE_RAPPEL_J1`              | partie opposée       | Rappel : litige en attente de votre réponse          |
| `LITIGE_RAPPEL_J3`              | partie opposée       | ⚠️ Rappel urgent : litige en attente depuis 3 jours  |
| `LITIGE_RAPPEL_J5`              | partie opposée       | 🚨 Dernier rappel — escalade imminente               |
| `AVOIR_EMIS`                    | soignant             | Avoir `{numero_avoir}` émis — Jolene (PDF joint)     |
| `REMBOURSEMENT_CONFIRME`        | soignant             | Remboursement de `{montant}` € effectué              |
| `REGULARISATION_SOCIALE_REQUISE`| soignant             | Ajustement heures — régularisation URSSAF/Carpimko   |
| `COMMISSION_AJUSTEE`            | établissement        | Avoir/facture complémentaire commission — `{numero}` |

### Admin

| Nom               | Destinataire                | Sujet                          |
| ----------------- | --------------------------- | ------------------------------ |
| `ADMIN_BROADCAST` | groupe (soignants/étabs)    | `{subject}` (libre)            |

## Incohérences connues à résoudre

- **`RELANCE_FACTURE` vs `RAPPEL_FACTURE`** : `ALLOWED_TYPES` whiteliste
  `RELANCE_FACTURE` (l.88) **et** `RAPPEL_FACTURE` (l.84) ; seul
  `RAPPEL_FACTURE` a un `case` dans le switch. `src/pages/admin/AdminImpayees.tsx`
  pousse `type: 'RELANCE_FACTURE'` → `renderTemplate` renvoie `null` et l'email
  n'est pas envoyé. **TODO** : aligner sur un seul nom (conserver
  `RAPPEL_FACTURE` et mettre à jour `AdminImpayees.tsx`, ou ajouter un `case
  'RELANCE_FACTURE'` dupliqué).

## Templates orphelins (whitelistés sans déclencheur actif)

Templates rendables mais non câblés à un déclencheur backend (RPC / edge
function / webhook) au moment de l'audit. À câbler ou supprimer :

- `CONTRAT_A_SIGNER` — prévu après génération contrat, non déclenché.
- `RECAP_HEBDO` — aucun cron.
- `ELIGIBLE_LIBERAL` — aucun déclencheur.
- `EVALUATION_RECUE` — aucun déclencheur (hors mocks).
- `PAIEMENT_CONFIRME` — aucun déclencheur.
- `MISSION_NON_POURVUE` — aucun déclencheur.
- `LITIGE_NOUVEAU_MESSAGE` — aucun déclencheur (références tests uniquement).
- `REMBOURSEMENT_CONFIRME` — `fn_confirmer_remboursement_avoir` commente "à
  câbler" mais ne pousse pas.
- `REGULARISATION_SOCIALE_REQUISE` — flag `missions.regularisation_sociale_requise`
  posé par `fn_admin_resoudre_litige`, mais aucun push email associé.
- `PAIEMENT_RAPIDE_RECU` — `factor-webhook` crée la notification in-app mais
  n'enqueue pas d'email.

## Ajouter un nouveau template — checklist

1. **Vérifier** ce registre : le cas est-il déjà couvert ? Si oui, étendre
   plutôt que dupliquer.
2. **Nommer** en `DOMAINE_ACTION` (uppercase snake_case, préfixe domaine).
3. **Whitelister** le nom dans `ALLOWED_TYPES` (`send-email/index.ts` l.78-94).
4. **Ajouter** le `case 'TYPE':` dans le switch `renderTemplate` :
   - Retourner `{ subject, html }` (+ `hasAttachment: true` si PDF joint).
   - Utiliser `WRAPPER()` pour l'enveloppe HTML (cohérence layout).
   - Utiliser les helpers `INFO_BOX`, `CARD_BOX`, `BUTTON`, `SECURITY_NOTE`.
   - Variables via `${data.xxx || 'fallback'}` (jamais `{variable}` non
     interpolé — cf. `tests/litiges/templates-structure.test.ts`).
5. **Câbler** le déclencheur côté backend (RPC, edge function, webhook, front)
   avec `supabase.functions.invoke('send-email', { body: { type, destinataire_id, destinataire_email, data } })`.
6. **Mettre à jour** ce registre (catégorie, ligne dans la table).
7. **Test manuel** : reproduire un envoi test (cf. `docs/tests-templates-litiges.md`
   pour les litiges) et vérifier sujet + rendu HTML + variables remplacées.

## Conventions

- **Enveloppe** : `WRAPPER()` pour le layout standard Jolene (header rose
  `#E04590`, footer CGU/Confidentialité). Jamais de HTML nu.
- **XSS** : `rawData` est automatiquement passé par `escapeHtml()`. Utiliser
  `data.xxx` (déjà échappé), pas `rawData.xxx`.
- **Pièces jointes** : le template doit retourner `hasAttachment: true` si le
  handler joint un PDF (ex : `AVOIR_EMIS`).
- **SMS** : certains types déclenchent aussi un SMS (whitelist CP5 :
  `LITIGE_OUVERTURE`, `REMBOURSEMENT_CONFIRME`, `LITIGE_RAPPEL_J1/J3/J5`).
  Cf. `docs/sms-configuration.md`.

## Tests

- **Structurels** : `tests/litiges/templates-structure.test.ts` — chaque
  template litige a un `case`, utilise `WRAPPER()`, pas de `{variable}`
  non-interpolé.
- **Longueur SMS** : `tests/sms/litige-length.test.ts` — body ≤ 140 c pour
  les 5 types éligibles.
- **Préfixe SMS** : `tests/sms/prefix.test.ts` — `resolveSmsPrefix` +
  truncation Twilio.
- **Tests manuels** : `docs/tests-templates-litiges.md` — 15 commandes curl
  pour les 12 templates litiges.
