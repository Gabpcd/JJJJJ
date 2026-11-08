import XCTest
@testable import JoleneCore

/// Rejoue `Resources/golden/presences-soignant-listes.json` (port de `regrouperCreneauxParMission`
/// et `construireListesPresences`, `src/lib/presences-soignant-listes.ts`, extraits de
/// `PresencesSoignant.tsx` par la PR web W1, #1112). Si un vecteur diverge, on corrige le port,
/// jamais le vecteur.
final class RulesListesPresencesTests: XCTestCase {
    private typealias Listes = ListesPresencesSoignant<MissionPresence, JSONValue>

    // MARK: - Projection de l'export

    /// L'export garde de chaque mission recopiée son identifiant, ses créneaux et son établissement.
    private func golden(_ m: MissionPresenceEnrichie<MissionPresence, JSONValue>) -> JSONValue {
        .object(["id": .string(m.mission.id), "creneaux": .array(m.creneaux.map(\.golden)), "etablissements": m.etablissement ?? .null])
    }

    private func golden(_ m: MissionPresenceAVenir<MissionPresence, JSONValue>) -> JSONValue {
        .object([
            "id": .string(m.mission.id),
            "creneaux": .array(m.creneaux.map(\.golden)),
            "etablissements": m.etablissement ?? .null,
            "dateAffichage": .chaine(m.dateAffichage),
            "prochainCreneau": m.prochainCreneau?.golden ?? .null,
            // `JSON.stringify(NaN)` vaut `null` : le natif ne rend jamais une durée non finie.
            "dureeAffichageHeures": m.dureeAffichageHeures.map(JSONValue.number) ?? .null,
            "planningAConfirmer": .bool(m.planningAConfirmer),
        ])
    }

    private func golden(_ listes: Listes) -> JSONValue {
        .object([
            "missionsAujourdhui": .array(listes.missionsAujourdhui.map { golden($0) }),
            "missionsAVenir": .array(listes.missionsAVenir.map { golden($0) }),
            "missionsEnCours": .array(listes.missionsEnCours.map { golden($0) }),
            "contrats": .object(listes.contrats.mapValues { .string($0.id) }),
        ])
    }

    // MARK: - Décodage des entrées

    private func mission(_ json: JSONValue) throws -> MissionPresence {
        MissionPresence(id: try XCTUnwrap(json["id"]?.string), statut: try XCTUnwrap(json["statut"]?.string),
                        debutLe: try XCTUnwrap(json["debut_le"]?.string), finLe: try XCTUnwrap(json["fin_le"]?.string),
                        dureeHeures: json["duree_heures"]?.double, etablissementId: json["etablissement_id"]?.string)
    }

    private func construire(_ entree: JSONValue) throws -> JSONValue {
        let missions = try XCTUnwrap(entree["missions"]?.array).map(mission)
        let creneaux = try XCTUnwrap(entree["creneauxParMission"]).decode([String: [MissionSlot]].self)
        // `contrats` nul ou absent : aucun contrat (`contrats || []`).
        let contrats = try entree["contrats"]?.array.map { try JSONValue.array($0).decode([ContratPointage].self) }
        var etablissements: [String: JSONValue] = [:]
        if case .object(let carte)? = entree["etablissements"] { etablissements = carte }
        let listes: Listes = ListesPresences.construire(missions: missions, creneauxParMission: creneaux, contrats: contrats,
                                                        maintenant: try Golden.instant(entree["maintenant"]),
                                                        etablissements: etablissements)
        return golden(listes)
    }

    func testVecteursGoldenPresencesSoignantListes() throws {
        let rejoues = try Golden.rejouer("presences-soignant-listes") { vecteur in
            switch vecteur.fonction {
            case "regrouperCreneauxParMission":
                let creneaux = try vecteur.input["creneaux"]?.array.map { try JSONValue.array($0).decode([MissionSlot].self) }
                return .object(ListesPresences.regrouperCreneauxParMission(creneaux).mapValues { .array($0.map(\.golden)) })
            case "construireListesPresences":
                return try construire(vecteur.input)
            default:
                return nil
            }
        }
        XCTAssertGreaterThan(rejoues, 0)
    }

    // MARK: - Garanties hors vecteurs

    /// Lundi 2 novembre 2026, 10 h à Paris : 2026-11-02T09:00:00Z.
    private let maintenant = DateHeureParis.date(millisecondes: 1_793_610_000_000)

    private func slot(_ id: String, _ debut: String, _ fin: String?, type: String = "PREVISIONNEL", missionId: String? = nil) -> MissionSlot {
        MissionSlot(id: id, missionId: missionId, debut: debut, fin: fin, estPause: false, typeCreneau: type)
    }

    func testUnContratSansMissionNOuvreJamaisLePointage() {
        // Hors domaine (`contrats_mission.mission_id` NOT NULL) : échec fermé, aucun contrat retenu.
        let listes: ListesPresencesSoignant<MissionPresence, String> = ListesPresences.construire(
            missions: [], creneauxParMission: [:],
            contrats: [ContratPointage(id: "orphelin", statut: "SIGNE_COMPLET", creeLe: "2026-10-01T00:00:00Z", missionId: nil)],
            maintenant: maintenant)
        XCTAssertTrue(listes.contrats.isEmpty)
    }

    func testUnCreneauSansMissionNEstRattacheANulleMission() {
        // Hors domaine (`mission_creneaux.mission_id` NOT NULL) : le créneau n'appartient à aucune mission.
        let groupes = ListesPresences.regrouperCreneauxParMission([
            slot("orphelin", "2026-11-02T07:00:00Z", "2026-11-02T15:00:00Z"),
            slot("a1", "2026-11-02T07:00:00Z", "2026-11-02T15:00:00Z", missionId: "a"),
        ])
        XCTAssertEqual(groupes.keys.sorted(), ["a"])
        XCTAssertEqual(groupes["a"]?.map(\.id), ["a1"])
    }

    func testUneFinIllisibleNeDonneJamaisUneDureeNonFinie() throws {
        let mission = MissionPresence(id: "m", statut: "ASSIGNEE", debutLe: "2026-10-20T07:00:00Z", finLe: "2026-11-20T15:00:00Z",
                                      dureeHeures: 7, etablissementId: nil)
        let listes: ListesPresencesSoignant<MissionPresence, String> = ListesPresences.construire(
            missions: [mission], creneauxParMission: ["m": [slot("c", "2026-11-04T07:00:00Z", "pas une date")]],
            contrats: [], maintenant: maintenant)
        let aVenir = try XCTUnwrap(listes.missionsAVenir.first)
        XCTAssertEqual(aVenir.dateAffichage, "2026-11-04T07:00:00Z")
        XCTAssertNil(aVenir.dureeAffichageHeures, "le web afficherait « NaN » : le natif n'affiche aucune durée")
        XCTAssertFalse(aVenir.planningAConfirmer)
    }

    func testAVenirEstBorneA20Missions() {
        XCTAssertEqual(ListesPresences.limiteAVenir, 20)
        let missions = (0..<25).map {
            MissionPresence(id: "m\($0)", statut: "ASSIGNEE", debutLe: "2026-10-20T07:00:00Z", finLe: "2026-11-20T15:00:00Z",
                            dureeHeures: nil, etablissementId: nil)
        }
        let listes: ListesPresencesSoignant<MissionPresence, String> = ListesPresences.construire(
            missions: missions, creneauxParMission: [:], contrats: nil, maintenant: maintenant)
        XCTAssertEqual(listes.missionsAVenir.count, 20)
        XCTAssertTrue(listes.missionsAVenir.allSatisfy(\.planningAConfirmer))
        XCTAssertEqual(listes.missionsAVenir.map(\.mission.id), (0..<20).map { "m\($0)" }, "ordre reçu conservé (tri stable)")
    }

    func testUneMissionLueEstUtilisableDirectement() throws {
        // `MissionRecord` (lot 1) porte les colonnes lues par la page : aucune copie n'est nécessaire.
        let record = MissionsTestSupport.record(finLe: "2026-10-27T16:00:00Z")
        let listes: ListesPresencesSoignant<MissionRecord, String> = ListesPresences.construire(
            missions: [record], creneauxParMission: [:], contrats: [], maintenant: try DateHeureParis.instantJolene("2026-10-27T09:00:00Z"),
            etablissements: ["etab-1": "Établissement de test"])
        XCTAssertEqual(listes.missionsAujourdhui.map(\.mission), [record], "mission ponctuelle du jour (repli sur sa plage)")
        XCTAssertEqual(listes.missionsAujourdhui.first?.etablissement, "Établissement de test")
        XCTAssertEqual(listes.missionsAujourdhui.first?.creneaux.map(\.id), ["mission-ponctuelle-mission-1"])
    }

    func testLesActivesSontLesMissionsEnCoursSansDependreDesPresences() {
        let missions = ["EN_COURS", "ASSIGNEE", "EN_COURS"].enumerated().map { index, statut in
            MissionPresence(id: "m\(index)", statut: statut, debutLe: "2026-10-10T07:00:00Z", finLe: "2026-11-20T15:00:00Z",
                            dureeHeures: nil, etablissementId: nil)
        }
        let listes: ListesPresencesSoignant<MissionPresence, String> = ListesPresences.construire(
            missions: missions, creneauxParMission: [:], contrats: [], maintenant: maintenant)
        XCTAssertEqual(listes.missionsEnCours.map(\.mission.id), ["m0", "m2"])
        XCTAssertEqual(listes.missionsEnCours.map(\.statut), ["EN_COURS", "EN_COURS"])
    }
}
