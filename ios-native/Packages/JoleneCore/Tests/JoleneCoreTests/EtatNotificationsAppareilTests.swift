import XCTest
@testable import JoleneCore

/// Carte « Autorisation du téléphone » (lot 3, T4 ; hôte définitif : préférences de T6) : textes
/// verbatim de `src/pages/PageParametresNotifications.tsx` l.341-352 et l.365 (HARD STOP n°4), choisis
/// comme le web l.147-155 : autorisé ET enregistrement confirmé → « autorisées », autorisé sans
/// confirmation → « n'a pas pu être enregistré », vérification en cours → « Vérification… »,
/// refusé → « bloquées », activation en échec → « L’état système n’a pas pu être vérifié » (l.351).
/// « Jamais demandé » (l.349, « Le canal est actif dans Jolene… ») n'est affiché que si le canal push
/// est connu actif (préférences, T6). Action de la carte (T6, mineur 4 de la revue B8 de T4) :
/// « Activer sur cet appareil » (l.365) là où le web la propose (l.356 : jamais demandé, enregistrement
/// en échec ou état indisponible, canal push actif) ; « Ouvrir les réglages » seulement si refusé.
final class EtatNotificationsAppareilTests: XCTestCase {
    private typealias E = EtatNotificationsAppareil

    private static func sourceDepot(_ chemin: String) throws -> String {
        var racine = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { racine.deleteLastPathComponent() }
        let fichier = racine.appendingPathComponent(chemin)
        guard FileManager.default.fileExists(atPath: fichier.path) else {
            throw XCTSkip("\(chemin) introuvable : \(fichier.path)")
        }
        return try String(contentsOf: fichier, encoding: .utf8)
    }

    func testTextesVerbatimDuWeb() throws {
        let web = try Self.sourceDepot("src/pages/PageParametresNotifications.tsx")
        let lignes = web.components(separatedBy: "\n")
        // (texte, ligne du web) : chaque texte affiché est présent mot pour mot à sa ligne source.
        let attendus: [(String, Int)] = [
            (E.titre, 341), (E.verification, 343), (E.autorisees, 346), (E.canalDesactive, 347),
            (E.aAutoriser, 349), (E.bloquees, 350), (E.indisponible, 351), (E.nonEnregistre, 352),
        ]
        for (texte, ligne) in attendus {
            XCTAssertGreaterThanOrEqual(lignes.count, ligne)
            XCTAssertTrue(lignes[ligne - 1].contains(texte), "« \(texte) » absent de PageParametresNotifications.tsx l.\(ligne)")
        }
        // Apostrophes typographiques du web conservées.
        XCTAssertTrue(E.verification.contains("’") && E.nonEnregistre.contains("’") && E.indisponible.contains("’"))
    }

    /// Lot 3, T6 : libellé du bouton d'activation, verbatim l.365 (`PageParametresNotifications.tsx`).
    func testLibelleActiverSurCetAppareilVerbatim() throws {
        let web = try Self.sourceDepot("src/pages/PageParametresNotifications.tsx")
        let lignes = web.components(separatedBy: "\n")
        XCTAssertEqual(E.activerSurAppareil, "Activer sur cet appareil")
        XCTAssertEqual(lignes[364].trimmingCharacters(in: .whitespaces), E.activerSurAppareil, "PageParametresNotifications.tsx l.365")
        // Conditions du web (l.356) : prompt, registration-error ou unavailable, et `global.canal_push`.
        XCTAssertTrue(lignes[355].contains("['prompt', 'registration-error', 'unavailable'].includes(autorisationPushNative) && global.canal_push"))
    }

    func testLibelleOuvrirLesReglagesEpingleSansSourceWeb() throws {
        // Action native sans équivalent web (le web n'ouvre pas les réglages système), non juridique : nommée
        // au §1.1 du blueprint, tranchée par délégation (L3-TJ, décision TJ5 de `DECISIONS_LOT3.md`, « Décisions
        // déléguées du 8 novembre 2026 ») et plus « à relire par Gabrielle » dans la section HARD STOP.
        XCTAssertEqual(E.ouvrirReglages, "Ouvrir les réglages")
        let blueprint = try Self.sourceDepot("docs/mobile-swift/LOT3_PLAN.md")
        XCTAssertTrue(blueprint.contains("« \(E.ouvrirReglages) »"), "LOT3_PLAN.md §1.1 nomme le libellé")
        // Le libellé figure dans la puce « Textes **sans équivalent web** (non juridiques), validés par délégation ».
        let (puce, sousSection) = try DecisionsLot3Document.puceDeleguee(
            "- Textes **sans équivalent web** (non juridiques), validés par délégation")
        XCTAssertTrue(sousSection.contains("### TJ5 — "), "décision TJ5 (textes natifs sans équivalent web)")
        XCTAssertTrue(puce.contains("« \(E.ouvrirReglages) »"),
                      "DECISIONS_LOT3.md liste « Ouvrir les réglages » parmi les textes sans équivalent web")
        try DecisionsLot3Document.assertHardStopSansRelectureEnAttente()
        let web = try Self.sourceDepot("src/pages/PageParametresNotifications.tsx")
        XCTAssertFalse(web.contains(E.ouvrirReglages), "aucune source web : le libellé n'est pas présenté comme verbatim")
    }

    func testChoixDuMessageCommeLeWeb() {
        XCTAssertNil(E.message(autorisation: nil, enregistrementConfirme: nil),
                     "lecture système immédiate : rien n'est affiché avant elle")
        XCTAssertEqual(E.message(autorisation: .accordee, enregistrementConfirme: nil), E.verification,
                       "autorisé, enregistrement en cours de vérification (web 'loading')")
        XCTAssertEqual(E.message(autorisation: .accordee, enregistrementConfirme: true), E.autorisees,
                       "hub, canal inconnu : l.346 (le web exige `canal_push` vrai, sinon l.347 : écart consigné, levé par T6)")
        XCTAssertEqual(E.message(autorisation: .provisoire, enregistrementConfirme: true), E.autorisees)
        XCTAssertEqual(E.message(autorisation: .accordee, enregistrementConfirme: false), E.nonEnregistre)
        XCTAssertEqual(E.message(autorisation: .provisoire, enregistrementConfirme: false), E.nonEnregistre)
        XCTAssertEqual(E.message(autorisation: .refusee, enregistrementConfirme: nil), E.bloquees)
        XCTAssertEqual(E.message(autorisation: .refusee, enregistrementConfirme: true), E.bloquees, "refus système prioritaire")
    }

    func testJamaisDemandeeNAffirmeLeCanalQueSIlEstConnuActif() {
        // l.349 affirme « Le canal est actif dans Jolene » : jamais sans connaître `canal_push`.
        XCTAssertNil(E.message(autorisation: .nonDemandee, enregistrementConfirme: nil), "hub : canal inconnu, aucune carte")
        XCTAssertNil(E.message(autorisation: .nonDemandee, enregistrementConfirme: false))
        XCTAssertEqual(E.message(autorisation: .nonDemandee, enregistrementConfirme: nil, canalPush: true), E.aAutoriser,
                       "préférences (T6), canal actif")
        XCTAssertNil(E.message(autorisation: .nonDemandee, enregistrementConfirme: nil, canalPush: false),
                     "canal coupé : le texte serait faux (le web l'affiche quel que soit le canal, écart à confirmer par T6)")
    }

    func testCanalPushConnuDesPreferences() {
        // Web l.345-347 : autorisé, canal coupé dans Jolene → message dédié (T6 fournit le canal).
        XCTAssertEqual(E.message(autorisation: .accordee, enregistrementConfirme: true, canalPush: false), E.canalDesactive)
        XCTAssertEqual(E.message(autorisation: .accordee, enregistrementConfirme: true, canalPush: true), E.autorisees)
        XCTAssertEqual(E.message(autorisation: .refusee, enregistrementConfirme: nil, canalPush: false), E.bloquees)
    }

    /// « Ouvrir les réglages » seulement quand seul un réglage système peut agir (refusé) ; « Activer sur cet
    /// appareil » là où le web propose sa relance (l.356), canal push connu actif ; sinon aucun bouton.
    func testActionDeLaCarte() {
        typealias A = EtatNotificationsAppareil.Action
        for canal: Bool? in [nil, false, true] {
            XCTAssertEqual(E.action(autorisation: .refusee, enregistrementConfirme: nil, canalPush: canal), A.ouvrirReglages,
                           "refusé : réactiver Jolene dans Réglages (canal \(String(describing: canal)))")
            XCTAssertNil(E.action(autorisation: .accordee, enregistrementConfirme: true, canalPush: canal), "autorisé et enregistré : superflu")
            XCTAssertNil(E.action(autorisation: .accordee, enregistrementConfirme: nil, canalPush: canal), "vérification en cours")
            XCTAssertNil(E.action(autorisation: nil, enregistrementConfirme: nil, canalPush: canal), "autorisation pas encore lue")
        }
        XCTAssertEqual(E.action(autorisation: .nonDemandee, enregistrementConfirme: nil, canalPush: true), A.activer,
                       "jamais demandé, canal actif : demande au tap (D1, web l.356)")
        XCTAssertNil(E.action(autorisation: .nonDemandee, enregistrementConfirme: nil, canalPush: false), "canal coupé : aucun bouton (web l.356)")
        XCTAssertNil(E.action(autorisation: .nonDemandee, enregistrementConfirme: nil, canalPush: nil),
                     "canal inconnu : Réglages n'a pas d'entrée Notifications tant que l'app n'a rien demandé")
        XCTAssertEqual(E.action(autorisation: .accordee, enregistrementConfirme: false, canalPush: true), A.activer,
                       "autorisé mais non enregistré : relance de l'enregistrement, Réglages n'y peut rien (mineur 4 de T4)")
        XCTAssertEqual(E.action(autorisation: .provisoire, enregistrementConfirme: false, canalPush: true), A.activer)
        XCTAssertNil(E.action(autorisation: .accordee, enregistrementConfirme: false, canalPush: false), "canal coupé : aucun bouton")
        XCTAssertNil(E.action(autorisation: .accordee, enregistrementConfirme: false, canalPush: nil))
        XCTAssertEqual(E.action(autorisation: .nonDemandee, enregistrementConfirme: nil, canalPush: true, indisponible: true), A.activer,
                       "activation en échec (web 'unavailable') : nouvel essai proposé")
        XCTAssertNil(E.action(autorisation: .accordee, enregistrementConfirme: nil, canalPush: false, indisponible: true))
        XCTAssertEqual(E.action(autorisation: .refusee, enregistrementConfirme: nil, canalPush: true, indisponible: true), A.activer,
                       "l'état indisponible prime, comme sur le web (le refus sera relu au prochain retour au premier plan)")
    }

    /// Web l.180-183 : une activation en échec affiche l'état indisponible (l.351), quel que soit l'état lu avant.
    func testActivationEnEchecAfficheLEtatIndisponible() {
        XCTAssertEqual(E.message(autorisation: .nonDemandee, enregistrementConfirme: nil, canalPush: true, indisponible: true),
                       E.indisponible)
        XCTAssertEqual(E.message(autorisation: .accordee, enregistrementConfirme: false, canalPush: true, indisponible: true),
                       E.indisponible)
        XCTAssertEqual(E.message(autorisation: nil, enregistrementConfirme: nil, canalPush: true, indisponible: true), E.indisponible)
        XCTAssertFalse(E.estPositif(autorisation: .accordee, enregistrementConfirme: true, indisponible: true))
    }

    func testTonDeLaCarte() {
        // Web l.328-332 : vert seulement quand le téléphone autorise et que l'appareil est enregistré.
        XCTAssertTrue(E.estPositif(autorisation: .accordee, enregistrementConfirme: true))
        XCTAssertFalse(E.estPositif(autorisation: .accordee, enregistrementConfirme: false))
        XCTAssertFalse(E.estPositif(autorisation: .accordee, enregistrementConfirme: nil))
        XCTAssertFalse(E.estPositif(autorisation: .refusee, enregistrementConfirme: true))
        XCTAssertFalse(E.estPositif(autorisation: nil, enregistrementConfirme: true))
    }
}

/// Modèle de la carte (lot 3, T4) : lecture de l'autorisation, puis, si elle permet l'enregistrement,
/// `PushCoordinator.surActive` (idempotent) et confirmation lue, comme le web l.142-158. Jamais de demande
/// d'autorisation (D1).
@MainActor
final class EtatNotificationsAppareilModelTests: XCTestCase {
    private typealias E = EtatNotificationsAppareil

    private func modele(_ monde: MondePush, _ snapshot: SessionSnapshot) -> EtatNotificationsAppareilModel {
        EtatNotificationsAppareilModel(push: monde.coordinator, permission: monde.permission, snapshot: snapshot)
    }

    func testAvantLaLectureAucuneCarte() async throws {
        let monde = MondePush()
        let model = modele(monde, try await monde.pret())
        XCTAssertNil(model.message)
        XCTAssertNil(model.action)
    }

    func testJamaisDemandeeDansLeHubAucuneCarteNiDemandeNiEnregistrement() async throws {
        let monde = MondePush(etat: .nonDemandee)
        let model = modele(monde, try await monde.pret())
        await model.verifier()
        XCTAssertEqual(model.autorisation, .nonDemandee)
        XCTAssertNil(model.message, "canal push inconnu dans le hub : jamais « Le canal est actif dans Jolene »")
        XCTAssertNil(model.action)
        let demandes = await monde.permission.demandes
        let enregistrements = await monde.registrar.enregistrements
        XCTAssertEqual(demandes, 0, "la carte ne demande jamais l'autorisation (D1)")
        XCTAssertEqual(enregistrements, 0)
        model.canalPush = true // préférences (T6) : canal connu actif
        XCTAssertEqual(model.message, E.aAutoriser)
        XCTAssertEqual(model.action, .activer, "préférences : « Activer sur cet appareil », jamais de demande sans tap")
        let demandesApres = await monde.permission.demandes
        XCTAssertEqual(demandesApres, 0)
    }

    func testAccordeeVerificationPuisConfirmationSansBouton() async throws {
        let barriere = Gate()
        let monde = MondePush(barriere: barriere)
        let model = modele(monde, try await monde.pret())
        let verification = Task { await model.verifier() }
        await waitUntil { await monde.registrar.enregistrements == 1 } // token APNs attendu
        XCTAssertEqual(model.message, E.verification)
        XCTAssertNil(model.action)
        await barriere.open()
        await verification.value
        XCTAssertEqual(model.message, E.autorisees)
        XCTAssertTrue(model.estPositif)
        XCTAssertNil(model.action, "autorisé et enregistré : aucun bouton")
    }

    func testNouvelleVerificationGardeLEtatConnu() async throws {
        // Retour au premier plan : l'état confirmé reste affiché pendant la relecture (pas de clignotement).
        let monde = MondePush()
        let model = modele(monde, try await monde.pret())
        await model.verifier()
        XCTAssertEqual(model.message, E.autorisees)
        let barriere = Gate()
        await monde.registrar.regler(barriere: barriere)
        let relecture = Task { await model.verifier() }
        await waitUntil { await monde.registrar.enregistrements == 2 }
        XCTAssertEqual(model.message, E.autorisees)
        await barriere.open()
        await relecture.value
        XCTAssertEqual(model.message, E.autorisees)
    }

    func testRefuseeProposeLesReglages() async throws {
        let monde = MondePush(etat: .refusee)
        let model = modele(monde, try await monde.pret())
        await model.verifier()
        XCTAssertEqual(model.message, E.bloquees)
        XCTAssertEqual(model.action, .ouvrirReglages)
        let enregistrements = await monde.registrar.enregistrements
        XCTAssertEqual(enregistrements, 0)
    }

    func testAccordeeNonEnregistreeProposeLActivationSiLeCanalEstActif() async throws {
        let monde = MondePush()
        await monde.gateway.echouerUpserts([JoleneError(.network, "hors ligne")])
        let model = modele(monde, try await monde.pret())
        await model.verifier()
        XCTAssertEqual(model.message, E.nonEnregistre)
        XCTAssertNil(model.action, "canal inconnu : aucun bouton (Réglages ne corrige pas un enregistrement en échec)")
        XCTAssertFalse(model.estPositif)
        model.canalPush = true
        XCTAssertEqual(model.action, .activer, "préférences, canal actif : relance (web l.356)")
    }

    // MARK: Activation au tap (lot 3, T6 ; D1 : « plus l'activation depuis Préférences »)

    func testActiverDemandeAuTapPuisEnregistre() async throws {
        let monde = MondePush(etat: .nonDemandee)
        await monde.permission.regler(apresDemande: .accordee)
        let model = EtatNotificationsAppareilModel(push: monde.coordinator, permission: monde.permission,
                                                   snapshot: try await monde.pret(), canalPush: true)
        await model.verifier()
        XCTAssertEqual(model.message, E.aAutoriser)
        await model.activer()
        let demandes = await monde.permission.demandes
        XCTAssertEqual(demandes, 1, "une seule demande, au tap")
        XCTAssertEqual(model.autorisation, .accordee)
        XCTAssertEqual(model.enregistrementConfirme, true)
        XCTAssertEqual(model.message, E.autorisees)
        XCTAssertNil(model.action)
        XCTAssertFalse(model.activationEnCours)
        let upserts = await monde.gateway.upserts
        XCTAssertEqual(upserts, [JetonsTest.hex(JetonsTest.a)], "l'appareil est enregistré après l'accord")
    }

    func testActiverRefuseAfficheBloquees() async throws {
        let monde = MondePush(etat: .nonDemandee)
        await monde.permission.regler(apresDemande: .refusee)
        let model = EtatNotificationsAppareilModel(push: monde.coordinator, permission: monde.permission,
                                                   snapshot: try await monde.pret(), canalPush: true)
        await model.verifier()
        await model.activer()
        XCTAssertEqual(model.message, E.bloquees)
        XCTAssertEqual(model.action, .ouvrirReglages)
        let enregistrements = await monde.registrar.enregistrements
        XCTAssertEqual(enregistrements, 0, "refusé : aucun token demandé")
    }

    func testActiverEnEchecAfficheIndisponiblePuisRelectureLeve() async throws {
        let monde = MondePush(etat: .nonDemandee)
        await monde.permission.regler(echecDemande: JoleneError(.unknown, "centre de notifications indisponible"))
        let model = EtatNotificationsAppareilModel(push: monde.coordinator, permission: monde.permission,
                                                   snapshot: try await monde.pret(), canalPush: true)
        await model.verifier()
        await model.activer()
        XCTAssertTrue(model.indisponible)
        XCTAssertEqual(model.message, E.indisponible, "web l.180-182 : 'unavailable'")
        XCTAssertEqual(model.action, .activer, "nouvel essai proposé")
        // Retour au premier plan : l'état système relu remplace l'état indisponible.
        await model.verifier()
        XCTAssertFalse(model.indisponible)
        XCTAssertEqual(model.message, E.aAutoriser)
    }

    func testActiverRelanceUnEnregistrementEnEchec() async throws {
        let monde = MondePush()
        await monde.gateway.echouerUpserts([JoleneError(.network, "hors ligne")])
        let model = EtatNotificationsAppareilModel(push: monde.coordinator, permission: monde.permission,
                                                   snapshot: try await monde.pret(), canalPush: true)
        await model.verifier()
        XCTAssertEqual(model.message, E.nonEnregistre)
        await model.activer()
        XCTAssertEqual(model.message, E.autorisees, "enregistrement relancé et confirmé")
        let upserts = await monde.gateway.upserts
        XCTAssertEqual(upserts.count, 1)
    }

    func testAucuneDoubleActivation() async throws {
        let barriere = Gate()
        let monde = MondePush(etat: .nonDemandee, barriere: barriere)
        await monde.permission.regler(apresDemande: .accordee)
        let model = EtatNotificationsAppareilModel(push: monde.coordinator, permission: monde.permission,
                                                   snapshot: try await monde.pret(), canalPush: true)
        let premiere = Task { await model.activer() }
        await waitUntil { await monde.registrar.enregistrements == 1 } // token APNs attendu, activation en vol
        XCTAssertTrue(model.activationEnCours)
        await model.activer()
        let demandes = await monde.permission.demandes
        XCTAssertEqual(demandes, 1, "un second tap pendant l'activation est ignoré")
        await barriere.open()
        await premiere.value
        XCTAssertFalse(model.activationEnCours)
        XCTAssertEqual(model.message, E.autorisees)
    }

    func testSansCoordinateurAucuneCarte() async throws {
        let monde = MondePush()
        let model = EtatNotificationsAppareilModel(push: nil, permission: nil, snapshot: try await monde.pret())
        await model.verifier()
        await model.activer()
        XCTAssertNil(model.autorisation)
        XCTAssertNil(model.message)
        let lectures = await monde.permission.lectures
        let demandes = await monde.permission.demandes
        XCTAssertEqual(lectures, 0)
        XCTAssertEqual(demandes, 0)
    }
}
