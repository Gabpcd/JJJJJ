import {
  type BoampRecord,
  estAvisPersonnelSante,
  extraireAcheteur,
  extraireProfessionsExplicites,
  mapperAvisBoamp,
} from "./mapping.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

function assertEquals<T>(actual: T, expected: T, message: string): void {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `${message}\nattendu=${JSON.stringify(expected)}\nobtenu=${
        JSON.stringify(actual)
      }`,
    );
  }
}

function activeRecord(overrides: Partial<BoampRecord> = {}): BoampRecord {
  return {
    idweb: "26-99999",
    objet: "Mise à disposition de médecins et infirmiers intérimaires",
    dateparution: "2026-07-20",
    datelimitereponse: "2026-09-10T16:00:00+00:00",
    nomacheteur: "Centre Hospitalier Exemple",
    code_departement: ["75"],
    nature: "APPEL_OFFRE",
    url_avis: "https://www.boamp.fr/pages/avis/?q=idweb:26-99999",
    donnees: JSON.stringify({
      EFORMS: {
        ContractNotice: {
          "cac:ContractingParty": {
            "cac:Party": {
              "cac:PartyIdentification": { "cbc:ID": "ORG-0001" },
            },
          },
          "efac:Organizations": {
            "efac:Organization": [
              {
                "efac:Company": {
                  "cac:PartyIdentification": { "cbc:ID": "ORG-0001" },
                  "cac:PartyName": {
                    "cbc:Name": { "#text": "Centre Hospitalier Exemple" },
                  },
                  "cac:PartyLegalEntity": { "cbc:CompanyID": "12345678901234" },
                  "cac:PostalAddress": {
                    "cbc:StreetName": "1 rue de la Santé",
                    "cbc:CityName": "Paris",
                    "cbc:PostalZone": "75013",
                  },
                  "cac:Contact": {
                    "cbc:Telephone": "+33 1 23 45 67 89",
                    "cbc:ElectronicMail": "marches@ch-exemple.fr",
                  },
                },
              },
              {
                "efac:Company": {
                  "cac:PartyIdentification": { "cbc:ID": "ORG-0003" },
                  "cac:PartyName": {
                    "cbc:Name": { "#text": "Tribunal administratif" },
                  },
                  "cac:PartyLegalEntity": { "cbc:CompanyID": "98765432109876" },
                  "cac:Contact": { "cbc:ElectronicMail": "greffe@tribunal.fr" },
                },
              },
            ],
          },
          "cac:ProcurementProject": {
            "cbc:Name": {
              "#text":
                "Mise à disposition de médecins et infirmiers intérimaires",
            },
            "cac:MainCommodityClassification": {
              "cbc:ItemClassificationCode": { "#text": "79625000" },
            },
          },
        },
      },
    }),
    ...overrides,
  };
}

Deno.test("BOAMP: retient l'acheteur référencé, pas le tribunal", () => {
  const buyer = extraireAcheteur(activeRecord());
  assertEquals(buyer, {
    nom: "Centre Hospitalier Exemple",
    siret: "12345678901234",
    email: "marches@ch-exemple.fr",
    telephone: "+33 1 23 45 67 89",
    adresse: "1 rue de la Santé",
    code_postal: "75013",
    ville: "Paris",
  }, "mauvais acheteur extrait");
});

Deno.test("BOAMP: crée un signal par profession réellement nommée", () => {
  const record = activeRecord();
  assertEquals(
    extraireProfessionsExplicites(record),
    ["MEDECIN", "IDE"],
    "professions explicites incorrectes",
  );
  const rows = mapperAvisBoamp(record, new Date("2026-07-21T00:00:00Z"));
  assertEquals(
    rows.map((row) => row.profession),
    ["MEDECIN", "IDE"],
    "mauvais signaux par profession",
  );
  assert(
    rows.every((row) => row.siret === "12345678901234"),
    "SIRET acheteur absent",
  );
  assert(
    rows.every((row) => row.details.contact_automatique === false),
    "un contact automatique a été activé",
  );
});

Deno.test("BOAMP: médical au sens adjectif ne devient pas médecin", () => {
  const record = activeRecord({
    objet:
      "Prestation d'intérim et mise en relation de personnel médical et paramédical",
    donnees: JSON.stringify({
      project: {
        description:
          "Prestation d'intérim et mise en relation de personnel médical et paramédical",
        cpv: "79620000",
      },
    }),
  });
  assert(estAvisPersonnelSante(record), "avis médical explicite écarté");
  assertEquals(
    extraireProfessionsExplicites(record),
    [],
    "une profession a été inventée",
  );
  const rows = mapperAvisBoamp(record, new Date("2026-07-21T00:00:00Z"));
  assertEquals(
    rows.map((row) => row.profession),
    [null],
    "le signal générique doit rester sans profession",
  );
});

Deno.test("BOAMP: CPV santé seul ne suffit pas et les faux positifs sont exclus", () => {
  const rejected = [
    "Formation du personnel infirmier aux gestes de premiers secours",
    "Fourniture de matériel médical destiné au personnel infirmier",
    "Campagne publicitaire et diffusion d'annonces de recrutement infirmier",
    "Prestations de radiologie médicale",
    "Mission d'organisation de dispositifs de secours pour les manifestations",
  ];
  for (const objet of rejected) {
    const record = activeRecord({ objet });
    assert(!estAvisPersonnelSante(record), `faux positif accepté: ${objet}`);
  }
});

Deno.test("BOAMP: un avis échu ne produit aucun signal", () => {
  const record = activeRecord({ datelimitereponse: "2026-07-20T12:00:00Z" });
  assertEquals(
    mapperAvisBoamp(record, new Date("2026-07-21T00:00:00Z")),
    [],
    "avis échu importé",
  );
});

Deno.test("BOAMP: une attribution avec titulaire, même sous forme de tableau, est exclue", () => {
  const record = activeRecord({
    nature: "ATTRIBUTION",
    titulaire: [{ nom: "Agence attributaire" }],
  });
  assert(!estAvisPersonnelSante(record), "avis déjà attribué accepté");
  assertEquals(
    mapperAvisBoamp(record, new Date("2026-07-21T00:00:00Z")),
    [],
    "une attribution ne doit produire aucun signal",
  );
});

Deno.test("BOAMP: pharmacien et manipulateur radio restent hors périmètre Jolene", () => {
  for (
    const objet of [
      "Mise à disposition de pharmaciens intérimaires",
      "Mise à disposition de manipulateurs radio intérimaires",
    ]
  ) {
    const record = activeRecord({ objet });
    assertEquals(
      mapperAvisBoamp(record, new Date("2026-07-21T00:00:00Z")),
      [],
      `profession hors périmètre importée : ${objet}`,
    );
  }
});

Deno.test("BOAMP: IADE et IBODE ne sont pas dégradés en IDE", () => {
  const record = activeRecord({
    objet:
      "Mise à disposition d'infirmiers anesthésistes IADE et d'IBODE intérimaires",
    donnees: JSON.stringify({
      project: {
        description:
          "Mise à disposition d'infirmiers anesthésistes IADE et d'IBODE intérimaires",
        cpv: "79624000",
      },
    }),
  });
  assertEquals(
    extraireProfessionsExplicites(record),
    ["IADE", "IBODE"],
    "spécialités infirmières dégradées",
  );
});
