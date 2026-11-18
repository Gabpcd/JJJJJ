import Foundation
import JoleneCore
import Supabase
import XCTest
@testable import JoleneSupabase

/// Justificatif d'annulation sur Supabase (lot 1, T7) : dépôt `justificatifs/<uid>/annulations-candidature/<id>/<ms>_<nom>`
/// sans écrasement, refus 4xx = rien n'est déposé (403 → `not_sent` côté reçu), 409 et réponse perdue = incertain
/// (réconcilié par HEAD), hôte injoignable = jamais parti, jeton refusé = session expirée, chemin d'un autre utilisateur
/// refusé avant tout appel.
final class SupabaseJustificatifStorageTests: XCTestCase {
    private let registry = StubRegistry.shared
    private let candidature = "1a2b3c4d-5e6f-4a7b-8c9d-0e1f2a3b4c5d"
    private var chemin: String { "\(TestClient.userId)/annulations-candidature/\(candidature)/1793577600000_billet.pdf" }
    private var objet: String { "/storage/v1/object/justificatifs/\(chemin)" }
    private let pdf = Data("%PDF-1.4 billet".utf8)

    override func setUp() {
        super.setUp()
        registry.reset()
    }

    private func stockage() -> SupabaseJustificatifStorage { SupabaseJustificatifStorage(client: TestClient.make()) }

    private func deposer() async throws -> IssueDepotJustificatif {
        try await stockage().deposer(chemin: chemin, octets: pdf, mime: .pdf, context: TestClient.context)
    }

    func testDepotBucketCheminContentTypeEtSansEcrasement() async throws {
        registry.add("POST", objet, respond: .json(200, #"{"Key":"justificatifs/\#(chemin)","Id":"obj-1"}"#))
        let issue = try await deposer()
        XCTAssertEqual(issue, .depose)
        let requete = try XCTUnwrap(registry.requests(to: objet).first)
        XCTAssertEqual(requete.method, "POST")
        XCTAssertEqual(requete.header("x-upsert"), "false", "`upsert: false` du web (l.86)")
        let corps = try XCTUnwrap(requete.body)
        XCTAssertTrue(String(decoding: corps, as: UTF8.self).contains("Content-Type: application/pdf"))
        XCTAssertEqual(registry.requests.count, 1, "un seul dépôt")
    }

    func testRefus4xxRienNestDepose() async throws {
        for statut in [403, 400, 413] {
            registry.reset()
            registry.add("POST", objet, respond: .json(statut, #"{"statusCode":"\#(statut)","error":"Unauthorized","message":"new row violates row-level security policy"}"#))
            let issue = try await deposer()
            XCTAssertEqual(issue, .refuse(statut: statut), "\(statut)")
        }
    }

    func testDejaPresentOuReponsePerdueIncertain() async throws {
        registry.add("POST", objet, respond: .json(409, #"{"statusCode":"409","error":"Duplicate","message":"The resource already exists"}"#))
        let doublon = try await deposer()
        XCTAssertEqual(doublon, .incertain, "409 : seul cet essai écrit sous ce chemin, réconciliation par HEAD")
        registry.reset()
        registry.add("POST", objet, respond: .json(502, "Bad Gateway"))
        let passerelle = try await deposer()
        XCTAssertEqual(passerelle, .incertain)
        registry.reset()
        registry.add("POST", objet, respond: .networkFailure(.timedOut))
        let delai = try await deposer()
        XCTAssertEqual(delai, .incertain)
    }

    func testHoteInjoignableJamaisParti() async throws {
        registry.add("POST", objet, respond: .networkFailure(.cannotConnectToHost))
        let issue = try await deposer()
        XCTAssertEqual(issue, .nonEnvoye)
    }

    func testJetonRefuseSessionExpiree() async throws {
        registry.add("POST", objet, respond: .json(400, #"{"statusCode":"400","error":"InvalidJWT","message":"\"exp\" claim timestamp check failed"}"#))
        do {
            _ = try await deposer()
            XCTFail("jeton refusé accepté")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur.kind, .unauthorized)
        }
    }

    func testPresenceRelueParHEAD() async throws {
        registry.add("HEAD", objet, respond: .json(200, ""))
        let present = try await stockage().existe(chemin: chemin, context: TestClient.context)
        XCTAssertTrue(present)
        registry.reset()
        registry.add("HEAD", objet, respond: .json(404, ""))
        let absent = try await stockage().existe(chemin: chemin, context: TestClient.context)
        XCTAssertFalse(absent)
        XCTAssertEqual(registry.requests.map(\.method), ["HEAD"], "aucun dépôt pendant la réconciliation")
    }

    func testCheminDUnAutreUtilisateurRefuseSansAppel() async throws {
        for invalide in ["autre/annulations-candidature/\(candidature)/1_a.pdf",
                         "\(TestClient.userId)/documents/\(candidature)/1_a.pdf",
                         "\(TestClient.userId)/annulations-candidature/../1_a.pdf"] {
            do {
                _ = try await stockage().deposer(chemin: invalide, octets: pdf, mime: .pdf, context: TestClient.context)
                XCTFail("\(invalide) accepté")
            } catch let erreur as JoleneError {
                XCTAssertEqual(erreur.kind, .contract)
            }
        }
        XCTAssertTrue(registry.requests.isEmpty)
    }
}
