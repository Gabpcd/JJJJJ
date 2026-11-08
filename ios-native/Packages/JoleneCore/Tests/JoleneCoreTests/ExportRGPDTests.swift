import XCTest
@testable import JoleneCore

/// Fichiers de l'export RGPD (lot 3, T11), port de `SectionConfidentialite.tsx` l.50-71 : JSON
/// `JSON.stringify(data, null, 2)`, CSV aplati par `flatten`, nom `mes-donnees-jolene-AAAA-MM-JJ`. Le contenu
/// n'est jamais recalculé : il est relu dans l'ordre des clés d'un objet JavaScript issu de `JSON.parse`.
///
/// Les attendus ont été produits par le code web lui-même (lignes 54-64 extraites du fichier, transpilées
/// par TypeScript et exécutées sous Node 24, avec `JSON.parse` et `JSON.stringify` du moteur), le 08/11/2026 ;
/// `testAplatissementWebInchange` fait rougir ce test si ces lignes changent.
final class ExportRGPDTests: XCTestCase {
    private func donnees(_ texte: String) -> ExportDonneesRGPD { ExportDonneesRGPD(json: Data(texte.utf8)) }

    private func json(_ entree: String) throws -> String {
        try ExportRGPD.contenuJSON(JSONOrdonne.analyser(Data(entree.utf8)))
    }

    private func csv(_ entree: String) throws -> String {
        try ExportRGPD.contenuCSV(JSONOrdonne.analyser(Data(entree.utf8)))
    }

    // MARK: - Ordre des clés d'un objet JavaScript

    func testOrdreDesClesIndicesDeTableauDAbordPuisOrdreDInsertion() throws {
        let entree = #"{"b":1,"a":2,"10":3,"2":4,"01":5,"-1":6,"4294967295":7,"4294967294":8,"x":{"9":1,"z":2,"1":3}}"#
        XCTAssertEqual(try json(entree), """
        {
          "2": 4,
          "10": 3,
          "4294967294": 8,
          "b": 1,
          "a": 2,
          "01": 5,
          "-1": 6,
          "4294967295": 7,
          "x": {
            "1": 3,
            "9": 1,
            "z": 2
          }
        }
        """)
        XCTAssertEqual(try csv(entree), """
        Champ,Valeur
        "2","4"
        "10","3"
        "4294967294","8"
        "b","1"
        "a","2"
        "01","5"
        "-1","6"
        "4294967295","7"
        "x.1","3"
        "x.9","1"
        "x.z","2"
        """)
    }

    func testCleEnDoubleGardeSaPremierePlaceEtSaDerniereValeur() throws {
        XCTAssertEqual(try json(#"{"a":1,"b":2,"a":3}"#), "{\n  \"a\": 3,\n  \"b\": 2\n}")
        XCTAssertEqual(try csv(#"{"a":1,"b":2,"a":3}"#), "Champ,Valeur\n\"a\",\"3\"\n\"b\",\"2\"")
    }

    // MARK: - Nombres (`Number::toString`)

    func testNombresEcritsCommeJavaScript() throws {
        let entree = #"{"l":[1.0,100,0.1,1e21,1e-7,123456789012345678901,1.5e-5,-0,5e-324,1.7976931348623157e308,0.000001,1e20,2.5e+25,12.50,-3.25e-9,1152921504606846976],"a":1.0,"b":-0,"c":1e-7,"d":1e21,"e":0.5}"#
        XCTAssertEqual(try json(entree), """
        {
          "l": [
            1,
            100,
            0.1,
            1e+21,
            1e-7,
            123456789012345680000,
            0.000015,
            0,
            5e-324,
            1.7976931348623157e+308,
            0.000001,
            100000000000000000000,
            2.5e+25,
            12.5,
            -3.25e-9,
            1152921504606847000
          ],
          "a": 1,
          "b": 0,
          "c": 1e-7,
          "d": 1e+21,
          "e": 0.5
        }
        """)
        XCTAssertEqual(try csv(entree), """
        Champ,Valeur
        "l","[1,100,0.1,1e+21,1e-7,123456789012345680000,0.000015,0,5e-324,1.7976931348623157e+308,0.000001,100000000000000000000,2.5e+25,12.5,-3.25e-9,1152921504606847000]"
        "a","1"
        "b","0"
        "c","1e-7"
        "d","1e+21"
        "e","0.5"
        """)
    }

    func testTexteDUnNombreCommeStringDeJavaScript() {
        let cas: [(Double, String)] = [
            (1, "1"), (100, "100"), (0.1, "0.1"), (1e21, "1e+21"), (1e-7, "1e-7"), (123_456_789_012_345_683_968, "123456789012345680000") /* = Double du littéral 123456789012345678901 */,
            (1.5e-5, "0.000015"), (-0.0, "0"), (Double.leastNonzeroMagnitude, "5e-324") /* 5e-324 */, (1.7976931348623157e308, "1.7976931348623157e+308"),
            (0.000001, "0.000001"), (1e20, "100000000000000000000"), (2.5e25, "2.5e+25"), (12.5, "12.5"),
            (-3.25e-9, "-3.25e-9"), (1_152_921_504_606_846_976, "1152921504606847000"), (0.1 + 0.2, "0.30000000000000004"),
            (1.0 / 3.0, "0.3333333333333333"), (123e-20, "1.23e-18"), (4.35, "4.35"),
            (.infinity, "Infinity"), (-.infinity, "-Infinity"), (.nan, "NaN"),
        ]
        for (valeur, attendu) in cas {
            XCTAssertEqual(ExportRGPD.texteNombre(valeur), attendu, "String(\(valeur))")
        }
        // `JSON.stringify` d'un nombre non fini : `null` (jamais rencontré dans un jsonb, porté pour être complet).
        XCTAssertEqual(JSONOrdonne.tableau([.nombre(.infinity), .nombre(.nan), .nombre(-0.0)]).texteCompact, "[null,null,0]")
    }

    // MARK: - Chaînes

    func testChainesEchappeesCommeJSONStringify() throws {
        let entree = #"{"s":"a\"b\\c\n\t\u0001\u007f/é😀\u2028","q":"x\"y","k\u00e9":"v"}"#
        XCTAssertEqual(try json(entree),
                       "{\n  \"s\": \"a\\\"b\\\\c\\n\\t\\u0001\u{7F}/é😀\u{2028}\",\n  \"q\": \"x\\\"y\",\n  \"ké\": \"v\"\n}")
        XCTAssertEqual(try csv(entree),
                       "Champ,Valeur\n\"s\",\"a\"\"b\\c\n\t\u{01}\u{7F}/é😀\u{2028}\"\n\"q\",\"x\"\"y\"\n\"ké\",\"v\"")
        // Paire de substitution `\ud83d\ude00` = « 😀 » ; une moitié seule est refusée (le jsonb n'en produit pas).
        XCTAssertEqual(try JSONOrdonne.analyser(Data(#""\ud83d\ude00""#.utf8)), .chaine("😀"))
        XCTAssertThrowsError(try JSONOrdonne.analyser(Data(#""\ud83d""#.utf8)))
        XCTAssertEqual(JSONOrdonne.chaine("\u{08}\u{0C}\r\u{1F}").texteCompact, #""\b\f\r\u001f""#)
    }

    // MARK: - Aplatissement CSV

    func testObjetsImbriquesAplatisTableauxEnJSONCompactNullVide() throws {
        let entree = #"{"profil":{"nom":"Démo","adresse":{"ville":"Lyon","cp":null},"vide":{}},"missions":[{"id":"m1","b":true,"o":{"z":1,"a":[]}}],"n":null,"t":true,"f":false,"x":12.5,"s":"a\"b","multi":"l1\nl2"}"#
        XCTAssertEqual(try csv(entree), """
        Champ,Valeur
        "profil.nom","Démo"
        "profil.adresse.ville","Lyon"
        "profil.adresse.cp",""
        "missions","[{""id"":""m1"",""b"":true,""o"":{""z"":1,""a"":[]}}]"
        "n",""
        "t","true"
        "f","false"
        "x","12.5"
        "s","a""b"
        "multi","l1
        l2"
        """)
        XCTAssertEqual(try json(entree), """
        {
          "profil": {
            "nom": "Démo",
            "adresse": {
              "ville": "Lyon",
              "cp": null
            },
            "vide": {}
          },
          "missions": [
            {
              "id": "m1",
              "b": true,
              "o": {
                "z": 1,
                "a": []
              }
            }
          ],
          "n": null,
          "t": true,
          "f": false,
          "x": 12.5,
          "s": "a\\"b",
          "multi": "l1\\nl2"
        }
        """)
    }

    func testTableauxEtObjetsVides() throws {
        let entree = #"{"a":[],"b":{},"c":[[]],"d":[{}],"e":[1,[2,{"f":null}]]}"#
        XCTAssertEqual(try json(entree), """
        {
          "a": [],
          "b": {},
          "c": [
            []
          ],
          "d": [
            {}
          ],
          "e": [
            1,
            [
              2,
              {
                "f": null
              }
            ]
          ]
        }
        """)
        XCTAssertEqual(try csv(entree), "Champ,Valeur\n\"a\",\"[]\"\n\"c\",\"[[]]\"\n\"d\",\"[{}]\"\n\"e\",\"[1,[2,{\"\"f\"\":null}]]\"")
        XCTAssertEqual(try csv("{}"), "Champ,Valeur\n", "`'Champ,Valeur\\n' + [].join('\\n')`")
    }

    func testAnalyseStricteCommeJSONParse() {
        for invalide in ["", "{", "{\"a\":1,}", "[1,]", "{'a':1}", "01", "1.", ".5", "+1", "NaN", "\"\u{01}\"", "{\"a\":1} x", "tru", "\"\\x\""] {
            XCTAssertThrowsError(try JSONOrdonne.analyser(Data(invalide.utf8)), "JSON.parse lève : \(invalide)")
        }
        XCTAssertEqual(try JSONOrdonne.analyser(Data(" \t\r\n{ \"a\" : [ true , false , null ] }\n".utf8)),
                       .objet([MembreJSON(cle: "a", valeur: .tableau([.booleen(true), .booleen(false), .null]))]))
        XCTAssertEqual(try JSONOrdonne.analyser(Data("-0".utf8)), .nombre(-0.0))
        XCTAssertEqual(try JSONOrdonne.analyser(Data(#""\/""#.utf8)), .chaine("/"))
    }

    // MARK: - Réponse du serveur et fichiers

    func testReponseAvecErreurVraieEstUnRefusSansFichier() {
        // `if (data && typeof data === 'object' && (data as any).error)` (l.37) : valeur « vraie » au sens JavaScript.
        XCTAssertEqual(ExportRGPD.analyserReponse(Data(#"{"error":"Trop d'exports en peu de temps. Réessayez dans quelques minutes."}"#.utf8)),
                       .refus(message: "Trop d'exports en peu de temps. Réessayez dans quelques minutes."))
        XCTAssertEqual(ExportRGPD.analyserReponse(Data(#"{"error":"Non authentifié"}"#.utf8)), .refus(message: "Non authentifié"))
        XCTAssertEqual(ExportRGPD.analyserReponse(Data(#"{"error":true}"#.utf8)), .refus(message: nil))
        XCTAssertEqual(ExportRGPD.analyserReponse(Data(#"{"error":{"x":1}}"#.utf8)), .refus(message: nil))
        // Valeurs « fausses » : l'export continue, comme sur le web.
        for faux in [#"{"error":null,"profil":{}}"#, #"{"error":"","profil":{}}"#, #"{"error":false}"#, #"{"error":0}"#] {
            XCTAssertEqual(ExportRGPD.analyserReponse(Data(faux.utf8)), .donnees(donnees(faux)), faux)
        }
        // Corps illisible ou non objet : refus de contrat (le serveur ne renvoie qu'un objet).
        for illisible in ["", "[]", "\"x\"", "null", "42", "{"] {
            XCTAssertEqual(ExportRGPD.analyserReponse(Data(illisible.utf8)), .illisible, illisible)
        }
        // Les octets du serveur sont rendus tels quels (ordre des clés conservé jusqu'au fichier).
        let brut = #"{"z":1,"a":{"y":2,"b":3}}"#
        XCTAssertEqual(ExportRGPD.analyserReponse(Data(brut.utf8)), .donnees(donnees(brut)))
    }

    func testNomTypeEtContenuDesFichiers() throws {
        // `new Date().toISOString().slice(0, 10)` : date UTC, jamais celle du fuseau de l'appareil
        // (2026-11-02T23:59:59Z → 02 ; 2026-11-01T23:59:59Z, déjà le 2 novembre à Paris → 01).
        let instant = Date(timeIntervalSince1970: 1_793_577_600) // 2026-11-02T00:00:00Z
        XCTAssertEqual(ExportRGPD.nomFichier(format: .json, maintenant: instant), "mes-donnees-jolene-2026-11-02.json")
        XCTAssertEqual(ExportRGPD.nomFichier(format: .csv, maintenant: instant.addingTimeInterval(86_399)), "mes-donnees-jolene-2026-11-02.csv")
        XCTAssertEqual(ExportRGPD.nomFichier(format: .csv, maintenant: instant.addingTimeInterval(-1)), "mes-donnees-jolene-2026-11-01.csv")

        let brut = donnees(#"{"b":[1,2],"a":{"c":"é"}}"#)
        let fichierJSON = try ExportRGPD.fichier(brut, format: .json, maintenant: instant)
        XCTAssertEqual(fichierJSON.nom, "mes-donnees-jolene-2026-11-02.json")
        XCTAssertEqual(fichierJSON.mime, "application/json")
        XCTAssertEqual(String(decoding: fichierJSON.contenu, as: UTF8.self),
                       "{\n  \"b\": [\n    1,\n    2\n  ],\n  \"a\": {\n    \"c\": \"é\"\n  }\n}", "UTF-8, sans BOM ni saut final")
        XCTAssertNotEqual(fichierJSON.contenu.first, 0xEF, "aucun BOM")
        let fichierCSV = try ExportRGPD.fichier(brut, format: .csv, maintenant: instant)
        XCTAssertEqual(fichierCSV.nom, "mes-donnees-jolene-2026-11-02.csv")
        XCTAssertEqual(fichierCSV.mime, "text/csv")
        XCTAssertEqual(String(decoding: fichierCSV.contenu, as: UTF8.self), "Champ,Valeur\n\"b\",\"[1,2]\"\n\"a.c\",\"é\"")
        XCTAssertThrowsError(try ExportRGPD.fichier(donnees("[]"), format: .json, maintenant: instant), "jamais un fichier d'un corps non objet")
        XCTAssertEqual(ExportRGPD.auditDetails(.csv), ["format": "csv"])
    }

    func testAplatissementWebInchange() throws {
        // Garde de dérive : les attendus ci-dessus viennent de ces lignes exactes du web.
        let source = try CompteVerbatimTests.lignes("src/components/profil-soignant/SectionConfidentialite.tsx")
        let attendues: [(Int, String)] = [
            (54, "const rows: string[][] = [];"),
            (55, "const flatten = (obj: any, prefix = '') => {"),
            (56, "for (const [k, v] of Object.entries(obj || {})) {"),
            (57, "const key = prefix ? `${prefix}.${k}` : k;"),
            (58, "if (Array.isArray(v)) rows.push([key, JSON.stringify(v)]);"),
            (59, "else if (typeof v === 'object' && v !== null) flatten(v, key);"),
            (60, "else rows.push([key, String(v ?? '')]);"),
            (63, "flatten(data);"),
            (64, "contenu = 'Champ,Valeur\\n' + rows.map((r) => r.map((c) => `\"${String(c).replace(/\"/g, '\"\"')}\"`).join(',')).join('\\n');"),
            (68, "contenu = JSON.stringify(data, null, 2);"),
        ]
        for (ligne, texte) in attendues {
            XCTAssertEqual(source[ligne - 1].trimmingCharacters(in: .whitespaces), texte, "SectionConfidentialite.tsx l.\(ligne)")
        }
    }
}
