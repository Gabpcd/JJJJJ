# Registre des traitements — Jolene SAS

Conforme à l'**article 30 du RGPD** (registre des activités de traitement).

Date de mise à jour : 28 avril 2026
Responsable de traitement : **Jolene SAS**
DPO : Gabrielle Picard (dpo@jolene.app)

## Identification du responsable de traitement

| Champ | Valeur |
|---|---|
| Raison sociale | Jolene SAS |
| Forme juridique | Société par actions simplifiée |
| SIREN | (à compléter par Gabrielle) |
| Siège social | (à compléter) |
| Représentant légal | Gabrielle Picard |
| DPO | Gabrielle Picard (dpo@jolene.app) |

## Traitements

### T-01 — Gestion des comptes soignants

| Champ | Valeur |
|---|---|
| Finalité | Inscription, authentification et gestion du compte des professionnels de santé |
| Base légale | Exécution du contrat (RGPD art. 6.1.b) |
| Catégories de personnes | Soignants (IDE, médecins, AS/AES, paramédicaux, sages-femmes, etc.) |
| Catégories de données | Identité (nom, prénom, date naissance), contact (email, tél), adresse, RPPS, ADELI (legacy), profession, type d'exercice (LIBERAL/SALARIE/MIXTE), photo profil |
| Données sensibles | Aucune (le RPPS n'est pas une donnée de santé au sens L.1111-8 CSP) |
| Destinataires | Soignant lui-même, admin Jolene, étabs avec mission active |
| Transferts hors UE | Aucun (Supabase Paris) |
| Durée de conservation | Compte actif : durée relation contractuelle. Compte supprimé : 3 ans (anonymisation immédiate, conservation pour preuves légales) |
| Mesures de sécurité | RLS Postgres, chiffrement at rest AES-256, MFA disponible, rate-limit Auth |

### T-02 — Vérification d'identité (KYC soignants)

| Champ | Valeur |
|---|---|
| Finalité | Vérifier l'éligibilité d'un soignant à exercer (RPPS, diplômes, identité) |
| Base légale | Obligation légale (art. L4111-1 CSP, RGPD art. 6.1.c) |
| Catégories de données | Carte d'identité (PDF/image), diplôme (PDF/image), attestation honneur, RPPS API ANS |
| Données sensibles | Documents d'identité (catégorie 9 RGPD si lisibilité raciale possible) |
| Destinataires | Admin Jolene (vérification), IA Anthropic Claude (extraction OCR sans rétention) |
| Transferts hors UE | Anthropic USA (Standard Contractual Clauses signées) |
| Durée de conservation | Documents : 5 ans après dernière mission (obligation santé). Vérifications : audit append-only pendant 10 ans |
| Mesures de sécurité | Storage Supabase chiffré, signed URLs avec expiration 1h, RLS strictes |

### T-03 — Mise en relation soignants ↔ établissements

| Champ | Valeur |
|---|---|
| Finalité | Permettre aux soignants de candidater à des missions publiées par les étabs |
| Base légale | Exécution du contrat (RGPD art. 6.1.b) |
| Catégories de données | Profil soignant (résumé), mission, candidature, message, CV partiel (expérience, spécialités) |
| Données sensibles | Aucune |
| Destinataires | Soignant, étab destinataire, admin Jolene |
| Transferts hors UE | Aucun |
| Durée de conservation | Candidatures : durée relation + 3 ans (preuves) |
| Mesures de sécurité | RLS strictes, exclusions configurables côté étab |

### T-04 — Gestion des présences (pointage GPS)

| Champ | Valeur |
|---|---|
| Finalité | Vérifier la présence effective des soignants sur les missions |
| Base légale | Exécution du contrat + intérêt légitime (lutte contre la fraude au pointage) |
| Catégories de données | Coordonnées GPS arrivée/départ (lat/lng + précision), IP, terminal (modèle), distance étab, alertes téléportation |
| Données sensibles | Géolocalisation (catégorie spéciale potentielle) |
| Destinataires | Soignant lui-même, étab de la mission, admin Jolene |
| Transferts hors UE | Aucun |
| Durée de conservation | Coordonnées GPS : **anonymisées après 90 jours** (cron `fn_anonymiser_gps_anciennes`). Présences : 5 ans (preuves) |
| Mesures de sécurité | Consentement explicite (`soignants.consentement_gps`), anonymisation auto |

### T-05 — Facturation honoraires (mandataire art. 289 I-2 CGI)

| Champ | Valeur |
|---|---|
| Finalité | Émettre les factures pour les soignants LIBERAL/MIXTE en qualité de mandataire |
| Base légale | Obligation légale fiscale (art. 289 I-2 CGI, art. 261-4 CGI, RGPD art. 6.1.c) |
| Catégories de données | Identité soignant + étab, SIRET, RIB last4, montants, mandat de facturation signé (IP, hash, version) |
| Données sensibles | Aucune (RIB last4 = pseudonymisé) |
| Destinataires | Soignant, étab destinataire, admin, Defacto (cession créance optionnelle), Chorus Pro (secteur public), comptable |
| Transferts hors UE | Aucun (Defacto FR, Chorus FR) |
| Durée de conservation | **10 ans** (art. L102 B LPF, obligation fiscale française) |
| Mesures de sécurité | Numérotation séquentielle immutable, triggers `trg_fh_immutability`, audit append-only `invoice_audit_log` (10 ans) |

### T-06 — Bulletin de paie (soignants SALARIE/MIXTE)

| Champ | Valeur |
|---|---|
| Finalité | Émettre le bulletin de paie des soignants en exercice salarié |
| Base légale | Obligation légale (art. R3243-1 CTW, RGPD art. 6.1.c) |
| Catégories de données | Identité soignant, étab employeur, NIR (n° sécu), période, brut, cotisations, net, IFM/ICP |
| Données sensibles | NIR = donnée identifiante particulière (CNIL délibération 2019-021) |
| Destinataires | Soignant, étab employeur, admin |
| Transferts hors UE | Aucun |
| Durée de conservation | **5 ans** par l'employeur (art. L3243-4 CTW), conservation indéfinie côté salarié |
| Mesures de sécurité | RLS strictes, NIR exclu de l'export RGPD, triggers immutabilité `trg_bp_immutability`, GRANT INSERT/UPDATE absent pour authenticated (RPC SECURITY DEFINER seules) |

### T-07 — Paiement (Stripe Connect)

| Champ | Valeur |
|---|---|
| Finalité | Encaisser les paiements établissement → Jolene + reverser aux soignants |
| Base légale | Exécution du contrat (RGPD art. 6.1.b) |
| Catégories de données | Stripe customer/account ID, IBAN last4, transferts, payouts |
| Données sensibles | Aucune |
| Destinataires | Soignant, étab, admin, Stripe (sous-traitant DPA signé) |
| Transferts hors UE | Stripe Ireland (UE), backup USA (SCC Stripe DPA) |
| Durée de conservation | 10 ans (obligation comptable) |
| Mesures de sécurité | Stripe gère les données carte (PCI-DSS L1), Jolene ne stocke que les IDs et 4 derniers chiffres |

### T-08 — Communication (notifications, emails, SMS)

| Champ | Valeur |
|---|---|
| Finalité | Notifier les utilisateurs (mission, paiement, alerte) |
| Base légale | Exécution contrat + intérêt légitime |
| Catégories de données | Email, téléphone, contenu notification |
| Destinataires | Soignant/étab, Resend (email), Twilio (SMS) |
| Transferts hors UE | Resend USA (SCC), Twilio USA (SCC) |
| Durée de conservation | Logs envois : 1 an. Tokens push : durée d'usage. SMS opt-out respecté (`soignants.sms_actif`) |
| Mesures de sécurité | Captcha Turnstile sur inscription, opt-out SMS explicite |

### T-09 — Audit logs (conformité)

| Champ | Valeur |
|---|---|
| Finalité | Traçabilité des actions utilisateur et admin pour conformité RGPD/fiscale |
| Base légale | Obligation légale (RGPD art. 30, art. 32 sécurité) |
| Catégories de données | Identifiant acteur, action, ressource, IP, user-agent |
| Destinataires | Admin Jolene uniquement |
| Transferts hors UE | Aucun |
| Durée de conservation | **3 ans** actions user, **5 ans** actions admin (recommandation CNIL), **10 ans** invoice_audit_log (fiscal) |
| Mesures de sécurité | Append-only (UPDATE/DELETE bloqués), RLS admin only |

### T-10 — Géolocalisation établissements (carte missions)

| Champ | Valeur |
|---|---|
| Finalité | Affichage des missions sur carte (Leaflet OpenStreetMap) |
| Base légale | Exécution du contrat (RGPD art. 6.1.b) |
| Catégories de données | Adresse étab, lat/lng, ville |
| Destinataires | Soignants, OpenStreetMap (tiles uniquement, pas de transfert de données utilisateur) |
| Transferts hors UE | Aucun (OSM Allemagne) |
| Durée de conservation | Durée de la relation établissement |

## Sous-traitants (annexe)

Liste détaillée dans `docs/dpa-template.md`.

| Sous-traitant | Rôle | Localisation | Encadrement |
|---|---|---|---|
| Supabase | Hébergement DB + Auth + Storage | AWS Paris (UE) | DPA signé |
| Vercel | Hébergement frontend | AWS USA + edges UE | DPA signé + SCC |
| Stripe | Paiements | Ireland (UE) + USA backup | DPA signé + SCC |
| Resend | Emails transactionnels | USA | SCC |
| Twilio | SMS | USA | SCC |
| YouSign | Signature électronique contrats | France | DPA signé (UE) |
| Anthropic | OCR documents (Claude) | USA, no-retention | SCC |
| Cloudflare | CDN + Captcha Turnstile | Worldwide | DPA Cloudflare |
| Sentry | Monitoring erreurs | USA | SCC |
| OpenStreetMap | Cartes | Allemagne (UE) | Pas de transfert |
| Defacto | Affacturage soignants | France | DPA + cession créance |
| Chorus Pro / PISTE | Facturation secteur public | France (gov) | API publique gov.fr |
| ProSantéConnect | SSO santé | France (ANS) | API publique |

## Droits des personnes

| Droit | Comment l'exercer | Délai max |
|---|---|---|
| Accès (art. 15) | RPC `fn_exporter_mes_donnees` ou `/legal/confidentialite` → contact DPO | 1 mois |
| Rectification (art. 16) | UI profil ou demande dpo@jolene.app | 1 mois |
| Effacement (art. 17) | RPC `fn_supprimer_compte_rate_limited` ou `fn_supprimer_compte_etablissement_rate_limited` | Immédiat (sauf obligations conservation) |
| Limitation (art. 18) | Demande dpo@jolene.app | 1 mois |
| Portabilité (art. 20) | RPC `fn_exporter_mes_donnees` (JSON) | 1 mois |
| Opposition (art. 21) | Demande dpo@jolene.app | 1 mois |
| Réclamation (art. 77) | CNIL (cnil.fr/plaintes) | — |

## Mesures de sécurité techniques

- **Chiffrement** : at rest AES-256 (Supabase RDS), in transit TLS 1.3.
- **Authentification** : Supabase Auth, MFA disponible, rate-limit anti brute-force.
- **RLS** : 87 tables, 100 % couvertes (cf. `docs/audit-rls.md`).
- **Audit** : append-only sur `journaux_audit` et `invoice_audit_log`.
- **Captcha** : Turnstile sur les formulaires Web publics à risque ; jamais sur la connexion ni dans les apps natives.
- **Anti-bot** : rate-limit 8 edge functions (verify-rpps, verify-siret, etc.).
- **Source maps Sentry** : symbolisation prod activée si `SENTRY_AUTH_TOKEN`.
- **Hardening anti-seed** : triggers `fn_anti_seed_*` bloquent les INSERT incohérents.

## Notification de violation (art. 33)

En cas de violation susceptible d'engendrer un risque pour les droits :

1. T+0 : détection (Sentry alert, monitoring, signalement utilisateur).
2. T+1h : Gabrielle évalue gravité avec checklist CNIL.
3. T+24h : si risque élevé, notification CNIL via cnil.fr/notification-violations.
4. T+72h max (CNIL) : notification finale CNIL avec impact, mesures, contacts.
5. Si risque élevé pour personnes : notification individuelle (email).
6. Documentation interne dans `journaux_audit` (action `ADMIN_ACTION` + détails).
