import XCTest
@testable import JoleneCore

/// Modèle de la vue Swipe (lot 4, T3a ; `LOT4_PLAN.md` §2.5). Règles prouvées : carte retirée seulement après la
/// réponse du serveur ; refus et délai dépassé → message, carte en tête, aucun renvoi ; ❤️ par `SWIPE_LIKE` avec le
/// planning exact, choix de contrat rejoué ; retrait sans réinsertion (D4) ; fin de paquet → favoris ouverts à venir ;
/// réponse d'un epoch périmé ignorée ; quiz au premier contact seulement.
@MainActor
final class SwipeModelTests: XCTestCase {
    // MARK: - Ports factices

    actor Journal {
        private(set) var appels: [String] = []
        func noter(_ appel: String) { appels.append(appel) }
        func nombre(_ prefixe: String) -> Int { appels.filter { $0.hasPrefix(prefixe) }.count }
    }

    private struct AuthPrete: AuthPort {
        func restoreSession() async throws -> AuthenticatedUser? {
            AuthenticatedUser(id: "u-1", email: "u-1@example.invalid", emailConfirmedAt: Date(timeIntervalSince1970: 1_700_000_000),
                              appMetadataRole: "SOIGNANT")
        }
        func signIn(email: String, password: String) async throws -> AuthenticatedUser { throw JoleneError(.invalidCredentials, "refusé") }
        func signOut() async throws {}
    }

    private struct SwipeFactice: SwipePort {
        let journal: Journal
        var paquetLu: @Sendable () async throws -> [CarteSwipe] = { [] }
        var issue: @Sendable (String, DirectionSwipe) async throws -> SwipeOutcome = { _, _ in .enregistre }
        var retrait: @Sendable (String) async throws -> RetraitOutcome = { _ in .retiree }
        var nombre: @Sendable () async throws -> Int = { 0 }

        func paquet(context: MissionReadContext) async throws -> [CarteSwipe] {
            await journal.noter("paquet")
            return try await paquetLu()
        }
        func enregistrer(missionId: String, direction: DirectionSwipe, context: MissionReadContext) async throws -> SwipeOutcome {
            await journal.noter("enregistrer \(missionId) \(direction.rawValue)")
            return try await issue(missionId, direction)
        }
        func retirer(candidatureId: String, context: MissionReadContext) async throws -> RetraitOutcome {
            await journal.noter("retirer \(candidatureId)")
            return try await retrait(candidatureId)
        }
        func nombreSwipes(context: MissionReadContext) async throws -> Int {
            await journal.noter("nombre")
            return try await nombre()
        }
        func initialiserPreferences(_ preferences: PreferencesMatching, context: MissionReadContext) async throws {
            await journal.noter("preferences")
        }
    }

    private struct CandidatureFactice: CandidaturePort {
        let journal: Journal
        var issues: @Sendable (Int) async throws -> CandidatureOutcome

        func confirmer(action: ActionPlanning, missionId: String, creneaux: [CreneauConfirmePayload], message: String?,
                       choixContrat: String?, candidatureId: String?, context: MissionReadContext) async throws -> CandidatureOutcome {
            await journal.noter("confirmer \(action.rawValue) \(missionId) \(creneaux.count) \(choixContrat ?? "-") \(message ?? "-")")
            return try await issues(await journal.nombre("confirmer"))
        }
        func refuserProposition(candidatureId: String, context: MissionReadContext) async throws { throw JoleneError(.contract, "x") }
        func candidature(missionId: String, context: MissionReadContext) async throws -> CandidatureRecord? { nil }
        func annulerCandidature(id: String, motif: String, texte: String, justificatifPath: String?,
                                context: MissionReadContext) async throws -> AnnulationOutcome { throw JoleneError(.contract, "x") }
        func annulerMission(id: String, motif: String?, context: MissionReadContext) async throws -> AnnulationOutcome {
            throw JoleneError(.contract, "x")
        }
    }

    private struct FavorisFactices: FavorisPort {
        var lignes: [MissionSauvegardee]
        func missionsSauvegardees(context: MissionReadContext) async throws -> [MissionSauvegardee] { lignes }
        func sauvegarder(missionId: String, context: MissionReadContext) async throws -> [MissionSauvegardee] { lignes }
        func retirer(missionId: String, context: MissionReadContext) async throws -> [MissionSauvegardee] { lignes }
        func etablissementsFavoris(context: MissionReadContext) async throws -> [EtablissementFavori] { [] }
        func basculerEtablissement(id: String, actif: Bool, context: MissionReadContext) async throws -> [EtablissementFavori] { [] }
    }

    private struct MissionsFactices: MissionsPort {
        var relue: @Sendable (String) async throws -> Mission? = { _ in nil }
        func profile(userId: String) async throws -> SoignantProfile? { SoignantProfile(id: "u-1", profession: "IDE") }
        func listMissions(context: MissionReadContext, filters: MissionFilters) async throws -> [Mission] { [] }
        func mission(id: String, context: MissionReadContext) async throws -> Mission? { try await relue(id) }
    }

    // MARK: - Données

    nonisolated private static func ligne(_ id: String, nbCreneaux: Int = 1) -> LigneSwipe {
        let json = """
        {"mission_id":"\(id)","intitule":"Mission \(id)","profession_requise":"IDE","etablissement_id":"e-1",
         "etablissement_nom":"Clinique","debut_le":"2026-12-01T19:00:00+00:00","fin_le":"2026-12-02T07:00:00+00:00",
         "nb_creneaux":\(nbCreneaux),"score":80,"breakdown":{"distance":12}}
        """
        return try! JSONDecoder().decode(LigneSwipe.self, from: Data(json.utf8))
    }

    nonisolated private static func carte(_ id: String) -> CarteSwipe {
        CarteSwipe(ligne: ligne(id), creneaux: [MissionSlot(id: "\(id)-s1", missionId: id, debut: "2026-12-01T19:00:00+00:00",
                                                            fin: "2026-12-02T07:00:00+00:00", estPause: false, typeCreneau: "PREVISIONNEL")])
    }

    nonisolated private static func sauvegardee(_ id: String, statut: String = "OUVERTE", debut: String = "2026-11-20T07:00:00.000Z") -> MissionSauvegardee {
        MissionSauvegardee(id: "s-\(id)", missionId: id, creeLe: "2026-11-01T10:00:00+00:00",
                           mission: MissionSauvegardee.Apercu(id: id, intitule: "Mission \(id)", debutLe: debut, finLe: nil,
                                                              dureeHeures: 8, nbCreneaux: 1, statut: statut))
    }

    private let options = [ChoixContratOption(value: "SALARIE", label: "Salarié"), ChoixContratOption(value: "LIBERAL", label: "Libéral")]

    private func pret(swipe: SwipeFactice, candidature: CandidatureFactice? = nil, favoris: [MissionSauvegardee] = [],
                      missions: MissionsFactices = MissionsFactices(), email: String? = nil,
                      timeout: TimeInterval = SessionController.defaultResolutionTimeout) async throws -> (SwipeModel, SessionController) {
        var gateways = Lot1Fakes.gateways(clock: FixedClock(DemoWorld.fixedNow))
        gateways.auth = AuthPrete()
        gateways.missions = missions
        gateways.swipe = swipe
        gateways.favoris = FavorisFactices(lignes: favoris)
        if let candidature { gateways.candidature = candidature }
        let controller = SessionController(gateways: gateways, resolutionTimeout: timeout)
        let state = await controller.start()
        var snapshot = try XCTUnwrap(state.snapshot, "session prête attendue, obtenu \(state)")
        if let email { snapshot.context.email = email }
        return (SwipeModel(controller: controller, snapshot: snapshot), controller)
    }

    // MARK: - ✕ et ⭐

    func testCarteRetireeSeulementApresOkEtSecondGesteIgnore() async throws {
        let journal = Journal()
        let barriere = Gate()
        let swipe = SwipeFactice(journal: journal, paquetLu: { [Self.carte("m-1"), Self.carte("m-2")] },
                                 issue: { _, _ in await barriere.wait(); return .enregistre })
        let (model, _) = try await pret(swipe: swipe)
        await model.charger()
        XCTAssertEqual(model.cartes.map(\.id), ["m-1", "m-2"])
        XCTAssertTrue(model.paquetLuNonVide)

        let geste = Task { await model.passer("m-1") }
        await waitUntil { await journal.nombre("enregistrer") == 1 }
        XCTAssertEqual(model.cartes.map(\.id), ["m-1", "m-2"], "aucun retrait avant la réponse du serveur")
        XCTAssertEqual(model.actionEnCours, "m-1")
        await model.passer("m-2")
        await model.sauvegarder("m-1")
        let enVol = await journal.nombre("enregistrer")
        XCTAssertEqual(enVol, 1, "un second geste pendant l'appel est ignoré")
        await barriere.open()
        await geste.value
        XCTAssertEqual(model.cartes.map(\.id), ["m-2"])
        XCTAssertNil(model.message)
        XCTAssertNil(model.actionEnCours)

        await model.sauvegarder("m-2")
        XCTAssertEqual(model.annonce, .favoriSauvegarde(missionId: "m-2"))
        let appels = await journal.appels
        XCTAssertEqual(appels.filter { $0.hasPrefix("enregistrer") }, ["enregistrer m-1 DISLIKE", "enregistrer m-2 FAVORI"])
    }

    func testRefusRemetEnTeteSaufRefusHorsPaquet() async throws {
        let journal = Journal()
        let swipe = SwipeFactice(journal: journal, paquetLu: { [Self.carte("m-1"), Self.carte("m-2")] }, issue: { id, _ in
            let code = id == "m-2" ? "direction_invalide" : "mission_deja_swipee"
            let refus = SwipeRefus.traduire(code)
            return .refuse(code: refus.code, message: refus.message)
        })
        let (model, _) = try await pret(swipe: swipe)
        await model.charger()
        await model.passer("m-2")
        XCTAssertEqual(model.message, SwipeRefus.libelles["direction_invalide"])
        XCTAssertEqual(model.cartes.map(\.id), ["m-2", "m-1"], "carte refusée remise en tête")
        await model.passer("m-1")
        XCTAssertEqual(model.message, "Vous avez déjà répondu à cette mission.")
        XCTAssertEqual(model.cartes.map(\.id), ["m-2"], "ligne swipes déjà posée : la carte ne reviendrait pas")
    }

    /// Revue B8 de #1165, m1 : `acces_refuse` (établissement qui a exclu le soignant) et `profession_incompatible` sont
    /// refusés avant l'écriture de la ligne `swipes`, et le paquet relu les resservirait (`fn_soignant_eligible_mission`
    /// ne filtre pas `fn_est_exclu`) : la carte est écartée pour la session, jamais remise en tête.
    func testAccesRefuseEtProfessionIncompatibleEcartentLaCartePourLaSession() async throws {
        let journal = Journal()
        let swipe = SwipeFactice(journal: journal, paquetLu: { [Self.carte("m-1"), Self.carte("m-2"), Self.carte("m-3")] },
                                 issue: { _, _ in
                                     let refus = SwipeRefus.traduire("acces_refuse")
                                     return .refuse(code: refus.code, message: refus.message)
                                 })
        let candidature = CandidatureFactice(journal: journal) { _ in
            let refus = SwipeRefus.traduire("profession_incompatible")
            return .refusee(code: refus.code, message: refus.message, documentsRequisPour: nil)
        }
        let (model, _) = try await pret(swipe: swipe, candidature: candidature)
        await model.charger()
        await model.passer("m-2")
        XCTAssertEqual(model.message, SwipeRefus.libelles["acces_refuse"])
        XCTAssertEqual(model.cartes.map(\.id), ["m-1", "m-3"], "jamais remise en tête : elle bloquerait le paquet")
        await model.candidater("m-3")
        XCTAssertEqual(model.message, SwipeRefus.libelles["profession_incompatible"])
        XCTAssertEqual(model.cartes.map(\.id), ["m-1"])

        await model.charger()
        XCTAssertEqual(model.cartes.map(\.id), ["m-1"], "le serveur les resert : écartées des paquets relus de la session")
        XCTAssertTrue(model.paquetLuNonVide)
        let lectures = await journal.nombre("paquet")
        XCTAssertEqual(lectures, 2)
    }

    func testDelaiDepasseMessageCarteRemiseAucunRenvoi() async throws {
        let journal = Journal()
        let jamais = Gate()
        let swipe = SwipeFactice(journal: journal, paquetLu: { [Self.carte("m-1"), Self.carte("m-2")] },
                                 issue: { _, _ in await jamais.wait(); return .enregistre })
        let (model, _) = try await pret(swipe: swipe, timeout: 0.05)
        await model.charger()
        await model.sauvegarder("m-2")
        XCTAssertEqual(model.message, SessionController.timeoutMessage)
        XCTAssertEqual(model.cartes.map(\.id), ["m-2", "m-1"], "un délai ne prouve rien : carte remise en tête")
        let appels = await journal.nombre("enregistrer")
        XCTAssertEqual(appels, 1, "aucun renvoi automatique")
        XCTAssertNil(model.annonce)
        await jamais.open()
    }

    // MARK: - ❤️

    func testCandidatureSwipeLikePuisRetraitSansReinsertion() async throws {
        let journal = Journal()
        let swipe = SwipeFactice(journal: journal, paquetLu: { [Self.carte("m-1"), Self.carte("m-2")] })
        let candidature = CandidatureFactice(journal: journal) { _ in .confirmed(candidatureId: "c-1", contratId: nil) }
        let (model, _) = try await pret(swipe: swipe, candidature: candidature)
        await model.charger()
        await model.candidater("m-1")
        let appels = await journal.appels
        XCTAssertEqual(appels.filter { $0.hasPrefix("confirmer") }, ["confirmer SWIPE_LIKE m-1 1 - -"],
                       "SWIPE_LIKE, planning exact (un créneau), sans choix de contrat ni message")
        XCTAssertEqual(model.cartes.map(\.id), ["m-2"])
        XCTAssertEqual(model.annonce, .candidatureEnvoyee(missionId: "m-1"))
        XCTAssertEqual(model.candidatureAnnulable, SwipeModel.CandidatureAnnulable(candidatureId: "c-1", missionId: "m-1"))

        await model.retirerCandidature()
        let retraits = await journal.appels.filter { $0.hasPrefix("retirer") }
        XCTAssertEqual(retraits, ["retirer c-1"])
        XCTAssertEqual(model.annonce, .candidatureRetiree(missionId: "m-1"))
        XCTAssertEqual(model.cartes.map(\.id), ["m-2"], "D4 : la carte n'est jamais remise dans le paquet")
        XCTAssertNil(model.candidatureAnnulable)
        await model.retirerCandidature()
        let nombre = await journal.nombre("retirer")
        XCTAssertEqual(nombre, 1, "un seul retrait par candidature")
    }

    func testChoixDeContratDemandePuisRejoueAvecLOption() async throws {
        let journal = Journal()
        let swipe = SwipeFactice(journal: journal, paquetLu: { [Self.carte("m-2"), Self.carte("m-1")] })
        let options = self.options
        let candidature = CandidatureFactice(journal: journal) { rang in
            rang == 1 ? .choixRequis(options) : .confirmed(candidatureId: "c-9", contratId: nil)
        }
        let (model, _) = try await pret(swipe: swipe, candidature: candidature)
        await model.charger()
        await model.candidater("m-1")
        XCTAssertEqual(model.optionsContrat, options)
        XCTAssertEqual(model.missionChoixContrat, "m-1")
        XCTAssertEqual(model.cartes.map(\.id), ["m-1", "m-2"], "la carte attend le choix, en tête")
        await model.candidater("m-1", choixContrat: "LIBERAL")
        let appels = await journal.appels.filter { $0.hasPrefix("confirmer") }
        XCTAssertEqual(appels.last, "confirmer SWIPE_LIKE m-1 1 LIBERAL -")
        XCTAssertEqual(model.cartes.map(\.id), ["m-2"])
        XCTAssertTrue(model.optionsContrat.isEmpty)
    }

    func testPlanningModifieRelitLaMissionSansRenvoi() async throws {
        let journal = Journal()
        let swipe = SwipeFactice(journal: journal, paquetLu: { [Self.carte("m-2"), Self.carte("m-1")] })
        let candidature = CandidatureFactice(journal: journal) { _ in
            .planningAReconfirmer(code: "PLANNING_MODIFIE_RECONFIRMER", message: "Le planning a changé depuis son affichage.")
        }
        var relue = Self.carte("m-1").mission
        relue.record.nbCreneaux = 2
        relue.creneauxPlanifies.append(MissionSlot(id: "m-1-s2", missionId: "m-1", debut: "2026-12-03T19:00:00+00:00",
                                                   fin: "2026-12-04T07:00:00+00:00", estPause: false, typeCreneau: "PREVISIONNEL"))
        let lue = relue
        let (model, _) = try await pret(swipe: swipe, candidature: candidature, missions: MissionsFactices(relue: { _ in lue }))
        await model.charger()
        await model.candidater("m-1")
        XCTAssertEqual(model.message, "Le planning a changé depuis son affichage.")
        XCTAssertEqual(model.cartes.map(\.id), ["m-1", "m-2"])
        XCTAssertEqual(model.cartes.first?.mission.creneauxPlanifies.count, 2, "planning relu, jamais supposé")
        XCTAssertEqual(model.cartes.first?.score, 80, "score du paquet conservé")
        let confirmations = await journal.nombre("confirmer")
        XCTAssertEqual(confirmations, 1, "aucun renvoi automatique")
    }

    // MARK: - Fin de paquet, epoch, quiz

    func testFinDePaquetReproposeLesFavorisOuvertsAVenir() async throws {
        let journal = Journal()
        let swipe = SwipeFactice(journal: journal, paquetLu: { [Self.carte("m-1")] })
        let favoris = [Self.sauvegardee("f-1"), Self.sauvegardee("f-passee", debut: "2026-10-01T07:00:00.000Z"),
                       Self.sauvegardee("f-assignee", statut: "ASSIGNEE")]
        let (model, _) = try await pret(swipe: swipe, favoris: favoris)
        await model.charger()
        XCTAssertFalse(model.finDePaquet)
        XCTAssertTrue(model.favorisFinDePaquet.isEmpty, "favoris lus seulement en fin de paquet")
        await model.passer("m-1")
        XCTAssertTrue(model.finDePaquet)
        XCTAssertTrue(model.paquetLuNonVide, "« tout vu » plutôt que « aucune nouvelle mission »")
        XCTAssertEqual(model.favorisFinDePaquet.map(\.missionId), ["f-1"], "OUVERTE et à venir seulement")
    }

    func testReponseDUnEpochPerimeIgnoree() async throws {
        let journal = Journal()
        let barriere = Gate()
        let swipe = SwipeFactice(journal: journal, paquetLu: { await barriere.wait(); return [Self.carte("m-1")] })
        let (model, controller) = try await pret(swipe: swipe)
        let lecture = Task { await model.charger() }
        await waitUntil { await journal.nombre("paquet") == 1 }
        _ = await controller.signOut()
        await barriere.open()
        await lecture.value
        XCTAssertTrue(model.cartes.isEmpty, "le paquet d'une identité retirée n'est jamais publié")
        XCTAssertEqual(model.etat, .chargement)
        await model.passer("m-1")
        let appels = await journal.nombre("enregistrer")
        XCTAssertEqual(appels, 0)
    }

    func testQuizAuPremierContactSeulement() async throws {
        let journal = Journal()
        let (sansSwipe, _) = try await pret(swipe: SwipeFactice(journal: journal, nombre: { 0 }))
        let propose = await sansSwipe.quizAProposer(dejaVu: false)
        let dejaVu = await sansSwipe.quizAProposer(dejaVu: true)
        XCTAssertTrue(propose)
        XCTAssertFalse(dejaVu)
        let lectures = await journal.nombre("nombre")
        XCTAssertEqual(lectures, 1, "marqueur local posé : aucune lecture")

        let (avecSwipes, _) = try await pret(swipe: SwipeFactice(journal: journal, nombre: { 3 }))
        let dejaSwipe = await avecSwipes.quizAProposer(dejaVu: false)
        XCTAssertFalse(dejaSwipe)
        let (illisible, _) = try await pret(swipe: SwipeFactice(journal: journal, nombre: { throw JoleneError(.network, "coupure") }))
        let echec = await illisible.quizAProposer(dejaVu: false)
        XCTAssertFalse(echec, "compte illisible : rien n'est proposé")
        let (e2e, _) = try await pret(swipe: SwipeFactice(journal: journal, nombre: { 0 }), email: "playwright-x@example.invalid")
        let playwright = await e2e.quizAProposer(dejaVu: false)
        XCTAssertFalse(playwright, "comptes E2E : jamais de quiz, comme le web")

        let horsBornes = await sansSwipe.appliquerQuiz(PreferencesMatching(nuit: 2, jour: 0, weekend: 0, semaine: 0))
        XCTAssertFalse(horsBornes)
        let applique = await sansSwipe.appliquerQuiz(.depuisQuiz(horaire: .nuit, rythme: .tous))
        XCTAssertTrue(applique)
        let envois = await journal.nombre("preferences")
        XCTAssertEqual(envois, 1, "rien n'est envoyé hors bornes")
    }
}
