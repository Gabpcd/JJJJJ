import XCTest
@testable import JoleneCore

/// Nullabilité réelle du schéma (`supabase/schema/public.sql`, `types.ts`) : `missions.est_urgente`,
/// `missions.statut`, `soignants.profession` et `soignants.tous_documents_valides` sont NULLables.
/// Une ligne à NULL ne doit jamais faire échouer tout le décodage d'une page PostgREST.
final class ModelsDecodingTests: XCTestCase {
    private func missionJSON(estUrgente: String, statut: String) -> Data {
        Data("""
        {"id":"m-null","intitule":"Mission","description":null,"service":null,"profession_requise":"IDE",
         "specialite_medicale_requise":null,"accepte_non_specialises":null,"debut_le":"2026-12-01T19:00:00+00:00",
         "fin_le":"2026-12-02T07:00:00+00:00","duree_heures":null,"nb_creneaux":1,"taux_horaire_base":null,
         "taux_rist_plafonne":null,"rist_plafond_applique":null,"total_brut":null,"net_a_payer":null,
         "est_urgente":\(estUrgente),"niveau_urgence":null,"statut":\(statut),"etablissement_id":"etab-1",
         "type_contrat_recherche":null,"boostee_le":null,"mode_remuneration":null,"retrocession_pct":null}
        """.utf8)
    }

    func testMissionRecordToleratesNullEstUrgenteAndStatut() throws {
        let record = try JSONDecoder().decode(MissionRecord.self, from: missionJSON(estUrgente: "null", statut: "null"))
        XCTAssertFalse(record.estUrgente, "NULL vaut false, comme `!mission.est_urgente` côté pilote")
        XCTAssertEqual(record.statut, "", "NULL n'est jamais confondu avec OUVERTE")
        let urgent = try JSONDecoder().decode(MissionRecord.self, from: missionJSON(estUrgente: "true", statut: "\"OUVERTE\""))
        XCTAssertTrue(urgent.estUrgente)
        XCTAssertEqual(urgent.statut, "OUVERTE")
    }

    func testMissionRecordStillRequiresNotNullColumns() {
        let sansId = Data(#"{"intitule":"x","profession_requise":"IDE","debut_le":"a","fin_le":"b","etablissement_id":"e"}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(MissionRecord.self, from: sansId))
    }

    func testMissionRecordRoundTripsThroughEncoder() throws {
        let record = try JSONDecoder().decode(MissionRecord.self, from: missionJSON(estUrgente: "false", statut: "\"OUVERTE\""))
        let again = try JSONDecoder().decode(MissionRecord.self, from: JSONEncoder().encode(record))
        XCTAssertEqual(again, record)
    }

    func testSoignantProfileToleratesNullProfessionAndDocuments() throws {
        let json = Data("""
        {"id":"u-1","profession":null,"adresse_lat":null,"adresse_lng":null,"rayon_deplacement_km":null,
         "tous_documents_valides":null,"type_contrat":null,"types_contrat_acceptes":null,"type_exercice":null,"taux_horaire_minimum":null}
        """.utf8)
        let profile = try JSONDecoder().decode(SoignantProfile.self, from: json)
        XCTAssertEqual(profile.profession, "", "profession NULL = inscription non terminée (profil renvoyé nil par le gateway)")
        XCTAssertFalse(profile.tousDocumentsValides)
        XCTAssertThrowsError(try MissionBusiness.validateContext(MissionReadContext(userId: "u-1", email: nil, profile: profile)),
                             "un profil sans profession ne lit jamais les missions")
    }
}
