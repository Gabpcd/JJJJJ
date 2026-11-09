import XCTest
@testable import JoleneCore

/// Monde démo de l'onglet Revenus (lot 3, T12 ; blueprint §2.7) : fixtures `demo-revenus.json`, `demo-escrow.json` et
/// `demo-missions-terminees.json` exportées par `scripts/mobile/export-demo-fixtures.mjs` (horloge fixée), lues par les
/// MÊMES décodeurs que le monde Supabase (`TotauxRevenus.lire`, `PaiementRapide.lireListe`, `MissionTerminee`,
/// `PaiementSoignantLu`, `RevenusAssemblage`). Aucun réseau ; tout autre compte que le profil fictif est refusé.
final class DemoRevenusGatewayTests: XCTestCase {
    private let context = DemoWorld.context

    func testFixturesALHorlogeDuMondeDemo() throws {
        let iso = DateHeureParis.isoUTC(DemoWorld.fixedNow)
        XCTAssertEqual(try DemoFixtures.loadRevenus().fixedNow, iso)
        XCTAssertEqual(try DemoFixtures.loadEscrow().fixedNow, iso)
        XCTAssertEqual(try DemoFixtures.loadMissionsTerminees().fixedNow, iso)
    }

    func testTotauxDuProfilMixte() async throws {
        let totaux = try await DemoRevenusGateway().totaux(context: context)
        XCTAssertEqual(totaux, TotauxRevenus(moisEnCours: 195, total: 1425.6, enAttente: 780, stripeConnectActif: true))
    }

    func testLesSeptEtatsDuPaiementRapideDansLOrdreServeur() async throws {
        let lignes = try await DemoRevenusGateway().paiementsRapides(context: context)
        XCTAssertEqual(lignes.map(\.etat), ["RETARDE", "LITIGE", "ATTENTE_VALIDATION", "VERSEMENT_EN_COURS", "RESERVE", "VERSE", "ANNULE"])
        XCTAssertEqual(Set(lignes.map(\.etat)), Set(EtatEscrow.allCases.map(\.rawValue)))
        let litige = try XCTUnwrap(lignes.first { $0.etat == "LITIGE" })
        XCTAssertEqual(litige.missionId, "demo-assignee-002", "le litige ouvre une mission démo réelle (détail natif)")
        let affiche = RevenusPresentation.escrow(lignes)
        XCTAssertEqual(affiche.aVenir.count, 5)
        XCTAssertEqual(affiche.verses.map(\.libelle), ["Versé le 30/10"])
        XCTAssertEqual(affiche.annules.count, 1)
    }

    func testMissionsTermineesAvecTemoinsDesQuatreCas() async throws {
        let page = try await DemoRevenusGateway().missionsTerminees(context: context, page: 0)
        XCTAssertEqual(page.page, 0)
        XCTAssertFalse(page.aSuivre)
        XCTAssertEqual(page.missions.map(\.id), ["demo-terminee-001", "demo-terminee-002", "demo-terminee-003",
                                                 "demo-terminee-004", "demo-terminee-005"], "debut_le décroissant, comme le web")
        let lignes = Dictionary(uniqueKeysWithValues: page.missions.map { ($0.id, RevenusPresentation.mission($0)) })
        // Salariée, déclaration à confirmer (montants égaux à la carte des gains de l'Accueil démo).
        XCTAssertEqual(lignes["demo-terminee-001"]?.montant, "162,40\u{00A0}€")
        XCTAssertEqual(lignes["demo-terminee-001"]?.etat.texte, "Réception à confirmer")
        XCTAssertEqual(lignes["demo-terminee-001"]?.sousTitre, "🏥 Établissement fictif République · Médecine polyvalente")
        // Libérale : honoraires, état renvoyé aux factures.
        XCTAssertEqual(lignes["demo-terminee-002"]?.montant, "256,00\u{00A0}€")
        XCTAssertEqual(lignes["demo-terminee-002"]?.etat.texte, "Paiement suivi dans Factures")
        // Contrat non choisi : brut indicatif.
        XCTAssertEqual(lignes["demo-terminee-003"]?.nature, "Rémunération brute indicative")
        XCTAssertEqual(lignes["demo-terminee-003"]?.etat.texte, "Régime à vérifier")
        // Salariée : la confirmation la plus récente l'emporte sur une ancienne contestation.
        XCTAssertEqual(lignes["demo-terminee-004"]?.etat, EtatLigneRevenus(texte: "Réception confirmée", ton: .succes))
        // Témoin D5 : colonnes Rist présentes dans la fixture, jamais lues ; montant stocké affiché (280, jamais 320).
        XCTAssertEqual(lignes["demo-terminee-005"]?.montant, "280,00\u{00A0}€")
    }

    func testPagesSuivantesVidesEtPageNegativeRefusee() async throws {
        let suivante = try await DemoRevenusGateway().missionsTerminees(context: context, page: 1)
        XCTAssertTrue(suivante.missions.isEmpty)
        XCTAssertFalse(suivante.aSuivre)
        do {
            _ = try await DemoRevenusGateway().missionsTerminees(context: context, page: -1)
            XCTFail("page négative acceptée")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur.kind, .contract)
        }
    }

    func testAutreCompteRefuseDemoSeulement() async {
        let autre = MissionReadContext(userId: "u-reel", email: nil, profile: SoignantProfile(id: "u-reel", profession: "IDE"))
        let gateway = DemoRevenusGateway()
        for appel in [
            { _ = try await gateway.totaux(context: autre) },
            { _ = try await gateway.paiementsRapides(context: autre) },
            { _ = try await gateway.missionsTerminees(context: autre, page: 0) },
        ] as [() async throws -> Void] {
            do {
                try await appel()
                XCTFail("un compte réel ne doit jamais lire la démo")
            } catch let erreur as JoleneError {
                XCTAssertEqual(erreur.kind, .demoOnly)
            } catch {
                XCTFail("erreur inattendue \(error)")
            }
        }
    }

    /// Variante de recette `JOLENE_FORCE_REVENUS_ECHEC=1` (`DemoRevenusTests.testErreurPuisReprise`) : la première lecture
    /// des missions échoue, la suivante réussit ; les autres sections sont inchangées.
    func testVarianteEchecPremiereLectureDesMissions() async throws {
        let gateway = DemoRevenusEchecGateway()
        do {
            _ = try await gateway.missionsTerminees(context: context, page: 0)
            XCTFail("premier chargement attendu en échec")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur.kind, .network)
        }
        let page = try await gateway.missionsTerminees(context: context, page: 0)
        XCTAssertEqual(page.missions.count, 5)
        let totaux = try await gateway.totaux(context: context)
        XCTAssertNotNil(totaux)
        XCTAssertEqual(try await gateway.paiementsRapides(context: context).count, 7)
    }

    func testMondeDemoCableLesRevenus() {
        XCTAssertTrue(DemoWorld.gateways().revenus is DemoRevenusGateway, "lot 3, T12 câble les revenus en démo")
        XCTAssertEqual(DemoRevenusEchecGateway.variableEnvironnement, "JOLENE_FORCE_REVENUS_ECHEC")
    }
}
