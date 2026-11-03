import Foundation
import JoleneCore
import XCTest
@testable import JoleneSupabase

/// Les listes blanches Swift sont **égales** au champ `exceptions` de `ios-native/rpc-contracts.json`,
/// extrait du dump par `check-rpc-contracts.mjs` (lot 5 §2.5, D12) : une modification serveur d'un
/// message ou d'un SQLSTATE rougit d'abord le contrat (job « Cœur »), puis ce test tant que la constante
/// Swift n'est pas reprise.
final class ListesBlanchesEtablissementTests: XCTestCase {
    func testListesSwiftEgalesAuContratVersionne() throws {
        let contrats = try Depot.contrats()
        let avecExceptions = contrats.rpcs.filter { $0.exceptions != nil }
        XCTAssertEqual(Set(avecExceptions.map(\.name)), Set(ListesBlanchesEtablissement.parRPC.keys),
                       "une liste Swift par RPC du lot 5, aucune de plus")
        XCTAssertEqual(avecExceptions.count, 14)
        for contrat in avecExceptions {
            let attendues = (contrat.exceptions ?? []).map { [$0.sqlstate, $0.message] }
            let swift = (ListesBlanchesEtablissement.parRPC[contrat.name] ?? []).map { [$0.sqlstate, $0.message] }
            XCTAssertEqual(swift, attendues, "\(contrat.name) : liste blanche Swift ≠ rpc-contracts.json")
        }
    }

    func testTraitementsDesExceptions() throws {
        let contrats = try Depot.contrats()
        for contrat in contrats.rpcs {
            for (rang, exception) in (contrat.exceptions ?? []).enumerated() {
                let swift = try XCTUnwrap(ListesBlanchesEtablissement.parRPC[contrat.name]?[rang])
                // Le trigger RBAC (seul message formaté par l'argument du trigger) est toujours neutre.
                if exception.declencheur?.hasPrefix("trg_p0_rbac_") == true {
                    XCTAssertEqual(swift.traitement, .messageNeutre(RPCInterception.messageRoleInsuffisant), exception.message)
                } else if exception.sqlstate == "28000" {
                    XCTAssertEqual(swift.traitement, .session, "\(contrat.name) : 28000 → session")
                } else if exception.message.hasPrefix("Notification d'acceptation impossible") {
                    // Revue B8 de T0, mineur 5 : suite non garantie, détail interne possible.
                    XCTAssertEqual(swift.traitement, .generique)
                } else {
                    XCTAssertEqual(swift.traitement, .verbatim, "\(contrat.name) : « \(exception.message) »")
                }
            }
        }
    }

    func testRBACDesTablesEcritesCouvert() throws {
        // Revue B8 de T0, mineur 3 : triggers RBAC des tables écrites par l'acceptation et la clôture.
        let traiter = ListesBlanchesEtablissement.parRPC["fn_traiter_candidature_planning_v1"]?.map(\.message) ?? []
        for permission in ["missions", "contrats", "candidatures"] {
            XCTAssertTrue(traiter.contains("Permission etablissement \(permission) requise"), permission)
        }
        let fin = ListesBlanchesEtablissement.parRPC["fn_declarer_fin_retroactive"]?.map(\.message) ?? []
        XCTAssertTrue(fin.contains("Permission etablissement pointage requise"))
        XCTAssertTrue(fin.contains("Permission etablissement missions requise"))
    }

    func testInterceptionsConstruitesDepuisLesListes() {
        let traiter = ListesBlanchesEtablissement.interceptions(rpc: "fn_traiter_candidature_planning_v1")
        XCTAssertEqual(traiter, [
            .codeDuTravail,
            .accesRefuse(messagesExacts: ["Permission etablissement missions requise", "Permission etablissement contrats requise",
                                          "Permission etablissement candidatures requise"],
                         messageAffiche: RPCInterception.messageRoleInsuffisant),
            .refusMetier(sqlstate: "P0001", messagesExacts: ListesBlanchesEtablissement.paiementNonConfigure),
        ])
        XCTAssertEqual(ListesBlanchesEtablissement.paiementNonConfigure.count, 2)
        XCTAssertEqual(ListesBlanchesEtablissement.interceptions(rpc: "fn_obtenir_conversation"), [
            .codeDuTravail,
            .accesRefuse(messagesExacts: ["Conversation non autorisée"]),
            .refusMetier(sqlstate: "22023", messagesExacts: ["Interlocuteur invalide"]),
            .nonAuthentifie(sqlstate: "28000"),
        ])
        XCTAssertEqual(ListesBlanchesEtablissement.interceptions(rpc: "fn_mes_permissions_etab"), [.codeDuTravail])
        let validation = ListesBlanchesEtablissement.interceptions(rpc: "fn_valider_presence")
        XCTAssertEqual(validation.count, 4, "Code du travail, RBAC neutre, P0001, 23503")
    }

    func testRPCConsommeesParT1() throws {
        let contrats = try Depot.contrats()
        let statut = Dictionary(uniqueKeysWithValues: contrats.rpcs.map { ($0.name, $0.statut) })
        XCTAssertEqual(statut[SupabaseEtabSessionGateway.permissionsRPC], "consommee")
        XCTAssertEqual(statut[SupabaseEtabSessionGateway.profilRPC], "consommee")
    }
}
