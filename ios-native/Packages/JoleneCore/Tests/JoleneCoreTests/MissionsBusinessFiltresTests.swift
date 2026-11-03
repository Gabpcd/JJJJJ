import XCTest
@testable import JoleneCore

/// Extension de `MissionsBusinessTests` (lot 1, T4a) : chaque critère de la feuille de filtres et
/// chaque chip, passé par `ExplorerFiltres.missionFilters`, produit le filtrage de `MissionBusiness.filter`
/// (port de `filterMissions`). Les comptes du monde démo fondent les attentes de `DemoExplorerTests`.
final class MissionsBusinessFiltresTests: XCTestCase {
    typealias S = MissionsTestSupport

    private var base: ExplorerFiltres { ExplorerFiltres.initiaux(profile: S.context.profile) }

    private func filtrer(_ missions: [Mission], _ change: (inout ExplorerFiltres) -> Void) -> [String] {
        var filtres = base
        change(&filtres)
        return S.ids(MissionBusiness.filter(missions, context: S.context, filters: filtres.missionFilters))
    }

    private func situee(_ id: String, distance: Double?, ville: String = "Paris", cp: String = "75011") -> Mission {
        var mission = S.mission(S.record(id: id))
        mission.distanceKm = distance
        mission.etablissement?.adresseVille = ville
        mission.etablissement?.adresseCodePostal = cp
        return mission
    }

    func testFiltreRayonExcluSeulementLesDistancesConnuesAuDela() {
        let rows = [situee("a", distance: 3), situee("b", distance: 12), situee("c", distance: nil)]
        XCTAssertEqual(filtrer(rows) { $0.rayonKm = 5 }, ["a", "c"], "distance inconnue ≠ hors rayon")
        XCTAssertEqual(filtrer(rows) { $0.rayonKm = 12 }, ["a", "b", "c"], "borne incluse (`distance > rayon` exclut)")
    }

    func testFiltreVilleOuDebutDeCodePostal() {
        let rows = [situee("paris", distance: 1), situee("lilas", distance: 5, ville: "Les Lilas", cp: "93260")]
        XCTAssertEqual(filtrer(rows) { $0.ville = "lilas" }, ["lilas"])
        XCTAssertEqual(filtrer(rows) { $0.ville = "93" }, ["lilas"])
        XCTAssertEqual(filtrer(rows) { $0.ville = "260" }, [], "le code postal se compare par préfixe")
        XCTAssertEqual(filtrer(rows) { $0.ville = "  " }, ["paris", "lilas"])
    }

    func testFiltreTauxMinimumEtUrgentes() {
        let rows = [S.mission(S.record(id: "bas", tauxHoraireBase: 22)),
                    S.mission(S.record(id: "haut", tauxHoraireBase: 31, estUrgente: true))]
        XCTAssertEqual(filtrer(rows) { $0.tauxMin = 30 }, ["haut"])
        XCTAssertEqual(filtrer(rows) { $0.tauxMin = 0 }, ["bas", "haut"])
        XCTAssertEqual(filtrer(rows) { $0 = $0.basculantUrgentes() }, ["haut"])
    }

    func testFiltreContratEtProfessionExplicite() {
        let rows = [S.mission(S.record(id: "salarie")), S.mission(S.record(id: "liberal", typeContratRecherche: "LIBERAL")),
                    S.mission(S.record(id: "iade", professionRequise: "IADE"))]
        XCTAssertEqual(filtrer(rows) { $0.typeContrat = .cdd }, ["salarie"])
        XCTAssertEqual(filtrer(rows) { $0.typeContrat = .liberal }, ["liberal"])
        XCTAssertEqual(filtrer(rows) { $0.profession = "IADE" }, ["iade"], "profession explicite : correspondance exacte")
    }

    func testChipsHorairesSurCreneauxParis() {
        // 21:00 → 05:00 Paris (20:00Z → 04:00Z en novembre) : nuit ; samedi 7 novembre 2026 : week-end.
        let nuit = S.mission(S.record(id: "nuit", finLe: "2026-11-03T04:00:00Z"),
                             slots: [S.slot(id: "n", debut: "2026-11-02T20:00:00Z", fin: "2026-11-03T04:00:00Z", missionId: "nuit")])
        let jour = S.mission(S.record(id: "jour", finLe: "2026-11-04T15:00:00Z"),
                             slots: [S.slot(id: "j", debut: "2026-11-04T07:00:00Z", fin: "2026-11-04T15:00:00Z", missionId: "jour")])
        let samedi = S.mission(S.record(id: "samedi", finLe: "2026-11-07T15:00:00Z"),
                               slots: [S.slot(id: "s", debut: "2026-11-07T07:00:00Z", fin: "2026-11-07T15:00:00Z", missionId: "samedi")])
        let rows = [nuit, jour, samedi]
        XCTAssertEqual(filtrer(rows) { $0 = $0.basculantHoraire(.nuit) }, ["nuit"])
        XCTAssertEqual(filtrer(rows) { $0 = $0.basculantHoraire(.jour) }, ["jour", "samedi"])
        XCTAssertEqual(filtrer(rows) { $0 = $0.basculantHoraire(.weekend) }, ["samedi"])
        XCTAssertEqual(filtrer(rows) { $0 = $0.basculantHoraire(.weekend).basculantHoraire(.weekend) }, ["nuit", "jour", "samedi"])
    }

    func testReinitialiserRetrouveLaListeInitiale() {
        let rows = [situee("pres", distance: 2), situee("loin", distance: 40)]
        var modifies = base; modifies.rayonKm = 5; modifies.typeContrat = .liberal; modifies.ville = "Lyon"
        XCTAssertEqual(S.ids(MissionBusiness.filter(rows, context: S.context, filters: modifies.missionFilters)), [])
        let remis = modifies.reinitialises(profile: S.context.profile)
        XCTAssertEqual(S.ids(MissionBusiness.filter(rows, context: S.context, filters: remis.missionFilters)), ["pres", "loin"])
    }

    // MARK: Monde démo (attentes de DemoExplorerTests)

    private func compteDemo(_ change: (inout ExplorerFiltres) -> Void) async throws -> Int {
        var filtres = ExplorerFiltres.initiaux(profile: DemoWorld.context.profile)
        change(&filtres)
        return try await DemoMissionsGateway().listMissions(context: DemoWorld.context, filters: filtres.missionFilters).count
    }

    func testComptesDuMondeDemoParFiltre() async throws {
        let initial = try await compteDemo { _ in }
        XCTAssertEqual(initial, 30)
        let urgentes = try await compteDemo { $0 = $0.basculantUrgentes() }
        XCTAssertEqual(urgentes, DemoExplorerAttendus.urgentes)
        let weekend = try await compteDemo { $0 = $0.basculantHoraire(.weekend) }
        XCTAssertEqual(weekend, DemoExplorerAttendus.weekend)
        let nuit = try await compteDemo { $0 = $0.basculantHoraire(.nuit) }
        XCTAssertEqual(nuit, DemoExplorerAttendus.nuit)
        let rayonMinimum = try await compteDemo { $0.rayonKm = ExplorerFiltres.rayonMinimumKm }
        XCTAssertEqual(rayonMinimum, DemoExplorerAttendus.rayonMinimum)
        let cdd = try await compteDemo { $0.typeContrat = .cdd }
        XCTAssertEqual(cdd, DemoExplorerAttendus.cdd)
        let remis = try await compteDemo { $0.rayonKm = 5; $0.typeContrat = .liberal; $0 = $0.reinitialises(profile: DemoWorld.context.profile) }
        XCTAssertEqual(remis, 30)
    }

    func testEtatVideDuMondeDemoProposeElargirEtActualiser() async throws {
        // Rayon minimum + Libéral : seul l'établissement à 1,4 km (SALARIE) est dans le rayon → liste
        // vide, aucune chip, rayon < 100 km → « Élargir le rayon » ET « Actualiser » (revue T4a).
        var filtres = ExplorerFiltres.initiaux(profile: DemoWorld.context.profile)
        filtres.rayonKm = ExplorerFiltres.rayonMinimumKm
        filtres.typeContrat = .liberal
        let vide = try await compteDemo { $0 = filtres }
        XCTAssertEqual(vide, 0)
        XCTAssertEqual(filtres.actionEtatVide, .elargirRayon)
        // Élargir (+20 km → 25 km) atteint le cabinet libéral à 6,4 km.
        XCTAssertEqual(filtres.elargissantRayon().rayonKm, DemoExplorerAttendus.rayonApresElargissement)
        let elargi = try await compteDemo { $0 = filtres.elargissantRayon() }
        XCTAssertEqual(elargi, DemoExplorerAttendus.liberalApresElargissement)
    }
}

/// Comptes attendus du monde démo (`demo-missions.json`, 30 missions, 3 établissements à 1,4 / 5,6 / 6,4 km
/// du profil démo). Recopiés dans `JoleneUITests/DemoExplorerTests.swift` : ce test les prouve.
enum DemoExplorerAttendus {
    static let urgentes = 6
    /// Créneaux qui touchent un samedi ou un dimanche civil de Paris.
    static let weekend = 11
    /// Créneaux 20:00Z → 04:00Z (21 h → 5 h à Paris en novembre).
    static let nuit = 7
    /// Rayon minimum (5 km) : seul l'établissement à 1,4 km reste (10 missions). À 10 km, les trois
    /// établissements sont dans le rayon : le compteur ne baisserait pas.
    static let rayonMinimum = 10
    /// Contrat CDD : les 20 missions SALARIE, les 10 LIBERAL sont exclues.
    static let cdd = 20
    /// État vide : rayon minimum (5 km) + Libéral → 0 mission ; « Élargir le rayon (+20 km) » → 25 km,
    /// les 10 missions LIBERAL du cabinet à 6,4 km.
    static let rayonApresElargissement: Double = 25
    static let liberalApresElargissement = 10
}
