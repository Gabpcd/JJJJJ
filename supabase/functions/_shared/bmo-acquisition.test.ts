// deno-lint-ignore-file no-import-prefix
import { zipSync } from "npm:fflate@0.8.2";
import {
  aggregateBmoRecords,
  type BmoRecord,
  mapBmoCode,
  parseBmoNumber,
  parseBmoWorkbook,
} from "./bmo-acquisition.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

function assertEquals<T>(actual: T, expected: T, message: string): void {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `${message}: attendu=${JSON.stringify(expected)} obtenu=${
        JSON.stringify(actual)
      }`,
    );
  }
}

function xmlEscape(value: string): string {
  return value.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(
    />/g,
    "&gt;",
  );
}

function workbookFixture(): Uint8Array {
  const strings = [
    "annee",
    "Code métier BMO",
    "Nom métier BMO",
    "Dept",
    "met",
    "xmet",
    "smet",
    "V0X60",
    "Aides-soignants",
    "75",
    "*",
    "V1X80",
    "Infirmiers et sages-femmes",
    "69",
  ];
  const sharedStrings = `<?xml version="1.0" encoding="UTF-8"?><sst>${
    strings.map((value) => `<si><t>${xmlEscape(value)}</t></si>`).join("")
  }</sst>`;
  const s = (column: string, row: number, index: number) =>
    `<c r="${column}${row}" t="s"><v>${index}</v></c>`;
  const n = (column: string, row: number, value: number) =>
    `<c r="${column}${row}"><v>${value}</v></c>`;
  const sheet = `<?xml version="1.0" encoding="UTF-8"?><worksheet><sheetData>
    <row r="1">${s("A", 1, 0)}${s("B", 1, 1)}${s("C", 1, 2)}${s("H", 1, 3)}${
    s("M", 1, 4)
  }${s("N", 1, 5)}${s("O", 1, 6)}</row>
    <row r="2">${n("A", 2, 2026)}${s("B", 2, 7)}${s("C", 2, 8)}${s("H", 2, 9)}${
    n("M", 2, 10)
  }${n("N", 2, 5)}${n("O", 2, 2)}</row>
    <row r="3">${n("A", 3, 2026)}${s("B", 3, 7)}${s("C", 3, 8)}${s("H", 3, 9)}${
    s("M", 3, 10)
  }${s("N", 3, 10)}${s("O", 3, 10)}</row>
    <row r="4">${n("A", 4, 2026)}${s("B", 4, 11)}${s("C", 4, 12)}${
    s("H", 4, 13)
  }${n("M", 4, 20)}${n("N", 4, 8)}${n("O", 4, 4)}</row>
  </sheetData></worksheet>`;
  return zipSync({
    "xl/sharedStrings.xml": new TextEncoder().encode(sharedStrings),
    "xl/worksheets/sheet2.xml": new TextEncoder().encode(sheet),
  });
}

Deno.test("BMO parse le XLSX et conserve les valeurs confidentielles comme null", () => {
  const records = parseBmoWorkbook(workbookFixture());
  assertEquals(records.length, 3, "nombre de lignes sante");
  assertEquals(records[0], {
    year: 2026,
    code: "V0X60",
    label: "Aides-soignants",
    departement: "75",
    projects: 10,
    difficult: 5,
    seasonal: 2,
  }, "premiere ligne");
  assertEquals(records[1].projects, null, "projets masques");
  assertEquals(records[1].difficult, null, "difficulte masquee");
  assertEquals(records[1].seasonal, null, "saisonnier masque");
  assertEquals(parseBmoNumber("*"), null, "etoile confidentielle");
  assertEquals(parseBmoNumber("1 234,5"), 1234.5, "nombre francais");
});

Deno.test("BMO distingue metiers exacts et categories agregees", () => {
  assertEquals(
    mapBmoCode("V0X60"),
    [{ profession: "AS", precision: "EXACT" }],
    "AS exacte",
  );
  assertEquals(mapBmoCode("V1X80"), [
    { profession: "IDE", precision: "AGREGAT" },
    { profession: "SAGE_FEMME", precision: "AGREGAT" },
  ], "IDE et sage-femme agreges");
  assertEquals(mapBmoCode("V3X90"), [], "pharmacien exclu");
  assertEquals(mapBmoCode("V3Z70"), [], "manipulateur radio exclu");
});

Deno.test("BMO agrege par departement et ne fabrique pas de ratio sur des valeurs masquees", () => {
  const records: BmoRecord[] = [
    {
      year: 2026,
      code: "V0X60",
      label: "Aides-soignants",
      departement: "75",
      projects: 10,
      difficult: 5,
      seasonal: 2,
    },
    {
      year: 2026,
      code: "V0X60",
      label: "Aides-soignants",
      departement: "75",
      projects: null,
      difficult: null,
      seasonal: null,
    },
    {
      year: 2026,
      code: "V1X80",
      label: "Infirmiers et sages-femmes",
      departement: "69",
      projects: 20,
      difficult: 8,
      seasonal: 4,
    },
    {
      year: 2026,
      code: "V2X91",
      label: "Dentistes",
      departement: "13",
      projects: null,
      difficult: null,
      seasonal: null,
    },
  ];
  const rows = aggregateBmoRecords(records, "https://source.test/bmo.xlsx");
  const as = rows.find((row) => row.profession === "AS");
  assert(as, "ligne AS manquante");
  assertEquals(as.bmo_projets_recrutement, 10, "projets AS connus");
  assertEquals(as.bmo_difficulte_pct, 50, "difficulte AS");
  assertEquals(as.bmo_saisonnier_pct, 20, "saisonnier AS");

  const ideSf = rows.filter((row) => row.bmo_code === "V1X80");
  assertEquals(
    ideSf.map((row) => row.profession).sort(),
    ["IDE", "SAGE_FEMME"],
    "ventilation categorie",
  );
  const dentiste = rows.find((row) => row.profession === "DENTISTE");
  assert(dentiste, "ligne dentiste manquante");
  assertEquals(
    dentiste.bmo_projets_recrutement,
    0,
    "confidentiel compte a zero",
  );
  assertEquals(dentiste.bmo_difficulte_pct, null, "ratio confidentiel absent");
  assert(
    !rows.some((row) => row.profession === "PHARMACIEN"),
    "pharmacien ne doit pas etre importe",
  );
  assert(
    !rows.some((row) => row.profession === "MANIPULATEUR_RADIO"),
    "manipulateur radio ne doit pas etre importe",
  );
});
