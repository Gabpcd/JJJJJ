# DPA — Data Processing Agreement (template pilotes)

Modèle d'accord de traitement à signer avec chaque établissement client
(art. 28 RGPD). À adapter par avocat avant signature avec les premiers pilotes.

---

## Préambule

**Entre :**

- **Jolene SAS**, [adresse à compléter], représentée par Gabrielle Picard,
  ci-après « le **Sous-traitant** » (ou Responsable de Traitement Conjoint
  selon scope) ;

- **[Nom de l'établissement]**, [forme juridique], SIRET [à compléter],
  [adresse], représenté par [nom], en qualité de [fonction], ci-après
  « le **Responsable de Traitement** » ou « le **Client** ».

## Article 1 — Objet

Le présent DPA encadre le traitement par Jolene SAS des données à caractère
personnel pour le compte du Client, dans le cadre des services suivants :

- **Mise en relation** soignants ↔ établissements via la plateforme Jolene.
- **Facturation** des honoraires soignants (mandataire art. 289 I-2 CGI).
- **Bulletin de paie** des soignants SALARIE/MIXTE (art. R3243-1 CTW).
- **Traçabilité** des présences via pointage GPS (consentement soignant).
- **Communication** transactionnelle (email, SMS, push).

## Article 2 — Nature, finalité et durée du traitement

| Item | Détail |
|---|---|
| Nature | Collecte, stockage, consultation, transmission, anonymisation |
| Finalité | Cf. registre des traitements `docs/registre-traitements.md` (T-01 à T-10) |
| Durée | Durée du contrat de service + délais légaux de conservation post-résiliation |

## Article 3 — Catégories de personnes concernées

- Soignants (libéraux, salariés, mixtes).
- Personnel administratif des établissements clients.
- Personnel de Jolene SAS (admin plateforme).

## Article 4 — Catégories de données

- Identification (nom, prénom, email, téléphone, RPPS/ADELI, SIRET).
- Documents d'identité et diplômes. Jolene conserve la déclaration sur
  l'honneur relative aux vaccinations obligatoires et à la médecine du travail,
  ainsi que sa date de signature ; les justificatifs médicaux sont vérifiés en
  présentiel par les établissements et ne sont pas conservés chez Jolene.
- Données de mission et de présence (pointage GPS, photos pointage).
- Données financières (factures, virements, RIB last4, Stripe IDs).
- Données de paie (NIR, salaire brut/net, cotisations, période).
- Communications (chat in-app, notifications, emails, SMS).

## Article 5 — Obligations du Sous-traitant (Jolene)

5.1. **Confidentialité** : Jolene s'engage à traiter les données uniquement
selon les instructions documentées du Responsable de Traitement.

5.2. **Sécurité** (art. 32 RGPD) :
- Chiffrement at rest (AES-256 RDS) et in transit (TLS 1.3).
- RLS Postgres sur 100 % des tables sensibles.
- Audit append-only des actions critiques.
- Captcha anti-bot sur les endpoints d'inscription et d'authentification.
- Rate-limiting sur les edge functions sensibles.
- Secrets non logués, pas de circulation hors runtime Supabase.

5.3. **Sous-traitance ultérieure** : Jolene utilise les sous-traitants listés
en annexe (cf. `docs/registre-traitements.md` § Sous-traitants). Toute
substitution sera notifiée 30 jours avant changement.

5.4. **Notification de violation** : Jolene s'engage à notifier le Client dans
**24 heures** maximum après détection d'une violation impactant ses données,
avec :
- description de la violation (nature, volume, type de données),
- mesures correctives prises,
- impact estimé.

5.5. **Droits des personnes** : Jolene assiste le Client pour répondre aux
demandes des personnes (accès, rectification, effacement) :
- via les RPC `fn_exporter_mes_donnees`, `fn_exporter_rgpd_etablissement`,
  `fn_supprimer_compte_rate_limited`, `fn_supprimer_compte_etablissement_rate_limited`.
- via demande au DPO Jolene (dpo@jolene.app) sous 1 mois max.

5.6. **Audit** : le Client peut demander un audit annuel de la conformité
RGPD de Jolene. L'audit se fait sur dossier (rapports SOC2 si disponibles,
politiques internes, journaux d'audit anonymisés). Audit physique ou intrusif
exclu (Jolene est multi-tenant).

5.7. **Retour ou destruction des données** : à la fin du contrat :
- Données fiscales conservées 10 ans (obligation légale, art. L102 B LPF).
- Bulletins de paie conservés 5 ans (art. L3243-4 CTW).
- Audit logs conservés 5 ans.
- Autres données : anonymisation immédiate sur demande, ou export JSON
  livré au Client avant suppression (RPC `fn_exporter_rgpd_etablissement`).

## Article 6 — Obligations du Responsable de Traitement (Client)

6.1. Le Client s'engage à :
- Informer ses soignants et personnel des traitements effectués.
- Recueillir les consentements quand requis (notamment GPS).
- Ne pas transmettre à Jolene de données non nécessaires aux finalités du contrat.
- Notifier les changements de personnel admin (départ → désactivation compte).

6.2. Le Client est responsable de la légalité des données qu'il confie à
Jolene (notamment : données de soignants tiers, demandes de mission contenant
données de patients = INTERDIT).

## Article 7 — Sous-traitants ultérieurs (annexe)

| Sous-traitant | Rôle | Localisation | Encadrement |
|---|---|---|---|
| Supabase | Hébergement DB + Auth + Storage | AWS Irlande (UE) | DPA Supabase |
| Vercel | Hébergement frontend | AWS USA + edges UE | DPA Vercel + SCC |
| Stripe | Paiements | Ireland (UE) + USA | DPA Stripe + SCC |
| Resend | Emails transactionnels | USA | SCC |
| Twilio | SMS | USA | SCC |
| YouSign | Signature électronique | France | DPA YouSign |
| Anthropic | OCR documents IA (Claude) | USA, no-retention | SCC |
| Cloudflare | CDN + Captcha Turnstile | Worldwide | DPA Cloudflare |
| Sentry | Monitoring erreurs | USA | SCC |
| Defacto | Affacturage soignants | France | DPA + cession |
| Chorus Pro / PISTE | Facturation gov | France (gov.fr) | API gov |

Les Standard Contractual Clauses (SCC) sont signées avec chaque sous-traitant
hors UE conformément à la décision (UE) 2021/914.

## Article 8 — Transferts hors UE

Les transferts hors UE sont **strictement encadrés par SCC** signées avec
chaque sous-traitant hors UE. Pour les transferts vers les USA, la décision
d'adéquation **Data Privacy Framework** (CE 10/07/2023) est invoquée
quand applicable (Stripe, Sentry, Anthropic, Resend, Twilio sont
DPF-certifiés).

## Article 9 — Responsabilités

9.1. **En cas de manquement** Jolene au DPA causant un dommage au Client ou
à une personne concernée, la responsabilité de Jolene est engagée à hauteur
de [montant à négocier — typiquement 1× les sommes versées par le Client
sur les 12 derniers mois].

9.2. **Force majeure** : sans préjudice des obligations RGPD impératives
(notification CNIL etc.).

## Article 10 — Durée et résiliation

10.1. Le DPA prend effet à sa signature et reste en vigueur tant que Jolene
traite des données pour le compte du Client.

10.2. Résiliation immédiate possible par le Client en cas de manquement grave
de Jolene au DPA, sans préjudice des obligations de conservation légales.

## Article 11 — Loi applicable et juridiction

Droit français. Tribunal compétent : tribunaux de Paris.

---

**Fait à _________________, le _________________**

| Pour Jolene SAS | Pour [Établissement] |
|---|---|
| Gabrielle Picard | [Nom] |
| Présidente | [Fonction] |
| Signature : | Signature : |

---

## Annexe A — Sous-traitants (état au 28/04/2026)

Liste exhaustive maintenue dans `docs/registre-traitements.md` § Sous-traitants.
Mise à jour à chaque changement avec notification 30 jours préalable.

## Annexe B — Coordonnées DPO

- **DPO Jolene** : Gabrielle Picard, dpo@jolene.app
- **Contact urgence** : (à compléter selon escalade)
- **Adresse postale** : (à compléter)

## Annexe C — Procédure de notification de violation

Voir `docs/registre-traitements.md` § Notification de violation (art. 33).
