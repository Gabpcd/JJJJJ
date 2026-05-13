# OTP SMS vérification téléphone (Sprint 6)

> Fix **P1-12** audit Sprint 5. Workflow OTP SMS pour vérifier le numéro de téléphone à l'inscription et à chaque modification.

## Architecture

Migration `20260515120000_pr9s6_otp_sms_telephone.sql` ajoute :

### Tables
- **`otps_telephone`** : id, user_id, telephone, code_hash (bcrypt), tentatives, utilise, cree_le, expire_le (10 min)
- Index : `(user_id, cree_le DESC)`, `(telephone, cree_le DESC)`
- RLS : user voit uniquement ses propres OTPs

### Colonnes
- `soignants.telephone_verifie boolean DEFAULT false`
- `soignants.telephone_verifie_le timestamptz`
- `soignants.telephone_en_attente_verification text`
- Idem `etablissements.*`

## RPCs

### `fn_envoyer_otp_telephone(p_telephone text) → jsonb`

- Validation E164 simplifié (regex `^\+?[0-9 ]{9,15}$`)
- Rate limit **3 SMS / 24h par user** (`COUNT(*) FROM otps_telephone WHERE user_id = uid AND cree_le > NOW() - 24h`)
- Génération code 6 chiffres → hash bcrypt → INSERT otps_telephone
- Stockage `telephone_en_attente_verification` sur profil
- INSERT externalisation_actions SMS_NOTIF (worker Twilio Sprint 4)
- Codes erreur : `NON_AUTHENTIFIE`, `TELEPHONE_INVALIDE`, `RATE_LIMIT`

### `fn_verifier_otp_telephone(p_code text) → jsonb`

- Code format `^[0-9]{6}$` requis
- SELECT dernier OTP user non utilisé non expiré
- Blocage après **5 tentatives** par OTP
- Incrémente tentatives avant vérif, retourne `tentatives_restantes`
- `extensions.crypt(p_code, code_hash) = code_hash` → marque utilisé + `telephone_verifie = true`
- Codes erreur : `NON_AUTHENTIFIE`, `CODE_INVALIDE`, `OTP_INEXISTANT_OU_EXPIRE`, `TROP_TENTATIVES`, `CODE_INCORRECT`

## Composant frontend

`VerificationTelephoneOTP` (réutilisable) :

```tsx
<VerificationTelephoneOTP
  telephoneInitial={user.telephone}
  onVerifie={(tel) => console.log('Téléphone vérifié:', tel)}
/>
```

2 étapes UI :
1. **Saisie** : input tel + bouton "Envoyer le code SMS"
2. **Vérification** : input code 6 chiffres + bouton "Vérifier"

Toasts contextuels en cas d'erreur (RATE_LIMIT, CODE_INCORRECT avec tentatives restantes, etc.).

## Intégration

À ajouter dans :
- `InscriptionSoignant` (après étape téléphone)
- `InscriptionEtablissement` (idem)
- `/soignant/parametres` section compte (modification téléphone)
- `/etablissement/parametres` (idem)

## Sécurité

- Code jamais stocké en clair (bcrypt salt 8)
- Code envoyé via SMS Twilio (infra Sprint 2 réutilisée via `externalisation_actions` SMS_NOTIF)
- Rate limit anti-flood
- Blocage après 5 tentatives → nouveau code SMS requis
- Audit complet via `journaux_audit` action=SYSTEM

## Cas d'usage

1. **Inscription** : flag `telephone_verifie = false` initial → utilisateur clique "Vérifier mon numéro" → SMS reçu → saisie code → flag passe à true
2. **Modification téléphone** : nouveau numéro stocké en `telephone_en_attente_verification` → OTP envoyé → si vérifié, `telephone` mis à jour et flag = true
3. **Migration utilisateurs existants** : `telephone_verifie = false` par défaut, demande de vérification à la prochaine connexion (banner)
