import XCTest
@testable import JoleneCore

/// Taps push du lot 3 (T5 ; blueprint §2.5, §3 T5) : payload réduit aux paires textuelles, routage golden
/// (`PushRouting`, lien explicite d'abord, rôle du snapshot), destination par `DestinationLien` (routes de T3a),
/// tap avant `.ready` différé puis rejoué avec le rôle, tap lié à un autre epoch écarté, lien externe refusé,
/// racine « / » avec un type connu → repli métier ; cible présentée dans l'espace (`CibleNotification`).
@MainActor
final class PushTapIntentTests: XCTestCase {
    private func url(_ s: String) -> URL { URL(string: s)! }

    private func snapshot(epoch: Int, role: String = "SOIGNANT") -> SessionSnapshot {
        let user = AuthenticatedUser(id: "u-tap", email: "u-tap@example.invalid",
                                     emailConfirmedAt: Date(timeIntervalSince1970: 1_700_000_000), appMetadataRole: role)
        let profil = SoignantProfile(id: user.id, profession: "IDE")
        return SessionSnapshot(user: user, role: RoleResult(role: role), profile: profil,
                               context: MissionReadContext(userId: user.id, email: user.email, profile: profil), epoch: epoch)
    }

    // MARK: - Payload

    func testUserInfoReduitAuxPairesTextuelles() {
        let userInfo: [AnyHashable: Any] = [
            "aps": ["alert": ["title": "Titre", "body": "Corps"], "sound": "default"],
            "type_evenement": "RAPPEL_MISSION", "mission_id": "m-1", "compteur": 3, 7: "valeur à clé non textuelle",
        ]
        let tap = PushTapIntent(userInfo: userInfo)
        XCTAssertEqual(tap.donnees, ["type_evenement": "RAPPEL_MISSION", "mission_id": "m-1"])
        XCTAssertEqual(tap.destination(role: "SOIGNANT")?.destination, .missionDetail(id: "m-1"))
    }

    func testLienExpliciteDAbordPuisRepliMetierSurLaRacine() throws {
        // Lien interne : gagne sur le type (`lienExplicite`, `pushNative.ts` l.59-66).
        let lien = PushTapIntent(donnees: ["type_evenement": "RAPPEL_MISSION", "mission_id": "m-1",
                                           "lien": "/soignant/notifications"])
        XCTAssertEqual(lien.destination(role: "SOIGNANT")?.route, .notifications)
        // « / » avec un type connu : repli métier (ancien dispatcher qui injectait la racine).
        let racine = PushTapIntent(donnees: ["type_evenement": "RAPPEL_MISSION", "mission_id": "m-1", "lien": "/"])
        XCTAssertEqual(racine.destination(role: "SOIGNANT")?.destination, .missionDetail(id: "m-1"))
        // « / » sans type : la racine, renvoi web.
        let seul = PushTapIntent(donnees: ["lien": "/"])
        XCTAssertEqual(seul.destination(role: nil)?.destination, .safari(url("https://jolene.app/")))
    }

    func testLienExterneRefuseJamaisOuvert() {
        // Hôte étranger : ignoré, le type décide ; sans type, aucune destination.
        let avecType = PushTapIntent(donnees: ["type_evenement": "CANDIDATURE_ACCEPTEE", "mission_id": "m 1",
                                               "lien": "https://evil.example/soignant/missions/x"])
        XCTAssertEqual(avecType.destination(role: "SOIGNANT")?.destination, .missionDetail(id: "m 1"))
        for lien in ["https://evil.example/soignant/notifications", "http://jolene.app/soignant/notifications",
                     "javascript:alert(1)"] {
            XCTAssertNil(PushTapIntent(donnees: ["lien": lien]).destination(role: "SOIGNANT"), lien)
        }
        XCTAssertNil(PushTapIntent(donnees: ["type_evenement": "TYPE_INCONNU"]).destination(role: "SOIGNANT"))
        XCTAssertNil(PushTapIntent(donnees: [:]).destination(role: "SOIGNANT"))
    }

    /// Au moins six types de la table du web (critère « tap ouvrant l'écran attendu », niveau 1 ici) : route
    /// résolue et cible de l'espace. `FACTURE_EMISE`, `PAIEMENT_RECU` et les préférences visent des écrans livrés
    /// après T5 : seule la route résolue est affirmée (renvoi web d'ici leur tranche).
    func testCiblesDesTypesPrincipaux() throws {
        let cas: [(donnees: [String: String], route: JoleneRoute, cible: CibleNotification)] = [
            (["type_evenement": "RAPPEL_MISSION", "mission_id": "demo-assignee-001"],
             .missionDetail(id: "demo-assignee-001"), .mission(id: "demo-assignee-001")),
            (["type_evenement": "CANDIDATURE_ACCEPTEE", "mission_id": "demo-mission-002"],
             .missionDetail(id: "demo-mission-002"), .mission(id: "demo-mission-002")),
            (["type_evenement": "MISSION_ASSIGNEE", "mission_id": "m-3"], .missionDetail(id: "m-3"), .mission(id: "m-3")),
            (["type_evenement": "MISSION_A_POURVOIR"], .explorer, .onglet(.explorer)),
            (["type_evenement": "MISSION_ANNULEE_ETAB"], .missions, .onglet(.missions)),
            (["type_evenement": "SYSTEM", "lien": "/soignant/notifications"], .notifications, .centre),
            (["type_evenement": "LITIGE_OUVERT", "litige_id": "l1"],
             .safari(url("https://jolene.app/soignant/litiges#l1")), .web(.safari(url("https://jolene.app/soignant/litiges#l1")))),
            (["type_evenement": "CONTRAT_A_SIGNER", "contrat_id": "c1"],
             .safari(url("https://jolene.app/contrat/c1")), .web(.safari(url("https://jolene.app/contrat/c1")))),
            (["type_evenement": "FACTURE_EMISE"], .revenus(section: .factures),
             .web(.safari(url("https://jolene.app/soignant/mes-gains?tab=factures")))),
            (["type_evenement": "PAIEMENT_RECU"], .revenus(section: .paiementsAConfirmer),
             .web(.safari(url("https://jolene.app/soignant/mes-gains?tab=paiements")))),
            (["type_evenement": "SYSTEM", "lien": "/soignant/parametres/notifications"], .parametresNotifications,
             .web(.safari(url("https://jolene.app/soignant/parametres/notifications")))),
        ]
        for c in cas {
            let lien = try XCTUnwrap(PushTapIntent(donnees: c.donnees).destination(role: "SOIGNANT"), "\(c.donnees)")
            XCTAssertEqual(lien.route, c.route, "\(c.donnees)")
            XCTAssertEqual(CibleNotification(lien), c.cible, "\(c.donnees)")
        }
    }

    func testRoleDuSnapshotPourLesTypesEtablissement() throws {
        let tap = PushTapIntent(donnees: ["type_evenement": "FACTURE_EMISE", "facture_id": "f1"])
        XCTAssertEqual(tap.destination(role: "SOIGNANT")?.route, .revenus(section: .factures))
        XCTAssertEqual(tap.destination(role: "ADMIN_ETABLISSEMENT")?.destination,
                       .etablissement(url("https://jolene.app/etablissement/facturation/f1")))
    }

    // MARK: - Boîte des taps (epoch, rejeu)

    func testTapAvantReadyDiffereEtRejoueAvecLeRole() {
        let boite = BoiteTapsPush()
        boite.recevoir(PushTapIntent(donnees: ["type_evenement": "FACTURE_EMISE", "facture_id": "f1"]))
        XCTAssertEqual(boite.tapsRecus, 1)
        XCTAssertTrue(boite.aUnTapEnAttente, "aucun espace ouvert : le tap attend")
        // Premier espace prêt (connexion après un lancement à froid) : rôle établissement connu à ce moment.
        let lien = boite.prendre(pour: snapshot(epoch: 3, role: "ADMIN_ETABLISSEMENT"))
        XCTAssertEqual(lien?.route, .etablissement(url("https://jolene.app/etablissement/facturation/f1")))
        XCTAssertFalse(boite.aUnTapEnAttente)
        XCTAssertNil(boite.prendre(pour: snapshot(epoch: 3)), "rejoué une seule fois")
    }

    func testTapPendantUnEspaceLieASonEpochEtEcarteParUnAutre() {
        let boite = BoiteTapsPush()
        XCTAssertNil(boite.prendre(pour: snapshot(epoch: 1)), "ouverture de l'espace 1, rien en attente")
        boite.recevoir(PushTapIntent(donnees: ["type_evenement": "RAPPEL_MISSION", "mission_id": "m-1"]))
        // L'espace 1 disparaît (déconnexion) avant d'avoir relu la boîte ; une autre identité ouvre l'espace 2.
        boite.fermerEspace(epoch: 1)
        XCTAssertNil(boite.prendre(pour: snapshot(epoch: 2)), "tap d'un autre epoch : jamais présenté")
        XCTAssertFalse(boite.aUnTapEnAttente, "écarté, pas gardé pour plus tard")
        // Un tap reçu pendant l'espace 2 lui est présenté.
        boite.recevoir(PushTapIntent(donnees: ["type_evenement": "RAPPEL_MISSION", "mission_id": "m-2"]))
        XCTAssertEqual(boite.prendre(pour: snapshot(epoch: 2))?.destination, .missionDetail(id: "m-2"))
    }

    func testFermetureDUnAncienEspaceNeFermePasLeSuivant() {
        let boite = BoiteTapsPush()
        _ = boite.prendre(pour: snapshot(epoch: 4))
        _ = boite.prendre(pour: snapshot(epoch: 5)) // le nouvel espace apparaît avant la disparition de l'ancien
        boite.fermerEspace(epoch: 4)
        boite.recevoir(PushTapIntent(donnees: ["type_evenement": "MISSION_A_POURVOIR"]))
        XCTAssertEqual(boite.prendre(pour: snapshot(epoch: 5))?.destination, .explorer, "lié à l'espace 5 resté ouvert")
    }

    func testLeDernierTapGagne() {
        let boite = BoiteTapsPush()
        boite.recevoir(PushTapIntent(donnees: ["type_evenement": "MISSION_A_POURVOIR"]))
        boite.recevoir(PushTapIntent(donnees: ["type_evenement": "MISSION_ANNULEE_ETAB"]))
        XCTAssertEqual(boite.tapsRecus, 2)
        XCTAssertEqual(boite.prendre(pour: snapshot(epoch: 1))?.destination, .missions)
        XCTAssertNil(boite.prendre(pour: snapshot(epoch: 1)))
    }

    func testPremierPlanSignale() {
        let boite = BoiteTapsPush()
        boite.signalerPremierPlan()
        boite.signalerPremierPlan()
        XCTAssertEqual(boite.premiersPlans, 2)
        XCTAssertEqual(boite.tapsRecus, 0, "une notification au premier plan n'est pas un tap")
    }

    // MARK: - Simulation DEBUG

    func testArgumentDeSimulation() {
        XCTAssertEqual(PushTapIntent.argumentSimulation, "-JOLENE_SIMULER_PUSH")
        func simule(_ valeur: String) -> [String: String]? {
            PushTapIntent.simule(arguments: ["-JOLENE_MODE", "demo", "-JOLENE_SIMULER_PUSH", valeur])?.donnees
        }
        XCTAssertEqual(simule("RAPPEL_MISSION:demo-assignee-001"),
                       ["type_evenement": "RAPPEL_MISSION", "mission_id": "demo-assignee-001"])
        XCTAssertEqual(simule("MISSION_A_POURVOIR"), ["type_evenement": "MISSION_A_POURVOIR"])
        XCTAssertEqual(simule("CONTRAT_A_SIGNER:contrat_id=c1"), ["type_evenement": "CONTRAT_A_SIGNER", "contrat_id": "c1"])
        XCTAssertEqual(simule("SYSTEM::https://jolene.app/soignant/notifications?x=1"),
                       ["type_evenement": "SYSTEM", "lien": "https://jolene.app/soignant/notifications?x=1"],
                       "le lien garde ses « : »")
        XCTAssertNil(simule(""))
        XCTAssertNil(simule(":m-1"))
        XCTAssertNil(PushTapIntent.simule(arguments: ["-JOLENE_SIMULER_PUSH"]))
        XCTAssertNil(PushTapIntent.simule(arguments: []))
    }

    func testLibelleDebugDeLaRoutePresentee() {
        XCTAssertEqual(PushTapIntent.libelleDebug(.missionDetail(id: "demo-assignee-001")), "missionDetail demo-assignee-001")
        XCTAssertEqual(PushTapIntent.libelleDebug(.safari(url("https://jolene.app/soignant/litiges"))),
                       "safari https://jolene.app/soignant/litiges")
        XCTAssertEqual(PushTapIntent.libelleDebug(.explorer), "explorer")
        XCTAssertEqual(PushTapIntent.libelleDebug(.notifications), "notifications")
    }

    // MARK: - Journalisation (PRINCIPES §7)

    func testDescriptionSansIdentifiantNiLien() {
        let tap = PushTapIntent(donnees: ["type_evenement": "CONTRAT_A_SIGNER", "contrat_id": "SECRET-ID-1",
                                          "lien": "/etab/invitation/SECRET-JETON-2"])
        for texte in [String(describing: tap), String(reflecting: tap), "\(tap)", "\(Mirror(reflecting: tap).children.map { $0.value })"] {
            XCTAssertFalse(texte.contains("SECRET"), texte)
        }
        XCTAssertEqual(tap.description, "PushTapIntent(type: « CONTRAT_A_SIGNER », clés: contrat_id, lien, type_evenement)")
    }
}
