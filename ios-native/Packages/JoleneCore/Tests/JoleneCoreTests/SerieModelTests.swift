import XCTest
@testable import JoleneCore

/// Détail de série (L4-T12, `docs/mobile-swift/LOT4_PLAN.md` §3 T12) sur un port témoin et sur le monde démo :
/// sélection par `SelectionSerieCandidat` (lot 1 T2), boucle d'acceptation séquentielle, une issue par mission, arrêt
/// sur le refus de conformité affiché tel que servi (HARD STOP n°4, décision 2 du lot 1), aucun renvoi.
@MainActor
final class SerieModelTests: XCTestCase {
    /// Refus d'un trigger de conformité, au format du serveur (`supabase/schema/public.sql`, `dec_verifier_plafond_48h`).
    private static let refusServeur = "[CODE DU TRAVAIL] Semaine du 30/11/2026 : 40.0h Jolene + 10.0h ailleurs = 50.0h total (max 48h, Art. L3121-20)"
    private static let conflitServeur = "Tu es déjà confirmé(e) sur « Garde de nuit » le 12/11 08h00–12/11 16h00. Ce créneau chevauche la mission."

    // MARK: - Port témoin

    private enum Reponse: Sendable {
        case issue(CandidatureOutcome)
        case erreur(JoleneError)
        case annulation
    }

    /// Série en mémoire : journal des appels (début et fin de chaque envoi, lectures), réponses scriptées par mission,
    /// missions acceptées relues attribuées au soignant (sauf `relectureFigee`).
    private actor Temoin: SeriePort {
        private var lignes: [Mission]
        private let reponses: [String: Reponse]
        private let userId: String
        private let relectureFigee: Bool
        private let attribueesSansReponse: Set<String>
        private(set) var journal: [String] = []
        private(set) var envois: [String] = []
        private(set) var lectures = 0
        private(set) var enVol = 0
        private(set) var enVolMax = 0
        private var echecsDeLecture: [JoleneError]

        init(_ lignes: [Mission], reponses: [String: Reponse] = [:], userId: String = DemoWorld.context.userId,
             relectureFigee: Bool = false, attribueesSansReponse: Set<String> = [], echecsDeLecture: [JoleneError] = []) {
            self.lignes = lignes
            self.reponses = reponses
            self.userId = userId
            self.relectureFigee = relectureFigee
            self.attribueesSansReponse = attribueesSansReponse
            self.echecsDeLecture = echecsDeLecture
        }

        func missions(serieId: String, context: MissionReadContext) async throws -> [Mission] {
            lectures += 1
            if !echecsDeLecture.isEmpty { throw echecsDeLecture.removeFirst() }
            return lignes
        }

        func accepter(missionId: String, creneaux: [CreneauConfirmePayload],
                      context: MissionReadContext) async throws -> CandidatureOutcome {
            envois.append(missionId)
            journal.append("debut \(missionId)")
            enVol += 1
            enVolMax = max(enVolMax, enVol)
            await Task.yield()
            defer {
                enVol -= 1
                journal.append("fin \(missionId)")
            }
            // Le serveur a pu agir alors que la réponse est perdue.
            if attribueesSansReponse.contains(missionId) { attribuer(missionId) }
            switch reponses[missionId] ?? .issue(.confirmed(candidatureId: nil, contratId: "contrat-\(missionId)")) {
            case let .issue(issue):
                if case .confirmed = issue, !relectureFigee { attribuer(missionId) }
                return issue
            case let .erreur(erreur):
                throw erreur
            case .annulation:
                throw CancellationError()
            }
        }

        private func attribuer(_ id: String) {
            guard let index = lignes.firstIndex(where: { $0.id == id }) else { return }
            lignes[index].record.statut = CandidatureRules.statutAssignee
            lignes[index].record.soignantAssigneId = userId
        }
    }

    // MARK: - Fabriques

    /// Mission ouverte au planning exact, copie d'une mission de `demo-missions.json` (créneau unique).
    private func mission(_ id: String, jour: Int = 3, statut: String = "OUVERTE", assigneeA: String? = nil,
                         planningExact: Bool = true) throws -> Mission {
        var fixture = try XCTUnwrap(DemoFixtures.loadMissions().missions.first { $0.record.id == "demo-mission-001" })
        let debut = String(format: "2026-11-%02dT07:00:00.000Z", jour)
        let fin = String(format: "2026-11-%02dT15:00:00.000Z", jour)
        fixture.record.id = id
        fixture.record.intitule = "Renfort \(id)"
        fixture.record.debutLe = debut
        fixture.record.finLe = fin
        fixture.record.statut = statut
        fixture.record.soignantAssigneId = assigneeA
        // Planning non exact : deux créneaux attendus, un seul servi.
        fixture.record.nbCreneaux = planningExact ? 1 : 2
        let creneaux = [MissionSlot(id: "\(id)-slot", missionId: id, debut: debut, fin: fin, estPause: false, typeCreneau: "PREVISIONNEL")]
        return MissionBusiness.enrich(record: fixture.record, context: DemoWorld.context, etablissement: nil, slots: creneaux)
    }

    private func session(_ port: any SeriePort) async throws -> (SessionController, SessionSnapshot) {
        var gateways = DemoWorld.gateways()
        gateways.serie = port
        let controller = SessionController(gateways: gateways)
        let state = await controller.signIn(email: DemoWorld.context.email ?? "", password: "demonstration")
        return (controller, try XCTUnwrap(state.snapshot, "session démo prête attendue, obtenu \(state)"))
    }

    private func modele(_ port: any SeriePort, serieId: String = "SERIE_1793577600000_test01") async throws -> SerieModel {
        let (controller, snapshot) = try await session(port)
        let model = SerieModel(serieId: serieId, controller: controller, snapshot: snapshot)
        await model.charger()
        return model
    }

    private func quatre() throws -> [Mission] {
        try [mission("m1", jour: 3), mission("m2", jour: 4), mission("m3", jour: 5), mission("m4", jour: 6)]
    }

    // MARK: - Lecture et sélection

    func testChargerSelectionneLesMissionsOuvertesAuPlanningExact() async throws {
        let temoin = Temoin(try [mission("m1", jour: 3), mission("m2", jour: 4, planningExact: false),
                                 mission("m3", jour: 5, statut: "ASSIGNEE", assigneeA: "un-autre")])
        let model = try await modele(temoin)
        XCTAssertEqual(model.missions.map(\.id), ["m1", "m2", "m3"], "ordre du serveur")
        XCTAssertEqual(model.ouvertes.map(\.id), ["m1", "m2"])
        XCTAssertEqual(model.selection, ["m1"], "seules les missions ouvertes au planning exact sont cochées (web l.135)")
        XCTAssertTrue(model.peutAccepter)
        XCTAssertEqual(model.libelleAction, "★ Accepter la sélection (1)")
        XCTAssertTrue(model.selectionnable(model.missions[0]))
        XCTAssertFalse(model.selectionnable(model.missions[1]), "planning non exact : pas de case à cocher")
        XCTAssertFalse(model.selectionnable(model.missions[2]), "mission pourvue : pas de case à cocher")

        model.basculer("m2")
        model.basculer("m3")
        XCTAssertEqual(model.selection, ["m1"], "une mission non sélectionnable n'est jamais cochée")
        model.basculer("m1")
        XCTAssertEqual(model.selection, [])
        XCTAssertFalse(model.peutAccepter, "sélection vide")
        await model.accepter()
        let envois = await temoin.envois
        XCTAssertEqual(envois, [], "sélection vide : aucun envoi")
        XCTAssertEqual(model.erreur, SerieTextes.selectionACorriger)
    }

    func testSerieSansMissionAccessibleEstIntrouvable() async throws {
        let model = try await modele(Temoin([]))
        XCTAssertEqual(model.etat, .introuvable)
        XCTAssertFalse(model.peutAccepter)
    }

    func testEchecDeLecturePuisReessai() async throws {
        let temoin = Temoin(try quatre(), echecsDeLecture: [JoleneError(.network, "Connexion impossible."),
                                                            JoleneError(.unauthorized, "Votre session a expiré. Reconnectez-vous.")])
        let model = try await modele(temoin)
        XCTAssertEqual(model.etat, .echec(SerieTextes.indisponibleTexte), "texte du web, jamais le détail technique")
        XCTAssertFalse(model.sessionExpiree)
        await model.recharger()
        XCTAssertEqual(model.etat, .echec("Votre session a expiré. Reconnectez-vous."))
        XCTAssertTrue(model.sessionExpiree)
        await model.recharger()
        XCTAssertEqual(model.missions.count, 4)
        XCTAssertFalse(model.sessionExpiree)
        XCTAssertEqual(model.selection.count, 4)
    }

    // MARK: - Boucle d'acceptation

    func testBoucleSequentielleUneIssueParMissionSansRenvoi() async throws {
        let temoin = Temoin(try quatre(), reponses: [
            "m2": .issue(.refusee(code: "CONFLIT_PLANNING", message: Self.conflitServeur, documentsRequisPour: nil)),
            "m3": .issue(.choixRequis([ChoixContratOption(value: "SALARIE", label: "Salarié (CDD / bulletin de paie)"),
                                       ChoixContratOption(value: "LIBERAL", label: "Libéral (note d'honoraires)")])),
        ])
        let model = try await modele(temoin)
        await model.accepter()

        let journal = await temoin.journal
        XCTAssertEqual(journal, ["debut m1", "fin m1", "debut m2", "fin m2", "debut m3", "fin m3", "debut m4", "fin m4"],
                       "une mission après l'autre, dans l'ordre affiché, une seule requête chacune")
        let enVolMax = await temoin.enVolMax
        XCTAssertEqual(enVolMax, 1, "jamais deux acceptations en vol")
        XCTAssertEqual(model.resultats, [
            "m1": .acceptee,
            "m2": .refusee(code: "CONFLIT_PLANNING", message: Self.conflitServeur),
            "m3": .choixContratRequis,
            "m4": .acceptee,
        ])
        XCTAssertNil(model.refusConformite)
        XCTAssertEqual(model.bilan, BilanSerie(acceptees: 2, echouees: 2, nonEnvoyees: 0))
        XCTAssertEqual(model.bilan?.texte, "2 mission(s) acceptée(s), 2 en conflit.")
        XCTAssertEqual(model.bilan?.ton, .partiel)
        XCTAssertFalse(model.enCours)
        XCTAssertNil(model.missionEnCours)
        // Relecture après la boucle : les missions acceptées ne sont plus ouvertes, la sélection restante est gardée.
        let lectures = await temoin.lectures
        XCTAssertEqual(lectures, 2, "une lecture à l'ouverture, une relecture après la boucle")
        XCTAssertEqual(model.ouvertes.map(\.id), ["m2", "m3"])
        XCTAssertEqual(model.selection, ["m2", "m3"], "aucune mission retirée en silence de la sélection")
    }

    func testToutAccepteBilanDeSucces() async throws {
        let temoin = Temoin(try quatre())
        let model = try await modele(temoin)
        await model.accepter()
        XCTAssertEqual(model.bilan?.texte, "4 missions acceptées !")
        XCTAssertEqual(model.bilan?.ton, .succes)
        XCTAssertEqual(model.ouvertes, [])
        XCTAssertFalse(model.peutAccepter)
    }

    func testArretSurLeRefusDeConformiteAfficheTelQueServi() async throws {
        let temoin = Temoin(try quatre(), reponses: [
            "m2": .issue(.refusee(code: CandidatureOutcome.codeRefusCodeDuTravail, message: Self.refusServeur, documentsRequisPour: nil)),
        ])
        let model = try await modele(temoin)
        await model.accepter()

        let envois = await temoin.envois
        XCTAssertEqual(envois, ["m1", "m2"], "la boucle s'arrête sur le refus : m3 et m4 ne sont jamais envoyées")
        XCTAssertEqual(model.refusConformite, RefusConformiteSerie(missionId: "m2", message: Self.refusServeur))
        XCTAssertEqual(model.refusConformite?.message, Self.refusServeur, "texte du serveur mot pour mot, sans ajout ni retrait")
        XCTAssertEqual(model.resultats, [
            "m1": .acceptee,
            "m2": .codeDuTravail(message: Self.refusServeur),
            "m3": .nonEnvoyee,
            "m4": .nonEnvoyee,
        ])
        XCTAssertEqual(model.bilan, BilanSerie(acceptees: 1, echouees: 1, nonEnvoyees: 2))
        XCTAssertEqual(model.bilan?.texte, "1 mission(s) acceptée(s), 1 en conflit.")

        // La mission refusée reste cochée et bloque : rien n'est renvoyé tant qu'elle n'est pas décochée.
        XCTAssertEqual(model.analyse.idsEnConflit, ["m2"])
        XCTAssertFalse(model.peutAccepter)
        XCTAssertEqual(model.libelleAction, SerieTextes.decocherConflits)
        await model.accepter()
        let apresSecondAppui = await temoin.envois
        XCTAssertEqual(apresSecondAppui, ["m1", "m2"], "aucun renvoi du refus")
        XCTAssertEqual(model.erreur, SerieTextes.selectionACorriger)

        // Décochée par le soignant : les missions non envoyées peuvent être acceptées, le refus reste affiché.
        model.basculer("m2")
        XCTAssertTrue(model.peutAccepter)
        XCTAssertEqual(model.libelleAction, "★ Accepter la sélection (2)")
        await model.accepter()
        let finaux = await temoin.envois
        XCTAssertEqual(finaux, ["m1", "m2", "m3", "m4"], "m2 n'est envoyée qu'une fois")
        XCTAssertEqual(model.resultats["m2"], .codeDuTravail(message: Self.refusServeur))
        XCTAssertEqual(model.resultats["m3"], .acceptee)
        XCTAssertEqual(model.resultats["m4"], .acceptee)
        XCTAssertNil(model.refusConformite, "le refus de la boucle précédente n'est pas réaffiché comme celui de la nouvelle")
        XCTAssertEqual(model.bilan?.texte, "2 missions acceptées !")
    }

    func testRefusSansCodePoursuitLaBoucleEtNeBloquePasLaSelection() async throws {
        let quota = "Trop de candidatures en peu de temps. Réessayez plus tard."
        let indisponible = "Cette mission n'est plus disponible."
        let temoin = Temoin(try quatre(), reponses: [
            "m1": .erreur(JoleneError(.unknown, quota)),
            "m2": .issue(.missionDejaAttribuee(message: indisponible)),
            "m3": .issue(.planningAReconfirmer(code: "PLANNING_MODIFIE_RECONFIRMER", message: DemoCandidatureGateway.Textes.planningModifie)),
        ])
        let model = try await modele(temoin)
        await model.accepter()
        let envois = await temoin.envois
        XCTAssertEqual(envois, ["m1", "m2", "m3", "m4"], "un refus du serveur n'arrête pas la boucle (web l.317-318)")
        XCTAssertEqual(model.resultats, [
            "m1": .refusee(code: nil, message: quota),
            "m2": .refusee(code: nil, message: indisponible),
            "m3": .planningModifie(message: DemoCandidatureGateway.Textes.planningModifie),
            "m4": .acceptee,
        ])
        XCTAssertEqual(model.idsConflit, [], "seul un refus structuré du serveur marque une mission en conflit")
        XCTAssertEqual(model.bilan?.texte, "1 mission(s) acceptée(s), 3 en conflit.")
    }

    func testRienAccepte() async throws {
        let temoin = Temoin(try [mission("m1")], reponses: [
            "m1": .issue(.refusee(code: "REPOS_11H", message: "Repos insuffisant avec « Garde » : 8.5 h au lieu de 11 h minimum.", documentsRequisPour: nil)),
        ])
        let model = try await modele(temoin)
        await model.accepter()
        XCTAssertEqual(model.bilan?.texte, SerieTextes.bilanAucune)
        XCTAssertEqual(model.bilan?.ton, .echec)
        XCTAssertNil(model.refusConformite, "refus jsonb du serveur : affiché sur la mission, la boucle ne s'arrête pas pour lui")
        XCTAssertEqual(model.idsConflit, ["m1"])
    }

    // MARK: - Aucun renvoi

    func testReponsePerdueArreteLaBoucleSansRenvoi() async throws {
        let delai = JoleneError(.network, SessionController.timeoutMessage)
        let temoin = Temoin(try quatre(), reponses: ["m2": .erreur(delai)])
        let model = try await modele(temoin)
        await model.accepter()
        let envois = await temoin.envois
        XCTAssertEqual(envois, ["m1", "m2"], "état du serveur inconnu : plus rien n'est envoyé, rien n'est renvoyé")
        XCTAssertEqual(model.resultats, [
            "m1": .acceptee,
            "m2": .nonConfirmee(message: SessionController.timeoutMessage),
            "m3": .nonEnvoyee,
            "m4": .nonEnvoyee,
        ])
        XCTAssertEqual(model.idsConflit, [], "une réponse perdue n'est pas un refus")
        let lectures = await temoin.lectures
        XCTAssertEqual(lectures, 2, "la série est relue")
    }

    func testReponsePerdueReconcilieeParRelecture() async throws {
        let temoin = Temoin(try quatre(), reponses: ["m2": .erreur(JoleneError(.contract, "Votre réponse a été envoyée mais n'a pas pu être relue. Vérifiez Mes missions avant de réessayer."))],
                            attribueesSansReponse: ["m2"])
        let model = try await modele(temoin)
        await model.accepter()
        let envois = await temoin.envois
        XCTAssertEqual(envois, ["m1", "m2"])
        XCTAssertEqual(model.resultats["m2"], .acceptee, "relue attribuée au soignant de la session : acceptée, sans renvoi")
        XCTAssertEqual(model.bilan, BilanSerie(acceptees: 2, echouees: 0, nonEnvoyees: 2))
        XCTAssertEqual(model.bilan?.ton, .partiel)
        XCTAssertEqual(model.bilan?.texte, "2 missions acceptées !")
    }

    func testSessionExpireeArreteLaBoucle() async throws {
        let expiree = JoleneError(.unauthorized, "Votre session a expiré. Reconnectez-vous.")
        let temoin = Temoin(try quatre(), reponses: ["m1": .erreur(expiree)])
        let model = try await modele(temoin)
        await model.accepter()
        let envois = await temoin.envois
        XCTAssertEqual(envois, ["m1"])
        XCTAssertTrue(model.sessionExpiree)
        XCTAssertEqual(model.erreur, expiree.message)
        XCTAssertEqual(model.resultats, ["m1": .nonEnvoyee, "m2": .nonEnvoyee, "m3": .nonEnvoyee, "m4": .nonEnvoyee],
                       "requête refusée faute de session : rien n'a été traité, rien d'autre n'est envoyé")
        XCTAssertEqual(model.bilan?.texte, SerieTextes.bilanAucune)
        let lectures = await temoin.lectures
        XCTAssertEqual(lectures, 1, "session expirée : pas de relecture")
    }

    func testSecondAppuiPendantLaBoucleEstIgnore() async throws {
        let temoin = Temoin(try quatre())
        let model = try await modele(temoin)
        async let premier: Void = model.accepter()
        async let second: Void = model.accepter()
        _ = await (premier, second)
        let envois = await temoin.envois
        XCTAssertEqual(envois, ["m1", "m2", "m3", "m4"], "chaque mission n'est envoyée qu'une fois")
    }

    func testAnnulationNEstJamaisUneErreur() async throws {
        let temoin = Temoin(try quatre(), reponses: ["m1": .annulation])
        let model = try await modele(temoin)
        await model.accepter()
        XCTAssertNil(model.erreur)
        XCTAssertNil(model.bilan)
        XCTAssertFalse(model.enCours)
    }

    func testRetourSurLEcranRelitSansEffacerLesIssues() async throws {
        let temoin = Temoin(try quatre(), reponses: [
            "m2": .issue(.refusee(code: CandidatureOutcome.codeRefusCodeDuTravail, message: Self.refusServeur, documentsRequisPour: nil)),
        ])
        let model = try await modele(temoin)
        await model.accepter()
        await model.charger()
        XCTAssertEqual(model.refusConformite?.message, Self.refusServeur, "réapparition : le refus reste affiché")
        XCTAssertEqual(model.resultats["m2"], .codeDuTravail(message: Self.refusServeur))
        await model.recharger()
        XCTAssertNil(model.refusConformite, "lecture complète : issues effacées, sélection réinitialisée")
        XCTAssertEqual(model.resultats, [:])
        XCTAssertEqual(model.selection, ["m2", "m3", "m4"])
    }

    // MARK: - Monde démo

    func testSerieDemoCinqMissionsUneRefuseePourConflit() async throws {
        // Un seul monde : le port de la série partage les missions et la candidature de la session.
        let monde = DemoWorld.gateways()
        XCTAssertTrue(monde.serie is DemoSerieGateway)
        let session = SessionController(gateways: monde)
        let etat = await session.signIn(email: DemoWorld.context.email ?? "", password: "demonstration")
        let instantane = try XCTUnwrap(etat.snapshot)
        let serie = SerieModel(serieId: "SERIE_1793577600000_demo01", controller: session, snapshot: instantane)
        await serie.charger()
        XCTAssertEqual(serie.missions.map(\.id), ["demo-mission-001", "demo-mission-010", "demo-mission-013", "demo-mission-025", "demo-mission-028"])
        XCTAssertEqual(serie.selection.count, 5)
        await serie.accepter()
        XCTAssertEqual(serie.resultats["demo-mission-013"],
                       .refusee(code: "CONFLIT_PLANNING",
                                message: "Tu es déjà confirmé(e) sur « Démonstration · Mission assignée 4 » le 15/11 08h00–15/11 16h00. Ce créneau chevauche la mission."))
        XCTAssertEqual(serie.resultats.values.filter { $0 == .acceptee }.count, 4)
        XCTAssertEqual(serie.bilan?.texte, "4 mission(s) acceptée(s), 1 en conflit.")
        XCTAssertEqual(serie.ouvertes.map(\.id), ["demo-mission-013"], "les quatre missions acceptées sont relues attribuées")
        // Monde cohérent : la mission acceptée est servie attribuée par le port des missions du même monde.
        let relue = try await monde.missions.mission(id: "demo-mission-001", context: DemoWorld.context)
        XCTAssertEqual(relue?.record.statut, "ASSIGNEE")
        XCTAssertEqual(relue?.record.soignantAssigneId, DemoWorld.context.userId)
    }

    func testSerieDemoArretSurLeRefusDeConformite() async throws {
        let monde = DemoWorld.gateways()
        let session = SessionController(gateways: monde)
        let etat = await session.signIn(email: DemoWorld.context.email ?? "", password: "demonstration")
        let serie = SerieModel(serieId: "SERIE_1793577600000_demo02", controller: session, snapshot: try XCTUnwrap(etat.snapshot))
        await serie.charger()
        XCTAssertEqual(serie.missions.map(\.id), ["demo-mission-002", "demo-mission-005", "demo-mission-008", "demo-assignee-004", "demo-mission-023"])
        XCTAssertEqual(serie.selection, ["demo-mission-002", "demo-mission-005", "demo-mission-008", "demo-mission-023"],
                       "la mission déjà pourvue n'est pas sélectionnable")
        XCTAssertEqual(SerieTextes.statutFerme(serie.missions[3]), SerieTextes.dejaPourvue)
        await serie.accepter()
        let attendu = "[CODE DU TRAVAIL] Repos insuffisant avant mission : 5.0 heures au lieu de 11h minimum (Art. L3131-1). Assignation bloquée."
        XCTAssertEqual(serie.resultats, [
            "demo-mission-002": .choixContratRequis,
            "demo-mission-005": .acceptee,
            "demo-mission-008": .codeDuTravail(message: attendu),
            "demo-mission-023": .nonEnvoyee,
        ])
        XCTAssertEqual(serie.refusConformite, RefusConformiteSerie(missionId: "demo-mission-008", message: attendu))
        XCTAssertEqual(serie.bilan?.texte, "1 mission(s) acceptée(s), 2 en conflit.")
        let relue = try await monde.missions.mission(id: "demo-mission-023", context: DemoWorld.context)
        XCTAssertEqual(relue?.record.statut, "OUVERTE", "jamais envoyée : toujours ouverte")
    }
}
