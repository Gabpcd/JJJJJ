import XCTest
@testable import JoleneCore

/// Modèle des présences de l'établissement (lot 5, T8, B9) : onglets dérivés, créneaux relus avant toute validation
/// (web l.213-249), un seul appel par geste (bouton désactivé pendant l'envoi), issue inconnue relue jamais renvoyée,
/// note au mieux qui ne défait jamais la validation, lot limité aux présences sans alerte revérifiées, contestation à
/// motif borné, clôture sans heure future (D28), refus serveur mot pour mot, refus de droit relu une fois, aucune action
/// sans la permission `pointage`. Session établissement réelle du monde démo, port des présences scripté.
@MainActor
final class PresencesEtabModelTests: XCTestCase {
    private struct PanneTest: Error {}

    /// Porte : retient un appel du port jusqu'à son ouverture (mesure de l'état « envoi en cours »).
    private actor Porte {
        private var ouverte = false
        private var attentes: [CheckedContinuation<Void, Never>] = []

        func attendre() async {
            if ouverte { return }
            await withCheckedContinuation { attentes.append($0) }
        }

        func ouvrir() {
            ouverte = true
            attentes.forEach { $0.resume() }
            attentes = []
        }
    }

    /// Port scripté : chaque lecture et chaque mutation consomme sa file ; tout appel s'inscrit au journal.
    private final class Script: EtabPresencesPort, @unchecked Sendable {
        private let lock = NSLock()
        private var listes: [[PresenceEtab]]
        private var journal: [String] = []
        var terminees: [EtabMissionResume] = []
        var creneauxRelus: [String: [MissionSlot]] = [:]
        var panneCreneaux = false
        var validations: [Result<ValidationPresenceOutcome, Error>] = []
        var lots: [Result<ValidationLotOutcome, Error>] = []
        var contestations: [Result<ContestationOutcome, Error>] = []
        var notes: [Result<NotationOutcome, Error>] = []
        var clotures: [Result<ClotureOutcome, Error>] = []
        var porte: Porte?

        init(_ listes: [PresenceEtab]...) { self.listes = listes }

        var appels: [String] { lock.withLock { journal } }
        var mutations: [String] { appels.filter { !$0.hasPrefix("presences") && !$0.hasPrefix("terminees") && !$0.hasPrefix("creneaux") } }

        private func noter(_ appel: String) { lock.withLock { journal.append(appel) } }

        private func suivant<T>(_ file: inout [Result<T, Error>]) throws -> T {
            lock.lock()
            let resultat: Result<T, Error> = file.isEmpty ? .failure(PanneTest()) : file.removeFirst()
            lock.unlock()
            return try resultat.get()
        }

        /// Chaque lecture consomme une liste ; la dernière reste servie.
        func presences(context: EtablissementReadContext) async throws -> [PresenceEtab] {
            lireListe()
        }

        private func lireListe() -> [PresenceEtab] {
            lock.lock()
            defer { lock.unlock() }
            journal.append("presences")
            return listes.count > 1 ? listes.removeFirst() : (listes.first ?? [])
        }

        func missionsTerminees(context: EtablissementReadContext) async throws -> [EtabMissionResume] {
            noter("terminees")
            return terminees
        }

        func creneaux(missionId: String, context: EtablissementReadContext) async throws -> [MissionSlot] {
            noter("creneaux \(missionId)")
            if panneCreneaux { throw PanneTest() }
            return creneauxRelus[missionId] ?? []
        }

        func valider(presenceId: String, context: EtablissementReadContext) async throws -> ValidationPresenceOutcome {
            noter("valider \(presenceId)")
            await porte?.attendre()
            return try suivant(&validations)
        }

        func validerLot(ids: [String], context: EtablissementReadContext) async throws -> ValidationLotOutcome {
            noter("lot \(ids.joined(separator: ","))")
            return try suivant(&lots)
        }

        func contester(presenceId: String, motif: String, context: EtablissementReadContext) async throws -> ContestationOutcome {
            noter("contester \(presenceId) [\(motif)]")
            return try suivant(&contestations)
        }

        func noter(missionId: String, note: Int, context: EtablissementReadContext) async throws -> NotationOutcome {
            noter("noter \(missionId) \(note)")
            return try suivant(&notes)
        }

        func cloturerSegment(missionId: String, heureFin: Date, context: EtablissementReadContext) async throws -> ClotureOutcome {
            noter("cloturer \(missionId) \(DateHeureParis.isoUTC(heureFin))")
            return try suivant(&clotures)
        }
    }

    private final class Compteur: @unchecked Sendable {
        private let lock = NSLock()
        private var valeur = 0
        var nombre: Int { lock.withLock { valeur } }
        func incrementer() { lock.withLock { valeur += 1 } }
    }

    // MARK: - Données (horloge du monde démo : 2026-11-02T00:00:00Z)

    private func creneau(_ id: String, _ mission: String, _ debut: String, _ fin: String?, type: String = "PREVISIONNEL") -> MissionSlot {
        MissionSlot(id: id, missionId: mission, debut: debut, fin: fin, estPause: false, typeCreneau: type)
    }

    private func terminee(_ mission: String) -> [MissionSlot] {
        [creneau("\(mission)-p", mission, "2026-10-31T06:00:00Z", "2026-10-31T14:00:00Z"),
         creneau("\(mission)-e", mission, "2026-10-31T06:01:00Z", "2026-10-31T14:03:00Z", type: "EFFECTIF")]
    }

    private func ouverte(_ mission: String) -> [MissionSlot] {
        [creneau("\(mission)-p", mission, "2026-11-01T23:00:00Z", "2026-11-02T07:00:00Z"),
         creneau("\(mission)-e", mission, "2026-11-01T23:58:00Z", nil, type: "EFFECTIF")]
    }

    private func presence(_ id: String, mission: String, creneaux: [MissionSlot], valide: Bool = false, perimetre: Bool? = true,
                          motif: String? = nil) -> PresenceEtab {
        PresenceEtab(id: id, missionId: mission, valideParEtablissement: valide, valideLe: valide ? "2026-11-02T00:00:01Z" : nil,
                     motifLitige: motif, soignantId: "demo-soignant", distanceEtablissementM: 30, perimetreGpsValide: perimetre,
                     alerteTeleportation: false,
                     mission: MissionPresenceEtab(id: mission, intitule: "Mission \(mission)", debutLe: creneaux.first?.debut,
                                                  finLe: creneaux.first?.fin, nbCreneaux: 1, etablissementId: "demo-etab-1"),
                     creneaux: creneaux)
    }

    private func aValider(_ id: String = "p-1", mission: String = "m-1", perimetre: Bool? = true) -> PresenceEtab {
        presence(id, mission: mission, creneaux: terminee(mission), perimetre: perimetre)
    }

    private func validee(_ id: String = "p-1", mission: String = "m-1") -> PresenceEtab {
        presence(id, mission: mission, creneaux: terminee(mission), valide: true)
    }

    private func modele(_ script: Script, role: RoleEtab = .proprietaire, missionId: String? = nil,
                        relectures: Compteur = Compteur()) async throws -> PresencesEtabModel {
        var gateways = DemoWorld.gateways(espace: .etablissement(.init(role: role)))
        gateways.etablissement.presences = script
        let controller = SessionController(gateways: gateways, espaceEtablissement: .ouvert)
        _ = await controller.start()
        let etat = await controller.signIn(email: DemoEspace.emailEtablissement, password: "demo")
        guard case let .readyEtablissement(snapshot) = etat else {
            XCTFail("espace établissement démo attendu, obtenu \(etat)")
            throw PanneTest()
        }
        let model = PresencesEtabModel(missionId: missionId, controller: controller, snapshot: snapshot,
                                       relirePerimetre: { relectures.incrementer() })
        await model.charger()
        return model
    }

    /// Attend qu'une condition soit vraie en laissant tourner les tâches (au plus 2 s).
    private func attendre(_ condition: @MainActor () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<400 where !condition() { try? await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertTrue(condition(), "condition jamais atteinte", file: file, line: line)
    }

    // MARK: - Lecture et onglets

    func testChargementOngletsDerivesEtSoignantsLus() async throws {
        let script = Script([aValider("p-1", mission: "m-1"), aValider("p-2", mission: "m-2", perimetre: false),
                             presence("p-3", mission: "m-3", creneaux: ouverte("m-3")), validee("p-4", mission: "m-4")])
        script.terminees = [EtabMissionResume(id: "m-1", intitule: "Pointée"), EtabMissionResume(id: "m-9", intitule: "Sans pointage")]
        let model = try await modele(script)
        XCTAssertEqual(model.etat, .chargee)
        XCTAssertEqual(model.onglet, .aValider)
        XCTAssertEqual(model.repartition.aValider.map(\.id), ["p-1", "p-2"])
        XCTAssertEqual(model.repartition.enCours.map(\.id), ["p-3"])
        XCTAssertEqual(model.repartition.validees.map(\.id), ["p-4"])
        XCTAssertEqual(model.missionsSansPointage.map(\.id), ["m-9"])
        XCTAssertEqual(OngletPresencesEtab.allCases.map { model.nombre($0) }, [2, 1, 1, 2], "alertes : 1 hors zone + 1 mission sans pointage")
        XCTAssertEqual(model.lotEligibles.map(\.id), ["p-1"])
        XCTAssertEqual(model.maintenant, DemoWorld.fixedNow, "horloge des gateways, jamais posée localement")
        XCTAssertEqual(model.carte(model.presences[0]).titre, "Camille Démo · Infirmier(ère) Diplômé(e) d'État (IDE)",
                       "nom lu par fn_soignant_pour_etablissement (port de T5)")
        XCTAssertTrue(model.peutAgir)
        XCTAssertEqual(script.mutations, [])
        model.selectionner(.alertes)
        XCTAssertEqual(model.onglet, .alertes)
    }

    func testEchecDeLecturePuisRelectureQuiConserveLaListe() async throws {
        final class Panne: EtabPresencesPort, @unchecked Sendable {
            func presences(context: EtablissementReadContext) async throws -> [PresenceEtab] { throw JoleneError(.network, "Hors ligne.") }
            func missionsTerminees(context: EtablissementReadContext) async throws -> [EtabMissionResume] { [] }
            func creneaux(missionId: String, context: EtablissementReadContext) async throws -> [MissionSlot] { [] }
            func valider(presenceId: String, context: EtablissementReadContext) async throws -> ValidationPresenceOutcome { throw PanneTest() }
            func validerLot(ids: [String], context: EtablissementReadContext) async throws -> ValidationLotOutcome { throw PanneTest() }
            func contester(presenceId: String, motif: String, context: EtablissementReadContext) async throws -> ContestationOutcome { throw PanneTest() }
            func noter(missionId: String, note: Int, context: EtablissementReadContext) async throws -> NotationOutcome { throw PanneTest() }
            func cloturerSegment(missionId: String, heureFin: Date, context: EtablissementReadContext) async throws -> ClotureOutcome { throw PanneTest() }
        }
        var gateways = DemoWorld.gateways(espace: .etablissement(.init()))
        gateways.etablissement.presences = Panne()
        let controller = SessionController(gateways: gateways, espaceEtablissement: .ouvert)
        _ = await controller.start()
        guard case let .readyEtablissement(snapshot) = await controller.signIn(email: DemoEspace.emailEtablissement, password: "demo") else {
            return XCTFail("espace établissement démo attendu")
        }
        let model = PresencesEtabModel(controller: controller, snapshot: snapshot)
        await model.charger()
        XCTAssertEqual(model.etat, .echec("Hors ligne."))
        XCTAssertTrue(model.presences.isEmpty)
    }

    func testFiltreDeLaMissionPourLaDestinationPresencesMission() async throws {
        let script = Script([aValider("p-1", mission: "m-1"), aValider("p-2", mission: "m-2")])
        script.terminees = [EtabMissionResume(id: "m-2", intitule: "x"), EtabMissionResume(id: "m-9", intitule: "y")]
        let model = try await modele(script, missionId: "m-2")
        XCTAssertEqual(model.presences.map(\.id), ["p-2"])
        XCTAssertTrue(model.missionsSansPointage.isEmpty, "m-9 n'est pas la mission affichée ; m-2 est pointée")
    }

    // MARK: - Validation

    func testValidationNoteObligatoireCreneauxRelusPuisNoteEtRelecture() async throws {
        let script = Script([aValider()], [validee()])
        script.creneauxRelus["m-1"] = terminee("m-1")
        script.validations = [.success(.validee(valideLe: "2026-11-02T00:00:01Z"))]
        script.notes = [.success(.enregistree)]
        let model = try await modele(script)

        model.ouvrirValidation(presenceId: "p-1")
        XCTAssertEqual(model.validation, PresencesEtabModel.Validation(presenceId: "p-1", note: 0, prenom: "Camille"))
        XCTAssertFalse(model.peutConfirmerValidation, "aucune validation sans note (parité F4)")
        await model.confirmerValidation()
        XCTAssertEqual(script.mutations, [], "sans note, rien n'est envoyé")
        model.choisirNote(9)
        XCTAssertEqual(model.validation?.note, 0)
        model.choisirNote(4)
        XCTAssertTrue(model.peutConfirmerValidation)

        await model.confirmerValidation()
        XCTAssertEqual(script.appels.filter { $0 != "presences" && $0 != "terminees" }, ["creneaux m-1", "valider p-1", "noter m-1 4"],
                       "créneaux relus avant l'envoi, note après la validation relue")
        XCTAssertEqual(script.appels.suffix(2).sorted(), ["presences", "terminees"], "puis liste relue")
        XCTAssertEqual(script.appels.count, 7)
        XCTAssertNil(model.validation)
        XCTAssertEqual(model.annonce, .succes("Présence validée et note 4/5 envoyée !"))
        XCTAssertEqual(model.repartition.validees.map(\.id), ["p-1"], "« Validée » vient de la liste relue")
        XCTAssertNil(model.enCours)
    }

    func testCreneauxRelusNonEligiblesAucunEnvoi() async throws {
        let script = Script([aValider()])
        // Une autre session a ouvert un pointage depuis le chargement de la page.
        script.creneauxRelus["m-1"] = terminee("m-1") + [creneau("m-1-e2", "m-1", "2026-11-01T22:00:00Z", nil, type: "EFFECTIF")]
        let model = try await modele(script)
        model.ouvrirValidation(presenceId: "p-1")
        model.choisirNote(5)
        await model.confirmerValidation()
        XCTAssertEqual(script.mutations, [], "ni validation ni note")
        XCTAssertEqual(model.annonce, .avertissement(PresencesEtabPresentation.plusEligible))
        XCTAssertNil(model.validation)
        XCTAssertEqual(script.appels.filter { $0 == "presences" }.count, 2, "liste relue")

        // Relecture des créneaux en échec : même prudence (fail-closed).
        let panne = Script([aValider()])
        panne.panneCreneaux = true
        let second = try await modele(panne)
        second.ouvrirValidation(presenceId: "p-1")
        second.choisirNote(5)
        await second.confirmerValidation()
        XCTAssertEqual(panne.mutations, [])
        XCTAssertEqual(second.annonce, .avertissement(PresencesEtabPresentation.plusEligible))
    }

    func testUnSeulAppelPendantLEnvoiBoutonDesactive() async throws {
        let script = Script([aValider()], [validee()])
        script.creneauxRelus["m-1"] = terminee("m-1")
        script.validations = [.success(.validee(valideLe: "2026-11-02T00:00:01Z")), .success(.validee(valideLe: "x"))]
        script.notes = [.success(.enregistree), .success(.enregistree)]
        let porte = Porte()
        script.porte = porte
        let model = try await modele(script)
        model.ouvrirValidation(presenceId: "p-1")
        model.choisirNote(3)

        let envoi = Task { await model.confirmerValidation() }
        await attendre { script.mutations == ["valider p-1"] }
        XCTAssertEqual(model.enCours, "p-1")
        XCTAssertFalse(model.peutConfirmerValidation, "bouton désactivé pendant l'appel")
        await model.confirmerValidation() // second toucher
        model.annulerValidation()
        XCTAssertNotNil(model.validation, "la feuille ne se ferme pas pendant l'envoi")
        model.ouvrirContestation(presenceId: "p-1")
        XCTAssertNil(model.contestation, "aucune autre action pendant l'envoi")
        model.ouvrirLot()
        XCTAssertFalse(model.lotOuvert)
        await porte.ouvrir()
        await envoi.value
        XCTAssertEqual(script.mutations, ["valider p-1", "noter m-1 3"], "double toucher = un seul appel")
        XCTAssertNil(model.enCours)
    }

    func testIssueInconnueRelueJamaisRenvoyee() async throws {
        // Délai dépassé, mais le serveur a validé : la relecture le montre, la note part, rien n'est renvoyé.
        let script = Script([aValider()], [validee()])
        script.creneauxRelus["m-1"] = terminee("m-1")
        script.validations = [.failure(JoleneError(.network, SessionController.timeoutMessage))]
        script.notes = [.success(.enregistree)]
        let model = try await modele(script)
        model.ouvrirValidation(presenceId: "p-1")
        model.choisirNote(5)
        await model.confirmerValidation()
        XCTAssertEqual(script.mutations, ["valider p-1", "noter m-1 5"], "une seule validation envoyée")
        XCTAssertEqual(model.annonce, .succes("Présence validée et note 5/5 envoyée !"))
        XCTAssertEqual(model.repartition.validees.map(\.id), ["p-1"])

        // Délai dépassé et présence relue non validée : erreur affichée, aucun renvoi, aucune note.
        let echec = Script([aValider()])
        echec.creneauxRelus["m-1"] = terminee("m-1")
        echec.validations = [.failure(JoleneError(.network, SessionController.timeoutMessage))]
        let second = try await modele(echec)
        second.ouvrirValidation(presenceId: "p-1")
        second.choisirNote(5)
        await second.confirmerValidation()
        XCTAssertEqual(echec.mutations, ["valider p-1"])
        XCTAssertEqual(second.annonce, .erreur(SessionController.timeoutMessage))
        XCTAssertEqual(second.repartition.aValider.map(\.id), ["p-1"], "jamais « Validée » sans relecture")
        XCTAssertNil(second.validation)
    }

    func testNoteEnEchecNeDefaitJamaisLaValidation() async throws {
        let refusServeur = "Seules les missions TERMINEE peuvent être notées"
        let cas: [(Result<NotationOutcome, Error>, String?)] = [
            (.success(.nonEnregistree(message: refusServeur)), refusServeur),
            (.failure(PanneTest()), nil),
            (.success(.nonEnregistree(message: nil)), nil),
        ]
        for (note, avis) in cas {
            let script = Script([aValider()], [validee()])
            script.creneauxRelus["m-1"] = terminee("m-1")
            script.validations = [.success(.validee(valideLe: "2026-11-02T00:00:01Z"))]
            script.notes = [note]
            let model = try await modele(script)
            model.ouvrirValidation(presenceId: "p-1")
            model.choisirNote(2)
            await model.confirmerValidation()
            XCTAssertEqual(model.annonce, .succes("Présence validée !"), "validation acquise sans la note (web l.306)")
            XCTAssertEqual(model.avisNote, avis, "refus serveur de la note mot pour mot, à part")
            XCTAssertEqual(model.repartition.validees.map(\.id), ["p-1"])
            XCTAssertEqual(script.mutations, ["valider p-1", "noter m-1 2"])
        }
    }

    func testRefusServeurVerbatimEtRefusDeDroitReluUneFois() async throws {
        let refus = Script([aValider()])
        refus.creneauxRelus["m-1"] = terminee("m-1")
        refus.validations = [.success(.refusee(message: "Un pointage est encore ouvert pour cette mission."))]
        let relectures = Compteur()
        let model = try await modele(refus, relectures: relectures)
        model.ouvrirValidation(presenceId: "p-1")
        model.choisirNote(4)
        await model.confirmerValidation()
        XCTAssertEqual(model.annonce, .erreur("Un pointage est encore ouvert pour cette mission."))
        XCTAssertEqual(refus.mutations, ["valider p-1"], "aucune note sans validation")
        XCTAssertEqual(relectures.nombre, 0)

        let droit = Script([aValider()])
        droit.creneauxRelus["m-1"] = terminee("m-1")
        droit.validations = [.success(.accesRefuse(message: "Votre rôle dans cet établissement ne permet pas cette action."))]
        let second = try await modele(droit, relectures: relectures)
        second.ouvrirValidation(presenceId: "p-1")
        second.choisirNote(4)
        await second.confirmerValidation()
        XCTAssertEqual(second.annonce, .erreur("Votre rôle dans cet établissement ne permet pas cette action."))
        XCTAssertEqual(relectures.nombre, 1, "périmètre relu une fois, jamais une déconnexion")
        XCTAssertEqual(droit.mutations, ["valider p-1"])
    }

    // MARK: - Permissions

    func testSansPermissionPointageAucuneAction() async throws {
        let script = Script([aValider(), presence("p-3", mission: "m-3", creneaux: ouverte("m-3"))])
        script.creneauxRelus["m-1"] = terminee("m-1")
        let model = try await modele(script, role: .lectureSeule)
        XCTAssertEqual(model.etat, .chargee, "la lecture reste ouverte")
        XCTAssertFalse(model.peutAgir)
        model.ouvrirValidation(presenceId: "p-1")
        model.ouvrirContestation(presenceId: "p-1")
        model.ouvrirLot()
        model.ouvrirCloture(missionId: "m-3")
        XCTAssertNil(model.validation)
        XCTAssertNil(model.contestation)
        XCTAssertNil(model.cloture)
        XCTAssertFalse(model.lotOuvert)
        await model.confirmerValidation()
        await model.confirmerLot()
        await model.envoyerContestation()
        await model.confirmerCloture(saisie: "2026-11-02T01:00")
        XCTAssertEqual(script.mutations, [])

        let pointage = try await modele(Script([aValider()]), role: .pointageOnly)
        XCTAssertTrue(pointage.peutAgir, "POINTAGE_ONLY : la permission servie suffit, aucune table de rôles ici")
        // Permissions relues à epoch constant : l'écran re-filtre sans être reconstruit.
        var retire = pointage.context
        retire.permissions = PermissionsEtab(accordees: [.lecture])
        pointage.adopter(retire)
        XCTAssertFalse(pointage.peutAgir)
        var autreEpoch = pointage.context
        autreEpoch.epoch += 1
        autreEpoch.permissions = PermissionsEtab(accordees: Set(PermissionEtab.allCases))
        pointage.adopter(autreEpoch)
        XCTAssertFalse(pointage.peutAgir, "un contexte d'un autre epoch n'est jamais adopté")
    }

    // MARK: - Lot

    func testLotEnvoieLesEligiblesRevérifieesEtAfficheLeResultatRelu() async throws {
        let liste = [aValider("p-1", mission: "m-1"), aValider("p-2", mission: "m-2", perimetre: false),
                     aValider("p-3", mission: "m-3"), aValider("p-4", mission: "m-4")]
        let script = Script(liste, [validee("p-1", mission: "m-1"), liste[1], liste[2], liste[3]])
        script.creneauxRelus = ["m-1": terminee("m-1"), "m-4": terminee("m-4"),
                                "m-3": terminee("m-3") + [creneau("m-3-e2", "m-3", "2026-11-01T22:00:00Z", nil, type: "EFFECTIF")]]
        script.lots = [.success(.traitee(validees: 1, selectionnees: 2))]
        let model = try await modele(script)
        XCTAssertEqual(model.lotEligibles.map(\.id), ["p-1", "p-3", "p-4"], "p-2 hors zone : jamais dans le lot")
        await model.confirmerLot()
        XCTAssertEqual(script.mutations, [], "rien sans confirmation")
        model.ouvrirLot()
        XCTAssertTrue(model.lotOuvert)
        await model.confirmerLot()
        XCTAssertEqual(script.mutations, ["lot p-1,p-4"], "p-3 a un pointage ouvert à la relecture : retirée de l'envoi")
        XCTAssertEqual(model.annonce, .lot("1 présence validée sur 2 sélectionnées.", complet: false), "comptes relus par la gateway")
        XCTAssertFalse(model.lotOuvert)
        XCTAssertEqual(model.repartition.validees.map(\.id), ["p-1"])
        XCTAssertEqual(script.appels.filter { $0.hasPrefix("noter") }, [], "le lot ne note pas (web l.333-374)")
    }

    func testLotSansEligibleReluOuIssueInconnue() async throws {
        let aucune = Script([aValider()])
        aucune.creneauxRelus["m-1"] = []
        let model = try await modele(aucune)
        model.ouvrirLot()
        await model.confirmerLot()
        XCTAssertEqual(aucune.mutations, [])
        XCTAssertEqual(model.annonce, .avertissement(PresencesEtabPresentation.lotPlusEligible))

        // Issue inconnue : la liste relue fait foi, le lot n'est pas renvoyé.
        let inconnue = Script([aValider()], [validee()])
        inconnue.creneauxRelus["m-1"] = terminee("m-1")
        inconnue.lots = [.failure(JoleneError(.network, SessionController.timeoutMessage))]
        let second = try await modele(inconnue)
        second.ouvrirLot()
        await second.confirmerLot()
        XCTAssertEqual(inconnue.mutations, ["lot p-1"])
        XCTAssertEqual(second.annonce, .lot("1 présence validée sur 1 sélectionnée.", complet: true))

        let refus = Script([aValider()])
        refus.creneauxRelus["m-1"] = terminee("m-1")
        refus.lots = [.success(.refusee(message: "Non autorisé"))]
        let troisieme = try await modele(refus)
        troisieme.ouvrirLot()
        await troisieme.confirmerLot()
        XCTAssertEqual(troisieme.annonce, .erreur("Non autorisé"))
    }

    // MARK: - Contestation

    func testContestationMotifBorneEnvoiEtRefusDansLaFeuille() async throws {
        let conteste = presence("p-1", mission: "m-1", creneaux: terminee("m-1"), motif: "Absent")
        let script = Script([aValider()], [conteste])
        script.contestations = [.success(.refusee(message: "Présence introuvable")), .success(.contestee(motifLitige: "Absent"))]
        let model = try await modele(script)
        model.ouvrirContestation(presenceId: "p-1")
        XCTAssertNotNil(model.contestation)
        model.saisirMotif("  ab  ")
        XCTAssertFalse(model.peutEnvoyerContestation, "3 caractères après nettoyage, comme le serveur")
        await model.envoyerContestation()
        XCTAssertEqual(script.mutations, [])
        model.saisirMotif(String(repeating: "x", count: 900))
        XCTAssertEqual(model.contestation?.motif.count, PresencesEtabModel.longueurMaxMotif)
        model.saisirMotif("  Absent \n")
        XCTAssertTrue(model.peutEnvoyerContestation)

        await model.envoyerContestation()
        XCTAssertEqual(script.mutations, ["contester p-1 [Absent]"], "motif nettoyé envoyé")
        XCTAssertEqual(model.contestation?.erreur, "Présence introuvable", "refus serveur dans la feuille restée ouverte")
        await model.envoyerContestation()
        XCTAssertNil(model.contestation)
        XCTAssertEqual(model.annonce, .avertissement("Contestation enregistrée."))
        XCTAssertEqual(model.carte(model.presences[0]).litige, "⚠️ Litige : Absent", "motif relu au serveur")

        // Proposée seulement pour une présence à valider (CarteValidation.tsx l.213-255).
        let autres = try await modele(Script([validee(), presence("p-3", mission: "m-3", creneaux: ouverte("m-3"))]))
        autres.ouvrirContestation(presenceId: "p-1")
        autres.ouvrirContestation(presenceId: "p-3")
        XCTAssertNil(autres.contestation)
        autres.ouvrirValidation(presenceId: "p-3")
        XCTAssertNil(autres.validation)
    }

    // MARK: - Clôture

    func testClotureHeureDeParisBorneeEtSegmentFermeRelu() async throws {
        let fermee = presence("p-3", mission: "m-3", creneaux: [ouverte("m-3")[0],
                                                               creneau("m-3-e", "m-3", "2026-11-01T23:58:00Z", "2026-11-02T00:00:00Z", type: "EFFECTIF")])
        let script = Script([presence("p-3", mission: "m-3", creneaux: ouverte("m-3"))], [fermee])
        script.clotures = [.success(.refusee(message: "L'heure de fin (2026-11-01 23:59:00+00) doit être postérieure au début du créneau (2026-11-01 23:59:30+00).")),
                           .success(.cloturee)]
        let model = try await modele(script)
        XCTAssertTrue(model.carte(model.presences[0]).segmentOuvert)
        model.ouvrirCloture(missionId: "m-3")
        let bornes = try XCTUnwrap(model.cloture?.bornes)
        XCTAssertEqual(bornes.fin, DemoWorld.fixedNow, "le sélecteur ne propose jamais une heure future")
        XCTAssertEqual(DateHeureParis.isoUTC(bornes.debut), "2026-11-01T23:59:00.000Z",
                       "minute qui suit le début du segment (le serveur refuse une fin égale au début, revue B8 textes, mineur 9)")

        await model.confirmerCloture(saisie: "2026-11-02T01:01") // une minute après maintenant (01:00 à Paris)
        XCTAssertEqual(model.cloture?.erreur, ClotureSegment.messageHeureFuture, "D28 : refusée avant tout envoi")
        await model.confirmerCloture(saisie: "2026-03-29T02:30")
        XCTAssertEqual(model.cloture?.erreur, ClotureSegment.messageHeureInexistante)
        XCTAssertEqual(script.mutations, [])

        await model.confirmerCloture(saisie: "2026-11-02T00:59")
        XCTAssertEqual(script.mutations, ["cloturer m-3 2026-11-01T23:59:00.000Z"], "heure de Paris convertie en instant")
        XCTAssertEqual(model.cloture?.erreur, "L'heure de fin (2026-11-01 23:59:00+00) doit être postérieure au début du créneau (2026-11-01 23:59:30+00).",
                       "refus 23514 du serveur mot pour mot")
        await model.confirmerCloture(saisie: "2026-11-02T01:00")
        XCTAssertNil(model.cloture)
        XCTAssertEqual(model.annonce, .succes("Segment clôturé."))
        XCTAssertFalse(model.carte(model.presences[0]).segmentOuvert, "segment fermé relu")

        // Sans segment ouvert, la clôture n'est jamais proposée.
        let sans = try await modele(Script([aValider()]))
        sans.ouvrirCloture(missionId: "m-1")
        XCTAssertNil(sans.cloture)
    }

    func testClotureRefusDeDroitVerbatimPuisPerimetreRelu() async throws {
        let script = Script([presence("p-3", mission: "m-3", creneaux: ouverte("m-3"))])
        script.clotures = [.success(.accesRefuse(message: "Vous n'êtes pas autorisé(e) à déclarer une fin rétroactive sur cette mission."))]
        let relectures = Compteur()
        let model = try await modele(script, role: .pointageOnly, relectures: relectures)
        model.ouvrirCloture(missionId: "m-3")
        XCTAssertNotNil(model.cloture, "l'action suit la permission pointage servie ; le serveur décide")
        await model.confirmerCloture(saisie: "2026-11-02T01:00")
        XCTAssertNil(model.cloture)
        XCTAssertEqual(model.annonce, .erreur("Vous n'êtes pas autorisé(e) à déclarer une fin rétroactive sur cette mission."))
        XCTAssertEqual(relectures.nombre, 1)
    }
}
