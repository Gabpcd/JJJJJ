// Mandat de facturation — Article 289 I-2 du Code Général des Impôts
// Document légal permettant à Jolene d'émettre techniquement des factures au nom et pour le compte du soignant libéral.
// Le soignant reste le vendeur légal et juridique de la prestation. Jolene agit uniquement en qualité de mandataire technique.

export const MANDAT_FACTURATION_VERSION = '1.3';

// Info soignant à injecter dans le mandat lors du rendu. Les champs manquants
// sont remplacés par "—" pour ne pas générer un document faussement complet.
export interface SoignantMandatInfo {
  prenom?: string | null;
  nom?: string | null;
  profession?: string | null;
  professionLabel?: string | null;
  numero_rpps?: string | null;
  numero_adeli?: string | null;
  siret_liberal?: string | null;
  email?: string | null;
  adresse_rue?: string | null;
  adresse_code_postal?: string | null;
  adresse_ville?: string | null;
}

function formatValeur(v?: string | null): string {
  const s = (v || '').trim();
  return s.length > 0 ? s : '—';
}

function formatAdresse(info: SoignantMandatInfo): string {
  const rue = (info.adresse_rue || '').trim();
  const cp = (info.adresse_code_postal || '').trim();
  const ville = (info.adresse_ville || '').trim();
  const cpVille = [cp, ville].filter(Boolean).join(' ');
  const parts = [rue, cpVille].filter(Boolean);
  return parts.length > 0 ? parts.join(', ') : '—';
}

/**
 * Construit le texte du mandat de facturation en injectant les informations
 * personnelles du soignant dans la section "Parties".
 */
export function buildMandatFacturationTexte(info: SoignantMandatInfo): string {
  const nomComplet = [info.prenom, info.nom].filter(Boolean).join(' ') || '—';
  const profession = info.professionLabel || info.profession || '—';
  const rpps = formatValeur(info.numero_rpps);
  const adeli = formatValeur(info.numero_adeli);
  const siret = formatValeur(info.siret_liberal);
  const email = formatValeur(info.email);
  const adresse = formatAdresse(info);

  // On ne liste un numéro d'identification que s'il est réellement renseigné,
  // mais on affiche toujours les deux lignes RPPS/ADELI pour cohérence légale.
  const ligneRpps = `Numéro RPPS : ${rpps}`;
  const ligneAdeli = `Numéro ADELI : ${adeli}`;
  const ligneSiret = `SIRET : ${siret}`;
  const ligneAdresse = `Adresse professionnelle : ${adresse}`;
  const ligneEmail = `Email de contact : ${email}`;

  return `
# Mandat de facturation et d'encaissement

**Article 289 I-2 du Code Général des Impôts**

---

## 1. Parties

**LE MANDANT** — **${nomComplet}**, professionnel de santé libéral utilisateur de la plateforme Jolene (ci-après « le Soignant »).

Profession : **${profession}**

${ligneRpps}

${ligneAdeli}

${ligneSiret}

${ligneAdresse}

${ligneEmail}

**LE MANDATAIRE** : La société Jolene, SAS au capital social indiqué dans ses mentions légales, dont le siège social figure sur son site, représentée par son représentant légal (ci-après « Jolene »).

---

## 2. Objet du mandat

Par le présent mandat, le Soignant donne mandat à Jolene d'émettre des factures **en son nom et pour son compte** à destination des établissements de santé (cliniques, EHPAD, hôpitaux, HAD, centres de santé, pharmacies, etc.) auprès desquels il réalise des missions via la plateforme Jolene.

Ces factures matérialisent la rémunération des prestations professionnelles effectuées par le Soignant dans le cadre de son activité libérale.

La fréquence de facturation est adaptée à la durée de la mission :
- **Mission ≤ 7 jours** : une facture finale unique émise à la terminaison de la mission.
- **Mission > 7 jours** : des factures hebdomadaires intermédiaires émises chaque semaine ISO (lundi à dimanche) échue, complétées par une facture finale pour la période restante à la terminaison de la mission.

Cette stratégie de facturation est déterminée automatiquement au moment de l'assignation du Soignant à la mission et ne peut être modifiée ultérieurement.

---

## 3. Portée du mandat

Le Soignant autorise expressément Jolene à :

1. **Émettre** en son nom et pour son compte des factures d'honoraires correspondant aux missions réalisées et validées sur la plateforme, selon la fréquence définie à l'article 2
2. **Mentionner** sur ces factures les informations légalement obligatoires : identité du Soignant (nom, prénom, profession, numéro RPPS/ADELI, SIREN si applicable), identité du débiteur, désignation de la prestation, date d'exécution, montant
3. **Transmettre** électroniquement ces factures aux établissements débiteurs
4. **Encaisser** pour le compte du Soignant le montant des factures via les services de paiement intégrés (notamment Stripe Connect) et **reverser** ces sommes sur le compte bancaire déclaré par le Soignant, déduction faite de la commission Jolene convenue
5. **Conserver** une copie légale des factures émises pour la durée prévue par la loi (10 ans minimum)
6. **Paiement rapide ⚡** — Pour les missions éligibles, le Soignant autorise Jolene à donner instruction au prestataire de services de paiement (Stripe) de conserver les honoraires encaissés sur son compte de paiement jusqu'à la validation des présences par l'Établissement, la libération intervenant au plus tard soixante-douze (72) heures après la fin de la mission ; en cas d'annulation de la mission avant son début, Jolene est autorisée à donner instruction de restitution des sommes à l'Établissement

---

## 4. Obligations du Soignant

Le Soignant s'engage à :

1. **Garder l'entière responsabilité** du contenu des factures émises en son nom. Le Soignant demeure le vendeur légal de la prestation facturée
2. **Maintenir à jour** ses informations professionnelles sur la plateforme (identité, numéro RPPS/ADELI, régime fiscal, coordonnées bancaires, statut de TVA)
3. **Déclarer** les factures émises dans sa propre comptabilité et s'acquitter des obligations fiscales et sociales correspondantes (URSSAF, impôts, etc.)
4. **Informer** Jolene sans délai de tout changement de statut juridique ou fiscal pouvant affecter les modalités de facturation
5. **Ne pas émettre** de facture distincte pour les mêmes prestations auprès de l'établissement

---

## 5. Obligations de Jolene

Jolene s'engage à :

1. **Émettre fidèlement** les factures conformément aux données fournies par le Soignant et validées dans le cadre des missions
2. **Ne mentionner** sur les factures que des informations exactes et vérifiables
3. **Reverser** au Soignant les sommes encaissées, déduction faite de la commission convenue, dans les délais et modalités prévus par les conditions générales
4. **Conserver** un archivage légal des factures émises et le rendre accessible au Soignant sur simple demande
5. **Transmettre** sur demande du Soignant ou de son expert-comptable tout élément justificatif

---

## 6. TVA et régime fiscal

Les prestations de soins à la personne effectuées par les professionnels de santé libéraux sont **exonérées de TVA** en application de l'**article 261-4 du CGI** (actes médicaux et paramédicaux dispensés par les professions réglementées).

Les factures émises mentionneront cette exonération. Toutefois, si le Soignant relève d'un régime fiscal différent ou n'est pas éligible à cette exonération, il en informera Jolene afin que les factures portent la TVA applicable.

Le Soignant reste seul responsable de ses déclarations fiscales et sociales.

---

## 7. Durée et résiliation

Le présent mandat prend effet à la date de son acceptation électronique par le Soignant et est conclu **pour une durée indéterminée**.

Chaque partie peut y mettre fin à tout moment par notification écrite (email), avec un préavis de **30 jours**. Les factures déjà émises et les encaissements en cours demeurent exécutés conformément aux modalités prévues.

La résiliation du compte Jolene par le Soignant emporte automatiquement la résiliation du présent mandat.

---

## 8. Preuve de l'acceptation

L'acceptation du présent mandat s'effectue par **acceptation électronique explicite** (case à cocher + bouton de confirmation) sur la plateforme Jolene. Cette acceptation fait l'objet d'un enregistrement horodaté conservé par Jolene, comprenant la date et l'heure, l'adresse IP, le navigateur utilisé et le numéro de version du document signé.

Cet enregistrement constitue la preuve opposable de l'acceptation, conformément aux articles 1366 et 1367 du Code civil relatifs à la preuve électronique.

---

## 9. Absence de lien de subordination

Il est expressément convenu que le présent mandat **n'emporte aucun lien de subordination** entre Jolene et le Soignant. Le Soignant conserve :

- Son statut de **professionnel libéral indépendant**
- Son **autonomie complète** dans l'exercice de sa profession (choix des missions, organisation, tarifs dans le cadre des missions acceptées)
- Ses propres obligations sociales (URSSAF indépendant) et fiscales
- Sa responsabilité civile professionnelle

Jolene n'est **pas une entreprise de travail temporaire**, **pas une société de portage salarial**, et n'exerce aucune fonction d'employeur vis-à-vis du Soignant.

---

## 10. Droit applicable — Litiges

Le présent mandat est soumis au **droit français**. Tout litige relatif à son interprétation ou son exécution relèvera des tribunaux compétents du ressort du siège social de Jolene, sauf dispositions légales impératives contraires.

---

## 11. Modification

Jolene peut modifier le présent mandat à tout moment. Toute modification substantielle sera notifiée au Soignant par email et requerra une **nouvelle acceptation électronique**. La version en vigueur est identifiée par son numéro et sa date.

---

**Version du mandat** : ${MANDAT_FACTURATION_VERSION}
**Dernière mise à jour** : 29 avril 2026
`.trim();
}

// Version "template vide" conservée pour compat : rendue avec placeholders — ne
// pas utiliser dans le rendu final, utiliser buildMandatFacturationTexte().
export const MANDAT_FACTURATION_TEXTE = buildMandatFacturationTexte({});

// Calcule un hash court du texte pour preuve d'intégrité (non cryptographique fort, indicateur)
export async function hashMandatTexte(texte: string): Promise<string> {
  const encoder = new TextEncoder();
  const data = encoder.encode(texte);
  const hashBuffer = await crypto.subtle.digest('SHA-256', data);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  return hashArray.map(b => b.toString(16).padStart(2, '0')).join('');
}
