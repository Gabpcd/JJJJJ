import XCTest
@testable import JoleneCore

/// Drapeaux d'écran natif (lot 1, T9, décision 15) : `ios_natif_{accueil,explorer,missions,revenus,profil}_actif`
/// lus avec la session (aucun GRANT `anon`) après `.ready` et à la reprise, AVANT que l'espace ne
/// s'affiche (un écran coupé n'est jamais monté) ; défaut fail-open `true`. Les erreurs réseau et
/// 42501 du transport sont prouvées par `SupabaseFlagsGatewayTests` ; ici, le délai et l'epoch.
@MainActor
final class FeatureFlagsTests: XCTestCase {

    func testToutEstNatifAvantLaPremiereLecture() {
        let ecrans = EcransNatifsModel()
        for ecran in EcranNatif.allCases {
            XCTAssertTrue(ecrans.estActif(ecran), "\(ecran.cle) : fail-open")
        }
    }

    func testValeursServeurLuesAvantLAffichageDeLEspace() async {
        let script = FlagScript([EcranNatif.missions.cle: false])
        var monde = SessionDurcieMonde(restored: soignantDurci)
        monde.flags = ScriptedFlags(script: script)
        let store = monde.store()
        var observes: [(pret: Bool, missions: Bool)] = []
        let ecrans = store.ecrans
        // `@Published` émet avant l'affectation : la valeur lue ici est celle de l'instant où
        // `.ready` est publié, donc celle que voit `MainTabView` à son premier rendu.
        let abonnement = store.$state.sink { etat in observes.append((etat.isReady, ecrans.estActif(.missions))) }
        await store.start()
        abonnement.cancel()
        XCTAssertTrue(store.state.isReady)
        XCTAssertFalse(store.ecrans.estActif(.missions), "arrêt d'urgence : Mes missions renvoie vers le web")
        for ecran in [EcranNatif.accueil, .explorer, .revenus, .profil] {
            XCTAssertTrue(store.ecrans.estActif(ecran), "\(ecran.cle)")
        }
        let premierPret = observes.first { $0.pret }
        XCTAssertEqual(premierPret?.missions, false, "drapeaux appliqués avant la publication de .ready : l'écran coupé n'est jamais monté")
        let lectures = await script.lectures
        XCTAssertEqual(Set(lectures), Set(EcranNatif.allCases.map(\.cle)))
        XCTAssertEqual(lectures.count, 5, "une lecture par écran")
    }

    func testDrapeauMuetBorneRendFailOpen() async {
        let gate = Gate()
        let script = FlagScript([EcranNatif.explorer.cle: false])
        var monde = SessionDurcieMonde(restored: soignantDurci)
        monde.timeout = 0.05
        monde.flags = ScriptedFlags(script: script, gate: gate)
        let store = monde.store()
        await store.start()
        XCTAssertTrue(store.state.isReady, "un drapeau muet ne retient pas l'espace au-delà du délai")
        for ecran in EcranNatif.allCases {
            XCTAssertTrue(store.ecrans.estActif(ecran), "\(ecran.cle) : délai dépassé → défaut fail-open")
        }
        await gate.open()
    }

    func testRepriseRelitLesDrapeaux() async {
        let script = FlagScript()
        var monde = SessionDurcieMonde(restored: soignantDurci)
        monde.flags = ScriptedFlags(script: script)
        let store = monde.store()
        await store.start()
        XCTAssertTrue(store.ecrans.estActif(.revenus))
        await script.set(EcranNatif.revenus.cle, false)
        await store.start() // reprise > 30 min
        XCTAssertTrue(store.state.isReady)
        XCTAssertFalse(store.ecrans.estActif(.revenus), "la reprise relit parametres_systeme")
        await script.set(EcranNatif.revenus.cle, true)
        await store.start()
        XCTAssertTrue(store.ecrans.estActif(.revenus), "réactivation relue elle aussi")
        let lectures = await script.lectures
        XCTAssertEqual(lectures.count, 15)
    }

    func testConnexionExpliciteLitLesDrapeaux() async {
        let script = FlagScript([EcranNatif.profil.cle: false])
        var monde = SessionDurcieMonde()
        monde.flags = ScriptedFlags(script: script)
        let store = monde.store()
        await store.start()
        let avant = await script.lectures
        XCTAssertEqual(avant, [], "aucune lecture sans session (fn_param_bool refusé à anon)")
        await store.signIn(email: "t9@example.invalid", password: "secret-value")
        XCTAssertTrue(store.state.isReady)
        XCTAssertFalse(store.ecrans.estActif(.profil))
    }

    func testCompteBloqueOuConnexionRefuseeNeLitRien() async {
        let script = FlagScript()
        var monde = SessionDurcieMonde()
        monde.sansProfil = true
        monde.flags = ScriptedFlags(script: script)
        let store = monde.store()
        await store.signIn(email: "t9@example.invalid", password: "secret-value")
        guard case .blocked = store.state else { return XCTFail("obtenu \(store.state)") }
        let lectures = await script.lectures
        XCTAssertEqual(lectures, [], "drapeaux lus seulement pour un espace prêt")
    }

    func testLectureDUnEpochPerimeIgnoree() async {
        let gate = Gate()
        let script = FlagScript([EcranNatif.accueil.cle: false])
        let monde = SessionDurcieMonde(restored: soignantDurci)
        let controller = SessionController(gateways: {
            var g = monde.gateways()
            g.flags = ScriptedFlags(script: script, gate: gate)
            return g
        }())
        let etat = await controller.start()
        guard case let .ready(snapshot) = etat else { return XCTFail("obtenu \(etat)") }
        let ecrans = EcransNatifsModel()
        async let lecture: Void = ecrans.charger(snapshot: snapshot, controller: controller)
        await waitUntil { await script.demandes.count == EcranNatif.allCases.count }
        _ = await controller.signOut() // l'identité change pendant la lecture
        await gate.open()
        await lecture
        XCTAssertTrue(ecrans.estActif(.accueil), "réponse d'un epoch périmé ignorée")
    }

    func testEpochDejaPerimeNeLitRien() async {
        let script = FlagScript([EcranNatif.accueil.cle: false])
        var monde = SessionDurcieMonde(restored: soignantDurci)
        monde.flags = ScriptedFlags(script: script)
        let controller = SessionController(gateways: monde.gateways())
        let etat = await controller.start()
        guard case let .ready(snapshot) = etat else { return XCTFail("obtenu \(etat)") }
        _ = await controller.signOut()
        let ecrans = EcransNatifsModel()
        await ecrans.charger(snapshot: snapshot, controller: controller)
        let lectures = await script.lectures
        XCTAssertEqual(lectures, [], "gateways(for:) refuse un epoch périmé : aucun appel")
        XCTAssertTrue(ecrans.estActif(.accueil))
    }

    // MARK: - Écrans, routes et URL de renvoi

    func testTitresCheminsEtRoutesDesEcrans() {
        XCTAssertEqual(EcranNatif.allCases.map(\.titre), ["Accueil", "Explorer", "Mes missions", "Revenus", "Profil"])
        XCTAssertEqual(EcranNatif.allCases.map(\.urlWeb.absoluteString), [
            "https://jolene.app/soignant/tableau-de-bord",
            "https://jolene.app/soignant/recherche-missions",
            "https://jolene.app/soignant/missions",
            "https://jolene.app/soignant/mes-gains",
            "https://jolene.app/soignant/profil",
        ])
        for ecran in EcranNatif.allCases {
            let route = LinkRouter.resolve(link: ecran.urlWeb.absoluteString)
            XCTAssertEqual(route.flatMap(EcranNatif.init(route:)), ecran, "le chemin de renvoi désigne bien l'onglet \(ecran)")
        }
        XCTAssertNil(EcranNatif(route: .missionDetail(id: "m1")))
        XCTAssertNil(EcranNatif(route: .connexion))
        XCTAssertNil(EcranNatif(route: .safari(URL(string: "https://jolene.app/admin")!)))
    }

    // MARK: - Surcharges de lancement (DEBUG, démo)

    func testSurchargesDeLancement() {
        let arguments = ["Jolene", "-JOLENE_MODE", "demo",
                         "-JOLENE_FLAG_ios_natif_missions_actif", "false",
                         "-JOLENE_FLAG_ios_natif_accueil_actif", "true",
                         "-JOLENE_FLAG_ios_natif_revenus_actif", "0",
                         "-JOLENE_FLAG_ios_natif_profil_actif", "peut-etre",
                         "-JOLENE_FLAG_", "false",
                         "-JOLENE_FLAG_ios_natif_explorer_actif"]
        XCTAssertEqual(DrapeauxLancement.surcharges(arguments: arguments), [
            "ios_natif_missions_actif": false,
            "ios_natif_accueil_actif": true,
            "ios_natif_revenus_actif": false,
        ], "valeur illisible, clé vide ou valeur absente : ignorées (jamais une coupure inventée)")
        XCTAssertEqual(DrapeauxLancement.surcharges(arguments: ["Jolene"]), [:])
    }
}
