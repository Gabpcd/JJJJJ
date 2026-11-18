import XCTest
@testable import JoleneCore

/// Candidature du détail de mission (lot 1, T6b) : état du bloc (`CandidatureEcran`), modèle (`CandidatureModel`) sur
/// le monde démo, identité démo unique entre les projections du lot 1 et du lot 3, textes vouvoyés.
@MainActor
final class CandidatureEcranTests: XCTestCase {
    private let maintenant = DemoWorld.fixedNow
    private let userId = DemoWorld.context.userId

    private func mission(_ id: String) async throws -> Mission {
        let lue = try await DemoWorld.gateways().missions.mission(id: id, context: DemoWorld.context)
        return try XCTUnwrap(lue, id)
    }

    private var profilCandidat: SoignantProfile { VarianteProfilDemo.candidat.appliquer(DemoWorld.context.profile) }

    private func etat(_ mission: Mission, candidature: CandidatureRecord? = nil, profil: SoignantProfile? = nil) -> CandidatureEcran {
        CandidatureEcran.etat(mission: mission, candidature: candidature, profil: profil ?? profilCandidat,
                              userId: userId, maintenant: maintenant)
    }

    private func proposition(_ missionId: String, contrat: String?, creeIlYa minutes: Double = 30) -> CandidatureRecord {
        CandidatureRecord(id: "p-1", missionId: missionId, statut: "PROPOSEE", message: nil, typeContratChoisi: contrat,
                          creeLe: DateHeureParis.isoUTC(maintenant.addingTimeInterval(-minutes * 60)))
    }

    // MARK: - État du bloc

    func testActionSelonLeModeDAttributionEtPlanning() async throws {
        let accepter = try await mission("demo-mission-013")
        let postuler = try await mission("demo-mission-014")
        XCTAssertEqual(etat(accepter), .ouverte(.accepter))
        XCTAssertEqual(etat(postuler), .ouverte(.postuler))
        var sansPlanning = try await mission("demo-mission-013")
        sansPlanning.erreurPlanning = true
        guard case let .planningBloque(action, message) = etat(sansPlanning) else { return XCTFail("planning bloqué attendu") }
        XCTAssertEqual(action, .accepter)
        XCTAssertEqual(message, PlanningCandidatRules.messageErreurChargement)
    }

    func testSoftGateDuProfilDemoParDefaut() async throws {
        // Identité démo par défaut (sans téléphone, RPPS non vérifié) : le gate nomme les deux champs, dans l'ordre web.
        let m = try await mission("demo-mission-013")
        XCTAssertEqual(etat(m, profil: DemoWorld.context.profile), .profilIncomplet(manquants: ["Téléphone", "RPPS vérifié"]))
        XCTAssertEqual(etat(m, profil: profilCandidat), .ouverte(.accepter), "variante candidat")
    }

    func testAssigneeDejaAttribueeEtMasque() async throws {
        var m = try await mission("demo-mission-013")
        m.record.statut = "ASSIGNEE"
        m.record.soignantAssigneId = userId.uppercased()
        XCTAssertEqual(etat(m), .assignee, "comparaison d'identifiant sans casse")
        m.record.soignantAssigneId = "autre-soignant"
        XCTAssertEqual(etat(m), .dejaAttribuee)
        m.record.statut = "ANNULEE"
        m.record.soignantAssigneId = nil
        XCTAssertEqual(etat(m), .masque)
    }

    func testPropositionLiberaleNativeSinonRenvoiWeb() async throws {
        let m = try await mission("demo-mission-011") // SALARIE
        XCTAssertEqual(etat(m, candidature: proposition(m.id, contrat: nil)), .propositionWeb(candidatureId: "p-1"))
        XCTAssertEqual(etat(m, candidature: proposition(m.id, contrat: "LIBERAL")), .proposition(candidatureId: "p-1"))
        XCTAssertEqual(etat(m, candidature: proposition(m.id, contrat: nil, creeIlYa: 121)), .ouverte(.accepter),
                       "proposition expirée : flux ordinaire")
        let liberale = try await mission("demo-mission-012") // LIBERAL
        XCTAssertEqual(etat(liberale, candidature: proposition(liberale.id, contrat: nil)), .proposition(candidatureId: "p-1"))
    }

    func testCandidatureEnvoyeeEnModeCandidature() async throws {
        let m = try await mission("demo-mission-014")
        let attente = CandidatureRecord(id: "c-1", missionId: m.id, statut: "EN_ATTENTE", message: nil, typeContratChoisi: nil, creeLe: nil)
        XCTAssertEqual(etat(m, candidature: attente), .envoyee)
        XCTAssertEqual(etat(m, candidature: attente, profil: DemoWorld.context.profile), .envoyee, "avant le soft-gate, comme le web")
    }

    // MARK: - Modèle sur le monde démo

    private func modele(_ missionId: String, variante: VarianteProfilDemo? = .candidat) async throws -> (CandidatureModel, Gateways) {
        let gateways = DemoWorld.gateways(drapeaux: [:], varianteProfil: variante)
        let controller = SessionController(gateways: gateways)
        let state = await controller.signIn(email: DemoWorld.context.email ?? "", password: "demonstration")
        let snapshot = try XCTUnwrap(state.snapshot, "session démo prête attendue, obtenu \(state)")
        let model = CandidatureModel(missionId: missionId, controller: controller, snapshot: snapshot)
        await model.charger()
        return (model, gateways)
    }

    private func relue(_ id: String, _ gateways: Gateways, profil: SoignantProfile) async throws -> Mission {
        var context = DemoWorld.context
        context.profile = profil
        let lue = try await gateways.missions.mission(id: id, context: context)
        return try XCTUnwrap(lue, id)
    }

    func testPostulerPuisCandidatureRelueEnvoyee() async throws {
        let (model, gateways) = try await modele("demo-mission-014")
        let m = try await relue("demo-mission-014", gateways, profil: profilCandidat)
        XCTAssertEqual(model.etat(m), .ouverte(.postuler))
        model.message = String(repeating: "a", count: 320)
        XCTAssertEqual(model.message.count, 300, "message borné à 300 comme le web")
        let relire = await model.confirmer(m)
        XCTAssertTrue(relire)
        XCTAssertNil(model.issue)
        XCTAssertEqual(model.candidature?.statut, "EN_ATTENTE", "candidature relue côté serveur démo")
        XCTAssertEqual(model.etat(m), .envoyee)
        XCTAssertEqual(model.message, "", "message vidé après l'envoi relu")
    }

    func testAccepterPuisMissionRelueAssignee() async throws {
        let (model, gateways) = try await modele("demo-mission-013")
        let m = try await relue("demo-mission-013", gateways, profil: profilCandidat)
        let relire = await model.confirmer(m)
        XCTAssertTrue(relire)
        XCTAssertNil(model.issue)
        let apres = try await relue("demo-mission-013", gateways, profil: profilCandidat)
        XCTAssertEqual(apres.record.statut, "ASSIGNEE", "relue par le monde démo, jamais posée par l'écran")
        XCTAssertEqual(model.etat(apres), .assignee)
        // Seconde tentative sur la mission relue : refus verbatim du serveur démo, aucun succès.
        _ = await model.confirmer(m)
        XCTAssertEqual(model.issue, .erreur(DemoCandidatureGateway.Textes.missionIndisponible))
    }

    func testProfilParDefautBloqueSansAppel() async throws {
        let (model, gateways) = try await modele("demo-mission-013", variante: nil)
        let m = try await relue("demo-mission-013", gateways, profil: DemoWorld.context.profile)
        XCTAssertEqual(model.etat(m), .profilIncomplet(manquants: ["Téléphone", "RPPS vérifié"]))
    }

    func testRefusDePropositionRelu() async throws {
        let (model, gateways) = try await modele("demo-mission-011")
        let m = try await relue("demo-mission-011", gateways, profil: profilCandidat)
        XCTAssertEqual(model.etat(m), .propositionWeb(candidatureId: "demo-proposition-001"), "proposition salariée : renvoi web")
        let acceptee = await model.accepterProposition(m)
        XCTAssertFalse(acceptee, "aucune acceptation native d'une proposition salariée")
        let refusee = await model.refuserProposition(m)
        XCTAssertTrue(refusee)
        XCTAssertEqual(model.issue, .propositionRefusee)
        XCTAssertEqual(model.candidature?.statut, "REFUSEE")
        XCTAssertEqual(model.etat(m), .ouverte(.accepter), "proposition refusée : flux ordinaire")
    }

    // MARK: - Profil démo et textes

    func testIdentiteDemoUniqueEntreLesProjections() async throws {
        let complet = try await DemoProfilGateway().profil(context: DemoWorld.context)
        let lot1 = DemoWorld.context.profile
        XCTAssertEqual(lot1.prenom, complet.prenom)
        XCTAssertEqual(lot1.nom, complet.nom)
        XCTAssertEqual(lot1.dateNaissanceRenseignee, !(complet.dateNaissance ?? "").isEmpty)
        XCTAssertEqual(lot1.telephoneRenseigne, !(complet.telephone ?? "").isEmpty)
        XCTAssertEqual(lot1.rppsVerifie, complet.rppsVerifie)
        for variante in VarianteProfilDemo.allCases {
            let variee = try await DemoProfilGateway(variante: variante).profil(context: DemoWorld.context)
            let projection = variante.appliquer(lot1)
            XCTAssertEqual(projection.telephoneRenseigne, !(variee.telephone ?? "").isEmpty, variante.rawValue)
            XCTAssertEqual(projection.rppsVerifie, variee.rppsVerifie, variante.rawValue)
            XCTAssertEqual(projection.dateNaissanceRenseignee, !(variee.dateNaissance ?? "").isEmpty, variante.rawValue)
        }
        XCTAssertTrue(ProfilCompletion.calculer(VarianteProfilDemo.candidat.appliquer(lot1)).peutCandidater)
        let profilSession = try await DemoWorld.gateways(drapeaux: [:], varianteProfil: .candidat).missions.profile(userId: userId)
        XCTAssertEqual(profilSession?.rppsVerifie, true, "la variante vaut pour le soft-gate du lot 1")
    }

    func testTextesVouvoyesDuDetailDeMission() throws {
        let racine = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let page = try String(contentsOf: racine.appendingPathComponent("src/pages/DetailMissionSoignant.tsx"), encoding: .utf8)
        let L = LibellesCandidature.self
        for verbatim in [L.postuler, L.postulerEnCours, L.accepter, L.accepterEnCours, L.messageLibelle, L.envoyee,
                         L.dejaAttribuee, L.voirAutresMissions, L.completerProfil, L.recapEnvoyer, L.recapAccepter] {
            XCTAssertTrue(page.contains(verbatim), "texte web absent : \(verbatim)")
        }
        let vouvoyes: [(natif: String, web: String)] = [
            (L.messagePlaceholder, "Présente-toi brièvement…"),
            (L.postulerAide, "L'établissement examinera ta candidature. Tu seras notifié(e) de sa décision."),
            (L.envoyeeDocuments, "Prochaine étape : valide tes documents pour que l'établissement puisse t'accepter."),
            (L.envoyeeProfil, "L'établissement examinera ton profil et reviendra vers toi."),
            (L.assignee, "✅ Tu es assigné(e) à cette mission"),
        ]
        for (natif, web) in vouvoyes {
            XCTAssertTrue(page.contains(web), "source web changée : \(web)")
            XCTAssertNotEqual(natif, web)
        }
        XCTAssertEqual(L.manquants(2), "Il manque 2 informations pour pouvoir postuler :")
        XCTAssertEqual(L.manquants(1), "Il manque 1 information pour pouvoir postuler :")
        XCTAssertEqual(L.recapDescription(intitule: nil), "Mission — confirmez uniquement si vous pouvez assurer tous les créneaux ci-dessous.")
    }
}
