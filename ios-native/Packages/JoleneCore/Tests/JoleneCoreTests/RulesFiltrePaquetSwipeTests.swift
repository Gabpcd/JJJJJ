import XCTest
@testable import JoleneCore

/// Rejoue `Resources/golden/filtre-paquet-swipe.json` (port de `src/lib/filtre-paquet-swipe.ts`, L4-T2).
final class RulesFiltrePaquetSwipeTests: XCTestCase {
    /// Carte du paquet (clés de `fn_obtenir_missions_swipe`) → entrée Swift ; le planning suit `RulesPlanningCandidatTests`.
    static func mission(_ valeur: JSONValue?) throws -> (id: String, mission: MissionPaquetSwipe) {
        let carte = try XCTUnwrap(valeur, "mission absente du vecteur")
        var planning = try RulesPlanningCandidatTests.mission(carte)
        planning.id = carte["id"]?.string ?? carte["mission_id"]?.string
        return (try XCTUnwrap(carte["mission_id"]?.string), MissionPaquetSwipe(
            professionRequise: carte["profession_requise"]?.string,
            etablissementVille: carte["etablissement_ville"]?.string,
            etablissementCodePostal: carte["etablissement_code_postal"]?.string,
            distanceKm: carte["distance_km"]?.double,
            tauxHoraireBase: carte["taux_horaire_base"]?.double,
            typeContratRecherche: carte["type_contrat_recherche"]?.string,
            estUrgente: carte["est_urgente"]?.bool ?? false,
            planning: planning
        ))
    }

    static func filtre(_ valeur: JSONValue?) throws -> FiltrePaquetSwipe? {
        guard let valeur, !valeur.estNull else { return nil }
        return FiltrePaquetSwipe(
            urgentesOnly: try XCTUnwrap(valeur["urgentesOnly"]?.bool),
            horaire: try XCTUnwrap(valeur["horaire"]?.string.flatMap(MissionFilters.Horaire.init(rawValue:))),
            profession: try XCTUnwrap(valeur["profession"]?.string),
            ville: try XCTUnwrap(valeur["ville"]?.string),
            rayonKm: try XCTUnwrap(valeur["rayonKm"]?.double),
            tauxMin: try XCTUnwrap(valeur["tauxMin"]?.double),
            typeContrat: try XCTUnwrap(valeur["typeContrat"]?.string)
        )
    }

    func testVecteursGoldenFiltrePaquetSwipe() throws {
        var parFonction: [String: Int] = [:]
        let rejoues = try Golden.rejouer("filtre-paquet-swipe") { vecteur in
            let entree = vecteur.input
            parFonction[vecteur.fonction, default: 0] += 1
            let parcours = entree["professionParcours"]?.string
            switch vecteur.fonction {
            case "missionCorrespondProfessionInscription":
                return .bool(FiltrePaquetSwipe.missionCorrespondProfessionInscription(
                    requise: entree["requise"]?.string, selection: try XCTUnwrap(entree["selection"]?.string),
                    compte: try XCTUnwrap(entree["compte"]?.string)))
            case "missionPasseFiltrePaquet":
                let filtre = try XCTUnwrap(try Self.filtre(entree["filtre"]))
                return .bool(filtre.laissePasser(try Self.mission(entree["mission"]).mission, professionParcours: parcours))
            case "filtrerPaquetSwipe":
                let paquet = try XCTUnwrap(entree["paquet"]?.array).map { try Self.mission($0) }
                let filtres = FiltrePaquetSwipe.filtrer(paquet, filtre: try Self.filtre(entree["filtre"]),
                                                        professionParcours: parcours, mission: \.mission)
                return .array(filtres.map { .string($0.id) })
            default:
                return nil
            }
        }
        XCTAssertGreaterThan(rejoues, 500)
        for fonction in ["missionCorrespondProfessionInscription", "missionPasseFiltrePaquet", "filtrerPaquetSwipe"] {
            XCTAssertGreaterThan(parFonction[fonction] ?? 0, 0, "aucun vecteur golden pour \(fonction)")
        }
    }

    /// Carte décodée (`CarteSwipe.mission`) : ville, code postal et distance de l'enrichissement, planning de la mission.
    func testMissionPaquetDepuisUneMissionEnrichie() throws {
        let record = try JSONDecoder().decode(MissionRecord.self, from: Data("""
        {"id":"m1","intitule":"IDE nuit","profession_requise":"IDE","debut_le":"2026-11-04T20:00:00Z",
         "fin_le":"2026-11-05T05:00:00Z","taux_horaire_base":32,"est_urgente":true,"statut":"OUVERTE",
         "etablissement_id":"e1","type_contrat_recherche":"LIBERAL"}
        """.utf8))
        let etablissement = EtablissementSummary(id: "e1", nom: "Clinique", adresseVille: "Saint-Étienne", adresseCodePostal: "42000",
                                                 adresseLat: nil, adresseLng: nil, type: nil, logoUrl: nil)
        let mission = Mission(record: record, etablissement: etablissement, distanceKm: 12, creneauxPlanifies: [],
                              planningExact: true, erreurPlanning: false)
        let paquet = MissionPaquetSwipe(mission: mission)
        XCTAssertEqual(paquet.etablissementVille, "Saint-Étienne")
        XCTAssertEqual(paquet.etablissementCodePostal, "42000")
        XCTAssertEqual(paquet.distanceKm, 12)
        let filtre = FiltrePaquetSwipe(horaire: .nuit, ville: " étienne ", rayonKm: 20, tauxMin: 30)
        XCTAssertTrue(filtre.laissePasser(paquet, professionParcours: nil))
        var cdd = filtre
        cdd.typeContrat = "CDD"
        XCTAssertFalse(cdd.laissePasser(paquet, professionParcours: nil), "CDD écarte une mission LIBERAL")
    }
}
