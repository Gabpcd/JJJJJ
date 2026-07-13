export const CONTRAT_SERVICE_VERSION = 'v1.0';

export interface EtablissementContratInfo {
  nom?: string | null;
  siret?: string | null;
  type?: string | null;
  adresse_rue?: string | null;
  adresse_code_postal?: string | null;
  adresse_ville?: string | null;
  email_contact?: string | null;
  representant?: string | null;
}

function formatVal(v?: string | null): string {
  return (v || '').trim() || '—';
}

export function buildContratServiceTexte(info: EtablissementContratInfo): string {
  const nomEtab = formatVal(info.nom);
  const siret = formatVal(info.siret);
  const typeEtab = formatVal(info.type);
  const adresse = [info.adresse_rue, info.adresse_code_postal, info.adresse_ville].filter(Boolean).join(', ') || '—';
  const email = formatVal(info.email_contact);

  return `
# Contrat de service Jolene

---

## Parties

**JOLENE**, société par actions simplifiée unipersonnelle au capital de 1 000 euros, immatriculée au Registre du Commerce et des Sociétés de Paris sous le numéro 103 305 744, dont le siège social est situé 103 rue de Vaugirard, 75006 Paris, représentée par Madame Gabrielle Nahida Lina PICARD, en sa qualité de Présidente,

ci-après dénommée « Jolene »,

**ET :**

**${nomEtab}**, établissement de santé de type ${typeEtab}, SIRET ${siret}, situé ${adresse}, contact ${email},

ci-après dénommé « l'Établissement »,

ci-après désignés ensemble « les Parties ».

---

## Article 1 — Objet

Le présent contrat a pour objet de définir les conditions dans lesquelles Jolene met à disposition de l'Établissement la plateforme numérique jolene.app permettant de :
- publier des missions de remplacement de professionnels de santé,
- recevoir des candidatures de soignants inscrits sur la plateforme,
- assigner les missions et gérer leur exécution,
- gérer la facturation et le paiement des prestations.

---

## Article 2 — Nature de la relation

2.1 Jolene agit en qualité d'intermédiaire technique et de mandataire de facturation au sens de l'article 289 I-2 du Code général des impôts pour les soignants exerçant en libéral.

2.2 Pour les soignants en exercice salarié (CDD notamment), l'Établissement demeure **seul employeur** du soignant. Jolene n'est en aucun cas employeur des soignants. L'Établissement assume l'intégralité des obligations légales afférentes à la qualité d'employeur, notamment le respect du Code du travail, la déclaration aux organismes sociaux, et la responsabilité de la sécurité du soignant pendant la mission.

2.3 Jolene fournit, à titre de service accessoire, l'établissement automatisé des bulletins de paie au nom de l'Établissement employeur, conformément à l'article R3243-1 du Code du travail. La responsabilité finale du contenu du bulletin et du paiement des cotisations incombe à l'Établissement.

---

## Article 3 — Inscription et accès à la plateforme

3.1 L'Établissement déclare exercer une activité d'établissement de santé légalement constituée et autorisée à employer ou faire intervenir des professionnels de santé.

3.2 L'Établissement fournit lors de son inscription :
- un numéro SIRET valide,
- les coordonnées d'un représentant légal habilité à signer le présent contrat,
- un relevé d'identité bancaire (RIB) pour les opérations de paiement,
- toute pièce demandée par Jolene aux fins de vérification d'identité.

3.3 L'Établissement s'engage à maintenir ses informations à jour pendant toute la durée du contrat.

---

## Article 4 — Commission Jolene

4.1 En contrepartie du service rendu, Jolene perçoit une commission sur chaque mission réalisée par l'intermédiaire de la plateforme.

4.2 Le taux de commission applicable est celui défini sur le profil Établissement au moment de l'assignation de la mission. Le taux peut être négocié individuellement ou au niveau du groupe de santé d'appartenance.

4.3 La commission est calculée sur le montant brut total de la mission (heures travaillées multipliées par le taux horaire majorations incluses). Elle est due par l'Établissement à Jolene.

4.4 La commission est figée au moment de l'assignation de la mission et ne peut être modifiée a posteriori sauf renégociation explicite.

4.5 Jolene émet une facture de commission à l'Établissement selon une fréquence mensuelle ou hebdomadaire selon les modalités de la mission. Cette facture est payable à 30 jours date d'émission.

---

## Article 5 — Obligations de l'Établissement

5.1 L'Établissement s'engage à :
- décrire les missions publiées de manière sincère et complète,
- respecter les taux de majoration légaux et conventionnels (nuit, dimanche, fériés),
- déclarer dans les 48 heures les heures réellement travaillées par le soignant via la plateforme,
- payer les sommes dues aux soignants (paie pour les salariés, factures pour les libéraux par l'intermédiaire de Jolene),
- assurer les conditions de sécurité du soignant pendant la mission,
- conclure, le cas échéant, un contrat de travail individuel (CDD notamment) avec le soignant pour les missions salariées, dans les formes et délais prévus par le Code du travail.

5.2 L'Établissement s'engage à uploader sur la plateforme une copie signée du contrat de travail conclu avec le soignant pour chaque mission salariée, au plus tard le premier jour de la mission.

5.3 L'Établissement s'engage à respecter la convention collective applicable à son secteur (FHP, FEHAP, CCU, Croix-Rouge, FPH ou autre).

---

## Article 6 — Obligations de Jolene

6.1 Jolene s'engage à :
- mettre à disposition la plateforme avec une disponibilité raisonnable (objectif 99 % mensuel hors maintenance planifiée),
- assurer le support utilisateur durant les heures ouvrables,
- préserver la confidentialité des données conformément au Règlement Général sur la Protection des Données (RGPD),
- établir les factures d'honoraires libérales et les bulletins de paie salariés conformément aux obligations fiscales et sociales applicables.

6.2 Jolene n'est pas garante du choix du soignant ni de la qualité des prestations fournies par celui-ci. Elle agit comme intermédiaire neutre.

---

## Article 7 — Données personnelles

7.1 Dans le cadre de ce contrat, chaque Partie agit en qualité de responsable de traitement pour les données qu'elle collecte directement.

7.2 Jolene est sous-traitant de l'Établissement pour le traitement des données salariés et libéraux dans le cadre de l'établissement des bulletins de paie et factures, conformément à l'article 28 du RGPD. Un accord de sous-traitance des données (DPA) est annexé au présent contrat.

---

## Article 8 — Durée et résiliation

8.1 Le contrat est conclu pour une durée indéterminée à compter de sa signature électronique sur la plateforme.

8.2 Chaque Partie peut résilier le contrat à tout moment moyennant un préavis de 30 jours notifié par écrit.

8.3 En cas de manquement grave de l'une des Parties à ses obligations, l'autre Partie peut résilier le contrat sans préavis, sous réserve d'une mise en demeure préalable de 8 jours non suivie d'effet.

8.4 La résiliation n'éteint pas les obligations nées avant la résiliation, notamment le paiement des commissions et des sommes dues aux soignants.

---

## Article 9 — Responsabilité

9.1 Chaque Partie est responsable des conséquences de ses propres manquements.

9.2 La responsabilité de Jolene au titre du présent contrat est plafonnée au montant des commissions effectivement perçues par Jolene au titre des 12 mois précédant le fait générateur, sauf cas de faute lourde ou intentionnelle.

---

## Article 10 — Confidentialité

Chaque Partie s'engage à conserver confidentielles toutes informations auxquelles elle pourrait avoir accès dans le cadre du présent contrat, et à ne pas les divulguer à des tiers sans autorisation écrite préalable de l'autre Partie.

---

## Article 11 — Modifications

Toute modification du présent contrat doit faire l'objet d'un avenant écrit, notifié à l'Établissement avec un préavis de 30 jours et accepté par celui-ci.

---

## Article 12 — Droit applicable et juridiction

Le présent contrat est régi par le droit français. Tout litige relatif à son exécution ou son interprétation sera soumis aux tribunaux compétents de Paris.

---

## Article 13 — Signature électronique

Le présent contrat est signé électroniquement par l'Établissement via la plateforme jolene.app. Cette signature électronique vaut accord et engagement ferme et définitif sur l'ensemble des clauses, conformément aux articles 1366 et 1367 du Code civil.

---

**Version du contrat** : ${CONTRAT_SERVICE_VERSION}
**Dernière mise à jour** : 29 avril 2026
`.trim();
}

export const CONTRAT_SERVICE_TEXTE = buildContratServiceTexte({});
// Empreinte du modèle v1.0 avec champs établissement neutres. Le backend la
// combine aux données légales relues en base pour produire l'empreinte signée.
export const CONTRAT_SERVICE_TEMPLATE_FINGERPRINT = '11202a832970b69fcccbcdb95f079cd3d2d4b7bfbf4dc39d64ff961100c547f8';

export async function hashContratTexte(texte: string): Promise<string> {
  const encoder = new TextEncoder();
  const data = encoder.encode(texte);
  const hashBuffer = await crypto.subtle.digest('SHA-256', data);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  return hashArray.map(b => b.toString(16).padStart(2, '0')).join('');
}
