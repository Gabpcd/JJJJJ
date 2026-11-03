import XCTest
@testable import JoleneCore

/// Rejoue `Resources/golden/document-upload.json` (port de `src/lib/documentUpload.ts`).
final class RulesClassementDocumentTests: XCTestCase {
    private func golden(_ validation: ValidationFichierDocument) -> JSONValue {
        switch validation {
        case .valide(let mime):
            return .object(["ok": .bool(true), "mime": .string(mime.rawValue), "extension": .string(mime.extensionCanonique)])
        case .refuse(let code, let message):
            return .object(["ok": .bool(false), "code": .string(code.rawValue), "message": .string(message)])
        }
    }

    /// Le web lit `file.slice(0, 12)` d'un fichier dont l'export n'a fixé que les premiers
    /// octets (le reste vaut zéro) : l'app lit, elle, les 12 premiers octets réels du fichier.
    private func premiersOctets(_ entete: JSONValue?, taille: Int) throws -> [UInt8]? {
        guard let valeurs = entete?.array else { return nil }
        var octets = try valeurs.map { UInt8(try XCTUnwrap($0.int)) }
        let lus = min(12, taille)
        if octets.count < lus { octets += [UInt8](repeating: 0, count: lus - octets.count) }
        return octets
    }

    private func verifier(_ entree: JSONValue) throws -> JSONValue {
        let taille = try XCTUnwrap(entree["taille"]?.int)
        let options = entree["options"]
        let mimes = try options?["allowedMimes"]?.array.map { liste in
            try liste.map { try XCTUnwrap(MimeDocument(rawValue: try XCTUnwrap($0.string))) }
        }
        let validation = ClassementDocument.verifierFichier(
            nom: try XCTUnwrap(entree["name"]?.string),
            type: try XCTUnwrap(entree["type"]?.string),
            taille: taille,
            entete: try premiersOctets(entree["entete"], taille: taille),
            tailleMax: options?["maxBytes"]?.int ?? ClassementDocument.tailleMaxParDefaut,
            mimesAutorises: mimes ?? MimeDocument.allCases
        )
        return golden(validation)
    }

    func testVecteursGoldenDocumentUpload() throws {
        let rejoues = try Golden.rejouer("document-upload") { vecteur in
            let entree = vecteur.input
            switch vecteur.fonction {
            case "classerFormatDocument":
                return .string(ClassementDocument.classerFormat(nom: try XCTUnwrap(entree["name"]?.string),
                                                                type: try XCTUnwrap(entree["type"]?.string)).rawValue)
            case "sanitiserNomFichier":
                let mime = try XCTUnwrap(MimeDocument(rawValue: try XCTUnwrap(entree["mime"]?.string)))
                return .string(ClassementDocument.sanitiserNomFichier(try XCTUnwrap(entree["name"]?.string), mime: mime))
            case "verifierFichierDocument":
                return try verifier(entree)
            default:
                return nil
            }
        }
        XCTAssertGreaterThan(rejoues, 0)
    }

    func testHeicEstRefuseAvantToutEnvoi() {
        // Le pipeline natif convertit HEIC/HEIF en JPEG avant ce contrôle (décision Q13) ; la règle
        // elle-même reste celle du web : un HEIC brut n'est jamais téléversé.
        let verdict = ClassementDocument.verifierFichier(nom: "IMG_0001.HEIC", type: "image/heic", taille: 2048,
                                                         entete: [0, 0, 0, 0x18] + Array("ftypheic".utf8))
        guard case .refuse(let code, _) = verdict else { return XCTFail("HEIC accepté : \(verdict)") }
        XCTAssertEqual(code, .heicNonSupporte)
    }

    func testSignatureContraireAuFormatAnnonceEstRefusee() {
        let jpegAnnoncePdf = ClassementDocument.verifierFichier(nom: "piece.pdf", type: "application/pdf", taille: 4,
                                                                entete: [0xff, 0xd8, 0xff, 0x00])
        XCTAssertEqual(jpegAnnoncePdf, .refuse(code: .signatureInvalide,
                                               message: "Le contenu du fichier ne correspond pas au format annoncé. Exportez-le à nouveau en PDF, JPEG, PNG ou WebP."))
        let illisible = ClassementDocument.verifierFichier(nom: "piece.pdf", type: "application/pdf", taille: 4, entete: nil)
        XCTAssertEqual(illisible, .refuse(code: .signatureInvalide, message: "Impossible de lire le fichier sélectionné."))
    }

    func testNomAssainiSansCheminNiAccents() {
        XCTAssertEqual(ClassementDocument.sanitiserNomFichier("../../Pièce.. finale.jpg", mime: .pdf), "Piece-finale.pdf")
        XCTAssertEqual(ClassementDocument.sanitiserNomFichier("dossier/", mime: .jpeg), "document.jpg")
        XCTAssertEqual(ClassementDocument.sanitiserNomFichier(String(repeating: "é", count: 90) + ".png", mime: .png),
                       String(repeating: "e", count: 80) + ".png")
    }
}
