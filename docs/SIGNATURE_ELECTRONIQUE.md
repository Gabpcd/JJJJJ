# Signature électronique Jolene — architecture & audit trail

> Référence implémentée : Sprint 1 PR 4 (module OTP) + Sprint 2 PR 1 (hash réel + limites).
> Conformité légale : art. 1366-1367 du Code civil (signature électronique).

## Niveau de garantie

Jolene fournit une **signature électronique sécurisée avancée renforcée par OTP SMS**.
Elle n'est PAS une signature qualifiée eIDAS (qui nécessite un Prestataire de Services
de Confiance qualifié) — la mention juridique sur les contrats Jolene est explicite à ce
sujet et redirige vers un PSCo qualifié si nécessaire.

## Flow utilisateur (UI `SignerContratOtp.tsx`)

```
1. Soignant / étab ouvre /contrat/:id
2. Module rend le HTML du contrat (récupéré depuis templates_contrat)
3. Hash SHA-256 du HTML calculé côté client via crypto.subtle.digest
4. Utilisateur coche "J'ai lu et j'accepte les termes"
5. Clic "Recevoir le code SMS"
   → RPC fn_envoyer_otp_signature(contrat_id)
   → vérifie ordre (étab refusé si soignant pas encore signé)
   → vérifie limite anti-abus (3 SMS / 24h)
   → génère OTP 6 chiffres + hash SHA-256 du tuple (otp|contrat_id|user_id)
   → envoi SMS via send-sms edge function (via net.http_post)
6. Utilisateur saisit OTP reçu par SMS
7. Clic "Signer"
   → RPC fn_signer_contrat_otp(contrat_id, otp, hash_document, signature_image?)
   → vérifie OTP non expiré (10 min) + tentatives < 5
   → vérifie hash OTP (constant-time comparison via PG digest)
   → INSERT signatures_contrats (rôle, IP, UA, hash_document, signe_a)
   → UPDATE contrats_mission (signature_role + le)
   → si 2 parties signées → statut = SIGNE_COMPLET (trigger
     dec_email_contrat_signe_complet envoie email aux 2 parties)
```

## Données stockées (audit trail)

Table `signatures_contrats` :

| Colonne | Description |
|---|---|
| `contrat_id` | FK contrats_mission |
| `signataire_user_id` | uid Supabase Auth |
| `signataire_role` | `soignant` ou `etablissement` |
| `signe_a` | timestamp UTC de validation OTP |
| `ip_signature` | IP source (capturée serveur via `request.headers.x-forwarded-for`) |
| `user_agent` | UA navigateur |
| `hash_document` | SHA-256 hex du HTML signé |
| `otp_envoye_a` / `otp_valide_a` | horodatages OTP |
| `otp_code_hash` | hash SHA-256 de l'OTP + sel (jamais clair) |
| `otp_tentatives` | compteur (max 5) |
| `sms_envoyes_count` / `sms_premier_envoi_a` | anti-abus (max 3 / 24h) |
| `statut_signature` | en_attente / otp_envoye / signe / refuse / expire |
| `psc_session_active` / `rpps_verifie` / `traits_identite_verifies` | flags identité |

## Vérification d'intégrité

À tout moment, l'intégrité du document signé peut être vérifiée :

1. Récupérer `storage_path` depuis `contrats_mission`
2. Télécharger le HTML depuis bucket `contrats-signes` (signed URL via RPC `fn_contrat_storage_path`)
3. Calculer SHA-256 du HTML téléchargé
4. Comparer avec `signatures_contrats.hash_document` du signataire concerné
5. Identité ↔ preuve : si égalité, le document n'a pas été modifié depuis la signature

La page `/contrat/:id/certificat` affiche cette empreinte et l'explication
pédagogique (cf. `CertificatSignaturePage.tsx`).

## Codes d'erreur retournés par les RPCs

| Code | Cause | Action UI |
|---|---|---|
| `NON_AUTHENTIFIE` | Session expirée | Bandeau "reconnectez-vous" |
| `NON_AUTORISE` | Pas partie au contrat | Bandeau bloquant |
| `CONTRAT_INTROUVABLE` | mauvais ID | "rechargez la page" |
| `CONTRAT_INACTIF` | statut ANNULE/EXPIRE | Bandeau bloquant |
| `CONTRAT_DEJA_COMPLET` | déjà signé par les 2 | Bandeau bloquant |
| Ordre des signatures | établissement ou soignant en premier | Le contrat devient complet après les deux signatures |
| `TELEPHONE_MANQUANT` | tél non renseigné | Bandeau "complétez votre profil" |
| `TROP_DE_SMS` | 3 envois atteints / 24h | Bandeau anti-abus |
| `OTP_NON_DEMANDE` | "Signer" sans avoir demandé OTP | Notification |
| `OTP_EXPIRE` | OTP > 10 min | "Demandez un nouveau code" |
| `OTP_INCORRECT` | mauvais code | Compteur tentatives_restantes |
| `TROP_DE_TENTATIVES` | 5 erreurs OTP | "Renvoyez un nouveau code SMS" |
| `DEJA_SIGNE` | rôle déjà signé | Bandeau bloquant |
| `HASH_DOCUMENT_CHANGE` | hash différent à signature | "rechargez la page" |

## Ordre obligatoire soignant-puis-étab

Le backend (`fn_envoyer_otp_signature`) refuse explicitement l'envoi d'un OTP à
l'établissement tant que `contrats_mission.signature_soignant` n'est pas `true`.

Référence légale : art. L1242-13 Code du travail — l'employeur ne peut signer
seul un CDD avant le salarié (le contrat doit être remis dans les 2 jours
ouvrables, et la signature du salarié vaut acceptation).

## Limites anti-abus (Sprint 2 PR 1)

- **5 tentatives OTP max** par envoi (puis "TROP_DE_TENTATIVES")
- **3 envois SMS max / 24h** par contrat × rôle (puis "TROP_DE_SMS")
- **10 minutes** de validité OTP
- Fenêtre 24h reset automatiquement

Renforcement futur (Sprint 3+) : rate-limit IP via `_shared/rate-limit.ts`,
captcha sur 3e tentative, alertes Sentry au-delà d'un seuil suspect.
