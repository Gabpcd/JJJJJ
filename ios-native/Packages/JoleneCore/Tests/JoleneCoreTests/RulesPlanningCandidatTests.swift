import XCTest
@testable import JoleneCore

/// Rejoue `Resources/golden/planning-candidat.json`
/// (port de `src/components/planning/planning-candidat.ts`) et fige le contrat de
/// `CreneauxConfirmes` (charge utile `p_creneaux_confirmes` de `fn_confirmer_action_planning_v1`).
final class RulesPlanningCandidatTests: XCTestCase {
    typealias S = MissionsTestSupport

    // MARK: - Adaptateurs golden

    /// `MissionPlanningCandidat` du web (clés PostgREST) → entrée du port.
    static func mission(_ valeur: JSONValue?) throws -> PlanningCandidatInput {
        let m = try XCTUnwrap(valeur)
        return PlanningCandidatInput(
            id: m["id"]?.string ?? m["mission_id"]?.string,
            debutLe: m["debut_le"]?.string,
            finLe: m["fin_le"]?.string,
            nbCreneaux: Golden.entier(m["nb_creneaux"]),
            creneauxPlanifies: try (m["creneaux_planifies"] ?? .array([])).decode([MissionSlot].self),
            erreurPlanning: m["erreur_planning"]?.bool ?? false
        )
    }

    private func golden(_ planning: PlanningCandidat) -> JSONValue {
        .object([
            "creneaux": .array(planning.creneaux.map(\.golden)),
            "exact": .bool(planning.exact),
            "totalHeures": .number(planning.totalHeures),
            "periodeEtendue": .bool(planning.periodeEtendue),
            "messageBlocage": .chaine(planning.messageBlocage),
        ])
    }

    private func filtre(_ valeur: JSONValue?) throws -> MissionFilters.Horaire {
        try XCTUnwrap(MissionFilters.Horaire(rawValue: try XCTUnwrap(valeur?.string)))
    }

    func testVecteursGoldenPlanningCandidat() throws {
        let rejoues = try Golden.rejouer("planning-candidat") { vecteur in
            let entree = vecteur.input
            switch vecteur.fonction {
            case "construirePlanningCandidat":
                return golden(PlanningCandidatRules.construirePlanningCandidat(try Self.mission(entree["mission"])))
            case "creneauContientNuit":
                return .bool(PlanningCandidatRules.creneauContientNuit(try XCTUnwrap(entree["creneau"]).decode(MissionSlot.self)))
            case "creneauChevaucheWeekend":
                return .bool(PlanningCandidatRules.creneauChevaucheWeekend(try XCTUnwrap(entree["creneau"]).decode(MissionSlot.self)))
            case "planningCorrespondAuFiltre":
                return .bool(PlanningCandidatRules.planningCorrespondAuFiltre(try Self.mission(entree["mission"]), filtre: try filtre(entree["filtre"])))
            case "creneauxConfirmesPourAction":
                // Le web renvoie `debut`/`fin` tels que lus : la sélection est comparée mot pour mot,
                // la sérialisation `Z` de la charge utile RPC est un contrat Swift testé à part.
                guard let selection = CreneauxConfirmes.selectionner(try Self.mission(entree["mission"])) else { return .null }
                return .array(selection.map { .object(["debut": .string($0.debut), "fin": .chaine($0.fin)]) })
            default:
                return nil
            }
        }
        XCTAssertGreaterThan(rejoues, 0)
    }

    func testLeFichierGoldenCouvreChaqueFonctionPortee() throws {
        let fonctions = Set(try Golden.charger("planning-candidat").map(\.fonction))
        for attendue in ["construirePlanningCandidat", "creneauContientNuit", "creneauChevaucheWeekend",
                         "planningCorrespondAuFiltre", "creneauxConfirmesPourAction"] {
            XCTAssertTrue(fonctions.contains(attendue), "planning-candidat.json ne couvre pas « \(attendue) »")
        }
    }

    // MARK: - CreneauxConfirmes (charge utile RPC)

    func testSelectionRenvoieLesCreneauxExactsTriesSansPause() throws {
        let later = S.slot(id: "slot-2", debut: "2026-10-30T23:30:00Z", fin: "2026-10-31T05:00:00Z")
        let pause = S.slot(id: "pause", debut: "2026-10-27T12:00:00Z", fin: "2026-10-27T12:30:00Z", estPause: true)
        let effectif = S.slot(id: "eff", debut: "2026-10-27T08:05:00Z", fin: "2026-10-27T15:55:00Z", typeCreneau: "EFFECTIF")
        let mission = PlanningCandidatInput(record: S.record(finLe: later.fin!, nbCreneaux: 2), creneaux: [later, pause, effectif, S.slot()])
        let selection = try XCTUnwrap(CreneauxConfirmes.selectionner(mission))
        XCTAssertEqual(selection.map(\.id), ["slot-1", "slot-2"], "tri par début, pause et EFFECTIF exclus")
        XCTAssertEqual(selection.count, 2, "autant de créneaux que `nb_creneaux`")
        XCTAssertEqual(selection.map(\.debut), ["2026-10-27T08:00:00Z", "2026-10-30T23:30:00Z"], "chaînes lues, jamais réécrites")
    }

    func testSelectionNulleSiPlanningInexact() {
        let later = S.slot(id: "slot-2", debut: "2026-10-30T23:30:00Z", fin: "2026-10-31T05:00:00Z")
        XCTAssertNil(CreneauxConfirmes.selectionner(PlanningCandidatInput(record: S.record(finLe: later.fin!, nbCreneaux: 2), creneaux: [S.slot()])), "incomplet")
        XCTAssertNil(CreneauxConfirmes.selectionner(PlanningCandidatInput(record: S.record(), creneaux: [S.slot()], erreurPlanning: true)), "erreur de chargement")
        XCTAssertNil(CreneauxConfirmes.selectionner(PlanningCandidatInput(record: S.record(), creneaux: [S.slot(fin: nil)])), "créneau sans fin")
        XCTAssertNil(CreneauxConfirmes.pourAction(PlanningCandidatInput(record: S.record(), creneaux: [S.slot(fin: nil)])))
    }

    func testChargeUtileEnISO8601UTCSansFraction() throws {
        // Mêmes instants que les créneaux lus (offset +02:00, legacy sans offset, Z), sérialisés en UTC `Z`.
        let ete = S.slot(id: "a", debut: "2026-07-06T08:00:00+02:00", fin: "2026-07-06T16:00:00+02:00")
        let legacy = S.slot(id: "b", debut: "2026-08-31T08:00:00", fin: "2026-08-31T16:00:00")
        let utc = S.slot(id: "c", debut: "2026-12-01T07:00:00Z", fin: "2026-12-01T15:00:00.000Z")
        let mission = PlanningCandidatInput(id: "m", debutLe: "2026-07-06T08:00:00+02:00", finLe: "2026-12-01T15:00:00Z", nbCreneaux: 3,
                                            creneauxPlanifies: [utc, legacy, ete])
        let charge = try XCTUnwrap(CreneauxConfirmes.pourAction(mission))
        XCTAssertEqual(charge, [
            CreneauConfirme(debut: "2026-07-06T06:00:00Z", fin: "2026-07-06T14:00:00Z"),
            CreneauConfirme(debut: "2026-08-31T06:00:00Z", fin: "2026-08-31T14:00:00Z"),
            CreneauConfirme(debut: "2026-12-01T07:00:00Z", fin: "2026-12-01T15:00:00Z"),
        ])
        for creneau in charge {
            XCTAssertNotNil(creneau.debut.range(of: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$"#, options: .regularExpression), creneau.debut)
            XCTAssertNotNil(creneau.fin.range(of: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$"#, options: .regularExpression), creneau.fin)
        }
        // Chaque instant sérialisé est l'instant lu (le serveur compare des timestamptz).
        for (source, confirme) in zip(CreneauxConfirmes.selectionner(mission)!, charge) {
            XCTAssertEqual(try DateHeureParis.instantJolene(confirme.debut), try DateHeureParis.instantJolene(source.debut))
            XCTAssertEqual(try DateHeureParis.instantJolene(confirme.fin), try DateHeureParis.instantJolene(try XCTUnwrap(source.fin)))
        }
    }

    func testChargeUtileConserveUneFractionNonNulle() throws {
        // Un créneau à la milliseconde (jamais produit par le formulaire web) garde sa fraction :
        // la tronquer ferait diverger la comparaison serveur (`PLANNING_MODIFIE_RECONFIRMER`).
        let slot = S.slot(debut: "2026-10-27T08:00:00.250Z", fin: "2026-10-27T16:00:00Z")
        let charge = try XCTUnwrap(CreneauxConfirmes.pourAction(PlanningCandidatInput(record: S.record(), creneaux: [slot])))
        XCTAssertEqual(charge, [CreneauConfirme(debut: "2026-10-27T08:00:00.250Z", fin: "2026-10-27T16:00:00Z")])
    }

    func testChargeUtileSurLeRepliPonctuelEtClesJSON() throws {
        let mission = PlanningCandidatInput(id: "m", debutLe: "2026-07-31T08:00:00+02:00", finLe: "2026-07-31T16:00:00+02:00", nbCreneaux: 1)
        let charge = try XCTUnwrap(CreneauxConfirmes.pourAction(mission))
        XCTAssertEqual(charge, [CreneauConfirme(debut: "2026-07-31T06:00:00Z", fin: "2026-07-31T14:00:00Z")])
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(charge)) as? [[String: String]]
        XCTAssertEqual(json, [["debut": "2026-07-31T06:00:00Z", "fin": "2026-07-31T14:00:00Z"]], "clés `debut`/`fin` attendues par le serveur")
    }

    func testChargeUtileDepuisUneMissionEnrichie() {
        let mission = S.mission()
        XCTAssertEqual(CreneauxConfirmes.pourAction(mission)?.count, 1)
        let inexacte = S.mission(S.record(nbCreneaux: 2), slots: [S.slot()])
        XCTAssertNil(CreneauxConfirmes.pourAction(inexacte))
    }
}
