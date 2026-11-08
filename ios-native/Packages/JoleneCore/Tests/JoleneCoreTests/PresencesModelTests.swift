import XCTest
@testable import JoleneCore

/// Utilisateur restauré par les ports d'auth de ces tests (hors du main actor : lu par les ports).
private let utilisateurPresences = AuthenticatedUser(id: "u-1", email: "u-1@example.invalid",
                                                     emailConfirmedAt: Date(timeIntervalSince1970: 1_700_000_000),
                                                     appMetadataRole: "SOIGNANT")

/// Modèle de la page Présences (lot 2, T4a ; parité `src/pages/PresencesSoignant.tsx`) : instantané lu par
/// `gateways.pointage.presences(context:)`, onglet initial dérivé (`?tab=` puis Aujourd'hui → Actives → À venir,
/// l.276-278) posé au premier chargement réussi et jamais recalculé ensuite (onglet choisi conservé), listes dérivées
/// de l'horloge figée du chargement (`chargeLe`), historique filtré par `?filtre=a_valider` (l.279-288), relecture
/// à l'apparition au-delà de 60 s (`staleTime: 60_000`, l.262), et les règles d'état du lot 1 (`AccueilModel`) :
/// annulation jamais affichée en erreur, rafraîchissement sans démontage, session expirée, epoch périmé ignoré.
/// Aucun texte n'est produit par le modèle : un échec porte le message du port, ou aucun.
@MainActor
final class PresencesModelTests: XCTestCase {
    private struct ModelError: Error {}

    /// Port de pointage scripté : seul `presences` répond ; chaque appel consomme une étape. Les autres méthodes
    /// refusent (elles ne sont jamais appelées par la page des présences).
    private final class PortPresences: PointagePort, @unchecked Sendable {
        enum Etape {
            case instantane(InstantanePresences), echec(Error)
            /// `entree` s'ouvre à l'appel ; la réponse attend l'ouverture de `sortie`.
            case retenue(InstantanePresences, entree: Gate, sortie: Gate)
        }
        private let lock = NSLock()
        private var etapes: [Etape]
        private var appels = 0

        init(_ etapes: [Etape]) { self.etapes = etapes }

        var calls: Int { lock.lock(); defer { lock.unlock() }; return appels }

        private func suivante() -> Etape {
            lock.lock(); defer { lock.unlock() }
            appels += 1
            return etapes.isEmpty ? .instantane(InstantanePresences()) : etapes.removeFirst()
        }

        private var refus: JoleneError { JoleneError(.contract, "jamais appelé par la page des présences") }

        func presences(context: MissionReadContext) async throws -> InstantanePresences {
            switch suivante() {
            case let .instantane(instantane): return instantane
            case let .echec(error): throw error
            case let .retenue(instantane, entree, sortie):
                await entree.open()
                await sortie.wait()
                return instantane
            }
        }
        func etat(missionId: String, context: MissionReadContext) async throws -> EtatPointage { throw refus }
        func consentementGps(context: MissionReadContext) async throws -> Bool? { throw refus }
        func enregistrerConsentementGps(_ accepte: Bool, context: MissionReadContext) async throws -> Bool { throw refus }
        func scanner(code: String, metadonnees: MetadonneesScan, recu: RecuScan,
                     context: MissionReadContext) async throws -> IssueScan { throw refus }
        func reconcilier(recu: RecuScan, context: MissionReadContext) async throws -> IssueScan { throw refus }
        func detail(missionId: String, context: MissionReadContext) async throws -> DetailPresences { throw refus }
        func relancerValidation(missionId: String, context: MissionReadContext) async throws -> IssueRelance { throw refus }
    }

    /// Horloge que le test fait avancer (relecture au-delà de 60 s).
    private final class HorlogeReglable: ClockPort, @unchecked Sendable {
        private let lock = NSLock()
        private var instant: Date
        init(_ instant: Date) { self.instant = instant }
        func now() -> Date { lock.lock(); defer { lock.unlock() }; return instant }
        func avancer(_ secondes: TimeInterval) { lock.lock(); instant += secondes; lock.unlock() }
    }

    private struct PretAuth: AuthPort {
        func restoreSession() async throws -> AuthenticatedUser? { utilisateurPresences }
        func signIn(email: String, password: String) async throws -> AuthenticatedUser { throw ModelError() }
        func signOut() async throws {}
    }

    private struct PretMissions: MissionsPort {
        func profile(userId: String) async throws -> SoignantProfile? { SoignantProfile(id: userId, profession: "IDE") }
        func listMissions(context: MissionReadContext, filters: MissionFilters) async throws -> [Mission] { [] }
        func mission(id: String, context: MissionReadContext) async throws -> Mission? { nil }
    }

    private let maintenant = DemoWorld.fixedNow // 2026-11-02T00:00:00Z = lundi 2 novembre, 01h00 à Paris

    private func pret(_ port: PortPresences, horloge: ClockPort = FixedClock(DemoWorld.fixedNow))
        async throws -> (SessionController, SessionSnapshot) {
        var gateways = Gateways(auth: PretAuth(), role: NeutralRole(), missions: PretMissions(), clock: horloge)
        gateways.pointage = port
        let controller = SessionController(gateways: gateways)
        let state = await controller.start()
        let snapshot = try XCTUnwrap(state.snapshot, "session prête attendue, obtenu \(state)")
        return (controller, snapshot)
    }

    // MARK: - Instantanés de test

    private func mission(_ id: String, statut: String, debut: String, fin: String) -> MissionPresenceLue {
        MissionPresenceLue(id: id, intitule: "Mission \(id)", debutLe: debut, finLe: fin, dureeHeures: 8, statut: statut,
                           etablissementId: "etab-1")
    }

    private func prevu(_ missionId: String, _ debut: String, _ fin: String) -> MissionSlot {
        MissionSlot(id: "\(missionId)-prevu", missionId: missionId, debut: debut, fin: fin, estPause: false, typeCreneau: "PREVISIONNEL")
    }

    /// Mission du jour (créneau 01h05-09h05 à Paris) : onglet initial Aujourd'hui.
    private var avecMissionDuJour: InstantanePresences {
        InstantanePresences(missions: [mission("m-jour", statut: "ASSIGNEE", debut: "2026-11-02T00:05:00Z", fin: "2026-11-02T08:05:00Z")],
                            creneaux: [prevu("m-jour", "2026-11-02T00:05:00Z", "2026-11-02T08:05:00Z")],
                            chargeLe: maintenant)
    }

    /// Mission EN_COURS sans créneau du jour : onglet initial Actives.
    private var avecMissionEnCoursSeulement: InstantanePresences {
        InstantanePresences(missions: [mission("m-cours", statut: "EN_COURS", debut: "2026-11-05T07:00:00Z", fin: "2026-11-09T15:00:00Z")],
                            creneaux: [prevu("m-cours", "2026-11-05T07:00:00Z", "2026-11-05T15:00:00Z")],
                            chargeLe: maintenant)
    }

    /// Historique : une présence validée, une à valider (départ pointé), une sans départ.
    private var avecHistorique: InstantanePresences {
        let validee = PresenceLue(id: "p-ok", missionId: "h-1", soignantId: "u-1", pointageArriveeLe: "2026-10-31T07:00:00Z",
                                  pointageDepartLe: "2026-10-31T15:00:00Z", valideParEtablissement: true,
                                  valideLe: "2026-11-01T14:00:00Z")
        let aValider = PresenceLue(id: "p-attente", missionId: "h-2", soignantId: "u-1", pointageArriveeLe: "2026-10-30T07:00:00Z",
                                   pointageDepartLe: "2026-10-30T15:00:00Z", valideParEtablissement: false)
        let sansDepart = PresenceLue(id: "p-ouverte", missionId: "h-3", soignantId: "u-1", pointageArriveeLe: "2026-10-29T07:00:00Z",
                                     valideParEtablissement: false)
        return InstantanePresences(historique: [validee, aValider, sansDepart], chargeLe: maintenant)
    }

    // MARK: - Chargement et onglet initial

    func testChargementPublieLInstantaneEtOngletInitialAujourdhui() async throws {
        let port = PortPresences([.instantane(avecMissionDuJour)])
        let (controller, snapshot) = try await pret(port)
        let model = PresencesModel(controller: controller, snapshot: snapshot)
        XCTAssertEqual(model.state, .loading)
        XCTAssertNil(model.onglet, "aucun onglet avant le premier chargement (le web affiche le chargement)")
        await model.load()
        XCTAssertEqual(model.instantane, avecMissionDuJour)
        XCTAssertEqual(model.onglet, .aujourdhui)
        XCTAssertEqual(model.listes?.missionsAujourdhui.map(\.mission.id), ["m-jour"])
        XCTAssertEqual(model.chargeLe, maintenant, "instant de l'horloge des gateways")
        XCTAssertFalse(model.sessionExpired)
        XCTAssertEqual(port.calls, 1)
    }

    func testOngletInitialActivesPuisAVenirPuisParametreDuLien() async throws {
        let enCours = try await pret(PortPresences([.instantane(avecMissionEnCoursSeulement)]))
        let modelEnCours = PresencesModel(controller: enCours.0, snapshot: enCours.1)
        await modelEnCours.load()
        XCTAssertEqual(modelEnCours.onglet, .encours, "aucune mission du jour mais une mission en cours")

        let vide = try await pret(PortPresences([.instantane(InstantanePresences(chargeLe: maintenant))]))
        let modelVide = PresencesModel(controller: vide.0, snapshot: vide.1)
        await modelVide.load()
        XCTAssertEqual(modelVide.onglet, .avenir, "ni mission du jour ni mission en cours")

        let lien = try await pret(PortPresences([.instantane(avecMissionDuJour)]))
        let modelLien = PresencesModel(controller: lien.0, snapshot: lien.1, parametreOnglet: "historique")
        await modelLien.load()
        XCTAssertEqual(modelLien.onglet, .historique, "`?tab=` du lien d'abord, valeurs exactes du web")

        let inconnu = try await pret(PortPresences([.instantane(avecMissionDuJour)]))
        let modelInconnu = PresencesModel(controller: inconnu.0, snapshot: inconnu.1, parametreOnglet: "planning")
        await modelInconnu.load()
        XCTAssertEqual(modelInconnu.onglet, .aujourdhui, "valeur inconnue : onglet dérivé (écart assumé, blueprint T4a)")
    }

    func testOngletChoisiConserveApresUneRelecture() async throws {
        let port = PortPresences([.instantane(avecMissionDuJour), .instantane(avecMissionEnCoursSeulement)])
        let (controller, snapshot) = try await pret(port)
        let model = PresencesModel(controller: controller, snapshot: snapshot)
        await model.load()
        model.choisir(.historique)
        XCTAssertEqual(model.onglet, .historique)
        await model.load()
        XCTAssertEqual(model.onglet, .historique, "l'onglet initial n'est posé qu'une fois (`defaultValue` des onglets du web)")
        XCTAssertEqual(model.listes?.missionsEnCours.map(\.mission.id), ["m-cours"], "les listes suivent la relecture")
    }

    func testEtatVide() async throws {
        let (controller, snapshot) = try await pret(PortPresences([.instantane(InstantanePresences(chargeLe: maintenant))]))
        let model = PresencesModel(controller: controller, snapshot: snapshot)
        await model.load()
        let listes = try XCTUnwrap(model.listes)
        XCTAssertTrue(listes.missionsAujourdhui.isEmpty)
        XCTAssertTrue(listes.missionsAVenir.isEmpty)
        XCTAssertTrue(listes.missionsEnCours.isEmpty)
        XCTAssertTrue(model.historique.isEmpty)
        XCTAssertTrue(model.presencesValidees.isEmpty)
        XCTAssertEqual(model.onglet, .avenir)
    }

    func testListesDeriveesDeLHorlogeFigeeDuChargement() async throws {
        // L'instantané a été lu le 1er novembre à 23h00 à Paris : la mission du 2 novembre n'est pas « du jour ».
        var instantane = avecMissionDuJour
        instantane.chargeLe = Date(timeIntervalSince1970: 1_793_570_400) // 2026-11-01T22:00:00Z
        let (controller, snapshot) = try await pret(PortPresences([.instantane(instantane)]))
        let model = PresencesModel(controller: controller, snapshot: snapshot)
        await model.load()
        XCTAssertEqual(model.listes?.missionsAujourdhui.map(\.mission.id), [], "horloge figée au début du chargement (l.107)")
        XCTAssertEqual(model.listes?.missionsAVenir.map(\.mission.id), ["m-jour"])
        XCTAssertEqual(model.onglet, .avenir)
    }

    func testHistoriqueEtFiltreAValider() async throws {
        let tout = try await pret(PortPresences([.instantane(avecHistorique)]))
        let modelTout = PresencesModel(controller: tout.0, snapshot: tout.1)
        await modelTout.load()
        XCTAssertEqual(modelTout.historique.map(\.id), ["p-ok", "p-attente", "p-ouverte"], "tri par date décroissante")
        XCTAssertFalse(modelTout.aValider)

        let filtre = try await pret(PortPresences([.instantane(avecHistorique)]))
        let modelFiltre = PresencesModel(controller: filtre.0, snapshot: filtre.1, parametreFiltre: "a_valider")
        await modelFiltre.load()
        XCTAssertTrue(modelFiltre.aValider)
        XCTAssertEqual(modelFiltre.historique.map(\.id), ["p-attente"], "départ pointé et non validée seulement (l.284-288)")

        let autre = try await pret(PortPresences([.instantane(avecHistorique)]))
        let modelAutre = PresencesModel(controller: autre.0, snapshot: autre.1, parametreFiltre: "valides")
        XCTAssertFalse(modelAutre.aValider, "seule la valeur exacte `a_valider` filtre")
    }

    // MARK: - Erreurs, réessai, annulation, session

    func testEchecPuisReessai() async throws {
        let port = PortPresences([.echec(JoleneError(.network, "Connexion impossible.")), .echec(ModelError()),
                                  .instantane(avecMissionDuJour)])
        let (controller, snapshot) = try await pret(port)
        let model = PresencesModel(controller: controller, snapshot: snapshot)
        await model.load()
        XCTAssertEqual(model.state, .failed(PresencesModel.Echec(message: "Connexion impossible.")), "message du port tel quel")
        XCTAssertNil(model.onglet)
        await model.load()
        XCTAssertEqual(model.state, .failed(PresencesModel.Echec(message: nil)),
                       "erreur sans message lisible : aucun texte inventé, l'écran n'affiche que son titre")
        await model.load()
        XCTAssertEqual(model.instantane, avecMissionDuJour, "« Réessayer » relit l'instantané")
        XCTAssertEqual(model.onglet, .aujourdhui)
        XCTAssertEqual(port.calls, 3)
    }

    func testRafraichissementConserveLInstantaneEnCasDEchecOuDAnnulation() async throws {
        let port = PortPresences([.instantane(avecMissionDuJour), .echec(JoleneError(.network, "Connexion impossible.")),
                                  .echec(CancellationError()), .instantane(avecMissionEnCoursSeulement)])
        let (controller, snapshot) = try await pret(port)
        let model = PresencesModel(controller: controller, snapshot: snapshot)
        await model.load()
        await model.load()
        XCTAssertEqual(model.instantane, avecMissionDuJour, "les présences restent à l'écran après un rafraîchissement échoué")
        XCTAssertEqual(model.echecRafraichissement, PresencesModel.Echec(message: "Connexion impossible."))
        XCTAssertFalse(model.isRefreshing)
        await model.load()
        XCTAssertEqual(model.instantane, avecMissionDuJour, "rafraîchissement interrompu : instantané conservé")
        XCTAssertNil(model.echecRafraichissement)
        await model.load()
        XCTAssertEqual(model.instantane, avecMissionEnCoursSeulement, "le succès remplace l'instantané")
    }

    func testAnnulationLaisseLEtatEnChargement() async throws {
        let port = PortPresences([.echec(CancellationError()), .echec(JoleneError(.cancelled, "Chargement annulé."))])
        let (controller, snapshot) = try await pret(port)
        let model = PresencesModel(controller: controller, snapshot: snapshot)
        await model.load()
        XCTAssertEqual(model.state, .loading)
        await model.load()
        XCTAssertEqual(model.state, .loading, "`.task` relancera le chargement au prochain affichage")
        XCTAssertNil(model.echecRafraichissement)
    }

    func testSessionExpireeSignaleePourRevalidation() async throws {
        let port = PortPresences([.echec(JoleneError(.unauthorized, "Votre session a expiré. Reconnectez-vous."))])
        let (controller, snapshot) = try await pret(port)
        let model = PresencesModel(controller: controller, snapshot: snapshot)
        await model.load()
        XCTAssertTrue(model.sessionExpired)
        XCTAssertEqual(model.state, .failed(PresencesModel.Echec(message: "Votre session a expiré. Reconnectez-vous.")))
    }

    func testVerifierSessionRelitQuandLaSessionResteValide() async throws {
        let port = PortPresences([.echec(JoleneError(.unauthorized, "Votre session a expiré. Reconnectez-vous.")),
                                  .instantane(avecMissionDuJour)])
        let (controller, snapshot) = try await pret(port)
        let store = SessionStore(controller: controller)
        _ = await store.start()
        let model = PresencesModel(controller: controller, snapshot: try XCTUnwrap(store.state.snapshot))
        await model.load()
        XCTAssertTrue(model.sessionExpired)
        await model.verifierSession(store)
        XCTAssertFalse(model.sessionExpired)
        XCTAssertEqual(model.instantane, avecMissionDuJour)
        XCTAssertEqual(snapshot.context.userId, "u-1")
    }

    func testEpochPerimeAucunAppel() async throws {
        let port = PortPresences([.instantane(avecMissionDuJour)])
        let (controller, snapshot) = try await pret(port)
        let model = PresencesModel(controller: controller, snapshot: snapshot)
        _ = await controller.signOut()
        await model.load()
        XCTAssertEqual(model.state, .loading, "epoch périmé : aucun résultat publié")
        XCTAssertEqual(port.calls, 0, "aucune lecture sans gateways valides")
    }

    func testReponseRecueApresUnChangementDIdentiteIgnoree() async throws {
        let entree = Gate(), sortie = Gate()
        let port = PortPresences([.retenue(avecMissionDuJour, entree: entree, sortie: sortie)])
        let (controller, snapshot) = try await pret(port)
        let model = PresencesModel(controller: controller, snapshot: snapshot)
        let chargement = Task { await model.load() }
        await entree.wait()
        _ = await controller.signOut()
        await sortie.open()
        await chargement.value
        XCTAssertEqual(model.state, .loading, "réponse d'une identité quittée : jamais publiée")
        XCTAssertNil(model.onglet)
    }

    func testSeulLeChargementLePlusRecentPublie() async throws {
        let entreeAncien = Gate(), sortieAncien = Gate()
        let port = PortPresences([.retenue(avecMissionDuJour, entree: entreeAncien, sortie: sortieAncien),
                                  .instantane(avecMissionEnCoursSeulement)])
        let (controller, snapshot) = try await pret(port)
        let model = PresencesModel(controller: controller, snapshot: snapshot)
        let ancien = Task { await model.load() }
        await entreeAncien.wait()
        await model.load()
        XCTAssertEqual(model.instantane, avecMissionEnCoursSeulement)
        await sortieAncien.open()
        await ancien.value
        XCTAssertEqual(model.instantane, avecMissionEnCoursSeulement, "une réponse plus lente d'un chargement dépassé est ignorée")
        XCTAssertFalse(model.isRefreshing)
    }

    // MARK: - Relecture à l'apparition (staleTime 60 s)

    func testRelectureAuDelaDeSoixanteSecondesSeulement() async throws {
        let horloge = HorlogeReglable(maintenant)
        let port = PortPresences([.instantane(avecMissionDuJour), .instantane(avecMissionEnCoursSeulement)])
        let (controller, snapshot) = try await pret(port, horloge: horloge)
        let model = PresencesModel(controller: controller, snapshot: snapshot)
        await model.loadIfStale()
        XCTAssertEqual(port.calls, 1, "premier affichage : chargement")
        horloge.avancer(PresencesModel.delaiRelecture)
        await model.loadIfStale()
        XCTAssertEqual(port.calls, 1, "60 s pile : instantané encore frais")
        horloge.avancer(1)
        await model.loadIfStale()
        XCTAssertEqual(port.calls, 2, "au-delà de 60 s : relecture")
        XCTAssertEqual(model.instantane, avecMissionEnCoursSeulement)
    }

    func testApresUnEchecSeulReessayerRelance() async throws {
        let port = PortPresences([.echec(JoleneError(.network, "Connexion impossible."))])
        let (controller, snapshot) = try await pret(port)
        let model = PresencesModel(controller: controller, snapshot: snapshot)
        await model.loadIfStale()
        await model.loadIfStale()
        XCTAssertEqual(port.calls, 1, "jamais de boucle de relecture sur un échec")
    }

    // MARK: - Monde démo

    func testMondeDemoOngletsEtHistorique() async throws {
        let controller = SessionController(gateways: DemoWorld.gateways())
        let state = await controller.signIn(email: DemoWorld.context.email, password: "demonstration")
        let snapshot = try XCTUnwrap(state.snapshot)
        let model = PresencesModel(controller: controller, snapshot: snapshot)
        await model.load()
        let listes = try XCTUnwrap(model.listes)
        XCTAssertEqual(model.onglet, .aujourdhui)
        // Ordre de la fixture (`demo-presences.json`) ; en production, `order=debut_le.asc` côté PostgREST.
        XCTAssertEqual(listes.missionsAujourdhui.map(\.mission.id), ["demo-presence-a", "demo-presence-b", "demo-presence-c"])
        XCTAssertEqual(listes.missionsAVenir.map(\.mission.id), ["demo-presence-d", "demo-presence-e"])
        XCTAssertEqual(listes.missionsEnCours.map(\.mission.id), ["demo-presence-b"])
        XCTAssertEqual(model.presencesValidees.map(\.id), ["demo-presence-h1-presence"])
        XCTAssertEqual(model.historique.map(\.id), ["demo-presence-h1-presence", "demo-presence-h2-presence",
                                                    "effectifs-mission-demo-presence-h3"])
    }
}
