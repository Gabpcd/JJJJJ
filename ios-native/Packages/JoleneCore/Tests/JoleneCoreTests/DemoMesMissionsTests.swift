import XCTest
@testable import JoleneCore

/// Mes missions du monde démo (lot 1, T5) : `demo-mes-missions.json` (candidatures, passées) et les
/// missions ASSIGNEE de `demo-dashboard.json` (« À venir », source unique avec l'Accueil), aucun
/// réseau, horloge fixée. Les valeurs attendues sont celles que le XCUITest `DemoMesMissionsTests`
/// relit à l'écran.
final class DemoMesMissionsTests: XCTestCase {
    private let euro = "\u{00A0}€"
    private var port: MesMissionsPort { DemoWorld.gateways().mesMissions }

    func testFixtureHorlogeFixeeEtCoherenceAvecLeTableauDeBord() throws {
        let fichier = try DemoFixtures.loadMesMissions()
        XCTAssertEqual(fichier.fixedNow, "2026-11-02T00:00:00.000Z")
        XCTAssertEqual(fichier.candidatures.map(\.id), ["demo-candidature-001", "demo-candidature-002"])
        XCTAssertEqual(fichier.passees.map(\.mission.record.id), ["demo-terminee-001", "demo-terminee-002", "demo-annulee-001"])
        // Même mission terminée que les gains de l'Accueil : mêmes valeurs serveur.
        let gains = try XCTUnwrap(DemoFixtures.loadDashboard().gainsMissions.first)
        let terminee = try XCTUnwrap(fichier.passees.first { $0.finance.id == gains.id })
        XCTAssertEqual(terminee.finance, gains)
        let ouvertes = Set(try DemoFixtures.loadMissions().missions.map(\.record.id))
        XCTAssertTrue(fichier.candidatures.allSatisfy { ouvertes.contains($0.missionId) }, "candidatures sur des missions démo ouvertes")
    }

    func testCandidaturesEnAttenteAvecLeurMissionEnrichie() async throws {
        let candidatures = try await port.candidatures(context: DemoWorld.context)
        XCTAssertEqual(candidatures.map(\.id), ["demo-candidature-001", "demo-candidature-002"], "`cree_le` décroissant")
        let lignes = candidatures.compactMap { MesMissionsPresentation.ligne(candidature: $0, maintenant: DemoWorld.fixedNow) }
        XCTAssertEqual(lignes.map(\.id), ["demo-mission-004", "demo-mission-009"])
        XCTAssertEqual(lignes.map(\.texteAccessible), [
            "⏳ En attente de réponse, Salarié, Démonstration · Soins de suite 4, Établissement fictif République · Paris, 6 nov. · 21h00 → 05h00, 26,00\(euro)/h",
            "⏳ En attente de réponse, ★ Priorité historique, Libéral, Démonstration · Médecine polyvalente 9, Cabinet fictif du Parc · Vincennes, 11 nov. · 08h00 → 16h00, 23,00\(euro)/h",
        ])
    }

    func testCandidaturesDeSessionEnTeteEtMissionMasqueeEcartee() async throws {
        let posee = CandidatureRecord(id: "session-1", missionId: "demo-mission-002", statut: "EN_ATTENTE", message: nil,
                                      typeContratChoisi: nil, creeLe: "2026-11-02T00:00:00.000Z")
        let masquee = CandidatureRecord(id: "session-2", missionId: "demo-mission-999", statut: "EN_ATTENTE", message: nil,
                                        typeContratChoisi: nil, creeLe: "2026-11-02T00:00:00.000Z")
        let acceptee = CandidatureRecord(id: "session-3", missionId: "demo-mission-003", statut: "ACCEPTEE", message: nil,
                                         typeContratChoisi: nil, creeLe: "2026-11-02T00:00:00.000Z")
        let gateway = DemoMesMissionsGateway(candidaturesDeSession: { [posee, masquee, acceptee] })
        let candidatures = try await gateway.candidatures(context: DemoWorld.context)
        XCTAssertEqual(candidatures.map(\.id), ["session-1", "demo-candidature-001", "demo-candidature-002"],
                       "mission absente écartée, statut hors attente filtré, la plus récente d'abord")
        XCTAssertEqual(candidatures.first?.mission?.etablissement?.nom, "Établissement fictif des Lilas")
    }

    /// Point de fusion T6b (revue B8 de T5) : le serveur n'admet qu'une candidature par mission et par
    /// soignant (`UNIQUE candidatures_mission_id_soignant_id_key`). Une candidature de session sur une
    /// mission des fixtures la remplace — y compris quand elle n'est plus en attente (annulée) — et la
    /// liste ne porte jamais deux lignes pour une même mission (`Ligne.id` = id de mission).
    func testCandidatureDeSessionRemplaceCelleDesFixturesSurLaMemeMission() async throws {
        let relue = CandidatureRecord(id: "session-1", missionId: "demo-mission-004", statut: "EN_ATTENTE", message: "Super-like",
                                      typeContratChoisi: "LIBERAL", creeLe: "2026-11-02T00:00:00.000Z")
        let doublon = CandidatureRecord(id: "session-1b", missionId: "demo-mission-004", statut: "EN_ATTENTE", message: nil,
                                        typeContratChoisi: nil, creeLe: "2026-11-02T00:00:00.000Z")
        let gateway = DemoMesMissionsGateway(candidaturesDeSession: { [relue, doublon] })
        let candidatures = try await gateway.candidatures(context: DemoWorld.context)
        XCTAssertEqual(candidatures.map(\.id), ["session-1", "demo-candidature-002"], "la session a priorité, une ligne par mission")
        XCTAssertEqual(candidatures.map(\.missionId), ["demo-mission-004", "demo-mission-009"])
        XCTAssertEqual(candidatures.first?.typeContratChoisi, "LIBERAL")

        let annulee = CandidatureRecord(id: "session-2", missionId: "demo-mission-004", statut: "ANNULEE", message: nil,
                                        typeContratChoisi: nil, creeLe: "2026-11-02T00:00:00.000Z")
        let apresAnnulation = try await DemoMesMissionsGateway(candidaturesDeSession: { [annulee] }).candidatures(context: DemoWorld.context)
        XCTAssertEqual(apresAnnulation.map(\.id), ["demo-candidature-002"], "la candidature annulée en session masque celle des fixtures")
    }

    func testAVenirLesMissionsAssigneesDeLAccueil() async throws {
        let page = try await port.aVenir(context: DemoWorld.context, page: 0)
        XCTAssertEqual(page.missions.map(\.id), ["demo-assignee-001", "demo-assignee-002"])
        XCTAssertFalse(page.aSuivre)
        XCTAssertEqual(page.finances, [:])
        let lignes = page.missions.map { MesMissionsPresentation.ligneAVenir($0, maintenant: DemoWorld.fixedNow) }
        XCTAssertEqual(lignes.map(\.horaire), ["Prochain créneau : 5 nov. · 08h00 → 16h00 (8h)",
                                               "Prochain créneau : 9 nov. · 08h00 → 16h00 (8h)"])
        XCTAssertEqual(lignes.map(\.lieu), ["Établissement fictif République · Paris", "Établissement fictif des Lilas · Les Lilas"])
        XCTAssertEqual(page.missions.map { CalendrierMission.evenements(pour: $0).count }, [1, 2], "créneaux ajoutables au calendrier")
        let suivante = try await port.aVenir(context: DemoWorld.context, page: 1)
        XCTAssertEqual(suivante.missions.map(\.id), ["demo-assignee-001", "demo-assignee-002"], "lecture cumulative : pages 0 et 1")
        XCTAssertFalse(suivante.aSuivre)
    }

    /// Surcharge DEBUG `JOLENE_DEMO_MES_MISSIONS_PAGE` : pages d'une mission pour la recette de
    /// « Charger plus » dans l'interface (`DemoMesMissionsTests.testMesMissionsChargerPlus`).
    func testTaillePageDemoPourLaRecetteDeChargerPlus() async throws {
        let gateway = DemoMesMissionsGateway(taillePage: 1)
        let premiere = try await gateway.aVenir(context: DemoWorld.context, page: 0)
        XCTAssertEqual(premiere.missions.map(\.id), ["demo-assignee-001"])
        XCTAssertTrue(premiere.aSuivre)
        let deux = try await gateway.aVenir(context: DemoWorld.context, page: 1)
        XCTAssertEqual(deux.missions.map(\.id), ["demo-assignee-001", "demo-assignee-002"])
        XCTAssertTrue(deux.aSuivre, "lecture pleine (2 = 2 × 1) : « Charger plus » encore proposé, comme le web")
        let trois = try await gateway.aVenir(context: DemoWorld.context, page: 2)
        XCTAssertEqual(trois.missions.map(\.id), ["demo-assignee-001", "demo-assignee-002"])
        XCTAssertFalse(trois.aSuivre, "lecture incomplète : plus de « Charger plus »")
        let passees = try await gateway.passees(context: DemoWorld.context, page: 0)
        XCTAssertEqual(passees.missions.map(\.id), ["demo-terminee-001"])
        XCTAssertEqual(Set(passees.finances.keys), ["demo-terminee-001"], "colonnes des seules missions lues")
    }

    // MARK: - Recette des états dans l'interface (surcharges DEBUG, revue B8 de T5)

    func testSurchargesAbsentesPortDemoParDefaut() {
        XCTAssertNil(DemoMesMissionsSurcharges.port(environment: [:], clock: FixedClock(DemoWorld.fixedNow)))
        for invalide in ["0", "51", "abc", ""] {
            XCTAssertNil(DemoMesMissionsSurcharges.port(environment: [DemoMesMissionsSurcharges.variableTaillePage: invalide],
                                                        clock: FixedClock(DemoWorld.fixedNow)), "taille « \(invalide) » ignorée")
        }
        XCTAssertNil(DemoMesMissionsSurcharges.port(environment: [DemoMesMissionsSurcharges.variableEchec: "0"],
                                                    clock: FixedClock(DemoWorld.fixedNow)))
        XCTAssertEqual(DemoMesMissionsSurcharges.variableEchec, "JOLENE_FORCE_MES_MISSIONS_ECHEC")
        XCTAssertEqual(DemoMesMissionsSurcharges.variableVide, "JOLENE_FORCE_MES_MISSIONS_VIDE")
        XCTAssertEqual(DemoMesMissionsSurcharges.variableTaillePage, "JOLENE_DEMO_MES_MISSIONS_PAGE")
    }

    func testEchecForcePremiereLectureDeChaqueOngletPuisReprise() async throws {
        let port = try XCTUnwrap(DemoMesMissionsSurcharges.port(environment: [DemoMesMissionsSurcharges.variableEchec: "1"],
                                                                clock: FixedClock(DemoWorld.fixedNow)))
        for lecture in [{ _ = try await port.aVenir(context: DemoWorld.context, page: 0) },
                        { _ = try await port.candidatures(context: DemoWorld.context) },
                        { _ = try await port.passees(context: DemoWorld.context, page: 0) }] as [() async throws -> Void] {
            do {
                try await lecture()
                XCTFail("la première lecture de chaque onglet échoue")
            } catch let error as JoleneError {
                XCTAssertEqual(error, JoleneError(.network, SessionController.timeoutMessage), "panne simulée = délai dépassé")
            }
        }
        let reprise = try await port.aVenir(context: DemoWorld.context, page: 0)
        XCTAssertEqual(reprise.missions.map(\.id), ["demo-assignee-001", "demo-assignee-002"], "« Réessayer » relit la démo")
        let candidatures = try await port.candidatures(context: DemoWorld.context)
        XCTAssertEqual(candidatures.map(\.id), ["demo-candidature-001", "demo-candidature-002"])
    }

    func testSessionExpireeForceePuisRevalidation() async throws {
        let port = try XCTUnwrap(DemoMesMissionsSurcharges.port(environment: [DemoMesMissionsSurcharges.variableEchec: "session"],
                                                                clock: FixedClock(DemoWorld.fixedNow)))
        do {
            _ = try await port.aVenir(context: DemoWorld.context, page: 0)
            XCTFail("la première lecture échoue en session expirée")
        } catch let error as JoleneError {
            XCTAssertEqual(error, JoleneError(.unauthorized, SessionController.sessionExpiredMessage))
        }
        let relue = try await port.aVenir(context: DemoWorld.context, page: 0)
        XCTAssertEqual(relue.missions.count, 2, "après « Vérifier ma session », la lecture aboutit")
    }

    func testEchecForceNonConsommeParUneTacheAnnulee() async throws {
        let port = DemoMesMissionsEchecGateway()
        let annulee = await Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await port.aVenir(context: DemoWorld.context, page: 0)
        }.result
        XCTAssertThrowsError(try annulee.get()) { XCTAssertTrue($0 is CancellationError, "\($0)") }
        do {
            _ = try await port.aVenir(context: DemoWorld.context, page: 0)
            XCTFail("l'échec forcé n'a pas été consommé par la tâche annulée")
        } catch let error as JoleneError {
            XCTAssertEqual(error.kind, .network)
        }
    }

    func testListesVidesForceesEtCombinaisonAvecLEchec() async throws {
        let vide = try XCTUnwrap(DemoMesMissionsSurcharges.port(environment: [DemoMesMissionsSurcharges.variableVide: "1"],
                                                                clock: FixedClock(DemoWorld.fixedNow)))
        let candidatures = try await vide.candidatures(context: DemoWorld.context)
        let aVenir = try await vide.aVenir(context: DemoWorld.context, page: 0)
        let passees = try await vide.passees(context: DemoWorld.context, page: 0)
        XCTAssertEqual(candidatures, [])
        XCTAssertEqual(aVenir.missions, [])
        XCTAssertFalse(aVenir.aSuivre)
        XCTAssertEqual(passees.missions, [])
        XCTAssertEqual(passees.finances, [:])

        let videEnEchec = try XCTUnwrap(DemoMesMissionsSurcharges.port(
            environment: [DemoMesMissionsSurcharges.variableVide: "1", DemoMesMissionsSurcharges.variableEchec: "1"],
            clock: FixedClock(DemoWorld.fixedNow)))
        do {
            _ = try await videEnEchec.aVenir(context: DemoWorld.context, page: 0)
            XCTFail("l'échec forcé précède la liste vide")
        } catch let error as JoleneError {
            XCTAssertEqual(error.kind, .network)
        }
        let apres = try await videEnEchec.aVenir(context: DemoWorld.context, page: 0)
        XCTAssertEqual(apres.missions, [])

        let pagine = try XCTUnwrap(DemoMesMissionsSurcharges.port(environment: [DemoMesMissionsSurcharges.variableTaillePage: "1"],
                                                                  clock: FixedClock(DemoWorld.fixedNow)))
        let premiere = try await pagine.aVenir(context: DemoWorld.context, page: 0)
        XCTAssertEqual(premiere.missions.map(\.id), ["demo-assignee-001"])
        XCTAssertTrue(premiere.aSuivre)
    }

    func testPortsDeRecetteRefusentToutAutreUtilisateur() async {
        let autre = Self.autreContexte()
        let ports: [any MesMissionsPort] = [DemoMesMissionsEchecGateway(), DemoMesMissionsVideGateway()]
        for port in ports {
            for appel in [{ _ = try await port.candidatures(context: autre) },
                          { _ = try await port.aVenir(context: autre, page: 0) },
                          { _ = try await port.passees(context: autre, page: 0) }] as [() async throws -> Void] {
                do {
                    try await appel()
                    XCTFail("la démo ne sert aucun autre utilisateur, même en recette")
                } catch let error as JoleneError {
                    XCTAssertEqual(error, JoleneError(.demoOnly, DemoWorld.messageDemoSeulement))
                } catch {
                    XCTFail("type d'erreur inattendu : \(error)")
                }
            }
        }
    }

    func testPasseesMontantsServeurEtDetailLisible() async throws {
        let page = try await port.passees(context: DemoWorld.context, page: 0)
        XCTAssertEqual(page.missions.map(\.id), ["demo-terminee-001", "demo-terminee-002", "demo-annulee-001"], "`debut_le` décroissant")
        let lignes = page.missions.map { MesMissionsPresentation.lignePassee($0, finance: page.finances[$0.id]) }
        XCTAssertEqual(lignes.map(\.texteAccessible), [
            "Terminée, Démonstration · Mission terminée 1, Établissement fictif République, 1 nov. 2026, Net salarié estimé* : ~162,40\(euro)",
            "Terminée, Démonstration · Mission terminée 2, Établissement fictif des Lilas, 20 oct. → 21 oct. 2026, Honoraires bruts : 448,00\(euro)",
            "Annulée, Démonstration · Mission annulée, Cabinet fictif du Parc, 12 oct. 2026",
        ])
        let detail = try await DemoWorld.gateways().missions.mission(id: "demo-terminee-002", context: DemoWorld.context)
        XCTAssertEqual(detail?.record.statut, "TERMINEE", "une mission passée s'ouvre en détail")
        XCTAssertEqual(detail?.creneauxPlanifies.count, 2)
    }

    private static func autreContexte() -> MissionReadContext {
        var autre = DemoWorld.context
        autre.userId = "user-1"
        autre.profile.id = "user-1"
        return autre
    }

    func testAutreUtilisateurRefuseAvecErreurDemoOnly() async {
        let autre = Self.autreContexte()
        for appel in [{ _ = try await self.port.candidatures(context: autre) },
                      { _ = try await self.port.aVenir(context: autre, page: 0) },
                      { _ = try await self.port.passees(context: autre, page: 0) }] as [() async throws -> Void] {
            do {
                try await appel()
                XCTFail("la démo ne sert aucun autre utilisateur")
            } catch let error as JoleneError {
                XCTAssertEqual(error, JoleneError(.demoOnly, DemoWorld.messageDemoSeulement))
            } catch {
                XCTFail("type d'erreur inattendu : \(error)")
            }
        }
    }

    func testPaginationDeCinquanteCommeLeWeb() {
        let missions = (0..<120).map { index in
            Mission(record: MissionRecord(id: "m-\(index)", intitule: "M", description: nil, service: nil, professionRequise: "IDE",
                                          specialiteMedicaleRequise: nil, accepteNonSpecialises: nil, debutLe: "2026-11-05T07:00:00.000Z",
                                          finLe: "2026-11-05T15:00:00.000Z", dureeHeures: nil, nbCreneaux: 1, tauxHoraireBase: nil,
                                          tauxRistPlafonne: nil, ristPlafondApplique: nil, totalBrut: nil, netAPayer: nil, estUrgente: false,
                                          niveauUrgence: nil, statut: "ASSIGNEE", etablissementId: "e", typeContratRecherche: nil,
                                          boosteeLe: nil, modeRemuneration: nil, retrocessionPct: nil),
                    etablissement: nil, distanceKm: nil, creneauxPlanifies: [], planningExact: false)
        }
        // Lecture cumulative du web (« M1 », `range(0, (page + 1) * 50 - 1)`).
        let premiere = DemoMesMissionsGateway.page(missions, page: 0)
        XCTAssertEqual(premiere.missions.map(\.id).first, "m-0")
        XCTAssertEqual(premiere.missions.count, MissionsPage.taille)
        XCTAssertTrue(premiere.aSuivre, "lecture pleine : « Charger plus » proposé")
        let deuxieme = DemoMesMissionsGateway.page(missions, page: 1)
        XCTAssertEqual(deuxieme.missions.map(\.id), (0..<100).map { "m-\($0)" }, "pages 0 et 1 relues ensemble")
        XCTAssertTrue(deuxieme.aSuivre)
        let troisieme = DemoMesMissionsGateway.page(missions, page: 2)
        XCTAssertEqual(troisieme.missions.map(\.id), (0..<120).map { "m-\($0)" })
        XCTAssertFalse(troisieme.aSuivre, "120 < 150 : lecture incomplète")
        XCTAssertEqual(DemoMesMissionsGateway.page(missions, page: 3).missions.count, 120, "au-delà : toutes les missions, sans suite")
        XCTAssertEqual(DemoMesMissionsGateway.page(missions, page: 1, taille: 60).missions.count, 120)
        XCTAssertTrue(DemoMesMissionsGateway.page(missions, page: 1, taille: 60).aSuivre, "120 = 2 × 60 : lecture pleine")
    }
}
