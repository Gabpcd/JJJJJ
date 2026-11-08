import XCTest
@testable import JoleneCore

/// Modèles Explorer du lot 1 (T4a) : filtres appliqués par le port, chips, réinitialisation,
/// requêtes concurrentes (la dernière gagne, les lectures supplantées sont annulées), état vide
/// rafraîchissable avec les mêmes critères et lectures du lot 0 bornées à `resolutionTimeout`
/// (décision 14 : une seule constante pour lectures et mutations).
@MainActor
final class ExplorerModelsTests: XCTestCase {
    /// Port de missions scripté : enregistre les filtres reçus, peut répondre après un délai,
    /// ne jamais répondre (attente annulable, chaque annulation est comptée) ou échouer.
    private final class PortExplorer: MissionsPort, @unchecked Sendable {
        enum Reponse { case missions([Mission]), mission(Mission?), echec(Error), silence, apres(TimeInterval, [Mission]) }
        private let lock = NSLock()
        private var reponses: [Reponse]
        private var recus: [MissionFilters] = []
        private var appelsDetail = 0
        private var annules = 0

        init(_ reponses: [Reponse]) { self.reponses = reponses }

        var filtresRecus: [MissionFilters] { lock.lock(); defer { lock.unlock() }; return recus }
        var nombreAppels: Int { lock.lock(); defer { lock.unlock() }; return recus.count + appelsDetail }
        /// Attentes muettes (`.silence`) interrompues par une annulation avant leur terme.
        var annulations: Int { lock.lock(); defer { lock.unlock() }; return annules }

        private func suivante(_ filtres: MissionFilters?) -> Reponse {
            lock.lock(); defer { lock.unlock() }
            if let filtres { recus.append(filtres) } else { appelsDetail += 1 }
            return reponses.isEmpty ? .missions([]) : reponses.removeFirst()
        }

        private func compterAnnulation() {
            lock.lock(); defer { lock.unlock() }
            annules += 1
        }

        /// Attente muette de 30 s : seule une annulation l'interrompt, et elle est comptée.
        private func silence() async throws {
            do {
                try await Task.sleep(nanoseconds: 30_000_000_000)
            } catch {
                compterAnnulation()
                throw error
            }
        }

        func profile(userId: String) async throws -> SoignantProfile? {
            SoignantProfile(id: userId, profession: "IDE", adresseLat: 48.85, adresseLng: 2.35, rayonDeplacementKm: 30,
                            tauxHoraireMinimum: 24)
        }

        func listMissions(context: MissionReadContext, filters: MissionFilters) async throws -> [Mission] {
            switch suivante(filters) {
            case let .missions(missions): return missions
            case let .mission(mission): return mission.map { [$0] } ?? []
            case let .echec(error): throw error
            case .silence:
                try await silence()
                return []
            case let .apres(delai, missions):
                try await Task.sleep(nanoseconds: UInt64(delai * 1_000_000_000))
                return missions
            }
        }

        func mission(id: String, context: MissionReadContext) async throws -> Mission? {
            switch suivante(nil) {
            case let .missions(missions): return missions.first
            case let .mission(mission): return mission
            case let .echec(error): throw error
            case .silence:
                try await silence()
                return nil
            case let .apres(delai, missions):
                try await Task.sleep(nanoseconds: UInt64(delai * 1_000_000_000))
                return missions.first
            }
        }
    }

    private struct AuthPrete: AuthPort {
        func restoreSession() async throws -> AuthenticatedUser? {
            AuthenticatedUser(id: "u-1", email: "u-1@example.invalid", emailConfirmedAt: Date(), appMetadataRole: "SOIGNANT")
        }
        func signIn(email: String, password: String) async throws -> AuthenticatedUser { throw JoleneError(.invalidCredentials, "refusé") }
        func signOut() async throws {}
    }

    private func mission(_ id: String) -> Mission {
        let record = MissionRecord(id: id, intitule: "Mission \(id)", description: nil, service: nil, professionRequise: "IDE",
                                   specialiteMedicaleRequise: nil, accepteNonSpecialises: nil, debutLe: "2026-12-01T08:00:00+00:00",
                                   finLe: "2026-12-01T16:00:00+00:00", dureeHeures: 8, nbCreneaux: 1, tauxHoraireBase: 25,
                                   tauxRistPlafonne: nil, ristPlafondApplique: nil, totalBrut: nil, netAPayer: nil, estUrgente: false,
                                   niveauUrgence: nil, statut: "OUVERTE", etablissementId: "e-1", typeContratRecherche: nil,
                                   boosteeLe: nil, modeRemuneration: nil, retrocessionPct: nil)
        return Mission(record: record, etablissement: nil, distanceKm: nil, creneauxPlanifies: [], planningExact: true)
    }

    private func pret(_ port: PortExplorer, timeout: TimeInterval = SessionController.defaultResolutionTimeout) async throws
        -> (SessionController, SessionSnapshot) {
        let controller = SessionController(gateways: Gateways(auth: AuthPrete(), role: NeutralRole(), missions: port),
                                           resolutionTimeout: timeout)
        let state = await controller.start()
        let snapshot = try XCTUnwrap(state.snapshot, "session prête attendue, obtenu \(state)")
        return (controller, snapshot)
    }

    // MARK: Filtres

    func testPremiereLectureEnvoieLesFiltresDuLot0() async throws {
        let port = PortExplorer([.missions([mission("a")])])
        let (controller, snapshot) = try await pret(port)
        let model = MissionsListModel(controller: controller, snapshot: snapshot)
        XCTAssertEqual(model.filtres, ExplorerFiltres.initiaux(profile: snapshot.profile))
        await model.load()
        XCTAssertEqual(port.filtresRecus, [MissionBusiness.defaultFilters(profile: snapshot.profile)])
        XCTAssertEqual(model.missions.map(\.id), ["a"])
        XCTAssertEqual(model.filtres.rayonKm, 30)
        XCTAssertEqual(model.filtres.tauxMin, 24)
    }

    func testFiltresInitiauxPersonnalises() async throws {
        let port = PortExplorer([.missions([])])
        let (controller, snapshot) = try await pret(port)
        let initiaux = ExplorerFiltres.initiaux(profile: snapshot.profile, etablissementId: "etab-7")
        let model = MissionsListModel(controller: controller, snapshot: snapshot, filtresInitiaux: initiaux)
        await model.load()
        XCTAssertEqual(port.filtresRecus.first?.etablissementId, "etab-7")
    }

    func testAppliquerRelitAvecLesNouveauxFiltresEtRemplaceLaListe() async throws {
        let port = PortExplorer([.missions([mission("a"), mission("b")]), .missions([mission("b")])])
        let (controller, snapshot) = try await pret(port)
        let model = MissionsListModel(controller: controller, snapshot: snapshot)
        await model.load()
        var nouveaux = model.filtres
        nouveaux.rayonKm = 5
        nouveaux.typeContrat = .cdd
        await model.appliquer(nouveaux)
        XCTAssertEqual(model.filtres, nouveaux)
        XCTAssertEqual(port.filtresRecus.last, nouveaux.missionFilters)
        XCTAssertEqual(model.missions.map(\.id), ["b"])
        XCTAssertFalse(model.isRefreshing)
        XCTAssertNil(model.refreshError)
    }

    func testAppliquerAfficheLeChargementPuisLEchecSansListePerimee() async throws {
        let port = PortExplorer([.missions([mission("a")]), .echec(JoleneError(.network, "Connexion impossible."))])
        let (controller, snapshot) = try await pret(port)
        let model = MissionsListModel(controller: controller, snapshot: snapshot)
        await model.load()
        // Une liste lue avec d'autres critères n'est jamais présentée sous les nouveaux filtres.
        await model.appliquer(model.filtres.basculantUrgentes())
        XCTAssertEqual(model.state, .failed("Connexion impossible."))
        XCTAssertTrue(model.missions.isEmpty)
        XCTAssertTrue(model.filtres.urgentesOnly, "les filtres choisis restent affichés : « Réessayer » relit avec eux")
        await model.load()
        XCTAssertEqual(port.filtresRecus.last?.urgentesOnly, true)
    }

    func testAppliquerLesMemesFiltresSurUneListeChargeeNeRelitPas() async throws {
        let port = PortExplorer([.missions([mission("a")])])
        let (controller, snapshot) = try await pret(port)
        let model = MissionsListModel(controller: controller, snapshot: snapshot)
        await model.load()
        await model.appliquer(model.filtres)
        XCTAssertEqual(port.nombreAppels, 1)
        XCTAssertEqual(model.missions.map(\.id), ["a"])
    }

    /// Feuille de filtres (`ExplorerFeuilleFiltres`, enchaînement de `MissionsListScreen`) :
    /// « Afficher les missions » ne relit rien tant que la feuille n'est pas fermée, puis relit une
    /// fois avec les critères enregistrés ; « Fermer » ne relit rien et ne change aucun critère.
    func testFeuilleDeFiltresNAppliqueQuApresSaFermeture() async throws {
        let port = PortExplorer([.missions([mission("a"), mission("b")]), .missions([mission("b")])])
        let (controller, snapshot) = try await pret(port)
        let model = MissionsListModel(controller: controller, snapshot: snapshot)
        await model.load()
        let appliques = model.filtres
        var cdd = appliques
        cdd.typeContrat = .cdd

        var feuille = ExplorerFeuilleFiltres()
        feuille.ouvrir(avec: model.filtres)
        XCTAssertEqual(feuille.ouverture?.filtres, appliques)
        feuille.enregistrer(cdd)
        XCTAssertEqual(port.nombreAppels, 1, "aucune lecture pendant la fermeture de la feuille")
        XCTAssertEqual(model.filtres, appliques)
        XCTAssertEqual(model.state, .loaded([mission("a"), mission("b")]))

        feuille.ouverture = nil
        if let nouveaux = feuille.cloturer() { await model.appliquer(nouveaux) }
        XCTAssertEqual(port.nombreAppels, 2)
        XCTAssertEqual(port.filtresRecus.last, cdd.missionFilters)
        XCTAssertEqual(model.filtres, cdd)
        XCTAssertEqual(model.missions.map(\.id), ["b"])

        // « Fermer » : la feuille rouverte part de CDD, son brouillon est abandonné.
        feuille.ouvrir(avec: model.filtres)
        XCTAssertEqual(feuille.ouverture?.filtres, cdd)
        feuille.ouverture = nil
        if let nouveaux = feuille.cloturer() { await model.appliquer(nouveaux) }
        XCTAssertEqual(port.nombreAppels, 2, "« Fermer » ne relit pas")
        XCTAssertEqual(model.filtres, cdd)
        XCTAssertEqual(model.missions.map(\.id), ["b"])
    }

    func testChipsEtReinitialisationPassentParLePort() async throws {
        let port = PortExplorer([])
        let (controller, snapshot) = try await pret(port)
        let model = MissionsListModel(controller: controller, snapshot: snapshot)
        await model.load()
        let urgentes = ExplorerFiltres.chipsRapides[0], nuit = ExplorerFiltres.chipsRapides[2]
        await model.basculer(urgentes)
        XCTAssertEqual(port.filtresRecus.last?.urgentesOnly, true)
        await model.basculer(nuit)
        XCTAssertEqual(port.filtresRecus.last?.horaire, .nuit)
        XCTAssertEqual(port.filtresRecus.last?.urgentesOnly, true)
        await model.basculer(nuit)
        XCTAssertEqual(port.filtresRecus.last?.horaire, .tous)
        await model.reinitialiser()
        XCTAssertEqual(model.filtres, model.filtres.reinitialises(profile: snapshot.profile))
        XCTAssertEqual(port.filtresRecus.last?.urgentesOnly, false)
        XCTAssertEqual(port.filtresRecus.last?.tauxMin, 0, "« Réinitialiser » du web remet le taux à 0")
        XCTAssertEqual(port.filtresRecus.last?.rayonKm, 30)
        await model.appliquer(model.filtres.appliquant(.elargirRayon))
        XCTAssertEqual(port.filtresRecus.last?.rayonKm, 50)
    }

    func testLaDerniereDemandeGagneQuandDeuxLecturesSeChevauchent() async throws {
        let port = PortExplorer([.missions([mission("init")]), .apres(0.4, [mission("lente")]), .missions([mission("rapide")])])
        let (controller, snapshot) = try await pret(port)
        let model = MissionsListModel(controller: controller, snapshot: snapshot)
        await model.load()
        let premiere = model.filtres.basculantUrgentes()
        let seconde = model.filtres.basculantHoraire(.nuit)
        let lente = Task { await model.appliquer(premiere) }
        // Laisse la première lecture partir avant la seconde.
        while port.filtresRecus.count < 2 { await Task.yield() }
        await model.appliquer(seconde)
        XCTAssertEqual(model.missions.map(\.id), ["rapide"])
        await lente.value
        XCTAssertEqual(model.missions.map(\.id), ["rapide"], "la réponse tardive d'anciens filtres est ignorée")
        XCTAssertEqual(model.filtres, seconde)
        XCTAssertFalse(model.isRefreshing)
    }

    func testEpochPerimeAucunAppelAvecFiltres() async throws {
        let port = PortExplorer([.missions([mission("a")])])
        let (controller, snapshot) = try await pret(port)
        let model = MissionsListModel(controller: controller, snapshot: snapshot)
        _ = await controller.signOut()
        await model.appliquer(model.filtres.basculantUrgentes())
        XCTAssertEqual(port.nombreAppels, 0)
        XCTAssertEqual(model.state, .loading)
    }

    // MARK: État vide (revue T4a : « Actualiser » toujours disponible)

    func testEtatVideActualiserRelitAvecLesMemesCriteres() async throws {
        let port = PortExplorer([.missions([]), .missions([mission("publiee")])])
        let (controller, snapshot) = try await pret(port)
        let model = MissionsListModel(controller: controller, snapshot: snapshot)
        await model.load()
        XCTAssertEqual(model.state, .loaded([]))
        // Cas courant : rayon < 100 km et aucune chip → l'action secondaire existe, « Actualiser » aussi.
        XCTAssertEqual(model.filtres.actionEtatVide, .elargirRayon)
        let criteres = model.filtres
        await model.load()
        XCTAssertEqual(port.filtresRecus, [criteres.missionFilters, criteres.missionFilters],
                       "actualiser l'état vide relit le serveur avec les critères affichés")
        XCTAssertEqual(model.filtres, criteres, "actualiser ne touche à aucun critère")
        XCTAssertEqual(model.missions.map(\.id), ["publiee"], "une mission publiée entre-temps apparaît")
        XCTAssertFalse(model.isRefreshing)
        XCTAssertNil(model.refreshError)
    }

    func testEtatVideAvecChipActualiserGardeLaChip() async throws {
        let port = PortExplorer([.missions([mission("a")]), .missions([]), .missions([])])
        let (controller, snapshot) = try await pret(port)
        let model = MissionsListModel(controller: controller, snapshot: snapshot)
        await model.load()
        await model.basculer(ExplorerFiltres.chipsRapides[0])
        XCTAssertEqual(model.state, .loaded([]))
        XCTAssertEqual(model.filtres.actionEtatVide, .effacerFiltresRapides)
        await model.load()
        XCTAssertEqual(port.filtresRecus.count, 3)
        XCTAssertEqual(port.filtresRecus[2], port.filtresRecus[1], "mêmes critères : la chip n'est pas effacée par « Actualiser »")
        XCTAssertEqual(port.filtresRecus[2].urgentesOnly, true)
        XCTAssertEqual(model.state, .loaded([]))
    }

    func testEtatVideActualisationEchoueeExposeLErreurSansQuitterLEtatVide() async throws {
        let port = PortExplorer([.missions([]), .echec(JoleneError(.network, "Connexion impossible."))])
        let (controller, snapshot) = try await pret(port)
        let model = MissionsListModel(controller: controller, snapshot: snapshot)
        await model.load()
        await model.load()
        XCTAssertEqual(model.state, .loaded([]), "l'état vide reste affiché pendant et après l'actualisation")
        XCTAssertEqual(model.refreshError, "Connexion impossible.", "l'échec est exposé, l'écran l'affiche à l'état vide aussi")
        XCTAssertFalse(model.isRefreshing)
    }

    // MARK: Lectures supplantées (revue T4a : rafale de chips)

    func testUneLectureSupplanteeEstAnnuleeSansAttendreLeDelai() async throws {
        let port = PortExplorer([.missions([mission("init")]), .silence, .silence, .missions([mission("derniere")])])
        let (controller, snapshot) = try await pret(port)
        let model = MissionsListModel(controller: controller, snapshot: snapshot)
        await model.load()
        let debut = Date()
        // Rafale de trois chips : les deux premières lectures sont supplantées par la troisième.
        let premiere = Task { await model.basculer(ExplorerFiltres.chipsRapides[0]) }
        while port.filtresRecus.count < 2 { await Task.yield() }
        let seconde = Task { await model.basculer(ExplorerFiltres.chipsRapides[1]) }
        while port.filtresRecus.count < 3 { await Task.yield() }
        await model.basculer(ExplorerFiltres.chipsRapides[2])
        await premiere.value
        await seconde.value
        XCTAssertLessThan(Date().timeIntervalSince(debut), 5,
                          "les lectures supplantées sont annulées, pas laissées courir jusqu'au délai de 15 s")
        XCTAssertEqual(port.annulations, 2, "chaque lecture supplantée est interrompue côté port (requête annulée)")
        XCTAssertEqual(model.missions.map(\.id), ["derniere"])
        XCTAssertEqual(model.filtres.horaire, .nuit)
        XCTAssertTrue(model.filtres.urgentesOnly)
        XCTAssertFalse(model.isRefreshing)
        XCTAssertNil(model.refreshError)
    }

    func testUnRafraichissementSupplanteParUnFiltreEstAnnule() async throws {
        let port = PortExplorer([.missions([mission("a")]), .silence, .missions([mission("b")])])
        let (controller, snapshot) = try await pret(port)
        let model = MissionsListModel(controller: controller, snapshot: snapshot)
        await model.load()
        let debut = Date()
        let rafraichissement = Task { await model.load() }
        while port.filtresRecus.count < 2 { await Task.yield() }
        await model.appliquer(model.filtres.basculantUrgentes())
        await rafraichissement.value
        XCTAssertLessThan(Date().timeIntervalSince(debut), 5)
        XCTAssertEqual(port.annulations, 1)
        XCTAssertEqual(model.missions.map(\.id), ["b"])
        XCTAssertNil(model.refreshError, "une lecture supplantée n'est jamais une erreur")
        XCTAssertFalse(model.isRefreshing)
    }

    // MARK: Lectures bornées (décision 14)

    func testListeBorneeAuDelaiDeResolution() async throws {
        let port = PortExplorer([.silence])
        let (controller, snapshot) = try await pret(port, timeout: 0.2)
        let model = MissionsListModel(controller: controller, snapshot: snapshot)
        let debut = Date()
        await model.load()
        XCTAssertLessThan(Date().timeIntervalSince(debut), 5, "un port muet ne retient pas l'écran")
        XCTAssertEqual(model.state, .failed(SessionController.timeoutMessage))
        XCTAssertFalse(model.sessionExpired, "un délai dépassé n'est pas une session expirée")
    }

    func testRafraichissementBorneConserveLaListe() async throws {
        let port = PortExplorer([.missions([mission("a")]), .silence])
        let (controller, snapshot) = try await pret(port, timeout: 0.2)
        let model = MissionsListModel(controller: controller, snapshot: snapshot)
        await model.load()
        await model.load()
        XCTAssertEqual(model.missions.map(\.id), ["a"])
        XCTAssertEqual(model.refreshError, SessionController.timeoutMessage)
        XCTAssertFalse(model.isRefreshing)
    }

    func testDetailBorneAuDelaiDeResolution() async throws {
        let port = PortExplorer([.silence, .silence])
        let (controller, snapshot) = try await pret(port, timeout: 0.2)
        let sansValeur = MissionDetailModel(missionId: "a", initial: nil, controller: controller, snapshot: snapshot)
        await sansValeur.load()
        XCTAssertEqual(sansValeur.errorMessage, SessionController.timeoutMessage)
        XCTAssertFalse(sansValeur.isLoading)
        XCTAssertFalse(sansValeur.sessionExpired)
        let avecValeur = MissionDetailModel(missionId: "a", initial: mission("a"), controller: controller, snapshot: snapshot)
        await avecValeur.load()
        XCTAssertEqual(avecValeur.mission?.id, "a", "la valeur de la liste reste affichée")
        XCTAssertNil(avecValeur.errorMessage)
    }

    func testAnnulationDeLAppelantNEstPasUnDelaiDepasse() async throws {
        let port = PortExplorer([.silence])
        let (controller, snapshot) = try await pret(port)
        let model = MissionsListModel(controller: controller, snapshot: snapshot)
        let tache = Task { await model.load() }
        while port.filtresRecus.isEmpty { await Task.yield() }
        let debut = Date()
        tache.cancel()
        await tache.value
        XCTAssertLessThan(Date().timeIntervalSince(debut), 5, "l'annulation de la vue interrompt la lecture sans attendre le délai")
        XCTAssertEqual(port.annulations, 1, "la requête en vol est annulée côté port")
        XCTAssertEqual(model.state, .loading, "vue disparue : ni erreur ni message de délai, `.task` relancera")
        XCTAssertNil(model.refreshError)
    }
}
