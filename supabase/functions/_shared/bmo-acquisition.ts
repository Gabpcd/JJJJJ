// deno-lint-ignore-file no-import-prefix
// Lecture minimale et deterministe du classeur officiel BMO France Travail.
//
// Le fichier XLSX est un conteneur ZIP. Nous n'extrayons que les chaines
// partagees et la feuille de donnees, puis nous parcourons les lignes sans
// construire un DOM de pres de 54 000 lignes. Les categories BMO agregees ne
// sont jamais presentees comme des professions exactes dans le radar Jolene.

import { unzipSync } from "npm:fflate@0.8.2";

export const BMO_SOURCE_URL =
  "https://www.data.gouv.fr/api/1/datasets/r/228917c7-c22e-4766-835e-fcb923f29b3d";

const MAX_XLSX_BYTES = 25 * 1024 * 1024;
const MAX_SHARED_STRINGS_BYTES = 8 * 1024 * 1024;
const MAX_SHEET_BYTES = 80 * 1024 * 1024;

export type BmoPrecision = "EXACT" | "AGREGAT";

export type BmoRecord = {
  year: number;
  code: string;
  label: string;
  departement: string;
  projects: number | null;
  difficult: number | null;
  seasonal: number | null;
};

export type BmoUpsertRow = {
  departement: string;
  profession: string;
  bmo_annee: number;
  bmo_projets_recrutement: number;
  bmo_difficulte_pct: number | null;
  bmo_saisonnier_pct: number | null;
  bmo_code: string;
  bmo_libelle: string;
  precision: BmoPrecision;
  bmo_source_maj_le: string | null;
  source_url: string;
};

type BmoMapping = {
  profession: string;
  precision: BmoPrecision;
};

// PHARMACIEN est NON PROPOSE et MANIPULATEUR_RADIO est BLOQUE dans Jolene :
// ils sont volontairement absents, meme lorsqu'une categorie BMO les englobe.
const BMO_MAPPINGS: Readonly<Record<string, readonly BmoMapping[]>> = Object
  .freeze({
    V0X60: [{ profession: "AS", precision: "EXACT" }],
    V1X80: [
      { profession: "IDE", precision: "AGREGAT" },
      { profession: "SAGE_FEMME", precision: "AGREGAT" },
    ],
    T2B60: [{ profession: "AUXILIAIRE_PUERICULTURE", precision: "AGREGAT" }],
    V2X90: [{ profession: "MEDECIN", precision: "EXACT" }],
    V2X91: [{ profession: "DENTISTE", precision: "EXACT" }],
    V3X70: [{ profession: "PREPARATEUR_PHARMA", precision: "AGREGAT" }],
    V3X80: [
      { profession: "KINE", precision: "AGREGAT" },
      { profession: "DIETETICIEN", precision: "AGREGAT" },
      { profession: "ERGOTHERAPEUTE", precision: "AGREGAT" },
      { profession: "PSYCHOMOTRICIEN", precision: "AGREGAT" },
      { profession: "ORTHOPHONISTE", precision: "AGREGAT" },
    ],
    V4X84: [{ profession: "AES", precision: "AGREGAT" }],
  });

const REQUIRED_HEADERS = Object.freeze({
  year: "annee",
  code: "code metier bmo",
  label: "nom metier bmo",
  departement: "dept",
  projects: "met",
  difficult: "xmet",
  seasonal: "smet",
});

function decodeXmlEntities(value: string): string {
  return value.replace(
    /&(?:#(\d+)|#x([\da-f]+)|amp|lt|gt|quot|apos);/gi,
    (entity, decimal: string | undefined, hexadecimal: string | undefined) => {
      if (decimal) return String.fromCodePoint(Number(decimal));
      if (hexadecimal) {
        return String.fromCodePoint(Number.parseInt(hexadecimal, 16));
      }
      switch (entity.toLowerCase()) {
        case "&amp;":
          return "&";
        case "&lt;":
          return "<";
        case "&gt;":
          return ">";
        case "&quot;":
          return '"';
        case "&apos;":
          return "'";
        default:
          return entity;
      }
    },
  );
}

function normaliseHeader(value: string): string {
  return value
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .trim()
    .toLowerCase()
    .replace(/\s+/g, " ");
}

function parseSharedStrings(xml: string): string[] {
  const values: string[] = [];
  for (const match of xml.matchAll(/<si\b[^>]*>([\s\S]*?)<\/si>/g)) {
    let value = "";
    for (const textMatch of match[1].matchAll(/<t\b[^>]*>([\s\S]*?)<\/t>/g)) {
      value += decodeXmlEntities(textMatch[1]);
    }
    values.push(value);
  }
  return values;
}

function columnFromReference(reference: string): string {
  return reference.replace(/\d+/g, "").toUpperCase();
}

function parseCells(
  rowXml: string,
  sharedStrings: readonly string[],
): Map<string, string> {
  const cells = new Map<string, string>();
  for (const match of rowXml.matchAll(/<c\b([^>]*)>([\s\S]*?)<\/c>/g)) {
    const attributes = match[1];
    const reference = /\br="([A-Z]+\d+)"/.exec(attributes)?.[1];
    if (!reference) continue;

    const type = /\bt="([^"]+)"/.exec(attributes)?.[1] || "";
    const body = match[2];
    const raw = /<v\b[^>]*>([\s\S]*?)<\/v>/.exec(body)?.[1];
    let value = "";
    if (type === "s" && raw !== undefined) {
      const index = Number.parseInt(raw, 10);
      value = Number.isSafeInteger(index) ? sharedStrings[index] || "" : "";
    } else if (type === "inlineStr") {
      for (const textMatch of body.matchAll(/<t\b[^>]*>([\s\S]*?)<\/t>/g)) {
        value += decodeXmlEntities(textMatch[1]);
      }
    } else if (raw !== undefined) {
      value = decodeXmlEntities(raw);
    }
    cells.set(columnFromReference(reference), value.trim());
  }
  return cells;
}

export function parseBmoNumber(
  value: string | null | undefined,
): number | null {
  const normalised = (value || "").trim().replace(/\s/g, "").replace(",", ".");
  // France Travail masque certaines valeurs confidentielles avec "*".
  if (!normalised || normalised === "*") return null;
  const parsed = Number(normalised);
  return Number.isFinite(parsed) && parsed >= 0 ? parsed : null;
}

export function mapBmoCode(code: string): readonly BmoMapping[] {
  return BMO_MAPPINGS[code.trim().toUpperCase()] || [];
}

function assertArchiveEntry(
  archive: Record<string, Uint8Array>,
  path: string,
  maxBytes: number,
): Uint8Array {
  const entry = archive[path];
  if (!entry) throw new Error(`Classeur BMO invalide : ${path} absent`);
  if (entry.byteLength > maxBytes) {
    throw new Error(
      `Classeur BMO invalide : ${path} depasse la taille autorisee`,
    );
  }
  return entry;
}

export function parseBmoWorkbook(bytes: Uint8Array): BmoRecord[] {
  if (!bytes.byteLength || bytes.byteLength > MAX_XLSX_BYTES) {
    throw new Error("Classeur BMO absent ou trop volumineux");
  }

  const wantedPaths = new Set([
    "xl/sharedStrings.xml",
    "xl/worksheets/sheet2.xml",
  ]);
  const archive = unzipSync(bytes, {
    filter: (file) => {
      if (!wantedPaths.has(file.name)) return false;
      const limit = file.name.endsWith("sharedStrings.xml")
        ? MAX_SHARED_STRINGS_BYTES
        : MAX_SHEET_BYTES;
      if (file.originalSize > limit) {
        throw new Error(`Classeur BMO invalide : ${file.name} trop volumineux`);
      }
      return true;
    },
  });

  const decoder = new TextDecoder("utf-8", { fatal: true });
  const sharedStrings = parseSharedStrings(decoder.decode(assertArchiveEntry(
    archive,
    "xl/sharedStrings.xml",
    MAX_SHARED_STRINGS_BYTES,
  )));
  const sheetXml = decoder.decode(assertArchiveEntry(
    archive,
    "xl/worksheets/sheet2.xml",
    MAX_SHEET_BYTES,
  ));

  const rows = sheetXml.matchAll(/<row\b[^>]*>([\s\S]*?)<\/row>/g);
  const headerRow = rows.next();
  if (headerRow.done) {
    throw new Error("Classeur BMO invalide : en-tetes absents");
  }
  const headerCells = parseCells(headerRow.value[1], sharedStrings);
  const columns = new Map<string, string>();
  for (const [column, value] of headerCells) {
    columns.set(normaliseHeader(value), column);
  }

  const resolved = Object.fromEntries(
    Object.entries(REQUIRED_HEADERS).map(([key, header]) => {
      const column = columns.get(header);
      if (!column) {
        throw new Error(`Classeur BMO invalide : colonne ${header} absente`);
      }
      return [key, column];
    }),
  ) as Record<keyof typeof REQUIRED_HEADERS, string>;

  const records: BmoRecord[] = [];
  for (const rowMatch of rows) {
    const cells = parseCells(rowMatch[1], sharedStrings);
    const code = (cells.get(resolved.code) || "").trim().toUpperCase();
    if (mapBmoCode(code).length === 0) continue;

    const year = Number.parseInt(cells.get(resolved.year) || "", 10);
    const departement = (cells.get(resolved.departement) || "").trim()
      .toUpperCase();
    if (!Number.isInteger(year) || year < 2020 || year > 2100) continue;
    if (!/^(?:0[1-9]|[1-8]\d|9[0-5]|2A|2B|97[1-6])$/.test(departement)) {
      continue;
    }

    records.push({
      year,
      code,
      label: (cells.get(resolved.label) || code).trim(),
      departement,
      projects: parseBmoNumber(cells.get(resolved.projects)),
      difficult: parseBmoNumber(cells.get(resolved.difficult)),
      seasonal: parseBmoNumber(cells.get(resolved.seasonal)),
    });
  }

  if (records.length === 0) {
    throw new Error(
      "Classeur BMO invalide : aucune ligne de sante exploitable",
    );
  }
  return records;
}

function percentage(numerator: number, denominator: number): number | null {
  if (denominator <= 0) return null;
  return Math.min(100, Math.round((numerator / denominator) * 10_000) / 100);
}

export function aggregateBmoRecords(
  records: readonly BmoRecord[],
  sourceUrl = BMO_SOURCE_URL,
  sourceUpdatedAt: string | null = null,
): BmoUpsertRow[] {
  type Aggregate = {
    year: number;
    code: string;
    label: string;
    departement: string;
    projects: number;
    difficult: number;
    difficultBase: number;
    seasonal: number;
    seasonalBase: number;
  };

  const aggregates = new Map<string, Aggregate>();
  for (const record of records) {
    if (mapBmoCode(record.code).length === 0) continue;
    const key = `${record.year}\u0000${record.departement}\u0000${record.code}`;
    const current = aggregates.get(key) || {
      year: record.year,
      code: record.code,
      label: record.label,
      departement: record.departement,
      projects: 0,
      difficult: 0,
      difficultBase: 0,
      seasonal: 0,
      seasonalBase: 0,
    };
    current.projects += record.projects || 0;
    if (record.projects !== null && record.difficult !== null) {
      current.difficultBase += record.projects;
      current.difficult += record.difficult;
    }
    if (record.projects !== null && record.seasonal !== null) {
      current.seasonalBase += record.projects;
      current.seasonal += record.seasonal;
    }
    aggregates.set(key, current);
  }

  const result: BmoUpsertRow[] = [];
  for (const aggregate of aggregates.values()) {
    for (const mapping of mapBmoCode(aggregate.code)) {
      result.push({
        departement: aggregate.departement,
        profession: mapping.profession,
        bmo_annee: aggregate.year,
        bmo_projets_recrutement: Math.round(aggregate.projects),
        bmo_difficulte_pct: percentage(
          aggregate.difficult,
          aggregate.difficultBase,
        ),
        bmo_saisonnier_pct: percentage(
          aggregate.seasonal,
          aggregate.seasonalBase,
        ),
        bmo_code: aggregate.code,
        bmo_libelle: aggregate.label,
        precision: mapping.precision,
        bmo_source_maj_le: sourceUpdatedAt,
        source_url: sourceUrl,
      });
    }
  }
  return result.sort((a, b) =>
    a.departement.localeCompare(b.departement, "fr") ||
    a.profession.localeCompare(b.profession, "fr")
  );
}
