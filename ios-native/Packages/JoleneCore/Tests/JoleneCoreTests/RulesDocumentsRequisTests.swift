import XCTest
@testable import JoleneCore

/// Ligne de `documents_requis_par_profession` telle que le vecteur la porte : le port est générique
/// et doit rendre les lignes reçues qu'il retient, dans leur ordre, sans les reconstruire.
private struct RegleGolden: RegleDocumentRequisRepresentable {
    let json: JSONValue
    let profession: String
    let typeDocument: String
    let typeExerciceRequis: String?

    init(_ json: JSONValue) throws {
        self.json = json
        profession = try XCTUnwrap(json["profession"]?.string, "profession NOT NULL")
        typeDocument = try XCTUnwrap(json["type_document"]?.string, "type_document NOT NULL")
        typeExerciceRequis = json["type_exercice_requis"]?.string
    }
}

/// Rejoue `Resources/golden/documents-requis.json` (port de `filtrerDocumentsRequis` et
/// `documentValidePourExigence`, `src/lib/documents-requis.ts`, extraits de `DocumentsSoignant.tsx`
/// par la PR web W1, #1112). Si un vecteur diverge, on corrige le port, jamais le vecteur.
final class RulesDocumentsRequisTests: XCTestCase {
    private func soignant(_ json: JSONValue?) -> SoignantExigencesDocuments {
        SoignantExigencesDocuments(profession: json?["profession"]?.string, typeExercice: json?["type_exercice"]?.string,
                                   rppsVerifie: json?["rpps_verifie"]?.bool, adeliVerifie: json?["adeli_verifie"]?.bool)
    }

    func testVecteursGoldenDocumentsRequis() throws {
        let rejoues = try Golden.rejouer("documents-requis") { vecteur in
            let entree = vecteur.input
            switch vecteur.fonction {
            case "TYPES_DOCUMENTS_EXCLUS_UPLOAD":
                return .array(ExigencesDocuments.typesDocumentsExclusUpload.map(JSONValue.string))
            case "filtrerDocumentsRequis":
                // `regles` nul ou absent : liste absente (`regles || []`).
                let regles = try entree["regles"]?.array.map { try $0.map(RegleGolden.init) }
                let retenues = ExigencesDocuments.filtrerDocumentsRequis(regles, soignant: soignant(entree["soignant"]))
                return .array(retenues.map(\.json))
            case "documentValidePourExigence":
                let document = try XCTUnwrap(entree["document"])
                // `profession_certifiee` est lu par `resultat_ia->>profession_certifiee` (texte ou nul) :
                // toute autre valeur JSON est absente pour le natif, comme `typeof … === 'string'`.
                // `statut_verification` est NULLable (`public.sql` l.408) : nul est rejoué tel quel.
                let piece = DocumentSoignantExigence(typeDocument: try XCTUnwrap(document["type_document"]?.string),
                                                     statutVerification: document["statut_verification"]?.string,
                                                     valideJusqua: document["valide_jusqua"]?.string,
                                                     professionCertifiee: document["profession_certifiee"]?.string)
                return .bool(ExigencesDocuments.documentValidePourExigence(
                    piece, typeDocumentExige: try XCTUnwrap(entree["exigence"]?["type_document"]?.string),
                    profession: entree["profession"]?.string, maintenant: try Golden.instant(entree["maintenant"])))
            default:
                return nil
            }
        }
        XCTAssertGreaterThan(rejoues, 0)
    }

    // MARK: - Garanties hors vecteurs

    private func regle(_ typeDocument: String, _ typeExerciceRequis: String? = "TOUS", profession: String = "IDE") -> RegleDocumentRequis {
        RegleDocumentRequis(profession: profession, typeDocument: typeDocument, typeExerciceRequis: typeExerciceRequis)
    }

    func testAucuneExigenceNEstCodeeEnDur() {
        // Seule la table paramétrée dit quels documents sont requis : sans ligne, rien n'est exigé.
        for typeExercice in ["SALARIE", "LIBERAL", "MIXTE", nil] {
            let profil = SoignantExigencesDocuments(profession: "IDE", typeExercice: typeExercice, rppsVerifie: false, adeliVerifie: false)
            XCTAssertEqual(ExigencesDocuments.filtrerDocumentsRequis([RegleDocumentRequis](), soignant: profil), [])
            XCTAssertEqual(ExigencesDocuments.filtrerDocumentsRequis([RegleDocumentRequis]?.none, soignant: profil), [])
        }
    }

    func testLesTypesRemplacesParLAttestationNeSontJamaisProposesALEnvoi() {
        let regles = ExigencesDocuments.typesDocumentsExclusUpload.flatMap { type in
            ["TOUS", "LIBERAL_ONLY", "SALARIE_ONLY", nil].map { regle(type, $0) }
        }
        for typeExercice in ["SALARIE", "LIBERAL", "MIXTE", nil] {
            let profil = SoignantExigencesDocuments(profession: "IDE", typeExercice: typeExercice, rppsVerifie: true, adeliVerifie: true)
            XCTAssertEqual(ExigencesDocuments.filtrerDocumentsRequis(regles, soignant: profil), [], "régime \(typeExercice ?? "nul")")
        }
        XCTAssertEqual(ExigencesDocuments.typesDocumentsExclusUpload, ["VACCINATIONS", "MEDECINE_TRAVAIL"])
    }

    func testUnMixteCumuleLesObligationsSalarieesEtLiberales() {
        let regles = [regle("CARTE_IDENTITE"), regle("RCP_ASSURANCE", "LIBERAL_ONLY"), regle("CASIER_JUDICIAIRE", "SALARIE_ONLY")]
        let types = { (typeExercice: String?) in
            ExigencesDocuments.filtrerDocumentsRequis(regles, soignant: SoignantExigencesDocuments(
                profession: "IDE", typeExercice: typeExercice, rppsVerifie: nil, adeliVerifie: nil)).map(\.typeDocument)
        }
        XCTAssertEqual(types("MIXTE"), ["CARTE_IDENTITE", "RCP_ASSURANCE", "CASIER_JUDICIAIRE"])
        XCTAssertEqual(types("LIBERAL"), ["CARTE_IDENTITE", "RCP_ASSURANCE"])
        XCTAssertEqual(types("SALARIE"), ["CARTE_IDENTITE", "CASIER_JUDICIAIRE"])
        XCTAssertEqual(types(nil), ["CARTE_IDENTITE"], "sans régime : seules les exigences TOUS")
    }

    func testLeRppsNeDispensePasLesSpecialitesDuDiplome() {
        let regles = { (profession: String) in [self.regle("DIPLOME", profession: profession), self.regle("RPPS_ADELI", profession: profession)] }
        for profession in ["IADE", "IBODE"] {
            let profil = SoignantExigencesDocuments(profession: profession, typeExercice: "SALARIE", rppsVerifie: true, adeliVerifie: false)
            XCTAssertEqual(ExigencesDocuments.filtrerDocumentsRequis(regles(profession), soignant: profil).map(\.typeDocument), ["DIPLOME"])
        }
        let ide = SoignantExigencesDocuments(profession: "IDE", typeExercice: "SALARIE", rppsVerifie: true, adeliVerifie: false)
        XCTAssertEqual(ExigencesDocuments.filtrerDocumentsRequis(regles("IDE"), soignant: ide), [])
        let adeli = SoignantExigencesDocuments(profession: "IDE", typeExercice: "SALARIE", rppsVerifie: false, adeliVerifie: true)
        XCTAssertEqual(ExigencesDocuments.filtrerDocumentsRequis(regles("IDE"), soignant: adeli).map(\.typeDocument), ["DIPLOME"],
                       "un ADELI seul ne dispense pas du diplôme")
    }

    func testUneFinDeValiditeEnDateSeuleVautMinuitUTC() throws {
        // `valide_jusqua` est une colonne `date` : « 2026-11-02 » vaut 2026-11-02T00:00Z, comme `new Date`.
        let piece = DocumentSoignantExigence(typeDocument: "CARTE_IDENTITE", statutVerification: "VERIFIE",
                                             valideJusqua: "2026-11-02", professionCertifiee: nil)
        let valide = { (instant: String) in
            ExigencesDocuments.documentValidePourExigence(piece, typeDocumentExige: "CARTE_IDENTITE", profession: "IDE",
                                                          maintenant: try DateHeureParis.instantJolene(instant))
        }
        XCTAssertTrue(try valide("2026-11-01T23:59:59.999Z"))
        XCTAssertFalse(try valide("2026-11-02T00:00:00Z"), "fin atteinte : pièce non valide")
        let illisible = DocumentSoignantExigence(typeDocument: "CARTE_IDENTITE", statutVerification: "VERIFIE",
                                                 valideJusqua: "bientôt", professionCertifiee: nil)
        XCTAssertFalse(ExigencesDocuments.documentValidePourExigence(illisible, typeDocumentExige: "CARTE_IDENTITE", profession: "IDE",
                                                                     maintenant: try DateHeureParis.instantJolene("2000-01-01T00:00:00Z")),
                       "fin illisible : échec fermé")
    }

    func testLesLignesPostgrestSeDecodentAvecLesClesDeLaPage() throws {
        // Projections de `DocumentsSoignant.tsx` l.199-201.
        let ligne = Data(#"""
        {"id":"r1","profession":"IDE","type_document":"DIPLOME","description":"Diplôme d'État","a_expiration":false,
         "duree_validite_mois":null,"est_critique":true,"type_exercice_requis":"TOUS"}
        """#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(RegleDocumentRequis.self, from: ligne),
                       RegleDocumentRequis(id: "r1", profession: "IDE", typeDocument: "DIPLOME", typeExerciceRequis: "TOUS", estCritique: true))
        let profil = Data(#"{"profession":"IADE","type_exercice":"MIXTE","rpps_verifie":true,"adeli_verifie":null,"prenom":"A"}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(SoignantExigencesDocuments.self, from: profil),
                       SoignantExigencesDocuments(profession: "IADE", typeExercice: "MIXTE", rppsVerifie: true, adeliVerifie: nil))
        let piece = Data(#"""
        {"id":"d1","type_document":"DIPLOME","statut_verification":"VERIFIE","valide_jusqua":"2030-01-31","profession_certifiee":"IADE"}
        """#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(DocumentSoignantExigence.self, from: piece),
                       DocumentSoignantExigence(typeDocument: "DIPLOME", statutVerification: "VERIFIE",
                                                valideJusqua: "2030-01-31", professionCertifiee: "IADE"))
    }

    func testUnStatutDeVerificationNulNeCassePasLaListeEtNEstJamaisValide() throws {
        // `documents_soignants.statut_verification` est NULLable (DEFAULT 'EN_ATTENTE' sans NOT NULL,
        // `public.sql` l.408 ; `| null` dans `types.ts`) : une ligne à NULL ne doit pas faire échouer
        // le décodage de toute la liste. Le web la garde et la juge non valide (`=== 'VERIFIE'`).
        let lignes = Data(#"""
        [{"id":"d1","type_document":"CARTE_IDENTITE","statut_verification":"VERIFIE","valide_jusqua":null,"profession_certifiee":null},
         {"id":"d2","type_document":"CARTE_IDENTITE","statut_verification":null,"valide_jusqua":null,"profession_certifiee":null}]
        """#.utf8)
        let pieces = try JSONDecoder().decode([DocumentSoignantExigence].self, from: lignes)
        XCTAssertEqual(pieces, [
            DocumentSoignantExigence(typeDocument: "CARTE_IDENTITE", statutVerification: "VERIFIE", valideJusqua: nil, professionCertifiee: nil),
            DocumentSoignantExigence(typeDocument: "CARTE_IDENTITE", statutVerification: nil, valideJusqua: nil, professionCertifiee: nil),
        ])
        let maintenant = try DateHeureParis.instantJolene("2026-11-02T10:00:00Z")
        XCTAssertEqual(pieces.map {
            ExigencesDocuments.documentValidePourExigence($0, typeDocumentExige: "CARTE_IDENTITE", profession: "IDE", maintenant: maintenant)
        }, [true, false], "statut nul : pièce gardée, jamais valide")
    }
}
