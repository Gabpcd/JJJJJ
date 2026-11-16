import XCTest
@testable import JoleneCore

/// Extension additive de `Gateways` (blueprint lot 1 §2.2, PRINCIPES §2) : l'init du lot 0
/// compile inchangé et laisse chaque port du lot 1 « non câblé » ; un port non câblé refuse
/// explicitement (`.contract`, tranche citée) au lieu de rendre un état vide ; `unwiredPorts`
/// nomme les ports encore stubs pour que chaque monde (démo, Supabase) prouve son câblage.
final class Lot1PortsTests: XCTestCase {
    /// Champs ajoutés au lot 1, dans l'ordre de déclaration de `Gateways`.
    static let portsLot1 = ["dashboard", "candidature", "presence", "favoris", "mesMissions",
                            "compte", "audit", "flags", "recovery", "justificatifs"]

    private let contexte = DemoWorld.context

    func testInitDuLot0LaisseTousLesPortsDuLot1NonCables() {
        let gateways = Gateways(auth: NeutralAuth(), role: NeutralRole(), missions: NeutralMissions())
        // Lots 2 et 3 (T1) : le bloc « Lot 2 » (`Lot2PortsTests`), puis le bloc « Lot 3 » (`Lot3PortsTests`), suivent le
        // lot 1 dans `unwiredPorts`.
        XCTAssertEqual(gateways.unwiredPorts, Self.portsLot1 + Lot2PortsTests.portsLot2 + Lot3PortsTests.portsLot3)
        XCTAssertTrue(gateways.dashboard is UnwiredDashboardPort)
        XCTAssertTrue(gateways.candidature is UnwiredCandidaturePort)
        XCTAssertTrue(gateways.presence is UnwiredPresencePort)
        XCTAssertTrue(gateways.favoris is UnwiredFavorisPort)
        XCTAssertTrue(gateways.mesMissions is UnwiredMesMissionsPort)
        XCTAssertTrue(gateways.compte is UnwiredAccountPort)
        XCTAssertTrue(gateways.audit is UnwiredAuditPort)
        XCTAssertTrue(gateways.flags is UnwiredFlagsPort)
        XCTAssertTrue(gateways.recovery is UnwiredRecoveryPort)
        XCTAssertTrue(gateways.justificatifs is UnwiredJustificatifStoragePort)
        XCTAssertTrue(gateways.clock is SystemClock, "défaut d'horloge du lot 0 conservé")
    }

    func testSecondInitCompletNeLaisseAucunPortDuLot1NonCable() {
        let horloge = FixedClock(Date(timeIntervalSince1970: 1))
        let gateways = Lot1Fakes.gateways(clock: horloge)
        XCTAssertEqual(gateways.unwiredPorts, Lot2PortsTests.portsLot2 + Lot3PortsTests.portsLot3,
                       "seuls les ports des lots 2 et 3 restent à assigner")
        XCTAssertTrue(gateways.audit is FakeAudit)
        XCTAssertTrue(gateways.flags is FakeFlags)
        XCTAssertTrue(gateways.justificatifs is FakeJustificatifs)
        XCTAssertEqual(gateways.clock.now(), Date(timeIntervalSince1970: 1))
    }

    func testRemplacerUnPortLeRetireDeLaListe() {
        var gateways = Gateways(auth: NeutralAuth(), role: NeutralRole(), missions: NeutralMissions())
        gateways.audit = FakeAudit()
        gateways.flags = FakeFlags()
        XCTAssertEqual(gateways.unwiredPorts, Self.portsLot1.filter { $0 != "audit" && $0 != "flags" }
                       + Lot2PortsTests.portsLot2 + Lot3PortsTests.portsLot3)
    }

    func testChaquePortNonCableRefuseExplicitementEnCitantSaTranche() async {
        let g = Gateways(auth: NeutralAuth(), role: NeutralRole(), missions: NeutralMissions())
        let c = contexte
        await refuse("T3") { _ = try await g.dashboard.dashboard(context: c, delaiEcran: delaiEcranTest) }
        await refuse("T6a") {
            _ = try await g.candidature.confirmer(action: .postuler, missionId: "m", creneaux: [], message: nil,
                                                  choixContrat: nil, candidatureId: nil, context: c)
        }
        await refuse("T6a") { try await g.candidature.refuserProposition(candidatureId: "c", context: c) }
        await refuse("T6a") { _ = try await g.candidature.candidature(missionId: "m", context: c) }
        await refuse("T7") {
            _ = try await g.candidature.annulerCandidature(id: "c", motif: "AUTRE", texte: "texte", justificatifPath: nil, context: c)
        }
        await refuse("T7") { _ = try await g.candidature.annulerMission(id: "m", motif: nil, context: c) }
        await refuse("T6c") { _ = try await g.presence.confirmerPresence(missionId: "m", context: c) }
        await refuse("T4b") { _ = try await g.favoris.missionsSauvegardees(context: c) }
        await refuse("T4b") { _ = try await g.favoris.sauvegarder(missionId: "m", context: c) }
        await refuse("T4b") { _ = try await g.favoris.retirer(missionId: "m", context: c) }
        await refuse("T4b") { _ = try await g.favoris.etablissementsFavoris(context: c) }
        await refuse("T4b") { _ = try await g.favoris.basculerEtablissement(id: "e", actif: false, context: c) }
        await refuse("T5") { _ = try await g.mesMissions.candidatures(context: c) }
        await refuse("T5") { _ = try await g.mesMissions.aVenir(context: c, page: 0) }
        await refuse("T5") { _ = try await g.mesMissions.passees(context: c, page: 0) }
        await refuse("T8") { _ = try await g.compte.deleteAccount(context: c) }
        await refuse("T1") { _ = try await g.audit.connexion() }
        await refuse("T1") { _ = try await g.audit.deconnexion() }
        await refuse("T1") { _ = try await g.audit.activite() }
        await refuse("T1") {
            _ = try await g.audit.ecrire(action: .missionAssignation, typeRessource: "mission", idRessource: "m",
                                         details: [:], context: c)
        }
        await refuse("T10") { try await g.recovery.requestReset(email: "a@b.c") }
        await refuse("T10") { _ = try await g.recovery.openRecoverySession(.tokenHash(tokenHash: "x", otpType: "recovery")) }
        await refuse("T10") { try await g.recovery.updatePassword("motdepasse") }
        await refuse("T10") { try await g.recovery.signOutAfterRecovery() }
        await refuse("T7") {
            _ = try await g.justificatifs.upload(data: Data(), fileName: "a.pdf", candidatureId: "c", userId: c.userId)
        }
    }

    func testLeDrapeauNonCableRendLeDefautDemande() async {
        // Seul port non levant (FlagsPort) : son stub suit la politique fail-open documentée et
        // reste nommé par `unwiredPorts`, que les tests de chaque monde contrôlent.
        let stub = UnwiredFlagsPort()
        let actif = await stub.ecranActif(cle: EcranNatif.accueil.cle, defaut: true)
        let inactif = await stub.ecranActif(cle: EcranNatif.accueil.cle, defaut: false)
        XCTAssertTrue(actif)
        XCTAssertFalse(inactif)
    }

    func testClesDesEcransNatifsEtPolitiqueFailOpen() async {
        // Les cinq écrans du lot 1 ouvrent la liste ; les suivants : `Lot2PortsTests.testClesDesEcransDuLot2ApresCellesDuLot1`.
        XCTAssertEqual(EcranNatif.allCases.prefix(5).map(\.cle), ["ios_natif_accueil_actif", "ios_natif_explorer_actif",
                                                                  "ios_natif_missions_actif", "ios_natif_revenus_actif",
                                                                  "ios_natif_profil_actif"])
        XCTAssertTrue(FlagsPolicy.defautFailOpen, "décision 15 : défaut true, inverse assumé de useParamBool")
        let flags = FakeFlags(valeurs: [EcranNatif.missions.cle: false])
        let missions = await flags.ecranActif(.missions)
        let accueil = await flags.ecranActif(.accueil)
        XCTAssertFalse(missions)
        XCTAssertTrue(accueil, "clé absente : défaut fail-open")
    }

    func testActionsDuLot1() {
        XCTAssertEqual(ActionPlanning.allCases.map(\.rawValue), ["POSTULER", "ACCEPTER", "PROPOSITION"])
        // L'action du lot 1 ouvre la liste ; celles des lots 2 et 3 : `Lot2PortsTests.testActionDAuditDuLot2ApresCelleDuLot1`,
        // `Lot3PortsTests.testActionsAuditDuLot3`.
        XCTAssertEqual(Array(AuditAction.allCases.map(\.rawValue).prefix(1)), ["MISSION_ASSIGNATION"])
        XCTAssertEqual(AuditAction.allCases.first, .missionAssignation)
        XCTAssertEqual(MissionsPage.taille, 50)
    }

    // MARK: - Aide

    private func refuse(_ tranche: String, file: StaticString = #filePath, line: UInt = #line,
                        _ operation: () async throws -> Void) async {
        do {
            try await operation()
            XCTFail("un port non câblé ne doit jamais répondre", file: file, line: line)
        } catch let error as JoleneError {
            XCTAssertEqual(error.kind, .contract, file: file, line: line)
            XCTAssertTrue(error.message.contains("non câblé"), error.message, file: file, line: line)
            XCTAssertTrue(error.message.contains("tranche \(tranche) "), "\(error.message) doit citer \(tranche)", file: file, line: line)
            XCTAssertTrue(error.message.contains("LOT1_PLAN.md"), error.message, file: file, line: line)
        } catch {
            XCTFail("type d'erreur inattendu : \(error)", file: file, line: line)
        }
    }
}
