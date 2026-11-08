import XCTest
@testable import JoleneCore

/// Utilisateur restauré par les ports d'auth de ces tests (hors du main actor : lu par les ports).
private let utilisateurCentre = AuthenticatedUser(id: "u-centre", email: "u-centre@example.invalid",
                                                  emailConfirmedAt: Date(timeIntervalSince1970: 1_700_000_000),
                                                  appMetadataRole: "SOIGNANT")

/// Centre de notifications (lot 3, T5 ; `PageNotifications.tsx` l.46-103) : liste relue pour l'epoch, état vide
/// sans faux succès, erreur au texte web et « Réessayer », relecture silencieuse qui garde la liste, marquage lu
/// **relu** avant toute navigation (un échec n'ouvre rien), lien invalide signalé, cible présentable seulement
/// (jamais un bouton sans effet), textes verbatim.
@MainActor
final class CentreNotificationsTests: XCTestCase {
    /// Port scripté : réponses de `liste` dans l'ordre, marquage relu ou en échec, journal des appels.
    private actor PortScripte: NotificationsCenterPort {
        var listes: [Result<[NotificationJolene], JoleneError>]
        var marquage: Result<NotificationJolene?, JoleneError> = .success(nil)
        private(set) var appelsListe = 0
        private(set) var marquees: [String] = []
        private var barriere: Gate?

        init(_ listes: [Result<[NotificationJolene], JoleneError>]) { self.listes = listes }

        func liste(context: MissionReadContext) async throws -> [NotificationJolene] {
            appelsListe += 1
            if let barriere { await barriere.wait() }
            return try (listes.isEmpty ? .success([]) : listes.removeFirst()).get()
        }

        func marquerLue(id: String, context: MissionReadContext) async throws -> NotificationJolene {
            marquees.append(id)
            switch marquage {
            case .success(let ligne?): return ligne
            case .success(nil): return NotificationJolene(id: id, type: "SYSTEM", titre: "t", corps: "c", lue: true)
            case .failure(let erreur): throw erreur
            }
        }

        func regler(marquage: Result<NotificationJolene?, JoleneError>) { self.marquage = marquage }
        func regler(barriere: Gate?) { self.barriere = barriere }
            }

    private struct PretAuth: AuthPort {
        func restoreSession() async throws -> AuthenticatedUser? { utilisateurCentre }
        func signIn(email: String, password: String) async throws -> AuthenticatedUser {
            throw JoleneError(.invalidCredentials, "refus")
        }
        func signOut() async throws {}
    }

    private func pret(_ port: PortScripte) async throws -> (SessionController, SessionSnapshot) {
        var gateways = Gateways(auth: PretAuth(), role: NeutralRole(), missions: PushMissions(), clock: FixedClock(DemoWorld.fixedNow))
        gateways.notifications = port
        let controller = SessionController(gateways: gateways)
        let etat = await controller.start()
        let snapshot = try XCTUnwrap(etat.snapshot, "session prête attendue, obtenu \(etat)")
        return (controller, snapshot)
    }

    private func ligne(_ id: String, lien: String? = nil, lue: Bool = false) -> NotificationJolene {
        NotificationJolene(id: id, type: "SYSTEM", titre: "Titre \(id)", corps: "Corps \(id)", lien: lien, lue: lue,
                           creeLe: "2026-11-01T22:00:00.000Z")
    }

    // MARK: - Textes

    func testTextesVerbatimDuWeb() {
        XCTAssertEqual(CentreNotificationsTextes.titre, "Notifications")
        XCTAssertEqual(CentreNotificationsTextes.erreurChargement, "Impossible de charger vos notifications.")
        XCTAssertEqual(CentreNotificationsTextes.reessayer, "Réessayer")
        XCTAssertEqual(CentreNotificationsTextes.videTitre, "Tout est lu !")
        XCTAssertEqual(CentreNotificationsTextes.videDescription, "Vous n'avez aucune notification.")
        XCTAssertEqual(CentreNotificationsTextes.marquerLueImpossible, "Impossible de marquer cette notification comme lue.")
        XCTAssertEqual(CentreNotificationsTextes.lienInvalide, "Le lien de cette notification n’est pas valide.")
        XCTAssertEqual(CentreNotificationsTextes.voir, "Voir")
        XCTAssertEqual(CentreNotificationsTextes.nonLue, "Non lue")
        XCTAssertEqual(CentreNotificationsModel.limite, 200, ".limit(200), l.58")
    }

    // MARK: - Décodage

    func testDecodageToleranteDeLaLigne() throws {
        let json = """
        [{"id":"n1","titre":"T","corps":"C","type":"RAPPEL_MISSION","lien":"/soignant/missions/m1","lue":true,
          "lue_le":"2026-11-01T22:05:00+00:00","cree_le":"2026-11-01T22:00:00.123456+00:00"},
         {"id":"n2","titre":"T2","corps":"C2","type":"SYSTEM","lien":null,"lue":null,"lue_le":null,"cree_le":null},
         {"id":"n3","titre":"T3","corps":"C3","type":"SYSTEM"}]
        """
        let lignes = try JSONDecoder().decode([NotificationJolene].self, from: Data(json.utf8))
        XCTAssertEqual(lignes.map(\.id), ["n1", "n2", "n3"])
        XCTAssertEqual(lignes[0].lue, true)
        XCTAssertEqual(lignes[0].lien, "/soignant/missions/m1")
        XCTAssertEqual(lignes[0].lueLe, "2026-11-01T22:05:00+00:00")
        XCTAssertEqual(lignes[1].lue, false, "lue null : non lue, comme `!n.lue` du web")
        XCTAssertNil(lignes[1].lien)
        XCTAssertEqual(lignes[2].lue, false)
        XCTAssertNil(lignes[2].creeLe)
        XCTAssertThrowsError(try JSONDecoder().decode([NotificationJolene].self, from: Data(#"[{"id":"n4","type":"SYSTEM"}]"#.utf8)),
                             "titre et corps sont NOT NULL : une ligne sans eux est une rupture de contrat")
    }

    // MARK: - Chargement

    func testChargementPuisListeVideSansFauxSucces() async throws {
        let port = PortScripte([.success([ligne("n1"), ligne("n2", lue: true)]), .success([])])
        let (controller, snapshot) = try await pret(port)
        let model = CentreNotificationsModel(controller: controller, snapshot: snapshot)
        XCTAssertEqual(model.etat, .chargement)
        await model.charger()
        XCTAssertEqual(model.notifications.map(\.id), ["n1", "n2"])
        XCTAssertEqual(model.horloge.now(), DemoWorld.fixedNow, "horloge des gateways de la session")
        await model.charger()
        XCTAssertEqual(model.etat, .charge([]), "RLS vide : liste vide (état « Tout est lu ! »), jamais d'erreur")
    }

    func testErreurPuisReessayer() async throws {
        let port = PortScripte([.failure(JoleneError(.network, "Connexion impossible.")), .success([ligne("n1")])])
        let (controller, snapshot) = try await pret(port)
        let model = CentreNotificationsModel(controller: controller, snapshot: snapshot)
        await model.charger()
        XCTAssertEqual(model.etat, .echec, "le texte affiché est celui du web, pas le détail de l'erreur")
        await model.charger()
        XCTAssertEqual(model.notifications.map(\.id), ["n1"])
    }

    func testRelectureSilencieuseGardeLaListeEnCasDEchec() async throws {
        let port = PortScripte([.success([ligne("n1")]), .failure(JoleneError(.network, "Connexion impossible.")),
                                .success([ligne("n0"), ligne("n1")])])
        let (controller, snapshot) = try await pret(port)
        let model = CentreNotificationsModel(controller: controller, snapshot: snapshot)
        await model.charger()
        await model.charger(silencieux: true)
        XCTAssertEqual(model.notifications.map(\.id), ["n1"], "notification au premier plan : la liste reste en place")
        await model.charger(silencieux: true)
        XCTAssertEqual(model.notifications.map(\.id), ["n0", "n1"])
    }

    func testEpochPerimeAbandonne() async throws {
        let barriere = Gate()
        let port = PortScripte([.success([ligne("n1")])])
        await port.regler(barriere: barriere)
        let (controller, snapshot) = try await pret(port)
        let model = CentreNotificationsModel(controller: controller, snapshot: snapshot)
        let tache = Task { await model.charger() }
        await waitUntil { await port.appelsListe == 1 }
        _ = await controller.signOut()
        await barriere.open()
        await tache.value
        XCTAssertEqual(model.etat, .chargement, "réponse d'une identité partie : jamais publiée")
        await model.charger()
        XCTAssertEqual(model.etat, .chargement, "plus d'epoch valide : aucune lecture")
        let appels = await port.appelsListe
        XCTAssertEqual(appels, 1)
    }

    // MARK: - Ouvrir

    func testNonLueMarqueeRelueAvantDeNaviguer() async throws {
        let port = PortScripte([.success([ligne("n1", lien: "/soignant/missions/m-1"), ligne("n2", lue: true)])])
        let (controller, snapshot) = try await pret(port)
        let model = CentreNotificationsModel(controller: controller, snapshot: snapshot)
        await model.charger()
        let relue = NotificationJolene(id: "n1", type: "SYSTEM", titre: "Titre n1", corps: "Corps n1",
                                       lien: "/soignant/missions/m-1", lue: true, lueLe: "2026-11-02T00:00:00.000Z")
        await port.regler(marquage: .success(relue))
        let cible = await model.ouvrir(model.notifications[0], renvoiWebDisponible: false)
        XCTAssertEqual(cible, .mission(id: "m-1"))
        let marquees = await port.marquees
        XCTAssertEqual(marquees, ["n1"])
        XCTAssertEqual(model.notifications[0], relue, "la ligne affichée est la ligne relue")
        XCTAssertNil(model.messageAction)
        XCTAssertNil(model.ouvertureEnCours)
    }

    func testDejaLueAucunMarquage() async throws {
        let port = PortScripte([.success([ligne("n1", lien: "/soignant/recherche-missions", lue: true)])])
        let (controller, snapshot) = try await pret(port)
        let model = CentreNotificationsModel(controller: controller, snapshot: snapshot)
        await model.charger()
        let cible = await model.ouvrir(model.notifications[0], renvoiWebDisponible: false)
        XCTAssertEqual(cible, .onglet(.explorer))
        let marquees = await port.marquees
        XCTAssertEqual(marquees, [], "le web ne relit rien pour une notification déjà lue (l.90)")
    }

    func testEchecDuMarquageNOuvreRien() async throws {
        let port = PortScripte([.success([ligne("n1", lien: "/soignant/missions/m-1")])])
        let (controller, snapshot) = try await pret(port)
        let model = CentreNotificationsModel(controller: controller, snapshot: snapshot)
        await model.charger()
        await port.regler(marquage: .failure(JoleneError(.network, "Connexion impossible.")))
        let cible = await model.ouvrir(model.notifications[0], renvoiWebDisponible: true)
        XCTAssertNil(cible, "web l.92-95 : un échec n'ouvre rien")
        XCTAssertEqual(model.messageAction, "Impossible de marquer cette notification comme lue.")
        XCTAssertEqual(model.numeroMessage, 1)
        XCTAssertFalse(model.notifications[0].lue, "jamais de marquage local supposé")

        // Relue mais toujours non lue (mise à jour sans effet, RLS) : même refus, pas de faux succès.
        await port.regler(marquage: .success(ligne("n1", lien: "/soignant/missions/m-1", lue: false)))
        let encore = await model.ouvrir(model.notifications[0], renvoiWebDisponible: true)
        XCTAssertNil(encore)
        XCTAssertEqual(model.numeroMessage, 2, "une même erreur répétée est réannoncée")
        model.effacerMessage()
        XCTAssertNil(model.messageAction)
    }

    func testLienInvalideSignaleApresMarquage() async throws {
        let port = PortScripte([.success([ligne("n1", lien: "https://evil.example/x"), ligne("n2", lien: "", lue: true)])])
        let (controller, snapshot) = try await pret(port)
        let model = CentreNotificationsModel(controller: controller, snapshot: snapshot)
        await model.charger()
        let cible = await model.ouvrir(model.notifications[0], renvoiWebDisponible: true)
        XCTAssertNil(cible)
        XCTAssertEqual(model.messageAction, "Le lien de cette notification n’est pas valide.")
        let marquees = await port.marquees
        XCTAssertEqual(marquees, ["n1"], "marquée lue d'abord, comme le web")
        model.effacerMessage()
        let vide = await model.ouvrir(model.notifications[1], renvoiWebDisponible: true)
        XCTAssertNil(vide)
        XCTAssertNil(model.messageAction, "lien vide : rien à ouvrir, aucun message (`if (n.lien)`)")
    }

    func testRenvoiWebSeulementAvecLePresentateur() async throws {
        let port = PortScripte([.success([ligne("n1", lien: "/soignant/litiges", lue: true)])])
        let (controller, snapshot) = try await pret(port)
        let model = CentreNotificationsModel(controller: controller, snapshot: snapshot)
        await model.charger()
        let sans = await model.ouvrir(model.notifications[0], renvoiWebDisponible: false)
        XCTAssertNil(sans, "sans présentateur `.safari` (L1-T10), rien n'est ouvert")
        let avec = await model.ouvrir(model.notifications[0], renvoiWebDisponible: true)
        XCTAssertEqual(avec, .web(.safari(URL(string: "https://jolene.app/soignant/litiges")!)))
    }

    // MARK: - Présentation des lignes (jamais un bouton sans effet)

    func testVoirEtLigneActionnable() {
        let mission = ligne("a", lien: "/soignant/missions/m-1", lue: true)
        let web = ligne("b", lien: "/soignant/litiges", lue: true)
        let invalide = ligne("c", lien: "https://evil.example/x", lue: true)
        let sansLien = ligne("d", lue: true)
        let nonLueSansLien = ligne("e")
        let centre = ligne("f", lien: "/soignant/notifications", lue: true)
        XCTAssertTrue(CentreNotificationsModel.afficheVoir(mission, renvoiWebDisponible: false))
        XCTAssertTrue(CentreNotificationsModel.afficheVoir(centre, renvoiWebDisponible: false))
        XCTAssertFalse(CentreNotificationsModel.afficheVoir(web, renvoiWebDisponible: false))
        XCTAssertTrue(CentreNotificationsModel.afficheVoir(web, renvoiWebDisponible: true))
        XCTAssertFalse(CentreNotificationsModel.afficheVoir(invalide, renvoiWebDisponible: true), "web : « Voir » seulement si normalisable")
        XCTAssertFalse(CentreNotificationsModel.afficheVoir(sansLien, renvoiWebDisponible: true))

        XCTAssertTrue(CentreNotificationsModel.estActionnable(mission, renvoiWebDisponible: false))
        XCTAssertFalse(CentreNotificationsModel.estActionnable(web, renvoiWebDisponible: false), "lue, renvoi web impossible : rien à faire")
        XCTAssertTrue(CentreNotificationsModel.estActionnable(web, renvoiWebDisponible: true))
        XCTAssertTrue(CentreNotificationsModel.estActionnable(invalide, renvoiWebDisponible: false), "le web signale un lien invalide")
        XCTAssertFalse(CentreNotificationsModel.estActionnable(sansLien, renvoiWebDisponible: true))
        XCTAssertTrue(CentreNotificationsModel.estActionnable(nonLueSansLien, renvoiWebDisponible: false), "à marquer lue")
    }

    // MARK: - Cible d'une destination

    func testCibleDesDestinations() throws {
        func cible(_ lien: String) throws -> CibleNotification {
            CibleNotification(try XCTUnwrap(DestinationLien(link: lien), lien))
        }
        XCTAssertEqual(try cible("/soignant/tableau-de-bord"), .onglet(.accueil))
        XCTAssertEqual(try cible("/soignant/recherche-missions"), .onglet(.explorer))
        XCTAssertEqual(try cible("/soignant/missions?tab=passees"), .onglet(.missions))
        XCTAssertEqual(try cible("/soignant/mes-gains"), .onglet(.revenus))
        XCTAssertEqual(try cible("/soignant/mon-compte"), .onglet(.profil))
        XCTAssertEqual(try cible("/soignant/missions/m%201"), .mission(id: "m 1"))
        XCTAssertEqual(try cible("/soignant/notifications"), .centre)
        // Destination effective, jamais la route brute : factures et paiements restent des renvois web (D4, T13).
        XCTAssertEqual(try cible("/soignant/mes-gains?tab=factures"),
                       .web(.safari(URL(string: "https://jolene.app/soignant/mes-gains?tab=factures")!)))
        XCTAssertEqual(try cible("/soignant/mes-gains?tab=paiements"),
                       .web(.safari(URL(string: "https://jolene.app/soignant/mes-gains?tab=paiements")!)))
        XCTAssertEqual(try cible("/etablissement/missions/abc"),
                       .web(.etablissement(URL(string: "https://jolene.app/etablissement/missions/abc")!)))
        XCTAssertEqual(try cible("/connexion"), .aucune, "connexion depuis un espace prêt : coordinateur de L1-T10")
        XCTAssertEqual(try cible("/reset-password?token_hash=h&type=recovery"), .aucune)

        XCTAssertTrue(CibleNotification.onglet(.accueil).estPresentable(renvoiWebDisponible: false))
        XCTAssertTrue(CibleNotification.mission(id: "m").estPresentable(renvoiWebDisponible: false))
        XCTAssertTrue(CibleNotification.centre.estPresentable(renvoiWebDisponible: false))
        XCTAssertFalse(CibleNotification.web(.safari(URL(string: "https://jolene.app/")!)).estPresentable(renvoiWebDisponible: false))
        XCTAssertTrue(CibleNotification.web(.safari(URL(string: "https://jolene.app/")!)).estPresentable(renvoiWebDisponible: true))
        XCTAssertFalse(CibleNotification.aucune.estPresentable(renvoiWebDisponible: true))
    }
}
