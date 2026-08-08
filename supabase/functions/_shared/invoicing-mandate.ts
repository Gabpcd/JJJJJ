// Source canonique partagée par le frontend et l'Edge Function de signature.
// Mandat de facturation — article 289 I-2 du CGI jusqu'au 31 août 2026,
// puis article L. 216-43 du CIBS à compter du 1er septembre 2026.
// Document légal permettant à Jolene d'émettre techniquement des factures au nom et pour le compte du soignant libéral.
// Le soignant reste le vendeur légal et juridique de la prestation. Jolene agit uniquement en qualité de mandataire technique.

export const MANDAT_FACTURATION_VERSION = '1.4';

export type StatutTvaHonoraires =
  | 'FRANCHISE_EN_BASE'
  | 'REDEVABLE_TVA';

export const LABELS_PROFESSION_MANDAT: Record<string, string> = {
  IDE: "Infirmier(ère) Diplômé(e) d'État (IDE)",
  AS: 'Aide-Soignant(e) (AS)',
  AES: 'Accompagnant Éducatif et Social (AES)',
  AUXILIAIRE_PUERICULTURE: 'Auxiliaire de puériculture',
  IBODE: "Infirmier(ère) de Bloc Opératoire (IBODE)",
  IADE: 'Infirmier(ère) Anesthésiste (IADE)',
  SAGE_FEMME: 'Sage-Femme',
  KINE: 'Kinésithérapeute',
  MEDECIN: 'Médecin',
  DENTISTE: 'Chirurgien-Dentiste',
  PHARMACIEN: 'Pharmacien(ne)',
  MANIPULATEUR_RADIO: 'Manipulateur Radio',
  PREPARATEUR_PHARMA: 'Préparateur en Pharmacie',
  DIETETICIEN: 'Diététicien(ne)',
  ERGOTHERAPEUTE: 'Ergothérapeute',
  PSYCHOMOTRICIEN: 'Psychomotricien(ne)',
  ORTHOPHONISTE: 'Orthophoniste',
};

export const PROFESSIONS_RPPS_OBLIGATOIRE_MANDAT = new Set([
  'MEDECIN',
  'DENTISTE',
  'SAGE_FEMME',
  'PHARMACIEN',
]);

export const STATUTS_TVA_HONORAIRES: Array<{
  value: StatutTvaHonoraires;
  label: string;
  description: string;
}> = [
  {
    value: 'FRANCHISE_EN_BASE',
    label: 'Franchise en base — article 293 B du CGI',
    description: 'Tu ne factures pas la TVA sur tes prestations taxables tant que les conditions de la franchise sont remplies.',
  },
  {
    value: 'REDEVABLE_TVA',
    label: 'Redevable de la TVA',
    description: 'Tes prestations taxables sont soumises à la TVA ; un numéro de TVA doit être renseigné.',
  },
];

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
  numero_tva?: string | null;
  statut_tva_honoraires?: StatutTvaHonoraires | null;
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
  const profession = (info.profession && LABELS_PROFESSION_MANDAT[info.profession])
    || info.professionLabel
    || info.profession
    || '—';
  const rpps = formatValeur(info.numero_rpps);
  const adeli = formatValeur(info.numero_adeli);
  const siret = formatValeur(info.siret_liberal);
  const email = formatValeur(info.email);
  const adresse = formatAdresse(info);
  const numeroTva = formatValeur(info.numero_tva);
  const statutTva = STATUTS_TVA_HONORAIRES.find(
    (statut) => statut.value === info.statut_tva_honoraires,
  )?.label || 'À sélectionner avant la signature';

  // On ne liste un numéro d'identification que s'il est réellement renseigné,
  // mais on affiche toujours les deux lignes RPPS/ADELI pour cohérence légale.
  const ligneRpps = `Numéro RPPS : ${rpps}`;
  const ligneAdeli = `Numéro ADELI : ${adeli}`;
  const ligneSiret = `SIRET : ${siret}`;
  const ligneAdresse = `Adresse professionnelle : ${adresse}`;
  const ligneEmail = `Email de contact : ${email}`;

  return `
# Mandat de facturation et instructions de paiement

**Article 289 I-2 du Code général des impôts, puis article L. 216-43 du Code des impositions sur les biens et services à compter du 1er septembre 2026**

---

## 1. Parties

**LE MANDANT** — **${nomComplet}**, professionnel de santé libéral utilisateur de la plateforme Jolene (ci-après « le Soignant »).

Profession : **${profession}**

${ligneRpps}

${ligneAdeli}

${ligneSiret}

${ligneAdresse}

${ligneEmail}

Statut TVA déclaré pour l'activité libérale : **${statutTva}**

Numéro de TVA intracommunautaire, si applicable : **${numeroTva}**

**LE MANDATAIRE** : **JOLENE**, société par actions simplifiée unipersonnelle au capital de 1 000 euros, immatriculée au Registre du commerce et des sociétés de Paris sous le numéro 103 305 744, dont le siège social est situé 103 rue de Vaugirard, 75006 Paris, représentée par Madame Gabrielle Nahida Lina PICARD, en sa qualité de Présidente (ci-après « Jolene »).

---

## 2. Objet du mandat

Par le présent mandat, le Soignant donne mandat à Jolene d'émettre des factures **en son nom et pour son compte** à destination des établissements de santé (cliniques, EHPAD, hôpitaux, HAD, centres de santé, pharmacies, etc.) auprès desquels il réalise des missions via la plateforme Jolene.

Ces factures matérialisent la rémunération des prestations professionnelles effectuées par le Soignant dans le cadre de son activité libérale.

La fréquence de facturation est adaptée à la durée de la mission :
- **Mission ≤ 7 jours** : une facture finale unique émise à la terminaison de la mission.
- **Mission > 7 jours** : la prestation est décomptée en portions hebdomadaires closes ; une facture est émise pour chaque portion achevée (semaine ISO du lundi au dimanche), puis une facture finale couvre uniquement la période restante à la terminaison de la mission.

Cette cadence de facturation est déterminée automatiquement au moment de l'assignation du Soignant à la mission. Son verrouillage empêche un changement de cadence incohérent en cours de mission ; il n'empêche jamais la correction des dates, heures, taux, montants ou parties concernées lorsqu'un litige ou une erreur le justifie.

---

## 3. Portée du mandat

Le Soignant autorise expressément Jolene à :

1. **Émettre** en son nom et pour son compte des factures d'honoraires correspondant aux missions réalisées et validées sur la plateforme, selon la fréquence définie à l'article 2
2. **Mentionner** sur ces factures les informations légalement obligatoires : identité du Soignant (nom, prénom, profession, numéro RPPS/ADELI, SIREN si applicable), identité du débiteur, désignation de la prestation, date d'exécution, montant
3. **Transmettre** électroniquement ces factures aux établissements débiteurs et en mettre simultanément une copie à disposition du Soignant dans son espace Jolene
4. **Recueillir l'acceptation de chaque document** : à compter de sa notification et de sa mise à disposition horodatées, le Soignant peut valider expressément le document ou contester l'échéance exacte pendant quarante-huit (48) heures. En l'absence de contestation pendant ce délai, le document est réputé accepté pour l'exécution du présent mandat. Cette acceptation ne prive jamais le Soignant de ses droits en cas de fraude, de non-paiement, d'erreur non décelable dans ce délai ou de disposition légale impérative
5. **Donner au prestataire de services de paiement** les instructions nécessaires à l'encaissement et à la ventilation d'un paiement unique de l'Établissement entre deux créances juridiquement distinctes : (i) l'intégralité des honoraires TTC dus au Soignant et (ii) les frais de service Jolene dus séparément par l'Établissement. Les frais Jolene ne sont pas déduits des honoraires du Soignant
6. **Conserver** chaque version émise des factures, avoirs et factures rectificatives pendant dix (10) ans. Une version émise n'est pas écrasée : toute correction est matérialisée par une pièce liée sans ambiguïté à l'original. Le verrou d'unicité empêche uniquement deux factures principales concurrentes pour une même mission et une même période ; il n'empêche jamais une correction tracée après litige (recalcul avant émission, facture de remplacement, avoir, facture complémentaire ou rectification descriptive sans changement du total selon le statut et le sens de l'écart)
7. **Paiement rapide ⚡** — Pour une mission affichée comme éligible, Jolene donne normalement l'instruction de mise à disposition des honoraires au plus tard dans les soixante-douze (72) heures suivant la fin prévue de la mission et la validation des présences. Ce délai vise l'instruction donnée au prestataire de paiement, non le délai bancaire d'arrivée sur le compte. Il est suspendu en cas de litige, présence non validée, annulation, suspicion de fraude, contrôle réglementaire, échec ou remboursement du paiement de l'Établissement, compte de paiement du Soignant incomplet ou indisponible, ou indisponibilité du prestataire de paiement. Une correction postérieure ne modifie jamais silencieusement un versement déjà exécuté : le delta est traité par un complément, un avoir et, lorsque le remboursement automatique n'est pas sûr, une vérification financière explicite

---

## 4. Obligations du Soignant

Le Soignant s'engage à :

1. **Garder l'entière responsabilité** du contenu des factures émises en son nom. Le Soignant demeure le vendeur légal de la prestation facturée
2. **Maintenir à jour** ses informations professionnelles sur la plateforme (identité, numéro RPPS, SIRET, régime fiscal, coordonnées bancaires et statut TVA)
3. **Déclarer** les factures émises dans sa propre comptabilité et s'acquitter des obligations fiscales et sociales correspondantes (URSSAF, impôts, etc.)
4. **Informer** Jolene sans délai de tout changement de statut juridique ou fiscal pouvant affecter les modalités de facturation
5. **Ne pas émettre** une seconde facture pour la même mission et la même période déjà facturées par Jolene. Cette interdiction ne limite pas le droit de l'Établissement de publier plusieurs missions simultanées ni de recevoir les factures distinctes correspondant à des missions, périodes ou Soignants différents

---

## 5. Obligations de Jolene

Jolene s'engage à :

1. **Émettre fidèlement** les factures conformément aux données fournies par le Soignant et validées dans le cadre des missions
2. **Ne mentionner** sur les factures que des informations exactes et vérifiables
3. **Faire verser** au Soignant l'intégralité des honoraires TTC encaissés pour son compte. La commission Jolene de mise en relation et de services de plateforme est facturée séparément à l'Établissement, au taux contractuel de 15 % HT des honoraires HT validés dans Jolene, augmenté de la TVA applicable aux services Jolene
4. **Conserver** un archivage légal des factures émises et le rendre accessible au Soignant sur simple demande
5. **Transmettre** sur demande du Soignant ou de son expert-comptable tout élément justificatif

---

## 6. TVA et régime fiscal

Le statut TVA déclaré par le Soignant lors de la signature et la nature de chaque prestation sont deux informations distinctes.

Pour chaque mission susceptible d'être exercée en libéral, l'Établissement qualifie la prestation lors de sa publication comme **soin à la personne à finalité thérapeutique** ou **prestation taxable**. Après attribution, le Soignant voit cette qualification et doit la confirmer avant toute émission de facture. En cas de désaccord, la mission reste active mais la facturation est suspendue jusqu'à une revue humaine et une nouvelle confirmation du Soignant.

La facture applique ensuite la règle suivante :

- **Soin à la personne à finalité thérapeutique confirmé** : exonération de l'article 261, 4, 1° du CGI, puis de l'article L. 213-98 du CIBS à compter du 1er septembre 2026, lorsque les conditions attachées à la profession et à l'acte sont remplies
- **Prestation taxable réalisée par un Soignant en franchise en base** : mention « TVA non applicable, art. 293 B du CGI » tant que les conditions de ce régime sont remplies
- **Prestation taxable réalisée par un Soignant redevable de la TVA** : indication du taux, de la base et du montant de TVA applicables aux honoraires

Les services de mise en relation et de plateforme fournis par Jolene à l'Établissement constituent une prestation distincte des soins et sont facturés au taux normal applicable en métropole, actuellement 20 % (article 278 du CGI, puis article L. 213-151 du CIBS à compter du 1er septembre 2026).

Le Soignant reste seul responsable de ses déclarations fiscales et sociales.

---

## 7. Durée et résiliation

Le présent mandat prend effet à la date de son acceptation électronique par le Soignant et est conclu **pour une durée indéterminée**.

Le Soignant peut le révoquer à tout moment depuis son compte, avec effet immédiat pour les nouvelles factures. La révocation n'annule ni les factures déjà émises, ni les avoirs ou factures rectificatives rendus nécessaires par une prestation antérieure, ni les paiements, remboursements ou régularisations déjà engagés.

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
**Dernière mise à jour** : 8 août 2026
`.trim();
}

// Version "template vide" conservée pour compat : rendue avec placeholders — ne
// pas utiliser dans le rendu final, utiliser buildMandatFacturationTexte().
export const MANDAT_FACTURATION_TEXTE = buildMandatFacturationTexte({});

// Calcule l'empreinte SHA-256 du texte canonique pour la preuve d'intégrité.
export async function hashMandatTexte(texte: string): Promise<string> {
  const encoder = new TextEncoder();
  const data = encoder.encode(texte);
  const hashBuffer = await crypto.subtle.digest('SHA-256', data);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  return hashArray.map(b => b.toString(16).padStart(2, '0')).join('');
}
