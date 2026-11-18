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

    /// Revue B8 (M1) : le soft-gate relit la ligne démo que l'édition du profil (lot 3) réécrit — jamais une copie figée.
    func testModifierLeProfilPuisRelireLeveLeSoftGate() async throws {
        let (model, gateways) = try await modele("demo-mission-013", variante: .identiteVerrouillee)
        let m = try await relue("demo-mission-013", gateways, profil: DemoWorld.context.profile)
        XCTAssertEqual(model.etat(m), .profilIncomplet(manquants: ["Téléphone"]), "RPPS vérifié, téléphone absent")
        _ = try await gateways.profil.modifier(ModificationProfil(telephone: VarianteProfilDemo.telephoneCandidat),
                                               context: DemoWorld.context)
        let projection = try await gateways.missions.profile(userId: userId)
        XCTAssertEqual(projection?.telephoneRenseigne, true, "projection du lot 1 relue dans le même magasin")
        await model.charger()
        XCTAssertEqual(model.etat(m), .ouverte(.accepter), "soft-gate levé au retour sur le détail")
    }

    /// Revue B8 (m1) : `enCours` est posé avant tout `await` : un double toucher n'envoie qu'une action.
    func testDoubleToucherNEnvoieQuUneAction() async throws {
        let (model, gateways) = try await modele("demo-mission-013")
        let m = try await relue("demo-mission-013", gateways, profil: profilCandidat)
        async let premier = model.confirmer(m)
        async let second = model.confirmer(m)
        let issues = await [premier, second]
        XCTAssertEqual(issues.filter { $0 }.count, 1, "un seul envoi")
        XCTAssertNil(model.issue, "sans la garde, le second envoi afficherait « Cette mission n'est plus disponible. »")

        let (refus, gatewaysRefus) = try await modele("demo-mission-011")
        let proposee = try await relue("demo-mission-011", gatewaysRefus, profil: profilCandidat)
        async let r1 = refus.refuserProposition(proposee)
        async let r2 = refus.refuserProposition(proposee)
        let refus1 = await [r1, r2]
        XCTAssertEqual(refus1.filter { $0 }.count, 1)
        XCTAssertEqual(refus.issue, .propositionRefusee, "pas d'erreur « plus en attente » après le refus relu")
    }

    /// Revue B8 (m5) : lignes du récapitulatif comme `PlanningMissionCandidat.tsx` (année, « (lendemain) », durée).
    func testLignesDuRecapitulatifCommeLeWeb() {
        let jour = MissionSlot(debut: "2026-11-03T07:00:00.000Z", fin: "2026-11-03T15:00:00.000Z", estPause: false, typeCreneau: "PREVISIONNEL")
        XCTAssertEqual(MissionPresentation.creneauCandidat(jour), "mardi 3 novembre 2026, 08h00 → 16h00 · 8 h")
        let nuit = MissionSlot(debut: "2026-11-06T20:00:00.000Z", fin: "2026-11-07T06:30:00.000Z", estPause: false, typeCreneau: "PREVISIONNEL")
        XCTAssertEqual(MissionPresentation.creneauCandidat(nuit), "vendredi 6 novembre 2026, 21h00 → samedi 7 novembre 2026 · 07h30 (lendemain) · 10,5 h")
        let sansFin = MissionSlot(debut: "2026-11-03T07:00:00.000Z", fin: nil, estPause: false, typeCreneau: "PREVISIONNEL")
        XCTAssertEqual(MissionPresentation.creneauCandidat(sansFin), "mardi 3 novembre 2026, 08h00 → fin à confirmer")
    }

    /// Revue B8 (P2) : phrase d'engagement du récapitulatif, reprise à l'identique selon l'action.
    func testPhraseDEngagementSelonLAction() {
        XCTAssertEqual(LibellesCandidature.recapEngagement(.postuler), TextesWeb.Candidature.engagementCandidature)
        XCTAssertEqual(LibellesCandidature.recapEngagement(.accepter), TextesWeb.Candidature.engagementAcceptation)
        XCTAssertEqual(LibellesCandidature.recapEngagement(.proposition), TextesWeb.Candidature.engagementAcceptation)
        XCTAssertTrue(TextesWeb.Candidature.engagementAcceptation.hasPrefix("En confirmant, tu acceptes immédiatement"))
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
