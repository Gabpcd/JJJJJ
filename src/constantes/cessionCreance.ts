// Cession de créance — Articles 1321 et suivants du Code civil
// Document signé mission par mission lorsque le soignant demande une avance d'affacturage.
// Le soignant transfère la propriété de la créance à Jolene, qui peut alors la vendre à un factor.

export const CESSION_CREANCE_VERSION = '1.0';

export const CESSION_CREANCE_TEXTE = `
# Cession de créance

**Articles 1321 à 1326 du Code civil**

---

## 1. Parties

**LE CÉDANT** : Le professionnel de santé libéral (« le Soignant »), titulaire d'une créance sur l'établissement de santé débiteur de la facture concernée.

**LE CESSIONNAIRE** : La société Jolene SAS (« Jolene »), à qui le Soignant cède la créance.

---

## 2. Créance cédée

Le Soignant cède à Jolene, qui accepte, **la créance** qu'il détient sur l'établissement de santé débiteur, telle qu'elle résulte de la facture d'honoraires identifiée ci-dessus, pour son montant nominal exact.

Cette créance comprend :
- Le **principal** (montant TTC de la facture)
- Les **intérêts éventuels** courus à compter de l'échéance
- Tous les **droits accessoires** attachés à la créance

---

## 3. Effets de la cession

À compter de la signature électronique de la présente cession :

1. **Jolene devient propriétaire** de la créance et est seule habilitée à en recevoir le paiement de l'établissement débiteur
2. Le Soignant **garantit** l'existence de la créance, son caractère certain, liquide et exigible à son échéance
3. Jolene est autorisée à **vendre** ou à **transférer** cette créance à un tiers (notamment un affactureur) sans que le consentement supplémentaire du Soignant soit requis
4. Le Soignant **cesse d'être créancier** de l'établissement pour cette facture spécifique

---

## 4. Notification de la cession

Conformément à l'**article 1324 du Code civil**, la cession sera **opposable à l'établissement débiteur** par sa notification ou par sa prise d'acte.

Le Soignant autorise expressément Jolene (et le cas échéant l'affactureur cessionnaire ultérieur) à effectuer cette notification au nom du Soignant.

---

## 5. Contrepartie versée au Soignant

En échange de cette cession, Jolene s'engage à verser au Soignant :

- Le **montant net de la créance**, déduction faite des **frais d'affacturage** retenus par l'affactureur partenaire
- Et déduction faite des **frais Jolene** prévus dans les conditions générales

Ce versement intervient sous **24 à 48 heures ouvrées** après la confirmation par l'affactureur partenaire.

Le détail des frais est affiché de manière transparente avant validation de la cession et figure dans le récapitulatif post-opération.

---

## 6. Garantie du Soignant

Le Soignant **garantit** :

- **L'existence de la créance** au moment de la cession
- L'**absence de litige connu** avec l'établissement débiteur sur la prestation facturée
- L'**absence de double cession** ou de paiement déjà reçu
- La **conformité de la prestation** facturée à ce qui a été convenu

En cas de **fausse déclaration** ou de **contestation de la créance** par l'établissement débiteur du fait du Soignant, ce dernier s'engage à **rembourser** Jolene (ou l'affactureur cessionnaire) du montant avancé.

---

## 7. Caractère limité de la cession

La présente cession porte **uniquement sur la créance identifiée ci-dessus**. Elle n'emporte aucun engagement du Soignant sur ses autres créances présentes ou futures.

Chaque facture donne lieu à une **cession distincte** que le Soignant accepte ou refuse librement.

---

## 8. Absence de lien de subordination

Le Soignant **demeure professionnel libéral indépendant**. La cession de créance n'emporte aucun lien de subordination avec Jolene, ne modifie pas son statut fiscal ou social, et ne constitue ni une relation salariale ni un contrat de travail temporaire.

---

## 9. Preuve de l'acceptation

L'acceptation de la présente cession s'effectue par **signature électronique explicite** sur la plateforme Jolene. La signature est horodatée et fait l'objet d'un enregistrement comprenant la date et l'heure, l'adresse IP, le navigateur utilisé, le numéro de version du document, et un hash cryptographique du texte signé.

Cet enregistrement constitue la **preuve opposable** de l'acceptation, conformément aux articles 1366 et 1367 du Code civil relatifs à la preuve électronique.

---

## 10. Droit applicable

La présente cession est soumise au **droit français**. Tout litige relatif à son interprétation ou son exécution relèvera de la compétence des tribunaux français.

---

**Version** : ${CESSION_CREANCE_VERSION}
**Mise à jour** : 7 avril 2026
`.trim();

export async function hashCessionTexte(texte: string): Promise<string> {
  const encoder = new TextEncoder();
  const data = encoder.encode(texte);
  const hashBuffer = await crypto.subtle.digest('SHA-256', data);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  return hashArray.map(b => b.toString(16).padStart(2, '0')).join('');
}
