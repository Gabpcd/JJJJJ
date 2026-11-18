import XCTest
@testable import JoleneCore

/// Rejoue `Resources/golden/copie-bulletin-validation.json` (`validerListeCopiesBulletins` et
/// `copieBulletinTelechargeable` de `src/lib/copiesBulletins.ts`, fonction réelle, L4-T2) et fige les écarts plus
/// stricts que le web (échec fermé hors domaine golden).
final class RulesCopieBulletinValidationTests: XCTestCase {
    func testVecteursGoldenCopieBulletinValidation() throws {
        var parFonction: [String: Int] = [:]
        let rejoues = try Golden.rejouer("copie-bulletin-validation") { vecteur in
            parFonction[vecteur.fonction, default: 0] += 1
            switch vecteur.fonction {
            case "validerListeCopiesBulletins":
                let data = try (vecteur.input["data"] ?? .null).decode(ValeurJSON.self)
                do {
                    let copies = try CopieBulletinValidation.valider(data)
                    return .object(["valide": .bool(true), "ids": .array(copies.map { .string($0.id) })])
                } catch let refus as CopieBulletinValidation.ListeNonVerifiable {
                    return .object(["erreur": .string(refus.message)])
                }
            case "copieBulletinTelechargeable":
                return .bool(CopieBulletinValidation.telechargeable(statut: try XCTUnwrap(vecteur.input["statut"]?.string)))
            default:
                return nil
            }
        }
        XCTAssertGreaterThan(rejoues, 150)
        for fonction in ["validerListeCopiesBulletins", "copieBulletinTelechargeable"] {
            XCTAssertGreaterThan(parFonction[fonction] ?? 0, 0, "aucun vecteur golden pour \(fonction)")
        }
    }

    private static let ligne: [String: ValeurJSON] = [
        "id": .chaine("10000000-0000-4000-8000-000000000001"), "etablissement_id": .chaine("10000000-0000-4000-8000-000000000002"),
        "soignant_id": .chaine("10000000-0000-4000-8000-000000000003"), "etablissement_nom": .chaine("Employeur de test"),
        "soignant_nom": .chaine("Test"), "soignant_prenom": .chaine("Salarié"), "periode_debut": .chaine("2026-09-01"),
        "periode_fin": .chaine("2026-09-30"), "statut": .chaine("REMPLACEE"), "publie_le": .chaine("2026-09-29T12:00:00.123456+00:00"),
        "remplace_id": .null, "version": .nombre(2), "motif_remplacement": .chaine("CONTENU"),
        "mission_ids": .tableau([.chaine("10000000-0000-4000-8000-000000000004")]), "taille_octets": .nombre(256),
        "sha256": .chaine(String(repeating: "a", count: 64)), "signalee": .booleen(true),
    ]

    /// La ligne validée devient le modèle `CopieBulletin` (employeur = `etablissement_nom`), champ pour champ.
    func testLigneValideeDevientLeModele() throws {
        let copies = try CopieBulletinValidation.valider(.tableau([.objet(Self.ligne)]))
        XCTAssertEqual(copies, [CopieBulletin(id: "10000000-0000-4000-8000-000000000001", employeurNom: "Employeur de test",
                                              periodeDebut: "2026-09-01", periodeFin: "2026-09-30", statut: .remplacee,
                                              tailleOctets: 256, sha256: String(repeating: "a", count: 64),
                                              missionIds: ["10000000-0000-4000-8000-000000000004"], signalee: true)])
        XCTAssertTrue(CopieBulletinValidation.telechargeable(copies[0].statut))
        XCTAssertFalse(CopieBulletinValidation.telechargeable(.retiree))
    }

    /// Écarts assumés : le repli permissif de `Date.parse` (V8) et un statut tableau, acceptés par le web, sont refusés
    /// (ainsi qu'un décalage après `Z`, que V8 refuse aussi).
    func testEcartsPlusStrictsQueLeWeb() {
        for publieLe in ["2026-09-29 12:00:00+00", "2026-09-29t12:00:00Z", "2026-09-29T12:00:00+0000", "2026-9-29",
                         " 2026-09-29", "2026-09-29\n", "2026-09", "٢٠٢٦-09-29", "2026-09-29T12:00:00Z+01:00"] {
            var ligne = Self.ligne
            ligne["publie_le"] = .chaine(publieLe)
            XCTAssertThrowsError(try CopieBulletinValidation.valider(.tableau([.objet(ligne)])), "publie_le « \(publieLe) »") { erreur in
                XCTAssertEqual(erreur as? CopieBulletinValidation.ListeNonVerifiable, CopieBulletinValidation.ListeNonVerifiable())
            }
        }
        var statutTableau = Self.ligne
        statutTableau["statut"] = .tableau([.chaine("PUBLIEE")])
        XCTAssertThrowsError(try CopieBulletinValidation.valider(.tableau([.objet(statutTableau)])))
        XCTAssertEqual(CopieBulletinValidation.ListeNonVerifiable().errorDescription, "La liste des copies ne peut pas être vérifiée. Réessayez.")
    }
}
