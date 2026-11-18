import Foundation
import XCTest
@testable import JoleneCore

/// Règles pures de la candidature (lot 1, T6a) : action selon `mode_attribution`, preuves de relecture,
/// fenêtre et verrou d'une proposition, messages exacts d'une mission sortie de l'état OUVERTE.
final class CandidatureRulesTests: XCTestCase {
    private func record(mode: String?) -> MissionRecord {
        var record = MissionRecord(id: "m-1", intitule: "Mission", description: nil, service: nil, professionRequise: "IDE",
                                   specialiteMedicaleRequise: nil, accepteNonSpecialises: nil,
                                   debutLe: "2026-11-05T07:00:00Z", finLe: "2026-11-05T15:00:00Z", dureeHeures: 8,
                                   nbCreneaux: 1, tauxHoraireBase: 26, tauxRistPlafonne: nil, ristPlafondApplique: nil,
                                   totalBrut: nil, netAPayer: nil, estUrgente: false, niveauUrgence: 0, statut: "OUVERTE",
                                   etablissementId: "e-1", typeContratRecherche: "SALARIE", boosteeLe: nil,
                                   modeRemuneration: nil, retrocessionPct: nil)
        record.modeAttribution = mode
        return record
    }

    private func candidature(_ statut: String?, id: String = "c-1", missionId: String = "m-1",
                             creeLe: String? = "2026-11-01T23:30:00.000Z") -> CandidatureRecord {
        CandidatureRecord(id: id, missionId: missionId, statut: statut, message: nil, typeContratChoisi: nil, creeLe: creeLe)
    }

    func testModeCandidaturePostuleLesAutresAcceptent() {
        XCTAssertEqual(CandidatureRules.action(pour: record(mode: "CANDIDATURE")), .postuler)
        XCTAssertEqual(CandidatureRules.action(pour: record(mode: "PREMIER_ARRIVE")), .accepter)
        XCTAssertEqual(CandidatureRules.action(pour: record(mode: nil)), .accepter, "défaut serveur PREMIER_ARRIVE")
    }

    func testModeAttributionEtAttributionDecodeesDeLaLigneMissions() throws {
        let json = Data("""
        {"id":"m-1","intitule":"M","profession_requise":"IDE","debut_le":"2026-11-05T07:00:00Z","fin_le":"2026-11-05T15:00:00Z",
         "statut":"ASSIGNEE","etablissement_id":"e-1","mode_attribution":"CANDIDATURE",
         "presence_confirmee_le":"2026-11-04T10:00:00+00:00","soignant_assigne_id":"u-1"}
        """.utf8)
        let lue = try JSONDecoder().decode(MissionRecord.self, from: json)
        XCTAssertEqual(lue.modeAttribution, "CANDIDATURE")
        XCTAssertEqual(lue.presenceConfirmeeLe, "2026-11-04T10:00:00+00:00")
        XCTAssertEqual(lue.soignantAssigneId, "u-1")
        let sans = try JSONDecoder().decode(MissionRecord.self, from: Data("""
        {"id":"m-1","intitule":"M","profession_requise":"IDE","debut_le":"x","fin_le":"y","statut":"OUVERTE","etablissement_id":"e"}
        """.utf8))
        XCTAssertNil(sans.modeAttribution, "colonnes absentes tolérées")
        XCTAssertNil(sans.soignantAssigneId)
    }

    func testCandidaturePoseeRelueExigeLaMemeLigneEnAttente() {
        XCTAssertTrue(CandidatureRules.candidaturePoseeRelue(candidature("EN_ATTENTE"), id: "c-1", missionId: "m-1"))
        XCTAssertTrue(CandidatureRules.candidaturePoseeRelue(candidature("EN_ATTENTE_VALIDATION_ETAB"), id: "c-1", missionId: "m-1"))
        XCTAssertFalse(CandidatureRules.candidaturePoseeRelue(nil, id: "c-1", missionId: "m-1"), "rien relu : jamais un succès")
        XCTAssertFalse(CandidatureRules.candidaturePoseeRelue(candidature("EN_ATTENTE", id: "c-2"), id: "c-1", missionId: "m-1"))
        XCTAssertFalse(CandidatureRules.candidaturePoseeRelue(candidature("EN_ATTENTE", missionId: "m-2"), id: "c-1", missionId: "m-1"))
        XCTAssertFalse(CandidatureRules.candidaturePoseeRelue(candidature("ANNULEE"), id: "c-1", missionId: "m-1"))
        XCTAssertFalse(CandidatureRules.candidaturePoseeRelue(candidature(nil), id: "c-1", missionId: "m-1"))
    }

    func testAssignationRelueExigeAssigneeAuSoignantDeLaSession() {
        XCTAssertTrue(CandidatureRules.assignationRelue(statut: "ASSIGNEE", soignantAssigneId: "U-1", userId: "u-1"),
                      "uuid comparé sans la casse")
        XCTAssertFalse(CandidatureRules.assignationRelue(statut: "ASSIGNEE", soignantAssigneId: "u-2", userId: "u-1"))
        XCTAssertFalse(CandidatureRules.assignationRelue(statut: "OUVERTE", soignantAssigneId: "u-1", userId: "u-1"))
        XCTAssertFalse(CandidatureRules.assignationRelue(statut: "ASSIGNEE", soignantAssigneId: nil, userId: "u-1"))
        XCTAssertFalse(CandidatureRules.assignationRelue(statut: "ASSIGNEE", soignantAssigneId: "", userId: ""))
    }

    func testPropositionOuverteMoinsDeDeuxHeuresEtPROPOSEE() {
        let maintenant = Date(timeIntervalSince1970: 1_793_577_600) // 2026-11-02T00:00:00Z
        XCTAssertTrue(CandidatureRules.propositionOuverte(candidature("PROPOSEE"), maintenant: maintenant), "créée il y a 30 min")
        XCTAssertTrue(CandidatureRules.propositionOuverte(candidature("PROPOSEE", creeLe: "2026-11-01T22:00:00Z"), maintenant: maintenant),
                      "exactement 2 h : pas encore expirée (`cree_le < now() - 2 h`)")
        XCTAssertFalse(CandidatureRules.propositionOuverte(candidature("PROPOSEE", creeLe: "2026-11-01T21:59:59Z"), maintenant: maintenant))
        XCTAssertFalse(CandidatureRules.propositionOuverte(candidature("REFUSEE"), maintenant: maintenant))
        XCTAssertFalse(CandidatureRules.propositionOuverte(candidature("PROPOSEE", creeLe: "illisible"), maintenant: maintenant))
        XCTAssertFalse(CandidatureRules.propositionOuverte(candidature("PROPOSEE", creeLe: nil), maintenant: maintenant))
        XCTAssertFalse(CandidatureRules.propositionOuverte(nil, maintenant: maintenant))
    }

    func testRefusReluExigeREFUSEE() {
        XCTAssertTrue(CandidatureRules.refusRelu(candidature("REFUSEE"), id: "c-1"))
        XCTAssertFalse(CandidatureRules.refusRelu(candidature("PROPOSEE"), id: "c-1"))
        XCTAssertFalse(CandidatureRules.refusRelu(candidature("REFUSEE", id: "c-2"), id: "c-1"))
        XCTAssertFalse(CandidatureRules.refusRelu(nil, id: "c-1"))
    }

    func testMissionDejaAttribueeSurLesMessagesExactsDuServeur() {
        // Revue B8 de T6a, m1 : la vraie course (forme 3, variante sans point des délégués, attribution concurrente).
        XCTAssertTrue(CandidatureRules.estMissionDejaAttribuee("Cette mission n'est plus disponible."))
        XCTAssertTrue(CandidatureRules.estMissionDejaAttribuee("Cette mission n'est plus disponible"))
        XCTAssertTrue(CandidatureRules.estMissionDejaAttribuee("Cette mission vient d'être attribuée."))
        // L'ancienne branche « 0 rows » / « déjà prise » du web est morte (aucune fonction live) et faisait des faux positifs.
        XCTAssertFalse(CandidatureRules.estMissionDejaAttribuee("The result contains 0 rows"))
        XCTAssertFalse(CandidatureRules.estMissionDejaAttribuee("10 rows"))
        XCTAssertFalse(CandidatureRules.estMissionDejaAttribuee("Cette mission est déjà prise."))
        XCTAssertFalse(CandidatureRules.estMissionDejaAttribuee("Cette mission n'est plus disponible. Réessayez"), "égalité exacte")
    }

    func testIssueMissionDejaAttribueeDistincteDesRefus() {
        XCTAssertNotEqual(CandidatureOutcome.missionDejaAttribuee(message: "Cette mission vient d'être attribuée."),
                          CandidatureOutcome.refusee(code: nil, message: "Cette mission vient d'être attribuée.", documentsRequisPour: nil))
    }

    func testContratDeLaPropositionCommeLeWeb() {
        XCTAssertEqual(CandidatureRules.contratProposition(typeContratChoisi: "LIBERAL", typeContratRecherche: "TOUS"), "LIBERAL")
        XCTAssertEqual(CandidatureRules.contratProposition(typeContratChoisi: nil, typeContratRecherche: "SALARIE"), "SALARIE")
        XCTAssertEqual(CandidatureRules.contratProposition(typeContratChoisi: "", typeContratRecherche: "LIBERAL"), "LIBERAL")
        XCTAssertNil(CandidatureRules.contratProposition(typeContratChoisi: nil, typeContratRecherche: nil))
    }

    func testPropositionVerrouilleeHorsLiberal() {
        // Revue B8 de T6a, M1 : l'attestation hebdomadaire du web n'est pas portée ; seul LIBERAL reste natif.
        XCTAssertFalse(CandidatureRules.propositionVerrouillee(contrat: "LIBERAL"))
        for contrat in ["SALARIE", "TOUS", "liberal", "", nil] as [String?] {
            XCTAssertTrue(CandidatureRules.propositionVerrouillee(contrat: contrat), contrat ?? "nil")
        }
        XCTAssertEqual(CandidatureVerrou.cheminProposition, "/soignant/tableau-de-bord")
        XCTAssertTrue(CandidatureVerrou.messageRenvoiWeb.contains("LOT1_PLAN"), "le message cite la doc du gap")
        XCTAssertEqual(CandidatureVerrou.renvoiWeb(chemin: "/x").errorDescription, CandidatureVerrou.messageRenvoiWeb)
    }

    func testActionHorsLot1CiteSaDocEtSonLot() {
        let erreur = CandidatureRules.actionHorsLot1(.postuler)
        XCTAssertEqual(erreur.kind, .contract)
        XCTAssertTrue(erreur.message.contains("LOT1_PLAN") && erreur.message.contains("§1.2"), erreur.message)
        XCTAssertTrue(erreur.message.contains("lot 4"), erreur.message)
    }
}
