-- J2.3.C — Article centre d'aide : "Je n'ai pas reçu d'email"
-- Pour gérer le warmup réputation Outlook (domaine jolene.app récent).
-- Cf. docs/deliverability-warmup.md.

INSERT INTO public.articles_aide (slug, titre, contenu, audience, categorie, ordre_affichage, publie)
VALUES (
  'je-n-ai-pas-recu-d-email',
  'Je n''ai pas reçu d''email de Jolene',
$$Si vous attendez un email de Jolene (confirmation d'inscription, mission acceptée, facture, etc.) et qu'il n'arrive pas, voici les étapes pour le retrouver.

## Pourquoi cela arrive ?

Notre domaine `jolene.app` a été créé récemment (avril 2026). Les services anti-spam (Outlook, Hotmail, Live, parfois Gmail) sont **plus stricts avec les nouveaux domaines** : ils peuvent les classer en spam même quand l'authentification (SPF, DKIM, DMARC) est correcte.

C'est temporaire. Notre réputation s'améliore au fur et à mesure que des destinataires interagissent avec nos emails (lus, marqués comme "non-spam", ajoutés aux contacts). Comptez **1 à 3 mois** pour que la situation soit normalisée auprès des principaux fournisseurs.

## Où chercher l'email manquant ?

### 1. Dossier "Courrier indésirable" (ou "Spam")

C'est l'endroit le plus probable. Cherchez :
- Expéditeur : `bonjour@jolene.app`
- Sujet contenant **"Jolene"** ou **"Bienvenue"** / **"Mission"** / **"Facture"** selon le cas

**Outlook web** : volet de gauche → **Courrier indésirable**
**Outlook desktop** : dossiers → **Junk Email** ou **Courrier indésirable**
**Gmail** : volet de gauche → **Plus** → **Spam**
**iCloud** : **Indésirable**

### 2. Onglets "Promotions" / "Notifications" (Gmail)

Gmail trie automatiquement certains emails dans des onglets séparés. Vérifiez :
- **Promotions** (souvent où vont les emails marketing/récap)
- **Notifications**

## Comment ne plus rater nos emails ?

Une fois l'email retrouvé, faites ces 3 actions :

### 1. Marquez comme "Pas un courrier indésirable"

**Outlook** : clic droit → **Marquer comme étant légitime** → confirmer
**Gmail** : ouvrir l'email → bouton **Signaler comme non-spam** en haut

### 2. Ajoutez `bonjour@jolene.app` à vos contacts

**Outlook web** : ouvrir l'email → clic sur l'expéditeur → **Ajouter aux contacts**
**Gmail** : ouvrir l'email → cliquer sur l'expéditeur → **Ajouter à mes contacts**
**iCloud** : Mail → Préférences → Règles → ajouter règle "expéditeur `@jolene.app` → Inbox"

### 3. (Outlook avancé) Créer une règle automatique

Dans Outlook web : **Paramètres** → **Email** → **Règles** → **+ Ajouter une nouvelle règle**.
- Condition : *Expéditeur contient* `@jolene.app`
- Action : *Déplacer vers* la **Boîte de réception** + *Marquer comme lu, non*

Toutes nos communications arriveront ainsi directement en boîte de réception.

## Et si l'email n'est même pas dans le spam ?

Vérifiez dans cet ordre :

1. **Orthographe de votre adresse email** dans votre profil Jolene (Paramètres → Profil)
   — un email mal saisi est le cas le plus fréquent.
2. **Espace boîte aux lettres** : si votre boîte est pleine, les nouveaux mails sont rejetés.
3. **Filtre de blocage** : certaines entreprises bloquent les nouveaux domaines au niveau du serveur — testez avec une adresse personnelle si vous utilisez une boîte pro.

## Contactez-nous

Si rien ne fonctionne, écrivez-nous à <a href="mailto:bonjour@jolene.app">bonjour@jolene.app</a> ou via le centre d'aide en précisant :
- Votre adresse email Jolene
- Le type d'email attendu (bienvenue, mission, etc.)
- La date approximative

Nous vérifierons les logs d'envoi côté Resend (notre prestataire email) pour confirmer qu'il a bien été émis et identifier la cause précise.
$$,
  'COMMUN',
  'Inscription et profil',
  120,
  true
)
ON CONFLICT (slug) DO UPDATE SET
  contenu = EXCLUDED.contenu,
  titre = EXCLUDED.titre,
  audience = EXCLUDED.audience,
  categorie = EXCLUDED.categorie,
  publie = true,
  mis_a_jour_le = now();
