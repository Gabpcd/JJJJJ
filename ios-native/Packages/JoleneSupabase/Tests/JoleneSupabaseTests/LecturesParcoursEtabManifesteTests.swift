import Foundation
import JoleneCore
import Supabase
import XCTest
@testable import JoleneSupabase

/// Manifeste des lectures du parcours STAGING du lot 5 (`scripts/mobile/staging-lot5-lectures.json`), produit depuis
/// les constantes réelles des passerelles : le pré-vol de `staging-lot5-fixture.mjs` rejoue ces lectures sous le JWT
/// d'E1 avec la clé de l'app, avant le XCUITest (quatrième parcours STAGING, 26/11/2026). Un `select`, une table, un
/// filtre ou une fonction qui change dans le Swift sans le manifeste fait échouer ce test : régénérer avec
/// `JOLENE_ECRIRE_MANIFESTE_LECTURES=1 swift test --filter LecturesParcoursEtabManifesteTests` et versionner le résultat.
/// Seulement des lectures : aucune écriture (acceptation, notation, validation) n'y figure. Jetons de place : `{E1}`,
/// `{S1}`, `{M1}`, `{M2}`, `{CANDIDATURE}`, `{CONTRAT}`.
///
/// Ce que ce test garantit (revue de #1196, M1) : les `select` des passerelles (`missionSelect`, `slotSelect`,
/// `ContratResume.selection`…), les noms de fonctions, les tables des contrats et les tailles de page viennent des
/// constantes du Swift ; s'ils changent, le test échoue. Ce qu'il ne garantit pas : les autres tables, les filtres, les
/// ordres et les `select` courts (`statut`, `mission_id`, `id`) sont écrits en dur dans les passerelles comme ici, et
/// recopiés : une passerelle qui change de filtre ne fait pas échouer ce test. Le téléchargement du PDF du contrat
/// (Storage) n'est pas une lecture PostgREST et n'y figure pas.
final class LecturesParcoursEtabManifesteTests: XCTestCase {
    static let chemin = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("scripts/mobile/staging-lot5-lectures.json")

    private static func table(_ nom: String, _ table: String, _ select: String, _ filtres: [[String]],
                              order: String? = nil, limit: Int? = nil) -> [String: Any] {
        var l: [String: Any] = ["nom": nom, "table": table, "select": select, "filtres": filtres]
        if let order { l["order"] = order }
        if let limit { l["limit"] = limit }
        return l
    }

    private static func rpc(_ nom: String, _ fonction: String, _ params: [String: String]) -> [String: Any] {
        ["nom": nom, "fonction": fonction, "params": params]
    }

    static var manifeste: [String: Any] {
        let e1 = ["etablissement_id", "eq.{E1}"]
        let lectures: [[String: Any]] = [
            // Missions : liste (filtre Toutes puis Assignées), compteurs, créneaux, candidatures en attente, détail.
            table("missions — liste", "missions", SupabaseEtabMissionsGateway.missionSelect, [e1],
                  order: "debut_le.desc,id.asc", limit: EtabMissionsPage.taille),
            table("missions — liste Assignées", "missions", SupabaseEtabMissionsGateway.missionSelect, [e1, ["statut", "eq.ASSIGNEE"]],
                  order: "debut_le.desc,id.asc", limit: EtabMissionsPage.taille),
            table("missions — compteurs", "missions", "statut", [e1], order: "id.asc", limit: SupabaseEtabMissionsGateway.pageStatuts),
            table("missions — créneaux", "mission_creneaux", MissionQuery.slotSelect,
                  [["mission_id", "in.({M1},{M2})"], ["type_creneau", "eq.\(MissionQuery.forecastSlotType)"], ["est_pause", "eq.false"]],
                  order: "mission_id.asc,debut.asc,id.asc", limit: MissionQuery.slotPageSize),
            table("missions — candidatures en attente", "candidatures", "mission_id",
                  [["mission_id", "in.({M1})"], ["statut", "eq.EN_ATTENTE"]]),
            table("mission — détail", "missions", SupabaseEtabMissionsGateway.missionSelect, [["id", "eq.{M2}"], e1]),
            rpc("mission — soignant assigné", SupabaseEtabMissionsGateway.soignantRPC, ["p_soignant_id": "{S1}"]),
            table("mission — candidatures en attente (compte)", "candidatures", "id",
                  [["mission_id", "eq.{M1}"], ["statut", "eq.EN_ATTENTE"]]),
            // Candidatures de M1 : lecture habilitée et périmètre relu avant l'acceptation.
            rpc("candidatures — lecture habilitée", SupabaseEtabCandidaturesGateway.lectureRPC, ["p_mission_id": "{M1}"]),
            table("candidature — relecture", "candidatures", "id,mission_id", [["id", "eq.{CANDIDATURE}"]]),
            table("candidature — périmètre de la mission", "missions", SupabaseEtabCandidaturesGateway.missionPerimetreSelect,
                  [["id", "eq.{M1}"], e1]),
            // Contrat de M2 : liste, détail, certificat.
            table("contrats — liste", SupabaseContratsGateway.table, ContratResume.selection, [e1], order: "cree_le.desc.nullsfirst"),
            table("contrat — détail", SupabaseContratsGateway.table, ContratDetail.selection, [["id", "eq.{CONTRAT}"], e1]),
            table("contrat — certificat", SupabaseContratsGateway.tableSignatures, SignatureCertificat.selection,
                  [["contrat_id", "eq.{CONTRAT}"]], order: "cree_le.asc"),
            // Code de pointage de M2.
            table("pointage — mission", "missions", SupabaseEtabPointageGateway.missionSelect, [["id", "eq.{M2}"], e1]),
            rpc("pointage — état", SupabaseEtabPointageGateway.etatRPC, ["p_mission_id": "{M2}"]),
            rpc("pointage — contrat signé", SupabaseEtabPointageGateway.contratRPC, ["p_mission_id": "{M2}"]),
            // Présences (phase 2) : liste de l'établissement. La notation est une écriture : jamais rejouée.
            table("présences — liste", "presences", SupabaseEtabPresencesGateway.presenceSelect,
                  [["missions.etablissement_id", "eq.{E1}"], ["pointage_arrivee_le", "not.is.null"]],
                  order: "pointage_arrivee_le.desc"),
            table("présences — missions terminées", "missions", SupabaseEtabPresencesGateway.termineesSelect,
                  [e1, ["type_contrat_applique", "eq.SALARIE"], ["statut", "eq.TERMINEE"], ["soignant_assigne_id", "not.is.null"]],
                  order: "fin_le.desc"),
            table("présences — créneaux", "mission_creneaux", MissionQuery.slotSelect,
                  [["mission_id", "in.({M2})"], ["est_pause", "eq.false"]],
                  order: "mission_id.asc,debut.asc,id.asc", limit: MissionQuery.slotPageSize),
        ]
        return ["purpose": "lot5-lectures-parcours-etab-v1", "lectures": lectures]
    }

    static func json() throws -> String {
        let donnees = try JSONSerialization.data(withJSONObject: manifeste, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return String(decoding: donnees, as: UTF8.self) + "\n"
    }

    func testManifesteDesLecturesDuParcoursAJour() throws {
        let attendu = try Self.json()
        if ProcessInfo.processInfo.environment["JOLENE_ECRIRE_MANIFESTE_LECTURES"] == "1" {
            try attendu.write(to: Self.chemin, atomically: true, encoding: .utf8)
        }
        let versionne = try String(contentsOf: Self.chemin, encoding: .utf8)
        XCTAssertEqual(versionne, attendu, "manifeste des lectures du parcours à régénérer (JOLENE_ECRIRE_MANIFESTE_LECTURES=1)")
    }
}

/// Quatrième parcours STAGING : le dernier échec serveur est noté sans secret pour le diagnostic DEBUG des écrans.
final class DiagnosticDernierEchecTests: XCTestCase {
    func testDernierEchecNoteSansSecret() {
        let journal = DiagnosticDernierEchec()
        let uuid = "3f2b9c1e-8a4d-4c2e-9b7a-1d2e3f4a5b6c"
        SupabaseErrorMapping.noterDernierEchec(PostgrestError(code: "42703", message: "column missions.x does not exist (\(uuid))"),
                                               dans: journal)
        XCTAssertEqual(journal.valeur, "postgrest=42703;message=column missions.x does not exist (<uuid>)")
        // Une erreur déjà traduite ou une annulation ne remplace pas l'échec d'origine.
        SupabaseErrorMapping.noterDernierEchec(JoleneError(.unknown, "Réessayez."), dans: journal)
        SupabaseErrorMapping.noterDernierEchec(CancellationError(), dans: journal)
        XCTAssertEqual(journal.valeur, "postgrest=42703;message=column missions.x does not exist (<uuid>)")
        SupabaseErrorMapping.noterDernierEchec(URLError(.timedOut), dans: journal)
        XCTAssertEqual(journal.valeur, "reseau=\(URLError.Code.timedOut.rawValue)")
        journal.effacer()
        XCTAssertNil(journal.valeur)
    }
}
