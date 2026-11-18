import XCTest
@testable import JoleneCore

/// Modèles de la liste et du détail des missions établissement (lot 5, T5) : mêmes règles d'état que
/// `MesMissionsModel` (lecture cumulative, filtre relu en première page, relecture sans démontage, annulation jamais
/// affichée en erreur), détail en trois temps (mission, planning porté par la gateway, soignant en lecture
/// secondaire). Session établissement réelle du monde démo (`DemoWorld.gateways(espace:)`, espace ouvert), port des
/// missions scripté.
@MainActor
final class EtabMissionsModelTests: XCTestCase {
    private struct PanneTest: Error {}

    /// Port scripté : chaque appel consomme l'étape suivante et s'inscrit au journal.
    private final class Script: EtabMissionsPort, @unchecked Sendable {
        enum Etape {
            case page(EtabMissionsPage)
            case detail(EtabMissionDetail?)
            case soignant(SoignantPourEtab?)
            case echec(Error)
        }
        private let lock = NSLock()
        private var etapes: [Etape]
        private var journal: [String] = []

        init(_ etapes: [Etape]) { self.etapes = etapes }

        var appels: [String] { lock.withLock { journal } }

        private func suivante(_ appel: String) -> Etape {
            lock.withLock {
                journal.append(appel)
                return etapes.isEmpty ? .echec(PanneTest()) : etapes.removeFirst()
            }
        }

        func missions(context: EtablissementReadContext, statut: String?, page: Int) async throws -> EtabMissionsPage {
            switch suivante("missions \(statut ?? "toutes") \(page)") {
            case let .page(lue): return lue
            case let .echec(erreur): throw erreur
            default: throw PanneTest()
            }
        }

        func mission(id: String, context: EtablissementReadContext) async throws -> EtabMissionDetail? {
            switch suivante("mission \(id)") {
            case let .detail(lu): return lu
            case let .echec(erreur): throw erreur
            default: throw PanneTest()
            }
        }

        func soignant(id: String, context: EtablissementReadContext) async throws -> SoignantPourEtab? {
            switch suivante("soignant \(id)") {
            case let .soignant(lu): return lu
            case let .echec(erreur): throw erreur
            default: throw PanneTest()
            }
        }
    }

    /// Port dont la deuxième lecture du détail reste en vol jusqu'à `liberer()` (revue B8 de #1162, m6).
    private final class DetailRetenu: EtabMissionsPort, @unchecked Sendable {
        private let lock = NSLock()
        private var lectures = 0
        private var attente: CheckedContinuation<Void, Never>?
        private var libere = false
        private let premier: EtabMissionDetail
        private let second: EtabMissionDetail
        private let lu: SoignantPourEtab

        init(premier: EtabMissionDetail, second: EtabMissionDetail, soignant: SoignantPourEtab) {
            self.premier = premier; self.second = second; lu = soignant
        }

        var enAttente: Bool { lock.withLock { attente != nil } }

        func liberer() {
            let suite: CheckedContinuation<Void, Never>? = lock.withLock {
                libere = true
                defer { attente = nil }
                return attente
            }
            suite?.resume()
        }

        func missions(context: EtablissementReadContext, statut: String?, page: Int) async throws -> EtabMissionsPage {
            throw PanneTest()
        }

        func mission(id: String, context: EtablissementReadContext) async throws -> EtabMissionDetail? {
            let rang: Int = lock.withLock { lectures += 1; return lectures }
            guard rang > 1 else { return premier }
            await withCheckedContinuation { (suite: CheckedContinuation<Void, Never>) in
                let deja: Bool = lock.withLock {
                    if libere { return true }
                    attente = suite
                    return false
                }
                if deja { suite.resume() }
            }
            return second
        }

        func soignant(id: String, context: EtablissementReadContext) async throws -> SoignantPourEtab? { lu }
    }

    private func pret(_ port: any EtabMissionsPort) async throws -> (SessionController, EtablissementSessionSnapshot) {
        var gateways = DemoWorld.gateways(espace: .etablissement(.init()))
        gateways.etablissement.missions = port
        let controller = SessionController(gateways: gateways, espaceEtablissement: .ouvert)
        _ = await controller.start()
        let etat = await controller.signIn(email: DemoEspace.emailEtablissement, password: "demo")
        guard case let .readyEtablissement(snapshot) = etat else {
            XCTFail("espace établissement démo attendu, obtenu \(etat)")
            throw PanneTest()
        }
        return (controller, snapshot)
    }

    private func ligne(_ id: String, statut: String = "OUVERTE") -> EtabMissionResume {
        EtabMissionResume(id: id, intitule: "Mission \(id)", statut: statut, debutLe: "2026-11-05T06:00:00.000Z",
                          finLe: "2026-11-05T14:00:00.000Z", nbCreneaux: 1, etablissementId: "demo-etab-1")
    }

    private func page(_ ids: [String], numero: Int = 0, aSuivre: Bool = false,
                      compteurs: EtabMissionsCompteurs? = EtabMissionsCompteurs(statuts: ["OUVERTE"])) -> EtabMissionsPage {
        EtabMissionsPage(missions: ids.map { ligne($0) }, page: numero, aSuivre: aSuivre, compteurs: compteurs,
                         candidaturesEnAttente: ids.first.map { [$0: 2] } ?? [:])
    }

    // MARK: - Liste

    func testPremiereLectureFiltreParDefautEtCompteurs() async throws {
        let port = Script([.page(page(["m-1", "m-2"]))])
        let (controller, snapshot) = try await pret(port)
        let model = EtabMissionsModel(controller: controller, snapshot: snapshot)
        XCTAssertEqual(model.filtre, .toutes, "« Toutes » par défaut, comme le web")
        XCTAssertEqual(model.contenu, .chargement)
        await model.charger()
        XCTAssertEqual(model.missions.map(\.id), ["m-1", "m-2"])
        XCTAssertEqual(model.compteurs?.nombre(.ouvertes), 1)
        XCTAssertEqual(model.carte(ligne("m-1")).badges.map(\.texte).contains("2 candidatures à traiter"), true)
        XCTAssertFalse(model.peutChargerPlus)
        XCTAssertEqual(port.appels, ["missions toutes 0"])
    }

    func testFiltreRelitLaPremierePageEtChargerPlusEstCumulatif() async throws {
        let port = Script([.page(page(["m-1"], aSuivre: true)), .page(page(["m-1", "m-2"], numero: 1)),
                           .page(page(["m-3"], compteurs: nil))])
        let (controller, snapshot) = try await pret(port)
        let model = EtabMissionsModel(controller: controller, snapshot: snapshot)
        await model.charger()
        XCTAssertTrue(model.peutChargerPlus)
        await model.chargerPlus()
        XCTAssertEqual(model.missions.map(\.id), ["m-1", "m-2"], "pages 0…1 relues d'un tenant, liste remplacée")
        XCTAssertEqual(model.page, 1)
        XCTAssertFalse(model.peutChargerPlus, "dernière lecture non pleine")
        await model.chargerPlus()
        await model.selectionner(.terminees)
        XCTAssertEqual(model.filtre, .terminees)
        XCTAssertEqual(model.missions.map(\.id), ["m-3"])
        XCTAssertEqual(model.page, 0)
        XCTAssertEqual(model.compteurs?.nombre(.ouvertes), 1, "compteurs non relus : les derniers connus restent")
        XCTAssertEqual(port.appels, ["missions toutes 0", "missions toutes 1", "missions TERMINEE 0"])
    }

    func testEchecPremiereLectureEtRelectureConservantLaListe() async throws {
        let port = Script([.echec(JoleneError(.network, "Réseau indisponible.")), .page(page(["m-1"])),
                           .echec(JoleneError(.network, "Réseau indisponible.")), .echec(CancellationError())])
        let (controller, snapshot) = try await pret(port)
        let model = EtabMissionsModel(controller: controller, snapshot: snapshot)
        await model.charger()
        XCTAssertEqual(model.contenu, .echec("Réseau indisponible."))
        await model.charger()
        XCTAssertEqual(model.missions.map(\.id), ["m-1"])
        await model.charger()
        XCTAssertEqual(model.missions.map(\.id), ["m-1"], "relecture en échec : liste conservée")
        XCTAssertEqual(model.erreurRafraichissement, "Réseau indisponible.")
        XCTAssertFalse(model.rafraichissement)
        await model.charger()
        XCTAssertNil(model.erreurRafraichissement, "une annulation n'est jamais une erreur")
        XCTAssertEqual(model.missions.map(\.id), ["m-1"])
    }

    /// Intégration de la vague C (revue B8 de #1162, m2) : après l'échec d'un changement de filtre, la pastille du
    /// nouveau filtre n'est jamais posée sur l'ancienne liste ; le même filtre relu garde la sienne.
    func testEchecDUnChangementDeFiltreNAfficheJamaisLAncienneListe() async throws {
        let port = Script([.page(page(["m-1", "m-2"], aSuivre: true)), .page(page(["m-1", "m-2"])),
                           .echec(JoleneError(.network, "Réseau indisponible.")),
                           .page(page(["m-3"])), .echec(JoleneError(.network, "Réseau indisponible."))])
        let (controller, snapshot) = try await pret(port)
        let model = EtabMissionsModel(controller: controller, snapshot: snapshot)
        await model.charger()
        await model.chargerPlus()
        XCTAssertEqual(model.page, 1)
        await model.selectionner(.ouvertes)
        XCTAssertEqual(model.filtre, .ouvertes)
        XCTAssertEqual(model.contenu, .echec("Réseau indisponible."), "nouveau filtre en échec : jamais l'ancienne liste")
        XCTAssertTrue(model.missions.isEmpty)
        XCTAssertNil(model.erreurRafraichissement)
        XCTAssertFalse(model.rafraichissement)
        await model.charger()
        XCTAssertEqual(model.missions.map(\.id), ["m-3"], "« Réessayer » relit le nouveau filtre en première page")
        await model.selectionner(.ouvertes)
        XCTAssertEqual(model.missions.map(\.id), ["m-3"], "même filtre relu en échec : sa liste reste affichée")
        XCTAssertEqual(model.erreurRafraichissement, "Réseau indisponible.")
        XCTAssertEqual(port.appels, ["missions toutes 0", "missions toutes 1", "missions OUVERTE 0", "missions OUVERTE 0",
                                     "missions OUVERTE 0"])
    }

    // MARK: - Détail

    func testDetailPuisSoignantEnLectureSecondaire() async throws {
        let detail = EtabMissionDetail(mission: ligne("m-4", statut: "ASSIGNEE"), creneaux: [], soignantAssigneId: "s-1")
        let soignant = SoignantPourEtab(id: "s-1", prenom: "Camille", nom: "Démo", profession: "IDE")
        let port = Script([.detail(detail), .echec(JoleneError(.network, "Réseau indisponible.")), .soignant(soignant)])
        let (controller, snapshot) = try await pret(port)
        let model = EtabMissionDetailModel(missionId: "m-4", controller: controller, snapshot: snapshot)
        await model.charger()
        XCTAssertEqual(model.detail, detail, "l'échec du soignant n'efface jamais la mission")
        XCTAssertEqual(model.soignant, .echec("Réseau indisponible."))
        await model.rechargerSoignant()
        XCTAssertEqual(model.soignant, .charge(soignant))
        XCTAssertEqual(port.appels, ["mission m-4", "soignant s-1", "soignant s-1"])
    }

    /// Intégration de la vague C (revue B8 de #1162, m6) : « Réessayer » du soignant pendant une relecture de la mission
    /// ne l'abandonne plus ; sa réponse est publiée et `rafraichissement` retombe à faux.
    func testRelectureDuSoignantNAbandonneJamaisLaRelectureDeLaMission() async throws {
        let premier = EtabMissionDetail(mission: ligne("m-6", statut: "ASSIGNEE"), creneaux: [], soignantAssigneId: "s-1")
        var relue = ligne("m-6", statut: "ASSIGNEE")
        relue.intitule = "Mission m-6 relue"
        let second = EtabMissionDetail(mission: relue, creneaux: [], soignantAssigneId: "s-1")
        let soignant = SoignantPourEtab(id: "s-1", prenom: "Camille", nom: "Démo", profession: "IDE")
        let port = DetailRetenu(premier: premier, second: second, soignant: soignant)
        let (controller, snapshot) = try await pret(port)
        let model = EtabMissionDetailModel(missionId: "m-6", controller: controller, snapshot: snapshot)
        await model.charger()
        XCTAssertEqual(model.detail, premier)

        let relecture = Task { await model.charger() }
        var tours = 0
        while !port.enAttente, tours < 2_000 {
            tours += 1
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertTrue(port.enAttente, "la relecture de la mission est en vol")
        XCTAssertTrue(model.rafraichissement)
        await model.rechargerSoignant()
        XCTAssertEqual(model.soignant, .charge(soignant))
        port.liberer()
        await relecture.value
        XCTAssertEqual(model.detail, second, "la relecture en vol de la mission est publiée, jamais abandonnée")
        XCTAssertFalse(model.rafraichissement, "rafraîchissement remis à faux")
        XCTAssertEqual(model.soignant, .charge(soignant))
    }

    func testDetailIntrouvableSoignantSupprimeEtRelectureEnEchec() async throws {
        let libre = EtabMissionDetail(mission: ligne("m-1"), creneaux: [], soignantAssigneId: nil)
        let assignee = EtabMissionDetail(mission: ligne("m-5", statut: "ASSIGNEE"), creneaux: [], soignantAssigneId: "s-x")
        let port = Script([.detail(nil), .detail(libre), .detail(assignee), .soignant(nil),
                           .echec(JoleneError(.network, "Réseau indisponible."))])
        let (controller, snapshot) = try await pret(port)
        let introuvable = EtabMissionDetailModel(missionId: "x", controller: controller, snapshot: snapshot)
        await introuvable.charger()
        XCTAssertEqual(introuvable.etat, .introuvable)
        let ouverte = EtabMissionDetailModel(missionId: "m-1", controller: controller, snapshot: snapshot)
        await ouverte.charger()
        XCTAssertEqual(ouverte.soignant, .aucun, "aucun soignant assigné : aucune lecture")
        let model = EtabMissionDetailModel(missionId: "m-5", controller: controller, snapshot: snapshot)
        await model.charger()
        XCTAssertEqual(model.soignant, .indisponible, "null SQL : « Soignant indisponible », jamais un profil vide")
        await model.charger()
        XCTAssertEqual(model.detail, assignee, "relecture en échec : mission conservée")
        XCTAssertEqual(model.erreurRafraichissement, "Réseau indisponible.")
        XCTAssertEqual(port.appels, ["mission x", "mission m-1", "mission m-5", "soignant s-x", "mission m-5"])
    }
}
