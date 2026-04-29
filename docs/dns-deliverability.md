# Délivrabilité email — Diagnostic spam Outlook + actions DNS

## Contexte (29 avril 2026)

Le compte test `gabrielle.pcd@outlook.com` reçoit les emails BIENVENUE
**en spam** sur Outlook. Le doublon BIENVENUE est désormais corrigé
(commit 80c79ebf). Reste la délivrabilité.

## Causes probables (par ordre)

1. **Domaine `jolene.app` jeune** : faible réputation. Outlook (Microsoft
   SmartScreen) est particulièrement strict avec les domaines récents.
   Pas de fix code → "warmup" naturel.
2. **DMARC absent ou trop laxiste** (`p=none`) : Outlook met en spam
   par défaut sans DMARC strict.
3. **DKIM Resend non vérifié sur jolene.app** : le sender `noreply@jolene.app`
   nécessite un DKIM signé pour passer.
4. **SPF mal aligné** : si l'envelope-from Resend (`bounces@send.resend.com`)
   et le From (`noreply@jolene.app`) ne sont pas alignés via SPF/DKIM, échec
   d'authentification.
5. **From `noreply@`** : signal négatif mineur — Outlook préfère
   `bonjour@`, `equipe@`, etc.

## Action 1 — Vérifier le statut Resend

Connectez-vous au [dashboard Resend](https://resend.com/domains).

1. Vérifiez que **`jolene.app`** apparaît dans la liste des domaines.
2. Pour `jolene.app`, le statut doit être **« Verified »**. Si ce n'est
   pas le cas, Resend affiche les records DNS manquants à ajouter.

Tant que `jolene.app` n'est pas Verified dans Resend, **TOUS les emails
partent depuis le pool partagé `resend.dev`** (very low reputation) ou
sont rejetés. Outlook spam quasi-systématiquement.

## Action 2 — Compléter les records DNS (provider = Vercel)

Vercel a son DNS natif (`@vercel/dns`). Pour ajouter des records,
allez dans `Vercel → jolene project → Settings → Domains → jolene.app
→ Manage DNS Records`.

Ajoutez/vérifiez les **5 records** suivants (Resend les fournit dans le
dashboard quand on click "Add domain") :

### SPF (1 record TXT à la racine)
```
Name : @  (ou jolene.app)
Type : TXT
Value : v=spf1 include:amazonses.com ~all
```
Si vous avez déjà un record SPF existant (ex. `v=spf1 include:_spf.google.com`
pour Gmail Workspace), il faut **fusionner** (un seul SPF par domaine) :
```
v=spf1 include:_spf.google.com include:amazonses.com ~all
```

### DKIM Resend (3 records CNAME)
```
Name : resend._domainkey       Type : CNAME   Value : resend._domainkey.resend.com
Name : resend2._domainkey      Type : CNAME   Value : resend2._domainkey.resend.com
Name : resend3._domainkey      Type : CNAME   Value : resend3._domainkey.resend.com
```
(Resend utilise 3 paires de clés rotatives pour résilience.)

### DMARC (1 record TXT)
```
Name : _dmarc
Type : TXT
Value : v=DMARC1; p=quarantine; rua=mailto:postmaster@jolene.app; aspf=s; adkim=s
```
Notes :
- `p=quarantine` (au lieu de `p=none`) demande aux receveurs (Outlook)
  de mettre les emails non-authentifiés en spam → mais ALIGNE notre
  domaine avec un signal "on prend l'auth au sérieux", ce qui améliore
  globalement notre réputation.
- `rua=mailto:postmaster@jolene.app` reçoit les rapports DMARC quotidiens.
  Configurez `postmaster@jolene.app` comme alias vers votre boîte.
- `aspf=s; adkim=s` = alignement strict (recommandé après DKIM en place).

### Vérification
Une fois les records DNS posés (propagation 5-30 min) :
1. Cliquez **"Verify DNS Records"** dans Resend → doit passer Verified.
2. Outils externes : [mxtoolbox.com/spf](https://mxtoolbox.com/spf.aspx),
   [mxtoolbox.com/dmarc](https://mxtoolbox.com/dmarc.aspx),
   [mxtoolbox.com/DKIM](https://mxtoolbox.com/DKIM.aspx) (selector `resend`).

## Action 3 — Optionnel : changer le `from`

Le code envoie depuis `Jolene <noreply@jolene.app>`. Recommandation :
remplacer par `Jolene <bonjour@jolene.app>` (signal humain, mieux noté
par les filtres anti-spam).

Côté `supabase/functions/send-email/index.ts` ligne 1465 :
```diff
-from: 'Jolene <noreply@jolene.app>',
+from: 'Jolene <bonjour@jolene.app>',
```

L'adresse `bonjour@jolene.app` doit aussi être autorisée par Resend
(automatique si le domaine est Verified — toutes les adresses
`*@jolene.app` deviennent autorisées).

## Action 4 — Outlook spécifique : Postmaster Tools

Microsoft propose [SNDS](https://sendersupport.olc.protection.outlook.com/snds/)
(Smart Network Data Services) et [JMRP](https://sendersupport.olc.protection.outlook.com/pm/)
(Junk Mail Reporting Program) pour suivre la réputation côté Outlook.

Inscription gratuite avec votre IP d'envoi (IP Resend). Permet de
détecter spamtraps + complaints.

## Action 5 — Warmup (1-3 mois)

Les filtres Outlook montent en réputation au fur et à mesure des envois
légitimes. Tant que le volume est faible (early adopters), continuer
à demander aux destinataires de :
- Marquer `jolene.app` comme **Non spam** dans Outlook
- Ajouter `noreply@jolene.app` (ou `bonjour@`) à leurs **contacts**

Au bout de quelques semaines avec DKIM/DMARC en place + complaints
positives, Outlook descend automatiquement en boîte de réception.

## Validation après actions DNS

Une fois les 5 records DNS en place + Resend Verified :

1. Triggez un test E2E :
   - Inscription via `gabrielle.pcd+test3@outlook.com` sur jolene.app
2. Email BIENVENUE_SOIGNANT doit arriver **en boîte de réception**
   (pas en spam) sur Outlook après ~2 minutes.
3. Vérifiez les headers de l'email reçu :
   - `Authentication-Results` doit avoir `spf=pass`, `dkim=pass`, `dmarc=pass`
   - `Received-SPF: Pass`
   - DKIM signature valide

Si toujours en spam après tout ça, le problème est purement réputationnel
(jolene.app trop jeune) → patience + warmup naturel. Pas de fix code possible.
