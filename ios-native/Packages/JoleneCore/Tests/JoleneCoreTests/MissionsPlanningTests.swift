import XCTest
@testable import JoleneCore

final class MissionsPlanningTests: XCTestCase {
    typealias S = MissionsTestSupport

    func testDistanceHaversineIdentiqueAuWeb() {
        // Valeurs calculées par `calculerDistanceKm` (src/lib/geo.ts) via Node.
        XCTAssertEqual(Geo.distanceKm(lat1: 48.8566, lng1: 2.3522, lat2: 48.879, lng2: 2.421), 5.6)
        XCTAssertEqual(Geo.distanceKm(lat1: 48.8566, lng1: 2.3522, lat2: 48.867, lng2: 2.363), 1.4)
        XCTAssertEqual(Geo.distanceKm(lat1: 48.8566, lng1: 2.3522, lat2: 48.848, lng2: 2.439), 6.4)
        XCTAssertEqual(Geo.distanceKm(lat1: 48.8566, lng1: 2.3522, lat2: 48.8566, lng2: 2.3522), 0)
        XCTAssertNil(Geo.distanceKm(lat1: nil, lng1: 2.3522, lat2: 48.879, lng2: 2.421))
        XCTAssertNil(Geo.distanceKm(lat1: 48.8566, lng1: 2.3522, lat2: 48.879, lng2: nil))
    }

    func testParseInstantISOEtLegacyParis() {
        let attendu = Date(timeIntervalSince1970: 1_793_577_600) // 2026-11-02T00:00:00Z
        XCTAssertEqual(PlanningHorlogeParis.instant("2026-11-02T00:00:00Z"), attendu)
        XCTAssertEqual(PlanningHorlogeParis.instant("2026-11-02T00:00:00.000Z"), attendu)
        XCTAssertEqual(PlanningHorlogeParis.instant("2026-11-02T00:00:00+00:00"), attendu)
        XCTAssertEqual(PlanningHorlogeParis.instant("2026-11-02T01:00:00+01:00"), attendu)
        // Fraction tronquée à la milliseconde comme `new Date()` ; comparaison en millisecondes
        // entières (modèle JavaScript), jamais en `Double` : 0.123 n'est pas représentable exactement.
        XCTAssertEqual(PlanningHorlogeParis.instant("2026-11-02 00:00:00.123456+00").map(DateHeureParis.millisecondes),
                       1_793_577_600_123)
        // ISO legacy sans offset : heure murale française (CET en novembre).
        XCTAssertEqual(PlanningHorlogeParis.instant("2026-11-02T01:00:00"), attendu)
        XCTAssertEqual(PlanningHorlogeParis.instant("2026-11-02T01:00"), attendu)
        XCTAssertNil(PlanningHorlogeParis.instant("pas une date"))
        XCTAssertNil(PlanningHorlogeParis.instant("2026-11-02T01:00:00X"))
    }

    func testComposantesParisEtJoursCivils() {
        let instant = PlanningHorlogeParis.instant("2026-10-30T23:30:00Z")!
        let parties = PlanningHorlogeParis.parties(instant)
        XCTAssertEqual(parties, PlanningHorlogeParis.Parties(annee: 2026, mois: 10, jour: 31, heure: 0, minute: 30, seconde: 0))
        XCTAssertEqual(PlanningHorlogeParis.dateCourte(instant), "31/10/2026")
        XCTAssertEqual(PlanningHorlogeParis.heureMinute(instant), "00:30")
        XCTAssertEqual(PlanningHorlogeParis.jourSemaine(instant), 6) // samedi
        let minuit = PlanningHorlogeParis.debutJour(instant)
        XCTAssertEqual(minuit, PlanningHorlogeParis.instant("2026-10-30T23:00:00Z"))
        XCTAssertEqual(PlanningHorlogeParis.ajouterJoursCivils(minuit, 1), PlanningHorlogeParis.instant("2026-10-31T23:00:00Z"))
        // Passage à l'heure d'hiver 2026 (25/10) : 24/10 00:00 CEST + 1 jour = 25/10 00:00 CEST, + 2 = 26/10 00:00 CET.
        let veille = PlanningHorlogeParis.instant("2026-10-23T22:00:00Z")!
        XCTAssertEqual(PlanningHorlogeParis.ajouterJoursCivils(veille, 1), PlanningHorlogeParis.instant("2026-10-24T22:00:00Z"))
        XCTAssertEqual(PlanningHorlogeParis.ajouterJoursCivils(veille, 2), PlanningHorlogeParis.instant("2026-10-25T23:00:00Z"))
        XCTAssertEqual(PlanningHorlogeParis.instantDuJour(veille, heure: 20), PlanningHorlogeParis.instant("2026-10-24T18:00:00Z"))
    }

    func testConstruirePlanningCandidat() {
        let planning = PlanningCandidatRules.construirePlanningCandidat(PlanningCandidatInput(record: S.record(), creneaux: [S.slot()]))
        XCTAssertTrue(planning.exact)
        XCTAssertEqual(planning.totalHeures, 8)
        XCTAssertFalse(planning.periodeEtendue)
        XCTAssertNil(planning.messageBlocage)

        let later = S.slot(id: "slot-2", debut: "2026-10-30T23:30:00Z", fin: "2026-10-31T05:00:00Z")
        let pause = S.slot(id: "pause", debut: "2026-10-27T12:00:00Z", fin: "2026-10-27T12:30:00Z", estPause: true)
        let multi = PlanningCandidatRules.construirePlanningCandidat(
            PlanningCandidatInput(record: S.record(finLe: later.fin!, nbCreneaux: 2), creneaux: [later, pause, S.slot()]))
        XCTAssertTrue(multi.exact)
        XCTAssertEqual(multi.creneaux.map(\.id), ["slot-1", "slot-2"], "tri par début, pause exclue")
        XCTAssertEqual(multi.totalHeures, 13.5)
        XCTAssertTrue(multi.periodeEtendue)

        let incomplet = PlanningCandidatRules.construirePlanningCandidat(
            PlanningCandidatInput(record: S.record(finLe: later.fin!, nbCreneaux: 2), creneaux: [S.slot()]))
        XCTAssertFalse(incomplet.exact)
        XCTAssertEqual(incomplet.messageBlocage, PlanningCandidatRules.messagePlanningIncomplet)

        let erreur = PlanningCandidatRules.construirePlanningCandidat(PlanningCandidatInput(record: S.record(), creneaux: [S.slot()], erreurPlanning: true))
        XCTAssertFalse(erreur.exact)
        XCTAssertEqual(erreur.messageBlocage, PlanningCandidatRules.messageErreurChargement)

        let sansFin = PlanningCandidatRules.construirePlanningCandidat(PlanningCandidatInput(record: S.record(), creneaux: [S.slot(fin: nil)]))
        XCTAssertFalse(sansFin.exact, "un créneau de travail sans fin bloque, même avec le repli ponctuel")
        XCTAssertEqual(sansFin.creneaux.count, 1, "le repli contractuel reste proposé")

        // Mission longue (> 24 h) sans créneau : pas de repli, planning à confirmer.
        let longue = PlanningCandidatRules.construirePlanningCandidat(
            PlanningCandidatInput(record: S.record(finLe: "2026-10-29T16:00:00Z", nbCreneaux: nil), creneaux: []))
        XCTAssertFalse(longue.exact)
        XCTAssertTrue(longue.creneaux.isEmpty)
        // Créneau de nuit à cheval sur minuit : période étendue même avec un seul créneau.
        let nuit = PlanningCandidatRules.construirePlanningCandidat(PlanningCandidatInput(record: S.record(nbCreneaux: 1), creneaux: [S.slot(debut: "2026-10-30T20:00:00Z", fin: "2026-10-31T05:00:00Z")])) // 21:00 → 06:00 Paris
        XCTAssertTrue(nuit.periodeEtendue)
    }

    func testCreneauIllisibleRendLePlanningNonExactSansLeCompterAZero() {
        let lisible = MissionSlot(id: "a", debut: "2026-12-01T08:00:00+00:00", fin: "2026-12-01T16:00:00+00:00", estPause: false, typeCreneau: "PREVISIONNEL")
        let illisible = MissionSlot(id: "b", debut: "pas-une-date", fin: "2026-12-02T16:00:00+00:00", estPause: false, typeCreneau: "PREVISIONNEL")
        let input = PlanningCandidatInput(id: "m", debutLe: "2026-12-01T08:00:00+00:00", finLe: "2026-12-02T16:00:00+00:00", nbCreneaux: 2,
                                          creneauxPlanifies: [illisible, lisible])
        let planning = PlanningCandidatRules.construirePlanningCandidat(input)
        XCTAssertFalse(planning.exact, "un créneau à date illisible ne peut pas être vérifié : fail-closed")
        XCTAssertEqual(planning.messageBlocage, PlanningCandidatRules.messageErreurChargement)
        XCTAssertEqual(planning.totalHeures, 8, "seules les heures lisibles sont comptées")
        // Tri stable identique à `Array.prototype.sort` : la date illisible (NaN) garde sa position.
        XCTAssertEqual(planning.creneaux.map { $0.id }, ["b", "a"])
        XCTAssertEqual(PlanningCandidatRules.creneauxPrevisionnels([illisible, lisible]),
                       DisponibilitePointage.creneauxPrevisionnels([illisible, lisible]), "une seule implémentation")
    }

    func testRepliPonctuelDelegueADisponibilitePointage() {
        let attendu = DisponibilitePointage.ajouterRepliMissionPonctuelle(
            [], mission: PeriodeMissionPointage(id: "m", debutLe: "2026-12-01T08:00:00+00:00", finLe: "2026-12-01T16:00:00+00:00"))
        XCTAssertEqual(PlanningCandidatRules.ajouterRepliMissionPonctuelle([], id: "m", debutLe: "2026-12-01T08:00:00+00:00", finLe: "2026-12-01T16:00:00+00:00"), attendu)
        XCTAssertEqual(attendu.map { $0.id }, ["mission-ponctuelle-m"])
        // Date illisible : aucun repli, comme NaN côté JS.
        XCTAssertEqual(PlanningCandidatRules.ajouterRepliMissionPonctuelle([], id: "m", debutLe: "x", finLe: "2026-12-01T16:00:00+00:00"), [])
    }

    func testNuitEtWeekendParJourCivilParis() {
        XCTAssertFalse(PlanningCandidatRules.creneauContientNuit(S.slot())) // 09:00-17:00 Paris
        XCTAssertTrue(PlanningCandidatRules.creneauContientNuit(S.slot(debut: "2026-10-30T23:30:00Z", fin: "2026-10-31T05:00:00Z")))
        XCTAssertTrue(PlanningCandidatRules.creneauContientNuit(S.slot(debut: "2026-10-27T18:30:00Z", fin: "2026-10-27T19:30:00Z"))) // 19:30-20:30
        XCTAssertFalse(PlanningCandidatRules.creneauContientNuit(S.slot(debut: "2026-10-27T06:00:00Z", fin: "2026-10-27T19:00:00Z"))) // 07:00-20:00 exact
        XCTAssertTrue(PlanningCandidatRules.creneauContientNuit(S.slot(debut: "2026-10-27T05:59:00Z", fin: "2026-10-27T19:00:00Z")))
        XCTAssertFalse(PlanningCandidatRules.creneauContientNuit(S.slot(fin: nil)))
        XCTAssertFalse(PlanningCandidatRules.creneauChevaucheWeekend(S.slot())) // mardi 27/10
        XCTAssertTrue(PlanningCandidatRules.creneauChevaucheWeekend(S.slot(debut: "2026-10-30T23:30:00Z", fin: "2026-10-31T05:00:00Z"))) // samedi 00:30
        XCTAssertFalse(PlanningCandidatRules.creneauChevaucheWeekend(S.slot(debut: "2026-10-30T20:00:00Z", fin: "2026-10-30T23:00:00Z"))) // vendredi jusqu'à minuit
        XCTAssertTrue(PlanningCandidatRules.creneauChevaucheWeekend(S.slot(debut: "2026-10-30T20:00:00Z", fin: "2026-10-30T23:00:01Z")))
    }

    func testPlanningCorrespondAuFiltre() {
        let input = PlanningCandidatInput(mission: S.mission())
        XCTAssertTrue(PlanningCandidatRules.planningCorrespondAuFiltre(input, filtre: .tous))
        XCTAssertTrue(PlanningCandidatRules.planningCorrespondAuFiltre(input, filtre: .jour))
        XCTAssertFalse(PlanningCandidatRules.planningCorrespondAuFiltre(input, filtre: .nuit))
        XCTAssertFalse(PlanningCandidatRules.planningCorrespondAuFiltre(input, filtre: .weekend))
        let inexact = PlanningCandidatInput(mission: S.mission(S.record(nbCreneaux: 2), slots: [S.slot()]))
        XCTAssertTrue(PlanningCandidatRules.planningCorrespondAuFiltre(inexact, filtre: .tous))
        XCTAssertFalse(PlanningCandidatRules.planningCorrespondAuFiltre(inexact, filtre: .jour))
    }
}
