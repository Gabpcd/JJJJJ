import XCTest
@testable import JoleneCore

/// Rejoue `Resources/golden/planning-candidat.json` (port de
/// `src/components/planning/planning-candidat.ts`) et fige le format filaire de
/// `p_creneaux_confirmes` (`CreneauxConfirmes`, lot 1 T2).
final class RulesPlanningCandidatTests: XCTestCase {
    /// `MissionPlanningCandidat` JSON → entrée Swift. `nb_creneaux` suit `Number()` comme le web.
    static func mission(_ valeur: JSONValue?) throws -> PlanningCandidatInput {
        let mission = try XCTUnwrap(valeur, "mission absente du vecteur")
        return PlanningCandidatInput(
            id: mission["id"]?.string,
            debutLe: mission["debut_le"]?.string,
            finLe: mission["fin_le"]?.string,
            nbCreneaux: Golden.entier(mission["nb_creneaux"]),
            creneauxPlanifies: try (mission["creneaux_planifies"] ?? .array([])).decode([MissionSlot].self),
            erreurPlanning: mission["erreur_planning"]?.bool ?? false
        )
    }

    static func golden(_ planning: PlanningCandidat) -> JSONValue {
        .object([
            "creneaux": .array(planning.creneaux.map(\.golden)),
            "exact": .bool(planning.exact),
            "totalHeures": .number(planning.totalHeures),
            "periodeEtendue": .bool(planning.periodeEtendue),
            "messageBlocage": .chaine(planning.messageBlocage),
        ])
    }

    static func golden(_ creneaux: [CreneauConfirme]?) -> JSONValue {
        guard let creneaux else { return .null }
        return .array(creneaux.map { .object(["debut": .string($0.debut), "fin": .string($0.fin)]) })
    }

    func testVecteursGoldenPlanningCandidat() throws {
        var parFonction: [String: Int] = [:]
        let rejoues = try Golden.rejouer("planning-candidat") { vecteur in
            let entree = vecteur.input
            parFonction[vecteur.fonction, default: 0] += 1
            switch vecteur.fonction {
            case "construirePlanningCandidat":
                let creneaux = try entree["creneaux"].map { try $0.decode([MissionSlot].self) }
                return Self.golden(PlanningCandidatRules.construirePlanningCandidat(
                    try Self.mission(entree["mission"]), creneaux: creneaux, erreur: entree["erreur"]?.bool
                ))
            case "creneauxConfirmesPourAction":
                return Self.golden(CreneauxConfirmes.lus(try Self.mission(entree["mission"])))
            case "creneauxConfirmesFilaires":
                return Self.golden(CreneauxConfirmes.pourAction(try Self.mission(entree["mission"])))
            case "planningCorrespondAuFiltre":
                let filtre = try XCTUnwrap(entree["filtre"]?.string.flatMap(MissionFilters.Horaire.init(rawValue:)),
                                           "filtre inconnu dans « \(vecteur.name) »")
                return .bool(PlanningCandidatRules.planningCorrespondAuFiltre(try Self.mission(entree["mission"]), filtre: filtre))
            case "creneauContientNuit":
                return .bool(PlanningCandidatRules.creneauContientNuit(try XCTUnwrap(entree["creneau"]).decode(MissionSlot.self)))
            case "creneauChevaucheWeekend":
                return .bool(PlanningCandidatRules.creneauChevaucheWeekend(try XCTUnwrap(entree["creneau"]).decode(MissionSlot.self)))
            default:
                return nil
            }
        }
        XCTAssertGreaterThan(rejoues, 0)
        // Chaque fonction portée est effectivement couverte par l'export.
        for fonction in ["construirePlanningCandidat", "creneauxConfirmesPourAction", "creneauxConfirmesFilaires",
                         "planningCorrespondAuFiltre", "creneauContientNuit", "creneauChevaucheWeekend"] {
            XCTAssertGreaterThan(parFonction[fonction] ?? 0, 0, "aucun vecteur golden pour \(fonction)")
        }
    }

    // MARK: - CreneauxConfirmes : charge utile de fn_confirmer_action_planning_v1

    private func slot(_ id: String, _ debut: String, _ fin: String?, pause: Bool = false, type: String = "PREVISIONNEL") -> MissionSlot {
        MissionSlot(id: id, missionId: "m", debut: debut, fin: fin, estPause: pause, typeCreneau: type)
    }

    private func mission(nb: Int?, _ creneaux: [MissionSlot], erreur: Bool = false) -> PlanningCandidatInput {
        PlanningCandidatInput(id: "m", debutLe: "2026-07-06T08:00:00+02:00", finLe: "2026-07-08T16:00:00+02:00",
                              nbCreneaux: nb, creneauxPlanifies: creneaux, erreurPlanning: erreur)
    }

    func testFormatFilaireEstUTCSansFractionAvecSuffixeZ() throws {
        let creneaux = try XCTUnwrap(CreneauxConfirmes.pourAction(mission(nb: 1, [
            slot("a", "2026-07-06T08:00:00+02:00", "2026-07-06T16:00:00.000000+02:00"),
        ])))
        XCTAssertEqual(creneaux, [CreneauConfirme(debut: "2026-07-06T06:00:00Z", fin: "2026-07-06T14:00:00Z")])
        // Motif exigé par fn_valider_creneaux_mission_json (suffixe Z) et sans fraction.
        let motif = try NSRegularExpression(pattern: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$"#)
        for borne in creneaux.flatMap({ [$0.debut, $0.fin] }) {
            XCTAssertNotNil(motif.firstMatch(in: borne, range: NSRange(borne.startIndex..., in: borne)), borne)
        }
        // Encodage JSON : exactement les deux clés lues par le SQL (`element->>'debut'`, `element->>'fin'`).
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(creneaux)) as? [[String: String]]
        XCTAssertEqual(json, [["debut": "2026-07-06T06:00:00Z", "fin": "2026-07-06T14:00:00Z"]])
    }

    func testOrdreDuPlanningPausesEtEffectifsExclusNombreEgalAuCompteur() throws {
        let creneaux = [
            slot("j3", "2026-07-08T08:00:00+02:00", "2026-07-08T16:00:00+02:00"),
            slot("pause", "2026-07-07T12:00:00+02:00", "2026-07-07T12:30:00+02:00", pause: true),
            slot("j1", "2026-07-06T08:00:00+02:00", "2026-07-06T16:00:00+02:00"),
            slot("effectif", "2026-07-07T08:05:00+02:00", "2026-07-07T15:55:00+02:00", type: "EFFECTIF"),
            slot("j2", "2026-07-07T08:00:00+02:00", "2026-07-07T16:00:00+02:00"),
        ]
        let filaires = try XCTUnwrap(CreneauxConfirmes.pourAction(mission(nb: 3, creneaux)))
        XCTAssertEqual(filaires.map(\.debut), ["2026-07-06T06:00:00Z", "2026-07-07T06:00:00Z", "2026-07-08T06:00:00Z"])
        XCTAssertEqual(filaires.count, 3, "nombre = nb_creneaux, pause et EFFECTIF exclus")
        // Mêmes créneaux que la parité web, bornes lues inchangées.
        let lus = try XCTUnwrap(CreneauxConfirmes.lus(mission(nb: 3, creneaux)))
        XCTAssertEqual(lus.map(\.debut), ["2026-07-06T08:00:00+02:00", "2026-07-07T08:00:00+02:00", "2026-07-08T08:00:00+02:00"])
        // Compteur différent du nombre de lignes : aucune charge utile.
        XCTAssertNil(CreneauxConfirmes.pourAction(mission(nb: 2, creneaux)))
        XCTAssertNil(CreneauxConfirmes.pourAction(mission(nb: 4, creneaux)))
    }

    func testPlanningNonExactOuEnErreurNeProduitAucuneCharge() {
        let ouvert = [slot("o", "2026-07-06T08:00:00+02:00", nil)]
        XCTAssertNil(CreneauxConfirmes.pourAction(mission(nb: 1, ouvert)), "créneau sans fin")
        XCTAssertNil(CreneauxConfirmes.pourAction(mission(nb: 1, [slot("a", "2026-07-06T08:00:00+02:00", "2026-07-06T16:00:00+02:00")], erreur: true)),
                     "planning en erreur de chargement")
        // Mission longue (> 24 h) sans ligne : pas de repli, pas de charge utile.
        XCTAssertNil(CreneauxConfirmes.pourAction(mission(nb: nil, [])))
    }

    func testFractionDeSecondeNonNulleRefuseeEnEntier() {
        // Une fraction non nulle ne se représente pas sans changer l'instant comparé par le serveur :
        // toute la liste est refusée (planning à recharger), jamais tronquée.
        let microsecondes = [
            slot("a", "2026-07-06T06:00:00+00:00", "2026-07-06T14:00:00+00:00"),
            slot("b", "2026-07-07T06:00:00+00:00", "2026-07-07T14:00:00.000500+00:00"),
        ]
        XCTAssertNotNil(CreneauxConfirmes.lus(mission(nb: 2, microsecondes)), "la parité web garde la chaîne lue")
        XCTAssertNil(CreneauxConfirmes.pourAction(mission(nb: 2, microsecondes)))
        XCTAssertNil(CreneauxConfirmes.isoUTCSansFraction("2026-07-06T06:00:00.250+00:00"))
        XCTAssertNil(CreneauxConfirmes.isoUTCSansFraction("2026-07-06T06:00:00.000001Z"))
        XCTAssertEqual(CreneauxConfirmes.isoUTCSansFraction("2026-07-06T06:00:00.000+00:00"), "2026-07-06T06:00:00Z")
    }

    func testConversionUTCDecalagesHeureDEteEtLegacy() {
        XCTAssertEqual(CreneauxConfirmes.isoUTCSansFraction("2026-03-29T08:00:00+02:00"), "2026-03-29T06:00:00Z")
        XCTAssertEqual(CreneauxConfirmes.isoUTCSansFraction("2026-10-25T02:30:00+01:00"), "2026-10-25T01:30:00Z")
        XCTAssertEqual(CreneauxConfirmes.isoUTCSansFraction("2026-07-06T02:00:00-04:00"), "2026-07-06T06:00:00Z")
        XCTAssertEqual(CreneauxConfirmes.isoUTCSansFraction("2026-12-31T23:30:00-01:00"), "2027-01-01T00:30:00Z")
        // ISO legacy sans offset : heure murale française (CEST en juillet).
        XCTAssertEqual(CreneauxConfirmes.isoUTCSansFraction("2026-07-06T08:00"), "2026-07-06T06:00:00Z")
        XCTAssertNil(CreneauxConfirmes.isoUTCSansFraction("pas une date"))
        XCTAssertNil(CreneauxConfirmes.isoUTCSansFraction(""))
    }

    func testDateIllisibleEchoueFermeAuLieuDeLever() {
        // Le web lève (`instantJolene`) ; le port renvoie nil : planning non exact, action bloquée.
        // Domaine exclu des vecteurs golden (verrou `sansLevee` de l'export).
        let illisible = [slot("x", "pas une date", "2026-07-06T16:00:00+02:00")]
        XCTAssertNil(CreneauxConfirmes.lus(mission(nb: 1, illisible)))
        XCTAssertNil(CreneauxConfirmes.pourAction(mission(nb: 1, illisible)))
    }

    func testRepliPonctuelLegacySansLigneDonneLEnveloppe() throws {
        // Le serveur refuse ensuite (aucune ligne live, `v_nb_live = 0`) : le client reste fidèle au web.
        let ponctuelle = PlanningCandidatInput(id: "p", debutLe: "2026-07-06T08:00:00+02:00", finLe: "2026-07-06T16:00:00+02:00", nbCreneaux: 1)
        XCTAssertEqual(try XCTUnwrap(CreneauxConfirmes.pourAction(ponctuelle)),
                       [CreneauConfirme(debut: "2026-07-06T06:00:00Z", fin: "2026-07-06T14:00:00Z")])
    }

    func testMissionEnrichieUtiliseSesCreneauxEtSonErreur() throws {
        typealias S = MissionsTestSupport
        let mission = S.mission()
        XCTAssertEqual(try XCTUnwrap(CreneauxConfirmes.pourAction(PlanningCandidatInput(mission: mission))),
                       [CreneauConfirme(debut: "2026-10-27T08:00:00Z", fin: "2026-10-27T16:00:00Z")])
        var enErreur = mission
        enErreur.erreurPlanning = true
        XCTAssertNil(CreneauxConfirmes.pourAction(PlanningCandidatInput(mission: enErreur)))
    }
}
