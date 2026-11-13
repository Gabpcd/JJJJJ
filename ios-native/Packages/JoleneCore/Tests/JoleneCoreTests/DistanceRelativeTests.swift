import XCTest
@testable import JoleneCore

/// Date relative des lignes du centre de notifications (lot 3, T5) : port de `formatDistanceToNow(date,
/// { addSuffix: true, locale: fr })` de date-fns 3.6.0 (`src/pages/PageNotifications.tsx` l.161). Les attendus
/// sont ceux de date-fns exécuté sous Node 24 avec `TZ=Europe/Paris` (horloge de référence : l'horloge démo
/// 2026-11-02T00:00:00Z, plus des paires fin de mois et changement d'heure), jamais réécrits à la main ; on
/// corrige le port, jamais l'attendu. Commande : `TZ=Europe/Paris node <script>` avec `formatDistance(date,
/// maintenant, { addSuffix: true, locale: fr })` (équivalent de `formatDistanceToNow` à `maintenant`).
final class DistanceRelativeTests: XCTestCase {
    private static let paris = TimeZone(identifier: "Europe/Paris")!

    /// (date, maintenant, texte date-fns sous `TZ=Europe/Paris`).
    private static let casParis: [(String, String, String)] = [
        ("2026-11-02T00:00:00.000Z", "2026-11-02T00:00:00.000Z", "il y a moins d’une minute"),
        ("2026-11-01T23:59:31.000Z", "2026-11-02T00:00:00.000Z", "il y a moins d’une minute"),
        ("2026-11-02T00:00:29.000Z", "2026-11-02T00:00:00.000Z", "dans moins d’une minute"),
        ("2026-11-01T23:59:30.000Z", "2026-11-02T00:00:00.000Z", "il y a 1 minute"),
        ("2026-11-02T00:00:30.000Z", "2026-11-02T00:00:00.000Z", "dans 1 minute"),
        ("2026-11-01T23:59:01.000Z", "2026-11-02T00:00:00.000Z", "il y a 1 minute"),
        ("2026-11-02T00:00:59.000Z", "2026-11-02T00:00:00.000Z", "dans 1 minute"),
        ("2026-11-01T23:58:31.000Z", "2026-11-02T00:00:00.000Z", "il y a 1 minute"),
        ("2026-11-02T00:01:29.000Z", "2026-11-02T00:00:00.000Z", "dans 1 minute"),
        ("2026-11-01T23:58:30.000Z", "2026-11-02T00:00:00.000Z", "il y a 2 minutes"),
        ("2026-11-02T00:01:30.000Z", "2026-11-02T00:00:00.000Z", "dans 2 minutes"),
        ("2026-11-01T23:58:00.000Z", "2026-11-02T00:00:00.000Z", "il y a 2 minutes"),
        ("2026-11-02T00:02:00.000Z", "2026-11-02T00:00:00.000Z", "dans 2 minutes"),
        ("2026-11-01T23:15:31.000Z", "2026-11-02T00:00:00.000Z", "il y a 44 minutes"),
        ("2026-11-02T00:44:29.000Z", "2026-11-02T00:00:00.000Z", "dans 44 minutes"),
        ("2026-11-01T23:15:30.000Z", "2026-11-02T00:00:00.000Z", "il y a environ 1 heure"),
        ("2026-11-02T00:44:30.000Z", "2026-11-02T00:00:00.000Z", "dans environ 1 heure"),
        ("2026-11-01T23:15:00.000Z", "2026-11-02T00:00:00.000Z", "il y a environ 1 heure"),
        ("2026-11-02T00:45:00.000Z", "2026-11-02T00:00:00.000Z", "dans environ 1 heure"),
        ("2026-11-01T22:31:00.000Z", "2026-11-02T00:00:00.000Z", "il y a environ 1 heure"),
        ("2026-11-02T01:29:00.000Z", "2026-11-02T00:00:00.000Z", "dans environ 1 heure"),
        ("2026-11-01T22:30:00.000Z", "2026-11-02T00:00:00.000Z", "il y a environ 2 heures"),
        ("2026-11-02T01:30:00.000Z", "2026-11-02T00:00:00.000Z", "dans environ 2 heures"),
        ("2026-11-01T22:00:00.000Z", "2026-11-02T00:00:00.000Z", "il y a environ 2 heures"),
        ("2026-11-02T02:00:00.000Z", "2026-11-02T00:00:00.000Z", "dans environ 2 heures"),
        ("2026-11-01T19:00:00.000Z", "2026-11-02T00:00:00.000Z", "il y a environ 5 heures"),
        ("2026-11-02T05:00:00.000Z", "2026-11-02T00:00:00.000Z", "dans environ 5 heures"),
        ("2026-11-01T00:31:00.000Z", "2026-11-02T00:00:00.000Z", "il y a environ 23 heures"),
        ("2026-11-02T23:29:00.000Z", "2026-11-02T00:00:00.000Z", "dans environ 23 heures"),
        ("2026-11-01T00:30:00.000Z", "2026-11-02T00:00:00.000Z", "il y a environ 24 heures"),
        ("2026-11-02T23:30:00.000Z", "2026-11-02T00:00:00.000Z", "dans environ 24 heures"),
        ("2026-11-01T00:00:00.000Z", "2026-11-02T00:00:00.000Z", "il y a 1 jour"),
        ("2026-11-03T00:00:00.000Z", "2026-11-02T00:00:00.000Z", "dans 1 jour"),
        ("2026-10-31T22:00:00.000Z", "2026-11-02T00:00:00.000Z", "il y a 1 jour"),
        ("2026-11-03T02:00:00.000Z", "2026-11-02T00:00:00.000Z", "dans 1 jour"),
        ("2026-10-31T06:01:00.000Z", "2026-11-02T00:00:00.000Z", "il y a 1 jour"),
        ("2026-11-03T17:59:00.000Z", "2026-11-02T00:00:00.000Z", "dans 1 jour"),
        ("2026-10-31T06:00:00.000Z", "2026-11-02T00:00:00.000Z", "il y a 2 jours"),
        ("2026-11-03T18:00:00.000Z", "2026-11-02T00:00:00.000Z", "dans 2 jours"),
        ("2026-10-31T00:00:00.000Z", "2026-11-02T00:00:00.000Z", "il y a 2 jours"),
        ("2026-11-04T00:00:00.000Z", "2026-11-02T00:00:00.000Z", "dans 2 jours"),
        ("2026-10-27T00:00:00.000Z", "2026-11-02T00:00:00.000Z", "il y a 6 jours"),
        ("2026-11-08T00:00:00.000Z", "2026-11-02T00:00:00.000Z", "dans 6 jours"),
        ("2026-10-25T00:00:00.000Z", "2026-11-02T00:00:00.000Z", "il y a 8 jours"),
        ("2026-11-10T00:00:00.000Z", "2026-11-02T00:00:00.000Z", "dans 8 jours"),
        ("2026-10-24T00:00:00.000Z", "2026-11-02T00:00:00.000Z", "il y a 9 jours"),
        ("2026-11-11T00:00:00.000Z", "2026-11-02T00:00:00.000Z", "dans 9 jours"),
        ("2026-10-23T00:00:00.000Z", "2026-11-02T00:00:00.000Z", "il y a 10 jours"),
        ("2026-11-12T00:00:00.000Z", "2026-11-02T00:00:00.000Z", "dans 10 jours"),
        ("2026-10-04T00:00:00.000Z", "2026-11-02T00:00:00.000Z", "il y a 29 jours"),
        ("2026-12-01T00:00:00.000Z", "2026-11-02T00:00:00.000Z", "dans 29 jours"),
        ("2026-10-03T12:00:00.000Z", "2026-11-02T00:00:00.000Z", "il y a 29 jours"),
        ("2026-12-01T12:00:00.000Z", "2026-11-02T00:00:00.000Z", "dans 30 jours"),
        ("2026-10-03T00:00:00.000Z", "2026-11-02T00:00:00.000Z", "il y a 30 jours"),
        ("2026-12-02T00:00:00.000Z", "2026-11-02T00:00:00.000Z", "dans environ 1 mois"),
        ("2026-09-18T00:00:00.000Z", "2026-11-02T00:00:00.000Z", "il y a environ 1 mois"),
        ("2026-12-17T00:00:00.000Z", "2026-11-02T00:00:00.000Z", "dans environ 2 mois"),
        ("2026-09-04T00:00:00.000Z", "2026-11-02T00:00:00.000Z", "il y a environ 2 mois"),
        ("2026-12-31T00:00:00.000Z", "2026-11-02T00:00:00.000Z", "dans environ 2 mois"),
        ("2026-09-03T00:00:00.000Z", "2026-11-02T00:00:00.000Z", "il y a environ 2 mois"),
        ("2027-01-01T00:00:00.000Z", "2026-11-02T00:00:00.000Z", "dans 2 mois"),
        ("2026-08-24T00:00:00.000Z", "2026-11-02T00:00:00.000Z", "il y a 2 mois"),
        ("2027-01-11T00:00:00.000Z", "2026-11-02T00:00:00.000Z", "dans 2 mois"),
        ("2026-04-16T00:00:00.000Z", "2026-11-02T00:00:00.000Z", "il y a 7 mois"),
        ("2027-05-21T00:00:00.000Z", "2026-11-02T00:00:00.000Z", "dans 7 mois"),
        ("2026-01-06T00:00:00.000Z", "2026-11-02T00:00:00.000Z", "il y a 10 mois"),
        ("2027-08-29T00:00:00.000Z", "2026-11-02T00:00:00.000Z", "dans 10 mois"),
        ("2025-11-03T00:00:00.000Z", "2026-11-02T00:00:00.000Z", "il y a 12 mois"),
        ("2027-11-01T00:00:00.000Z", "2026-11-02T00:00:00.000Z", "dans 12 mois"),
        ("2025-11-02T00:00:00.000Z", "2026-11-02T00:00:00.000Z", "il y a environ 1 an"),
        ("2027-11-02T00:00:00.000Z", "2026-11-02T00:00:00.000Z", "dans environ 1 an"),
        ("2025-11-01T00:00:00.000Z", "2026-11-02T00:00:00.000Z", "il y a environ 1 an"),
        ("2027-11-03T00:00:00.000Z", "2026-11-02T00:00:00.000Z", "dans environ 1 an"),
        ("2025-09-28T00:00:00.000Z", "2026-11-02T00:00:00.000Z", "il y a environ 1 an"),
        ("2027-12-07T00:00:00.000Z", "2026-11-02T00:00:00.000Z", "dans environ 1 an"),
        ("2025-06-20T00:00:00.000Z", "2026-11-02T00:00:00.000Z", "il y a plus d’un an"),
        ("2028-03-16T00:00:00.000Z", "2026-11-02T00:00:00.000Z", "dans plus d’un an"),
        ("2024-12-02T00:00:00.000Z", "2026-11-02T00:00:00.000Z", "il y a presque 2 ans"),
        ("2028-10-02T00:00:00.000Z", "2026-11-02T00:00:00.000Z", "dans presque 2 ans"),
        ("2024-11-02T00:00:00.000Z", "2026-11-02T00:00:00.000Z", "il y a environ 2 ans"),
        ("2028-11-01T00:00:00.000Z", "2026-11-02T00:00:00.000Z", "dans presque 2 ans"),
        ("2024-08-24T00:00:00.000Z", "2026-11-02T00:00:00.000Z", "il y a environ 2 ans"),
        ("2029-01-10T00:00:00.000Z", "2026-11-02T00:00:00.000Z", "dans environ 2 ans"),
        ("2024-02-06T00:00:00.000Z", "2026-11-02T00:00:00.000Z", "il y a plus de 2 ans"),
        ("2029-07-29T00:00:00.000Z", "2026-11-02T00:00:00.000Z", "dans plus de 2 ans"),
        ("2023-10-29T00:00:00.000Z", "2026-11-02T00:00:00.000Z", "il y a environ 3 ans"),
        ("2029-11-06T00:00:00.000Z", "2026-11-02T00:00:00.000Z", "dans environ 3 ans"),
        ("2022-09-24T00:00:00.000Z", "2026-11-02T00:00:00.000Z", "il y a environ 4 ans"),
        ("2030-12-11T00:00:00.000Z", "2026-11-02T00:00:00.000Z", "dans environ 4 ans"),
        ("2026-01-31T10:00:00.000Z", "2026-04-01T10:00:00.000Z", "il y a 2 mois"),
        ("2025-12-31T23:30:00.000Z", "2026-02-28T12:00:00.000Z", "il y a environ 2 mois"),
        ("2024-02-29T12:00:00.000Z", "2025-02-28T12:00:00.000Z", "il y a environ 1 an"),
        ("2024-02-29T12:00:00.000Z", "2025-03-01T12:00:00.000Z", "il y a environ 1 an"),
        ("2025-02-28T12:00:00.000Z", "2026-02-28T12:00:00.000Z", "il y a environ 1 an"),
        ("2025-01-31T12:00:00.000Z", "2026-02-28T12:00:00.000Z", "il y a environ 1 an"),
        ("2025-03-31T12:00:00.000Z", "2026-03-30T12:00:00.000Z", "il y a 12 mois"),
        ("2023-11-15T08:00:00.000Z", "2026-11-02T00:00:00.000Z", "il y a presque 3 ans"),
        ("2024-08-15T08:00:00.000Z", "2026-11-02T00:00:00.000Z", "il y a environ 2 ans"),
        ("2026-10-24T12:00:00.000Z", "2026-11-02T00:00:00.000Z", "il y a 8 jours"),
        ("2026-10-25T00:30:00.000Z", "2026-10-25T01:20:00.000Z", "il y a -10 minutes"),
        ("2026-03-29T00:30:00.000Z", "2026-03-29T01:20:00.000Z", "il y a environ 2 heures"),
        ("2026-03-28T12:00:00.000Z", "2026-05-28T12:00:00.000Z", "il y a 2 mois"),
    ]

    private func instant(_ iso: String) throws -> Date {
        try DateHeureParis.instantJolene(iso)
    }

    func testParisCommeDateFns() throws {
        XCTAssertEqual(Self.casParis.count, 102)
        for (date, maintenant, attendu) in Self.casParis {
            let texte = DistanceRelative.depuis(try instant(date), maintenant: try instant(maintenant), fuseau: Self.paris)
            XCTAssertEqual(texte, attendu, "\(date) depuis \(maintenant)")
        }
    }

    /// Le fuseau de l'appareil compte (écart de décalage retranché, mois locaux) : mêmes paires sous `TZ=UTC`.
    func testUTCCommeDateFns() throws {
        let utc = TimeZone(identifier: "UTC")!
        let cas: [(String, String, String)] = [
            ("2026-10-24T12:00:00.000Z", "2026-11-02T00:00:00.000Z", "il y a 9 jours"),
            ("2026-10-25T00:30:00.000Z", "2026-10-25T01:20:00.000Z", "il y a environ 1 heure"),
            ("2023-11-15T08:00:00.000Z", "2026-11-02T00:00:00.000Z", "il y a presque 3 ans"),
            ("2025-03-31T12:00:00.000Z", "2026-03-30T12:00:00.000Z", "il y a 12 mois"),
        ]
        for (date, maintenant, attendu) in cas {
            XCTAssertEqual(DistanceRelative.depuis(try instant(date), maintenant: try instant(maintenant), fuseau: utc), attendu,
                           "\(date) depuis \(maintenant)")
        }
    }

    /// Dates du centre démo (`demo-notifications.json`, horloge démo) : libellés attendus par les XCUITest.
    func testDatesDuCentreDemo() throws {
        let maintenant = DemoWorld.fixedNow
        let attendus = ["il y a environ 2 heures", "il y a environ 5 heures", "il y a 1 jour", "il y a 2 jours",
                        "il y a 3 jours", "il y a 5 jours", "il y a 6 jours"]
        let lignes = try DemoFixtures.loadNotifications().notifications
        XCTAssertEqual(lignes.count, attendus.count)
        for (ligne, attendu) in zip(lignes, attendus) {
            let date = try instant(try XCTUnwrap(ligne.creeLe))
            XCTAssertEqual(DistanceRelative.depuis(date, maintenant: maintenant, fuseau: Self.paris), attendu, ligne.id)
        }
    }
}
