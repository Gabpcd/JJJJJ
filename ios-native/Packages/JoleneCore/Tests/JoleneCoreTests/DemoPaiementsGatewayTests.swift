import XCTest
@testable import JoleneCore

/// Monde démo des paiements déclarés (lot 3, T13 ; blueprint §2.7 : `demo-paiements-declares.json`, deux `DECLARE`,
/// acteur) : mêmes décodeurs, même assemblage et même règle de relecture que le monde Supabase ; refus verbatim du
/// serveur dans leur ordre ; l'onglet (`DemoRevenusGateway`) relit l'état des déclarations du serveur simulé. Aucun
/// réseau ; tout autre compte que le profil fictif est refusé.
final class DemoPaiementsGatewayTests: XCTestCase {
    private let context = DemoWorld.context

    func testFixtureALHorlogeDuMondeDemoEtDeclarationsDeLOnglet() throws {
        let fichier = try DemoFixtures.loadPaiementsDeclares()
        XCTAssertEqual(fichier.fixedNow, DateHeureParis.isoUTC(DemoWorld.fixedNow))
        let onglet = try DemoFixtures.loadMissionsTerminees().paiements.filter { $0.statut == "DECLARE" }
        XCTAssertEqual(fichier.paiements.map(\.id), onglet.map(\.id), "mêmes déclarations que l'onglet Revenus")
        XCTAssertEqual(fichier.paiements.map(\.id), ["demo-paiement-001", "demo-paiement-004"])
    }

    func testDeuxPaiementsAConfirmerAvecLeurDetail() async throws {
        let lignes = try await DemoPaiementsGateway().aConfirmer(context: context)
        XCTAssertEqual(lignes.map(\.id), ["demo-paiement-001", "demo-paiement-004"])
        let cartes = lignes.map(PaiementsDeclaresPresentation.carte)
        let nbsp = "\u{00A0}"
        XCTAssertEqual(cartes[0].titre, "💰 Établissement fictif République déclare vous avoir payé 162,40\(nbsp)€")
        XCTAssertEqual(cartes[0].mission, "Mission : Démonstration · Mission terminée 1")
        XCTAssertEqual(cartes[0].pointages?.titre, "Pointages enregistrés · 2 segments")
        XCTAssertEqual(cartes[0].pointages?.lignes, ["Segment 1 · 1 nov. · 08h05 → 12h00 · 3h55", "Pause précédente : 0h30",
                                                    "Segment 2 · 1 nov. · 12h30 → 16h00 · 3h30"])
        XCTAssertEqual(cartes[1].titre, "💰 Cabinet fictif du Parc déclare vous avoir payé 256,00\(nbsp)€")
        XCTAssertEqual(cartes[1].infos.map { "\($0.libelle) \($0.valeur)" },
                       ["Méthode : 🏦 Virement", "Date : 31 oct. 2026", "Référence : VIR-DEMO-0002"])
        XCTAssertEqual(cartes[1].pointages?.lignes, ["20 oct. · Arrivée : 09h00 · Départ : 17h00 · (🔢 Code)"])
        XCTAssertEqual(cartes[1].blocMission?.taux, "Taux retenu : 32,00\(nbsp)€/h")
    }

    func testConfirmerRelitCONFIRMEEtLOngletSuit() async throws {
        let paiements = DemoPaiementsGateway()
        let revenus = DemoRevenusGateway(paiementsDeclares: paiements)
        let issue = try await paiements.confirmer(id: "demo-paiement-001", context: context)
        guard case let .confirme(relue) = issue else { return XCTFail("confirmation attendue, obtenu \(issue)") }
        XCTAssertEqual(relue.statut, "CONFIRME")
        XCTAssertTrue(relue.confirmeParSoignant)
        let restants = try await paiements.aConfirmer(context: context)
        XCTAssertEqual(restants.map(\.id), ["demo-paiement-004"])
        let page = try await revenus.missionsTerminees(context: context, page: 0)
        let ligne = try XCTUnwrap(page.missions.first { $0.id == "demo-terminee-001" })
        XCTAssertEqual(RevenusPresentation.etat(ligne).texte, "Réception confirmée", "état de la mission relu")
        let refus = try await paiements.confirmer(id: "demo-paiement-001", context: context)
        XCTAssertEqual(refus, .refuse(message: "Paiement déjà confirmé"), "second appel : refus du serveur verbatim")
        let contestation = try await paiements.contester(id: "demo-paiement-001", motif: "Montant erroné", context: context)
        XCTAssertEqual(contestation, .refuse(message: "Paiement déjà confirmé"))
    }

    func testContesterMotifObligatoireRelectureEtIdempotence() async throws {
        let paiements = DemoPaiementsGateway()
        for blanc in ["", "   "] {
            let refus = try await paiements.contester(id: "demo-paiement-001", motif: blanc, context: context)
            XCTAssertEqual(refus, .refuse(message: "Motif requis"))
        }
        let long = try await paiements.contester(id: "demo-paiement-001", motif: String(repeating: "x", count: 501), context: context)
        XCTAssertEqual(long, .refuse(message: "Motif trop long (500 caractères maximum)"))
        let issue = try await paiements.contester(id: "demo-paiement-001", motif: " Montant erroné ", context: context)
        guard case let .conteste(relue, litige) = issue else { return XCTFail("contestation attendue, obtenu \(issue)") }
        XCTAssertEqual(relue.statut, "CONTESTE")
        XCTAssertTrue(relue.conteste)
        XCTAssertEqual(litige, "demo-litige-1")
        let encore = try await paiements.contester(id: "demo-paiement-001", motif: "Encore", context: context)
        XCTAssertEqual(encore, .refuse(message: "Paiement déjà contesté"), "idempotence : jamais un second litige")
        let introuvable = try await paiements.confirmer(id: "inconnu", context: context)
        XCTAssertEqual(introuvable, .refuse(message: "Paiement introuvable"))
    }

    /// Variante de recette `JOLENE_DEMO_PAIEMENTS=refus` (`DemoPaiementsTests`) : confirmé ailleurs, litige déjà ouvert.
    func testScenarioRefus() async throws {
        let paiements = DemoPaiementsGateway(scenario: .refus)
        let confirmation = try await paiements.confirmer(id: "demo-paiement-001", context: context)
        XCTAssertEqual(confirmation, .refuse(message: "Paiement déjà confirmé"))
        let apresConfirmation = try await paiements.aConfirmer(context: context)
        XCTAssertEqual(apresConfirmation.map(\.id), ["demo-paiement-004"], "confirmé ailleurs : la relecture ne le rend plus")
        let contestation = try await paiements.contester(id: "demo-paiement-004", motif: "Montant erroné", context: context)
        XCTAssertEqual(contestation, .refuse(message: "Un litige de ce type est déjà ouvert pour cette mission."))
        let apresContestation = try await paiements.aConfirmer(context: context)
        XCTAssertEqual(apresContestation.map(\.id), ["demo-paiement-004"], "aucune écriture")
        XCTAssertEqual(DemoPaiementsGateway.Scenario(rawValue: "refus"), .refus)
        XCTAssertEqual(DemoPaiementsGateway.variableEnvironnement, "JOLENE_DEMO_PAIEMENTS")
    }

    func testAutreCompteRefuseDemoSeulement() async {
        let autre = MissionReadContext(userId: "u-reel", email: nil, profile: SoignantProfile(id: "u-reel", profession: "IDE"))
        let gateway = DemoPaiementsGateway()
        for appel in [
            { _ = try await gateway.aConfirmer(context: autre) },
            { _ = try await gateway.confirmer(id: "demo-paiement-001", context: autre) },
            { _ = try await gateway.contester(id: "demo-paiement-001", motif: "x", context: autre) },
        ] as [() async throws -> Void] {
            do {
                try await appel()
                XCTFail("un compte réel ne doit jamais lire ni écrire la démo")
            } catch let erreur as JoleneError {
                XCTAssertEqual(erreur.kind, .demoOnly)
            } catch {
                XCTFail("erreur inattendue \(error)")
            }
        }
    }

    func testMondeDemoCableLesPaiementsDeclaresEtLOngletSurLeMemeServeur() async throws {
        let gateways = DemoWorld.gateways()
        let paiements = try XCTUnwrap(gateways.paiements as? DemoPaiementsGateway, "lot 3, T13 câble les paiements en démo")
        _ = try await paiements.confirmer(id: "demo-paiement-001", context: context)
        let page = try await gateways.revenus.missionsTerminees(context: context, page: 0)
        let ligne = try XCTUnwrap(page.missions.first { $0.id == "demo-terminee-001" })
        XCTAssertEqual(RevenusPresentation.etat(ligne).texte, "Réception confirmée", "un seul serveur simulé par monde")
    }
}
