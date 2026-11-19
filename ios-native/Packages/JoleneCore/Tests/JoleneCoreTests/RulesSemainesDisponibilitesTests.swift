import XCTest
@testable import JoleneCore

/// Rejoue `Resources/golden/semaines-disponibilites.json` (grille de `src/pages/MesDisponibilites.tsx`, date-fns réel,
/// L4-T2) : quatre semaines depuis le lundi Europe/Paris, changements d'heure compris.
final class RulesSemainesDisponibilitesTests: XCTestCase {
    static func golden(_ grille: GrilleDisponibilites) -> JSONValue {
        .object([
            "aujourdHui": .string(grille.aujourdhui.iso),
            "semaines": .array(grille.semaines.map { semaine in
                .object([
                    "entete": .string(semaine.entete),
                    "jours": .array(semaine.jours.map { jour in
                        .object(["jour": .string(jour.jour.iso), "passe": .bool(jour.passe),
                                 "estAujourdhui": .bool(jour.estAujourdhui), "libelle": .string(jour.libelle)])
                    }),
                ])
            }),
        ])
    }

    func testVecteursGoldenSemainesDisponibilites() throws {
        let rejoues = try Golden.rejouer("semaines-disponibilites") { vecteur in
            guard vecteur.fonction == "semainesDisponibilites" else { return nil }
            return Self.golden(SemainesDisponibilites.grille(maintenant: try Golden.instant(vecteur.input["maintenant"])))
        }
        XCTAssertGreaterThan(rejoues, 40)
    }

    /// Horloge de la démo (`2026-11-02T00:00:00Z`, un lundi) : grille du 2 au 29 novembre, aucun jour passé.
    func testGrilleDeLHorlogeDemo() throws {
        let grille = SemainesDisponibilites.grille(maintenant: try DateHeureParis.instantJolene("2026-11-02T00:00:00Z"))
        XCTAssertEqual(grille.semaines.count, 4)
        XCTAssertTrue(grille.semaines.allSatisfy { $0.jours.count == 7 })
        XCTAssertEqual(grille.semaines.first?.entete, "Semaine du 2 novembre")
        XCTAssertEqual(grille.semaines.first?.jours.first?.libelle, "lundi 2 nov.")
        XCTAssertEqual(grille.semaines.last?.jours.last?.jour.iso, "2026-11-29")
        XCTAssertFalse(grille.semaines.flatMap(\.jours).contains(where: \.passe))
        XCTAssertEqual(grille.semaines.flatMap(\.jours).filter(\.estAujourdhui).map(\.jour.iso), ["2026-11-02"])
    }
}
