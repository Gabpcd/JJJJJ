import XCTest
@testable import JoleneCore

/// Points d'entrée vers les présences (lot 2, T5a, décision 24) : boutons du détail d'une mission
/// (`DetailMissionSoignant.tsx` l.638-645, l.1477-1494) et widget « Aller pointer » de l'Accueil (`DashboardSoignant.tsx`
/// l.282-317, `WidgetAllerPointer.tsx`), rendus comme le web (heure de Paris).
final class PointsEntreePresencesTests: XCTestCase {
    /// 2026-11-02T00:00:00Z = lundi 2 novembre, 01h00 à Paris.
    private let maintenant = DemoWorld.fixedNow

    private func slot(_ debut: String, _ fin: String) -> MissionSlot {
        MissionSlot(id: "s-\(debut)", missionId: "m", debut: debut, fin: fin, estPause: false, typeCreneau: "PREVISIONNEL")
    }

    private func mission(_ id: String, statut: String = "ASSIGNEE", prochain: MissionSlot?, debut: String = "2026-11-02T00:05:00Z",
                         fin: String = "2026-11-02T08:05:00Z", planifiee: Bool = true) -> AccueilMission {
        let ligne = DashboardMissionLigne(id: id, intitule: "Mission \(id)", service: nil, debutLe: debut, finLe: fin, statut: statut,
                                          estUrgente: false, tauxHoraireBase: nil, etablissementId: "e-1", etabNom: nil)
        return AccueilMission(ligne: ligne, etablissementNom: "Établissement fictif République", etablissementVille: "Paris",
                              planning: planifiee ? .planifie(prochain: prochain, rang: prochain == nil ? nil : 1, nombre: 1) : .indisponible,
                              mission: nil)
    }

    // MARK: - Détail d'une mission

    func testEntreesDuDetailDUneMission() {
        let aujourdhui = [slot("2026-11-02T06:00:00Z", "2026-11-02T14:00:00Z")]
        let demain = [slot("2026-11-03T07:00:00Z", "2026-11-03T15:00:00Z")]
        typealias P = PointsEntreePresences
        XCTAssertEqual(P.entreeMission(statut: "ASSIGNEE", creneaux: aujourdhui, maintenant: maintenant), .presences(onglet: .aujourdhui))
        XCTAssertEqual(P.entreeMission(statut: "EN_COURS", creneaux: aujourdhui, maintenant: maintenant), .presences(onglet: .aujourdhui))
        XCTAssertEqual(P.entreeMission(statut: "ASSIGNEE", creneaux: demain, maintenant: maintenant), .presences(onglet: .avenir))
        XCTAssertEqual(P.entreeMission(statut: "EN_COURS", creneaux: demain, maintenant: maintenant), .presences(onglet: .encours))
        XCTAssertEqual(P.entreeMission(statut: "ASSIGNEE", creneaux: [], maintenant: maintenant), .presences(onglet: .avenir))
        XCTAssertEqual(P.entreeMission(statut: "TERMINEE", creneaux: demain, maintenant: maintenant), .heures)
        XCTAssertNil(P.entreeMission(statut: "OUVERTE", creneaux: aujourdhui, maintenant: maintenant))
        XCTAssertNil(P.entreeMission(statut: "ANNULEE", creneaux: aujourdhui, maintenant: maintenant))
        // Un créneau d'hier qui finit après minuit (Paris) chevauche aujourd'hui.
        let nuit = [slot("2026-11-01T21:00:00Z", "2026-11-02T05:00:00Z")]
        XCTAssertEqual(P.entreeMission(statut: "EN_COURS", creneaux: nuit, maintenant: maintenant), .presences(onglet: .aujourdhui))
        XCTAssertEqual(LibellesWeb.DetailMission.presencesEtPointage, "🕐 Présences et pointage")
        XCTAssertEqual(LibellesWeb.DetailMission.heuresPointees, "🕐 Voir mes heures pointées et mes pauses")
    }

    // MARK: - Widget « Aller pointer »

    func testCreneauActuelAllerPointerVersAujourdhui() throws {
        let widget = try XCTUnwrap(PointsEntreePresences.allerPointer(
            [mission("a", prochain: slot("2026-11-02T00:05:00Z", "2026-11-02T08:05:00Z"))], maintenant: maintenant))
        XCTAssertEqual(widget.missionId, "a")
        XCTAssertEqual(widget.titre, "Créneau de travail actuel", "pointable 15 min avant le début")
        XCTAssertEqual(widget.mission, "Mission a — Établissement fictif République")
        XCTAssertEqual(widget.horaire, "lundi 2 novembre · 01:05 → 09:05")
        XCTAssertEqual(widget.bouton, "Aller pointer →")
        XCTAssertEqual(widget.onglet, .aujourdhui)
    }

    func testMissionProcheDansLHeure() throws {
        let widget = try XCTUnwrap(PointsEntreePresences.allerPointer(
            [mission("b", prochain: slot("2026-11-02T00:40:00Z", "2026-11-02T08:40:00Z"))], maintenant: maintenant))
        XCTAssertEqual(widget.titre, "Mission dans 40 min")
        XCTAssertEqual(widget.bouton, "Voir horaires et présences →")
        XCTAssertEqual(widget.onglet, .aujourdhui)
        XCTAssertNil(PointsEntreePresences.allerPointer(
            [mission("c", prochain: slot("2026-11-02T02:00:00Z", "2026-11-02T10:00:00Z"))], maintenant: maintenant),
            "début dans 2 h : aucun widget")
    }

    func testMissionActiveVersActivesEtPriorites() throws {
        let enCours = mission("d", statut: "EN_COURS", prochain: slot("2026-11-03T07:00:00Z", "2026-11-03T15:00:00Z"),
                              debut: "2026-11-01T07:00:00Z", fin: "2026-11-03T15:00:00Z")
        let actif = try XCTUnwrap(PointsEntreePresences.allerPointer([enCours], maintenant: maintenant))
        XCTAssertEqual(actif.titre, "Mission active · prochain créneau")
        XCTAssertEqual(actif.horaire, "mardi 3 novembre · 08:00 → 16:00")
        XCTAssertEqual(actif.bouton, "Voir horaires et présences →")
        XCTAssertEqual(actif.onglet, .encours)

        // Créneau actuel prioritaire sur une mission proche placée avant elle.
        let proche = mission("e", prochain: slot("2026-11-02T00:40:00Z", "2026-11-02T08:40:00Z"))
        let actuel = mission("f", prochain: slot("2026-11-01T23:55:00Z", "2026-11-02T07:00:00Z"))
        XCTAssertEqual(PointsEntreePresences.allerPointer([proche, enCours, actuel], maintenant: maintenant)?.missionId, "f")
        XCTAssertEqual(PointsEntreePresences.allerPointer([enCours, proche], maintenant: maintenant)?.missionId, "e",
                       "mission proche avant une mission active")
        // Planning non vérifié : jamais retenu (`planning_indisponible`).
        XCTAssertNil(PointsEntreePresences.allerPointer(
            [mission("g", prochain: slot("2026-11-02T00:05:00Z", "2026-11-02T08:05:00Z"), planifiee: false)], maintenant: maintenant))
        XCTAssertNil(PointsEntreePresences.allerPointer([], maintenant: maintenant))
    }

    func testHoraireSansProchainCreneau() throws {
        // Mission EN_COURS sans créneau à venir : jamais retenue (le web exige `debut_affiche` pour une mission active).
        let sans = mission("h", statut: "EN_COURS", prochain: nil, debut: "2026-11-01T07:00:00Z", fin: "2026-11-01T15:00:00Z")
        XCTAssertNil(PointsEntreePresences.allerPointer([sans], maintenant: maintenant))
    }
}
