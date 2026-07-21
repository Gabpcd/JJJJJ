export const BOAMP_SOURCE_CODE = "BOAMP_API";

const CPV_PERSONNEL_SANTE = new Set(["79624000", "79625000"]);
const CPV_PERSONNEL_GENERIQUE = "79620000";

type JsonObject = Record<string, unknown>;

export type BoampRecord = {
  idweb?: unknown;
  objet?: unknown;
  dateparution?: unknown;
  datefindiffusion?: unknown;
  datelimitereponse?: unknown;
  nomacheteur?: unknown;
  titulaire?: unknown;
  code_departement?: unknown;
  code_departement_prestation?: unknown;
  nature?: unknown;
  nature_libelle?: unknown;
  procedure_libelle?: unknown;
  source_schema?: unknown;
  descripteur_libelle?: unknown;
  url_avis?: unknown;
  donnees?: unknown;
};

export type AcheteurBoamp = {
  nom: string | null;
  siret: string | null;
  email: string | null;
  telephone: string | null;
  adresse: string | null;
  code_postal: string | null;
  ville: string | null;
};

export type SignalAcquisitionBoamp = {
  source_code: typeof BOAMP_SOURCE_CODE;
  source_id: string;
  source_url: string;
  finess: null;
  siret: string | null;
  nom_etablissement: string;
  intitule: string;
  profession: string | null;
  departement: string | null;
  ville: string | null;
  type_contrat: "MARCHE_PUBLIC";
  publie_le: string | null;
  expire_le: string;
  volume_estime: 1;
  score_demande: number;
  details: Record<string, unknown>;
};

function texte(value: unknown): string | null {
  if (typeof value === "string") {
    const cleaned = value.trim();
    return cleaned || null;
  }
  if (typeof value === "number" && Number.isFinite(value)) return String(value);
  return null;
}

function aValeur(value: unknown): boolean {
  if (Array.isArray(value)) return value.some(aValeur);
  if (estObjet(value)) return Object.values(value).some(aValeur);
  return texte(value) !== null;
}

export function normaliser(value: unknown): string {
  return (texte(value) || "")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
}

function estObjet(value: unknown): value is JsonObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function cleLocale(key: string): string {
  return normaliser(
    key.includes(":") ? key.slice(key.lastIndexOf(":") + 1) : key,
  )
    .replace(/\s+/g, "");
}

function valeurLocale(object: JsonObject, ...keys: string[]): unknown {
  const wanted = new Set(
    keys.map((key) => normaliser(key).replace(/\s+/g, "")),
  );
  for (const [key, value] of Object.entries(object)) {
    if (wanted.has(cleLocale(key))) return value;
  }
  return undefined;
}

function valeurScalaire(value: unknown): string | null {
  const direct = texte(value);
  if (direct) return direct;
  if (Array.isArray(value)) {
    for (const item of value) {
      const result = valeurScalaire(item);
      if (result) return result;
    }
    return null;
  }
  if (!estObjet(value)) return null;
  for (const key of ["#text", "$t", "_", "value"]) {
    const result = texte(value[key]);
    if (result) return result;
  }
  if (Object.keys(value).length === 1) {
    return valeurScalaire(Object.values(value)[0]);
  }
  return null;
}

function parcourirJson(
  value: unknown,
  visitor: (object: JsonObject, path: string[]) => void,
  path: string[] = [],
  depth = 0,
): void {
  if (depth > 60) return;
  if (Array.isArray(value)) {
    for (const item of value) parcourirJson(item, visitor, path, depth + 1);
    return;
  }
  if (!estObjet(value)) return;
  visitor(value, path);
  for (const [key, child] of Object.entries(value)) {
    parcourirJson(child, visitor, [...path, cleLocale(key)], depth + 1);
  }
}

function analyserDonnees(value: unknown): unknown {
  if (estObjet(value) || Array.isArray(value)) return value;
  const raw = texte(value);
  if (!raw || raw.length > 2_000_000) return null;
  try {
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

function valeurImbriqueeParCle(
  value: unknown,
  wanted: string[],
): string | null {
  const wantedSet = new Set(
    wanted.map((key) => normaliser(key).replace(/\s+/g, "")),
  );
  let found: string | null = null;
  parcourirJson(value, (object) => {
    if (found) return;
    for (const [key, child] of Object.entries(object)) {
      if (!wantedSet.has(cleLocale(key))) continue;
      found = valeurScalaire(child);
      if (found) return;
    }
  });
  return found;
}

function extraireNomPartie(object: JsonObject): string | null {
  const partyName = valeurLocale(object, "PartyName");
  const fromPartyName = valeurImbriqueeParCle(partyName, ["Name"]);
  if (fromPartyName) return fromPartyName;
  return valeurScalaire(valeurLocale(
    object,
    "OfficialName",
    "NomOrganisme",
    "NomAcheteur",
    "Denomination",
    "Nom",
  ));
}

function extraireIdentifiantPartie(object: JsonObject): string | null {
  const identification = valeurLocale(object, "PartyIdentification");
  return valeurImbriqueeParCle(identification, ["ID"]) ||
    valeurScalaire(valeurLocale(object, "OrganizationID", "OrganisationID"));
}

function extraireSiretPartie(object: JsonObject): string | null {
  const legal = valeurLocale(object, "PartyLegalEntity", "LegalEntity");
  const candidates = [
    valeurImbriqueeParCle(legal, ["CompanyID", "Siret", "SIRET"]),
    valeurScalaire(valeurLocale(object, "CompanyID", "Siret", "SIRET")),
  ];
  for (const candidate of candidates) {
    const digits = (candidate || "").replace(/\D/g, "");
    if (/^\d{14}$/.test(digits)) return digits;
  }
  return null;
}

function extraireContactPartie(
  object: JsonObject,
): { email: string | null; telephone: string | null } {
  const contact = valeurLocale(object, "Contact", "ContactInfo", "Coordonnees");
  const email = valeurImbriqueeParCle(contact, [
    "ElectronicMail",
    "Email",
    "Courriel",
  ]);
  const telephone = valeurImbriqueeParCle(contact, [
    "Telephone",
    "Phone",
    "Tel",
  ]);
  return {
    email: email && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) ? email : null,
    telephone: telephone && telephone.replace(/\D/g, "").length >= 9
      ? telephone
      : null,
  };
}

function extraireAdressePartie(
  object: JsonObject,
): Pick<AcheteurBoamp, "adresse" | "code_postal" | "ville"> {
  const postal = valeurLocale(object, "PostalAddress", "Address", "Adresse");
  const street = valeurImbriqueeParCle(postal, [
    "StreetName",
    "AddressLine",
    "Adresse",
  ]);
  const additional = valeurImbriqueeParCle(postal, [
    "AdditionalStreetName",
    "ComplementAdresse",
  ]);
  const codePostal = valeurImbriqueeParCle(postal, [
    "PostalZone",
    "PostCode",
    "CodePostal",
  ]);
  const ville = valeurImbriqueeParCle(postal, ["CityName", "Town", "Ville"]);
  const addressParts = [
    ...new Set(
      [street, additional].filter((part): part is string => Boolean(part)),
    ),
  ];
  return {
    adresse: addressParts.length ? addressParts.join(", ") : null,
    code_postal: codePostal,
    ville,
  };
}

function nomsCorrespondent(left: string | null, right: string | null): boolean {
  const a = normaliser(left).replace(/\b\d{2,3}\b/g, "").trim();
  const b = normaliser(right).replace(/\b\d{2,3}\b/g, "").trim();
  return Boolean(a && b && (a === b || a.includes(b) || b.includes(a)));
}

/**
 * Les avis eForms peuvent contenir l'acheteur, le tribunal et d'autres
 * organismes. On privilégie l'identifiant référencé par ContractingParty,
 * puis la dénomination `nomacheteur`, afin de ne jamais attribuer au prospect
 * les coordonnées d'un tiers présent dans le même avis.
 */
export function extraireAcheteur(record: BoampRecord): AcheteurBoamp {
  const data = analyserDonnees(record.donnees);
  const nomTopLevel = texte(record.nomacheteur);
  const buyerIds = new Set<string>();

  parcourirJson(data, (object, path) => {
    if (!path.includes("contractingparty")) return;
    const id = valeurImbriqueeParCle(object, ["ID"]);
    if (id && /^ORG-[A-Z0-9_-]+$/i.test(id)) buyerIds.add(id);
  });

  const candidates: Array<
    AcheteurBoamp & { id: string | null; score: number }
  > = [];
  parcourirJson(data, (object) => {
    const partyName = valeurLocale(
      object,
      "PartyName",
      "OfficialName",
      "NomOrganisme",
      "NomAcheteur",
    );
    const legal = valeurLocale(
      object,
      "PartyLegalEntity",
      "LegalEntity",
      "CompanyID",
      "Siret",
    );
    const postal = valeurLocale(object, "PostalAddress", "Address", "Adresse");
    const contact = valeurLocale(
      object,
      "Contact",
      "ContactInfo",
      "Coordonnees",
    );
    if (
      partyName === undefined && legal === undefined && postal === undefined &&
      contact === undefined
    ) return;

    const nom = extraireNomPartie(object);
    const id = extraireIdentifiantPartie(object);
    const siret = extraireSiretPartie(object);
    const coordonnees = extraireContactPartie(object);
    const adresse = extraireAdressePartie(object);
    let score = 0;
    if (id && buyerIds.has(id)) score += 300;
    if (nomsCorrespondent(nom, nomTopLevel)) score += 200;
    if (nom) score += 10;
    if (siret) score += 20;
    if (coordonnees.email || coordonnees.telephone) score += 10;
    if (adresse.code_postal || adresse.ville) score += 5;
    candidates.push({ nom, id, siret, ...coordonnees, ...adresse, score });
  });

  candidates.sort((a, b) => b.score - a.score);
  const best = candidates[0];
  if (
    !best || (best.score < 200 && !nomsCorrespondent(best.nom, nomTopLevel))
  ) {
    return {
      nom: nomTopLevel,
      siret: null,
      email: null,
      telephone: null,
      adresse: null,
      code_postal: null,
      ville: null,
    };
  }
  return {
    nom: best.nom || nomTopLevel,
    siret: best.siret,
    email: best.email,
    telephone: best.telephone,
    adresse: best.adresse,
    code_postal: best.code_postal,
    ville: best.ville,
  };
}

function valeursTexte(value: unknown): string[] {
  if (Array.isArray(value)) return value.flatMap(valeursTexte);
  const scalar = texte(value);
  return scalar ? [scalar] : [];
}

function texteAvis(record: BoampRecord): string {
  const parts = [texte(record.objet) || ""];
  const data = analyserDonnees(record.donnees);
  const relevantKeys = new Set([
    "name",
    "description",
    "resumeobjet",
    "objet",
    "title",
    "shortdescription",
  ]);
  parcourirJson(data, (object) => {
    for (const [key, value] of Object.entries(object)) {
      if (!relevantKeys.has(cleLocale(key))) continue;
      const content = valeurScalaire(value);
      if (content) parts.push(content);
    }
  });
  return normaliser(parts.join(" ").slice(0, 300_000));
}

export function extraireCodesCpv(record: BoampRecord): string[] {
  const raw = typeof record.donnees === "string"
    ? record.donnees
    : JSON.stringify(record.donnees || {});
  const codes = raw.match(/\b(?:79620000|79624000|79625000)\b/g) || [];
  return [...new Set(codes)];
}

const EXCLUSIONS = [
  /\bformation\b/,
  /\be learning\b/,
  /\bsensibilisation\b/,
  /\bcoaching\b/,
  /\bfournitures? (?:de |d )?(?:materiel|equipements?|dispositifs?|logiciels?)\b/,
  /\bmaintenance\b.{0,80}\b(?:materiel|equipement|logiciel)\b/,
  /\b(?:achat|campagne) (?:d )?(?:espaces?|publicitaire|communication)\b/,
  /\b(?:diffusion|publication) (?:d )?annonces?\b/,
];

const SANTE =
  "(?:medical|paramedical|medico social|soignant|infirmier|infirmiere|aide soignant|auxiliaire de puericulture|sage femme|medecin|kinesitherapeute|manipulateur radio|ergotherapeute|psychomotricien|orthophoniste|dieteticien)";
const PERSONNEL =
  "(?:personnel|personnels|professionnel|professionnels|agent|agents|medecin|medecins|infirmier|infirmiers|infirmiere|infirmieres|soignant|soignants|soignante|soignantes|aide soignant|aides soignants)";
const STAFFING =
  "(?:mise a disposition|mise en relation|travail temporaire|interim|remplacement|recrutement|fourniture de personnel)";
const WORDING_PERSONNEL_SANTE = [
  new RegExp(`\\b${STAFFING}\\b.{0,140}\\b${SANTE}\\b`),
  new RegExp(`\\b${PERSONNEL}\\b.{0,140}\\b${STAFFING}\\b`),
  /\bpersonnels? (?:interimaires? )?(?:medicaux|paramedicaux|medico sociaux|soignants?)\b/,
];

export function estAvisPersonnelSante(record: BoampRecord): boolean {
  if (
    !texte(record.idweb) || !texte(record.objet) || !texte(record.nomacheteur)
  ) return false;
  if (
    aValeur(record.titulaire) ||
    normaliser(record.nature).includes("attribution")
  ) {
    return false;
  }
  const content = texteAvis(record);
  if (!content || EXCLUSIONS.some((pattern) => pattern.test(content))) {
    return false;
  }
  const wording = WORDING_PERSONNEL_SANTE.some((pattern) =>
    pattern.test(content)
  );
  if (!wording) return false;

  const codes = extraireCodesCpv(record);
  const targetCpv = codes.some((code) => CPV_PERSONNEL_SANTE.has(code));
  const strongExplicitWording =
    /\b(?:interim|travail temporaire|mise a disposition|mise en relation|remplacement)\b/
      .test(content) &&
    new RegExp(`\\b${SANTE}\\b`).test(content);
  return targetCpv || strongExplicitWording;
}

export function extraireProfessionsExplicites(record: BoampRecord): string[] {
  const content = texteAvis(record);
  const professions = new Set<string>();
  const specializedNurse =
    /\b(?:iade|infirmier anesthesiste|infirmiere anesthesiste)\b/.test(
      content,
    ) ||
    /\b(?:ibode|infirmier de bloc operatoire|infirmiere de bloc operatoire)\b/
      .test(content);

  if (
    /\b(?:iade|infirmier anesthesiste|infirmiere anesthesiste)\b/.test(content)
  ) professions.add("IADE");
  if (
    /\b(?:ibode|infirmier de bloc operatoire|infirmiere de bloc operatoire)\b/
      .test(content)
  ) professions.add("IBODE");
  if (/\bauxiliaires? de puericulture\b/.test(content)) {
    professions.add("AUXILIAIRE_PUERICULTURE");
  }
  if (/\baides? soignants?\b|\baides? soignantes?\b/.test(content)) {
    professions.add("AS");
  }
  if (/\baccompagnants? educatifs? (?:et )?sociaux?\b|\baes\b/.test(content)) {
    professions.add("AES");
  }
  if (/\bsages? femmes?\b/.test(content)) professions.add("SAGE_FEMME");
  if (/\b(?:masseurs? )?kinesitherapeutes?\b/.test(content)) {
    professions.add("KINE");
  }
  if (/\bpreparateurs? en pharmacie\b/.test(content)) {
    professions.add("PREPARATEUR_PHARMA");
  }
  if (/\bergotherapeutes?\b/.test(content)) professions.add("ERGOTHERAPEUTE");
  if (/\bpsychomotriciens?\b/.test(content)) professions.add("PSYCHOMOTRICIEN");
  if (/\borthophonistes?\b/.test(content)) professions.add("ORTHOPHONISTE");
  if (/\bdieteticiens?\b|\bdieteticiennes?\b/.test(content)) {
    professions.add("DIETETICIEN");
  }
  if (/\bchirurgiens? dentistes?\b|\bdentistes?\b/.test(content)) {
    professions.add("DENTISTE");
  }
  if (/\bmedecins?\b/.test(content)) professions.add("MEDECIN");
  if (!specializedNurse && /\binfirmi(?:er|ers|ere|eres|er)\b/.test(content)) {
    professions.add("IDE");
  }
  return [...professions];
}

function dateIso(value: unknown, endOfDay = false): string | null {
  const raw = texte(value);
  if (!raw) return null;
  const normalized = /^\d{4}-\d{2}-\d{2}$/.test(raw)
    ? `${raw}T${endOfDay ? "23:59:59" : "00:00:00"}Z`
    : raw;
  const date = new Date(normalized);
  return Number.isFinite(date.getTime()) ? date.toISOString() : null;
}

function urlAvisOfficielle(value: unknown, id: string): string {
  const fallback = `https://www.boamp.fr/pages/avis/?q=idweb:${
    encodeURIComponent(id)
  }`;
  const candidate = texte(value);
  if (!candidate) return fallback;
  try {
    const url = new URL(candidate);
    const hostname = url.hostname.toLowerCase();
    return url.protocol === "https:" &&
        (hostname === "boamp.fr" || hostname.endsWith(".boamp.fr"))
      ? url.toString()
      : fallback;
  } catch {
    return fallback;
  }
}

export function expirationAvis(record: BoampRecord): string | null {
  return dateIso(record.datelimitereponse, true) ||
    dateIso(record.datefindiffusion, true);
}

export function estAvisActif(record: BoampRecord, now = new Date()): boolean {
  const expiration = expirationAvis(record);
  return Boolean(expiration && new Date(expiration).getTime() >= now.getTime());
}

function normaliserDepartement(value: string): string | null {
  const cleaned = value.trim().toUpperCase();
  if (/^\d$/.test(cleaned)) return `0${cleaned}`;
  if (/^(?:\d{2}|\d{3}|2A|2B)$/.test(cleaned)) return cleaned;
  return null;
}

function departementDepuisCodePostal(value: string | null): string | null {
  const digits = (value || "").replace(/\D/g, "");
  if (!/^\d{5}$/.test(digits)) return null;
  return digits.startsWith("97") || digits.startsWith("98")
    ? digits.slice(0, 3)
    : digits.slice(0, 2);
}

export function extraireDepartements(
  record: BoampRecord,
  acheteur?: AcheteurBoamp,
): string[] {
  const values = [
    ...valeursTexte(record.code_departement_prestation),
    ...valeursTexte(record.code_departement),
  ];
  const postal = departementDepuisCodePostal(acheteur?.code_postal || null);
  if (postal) values.push(postal);
  return [
    ...new Set(
      values.map(normaliserDepartement).filter((value): value is string =>
        Boolean(value)
      ),
    ),
  ];
}

function scoreDemande(
  record: BoampRecord,
  acheteur: AcheteurBoamp,
  profession: string | null,
  now: Date,
): number {
  const codes = extraireCodesCpv(record);
  const expiration = expirationAvis(record);
  const daysLeft = expiration
    ? Math.max(0, (new Date(expiration).getTime() - now.getTime()) / 86_400_000)
    : 999;
  return Math.min(
    95,
    65 +
      (codes.some((code) => CPV_PERSONNEL_SANTE.has(code)) ? 10 : 0) +
      (profession ? 10 : 0) +
      (acheteur.email || acheteur.telephone ? 5 : 0) +
      (daysLeft <= 14 ? 5 : 0),
  );
}

/** Transforme un avis pertinent en un signal par profession explicite. */
export function mapperAvisBoamp(
  record: BoampRecord,
  now = new Date(),
): SignalAcquisitionBoamp[] {
  if (!estAvisActif(record, now) || !estAvisPersonnelSante(record)) return [];
  const id = texte(record.idweb);
  const intitule = texte(record.objet);
  if (!id || !intitule) return [];

  const acheteur = extraireAcheteur(record);
  const nom = acheteur.nom || texte(record.nomacheteur);
  const expireLe = expirationAvis(record);
  if (!nom || !expireLe) return [];

  const departements = extraireDepartements(record, acheteur);
  const cpvCodes = extraireCodesCpv(record);
  const professions = extraireProfessionsExplicites(record);
  // Jolene ne propose pas les missions de pharmacien et bloque les missions
  // de manipulateur radio. Un avis qui ne nomme que ces professions ne doit
  // donc pas être recyclé en faux signal générique.
  const professionHorsPerimetreNomme =
    /\bpharmaciens?\b|\bmanipulateurs? (?:radio|en electroradiologie)\b/.test(
      texteAvis(record),
    );
  if (professions.length === 0 && professionHorsPerimetreNomme) return [];
  const professionsOuGenerique: Array<string | null> = professions.length
    ? professions
    : [null];
  const sourceUrl = urlAvisOfficielle(record.url_avis, id);

  return professionsOuGenerique.map((profession) => ({
    source_code: BOAMP_SOURCE_CODE,
    source_id: `${id}:${profession || "GENERAL"}`,
    source_url: sourceUrl,
    finess: null,
    siret: acheteur.siret,
    nom_etablissement: nom,
    intitule,
    profession,
    departement: departements[0] || null,
    ville: acheteur.ville,
    type_contrat: "MARCHE_PUBLIC",
    publie_le: dateIso(record.dateparution),
    expire_le: expireLe,
    volume_estime: 1,
    score_demande: scoreDemande(record, acheteur, profession, now),
    details: {
      avis_boamp_id: id,
      preuve: "AVIS_MARCHE_PUBLIC_NOMME",
      cpv_codes: cpvCodes,
      departements,
      profession_explicite: profession !== null,
      procedure: texte(record.procedure_libelle),
      nature: texte(record.nature_libelle) || texte(record.nature),
      schema_boamp: texte(record.source_schema),
      descripteurs: valeursTexte(record.descripteur_libelle),
      acheteur: {
        nom,
        siret: acheteur.siret,
        email: acheteur.email,
        telephone: acheteur.telephone,
        adresse: acheteur.adresse,
        code_postal: acheteur.code_postal,
        ville: acheteur.ville,
      },
      silencieux: true,
      contact_automatique: false,
    },
  }));
}

export function estCpvPersonnelSante(code: string): boolean {
  return CPV_PERSONNEL_SANTE.has(code);
}

export function estCpvPersonnelGenerique(code: string): boolean {
  return code === CPV_PERSONNEL_GENERIQUE;
}
