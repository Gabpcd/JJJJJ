import XCTest
@testable import JoleneCore

/// Drapeaux d'écran de l'espace établissement (lot 5, T2a ; D14, §2.8) : sept clés
/// `ios_natif_etab_<ecran>_actif` posées par la migration D-FLAGS (#1111), lues après
/// `.readyEtablissement`, défaut fail-open (`FlagsPolicy.defautFailOpen`), enum additive
/// `EcranNatifEtablissement` (l'enum `EcranNatif` du lot 1 reste inchangée).

/// Port de drapeaux qui ne répond jamais (backend muet).
private struct DrapeauxMuets: FlagsPort {
    let barriere = Gate()
    func ecranActif(cle: String, defaut: Bool) async -> Bool {
        await barriere.wait()
        return false
    }
}

@MainActor
final class EtabFeatureFlagsTests: XCTestCase {
    static let septCles = [
        "ios_natif_etab_accueil_actif", "ios_natif_etab_missions_actif", "ios_natif_etab_publier_actif",
        "ios_natif_etab_presences_actif", "ios_natif_etab_pointage_actif", "ios_natif_etab_messages_actif",
        "ios_natif_etab_compte_actif",
    ]

    /// Session établissement démo prête (monde démo, aucun réseau), drapeaux remplacés par `flags`.
    private func sessionPrete(flags: FlagsPort) async throws -> (SessionController, EtablissementSessionSnapshot) {
        var gateways = DemoWorld.gateways(espace: .etablissement(.init()))
        gateways.flags = flags
        let controller = SessionController(gateways: gateways)
        _ = await controller.start()
        let state = await controller.signIn(email: DemoEspace.emailEtablissement, password: "demonstration")
        let snapshot = try XCTUnwrap(state.snapshotEtablissement, "espace établissement démo attendu, obtenu \(state)")
        return (controller, snapshot)
    }

    func testSeptClesIdentiquesALaMigrationDFlags() throws {
        XCTAssertEqual(EcranNatifEtablissement.allCases.map(\.cle), Self.septCles, "D14 : sept clés, pointage compris")
        XCTAssertTrue(Set(EcranNatifEtablissement.allCases.map(\.cle)).isDisjoint(with: EcranNatif.allCases.map(\.cle)),
                      "enum additive : aucune clé du lot 1 reprise")
        let migration = try SourceWebLot5.lire("supabase/migrations/20261102204450_drapeaux_ios_natif_lots_2_4_5.sql")
        let motif = try NSRegularExpression(pattern: "'(ios_natif_etab_[a-z_]+_actif)'")
        let plage = NSRange(migration.startIndex..., in: migration)
        let clesMigration = Set(motif.matches(in: migration, range: plage).compactMap { resultat -> String? in
            Range(resultat.range(at: 1), in: migration).map { String(migration[$0]) }
        })
        XCTAssertEqual(clesMigration, Set(Self.septCles), "chaque clé lue par l'app existe dans parametres_systeme")
    }

    func testPermissionEtCheminWebParEcran() {
        XCTAssertEqual(EcranNatifEtablissement.accueil.permissionRequise, .lecture)
        XCTAssertEqual(EcranNatifEtablissement.missions.permissionRequise, .lecture)
        XCTAssertEqual(EcranNatifEtablissement.presences.permissionRequise, .lecture)
        XCTAssertEqual(EcranNatifEtablissement.messages.permissionRequise, .lecture)
        XCTAssertEqual(EcranNatifEtablissement.publier.permissionRequise, .missions)
        XCTAssertEqual(EcranNatifEtablissement.pointage.permissionRequise, .pointage)
        XCTAssertNil(EcranNatifEtablissement.compte.permissionRequise, "déconnexion et suppression toujours atteignables")
        XCTAssertEqual(EcranNatifEtablissement.accueil.cheminWeb, "/etablissement/tableau-de-bord")
        XCTAssertEqual(EcranNatifEtablissement.missions.cheminWeb, "/etablissement/missions")
        XCTAssertEqual(EcranNatifEtablissement.publier.cheminWeb, "/etablissement/missions/creer")
        XCTAssertEqual(EcranNatifEtablissement.presences.cheminWeb, "/etablissement/presences")
        XCTAssertEqual(EcranNatifEtablissement.pointage.cheminWeb, "/etablissement/presences")
        XCTAssertEqual(EcranNatifEtablissement.messages.cheminWeb, "/etablissement/messagerie")
        XCTAssertEqual(EcranNatifEtablissement.compte.cheminWeb, "/etablissement/mon-compte")
        for ecran in EcranNatifEtablissement.allCases {
            XCTAssertEqual(ecran.urlWeb.absoluteString, "https://jolene.app\(ecran.cheminWeb)")
            XCTAssertFalse(ecran.titre.isEmpty)
        }
    }

    func testToutEstActifTantQueRienNEstLu() {
        let ecrans = EcransEtablissementModel()
        for ecran in EcranNatifEtablissement.allCases {
            XCTAssertTrue(ecrans.estActif(ecran, epoch: 1), "\(ecran.cle) : fail-open avant toute lecture")
        }
        XCTAssertNil(ecrans.epochCharge)
    }

    func testErreurOuDrapeauAbsentRendVrai() async throws {
        // `FlagsPort` ne lève jamais : erreur réseau, 42501 ou clé absente rendent `defaut` (lot 1).
        let (controller, snapshot) = try await sessionPrete(flags: FakeFlags())
        let ecrans = EcransEtablissementModel()
        await ecrans.charger(snapshot: snapshot, controller: controller)
        XCTAssertEqual(ecrans.epochCharge, snapshot.epoch)
        for ecran in EcranNatifEtablissement.allCases {
            XCTAssertTrue(ecrans.estActif(ecran, epoch: snapshot.epoch), "\(ecran.cle) : défaut fail-open")
        }
    }

    func testDrapeauCoupeHonoreSeulementPourSonEpoch() async throws {
        let flags = FakeFlags(valeurs: [EcranNatifEtablissement.presences.cle: false, EcranNatif.accueil.cle: false])
        let (controller, snapshot) = try await sessionPrete(flags: flags)
        let ecrans = EcransEtablissementModel()
        await ecrans.charger(snapshot: snapshot, controller: controller)
        XCTAssertFalse(ecrans.estActif(.presences, epoch: snapshot.epoch))
        XCTAssertTrue(ecrans.estActif(.accueil, epoch: snapshot.epoch), "la clé soignant du lot 1 ne coupe pas l'établissement")
        XCTAssertTrue(ecrans.estActif(.presences, epoch: snapshot.epoch + 1),
                      "une valeur lue pour une autre identité ne s'applique jamais")
    }

    func testDelaiEpuiseRendVrai() async throws {
        let (controller, snapshot) = try await sessionPrete(flags: DrapeauxMuets())
        let ecrans = EcransEtablissementModel()
        await ecrans.charger(snapshot: snapshot, controller: controller, delai: 0.05)
        for ecran in EcranNatifEtablissement.allCases {
            XCTAssertTrue(ecrans.estActif(ecran, epoch: snapshot.epoch), "\(ecran.cle) : délai dépassé → actif")
        }
    }

    func testLectureIgnoreePourUnEpochPerime() async throws {
        let flags = FakeFlags(valeurs: [EcranNatifEtablissement.missions.cle: false])
        let (controller, snapshot) = try await sessionPrete(flags: flags)
        _ = await controller.signOut()
        let ecrans = EcransEtablissementModel()
        await ecrans.charger(snapshot: snapshot, controller: controller)
        XCTAssertNil(ecrans.epochCharge, "aucune lecture pour une identité retirée")
        XCTAssertTrue(ecrans.estActif(.missions, epoch: snapshot.epoch))
    }

    func testStoreLitLesDrapeauxAvantDePublierLEspace() async throws {
        let gateways = DemoWorld.gateways(espace: .etablissement(.init()),
                                          drapeaux: [EcranNatifEtablissement.messages.cle: false])
        let store = SessionStore(controller: SessionController(gateways: gateways))
        await store.start()
        await store.signIn(email: DemoEspace.emailEtablissement, password: "demonstration")
        let snapshot = try XCTUnwrap(store.state.snapshotEtablissement, "obtenu \(store.state)")
        XCTAssertEqual(store.ecransEtablissement.epochCharge, snapshot.epoch, "drapeaux lus avant la publication de l'espace")
        XCTAssertFalse(store.ecransEtablissement.estActif(.messages, epoch: snapshot.epoch))
        XCTAssertTrue(store.ecransEtablissement.estActif(.accueil, epoch: snapshot.epoch))
    }

    func testSurchargeDeLancementDUnDrapeauEtablissement() async {
        let surcharges = DrapeauxLancement.surcharges(arguments: ["Jolene", "-JOLENE_MODE", "demo",
                                                                  "-JOLENE_FLAG_ios_natif_etab_presences_actif", "false"])
        XCTAssertEqual(surcharges, [EcranNatifEtablissement.presences.cle: false])
        let flags = DemoWorld.gateways(espace: .etablissement(.init()), drapeaux: surcharges).flags
        let presences = await flags.ecranEtablissementActif(.presences)
        let accueil = await flags.ecranEtablissementActif(.accueil)
        XCTAssertFalse(presences)
        XCTAssertTrue(accueil)
    }
}
