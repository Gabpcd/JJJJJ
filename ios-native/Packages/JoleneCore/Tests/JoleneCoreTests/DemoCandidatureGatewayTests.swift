import Foundation
import XCTest
@testable import JoleneCore

/// Candidature du monde démo (lot 1, T6a) : mêmes contrôles et mêmes textes que le serveur, relecture dans
/// l'acteur, candidatures de session visibles dans Mes missions ; annulations (T7) dans l'ordre et avec les textes du serveur.
final class DemoCandidatureGatewayTests: XCTestCase {
    private let context = DemoWorld.context

    private func fixture(_ id: String) throws -> DemoFixtures.MissionFixture {
        try XCTUnwrap(try DemoFixtures.loadMissions().missions.first { $0.record.id == id }, id)
    }

    private func creneaux(_ id: String) throws -> [CreneauConfirme] {
        let mission = try fixture(id)
        return try XCTUnwrap(CreneauxConfirmes.pourAction(PlanningCandidatInput(record: mission.record, creneaux: mission.creneaux)))
    }

    private func erreur(_ operation: () async throws -> Void) async -> JoleneError? {
        do {
            try await operation()
            return nil
        } catch let error as JoleneError {
            return error
        } catch {
            XCTFail("erreur inattendue : \(error)")
            return nil
        }
    }

    func testFixturesPortentLeModeDAttribution() throws {
        XCTAssertEqual(try fixture("demo-mission-004").record.modeAttribution, "CANDIDATURE")
        XCTAssertEqual(try fixture("demo-mission-001").record.modeAttribution, "PREMIER_ARRIVE")
        XCTAssertEqual(CandidatureRules.action(pour: try fixture("demo-mission-014").record), .postuler)
        // Les candidatures en attente de Mes missions portent sur des missions en mode candidature.
        for candidature in try DemoFixtures.loadMesMissions().candidatures {
            XCTAssertEqual(try fixture(candidature.missionId).record.modeAttribution, "CANDIDATURE", candidature.id)
        }
    }

    func testPostulerCreeUneCandidatureRelueVisibleDansMesMissions() async throws {
        let gateways = DemoWorld.gateways()
        let issue = try await gateways.candidature.confirmer(action: .postuler, missionId: "demo-mission-014",
                                                             creneaux: try creneaux("demo-mission-014"), message: "Disponible",
                                                             choixContrat: nil, candidatureId: nil, context: context)
        guard case let .confirmed(candidatureId?, nil) = issue else { return XCTFail("issue : \(issue)") }
        let relue = try await gateways.candidature.candidature(missionId: "demo-mission-014", context: context)
        XCTAssertEqual(relue?.id, candidatureId)
        XCTAssertEqual(relue?.statut, "EN_ATTENTE")
        XCTAssertEqual(relue?.message, "Disponible")
        XCTAssertEqual(relue?.creeLe, "2026-11-02T00:00:00.000Z", "horloge fixée")
        let mesMissions = try await gateways.mesMissions.candidatures(context: context)
        XCTAssertEqual(mesMissions.first?.id, candidatureId, "la plus récente en tête de l'onglet Candidatures")
        XCTAssertEqual(mesMissions.count, 3, "deux candidatures des fixtures + celle de la session")

        let seconde = await erreur {
            _ = try await gateways.candidature.confirmer(action: .postuler, missionId: "demo-mission-014",
                                                         creneaux: try self.creneaux("demo-mission-014"), message: nil,
                                                         choixContrat: nil, candidatureId: nil, context: self.context)
        }
        XCTAssertEqual(seconde, JoleneError(.unknown, "Vous avez déjà postulé à cette mission"))
    }

    func testPlanningDifferentAReconfirmerSansRienEcrire() async throws {
        let gateway = DemoCandidatureGateway()
        var modifie = try creneaux("demo-mission-014")
        modifie[0].fin = "2026-11-16T16:00:00Z"
        let issue = try await gateway.confirmer(action: .postuler, missionId: "demo-mission-014", creneaux: modifie, message: nil,
                                                choixContrat: nil, candidatureId: nil, context: context)
        XCTAssertEqual(issue, .planningAReconfirmer(code: "PLANNING_MODIFIE_RECONFIRMER",
                                                    message: "Le planning a changé depuis son affichage. Vérifiez à nouveau toutes les dates et tous les horaires."))
        let vide = try await gateway.confirmer(action: .accepter, missionId: "demo-mission-001", creneaux: [], message: nil,
                                               choixContrat: nil, candidatureId: nil, context: context)
        XCTAssertEqual(vide, .planningAReconfirmer(code: "PLANNING_MODIFIE_RECONFIRMER", message: DemoCandidatureGateway.Textes.planningModifie))
        let sessions = await gateway.candidaturesDeSession()
        XCTAssertTrue(sessions.isEmpty)
        let contrat = await gateway.contratAttribue(missionId: "demo-mission-001")
        XCTAssertNil(contrat)
    }

    func testAccepterAttribueLaMissionRelueAssigneeEtRetireeDExplorer() async throws {
        let gateways = DemoWorld.gateways()
        let issue = try await gateways.candidature.confirmer(action: .accepter, missionId: "demo-mission-001",
                                                             creneaux: try creneaux("demo-mission-001"), message: nil,
                                                             choixContrat: nil, candidatureId: nil, context: context)
        XCTAssertEqual(issue, .confirmed(candidatureId: nil, contratId: "demo-contrat-demo-mission-001"))
        // Revue B8, m5 : le détail démo relit la mission ASSIGNEE au profil fictif, Explorer ne la liste plus.
        let relue = try await gateways.missions.mission(id: "demo-mission-001", context: context)
        XCTAssertEqual(relue?.record.statut, "ASSIGNEE")
        XCTAssertEqual(relue?.record.soignantAssigneId, context.userId)
        let explorer = try await gateways.missions.listMissions(context: context, filters: MissionFilters())
        XCTAssertFalse(explorer.contains { $0.id == "demo-mission-001" })
        // Course : une seconde action sur la mission attribuée → message serveur exact de la forme 3.
        let encore = try await gateways.candidature.confirmer(action: .accepter, missionId: "demo-mission-001",
                                                              creneaux: try creneaux("demo-mission-001"), message: nil,
                                                              choixContrat: nil, candidatureId: nil, context: context)
        XCTAssertEqual(encore, .missionDejaAttribuee(message: "Cette mission n'est plus disponible."))
    }

    func testPostulerResoutLeContratAvantDeChercherUnDoublon() async throws {
        // Ordre de `fn_postuler_mission` (revue B8, m5) : `choix_requis` avant « Vous avez déjà postulé ».
        var mission = try fixture("demo-mission-014")
        mission.record.typeContratRecherche = "TOUS"
        let source = mission
        let existante = CandidatureRecord(id: "c-ancienne", missionId: "demo-mission-014", statut: "EN_ATTENTE", message: nil,
                                          typeContratChoisi: nil, creeLe: "2026-11-01T10:00:00.000Z")
        let gateway = DemoCandidatureGateway(missions: { [source] }, candidaturesInitiales: { [existante] })
        let issue = try await gateway.confirmer(action: .postuler, missionId: "demo-mission-014",
                                                creneaux: try creneaux("demo-mission-014"), message: nil, choixContrat: nil,
                                                candidatureId: nil, context: context)
        XCTAssertEqual(issue, .choixRequis(DemoCandidatureGateway.Textes.choixContrat))
    }

    func testAccepterUneMissionEnModeCandidatureRefuseVerbatim() async throws {
        let gateway = DemoCandidatureGateway()
        let refus = await erreur {
            _ = try await gateway.confirmer(action: .accepter, missionId: "demo-mission-014",
                                            creneaux: try self.creneaux("demo-mission-014"), message: nil, choixContrat: nil,
                                            candidatureId: nil, context: self.context)
        }
        XCTAssertEqual(refus, JoleneError(.unknown, "Cette mission nécessite une candidature"))
    }

    func testPropositionSalarieeDeLAccueilVerrouilleeSansRienEcrire() async throws {
        // Revue B8, M1 : l'attestation hebdomadaire du web n'est pas portée ; la proposition salariée part sur le web.
        let gateway = DemoCandidatureGateway()
        let avant = try await gateway.candidature(missionId: "demo-mission-011", context: context)
        XCTAssertEqual(avant?.id, "demo-proposition-001")
        XCTAssertEqual(avant?.statut, "PROPOSEE")
        for declare in [nil, "SALARIE", "LIBERAL"] as [String?] {
            do {
                _ = try await gateway.confirmer(action: .proposition, missionId: "demo-mission-011",
                                                creneaux: try creneaux("demo-mission-011"), message: nil, choixContrat: declare,
                                                candidatureId: "demo-proposition-001", context: context)
                XCTFail("proposition salariée acceptée en natif (déclaré \(declare ?? "nil"))")
            } catch let verrou as CandidatureVerrou {
                XCTAssertEqual(verrou, .renvoiWeb(chemin: "/soignant/tableau-de-bord"), "déclaré LIBERAL à tort : contrat relu SALARIE")
            }
        }
        let apres = try await gateway.candidature(missionId: "demo-mission-011", context: context)
        XCTAssertEqual(apres?.statut, "PROPOSEE", "rien n'est écrit")
        let contrat = await gateway.contratAttribue(missionId: "demo-mission-011")
        XCTAssertNil(contrat)
    }

    func testPropositionLiberaleAccepteePuisRelue() async throws {
        var mission = try fixture("demo-mission-003") // LIBERAL
        XCTAssertEqual(mission.record.typeContratRecherche, "LIBERAL")
        mission.record.modeAttribution = "PREMIER_ARRIVE"
        let source = mission
        let proposee = CandidatureRecord(id: "p-liberale", missionId: "demo-mission-003", statut: "PROPOSEE", message: nil,
                                         typeContratChoisi: nil, creeLe: "2026-11-01T23:30:00.000Z")
        let gateway = DemoCandidatureGateway(missions: { [source] }, candidaturesInitiales: { [proposee] })
        let issue = try await gateway.confirmer(action: .proposition, missionId: "demo-mission-003",
                                                creneaux: try creneaux("demo-mission-003"), message: nil, choixContrat: "LIBERAL",
                                                candidatureId: "p-liberale", context: context)
        XCTAssertEqual(issue, .confirmed(candidatureId: "p-liberale", contratId: "demo-contrat-demo-mission-003"))
        let apres = try await gateway.candidature(missionId: "demo-mission-003", context: context)
        XCTAssertEqual(apres?.statut, "ACCEPTEE")
        let introuvable = try await DemoCandidatureGateway(missions: { [source] }, candidaturesInitiales: { [] })
            .confirmer(action: .proposition, missionId: "demo-mission-003", creneaux: try creneaux("demo-mission-003"),
                       message: nil, choixContrat: "LIBERAL", candidatureId: "p-liberale", context: context)
        XCTAssertEqual(introuvable, .refusee(code: nil, message: "Proposition introuvable.", documentsRequisPour: nil))
    }

    func testPropositionRefuseePuisExpireeApresDeuxHeures() async throws {
        let gateway = DemoCandidatureGateway()
        try await gateway.refuserProposition(candidatureId: "demo-proposition-001", context: context)
        let refusee = try await gateway.candidature(missionId: "demo-mission-011", context: context)
        XCTAssertEqual(refusee?.statut, "REFUSEE")
        let plusEnAttente = await erreur { try await gateway.refuserProposition(candidatureId: "demo-proposition-001", context: self.context) }
        XCTAssertEqual(plusEnAttente, JoleneError(.unknown, "Cette proposition n’est plus en attente"))

        let tard = DemoCandidatureGateway(clock: FixedClock(DemoWorld.fixedNow.addingTimeInterval(3 * 3600)))
        let expiree = await erreur { try await tard.refuserProposition(candidatureId: "demo-proposition-001", context: self.context) }
        XCTAssertEqual(expiree, JoleneError(.unknown, "Cette proposition a expiré"))
        let relue = try await tard.candidature(missionId: "demo-mission-011", context: context)
        XCTAssertEqual(relue?.statut, "EXPIREE", "le serveur pose EXPIREE lui-même")
    }

    func testMissionTousPourUnProfilMixteDemandeLeChoixPuisRejoue() async throws {
        var mission = try fixture("demo-mission-001")
        mission.record.typeContratRecherche = "TOUS"
        let source = mission
        let gateway = DemoCandidatureGateway(missions: { [source] }, candidaturesInitiales: { [] })
        let creneaux = try creneaux("demo-mission-001")
        let choix = try await gateway.confirmer(action: .accepter, missionId: "demo-mission-001", creneaux: creneaux, message: nil,
                                                choixContrat: nil, candidatureId: nil, context: context)
        XCTAssertEqual(choix, .choixRequis([ChoixContratOption(value: "SALARIE", label: "Salarié (CDD / bulletin de paie)"),
                                            ChoixContratOption(value: "LIBERAL", label: "Libéral (note d'honoraires)")]))
        let rejoue = try await gateway.confirmer(action: .accepter, missionId: "demo-mission-001", creneaux: creneaux, message: nil,
                                                 choixContrat: "SALARIE", candidatureId: nil, context: context)
        XCTAssertEqual(rejoue, .confirmed(candidatureId: nil, contratId: "demo-contrat-demo-mission-001"))
    }

    func testAutreUtilisateurRefuse() async throws {
        let gateway = DemoCandidatureGateway()
        var autre = context
        autre.userId = "autre"
        autre.profile.id = "autre"
        let demo = await erreur { _ = try await gateway.candidature(missionId: "demo-mission-011", context: autre) }
        XCTAssertEqual(demo?.kind, .demoOnly)
        let annulation = await erreur { _ = try await gateway.annulerMission(id: "demo-assignee-001", motif: nil, context: autre) }
        XCTAssertEqual(annulation?.kind, .demoOnly)
    }

    // MARK: - Annulations (T7)

    private let explication = "Train supprimé ce matin, aucun autre trajet possible."

    func testToutesLesMissionsAssigneesDemarrentAPlusDe24h() throws {
        // Le serveur rendrait 0 point pour chacune (`neutre_delai_long`, pénalité de mission nulle) : la démo ne
        // simule aucun barème.
        for fixture in try DemoFixtures.loadDashboard().missionsAssignees {
            let debut = try DateHeureParis.instantJolene(fixture.record.debutLe)
            XCTAssertGreaterThan(debut.timeIntervalSince(DemoWorld.fixedNow), 24 * 3600, fixture.record.id)
            XCTAssertEqual(fixture.record.soignantAssigneId, DemoWorld.context.userId)
        }
    }

    func testCandidatureRetenueAnnuleeRelueAvecSonJustificatif() async throws {
        let gateway = DemoCandidatureGateway()
        let relue = try await gateway.candidature(missionId: "demo-assignee-003", context: context)
        XCTAssertEqual(relue, DemoCandidatureGateway.candidatureRetenue)
        let chemin = "demo-soignant/annulations-candidature/demo-candidature-retenue-003/1793577600000_billet.pdf"
        let issue = try await gateway.annulerCandidature(id: "demo-candidature-retenue-003", motif: "PROBLEME_TRANSPORT",
                                                         texte: explication, justificatifPath: chemin, context: context)
        XCTAssertEqual(issue, .annulee(points: 0, libre: true, contestable: false))
        let apres = try await gateway.candidature(missionId: "demo-assignee-003", context: context)
        XCTAssertEqual(apres?.statut, "ANNULEE")
        let transmis = await gateway.justificatifTransmis(candidatureId: "demo-candidature-retenue-003")
        XCTAssertEqual(transmis, chemin)
        let annulee = await gateway.missionAnnulee("demo-assignee-003")
        XCTAssertTrue(annulee)
        // Seconde annulation : refus du serveur, verbatim.
        let encore = try await gateway.annulerCandidature(id: "demo-candidature-retenue-003", motif: "AUTRE", texte: explication,
                                                          justificatifPath: nil, context: context)
        XCTAssertEqual(encore, .refusee(code: "STATUT_INVALIDE", message: "Candidature pas dans un état annulable (statut : ANNULEE)"))
    }

    func testCandidatureEnAttenteRetireeSansImpact() async throws {
        let gateway = DemoCandidatureGateway()
        let issue = try await gateway.annulerCandidature(id: "demo-candidature-001", motif: "CHANGEMENT_AVIS", texte: explication,
                                                         justificatifPath: nil, context: context)
        XCTAssertEqual(issue, .annulee(points: 0, libre: true, contestable: nil), "`{libre:true, points:0}` sans `contestable`")
        let mesMissions = try await DemoMesMissionsGateway(candidaturesDeSession: { await gateway.candidaturesDeSession() })
            .candidatures(context: context)
        XCTAssertFalse(mesMissions.contains { $0.id == "demo-candidature-001" }, "la candidature retirée quitte Mes missions")
    }

    func testRefusDeLAnnulationDansLOrdreDuServeur() async throws {
        let gateway = DemoCandidatureGateway()
        let motif = try await gateway.annulerCandidature(id: "demo-candidature-001", motif: "FLEMME", texte: explication,
                                                         justificatifPath: nil, context: context)
        XCTAssertEqual(motif, .refusee(code: "MOTIF_INVALIDE", message: DemoCandidatureGateway.Textes.motifInvalide))
        let texte = try await gateway.annulerCandidature(id: "demo-candidature-001", motif: "AUTRE", texte: "  court  ",
                                                         justificatifPath: nil, context: context)
        XCTAssertEqual(texte, .refusee(code: "TEXTE_REQUIS", message: "Texte libre obligatoire (min 10 caractères)"))
        let absente = try await gateway.annulerCandidature(id: "inconnue", motif: "AUTRE", texte: explication,
                                                           justificatifPath: nil, context: context)
        XCTAssertEqual(absente, .refusee(code: "CANDIDATURE_INTROUVABLE", message: "Candidature introuvable"))
        let proposition = try await gateway.annulerCandidature(id: "demo-proposition-001", motif: "AUTRE", texte: explication,
                                                               justificatifPath: nil, context: context)
        XCTAssertEqual(proposition, .refusee(code: "STATUT_INVALIDE", message: "Candidature pas dans un état annulable (statut : PROPOSEE)"))
    }

    func testMissionAssigneeAnnuleeUneSeuleFois() async throws {
        let gateway = DemoCandidatureGateway()
        let issue = try await gateway.annulerMission(id: "demo-assignee-001", motif: nil, context: context)
        XCTAssertEqual(issue, .annulee(points: 0, libre: nil, contestable: nil), "`penalite_score` nul à plus de 24 h")
        let encore = try await gateway.annulerMission(id: "demo-assignee-001", motif: nil, context: context)
        XCTAssertEqual(encore, .refusee(code: nil, message: "Cette mission ne vous est pas assignée"))
        let ouverte = try await gateway.annulerMission(id: "demo-mission-001", motif: nil, context: context)
        XCTAssertEqual(ouverte, .refusee(code: nil, message: "Cette mission ne vous est pas assignée"))
        let inconnue = try await gateway.annulerMission(id: "demo-inconnue", motif: nil, context: context)
        XCTAssertEqual(inconnue, .refusee(code: nil, message: "Mission introuvable"))
    }

    /// Revue B8 de #1156, M1 : le monde démo suit les annulations comme le serveur (mission remise en ligne) — détail relu
    /// `OUVERTE` sans soignant, absente d'« À venir », de nouveau listée dans Explorer (chemin de réouverture du XCUITest).
    func testMondeDemoSuitLAnnulation() async throws {
        let gateways = DemoWorld.gateways()
        let avant = try await gateways.missions.mission(id: "demo-assignee-001", context: context)
        XCTAssertEqual(avant?.record.statut, "ASSIGNEE")
        let issue = try await gateways.candidature.annulerMission(id: "demo-assignee-001", motif: nil, context: context)
        XCTAssertEqual(issue, .annulee(points: 0, libre: nil, contestable: nil))
        let relue = try await gateways.missions.mission(id: "demo-assignee-001", context: context)
        XCTAssertEqual(relue?.record.statut, "OUVERTE")
        XCTAssertNil(relue?.record.soignantAssigneId)
        let aVenir = try await gateways.mesMissions.aVenir(context: context, page: 0)
        XCTAssertFalse(aVenir.missions.contains { $0.id == "demo-assignee-001" })
        XCTAssertTrue(aVenir.missions.contains { $0.id == "demo-assignee-002" }, "les autres missions restent")
        let explorer = try await gateways.missions.listMissions(context: context, filters: MissionFilters())
        XCTAssertTrue(explorer.contains { $0.id == "demo-assignee-001" }, "remise en ligne")
        XCTAssertFalse(explorer.contains { $0.id == "demo-assignee-002" }, "une mission encore assignée reste hors d'Explorer")
        // La candidature retenue suit le même chemin.
        _ = try await gateways.candidature.annulerCandidature(id: "demo-candidature-retenue-003", motif: "AUTRE", texte: explication,
                                                              justificatifPath: nil, context: context)
        let retenue = try await gateways.missions.mission(id: "demo-assignee-003", context: context)
        XCTAssertEqual(retenue?.record.statut, "OUVERTE")
        XCTAssertNil(retenue?.record.soignantAssigneId)
        // Le serveur (simulé) admet encore « Urgence médicale », que l'app ne propose plus (décision 21).
        let medical = try await DemoCandidatureGateway().annulerCandidature(id: "demo-candidature-001", motif: "URGENCE_MEDICALE",
                                                                            texte: explication, justificatifPath: nil, context: context)
        XCTAssertEqual(medical, .annulee(points: 0, libre: true, contestable: nil))
    }
}
