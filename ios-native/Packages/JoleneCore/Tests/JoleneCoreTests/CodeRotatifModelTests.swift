import XCTest
@testable import JoleneCore

/// Modèle du code de pointage rotatif côté établissement (lot 5, T7 ; D23) : code lu au serveur à chaque cadence (5 s),
/// lecture immédiate au retour, arrêt et réponse en vol ignorée à la disparition, backoff 30 s après 3 erreurs (code
/// retiré, attente découpée en tics de réévaluation de 15 s), epoch périmé ignoré, planning et signature relus toutes les
/// 60 s, code jamais lu ni présenté sans la permission `pointage`, valeur qui n'est pas six chiffres jamais présentée.
/// Session établissement réelle du monde démo (`DemoWorld.gateways(espace:)`, espace ouvert), port du pointage scripté,
/// minuterie injectée (aucune attente réelle).
@MainActor
final class CodeRotatifModelTests: XCTestCase {
    private struct PanneTest: Error {}

    /// Journal partagé du port et de la minuterie : ordre des lectures et des attentes.
    private actor Journal {
        private(set) var evenements: [String] = []
        func noter(_ evenement: String) { evenements.append(evenement) }
    }

    /// Port scripté : chaque lecture de l'état consomme la file (la dernière réponse reste servie) ; `avantReponse` est
    /// appelé avec le rang de la lecture avant que la réponse ne parte.
    private actor Port: EtabPointagePort {
        enum Reponse: Sendable { case etat(EtatPointageEtab), echec }
        nonisolated let cadenceLecture: TimeInterval
        private var reponses: [Reponse]
        private let journal: Journal
        private let planningLisible: Bool
        private var avantReponse: (@Sendable (Int) async -> Void)?
        private(set) var lecturesEtat = 0
        private(set) var lecturesPlanning = 0
        private(set) var lecturesSignature = 0

        init(_ reponses: [Reponse], journal: Journal, planningLisible: Bool = true, cadence: TimeInterval = 5) {
            self.reponses = reponses; self.journal = journal; self.planningLisible = planningLisible
            cadenceLecture = cadence
        }

        func surLecture(_ action: @escaping @Sendable (Int) async -> Void) { avantReponse = action }

        func etat(missionId: String, context: EtablissementReadContext) async throws -> EtatPointageEtab {
            lecturesEtat += 1
            let rang = lecturesEtat
            await journal.noter("etat")
            if let avantReponse { await avantReponse(rang) }
            let reponse = reponses.count > 1 ? reponses.removeFirst() : reponses.first ?? .echec
            switch reponse {
            case let .etat(etat): return etat
            case .echec: throw JoleneError(.network, "Panne de démonstration.")
            }
        }

        func contratSigne(missionId: String, context: EtablissementReadContext) async throws -> Bool {
            lecturesSignature += 1
            return true
        }

        func planning(missionId: String, context: EtablissementReadContext) async throws -> PlanningMission {
            lecturesPlanning += 1
            guard planningLisible else { throw JoleneError(.network, "Planning illisible.") }
            return PlanningMission(mission: MissionAvecPlanningAttendu(id: missionId, debutLe: "2026-11-03T07:00:00Z",
                                                                       finLe: "2026-11-03T15:00:00Z", nbCreneaux: 1),
                                   creneaux: [MissionSlot(id: "c-1", missionId: missionId, debut: "2026-11-03T07:00:00Z",
                                                          fin: "2026-11-03T15:00:00Z", estPause: false, typeCreneau: "PREVISIONNEL")])
        }
    }

    /// Minuterie injectée : note chaque attente (et l'affichage à cet instant), arrête le suivi à la `arret`-ième.
    private actor Minuterie {
        private(set) var durees: [TimeInterval] = []
        private(set) var codesVus: [String] = []
        private let journal: Journal
        private var arret = Int.max
        private var surArret: (@Sendable () async -> Void)?
        private var instantane: (@Sendable () async -> String)?

        init(journal: Journal) { self.journal = journal }

        func configurer(arret: Int, instantane: @escaping @Sendable () async -> String,
                        surArret: @escaping @Sendable () async -> Void) {
            self.arret = arret; self.instantane = instantane; self.surArret = surArret
        }

        func attendre(_ duree: TimeInterval) async {
            durees.append(duree)
            await journal.noter("attente")
            if let instantane { codesVus.append(await instantane()) }
            if durees.count >= arret { await surArret?() }
        }
    }

    private struct Banc {
        let model: CodeRotatifModel
        let controller: SessionController
        let port: Port
        let minuterie: Minuterie
        let journal: Journal
    }

    /// 2026-11-03T10:00:00Z : dans le créneau 07:00-15:00 UTC du planning scripté.
    private let pendantLeCreneau = Date(timeIntervalSince1970: 1_793_700_000)

    private func banc(_ reponses: [Port.Reponse], role: RoleEtab = .proprietaire, planningLisible: Bool = true,
                      arret: Int) async throws -> Banc {
        let journal = Journal()
        let port = Port(reponses, journal: journal, planningLisible: planningLisible)
        let minuterie = Minuterie(journal: journal)
        var gateways = DemoWorld.gateways(espace: .etablissement(.init(role: role)))
        gateways.etablissement.pointage = port
        gateways.clock = FixedClock(pendantLeCreneau)
        let controller = SessionController(gateways: gateways, espaceEtablissement: .ouvert)
        _ = await controller.start()
        let etat = await controller.signIn(email: DemoEspace.emailEtablissement, password: "demo")
        guard case let .readyEtablissement(snapshot) = etat else {
            XCTFail("espace établissement démo attendu, obtenu \(etat)")
            throw PanneTest()
        }
        let model = CodeRotatifModel(missionId: "m-1", controller: controller, snapshot: snapshot,
                                     attendre: { await minuterie.attendre($0) })
        await minuterie.configurer(arret: arret, instantane: { await Self.decrire(model) }, surArret: { await model.desactiver() })
        return Banc(model: model, controller: controller, port: port, minuterie: minuterie, journal: journal)
    }

    private static func decrire(_ model: CodeRotatifModel) -> String {
        switch model.affichage.bloc {
        case let .code(code): return code.valeur
        case let .indisponible(message): return "indisponible: \(message)"
        case .momentanementIndisponible: return "momentanement"
        case .reservePointage: return "reserve"
        case .aucun: return "aucun"
        case let .planningInutilisable(message): return "planning: \(message)"
        case let .masque(titre, _): return "masque: \(titre)"
        }
    }

    private func etat(_ code: String?, segments: [CodeRotatifRules.Segment] = [], prochain: String = "OUVERTURE") -> Port.Reponse {
        .etat(EtatPointageEtab(statut: "ASSIGNEE", prochainTypeScan: prochain, segmentOuvert: segments.contains { $0.fin == nil },
                               segments: segments, codePointageActif: code))
    }

    // MARK: - Cadence et cycle de vie

    func testCodeLuAuServeurToutesLesCinqSecondes() async throws {
        let b = try await banc([etat("123456"), etat("100002")], arret: 2)
        XCTAssertTrue(b.model.chargement, "rien n'est présenté avant la première lecture")
        await b.model.suivre()
        let durees = await b.minuterie.durees
        XCTAssertEqual(durees, [5, 5], "cadence nominale D23 (web refetchInterval 5000)")
        let vus = await b.minuterie.codesVus
        XCTAssertEqual(vus, ["123456", "100002"], "la valeur présentée est toujours la dernière lue, jamais calculée")
        let lectures = await b.port.lecturesEtat
        XCTAssertEqual(lectures, 2)
        XCTAssertEqual(b.model.codePresente?.chiffres, "100 002")
        XCTAssertEqual(b.model.codePresente?.prochainPointage, "Arrivée")
        XCTAssertFalse(b.model.chargement)
    }

    func testArretALaDisparitionPuisLectureImmediateAuRetour() async throws {
        let b = try await banc([etat("123456")], arret: 1)
        await b.model.suivre()
        var evenements = await b.journal.evenements
        XCTAssertEqual(evenements, ["etat", "attente"], "aucune lecture après l'arrêt (arrière-plan ou disparition)")
        await b.minuterie.configurer(arret: 2, instantane: { "" }, surArret: { await b.model.desactiver() })
        await b.model.suivre()
        evenements = await b.journal.evenements
        XCTAssertEqual(evenements, ["etat", "attente", "etat", "attente"], "au retour, la première lecture part sans attendre")
    }

    func testReponseEnVolIgnoreeApresLaDisparition() async throws {
        let b = try await banc([etat("123456"), etat("999999")], arret: 10)
        let model = b.model
        await b.port.surLecture { rang in if rang == 2 { await model.desactiver() } }
        await model.suivre()
        XCTAssertEqual(model.codePresente?.valeur, "123456", "la réponse arrivée après la disparition n'est jamais publiée")
        let lectures = await b.port.lecturesEtat
        XCTAssertEqual(lectures, 2)
    }

    func testEpochPerimeIgnoreEtSuiviArrete() async throws {
        let b = try await banc([etat("123456"), etat("999999")], arret: 10)
        let controller = b.controller
        await b.port.surLecture { rang in if rang == 2 { _ = await controller.signOut() } }
        await b.model.suivre()
        XCTAssertEqual(b.model.codePresente?.valeur, "123456", "une réponse d'une autre session n'est jamais publiée")
        let durees = await b.minuterie.durees
        XCTAssertEqual(durees, [5], "le suivi s'arrête au changement d'epoch")
    }

    // MARK: - Erreurs

    func testTroisErreursRetirentLeCodeEtRalentissentPuisRetourNominal() async throws {
        let b = try await banc([etat("123456"), .echec, .echec, .echec, etat("100002")], arret: 6)
        await b.model.suivre()
        let durees = await b.minuterie.durees
        XCTAssertEqual(durees, [5, 5, 5, 15, 15, 5],
                       "backoff 30 s après 3 erreurs, découpé en tics de réévaluation de 15 s ; cadence nominale au retour")
        let vus = await b.minuterie.codesVus
        XCTAssertEqual(vus, ["123456", "123456", "123456", "indisponible: Panne de démonstration.",
                             "indisponible: Panne de démonstration.", "100002"],
                       "deux échecs gardent la dernière lecture ; au troisième, le code est retiré")
        XCTAssertEqual(b.model.erreursConsecutives, 0)
    }

    func testPremiereLectureEnEchecAfficheIndisponibleSansAttendre() async throws {
        let b = try await banc([.echec], arret: 1)
        await b.model.suivre()
        XCTAssertEqual(b.model.affichage.bloc, .indisponible(message: "Panne de démonstration."))
        XCTAssertNil(b.model.codePresente)
        XCTAssertTrue(b.model.segments.isEmpty)
    }

    func testRefusServeurVerbatimSansCode() async throws {
        let refus = EtatPointageEtab(statut: nil, prochainTypeScan: nil, segmentOuvert: false, segments: [],
                                     codePointageActif: nil, erreur: "Accès interdit")
        let b = try await banc([.etat(refus)], arret: 1)
        await b.model.suivre()
        XCTAssertEqual(b.model.affichage.bloc, .indisponible(message: "Accès interdit"))
    }

    // MARK: - Planning, permission, valeur

    func testPlanningEtSignatureRelusToutesLesSoixanteSecondes() async throws {
        let b = try await banc([etat("123456")], arret: 13)
        await b.model.suivre()
        let (etats, planning, signature) = (await b.port.lecturesEtat, await b.port.lecturesPlanning, await b.port.lecturesSignature)
        XCTAssertEqual(etats, 13)
        XCTAssertEqual(planning, 2, "à l'ouverture puis après 60 s (web staleTime 60_000)")
        XCTAssertEqual(signature, 2)
    }

    func testPlanningIllisibleMasqueLeCodeEtEstReluAuTicSuivant() async throws {
        let b = try await banc([etat("123456")], planningLisible: false, arret: 2)
        await b.model.suivre()
        XCTAssertEqual(b.model.affichage.bloc, .planningInutilisable(message: CodeRotatifRules.messagePlanningIndisponible))
        XCTAssertNil(b.model.codePresente, "aucun code d'arrivée sans planning lisible")
        let planning = await b.port.lecturesPlanning
        XCTAssertEqual(planning, 2, "relu à chaque tic tant qu'il n'a pas pu être lu")
    }

    func testSansPermissionPointageAucuneLectureNiCode() async throws {
        let b = try await banc([etat("123456")], role: .lectureSeule, arret: 1)
        XCTAssertFalse(b.model.autorise)
        await b.model.suivre()
        XCTAssertEqual(b.model.affichage.bloc, .reservePointage)
        XCTAssertNil(b.model.codePresente)
        XCTAssertFalse(b.model.chargement)
        let (etats, planning) = (await b.port.lecturesEtat, await b.port.lecturesPlanning)
        XCTAssertEqual(etats + planning, 0, "aucune lecture d'état ni polling sans la permission (web l.102-115)")
    }

    func testValeurQuiNestPasSixChiffresJamaisPresentee() async throws {
        for valeur in ["12345", "1234567", "12 345", "abcdef", "１２３４５６"] {
            let b = try await banc([etat(valeur)], arret: 1)
            await b.model.suivre()
            XCTAssertEqual(b.model.affichage.bloc, .momentanementIndisponible, valeur)
            XCTAssertNil(b.model.codePresente, valeur)
        }
    }

    func testSegmentOuvertCodeDeDepartEtPointagesEnregistres() async throws {
        let segment = CodeRotatifRules.Segment(id: "s-1", debut: "2026-11-03T07:02:00Z", fin: nil)
        let b = try await banc([etat("100002", segments: [segment], prochain: "FERMETURE")], arret: 1)
        await b.model.suivre()
        let code = try XCTUnwrap(b.model.codePresente)
        XCTAssertEqual(code.prochainPointage, "Départ ou pause")
        XCTAssertTrue(code.segmentEnCours)
        XCTAssertEqual(b.model.segments.map(\.libelle), ["Segment 1 · 03/11/2026 08h02 → en cours"])
        XCTAssertEqual(b.model.affichage.creneauActif?.libelle, "Créneau 1/1 · mardi 3 novembre 2026 à 08:00 → 16:00")
    }
}

/// Écran maintenu allumé (lot 5, T7) : demandes comptées par demandeur, veille rétablie à la dernière libération, à la
/// valeur d'avant la première demande.
@MainActor
final class IdleTimerControllerTests: XCTestCase {
    @MainActor
    private final class Reglage: IdleTimerSetting {
        var isIdleTimerDisabled: Bool
        init(_ valeur: Bool = false) { isIdleTimerDisabled = valeur }
    }

    func testApparitionDisparitionEtArrierePlan() {
        let reglage = Reglage()
        let veille = IdleTimerController(reglage: reglage)
        veille.appliquer(veilleDesactivee: true, demandeur: "code")
        XCTAssertTrue(reglage.isIdleTimerDisabled, "code affiché : écran maintenu allumé")
        XCTAssertTrue(veille.veilleDesactivee)
        veille.appliquer(veilleDesactivee: false, demandeur: "code")
        XCTAssertFalse(reglage.isIdleTimerDisabled, "arrière-plan ou disparition : veille rétablie")
        veille.appliquer(veilleDesactivee: true, demandeur: "code")
        XCTAssertTrue(reglage.isIdleTimerDisabled, "retour au premier plan")
        veille.retablirVeille(demandeur: "code")
        XCTAssertFalse(reglage.isIdleTimerDisabled)
        XCTAssertFalse(veille.veilleDesactivee)
    }

    func testDeuxEcransImbriquesRetablitAuDernier() {
        let reglage = Reglage()
        let veille = IdleTimerController(reglage: reglage)
        veille.desactiverVeille(demandeur: "ecran")
        veille.desactiverVeille(demandeur: "plein-ecran")
        veille.retablirVeille(demandeur: "plein-ecran")
        XCTAssertTrue(reglage.isIdleTimerDisabled, "un écran garde encore sa demande")
        veille.retablirVeille(demandeur: "ecran")
        XCTAssertFalse(reglage.isIdleTimerDisabled, "rétablie à la dernière libération")
    }

    func testDemandesIdempotentesEtValeurInitialeRetablie() {
        let reglage = Reglage()
        let veille = IdleTimerController(reglage: reglage)
        veille.desactiverVeille(demandeur: "code")
        veille.desactiverVeille(demandeur: "code")
        veille.retablirVeille(demandeur: "code")
        XCTAssertFalse(reglage.isIdleTimerDisabled, "une apparition répétée ne compte qu'une fois")
        veille.retablirVeille(demandeur: "inconnu")
        XCTAssertFalse(reglage.isIdleTimerDisabled)

        let dejaDesactivee = Reglage(true)
        let autre = IdleTimerController(reglage: dejaDesactivee)
        autre.desactiverVeille(demandeur: "code")
        autre.retablirVeille(demandeur: "code")
        XCTAssertTrue(dejaDesactivee.isIdleTimerDisabled, "jamais forcée à false si elle l'était avant la première demande")
    }
}
