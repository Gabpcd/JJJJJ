import XCTest
@testable import JoleneCore

/// Utilisateur restauré par les ports d'auth de ces tests (hors du main actor : lu par les ports).
private let utilisateurCentre = AuthenticatedUser(id: "u-centre", email: "u-centre@example.invalid",
                                                  emailConfirmedAt: Date(timeIntervalSince1970: 1_700_000_000),
                                                  appMetadataRole: "SOIGNANT")

/// Centre de notifications (lot 3, T5 ; `PageNotifications.tsx` l.46-103) : liste relue pour l'epoch, état vide
/// sans faux succès, erreur au texte web et « Réessayer », relecture silencieuse qui garde la liste, échec d'un
/// tirer-pour-rafraîchir signalé, marquage lu **relu** avant toute navigation (un échec n'ouvre rien et impose une
/// relecture, une annulation n'est pas une erreur), lien invalide signalé, cible présentable seulement (jamais un
/// bouton sans effet), garde « tout écran natif livré a sa cible », textes verbatim.
@MainActor
final class CentreNotificationsTests: XCTestCase {
    /// Port scripté : réponses de `liste` dans l'ordre, marquage relu ou en échec, journal des appels.
    private actor PortScripte: NotificationsCenterPort {
        var listes: [Result<[NotificationJolene], JoleneError>]
        var marquage: Result<NotificationJolene?, JoleneError> = .success(nil)
        private(set) var appelsListe = 0
        private(set) var marquees: [String] = []
        private var barriere: Gate?
        private var barriereMarquage: Gate?

        init(_ listes: [Result<[NotificationJolene], JoleneError>]) { self.listes = listes }

        func liste(context: MissionReadContext) async throws -> [NotificationJolene] {
            appelsListe += 1
            if let barriere { await barriere.wait() }
            return try (listes.isEmpty ? .success([]) : listes.removeFirst()).get()
        }

        func marquerLue(id: String, context: MissionReadContext) async throws -> NotificationJolene {
            marquees.append(id)
            if let barriereMarquage { await barriereMarquage.wait() }
            switch marquage {
            case .success(let ligne?): return ligne
            case .success(nil): return NotificationJolene(id: id, type: "SYSTEM", titre: "t", corps: "c", lue: true)
            case .failure(let erreur): throw erreur
            }
        }

        func regler(marquage: Result<NotificationJolene?, JoleneError>) { self.marquage = marquage }
        func regler(barriere: Gate?) { self.barriere = barriere }
        func regler(barriereMarquage: Gate?) { self.barriereMarquage = barriereMarquage }
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

    /// Indication vocale de « Voir » (`accueil-notifications-action`) : **sans source web** (non juridique), en
    /// attente de relecture par Gabrielle (`DECISIONS_LOT3.md`, section T5) ; épinglée ici pour qu'aucune
    /// reformulation ne passe inaperçue (revue L3-T5, m11).
    func testIndicationVocaleSansSourceWebEpinglee() {
        XCTAssertEqual(CentreNotificationsTextes.indicationOuvrirCentre, "Ouvre le centre de notifications")
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
        XCTAssertNil(model.erreurRafraichissement, "relecture non demandée par l'utilisateur : aucun encart")
        await model.charger(silencieux: true)
        XCTAssertEqual(model.notifications.map(\.id), ["n0", "n1"])
    }

    /// Revue L3-T5, m3 : l'échec d'un tirer-pour-rafraîchir manuel n'est jamais avalé — la liste reste, un encart
    /// porte le texte web `erreurChargement` (comme `accueil-refresh-error`) ; il disparaît au succès suivant.
    func testTirerPourRafraichirSignaleSonEchecSansRetirerLaListe() async throws {
        let port = PortScripte([.success([ligne("n1")]), .failure(JoleneError(.network, "Connexion impossible.")),
                                .success([ligne("n0"), ligne("n1")])])
        let (controller, snapshot) = try await pret(port)
        let model = CentreNotificationsModel(controller: controller, snapshot: snapshot)
        await model.charger()
        XCTAssertNil(model.erreurRafraichissement)
        await model.rafraichir()
        XCTAssertEqual(model.notifications.map(\.id), ["n1"], "la liste affichée reste en place")
        XCTAssertEqual(model.erreurRafraichissement, "Impossible de charger vos notifications.")
        await model.rafraichir()
        XCTAssertNil(model.erreurRafraichissement, "succès : l'encart disparaît")
        XCTAssertEqual(model.notifications.map(\.id), ["n0", "n1"])
    }

    /// Sans liste affichée (premier chargement en échec), tirer pour rafraîchir rend l'erreur plein écran et son
    /// « Réessayer », jamais un encart en plus.
    func testTirerPourRafraichirSansListeRendLErreurPleinEcran() async throws {
        let port = PortScripte([.failure(JoleneError(.network, "Connexion impossible.")),
                                .failure(JoleneError(.network, "Connexion impossible.")), .success([ligne("n1")])])
        let (controller, snapshot) = try await pret(port)
        let model = CentreNotificationsModel(controller: controller, snapshot: snapshot)
        await model.charger()
        await model.rafraichir()
        XCTAssertEqual(model.etat, .echec)
        XCTAssertNil(model.erreurRafraichissement)
        await model.rafraichir()
        XCTAssertEqual(model.notifications.map(\.id), ["n1"])
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
        XCTAssertEqual(model.lectures, 1, "une lecture relue périme le compteur de l'Accueil (revue L3-T5, m1)")
    }

    func testDejaLueAucunMarquage() async throws {
        let port = PortScripte([.success([ligne("n1", lien: "/soignant/recherche-missions", lue: true)])])
        let (controller, snapshot) = try await pret(port)
        let model = CentreNotificationsModel(controller: controller, snapshot: snapshot)
        await model.charger()
        let cible = await model.ouvrir(model.notifications[0], renvoiWebDisponible: false)
        XCTAssertEqual(cible, .explorer)
        let marquees = await port.marquees
        XCTAssertEqual(marquees, [], "le web ne relit rien pour une notification déjà lue (l.90)")
        XCTAssertEqual(model.lectures, 0, "rien n'a changé côté serveur : l'Accueil n'est pas périmé")
    }

    func testEchecDuMarquageNOuvreRien() async throws {
        // Chaque échec relit la liste (réconciliation, revue L3-T5 m2) : le script fournit ces deux relectures, où la
        // ligne est toujours non lue côté serveur.
        let nonLue = ligne("n1", lien: "/soignant/missions/m-1")
        let port = PortScripte([.success([nonLue]), .success([nonLue]), .success([nonLue])])
        let (controller, snapshot) = try await pret(port)
        let model = CentreNotificationsModel(controller: controller, snapshot: snapshot)
        await model.charger()
        await port.regler(marquage: .failure(JoleneError(.network, "Connexion impossible.")))
        let cible = await model.ouvrir(model.notifications[0], renvoiWebDisponible: true)
        XCTAssertNil(cible, "web l.92-95 : un échec n'ouvre rien")
        XCTAssertEqual(model.messageAction, "Impossible de marquer cette notification comme lue.")
        XCTAssertEqual(model.numeroMessage, 1)
        XCTAssertFalse(model.notifications[0].lue, "jamais de marquage local supposé")
        XCTAssertEqual(model.lectures, 0)

        // Relue mais toujours non lue (mise à jour sans effet, RLS) : même refus, pas de faux succès.
        await port.regler(marquage: .success(ligne("n1", lien: "/soignant/missions/m-1", lue: false)))
        let encore = await model.ouvrir(model.notifications[0], renvoiWebDisponible: true)
        XCTAssertNil(encore)
        XCTAssertEqual(model.numeroMessage, 2, "une même erreur répétée est réannoncée")
        XCTAssertEqual(model.lectures, 0)
        let appels = await port.appelsListe
        XCTAssertEqual(appels, 3, "chargement initial puis une relecture après chaque échec")
        model.effacerMessage()
        XCTAssertNil(model.messageAction)
    }

    /// Revue L3-T5, m2 (PRINCIPES §5 : « un délai dépassé sur une mutation impose une relecture ») : après un PATCH
    /// en délai dépassé, la liste est relue sans être retirée ; l'état réel est affiché, le message reste, rien
    /// n'est ouvert (le tap n'a pas abouti du point de vue de l'utilisateur).
    func testDelaiDepasseDuMarquageImposeUneRelecture() async throws {
        let port = PortScripte([.success([ligne("n1", lien: "/soignant/missions/m-1"), ligne("n2", lue: true)]),
                                .success([ligne("n1", lien: "/soignant/missions/m-1", lue: true), ligne("n2", lue: true)])])
        let (controller, snapshot) = try await pret(port)
        let model = CentreNotificationsModel(controller: controller, snapshot: snapshot)
        await model.charger()
        await port.regler(marquage: .failure(JoleneError(.network, SessionController.timeoutMessage)))
        let cible = await model.ouvrir(model.notifications[0], renvoiWebDisponible: false)
        XCTAssertNil(cible)
        XCTAssertEqual(model.messageAction, "Impossible de marquer cette notification comme lue.", "le message reste")
        let appels = await port.appelsListe
        XCTAssertEqual(appels, 2, "relecture après le délai dépassé")
        XCTAssertEqual(model.notifications.map(\.id), ["n1", "n2"])
        XCTAssertTrue(model.notifications[0].lue, "le serveur avait agi : l'état relu est affiché")
        XCTAssertNil(model.erreurRafraichissement, "relecture de réconciliation : jamais d'encart en plus")
        XCTAssertNil(model.ouvertureEnCours)
    }

    /// Revue L3-T5, m4 : centre quitté pendant le marquage (tâche du bouton annulée à la disparition) : rien n'est
    /// ouvert, aucune erreur n'est affichée (une annulation n'est jamais un échec), aucune relecture.
    func testOuvertureAnnuleeNOuvreRienNiNAfficheDErreur() async throws {
        let port = PortScripte([.success([ligne("n1", lien: "/soignant/missions/m-1")])])
        let barriere = Gate()
        await port.regler(barriereMarquage: barriere)
        let (controller, snapshot) = try await pret(port)
        let model = CentreNotificationsModel(controller: controller, snapshot: snapshot)
        await model.charger()
        let notification = model.notifications[0]
        let tache = Task { await model.ouvrir(notification, renvoiWebDisponible: false) }
        await waitUntil { await port.marquees.count == 1 }
        tache.cancel()
        let cible = await tache.value
        await barriere.open()
        XCTAssertNil(cible, "réponse tardive : jamais de navigation après le départ de l'utilisateur")
        XCTAssertNil(model.messageAction, "une annulation n'est jamais une erreur")
        XCTAssertEqual(model.numeroMessage, 0)
        XCTAssertNil(model.ouvertureEnCours)
        let appels = await port.appelsListe
        XCTAssertEqual(appels, 1, "aucune relecture pour un écran quitté")
    }

    /// Revue L3-T5, m5 : depuis le centre, une non lue qui vise le centre est marquée lue (relue) puis n'ouvre rien
    /// (l'utilisateur y est déjà), sans message.
    func testNonLueVersLeCentreMarqueeSansNavigation() async throws {
        let port = PortScripte([.success([ligne("n1", lien: "/soignant/notifications")])])
        let (controller, snapshot) = try await pret(port)
        let model = CentreNotificationsModel(controller: controller, snapshot: snapshot)
        await model.charger()
        let cible = await model.ouvrir(model.notifications[0], renvoiWebDisponible: true)
        XCTAssertNil(cible, "déjà dans le centre : rien à présenter")
        XCTAssertTrue(model.notifications[0].lue)
        XCTAssertNil(model.messageAction)
        XCTAssertEqual(model.lectures, 1)
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

    /// Revue B8 de T3b, m2 : le centre ne contourne pas l'option B (décision 7 du lot 1). Une ligne dont le lien est un
    /// lien de réinitialisation `?code=` n'ouvre jamais la page web avec le code : lue, elle n'est ni « Voir » ni un
    /// bouton ; non lue, elle est marquée lue (relue) puis n'ouvre rien, sans message (le lien est Jolene et valide).
    func testLienDeReinitialisationPkceJamaisServiParLeCentre() async throws {
        let lue = ligne("r1", lien: "/reset-password?code=c", lue: true)
        XCTAssertFalse(CentreNotificationsModel.afficheVoir(lue, renvoiWebDisponible: true))
        XCTAssertFalse(CentreNotificationsModel.estActionnable(lue, renvoiWebDisponible: true))
        let tokenHash = ligne("r2", lien: "/reset-password?token_hash=h&type=recovery", lue: true)
        XCTAssertTrue(CentreNotificationsModel.afficheVoir(tokenHash, renvoiWebDisponible: true),
                      "`token_hash` : la page web canonique sait le vérifier")

        let port = PortScripte([.success([ligne("r3", lien: "/reset-password?code=c")])])
        let (controller, snapshot) = try await pret(port)
        let model = CentreNotificationsModel(controller: controller, snapshot: snapshot)
        await model.charger()
        let cible = await model.ouvrir(model.notifications[0], renvoiWebDisponible: true)
        XCTAssertNil(cible, "jamais `.web(.safari(…?code=…))`")
        let marquees = await port.marquees
        XCTAssertEqual(marquees, ["r3"], "la lecture est relue comme pour toute ligne non lue")
        XCTAssertNil(model.messageAction)
    }

    // MARK: - Présentation des lignes (jamais un bouton sans effet)

    func testVoirEtLigneActionnable() {
        let mission = ligne("a", lien: "/soignant/missions/m-1", lue: true)
        let web = ligne("b", lien: "/soignant/litiges", lue: true)
        let invalide = ligne("c", lien: "https://evil.example/x", lue: true)
        let sansLien = ligne("d", lue: true)
        let nonLueSansLien = ligne("e")
        let centre = ligne("f", lien: "/soignant/notifications", lue: true)
        let accueil = ligne("g", lien: "/soignant/tableau-de-bord", lue: true)
        XCTAssertTrue(CentreNotificationsModel.afficheVoir(mission, renvoiWebDisponible: false))
        // Revue L3-T5, m5 (la version précédente de ce test affirmait « Voir » sur une ligne qui vise le centre, alors
        // qu'elle n'ouvrait rien) : depuis le centre, viser le centre n'a pas d'effet ; viser l'Accueil ramène à sa
        // racine.
        XCTAssertFalse(CentreNotificationsModel.afficheVoir(centre, renvoiWebDisponible: true))
        XCTAssertFalse(CentreNotificationsModel.estActionnable(centre, renvoiWebDisponible: true), "déjà lue, déjà dans le centre")
        XCTAssertTrue(CentreNotificationsModel.estActionnable(ligne("h", lien: "/soignant/notifications"), renvoiWebDisponible: false),
                      "non lue : à marquer lue")
        XCTAssertTrue(CentreNotificationsModel.afficheVoir(accueil, renvoiWebDisponible: false))
        XCTAssertTrue(CentreNotificationsModel.estActionnable(accueil, renvoiWebDisponible: false))
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
        XCTAssertEqual(try cible("/soignant/tableau-de-bord"), .accueil)
        XCTAssertEqual(try cible("/soignant/recherche-missions"), .explorer)
        XCTAssertEqual(try cible("/soignant/missions?tab=passees"), .missions)
        // Revue L3-T5, M1 : la section de Revenus est portée par la cible (jamais réduite à l'onglet).
        XCTAssertEqual(try cible("/soignant/mes-gains"), .revenus(section: .apercu))
        XCTAssertEqual(try cible("/soignant/mes-gains?tab=inconnu"), .revenus(section: .apercu))
        XCTAssertEqual(try cible("/soignant/mon-compte"), .monCompte)
        XCTAssertEqual(try cible("/soignant/missions/m%201"), .mission(id: "m 1"))
        XCTAssertEqual(try cible("/soignant/notifications"), .centre)
        // Intégration du lot 3 : préférences de notifications natives (T6), empilées sur l'onglet Profil.
        XCTAssertEqual(try cible("/soignant/parametres/notifications"), .preferences)
        XCTAssertEqual(try cible("https://www.jolene.app/soignant/parametres/notifications/?origine=push#haut"), .preferences)
        // Intégration du lot 3 : édition du profil native (T9), tout `?tab=` et l'alias `reputation` compris.
        XCTAssertEqual(try cible("/soignant/profil"), .profil)
        XCTAssertEqual(try cible("/soignant/profil?tab=principal"), .profil)
        XCTAssertEqual(try cible("/soignant/reputation"), .profil)
        // Point de fusion T3b / T11 (revue L3-T9 m2 ; revue B8 de T3b, m3) : l'onglet confidentialité du web (export RGPD,
        // suppression de compte) reste un renvoi web tant que le hub natif n'a pas l'export (L3-T11, garde de
        // `LinksRouterTests`) ; aucune notification du dump ne vise ce `?tab=`.
        XCTAssertEqual(try cible("/soignant/profil?tab=confidentialite"),
                       .web(.safari(URL(string: "https://jolene.app/soignant/profil?tab=confidentialite")!)))
        // Destination effective, jamais la route brute : factures et paiements restent des renvois web (D4, T13).
        XCTAssertEqual(try cible("/soignant/mes-gains?tab=factures"),
                       .web(.safari(URL(string: "https://jolene.app/soignant/mes-gains?tab=factures")!)))
        XCTAssertEqual(try cible("/soignant/mes-gains?tab=paiements"),
                       .web(.safari(URL(string: "https://jolene.app/soignant/mes-gains?tab=paiements")!)))
        XCTAssertEqual(try cible("/etablissement/missions/abc"),
                       .web(.etablissement(URL(string: "https://jolene.app/etablissement/missions/abc")!)))
        XCTAssertEqual(try cible("/connexion"), .aucune, "connexion depuis un espace prêt : coordinateur de L1-T10")
        // L3-T3b : écran de réinitialisation natif non livré, la page web canonique (`token_hash` conservé) est servie.
        XCTAssertEqual(try cible("/reset-password?token_hash=h&type=recovery"),
                       .web(.safari(URL(string: "https://jolene.app/reset-password?token_hash=h&type=recovery")!)))
        // Revue B8 de T3b, m2 : option B (décision 7 du lot 1) — un lien `?code=` n'est jamais servi par Safari, depuis le
        // centre comme depuis un lien universel ou un tap (`DeepLinkIntent.reinitialisationRefusee`).
        XCTAssertEqual(try cible("/reset-password?code=c"), .aucune)
        XCTAssertEqual(try cible("https://www.jolene.app/reset-password/?code=c&type=recovery#x"), .aucune)

        let racine = URL(string: "https://jolene.app/")!
        for cible in [CibleNotification.accueil, .explorer, .missions, .revenus(section: .apercu), .monCompte, .mission(id: "m"), .centre,
                      .preferences, .profil] {
            XCTAssertTrue(cible.estPresentable(renvoiWebDisponible: false), "\(cible)")
        }
        XCTAssertFalse(CibleNotification.web(.safari(racine)).estPresentable(renvoiWebDisponible: false))
        XCTAssertTrue(CibleNotification.web(.safari(racine)).estPresentable(renvoiWebDisponible: true))
        XCTAssertFalse(CibleNotification.aucune.estPresentable(renvoiWebDisponible: true))
        // Revue L3-T5, m5 : le centre n'est pas présentable depuis le centre (aucun effet visible).
        XCTAssertFalse(CibleNotification.centre.estPresentable(renvoiWebDisponible: true, depuisCentre: true))
        XCTAssertTrue(CibleNotification.accueil.estPresentable(renvoiWebDisponible: false, depuisCentre: true))
        XCTAssertTrue(CibleNotification.mission(id: "m").estPresentable(renvoiWebDisponible: false, depuisCentre: true))
        XCTAssertTrue(CibleNotification.preferences.estPresentable(renvoiWebDisponible: false, depuisCentre: true))
        XCTAssertTrue(CibleNotification.profil.estPresentable(renvoiWebDisponible: false, depuisCentre: true))
        // Une section de Revenus autre que l'aperçu n'a pas de présentation dans l'espace avant sa tranche (T13) :
        // elle n'est jamais réduite en silence à l'onglet (verrou, garde ci-dessous).
        for section in SectionRevenus.allCases where section != .apercu {
            XCTAssertFalse(CibleNotification.revenus(section: section).estPresentable(renvoiWebDisponible: true), "\(section)")
        }
    }

    /// Revue L3-T5, m9 : onglets de l'espace dans un enum dédié de JoleneCore (les drapeaux `EcranNatif` sont étendus
    /// par le lot 2 à des écrans qui ne sont pas des onglets) ; onglet porteur de chaque cible présentable.
    func testOngletsDeLEspaceEtOngletDeChaqueCible() {
        XCTAssertEqual(OngletEspace.allCases, [.accueil, .explorer, .missions, .revenus, .profil],
                       "cinq onglets de `BarreNavigation.tsx` l.33-37, dans l'ordre")
        let cas: [(CibleNotification, OngletEspace?)] = [
            (.accueil, .accueil), (.mission(id: "m"), .accueil), (.centre, .accueil), (.explorer, .explorer),
            (.missions, .missions), (.revenus(section: .apercu), .revenus), (.revenus(section: .paiementsAConfirmer), .revenus),
            (.monCompte, .profil), (.preferences, .profil), (.profil, .profil), (.web(.safari(URL(string: "https://jolene.app/")!)), nil), (.aucune, nil),
        ]
        for (cible, onglet) in cas {
            XCTAssertEqual(cible.onglet, onglet, "\(cible)")
        }
    }

    // MARK: - Garde : tout écran natif livré a sa cible dans l'espace (revue L3-T5, M1)

    /// Genre d'une route sans ses valeurs associées. Switch exhaustif sans `default` : une route, une section, une
    /// page d'inscription ou un retour Stripe ajouté sans être rangé ici ne compile pas.
    private enum GenreRoute: String, CaseIterable {
        case connexion, resetPassword, confirmerInscription
        case inscriptionSoignant, inscriptionReprendre, inscriptionCompleter
        case accueil, explorer, missions, missionDetail, serieDetail
        case revenusApercu, revenusFactures, revenusBulletins, revenusAvances, revenusPaiements
        case monCompte, profil, notifications, parametresNotifications
        case stripeConnect, stripeConnectSucces, stripeConnectRafraichir
        case safari, etablissement

        init(_ route: JoleneRoute) {
            switch route {
            case .connexion: self = .connexion
            case .resetPassword: self = .resetPassword
            case .confirmerInscription: self = .confirmerInscription
            case .inscription(let etape):
                switch etape.page {
                case .soignant: self = .inscriptionSoignant
                case .reprendre: self = .inscriptionReprendre
                case .completer: self = .inscriptionCompleter
                }
            case .accueil: self = .accueil
            case .explorer: self = .explorer
            case .missions: self = .missions
            case .missionDetail: self = .missionDetail
            case .serieDetail: self = .serieDetail
            case .revenus(let section):
                switch section {
                case .apercu: self = .revenusApercu
                case .factures: self = .revenusFactures
                case .bulletins: self = .revenusBulletins
                case .avances: self = .revenusAvances
                case .paiementsAConfirmer: self = .revenusPaiements
                }
            case .monCompte: self = .monCompte
            case .profil: self = .profil
            case .notifications: self = .notifications
            case .parametresNotifications: self = .parametresNotifications
            case .stripeConnect(let retour):
                switch retour {
                case nil: self = .stripeConnect
                case .succes?: self = .stripeConnectSucces
                case .rafraichir?: self = .stripeConnectRafraichir
                }
            case .safari: self = .safari
            case .etablissement: self = .etablissement
            }
        }
    }

    /// Un lien par genre de route : les routes de `DestinationLienTests.testTableDesEcransLivres`, plus un renvoi
    /// web et l'espace établissement. La couverture de tous les genres est exigée par la garde.
    private static let liensParGenre = [
        "/connexion", "/reset-password?token_hash=h&type=recovery", "/inscription/confirmer?token_hash=h&type=signup",
        "/inscription/soignant?profession=IDE", "/inscription/reprendre", "/inscription/completer?ref=ABCD-12",
        "/soignant/tableau-de-bord", "/soignant/recherche-missions", "/soignant/missions?tab=passees",
        "/soignant/missions/m-1", "/soignant/missions/serie/s-1",
        "/soignant/mes-gains", "/soignant/mes-gains?tab=factures", "/soignant/mes-gains?tab=bulletins",
        "/soignant/mes-gains?tab=avances", "/soignant/mes-gains?tab=paiements",
        "/soignant/mon-compte", "/soignant/profil", "/soignant/notifications", "/soignant/parametres/notifications",
        "/soignant/stripe-connect", "/soignant/stripe-connect?success=true", "/soignant/stripe-connect?refresh=true",
        "/soignant/litiges", "/etablissement/missions/abc",
    ]

    /// Liste d'exclusion nommée et fermée : routes natives **sans présentation depuis un espace prêt par nature**
    /// (connexion, consommée hors de l'espace par le coordinateur de liens, `DeepLinkIntent.horsEspace`). Une tranche
    /// n'y ajoute une route qu'avec sa justification dans `DECISIONS_LOT3.md` (reset natif à venir). L3-T3b en retire
    /// le reset : sans écran natif, sa ligne de `ecranNatifLivre` vaut `false` et son lien est un renvoi web
    /// canonique. T7 (intégration du lot 3) : confirmation (`/inscription/confirmer`) et pages `/inscription/soignant`
    /// et `/inscription/reprendre`, présentées hors de l'espace par le coordinateur des liens (`AiguillageLiens`,
    /// action `.inscription`, `BoiteLiensInscription` lue par `RootView`) — un compte ouvert n'a pas d'inscription à
    /// faire.
    private static let sansCibleDansLEspace: Set<GenreRoute> = [.connexion, .confirmerInscription,
                                                                .inscriptionSoignant, .inscriptionReprendre]

    /// Garde « un gap connu reste verrouillé » (`CLAUDE.md`) : toute route dont l'écran natif est livré
    /// (`DestinationLien.ecranNatifLivre == true`), parmi la table des routes et toute la famille push des vecteurs
    /// golden (`navigationPathForEvent`), a une **cible native présentable** dans l'espace — ni `.aucune` (le tap
    /// n'ouvrirait rien), ni `.web` (renvoi web d'un écran pourtant livré). Elle rougit dès qu'une tranche (T6, T7, T8,
    /// T9, T13, T14a) passe sa ligne de `ecranNatifLivre` à `true` sans ajouter sa cible à `CibleNotification.init`,
    /// sa présentation (`estPresentable`) et `MainTabView.presenter`. Un écran non livré reste un renvoi web canonique.
    func testToutEcranNatifLivreAUneCibleNativePresentable() throws {
        let golden = try Golden.charger("push-routing").filter { $0.fonction == "navigationPathForEvent" }
            .compactMap { $0.expected.string }
        XCTAssertFalse(golden.isEmpty, "vecteurs golden du routage push chargés")
        var genresCouverts = Set<GenreRoute>()
        var natifs = 0
        for chemin in Self.liensParGenre + golden {
            let lien = try XCTUnwrap(DestinationLien(link: chemin), chemin)
            let genre = GenreRoute(lien.route)
            genresCouverts.insert(genre)
            let cible = CibleNotification(lien)
            if Self.sansCibleDansLEspace.contains(genre) {
                XCTAssertEqual(cible, .aucune, "\(chemin) : exclusion nommée, rien n'est présenté depuis l'espace")
                continue
            }
            guard lien.route.isNative, DestinationLien.ecranNatifLivre(lien.route) else {
                XCTAssertEqual(cible, .web(lien.destination), "\(chemin) : écran non livré, renvoi web canonique")
                XCTAssertEqual(lien.destination.externalURL, lien.canonique, chemin)
                continue
            }
            natifs += 1
            switch cible {
            case .aucune, .web:
                XCTFail("\(chemin) : écran natif livré (`ecranNatifLivre`) sans cible native dans l'espace (\(cible)) — "
                        + "ajouter la cible à `CibleNotification.init` et sa présentation à `MainTabView.presenter`")
            default:
                XCTAssertTrue(cible.estPresentable(renvoiWebDisponible: false),
                              "\(chemin) : cible \(cible) non présentable dans l'espace (verrou de sa tranche)")
                XCTAssertNotNil(cible.onglet, "\(chemin) : onglet porteur de \(cible)")
            }
        }
        XCTAssertEqual(genresCouverts, Set(GenreRoute.allCases), "un lien par genre de route : table complète")
        XCTAssertGreaterThan(natifs, 0)
    }
}
