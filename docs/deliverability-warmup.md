# Délivrabilité email — plan warmup réputation domaine

## Contexte (29 avril 2026)

Le domaine `jolene.app` a été créé en **avril 2026** (~1 mois). Pour les
fournisseurs Microsoft (Outlook, Hotmail, Live, MSN), les nouveaux
domaines arrivent quasi-systématiquement en spam, **même avec une
authentification SPF / DKIM / DMARC parfaite**. C'est une protection
contre les domaines jetables utilisés par les spammeurs.

Pour Gmail / iCloud, les emails arrivent généralement en boîte de
réception dès le départ (réputation moins stricte sur les nouveaux
domaines), mais peuvent être triés dans l'onglet *Promotions*.

## État actuel

| Élément                      | État    | Notes                                         |
|------------------------------|---------|-----------------------------------------------|
| SPF                          | ✅      | `v=spf1 include:amazonses.com ~all`           |
| DKIM (Resend, 3 sélecteurs)  | ✅      | `resend._domainkey`, `resend2…`, `resend3…`   |
| DMARC                        | ✅      | `v=DMARC1; p=quarantine; aspf=s; adkim=s` (strict) |
| Expéditeur                   | ✅      | `Jolene <bonjour@jolene.app>` (signal humain) |
| Domaine vérifié dans Resend  | ✅      | Verified                                      |
| Âge du domaine               | ⏳      | ~1 mois, jeune → spam Outlook attendu          |

**Statut délivrabilité observé** :
- Outlook / Hotmail / Live : **spam** (cf. test gabrielle.pcd@outlook.com test4)
- Gmail / iCloud / autres : pas encore testé largement, *boîte de réception*
  attendu

## Plan warmup (1-3 mois)

### Court terme (semaines 1-2) — actions ponctuelles

1. **Demander aux destinataires de marquer "non-spam"**
   - Page `/inscription/succes` (créée J2.3.C) prévient les utilisateurs
     Outlook + leur donne les actions concrètes
   - Article centre d'aide `/aide/je-n-ai-pas-recu-d-email`
2. **Ajouter `bonjour@jolene.app` aux contacts** : signal positif fort
3. **Répondre à un email reçu** depuis l'adresse de l'utilisateur :
   conversation bidirectionnelle = signal très positif.
4. **Inscription au programme Microsoft SNDS** (Smart Network Data Services)
   - URL : https://sendersupport.olc.protection.outlook.com/snds/
   - Utiliser l'IP d'envoi Resend (à récupérer dans le dashboard Resend)
   - Permet de monitorer la réputation IP côté Microsoft

### Moyen terme (mois 1-3) — volume + cohérence

1. **Volume régulier d'envois transactionnels**
   - Inscriptions soignants + étabs (~10-50/jour cible)
   - Série email J0/J1/J3/J7 par inscrit (déjà en place via cron)
   - Notifications mission (création, candidature, assignation, fin)
   - Factures + bulletins paie

2. **Pas de pic anormal** : éviter d'envoyer 1000 emails d'un coup → spamtrap

3. **Cohérence sender** : toujours `bonjour@jolene.app`, pas d'alternance
   avec d'autres adresses pour éviter de fragmenter la réputation

4. **Bounces gérés** : Resend gère automatiquement les hard bounces.
   Vérifier dashboard Resend chaque semaine pour identifier des problèmes
   massifs (>5 % bounces = problème).

### Long terme (mois 3-6) — réputation établie

Si tout se passe bien (taux d'ouverture > 20 %, faibles complaints), la
réputation Outlook devrait s'améliorer. Pas d'action particulière, juste
maintenir le rythme.

## Monitoring

### 1. Dashboard Resend
- URL : https://resend.com/emails
- Stats : envois, ouvertures, clics, bounces, complaints
- Alerte si taux bounces > 5 % ou complaints > 0.1 %

### 2. Microsoft SNDS (Outlook)
- À configurer après warmup initial
- Status réputation IP côté Outlook

### 3. Sentry (déjà configuré)
- Section dédiée : tag `composant:send-email` + erreurs
- Alertes Sentry sur erreurs Resend API

### 4. Table `emails_envoyes` (DB)
```sql
-- Taux de succès envois 7 derniers jours
SELECT
  date_trunc('day', cree_le) AS jour,
  count(*) AS total,
  count(*) FILTER (WHERE statut = 'ENVOYE') AS envoyes,
  count(*) FILTER (WHERE statut = 'ERREUR') AS erreurs,
  round(100.0 * count(*) FILTER (WHERE statut = 'ERREUR') / count(*), 2) AS pct_erreurs
FROM emails_envoyes
WHERE cree_le >= now() - interval '7 days'
GROUP BY 1 ORDER BY 1 DESC;
```

## Si le spam Outlook persiste après 6 mois

**À investiguer dans cet ordre** :

1. **Headers email** : récupérer un email reçu en spam, vérifier
   `Authentication-Results`. Si `dmarc=fail` ou `dkim=fail`, problème
   technique à fixer.

2. **Contenu email** : trop de liens ? Trop d'images ? Mots-clés spam
   (urgent, gratuit, gagner) ? Tester via outils comme
   [mail-tester.com](https://www.mail-tester.com/) — score idéal > 9/10.

3. **Volume / fréquence** : envoyer trop peu (= domaine "abandonné") ou
   trop souvent au même destinataire (= spam) sont tous deux pénalisés.

4. **Microsoft SNDS** : si l'IP Resend est listée en "spamtrap", contacter
   le support Resend pour rotation IP.

5. **Considérer changement de provider** (en dernier recours) :
   Postmark > SendGrid > Mailgun ont tous une réputation IP différente.
   ⚠️ Migrer un domaine existant chez un nouveau provider casse la
   réputation acquise — n'envisager que si Resend pose problème.

**À NE PAS FAIRE** : racheter un nouveau domaine (`jolene-app.fr`,
`jolene.io`, etc.) en pensant que ça résout le problème. Le nouveau
domaine repart à zéro et le problème de réputation est identique.

## Lien avec d'autres documents

- `docs/dns-deliverability.md` — config DNS détaillée (SPF, DKIM, DMARC)
- `docs/module-onboarding-emails.md` — série email J0/J1/J3/J7
- `docs/audit-stack-existante.md` — outils en place (Resend = transactionnel)
