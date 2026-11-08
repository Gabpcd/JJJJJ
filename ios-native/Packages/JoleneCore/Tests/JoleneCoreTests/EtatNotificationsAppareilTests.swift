import XCTest
@testable import JoleneCore

/// Carte « Autorisation du téléphone » (lot 3, T4 ; hôte définitif : préférences de T6) : textes
/// verbatim de `src/pages/PageParametresNotifications.tsx` l.341-352 (HARD STOP n°4), choisis comme
/// le web l.147-155 : autorisé ET enregistrement confirmé → « autorisées », autorisé sans
/// confirmation → « n'a pas pu être enregistré », vérification en cours → « Vérification… »,
/// refusé → « bloquées ». « Jamais demandé » (l.349, « Le canal est actif dans Jolene… ») n'est
/// affiché que si le canal push est connu actif (préférences, T6) : dans le hub, aucune carte. Bouton
/// « Ouvrir les réglages » seulement quand un réglage système est utile (refusé, ou autorisé sans
/// enregistrement confirmé).
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

    func testLibelleDeSectionDuHubWeb() throws {
        let web = try Self.sourceDepot("src/pages/MonCompteSoignant.tsx")
        let ligne = web.components(separatedBy: "\n")[114]
        XCTAssertTrue(ligne.contains("label: '\(E.sectionHub)'"), "MonCompteSoignant.tsx l.115")
    }

    func testLibelleOuvrirLesReglagesEpingleSansSourceWeb() throws {
        // Action native sans équivalent web (le web n'ouvre pas les réglages système), non juridique : nommée
        // au §1.1 du blueprint, listée parmi les textes à relire par Gabrielle (`DECISIONS_LOT3.md`, HARD STOP).
        XCTAssertEqual(E.ouvrirReglages, "Ouvrir les réglages")
        let blueprint = try Self.sourceDepot("docs/mobile-swift/LOT3_PLAN.md")
        XCTAssertTrue(blueprint.contains("« \(E.ouvrirReglages) »"), "LOT3_PLAN.md §1.1 nomme le libellé")
        // Le libellé figure dans la puce « Textes **sans équivalent web** (non juridiques, à relire par Gabrielle) ».
        let decisions = try Self.sourceDepot("docs/mobile-swift/DECISIONS_LOT3.md")
        let entete = "- Textes **sans équivalent web** (non juridiques, à relire par Gabrielle)"
        let debut = try XCTUnwrap(decisions.range(of: entete), "puce des textes sans équivalent web de DECISIONS_LOT3.md")
        let suite = decisions[debut.upperBound...]
        let puce = suite.range(of: "\n- ").map { suite[..<$0.lowerBound] } ?? suite
        XCTAssertTrue(puce.contains("« \(E.ouvrirReglages) »"),
                      "DECISIONS_LOT3.md liste « Ouvrir les réglages » parmi les textes sans équivalent web")
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

    func testOuvrirLesReglagesSeulementQuandUnReglageEstUtile() {
        XCTAssertTrue(E.proposeReglages(autorisation: .refusee, enregistrementConfirme: nil), "réactiver Jolene dans Réglages")
        XCTAssertTrue(E.proposeReglages(autorisation: .accordee, enregistrementConfirme: false), "autorisé mais non enregistré")
        XCTAssertTrue(E.proposeReglages(autorisation: .provisoire, enregistrementConfirme: false))
        XCTAssertFalse(E.proposeReglages(autorisation: .accordee, enregistrementConfirme: true), "autorisé et enregistré : superflu")
        XCTAssertFalse(E.proposeReglages(autorisation: .accordee, enregistrementConfirme: nil), "vérification en cours")
        XCTAssertFalse(E.proposeReglages(autorisation: .nonDemandee, enregistrementConfirme: nil),
                       "jamais demandé : Réglages n'a pas d'entrée Notifications tant que l'app n'a rien demandé")
        XCTAssertFalse(E.proposeReglages(autorisation: nil, enregistrementConfirme: nil))
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
        XCTAssertFalse(model.proposeReglages)
    }

    func testJamaisDemandeeDansLeHubAucuneCarteNiDemandeNiEnregistrement() async throws {
        let monde = MondePush(etat: .nonDemandee)
        let model = modele(monde, try await monde.pret())
        await model.verifier()
        XCTAssertEqual(model.autorisation, .nonDemandee)
        XCTAssertNil(model.message, "canal push inconnu dans le hub : jamais « Le canal est actif dans Jolene »")
        XCTAssertFalse(model.proposeReglages)
        let demandes = await monde.permission.demandes
        let enregistrements = await monde.registrar.enregistrements
        XCTAssertEqual(demandes, 0, "la carte ne demande jamais l'autorisation (D1)")
        XCTAssertEqual(enregistrements, 0)
        model.canalPush = true // préférences (T6) : canal connu actif
        XCTAssertEqual(model.message, E.aAutoriser)
    }

    func testAccordeeVerificationPuisConfirmationSansBouton() async throws {
        let barriere = Gate()
        let monde = MondePush(barriere: barriere)
        let model = modele(monde, try await monde.pret())
        let verification = Task { await model.verifier() }
        await waitUntil { await monde.registrar.enregistrements == 1 } // token APNs attendu
        XCTAssertEqual(model.message, E.verification)
        XCTAssertFalse(model.proposeReglages)
        await barriere.open()
        await verification.value
        XCTAssertEqual(model.message, E.autorisees)
        XCTAssertTrue(model.estPositif)
        XCTAssertFalse(model.proposeReglages, "autorisé et enregistré : « Ouvrir les réglages » superflu")
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
        XCTAssertTrue(model.proposeReglages)
        let enregistrements = await monde.registrar.enregistrements
        XCTAssertEqual(enregistrements, 0)
    }

    func testAccordeeNonEnregistreeProposeLesReglages() async throws {
        let monde = MondePush()
        await monde.gateway.echouerUpserts([JoleneError(.network, "hors ligne")])
        let model = modele(monde, try await monde.pret())
        await model.verifier()
        XCTAssertEqual(model.message, E.nonEnregistre)
        XCTAssertTrue(model.proposeReglages)
        XCTAssertFalse(model.estPositif)
    }

    func testSansCoordinateurAucuneCarte() async throws {
        let monde = MondePush()
        let model = EtatNotificationsAppareilModel(push: nil, permission: nil, snapshot: try await monde.pret())
        await model.verifier()
        XCTAssertNil(model.autorisation)
        XCTAssertNil(model.message)
        let lectures = await monde.permission.lectures
        XCTAssertEqual(lectures, 0)
    }
}
