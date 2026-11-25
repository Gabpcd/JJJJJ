import XCTest
@testable import JoleneCore

/// « Mes litiges » et le fil d'un litige (lot 4, T8) sur le monde démo (`DemoLitigesGateway`) et sur des ports témoins :
/// filtres par groupe de statut, cible d'un lien dépliée, ouverture confirmée par la liste relue (PRINCIPES §3), refus du
/// serveur mot pour mot, relecture après une erreur de transport (jamais de renvoi), champ de message selon le statut.
@MainActor
final class LitigesModelTests: XCTestCase {
    /// Port témoin : monde démo, avec une ouverture, un ajout de message ou une lecture remplacés.
    private struct PortTemoin: LitigesPort {
        var demo = DemoLitigesGateway()
        var surLecture: (@Sendable (DemoLitigesGateway, MissionReadContext) async throws -> [Litige])?
        var surMissions: (@Sendable () async throws -> [MissionContestable])?
        var surOuverture: (@Sendable (DemoLitigesGateway, String, String, MissionReadContext) async throws -> OuvertureLitigeOutcome)?
        var surMessage: (@Sendable (DemoLitigesGateway, String, String, MissionReadContext) async throws -> IssueMessageLitige)?

        func lister(context: MissionReadContext) async throws -> [Litige] {
            if let surLecture { return try await surLecture(demo, context) }
            return try await demo.lister(context: context)
        }

        func missionsContestables(context: MissionReadContext) async throws -> [MissionContestable] {
            if let surMissions { return try await surMissions() }
            return try await demo.missionsContestables(context: context)
        }

        func ouvrir(missionId: String, motif: String, context: MissionReadContext) async throws -> OuvertureLitigeOutcome {
            if let surOuverture { return try await surOuverture(demo, missionId, motif, context) }
            return try await demo.ouvrir(missionId: missionId, motif: motif, context: context)
        }

        func fil(litigeId: String, context: MissionReadContext) async throws -> [MessageLitige] {
            try await demo.fil(litigeId: litigeId, context: context)
        }

        func ajouterMessage(litigeId: String, contenu: String, context: MissionReadContext) async throws -> IssueMessageLitige {
            if let surMessage { return try await surMessage(demo, litigeId, contenu, context) }
            return try await demo.ajouterMessage(litigeId: litigeId, contenu: contenu, context: context)
        }
    }

    private func session(_ port: any LitigesPort) async throws -> (SessionController, SessionSnapshot) {
        var gateways = DemoWorld.gateways()
        gateways.litiges = port
        let controller = SessionController(gateways: gateways)
        let state = await controller.signIn(email: DemoWorld.context.email ?? "", password: "demonstration")
        return (controller, try XCTUnwrap(state.snapshot, "session démo prête attendue, obtenu \(state)"))
    }

    private func modele(_ port: any LitigesPort = DemoLitigesGateway(), cible: String? = nil) async throws -> LitigesModel {
        let (controller, snapshot) = try await session(port)
        let model = LitigesModel(controller: controller, snapshot: snapshot, cible: cible)
        await model.charger()
        return model
    }

    /// Feuille ouverte, mission choisie et motif saisi.
    private func pretAEnvoyer(_ model: LitigesModel, mission: String = "demo-terminee-001",
                              motif: String = "Désaccord sur les heures") async {
        await model.ouvrirFormulaire()
        model.choisirMission(mission)
        model.saisirMotif(motif)
    }

    // MARK: - Liste, filtres, cible

    func testListeFiltresParGroupeEtBascule() async throws {
        let model = try await modele()
        XCTAssertEqual(model.litiges.map(\.id), ["demo-litige-001", "demo-litige-002", "demo-litige-003"])
        XCTAssertEqual(model.filtresVisibles.map(\.filtre), [.tous, .ouvert, .mediation, .resolu], "groupes vides masqués")
        XCTAssertEqual(model.filtresVisibles.map(\.nombre), [3, 1, 1, 1])
        XCTAssertEqual(model.filtre, .tous)
        XCTAssertNil(model.deplie, "aucun litige déplié sans cible")

        model.choisir(.mediation)
        XCTAssertEqual(model.litigesFiltres.map(\.id), ["demo-litige-002"])
        model.choisir(.resolu)
        XCTAssertEqual(model.litigesFiltres.map(\.id), ["demo-litige-003"], "accord et décision réunis sous « Résolus »")
        model.choisir(.tous)
        XCTAssertEqual(model.litigesFiltres.count, 3)

        model.basculer("demo-litige-002")
        XCTAssertEqual(model.deplie, "demo-litige-002")
        model.basculer("demo-litige-001")
        XCTAssertEqual(model.deplie, "demo-litige-001", "un seul litige déplié à la fois")
        model.basculer("demo-litige-001")
        XCTAssertNil(model.deplie)
    }

    func testCibleDuLienDeplieeUneSeuleFois() async throws {
        let model = try await modele(cible: "demo-litige-003")
        XCTAssertEqual(model.deplie, "demo-litige-003", "?litige= ou #id : litige déplié")
        XCTAssertEqual(model.filtre, .tous)
        model.basculer("demo-litige-003")
        model.choisir(.ouvert)
        await model.charger()
        XCTAssertNil(model.deplie, "cible consommée : une relecture ne redéplie rien")
        XCTAssertEqual(model.filtre, .ouvert)

        let absente = try await modele(cible: "demo-litige-999")
        XCTAssertNil(absente.deplie, "cible absente de la liste : rien n'est déplié")
        XCTAssertEqual(absente.litiges.count, 3)
    }

    func testFiltresAffichesEtReglesDeStatut() {
        XCTAssertTrue(LitigesPresentation.filtres([]).isEmpty, "aucun litige : aucun filtre")
        let statuts = ["OUVERT", "EN_DISCUSSION", "EN_MEDIATION", "MEDIATION_EN_COURS", "REVUE_ADMIN", "RESOLU_ACCORD_PARTIES",
                       "RESOLU_FAVEUR_SOIGNANT", "RESOLU_ADMIN", "FERME"]
        let litiges = statuts.enumerated().map { Litige(id: "l\($0.offset)", statut: $0.element) }
        let filtres = LitigesPresentation.filtres(litiges)
        XCTAssertEqual(filtres.map(\.filtre), FiltreLitiges.allCases)
        XCTAssertEqual(filtres.map(\.nombre), [9, 2, 2, 1, 2, 2])
        XCTAssertEqual(FiltreLitiges.allCases.map(\.libelle), ["Tous", "Ouverts", "Médiation", "Revue admin", "Résolus", "Fermés"])
        XCTAssertEqual(FiltreLitiges.allCases.map(\.identifiant),
                       ["litiges-filtre-tous", "litiges-filtre-ouvert", "litiges-filtre-mediation", "litiges-filtre-action_attendue",
                        "litiges-filtre-resolu", "litiges-filtre-ferme"])
        // Champ de message : tant que le litige n'est pas résolu (règle golden), soit les statuts que le serveur accepte.
        XCTAssertEqual(statuts.filter(LitigesPresentation.peutEcrire(statut:)),
                       ["OUVERT", "EN_DISCUSSION", "EN_MEDIATION", "MEDIATION_EN_COURS", "REVUE_ADMIN"])
        XCTAssertEqual(Set(statuts.filter(LitigesPresentation.peutEcrire(statut:))), DemoLitigesGateway.statutsOuverts)
        // Renvoi « Accord amiable sur jolene.app » : statuts où le web propose un accord, jamais en revue admin.
        XCTAssertEqual(statuts.filter(LitigesPresentation.accordSurLeWeb(statut:)),
                       ["OUVERT", "EN_DISCUSSION", "EN_MEDIATION", "MEDIATION_EN_COURS"])
    }

    // MARK: - Ouverture

    func testOuvertureConfirmeeParLaListeReluePuisDepliee() async throws {
        let model = try await modele()
        model.choisir(.mediation)
        await model.ouvrirFormulaire()
        XCTAssertEqual(model.formulaire.missions.map(\.id), ["demo-terminee-001", "demo-terminee-002"])
        XCTAssertFalse(model.peutEnvoyer, "ni mission ni motif")
        model.choisirMission("demo-mission-absente")
        XCTAssertEqual(model.missionChoisie, "", "une mission hors de la liste proposée n'est pas retenue")
        model.choisirMission("demo-terminee-001")
        model.saisirMotif("   trop   ")
        XCTAssertFalse(model.peutEnvoyer, "motif de moins de 10 caractères après trim : bouton désactivé, comme le web")
        let refuse = await model.envoyer()
        XCTAssertFalse(refuse)
        model.saisirMotif("  Désaccord sur les heures  ")
        XCTAssertTrue(model.peutEnvoyer)

        let ouvert = await model.envoyer()
        XCTAssertTrue(ouvert)
        XCTAssertEqual(model.confirmation, "Litige ouvert avec succès.")
        XCTAssertNil(model.erreur)
        XCTAssertEqual(model.formulaire, .ferme)
        XCTAssertEqual(model.motif, "")
        XCTAssertEqual(model.litiges.first?.id, "demo-litige-ajout-1", "litige OUVERT relu en tête")
        XCTAssertEqual(model.litiges.first?.statut, "OUVERT")
        XCTAssertEqual(model.litiges.first?.motif, "Désaccord sur les heures", "motif nettoyé comme le web (trim)")
        XCTAssertEqual(model.filtre, .tous, "le filtre revient à « Tous »")
        XCTAssertEqual(model.deplie, "demo-litige-ajout-1", "le litige ouvert est déplié : son fil s'affiche")
        XCTAssertEqual(model.filtresVisibles.map(\.nombre), [4, 2, 1, 1])

        await model.ouvrirFormulaire()
        XCTAssertEqual(model.formulaire.missions.map(\.id), ["demo-terminee-002"], "la mission en litige n'est plus proposée")
        XCTAssertNil(model.confirmation, "la confirmation s'efface à la réouverture")
        model.fermerFormulaire()
        XCTAssertEqual(model.formulaire, .ferme)
    }

    func testSaisieDuMotifBorneeA1000() async throws {
        let model = try await modele()
        await model.ouvrirFormulaire()
        model.saisirMotif(String(repeating: "a", count: 1200))
        XCTAssertEqual(model.motif.utf16.count, 1000, "maxLength={1000} du web")
        XCTAssertEqual(LitigesPresentation.compteur(model.motif), "1000/1000")
        XCTAssertEqual(LitigesPresentation.borner(String(repeating: "a", count: 999) + "👩‍⚕️"), String(repeating: "a", count: 999),
                       "jamais un caractère coupé")
        XCTAssertEqual(LitigesPresentation.longueur("  \u{00A0}abc\n"), 3, "trim JavaScript")
        XCTAssertFalse(LitigesPresentation.envoyable("123456789"))
        XCTAssertTrue(LitigesPresentation.envoyable("1234567890"))
    }

    func testRefusDuServeurMotPourMotDansLaFeuilleResteeOuverte() async throws {
        for message in MessagesLitigesServeur.ouverture {
            let model = try await modele(PortTemoin(surOuverture: { _, _, _, _ in .refuse(message: message) }))
            await pretAEnvoyer(model)
            let ouvert = await model.envoyer()
            XCTAssertFalse(ouvert)
            XCTAssertEqual(model.erreurFormulaire, message, "refus du serveur affiché mot pour mot")
            XCTAssertTrue(model.formulaire.estOuvert, "la feuille reste ouverte")
            XCTAssertEqual(model.motif, "Désaccord sur les heures", "saisie conservée")
            XCTAssertNil(model.confirmation)
            XCTAssertEqual(model.litiges.count, 3)
        }
    }

    func testLitigeAnnonceMaisAbsentDeLaRelectureJamaisUnSucces() async throws {
        let model = try await modele(PortTemoin(surOuverture: { _, _, _, _ in .ouvert(id: "fantome", informatif: false) }))
        await pretAEnvoyer(model)
        let ouvert = await model.envoyer()
        XCTAssertFalse(ouvert)
        XCTAssertEqual(model.erreurFormulaire, LitigesTextes.nonConfirme)
        XCTAssertNil(model.confirmation)
        XCTAssertTrue(model.formulaire.estOuvert)
    }

    func testErreurDeTransportPuisRelectureQuiFaitFoi() async throws {
        // Réponse perdue : le serveur a ouvert le litige. La relecture le montre : succès, sans renvoi.
        let perdue = try await modele(PortTemoin(surOuverture: { demo, mission, motif, context in
            _ = try await demo.ouvrir(missionId: mission, motif: motif, context: context)
            throw JoleneError(.network, "Connexion impossible.")
        }))
        await pretAEnvoyer(perdue)
        let retrouve = await perdue.envoyer()
        XCTAssertTrue(retrouve, "litige nouveau sur la mission relu : il fait foi")
        XCTAssertEqual(perdue.confirmation, "Litige ouvert avec succès.")
        XCTAssertEqual(perdue.deplie, "demo-litige-ajout-1")
        XCTAssertEqual(perdue.formulaire, .ferme)

        // Requête jamais reçue : l'erreur reste dans la feuille, rien n'est renvoyé.
        let coupee = try await modele(PortTemoin(surOuverture: { _, _, _, _ in throw JoleneError(.network, "Connexion impossible.") }))
        await pretAEnvoyer(coupee)
        let rien = await coupee.envoyer()
        XCTAssertFalse(rien)
        XCTAssertEqual(coupee.erreurFormulaire, "Connexion impossible.")
        XCTAssertTrue(coupee.formulaire.estOuvert)
        XCTAssertEqual(coupee.litiges.count, 3)
        XCTAssertFalse(coupee.sessionExpiree)

        let expiree = try await modele(PortTemoin(surOuverture: { _, _, _, _ in
            throw JoleneError(.unauthorized, "Votre session a expiré. Reconnectez-vous.")
        }))
        await pretAEnvoyer(expiree)
        let session = await expiree.envoyer()
        XCTAssertFalse(session)
        XCTAssertTrue(expiree.sessionExpiree)
        XCTAssertEqual(expiree.erreurFormulaire, "Votre session a expiré. Reconnectez-vous.")

        let annulation = try await modele(PortTemoin(surOuverture: { _, _, _, _ in throw CancellationError() }))
        await pretAEnvoyer(annulation)
        let annulee = await annulation.envoyer()
        XCTAssertFalse(annulee)
        XCTAssertNil(annulation.erreurFormulaire, "une annulation n'est jamais une erreur")
    }

    func testEchecsDeLecture() async throws {
        let liste = try await modele(PortTemoin(surLecture: { _, _ in throw JoleneError(.network, "Connexion impossible.") }))
        XCTAssertEqual(liste.liste, .echec("Impossible de charger les litiges."), "texte du web, jamais une liste vide")

        let missions = try await modele(PortTemoin(surMissions: { throw JoleneError(.network, "Connexion impossible.") }))
        await missions.ouvrirFormulaire()
        XCTAssertEqual(missions.formulaire, .ferme, "aucune feuille sans les missions")
        XCTAssertEqual(missions.erreur, "Impossible de charger les missions.")

        let vide = try await modele(PortTemoin(surMissions: { [] }))
        await vide.ouvrirFormulaire()
        XCTAssertEqual(vide.formulaire, .ouvert([]), "aucune mission éligible : feuille ouverte, envoi impossible")
        XCTAssertFalse(vide.peutEnvoyer)
    }

    // MARK: - Fil

    private func fil(_ litigeId: String, port: any LitigesPort = DemoLitigesGateway()) async throws -> LitigeFilModel {
        let (controller, snapshot) = try await session(port)
        let model = LitigeFilModel(litigeId: litigeId, controller: controller, snapshot: snapshot)
        await model.charger()
        return model
    }

    func testFilLuPuisMessageConfirmeParLaRelecture() async throws {
        let model = try await fil("demo-litige-001")
        XCTAssertEqual(model.messages.map(\.id), ["demo-litige-message-003", "demo-litige-message-004"])
        XCTAssertEqual(model.messages.map { LitigesPresentation.auteur($0, userId: model.userId) }, ["Vous", "Établissement"])
        XCTAssertFalse(model.peutEnvoyer)
        model.saisir("  bonjour  ")
        XCTAssertFalse(model.peutEnvoyer, "moins de 10 caractères après trim")
        model.saisir("  Voici le détail du désaccord.  ")
        XCTAssertTrue(model.peutEnvoyer)

        let envoye = await model.envoyer()
        XCTAssertTrue(envoye)
        XCTAssertEqual(model.messages.count, 3, "fil relu : un message de plus")
        XCTAssertEqual(model.messages.last?.contenu, "Voici le détail du désaccord.")
        XCTAssertEqual(model.messages.last.map { LitigesPresentation.auteur($0, userId: model.userId) }, "Vous")
        XCTAssertEqual(model.saisie, "", "saisie vidée après confirmation")
        XCTAssertNil(model.erreur)
    }

    func testRefusDuServeurSurLeFilMotPourMotEtSaisieConservee() async throws {
        // Litige résolu : l'écran masque le champ ; le serveur reste seul juge si un envoi part quand même.
        let resolu = try await fil("demo-litige-003")
        XCTAssertFalse(LitigesPresentation.peutEcrire(statut: "RESOLU_ACCORD_PARTIES"))
        resolu.saisir("Message sur un litige résolu")
        let refuse = await resolu.envoyer()
        XCTAssertFalse(refuse)
        XCTAssertEqual(resolu.erreur, "Ce litige est clôturé.")
        XCTAssertEqual(resolu.saisie, "Message sur un litige résolu", "saisie conservée")
        XCTAssertEqual(resolu.messages.count, 1)

        for message in MessagesLitigesServeur.message {
            let model = try await fil("demo-litige-001", port: PortTemoin(surMessage: { _, _, _, _ in .refuse(message: message) }))
            model.saisir("Voici le détail du désaccord.")
            let envoye = await model.envoyer()
            XCTAssertFalse(envoye)
            XCTAssertEqual(model.erreur, message, "refus du serveur affiché mot pour mot")
        }
    }

    func testFilNonConfirmeEtErreurDeTransportReconciliee() async throws {
        let muet = try await fil("demo-litige-001", port: PortTemoin(surMessage: { demo, litige, _, context in
            .ajoute(try await demo.fil(litigeId: litige, context: context))
        }))
        muet.saisir("Voici le détail du désaccord.")
        let nonConfirme = await muet.envoyer()
        XCTAssertFalse(nonConfirme)
        XCTAssertEqual(muet.erreur, LitigesTextes.messageNonConfirme)
        XCTAssertEqual(muet.saisie, "Voici le détail du désaccord.")

        let perdue = try await fil("demo-litige-001", port: PortTemoin(surMessage: { demo, litige, contenu, context in
            _ = try await demo.ajouterMessage(litigeId: litige, contenu: contenu, context: context)
            throw JoleneError(.network, "Connexion impossible.")
        }))
        perdue.saisir("Voici le détail du désaccord.")
        let retrouve = await perdue.envoyer()
        XCTAssertTrue(retrouve, "message relu dans le fil : il fait foi, sans renvoi")
        XCTAssertNil(perdue.erreur)
        XCTAssertEqual(perdue.saisie, "")
        XCTAssertEqual(perdue.messages.count, 3)

        let coupee = try await fil("demo-litige-001", port: PortTemoin(surMessage: { _, _, _, _ in
            throw JoleneError(.network, "Connexion impossible.")
        }))
        coupee.saisir("Voici le détail du désaccord.")
        let rien = await coupee.envoyer()
        XCTAssertFalse(rien)
        XCTAssertEqual(coupee.erreur, "Connexion impossible.")
        XCTAssertEqual(coupee.saisie, "Voici le détail du désaccord.", "jamais renvoyé seul : la saisie reste")
        XCTAssertEqual(coupee.messages.count, 2)
    }

    // MARK: - Mise en forme

    func testMiseEnFormeDesLitigesEtDesMessages() async throws {
        let model = try await modele()
        let premier = try XCTUnwrap(model.litiges.first)
        XCTAssertEqual(LitigesPresentation.jour(premier.creeLe), "1 nov. 2026", "heure de Paris")
        XCTAssertEqual(LitigesPresentation.intitule(premier), "Démonstration · Mission en litige 1")
        XCTAssertEqual(LitigesPresentation.etablissement(premier), "🏥 Établissement fictif République · 30 oct. 2026")
        XCTAssertEqual(LitigesPresentation.motif(premier), "Motif : Démonstration · Désaccord sur le poste occupé pendant la mission.")
        XCTAssertEqual(StatutLitige.regle(premier.statut).libelle, "Ouvert")

        let nu = Litige(id: "l", statut: "INCONNU")
        XCTAssertEqual(LitigesPresentation.intitule(nu), "Mission")
        XCTAssertEqual(LitigesPresentation.etablissement(nu), "🏥 Établissement non disponible")
        XCTAssertEqual(LitigesPresentation.motif(nu), "Motif : ")
        XCTAssertNil(LitigesPresentation.jour(nil))
        XCTAssertNil(LitigesPresentation.jour("pas une date"))

        await model.ouvrirFormulaire()
        XCTAssertEqual(model.formulaire.missions.map(LitigesPresentation.option), [
            "Démonstration · Mission terminée 1 — Établissement fictif République — 1 nov. 2026",
            "Démonstration · Mission terminée 2 — Établissement fictif des Lilas — 20 oct. 2026",
        ])
        XCTAssertEqual(LitigesPresentation.option(MissionContestable(id: "m", intitule: "Garde", etablissementId: nil)),
                       "Garde — Établissement non disponible — ")

        let message = MessageLitige(id: "m", auteurId: "autre", typeAuteur: "ADMIN", contenu: "c", creeLe: "2026-11-01T05:00:00.000Z")
        XCTAssertEqual(LitigesPresentation.heureMessage(message.creeLe), "1 nov. 06:00")
        XCTAssertEqual(LitigesPresentation.auteur(message, userId: "moi"), "🛡️ Jolene")
        XCTAssertEqual(LitigesPresentation.auteur(MessageLitige(id: "m", auteurId: "autre", typeAuteur: "SOIGNANT", contenu: "c"), userId: "moi"),
                       "Soignant(e)")
        XCTAssertEqual(LitigesPresentation.auteur(MessageLitige(id: "m", auteurId: "autre", typeAuteur: "ETABLISSEMENT", contenu: "c"),
                                                  userId: "moi"), "Établissement")
    }

    func testDecodageTolerantSeulLIdentifiantEstRequis() throws {
        let json = #"[{"id":"l1","statut":null,"motif":12,"missions":null,"cree_le":"2026-11-01T04:00:00+00:00"},{"id":"l2","missions":{"intitule":"Garde","debut_le":null}}]"#
        let litiges = try JSONDecoder().decode([Litige].self, from: Data(json.utf8))
        XCTAssertEqual(litiges, [Litige(id: "l1", statut: "", creeLe: "2026-11-01T04:00:00+00:00"),
                                 Litige(id: "l2", statut: "", missionIntitule: "Garde")])
        XCTAssertThrowsError(try JSONDecoder().decode([Litige].self, from: Data(#"[{"statut":"OUVERT"}]"#.utf8)),
                             "sans identifiant : ligne refusée")
        let messages = try JSONDecoder().decode([MessageLitige].self, from: Data(#"[{"id":"m1","contenu":null}]"#.utf8))
        XCTAssertEqual(messages, [MessageLitige(id: "m1", auteurId: nil, contenu: "")])
    }

    /// Revue B8 des textes de la vague D (M3) : proposition d'accord de l'établissement en attente de la réponse du
    /// soignant, lue sur les deux booléens servis (aucun montant), signalée par le texte du web.
    func testPropositionDAccordEnAttenteSurLesDeuxBooleens() throws {
        let json = #"{"id":"l1","statut":"OUVERT","accord_etablissement":true,"accord_soignant":null,"payload_modifications":{"montant":1}}"#
        let lu = try JSONDecoder().decode(Litige.self, from: Data(json.utf8))
        XCTAssertEqual(lu.accordEtablissement, true)
        XCTAssertNil(lu.accordSoignant)
        XCTAssertTrue(LitigesPresentation.propositionEnAttente(lu))
        XCTAssertFalse(LitigesPresentation.propositionEnAttente(Litige(id: "a", statut: "OUVERT")), "aucun accord")
        XCTAssertFalse(LitigesPresentation.propositionEnAttente(
            Litige(id: "b", statut: "OUVERT", accordEtablissement: true, accordSoignant: true)), "le soignant a déjà répondu")
        XCTAssertFalse(LitigesPresentation.propositionEnAttente(
            Litige(id: "c", statut: "OUVERT", accordSoignant: true)), "accord du seul soignant : rien à lui demander")
        XCTAssertFalse(LitigesPresentation.propositionEnAttente(
            Litige(id: "d", statut: "RESOLU_ACCORD_PARTIES", accordEtablissement: true)), "litige résolu")
        let illisible = try JSONDecoder().decode(Litige.self, from: Data(#"{"id":"l2","statut":"OUVERT","accord_etablissement":"oui"}"#.utf8))
        XCTAssertFalse(LitigesPresentation.propositionEnAttente(illisible), "valeur d'un autre type : ignorée, rien n'est annoncé")
        XCTAssertEqual(LitigesTextes.propositionRecue, "Proposition de résolution reçue — votre réponse est attendue")
    }
}
