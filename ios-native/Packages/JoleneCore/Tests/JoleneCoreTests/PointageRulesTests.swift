import XCTest
@testable import JoleneCore

/// Règles pures du bloc de pointage et de la page Présences (lot 2, T3), portées de `PointageRotatifSoignant.tsx`
/// (l.94, l.103-112, l.135-136, l.155-160) et `PresencesSoignant.tsx` (l.276-288).
final class PointageRulesTests: XCTestCase {
    private func date(_ iso: String) throws -> Date { try DateHeureParis.instantJolene(iso) }

    private func etat(ouvert: Bool, segments: [SegmentPointage], nbScans: Int = 1) -> EtatPointage {
        EtatPointage(statut: "EN_COURS", prochainTypeScan: ouvert ? .fermeture : .ouverture, nbScans: nbScans,
                     segmentOuvert: ouvert, segments: segments)
    }

    func testStatutsPointables() {
        XCTAssertTrue(PointageRules.pointageDisponible(statut: "ASSIGNEE"))
        XCTAssertTrue(PointageRules.pointageDisponible(statut: "EN_COURS"))
        for statut in ["TERMINEE", "OUVERTE", "assignee", "", nil] as [String?] {
            XCTAssertFalse(PointageRules.pointageDisponible(statut: statut), String(describing: statut))
        }
    }

    func testCodeSaisiSixChiffresApresTrim() {
        XCTAssertEqual(PointageRules.codeSaisi(" 123456\n"), "123456")
        for saisie in ["12345", "1234567", "12345a", "١٢٣٤٥٦", ""] {
            XCTAssertNil(PointageRules.codeSaisi(saisie), saisie)
        }
    }

    func testLibelleDActionSelonLeJourDeParis() throws {
        let maintenant = try date("2026-11-02T09:00:00Z") // 10 h à Paris
        XCTAssertEqual(PointageRules.action(etat(ouvert: true, segments: []), maintenant: maintenant), .departOuPause)
        // 23:30Z le 01/11 = 00:30 le 02/11 à Paris : déjà pointé aujourd'hui.
        let cejour = SegmentPointage(id: "s-1", debut: "2026-11-01T23:30:00Z", fin: "2026-11-02T01:00:00Z")
        XCTAssertEqual(PointageRules.action(etat(ouvert: false, segments: [cejour], nbScans: 2), maintenant: maintenant), .arriveeOuReprise)
        let veille = SegmentPointage(id: "s-0", debut: "2026-11-01T22:30:00Z", fin: "2026-11-01T22:45:00Z")
        XCTAssertEqual(PointageRules.action(etat(ouvert: false, segments: [veille], nbScans: 2), maintenant: maintenant), .arrivee)
        XCTAssertEqual(PointageRules.action(etat(ouvert: false, segments: []), maintenant: maintenant), .arrivee)
    }

    func testSegmentsSurPlusieursJoursEtSegmentEnCours() {
        let a = SegmentPointage(id: "a", debut: "2026-11-01T22:00:00Z", fin: "2026-11-01T22:30:00Z") // 01/11 23 h Paris
        let b = SegmentPointage(id: "b", debut: "2026-11-01T23:30:00Z", fin: nil)                   // 02/11 00 h 30 Paris
        XCTAssertTrue(PointageRules.segmentsSurPlusieursJours([a, b]))
        XCTAssertFalse(PointageRules.segmentsSurPlusieursJours([b]))
        XCTAssertFalse(PointageRules.segmentsSurPlusieursJours([b, SegmentPointage(id: "x", debut: "illisible", fin: nil)]))
        XCTAssertEqual(PointageRules.segmentEnCours(etat(ouvert: true, segments: [a, b]))?.id, "b")
    }

    func testNotationProposeeAuDepartFinal() throws {
        let fin = "2026-11-02T08:05:00Z"
        XCTAssertTrue(PointageRules.notationAProposer(typeScan: .fermeture, finLe: fin, maintenant: try date("2026-11-02T07:35:00Z")),
                      "fin − 30 min atteinte")
        XCTAssertFalse(PointageRules.notationAProposer(typeScan: .fermeture, finLe: fin, maintenant: try date("2026-11-02T07:34:59Z")))
        XCTAssertFalse(PointageRules.notationAProposer(typeScan: .ouverture, finLe: fin, maintenant: try date("2026-11-02T09:00:00Z")))
        XCTAssertFalse(PointageRules.notationAProposer(typeScan: .fermeture, finLe: "illisible", maintenant: try date("2026-11-02T09:00:00Z")))
        XCTAssertFalse(PointageRules.notationAProposer(typeScan: .fermeture, finLe: nil, maintenant: try date("2026-11-02T09:00:00Z")))
    }

    func testSurchargeDuCodeInvalideSeulementPourLeMessageExact() {
        // Décision 6 : seule la ligne l.55649 est surchargée ; l'autre P0002 (l.55775) reste verbatim.
        XCTAssertTrue(PointageRules.estCodeInvalide(sqlstate: "P0002", message: "Code de pointage invalide ou expiré."))
        XCTAssertFalse(PointageRules.estCodeInvalide(sqlstate: "P0002", message: "Aucun créneau effectif ouvert à fermer."))
        XCTAssertFalse(PointageRules.estCodeInvalide(sqlstate: "23514", message: "Code de pointage invalide ou expiré."))
        XCTAssertTrue(PointageRules.estAntiRejeu(sqlstate: "23514", message: "Scan déjà pris en compte. Prochain scan possible dans 87 secondes."))
        XCTAssertFalse(PointageRules.estAntiRejeu(sqlstate: "23514", message: "Le contrat doit être signé avant le pointage."))
    }

    func testEtatConfirmeUnScanAccepte() {
        let ouverture = ScanEnregistre(typeScanEffectue: .ouverture, prochainTypeScan: .fermeture, creneauEffectifId: "c",
                                       horodatageEffectif: nil, horodatageArrondi: nil, numeroScan: 3, validationEtabRequise: false)
        XCTAssertTrue(PointageRules.etatConfirme(EtatPointage(prochainTypeScan: .fermeture, nbScans: 3), scan: ouverture))
        XCTAssertFalse(PointageRules.etatConfirme(EtatPointage(prochainTypeScan: .ouverture, nbScans: 3), scan: ouverture),
                       "prochain type non basculé")
        XCTAssertFalse(PointageRules.etatConfirme(EtatPointage(prochainTypeScan: .fermeture, nbScans: 2), scan: ouverture),
                       "nb_scans en retard")
        XCTAssertFalse(PointageRules.etatConfirme(EtatPointage(prochainTypeScan: .fermeture, nbScans: nil), scan: ouverture))
    }

    func testOngletInitialEtFiltre() {
        XCTAssertEqual(PointageRules.ongletInitial(parametre: "historique", missionsAujourdhui: 2, missionsEnCours: 1), .historique)
        XCTAssertEqual(PointageRules.ongletInitial(parametre: nil, missionsAujourdhui: 1, missionsEnCours: 1), .aujourdhui)
        XCTAssertEqual(PointageRules.ongletInitial(parametre: "", missionsAujourdhui: 0, missionsEnCours: 1), .encours)
        XCTAssertEqual(PointageRules.ongletInitial(parametre: "inconnu", missionsAujourdhui: 0, missionsEnCours: 0), .avenir,
                       "écart assumé : une valeur inconnue retombe sur l'onglet dérivé")
        XCTAssertEqual(PointageRules.OngletPresences.allCases.map(\.rawValue), ["avenir", "encours", "aujourdhui", "historique"])
        XCTAssertTrue(PointageRules.filtreAValider("a_valider"))
        XCTAssertFalse(PointageRules.filtreAValider("A_VALIDER"))
        XCTAssertFalse(PointageRules.filtreAValider(nil))
    }
}
