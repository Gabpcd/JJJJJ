import XCTest
@testable import JoleneCore

/// Pré-prompt de notification (lot 3, T5 ; décision 1 du lot 3) : port de `DemandePermissionPush.tsx`
/// (l.53-126) et de `session-count.ts` — jamais à la 1re session, jamais si la marque est posée, jamais si
/// l'autorisation est déjà accordée ou refusée (la marque est alors posée sans rien afficher), 5 s plus tard
/// sinon ; « Activer » demande l'autorisation au tap seulement puis exige un enregistrement confirmé ;
/// « Plus tard » pose la marque `later`. Textes d'issue verbatim web.
@MainActor
final class PushPolicyTests: XCTestCase {
    // MARK: - Règle

    func testClesDelaiEtTextesVerbatim() {
        XCTAssertEqual(PrePromptPush.cleCompteur, "jolene.sessionCount")
        XCTAssertEqual(PrePromptPush.cleMarque, "jolene.pushPrePrompt")
        XCTAssertEqual(PrePromptPush.delaiAffichage, 5, "window.setTimeout(…, 5000), l.79")
        XCTAssertEqual(PrePromptPush.Marque.allCases.map(\.rawValue), ["accepted", "denied", "later"])
        XCTAssertEqual(PrePromptPush.issueActivees, "Alertes push activées !")
        XCTAssertEqual(PrePromptPush.issueNonActivees, "Notifications non activées. Vous pourrez les autoriser dans Réglages.")
        XCTAssertEqual(PrePromptPush.issueEchec, "Impossible d'activer les notifications.")
    }

    func testPremiereSessionJamais() {
        for numero in [0.0, 1.0] {
            for autorisation in AutorisationPush.allCases {
                XCTAssertEqual(PrePromptPush.decision(marque: nil, numeroSession: numero, autorisation: autorisation), .rien,
                               "session \(numero), \(autorisation)")
            }
        }
    }

    func testDeuxiemeLancementProposeSiJamaisDemande() {
        XCTAssertEqual(PrePromptPush.decision(marque: nil, numeroSession: 2, autorisation: .nonDemandee), .proposer)
        XCTAssertEqual(PrePromptPush.decision(marque: "", numeroSession: 7, autorisation: .nonDemandee), .proposer,
                       "marque vide : `localStorage.getItem` la lit comme absente")
    }

    func testMarqueDejaPoseeJamais() {
        for marque in PrePromptPush.Marque.allCases.map(\.rawValue) + ["valeur inattendue"] {
            for autorisation in AutorisationPush.allCases {
                XCTAssertEqual(PrePromptPush.decision(marque: marque, numeroSession: 9, autorisation: autorisation), .rien,
                               "\(marque), \(autorisation)")
            }
        }
    }

    func testAutorisationDejaDecideeMarqueeSansAffichage() {
        XCTAssertEqual(PrePromptPush.decision(marque: nil, numeroSession: 2, autorisation: .accordee), .marquer(.accepted))
        XCTAssertEqual(PrePromptPush.decision(marque: nil, numeroSession: 2, autorisation: .provisoire), .marquer(.accepted))
        XCTAssertEqual(PrePromptPush.decision(marque: nil, numeroSession: 2, autorisation: .refusee), .marquer(.denied),
                       "iOS ne réaffiche pas la feuille après un refus (l.73-77)")
    }

    // MARK: - Compteur de lancements

    func testLancementIncrementeLeCompteurDeLAppareil() {
        let stockage = MemoireStockageAppareil()
        XCTAssertEqual(ContextePrePromptPush.lancement(stockage: stockage).numeroSession, 1)
        XCTAssertEqual(stockage.lire(PrePromptPush.cleCompteur), "1")
        XCTAssertEqual(ContextePrePromptPush.lancement(stockage: stockage).numeroSession, 2, "second lancement à froid")
        XCTAssertEqual(stockage.lire(PrePromptPush.cleCompteur), "2")
        let illisible = MemoireStockageAppareil([PrePromptPush.cleCompteur: "abc"])
        XCTAssertEqual(ContextePrePromptPush.lancement(stockage: illisible).numeroSession, 1, "compteur illisible : 0 puis 1")
    }

    func testArgumentDebugDuNumeroDeSession() {
        XCTAssertEqual(PrePromptPush.argumentNumeroSession, "-JOLENE_SESSION_COUNT")
        XCTAssertEqual(PrePromptPush.numeroSessionForce(arguments: ["-JOLENE_MODE", "demo", "-JOLENE_SESSION_COUNT", "2"]), 2)
        XCTAssertEqual(PrePromptPush.numeroSessionForce(arguments: ["-JOLENE_SESSION_COUNT", "1"]), 1)
        XCTAssertNil(PrePromptPush.numeroSessionForce(arguments: ["-JOLENE_SESSION_COUNT", "-2"]))
        XCTAssertNil(PrePromptPush.numeroSessionForce(arguments: ["-JOLENE_SESSION_COUNT", "deux"]))
        XCTAssertNil(PrePromptPush.numeroSessionForce(arguments: ["-JOLENE_SESSION_COUNT"]))
        XCTAssertNil(PrePromptPush.numeroSessionForce(arguments: []))
    }

    // MARK: - Modèle

    private func modele(_ monde: MondePush, numero: Double, marque: String? = nil)
        async throws -> (PrePromptPushModel, MemoireStockageAppareil, SessionSnapshot) {
        let stockage = MemoireStockageAppareil(marque.map { [PrePromptPush.cleMarque: $0] } ?? [:])
        let snapshot = try await monde.pret()
        let model = PrePromptPushModel(contexte: ContextePrePromptPush(stockage: stockage, numeroSession: numero),
                                       permission: monde.permission, push: monde.coordinator, snapshot: snapshot, delai: 0)
        return (model, stockage, snapshot)
    }

    func testPremiereSessionRienNiLectureDAutorisation() async throws {
        let monde = MondePush(etat: .nonDemandee)
        let (model, stockage, _) = try await modele(monde, numero: 1)
        await model.evaluer()
        XCTAssertFalse(model.visible)
        XCTAssertNil(stockage.lire(PrePromptPush.cleMarque))
        let lectures = await monde.permission.lectures
        XCTAssertEqual(lectures, 0, "le web ne lit l'autorisation qu'à partir de la 2e session")
    }

    func testDeuxiemeSessionAfficheSansDemanderPuisActiverEnregistre() async throws {
        let monde = MondePush(etat: .nonDemandee)
        let (model, stockage, snapshot) = try await modele(monde, numero: 2)
        await model.evaluer()
        XCTAssertTrue(model.visible)
        var demandes = await monde.permission.demandes
        XCTAssertEqual(demandes, 0, "l'affichage ne demande rien au système (D1)")
        XCTAssertNil(stockage.lire(PrePromptPush.cleMarque), "aucune marque avant le choix")

        await monde.permission.regler(.accordee) // l'utilisateur accepte la feuille système
        await model.activer()
        XCTAssertFalse(model.visible)
        demandes = await monde.permission.demandes
        XCTAssertEqual(demandes, 1, "une seule demande, au tap")
        XCTAssertEqual(model.issue, .activees)
        XCTAssertEqual(model.issue?.message, "Alertes push activées !")
        XCTAssertEqual(stockage.lire(PrePromptPush.cleMarque), "accepted")
        let confirme = await monde.coordinator.enregistrementConfirme(epoch: snapshot.epoch)
        XCTAssertTrue(confirme, "enregistrement de l'appareil confirmé")
        XCTAssertEqual(monde.journal.entrees(prefixe: "upsert:").count, 1)
        model.effacerIssue()
        XCTAssertNil(model.issue)
    }

    func testRefusDeLaFeuilleSystemeMarqueDenied() async throws {
        let monde = MondePush(etat: .nonDemandee) // le double rend `false` : refus de la feuille
        let (model, stockage, _) = try await modele(monde, numero: 3)
        await model.evaluer()
        await model.activer()
        XCTAssertEqual(model.issue, .nonActivees)
        XCTAssertEqual(model.issue?.message, "Notifications non activées. Vous pourrez les autoriser dans Réglages.")
        XCTAssertEqual(stockage.lire(PrePromptPush.cleMarque), "denied")
        XCTAssertEqual(monde.journal.entrees(prefixe: "upsert:"), [], "aucun enregistrement sans autorisation")
    }

    func testAutorisationSansEnregistrementEstUnEchecSansMarque() async throws {
        let monde = MondePush(etat: .nonDemandee)
        let (model, stockage, _) = try await modele(monde, numero: 2)
        await model.evaluer()
        await monde.permission.regler(.accordee)
        await monde.gateway.echouerUpserts([JoleneError(.network, "Connexion impossible.")])
        await model.activer()
        XCTAssertEqual(model.issue, .echec, "web l.221-226 : autorisation sans enregistrement confirmé")
        XCTAssertEqual(model.issue?.message, "Impossible d'activer les notifications.")
        XCTAssertNil(stockage.lire(PrePromptPush.cleMarque), "marque non posée sur une erreur (l.118-120)")
    }

    func testPlusTardMarqueLaterEtNeRevientPlus() async throws {
        let monde = MondePush(etat: .nonDemandee)
        let (model, stockage, snapshot) = try await modele(monde, numero: 2)
        await model.evaluer()
        model.plusTard()
        XCTAssertFalse(model.visible)
        XCTAssertEqual(stockage.lire(PrePromptPush.cleMarque), "later")
        let demandes = await monde.permission.demandes
        XCTAssertEqual(demandes, 0)
        // Session suivante (même appareil) : jamais reproposé.
        let suivant = PrePromptPushModel(contexte: ContextePrePromptPush(stockage: stockage, numeroSession: 3),
                                         permission: monde.permission, push: monde.coordinator, snapshot: snapshot, delai: 0)
        await suivant.evaluer()
        XCTAssertFalse(suivant.visible)
    }

    func testAutorisationDejaAccordeeOuRefuseeMarqueeSansAffichage() async throws {
        for (etat, marque) in [(AutorisationPush.accordee, "accepted"), (.refusee, "denied")] {
            let monde = MondePush(etat: etat)
            let (model, stockage, _) = try await modele(monde, numero: 4)
            await model.evaluer()
            XCTAssertFalse(model.visible, "\(etat)")
            XCTAssertEqual(stockage.lire(PrePromptPush.cleMarque), marque, "\(etat)")
            let demandes = await monde.permission.demandes
            XCTAssertEqual(demandes, 0, "\(etat)")
        }
    }

    func testActiverOuPlusTardSansAffichageNeFontRien() async throws {
        let monde = MondePush(etat: .nonDemandee)
        let (model, stockage, _) = try await modele(monde, numero: 1)
        await model.activer()
        model.plusTard()
        let demandes = await monde.permission.demandes
        XCTAssertEqual(demandes, 0, "jamais de demande sans pré-prompt affiché")
        XCTAssertNil(stockage.lire(PrePromptPush.cleMarque))
        XCTAssertNil(model.issue)
    }

    func testDisparitionPendantLeDelaiNAfficheRien() async throws {
        let monde = MondePush(etat: .nonDemandee)
        let stockage = MemoireStockageAppareil()
        let snapshot = try await monde.pret()
        let model = PrePromptPushModel(contexte: ContextePrePromptPush(stockage: stockage, numeroSession: 2),
                                       permission: monde.permission, push: monde.coordinator, snapshot: snapshot, delai: 30)
        let tache = Task { await model.evaluer() }
        await waitUntil { await monde.permission.lectures == 1 }
        tache.cancel() // l'espace disparaît (déconnexion) pendant les 5 s du web
        await tache.value
        XCTAssertFalse(model.visible)
        XCTAssertNil(stockage.lire(PrePromptPush.cleMarque))
    }

    func testSansContexteNiPortAucunPrePrompt() async throws {
        let monde = MondePush(etat: .nonDemandee)
        let snapshot = try await monde.pret()
        let model = PrePromptPushModel(contexte: nil, permission: nil, push: nil, snapshot: snapshot, delai: 0)
        await model.evaluer()
        XCTAssertFalse(model.visible)
    }
}
