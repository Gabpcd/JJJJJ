import XCTest
@testable import JoleneCore

final class MissionsPresentationTests: XCTestCase {
    typealias S = MissionsTestSupport

    func testRemunerationUtiliseValeurServeurEtDistingueRetrocession() {
        XCTAssertEqual(MissionPresentation.remuneration(S.mission()), "26,75\u{00A0}€/h")
        XCTAssertEqual(MissionPresentation.remuneration(S.mission(S.record(modeRemuneration: "RETROCESSION", retrocessionPct: 70))),
                       "Rétrocession 70 % des honoraires")
        XCTAssertEqual(MissionPresentation.remuneration(S.mission(S.record(modeRemuneration: "RETROCESSION", retrocessionPct: 72.5))),
                       "Rétrocession 72.5 % des honoraires")
        XCTAssertEqual(MissionPresentation.remuneration(S.mission(S.record(modeRemuneration: "RETROCESSION", retrocessionPct: nil))),
                       "Rétrocession — % des honoraires")
        XCTAssertEqual(MissionPresentation.remuneration(S.mission(S.record(tauxHoraireBase: nil))), "Taux non renseigné")
        XCTAssertEqual(MissionPresentation.remuneration(S.mission(S.record(tauxHoraireBase: 23))), "23,00\u{00A0}€/h")
    }

    func testEurosReproduitIntlFrFR() {
        XCTAssertEqual(MissionPresentation.euros(1234.5), "1\u{202F}234,50\u{00A0}€")
        XCTAssertEqual(MissionPresentation.euros(23), "23,00\u{00A0}€")
        XCTAssertEqual(MissionPresentation.euros(0), "0,00\u{00A0}€")
        XCTAssertEqual(MissionPresentation.euros(26.755), "26,76\u{00A0}€")
    }

    func testPeriodeCreneauUniqueEtMultiCreneaux() {
        XCTAssertEqual(MissionPresentation.periode(S.mission()), "27/10/2026 · 09:00–17:00")
        let later = S.slot(id: "slot-2", debut: "2026-10-30T23:30:00Z", fin: "2026-10-31T05:00:00Z")
        let multi = S.mission(S.record(finLe: later.fin!, nbCreneaux: 2), slots: [S.slot(), later])
        XCTAssertEqual(MissionPresentation.periode(multi), "27/10/2026 → 31/10/2026 · 2 créneaux")
        let incomplete = S.mission(S.record(finLe: later.fin!, nbCreneaux: 2), slots: [S.slot()])
        XCTAssertEqual(MissionPresentation.periode(incomplete), "27/10/2026 → 31/10/2026 · planning à confirmer")
        // Créneau unique sans fin : planning non exact, même jour.
        let sansFin = S.mission(S.record(nbCreneaux: 1), slots: [S.slot(fin: nil)])
        XCTAssertEqual(MissionPresentation.periode(sansFin), "27/10/2026 · planning à confirmer")
    }

    func testLibellesProfessions() {
        XCTAssertEqual(MissionPresentation.professionLabel("IDE"), "Infirmier(ère) Diplômé(e) d'État (IDE)")
        XCTAssertEqual(MissionPresentation.professionLabel("DENTISTE"), "Chirurgien-Dentiste")
        XCTAssertEqual(MissionPresentation.professionLabel("INCONNU"), "INCONNU")
        XCTAssertEqual(MissionPresentation.professions.count, 17)
    }

    func testNombreJavaScript() {
        XCTAssertEqual(MissionPresentation.nombreJavaScript(70), "70")
        XCTAssertEqual(MissionPresentation.nombreJavaScript(70.5), "70.5")
        XCTAssertEqual(MissionPresentation.nombreJavaScript(5.6), "5.6")
        XCTAssertEqual(Geo.formaterDistance(nil), "Distance inconnue")
        XCTAssertEqual(Geo.formaterDistance(0.4), "400m")
        XCTAssertEqual(Geo.formaterDistance(5.6), "5.6 km")
    }

    func testCreneauEnHeureDeParis() {
        // 2026-07-02T06:00:00Z = jeudi 2 juillet 2026, 08:00 à Paris (heure d'été).
        let travail = MissionSlot(id: "s1", missionId: "m1", debut: "2026-07-02T06:00:00Z", fin: "2026-07-02T16:00:00Z",
                                  estPause: false, typeCreneau: "PREVISIONNEL")
        XCTAssertEqual(MissionPresentation.creneau(travail), "Jeudi 2 juillet · 08:00–18:00")
        // 2026-12-24T11:00:00Z = jeudi 24 décembre 2026, 12:00 à Paris (heure d'hiver), fin absente.
        let pause = MissionSlot(id: "s2", missionId: "m1", debut: "2026-12-24T11:00:00Z", fin: nil,
                                estPause: true, typeCreneau: "PREVISIONNEL")
        XCTAssertEqual(MissionPresentation.creneau(pause), "Pause · Jeudi 24 décembre · 12:00–—")
        let illisible = MissionSlot(debut: "pas une date", fin: nil, estPause: false, typeCreneau: "PREVISIONNEL")
        XCTAssertEqual(MissionPresentation.creneau(illisible), "Créneau à confirmer")
        let pauseIllisible = MissionSlot(debut: "", fin: nil, estPause: true, typeCreneau: "PREVISIONNEL")
        XCTAssertEqual(MissionPresentation.creneau(pauseIllisible), "Pause")
    }
}
