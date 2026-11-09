import XCTest
@testable import JoleneCore

/// Lot 3, T3a : destination effective d'un lien (`DestinationLien`). Une route dont l'écran natif
/// n'est pas encore livré est renvoyée vers Safari avec son URL canonique (query et fragment
/// conservés) ; chaque tranche d'écran change une ligne de `DestinationLien.ecranNatifLivre` et
/// ajuste ici les lignes correspondantes (table des écrans, famille du vecteur push).
///
/// Le nom `DeepLinkIntent` (et `DeepLinkIntentTests`) reste à L1-T10 : intention mémorisée avant
/// `.ready`, epoch (`DECISIONS_LOT3.md`, « T3 livrée en deux temps »).
final class DestinationLienTests: XCTestCase {
    private func lien(_ s: String) -> DestinationLien? {
        DestinationLien(url: URL(string: s)!)
    }

    private func url(_ s: String) -> URL { URL(string: s)! }

    // MARK: Écrans du lot 3 pas encore livrés

    func testRoutesLot3SansEcranRenvoyeesVersSafariCanonique() throws {
        let cas: [(lien: String, route: JoleneRoute, canonique: String)] = [
            ("https://jolene.app/soignant/stripe-connect?success=true", .stripeConnect(retour: .succes),
             "https://jolene.app/soignant/stripe-connect?success=true"),                                            // T14a
            ("https://jolene.app/soignant/stripe-connect?refresh=true", .stripeConnect(retour: .rafraichir),
             "https://jolene.app/soignant/stripe-connect?refresh=true"),                                            // T14a
            ("https://jolene.app/soignant/mes-gains?tab=paiements", .revenus(section: .paiementsAConfirmer),
             "https://jolene.app/soignant/mes-gains?tab=paiements"),                                                // T13
        ]
        for c in cas {
            let d = try XCTUnwrap(lien(c.lien), c.lien)
            XCTAssertEqual(d.route, c.route, c.lien)
            XCTAssertTrue(d.route.isNative, "\(c.lien) : la route reste native dans la table")
            XCTAssertFalse(DestinationLien.ecranNatifLivre(d.route), c.lien)
            XCTAssertEqual(d.destination, .safari(url(c.canonique)), c.lien)
            XCTAssertEqual(d.canonique, url(c.canonique), c.lien)
        }
    }

    /// Factures, bulletins et avances : renvoi web assumé jusqu'au lot 4 (`PARITE_SOIGNANT.md`,
    /// D4), alias compris ; l'URL canonique est celle du lien reçu (le web applique sa redirection).
    func testFacturesBulletinsAvancesToujoursEnRenvoiWeb() throws {
        let cas: [(String, SectionRevenus)] = [
            ("/soignant/mes-gains?tab=factures", .factures),
            ("/soignant/mes-gains?tab=bulletins&annee=2026", .bulletins),
            ("/soignant/mes-gains?tab=avances", .avances),
            ("/soignant/mes-factures-honoraires", .factures),
            ("/soignant/bulletins-paie", .bulletins),
            ("/soignant/mes-avances#haut", .avances),
        ]
        for (chemin, section) in cas {
            let d = try XCTUnwrap(lien("https://jolene.app" + chemin), chemin)
            XCTAssertEqual(d.route, .revenus(section: section), chemin)
            XCTAssertEqual(d.destination, .safari(url("https://jolene.app" + chemin)), chemin)
        }
    }

    /// Détail de série : renvoi web assumé au lot 1 (décision 11 de `LOT1_PLAN.md`, `PARITE_SOIGNANT.md`
    /// l.48 : « détail de série natif au lot 4 ») ; la route reste `.serieDetail` dans la table.
    func testDetailDeSerieEnRenvoiWebJusquAuLot4() throws {
        let d = try XCTUnwrap(lien("https://jolene.app/soignant/missions/serie/s%201?x=1"))
        XCTAssertEqual(d.route, .serieDetail(id: "s 1"))
        XCTAssertFalse(DestinationLien.ecranNatifLivre(d.route))
        XCTAssertEqual(d.destination, .safari(url("https://jolene.app/soignant/missions/serie/s%201?x=1")))
    }

    // MARK: Écrans du lot 3 livrés (la tranche passe sa ligne de `ecranNatifLivre` à `true`)

    /// Chaque tranche d'écran du lot 3 déplace ici son cas de `testRoutesLot3SansEcranRenvoyeesVersSafariCanonique` :
    /// la route est sa propre destination (écran natif), le lien canonique n'est plus servi par Safari.
    func testRoutesLot3AvecEcranLivreSontNatives() throws {
        let cas: [(lien: String, route: JoleneRoute)] = [
            ("https://jolene.app/soignant/parametres/notifications", .parametresNotifications),                     // T6
            ("https://www.jolene.app/soignant/parametres/notifications/?origine=push#haut", .parametresNotifications), // T6
            ("https://jolene.app/inscription/soignant?profession=IDE&ville=Lyon",
             .inscription(EtapeInscription(page: .soignant, query: "profession=IDE&ville=Lyon"))),                 // T7
            ("https://jolene.app/inscription/reprendre", .inscription(EtapeInscription(page: .reprendre, query: nil))), // T7
            // T8 : `CompletionProfilScreen` dans l'aiguillage d'onboarding (hors espace, `BoiteLiensInscription`).
            ("https://jolene.app/inscription/completer?ref=ABCD-12#x",
             .inscription(EtapeInscription(page: .completer, query: "ref=ABCD-12"))),                               // T8
            // T7 (intégration du lot 3) : `ConfirmationInscriptionScreen`, présenté hors de l'espace par le coordinateur.
            ("https://jolene.app/inscription/confirmer?token_hash=h&type=signup",
             .confirmerInscription(credentials: .tokenHash(tokenHash: "h", otpType: "signup"))),                    // T7
            ("https://jolene.app/inscription/confirmer?code=c", .confirmerInscription(credentials: .pkce(code: "c"))), // T7 (D10)
            ("https://jolene.app/inscription/confirmer#access_token=a&refresh_token=r&type=signup",
             .confirmerInscription(credentials: .implicit(accessToken: "a", refreshToken: "r"))),                  // T7
        ]
        for c in cas {
            let d = try XCTUnwrap(lien(c.lien), c.lien)
            XCTAssertEqual(d.route, c.route, c.lien)
            XCTAssertTrue(DestinationLien.ecranNatifLivre(d.route), c.lien)
            XCTAssertEqual(d.destination, c.route, c.lien)
            XCTAssertTrue(d.destination.isNative, c.lien)
            XCTAssertNil(d.destination.externalURL, c.lien)
        }
        let interne = try XCTUnwrap(DestinationLien(link: "/soignant/parametres/notifications"))
        XCTAssertEqual(interne.destination, .parametresNotifications, "lien interne (centre de notifications, T5)")
    }

    // MARK: Liens de rappel d'authentification sans écran natif (lot 3, T3b)

    /// Reliquat L1-T10 (T3b, `DECISIONS_LOT3.md`) : le coordinateur de liens est livré, pas l'écran de
    /// réinitialisation. Son lien part vers sa page web canonique, query et fragment conservés (la page web vérifie
    /// `token_hash` et le format implicit), au lieu d'une route native sans écran qui n'ouvrirait rien. Le refus de
    /// `?code=` sur `/reset-password` (option B, décision 7 du lot 1) ne dépend pas de cette ligne : `DeepLinkIntent`
    /// le lit sur la route (`DeepLinkIntentTests`). La confirmation d'inscription en est sortie à l'intégration de T7
    /// (`ConfirmationInscriptionScreen`, `testRoutesLot3AvecEcranLivreSontNatives`).
    func testLiensDeRappelSansEcranNatifRenvoyesVersSafariCanonique() throws {
        let cas: [(String, JoleneRoute)] = [
            ("/reset-password?token_hash=h&type=recovery", .resetPassword(credentials: .tokenHash(tokenHash: "h", otpType: "recovery"))),
            ("/reset-password#access_token=a&refresh_token=r&type=recovery",
             .resetPassword(credentials: .implicit(accessToken: "a", refreshToken: "r"))),
            ("/reset-password", .resetPassword(credentials: nil)),
        ]
        for (chemin, route) in cas {
            let d = try XCTUnwrap(lien("https://jolene.app" + chemin), chemin)
            XCTAssertEqual(d.route, route, chemin)
            XCTAssertTrue(d.route.isNative, "\(chemin) : la route reste native dans la table")
            XCTAssertFalse(DestinationLien.ecranNatifLivre(route), chemin)
            XCTAssertEqual(d.destination, .safari(url("https://jolene.app" + chemin)), chemin)
        }
    }

    // MARK: Destinations natives existantes inchangées

    func testRoutesDesLots0Et1InchangeesEtNatives() throws {
        let cas: [(String, JoleneRoute)] = [
            ("/connexion", .connexion),
            ("/soignant/tableau-de-bord", .accueil),
            ("/soignant/recherche-missions", .explorer),
            ("/soignant/missions?tab=passees", .missions),
            ("/soignant/missions/m%201", .missionDetail(id: "m 1")),
            ("/mission/m1", .missionDetail(id: "m1")),
            ("/soignant/mes-gains", .revenus(section: .apercu)),
            ("/soignant/mes-gains?tab=inconnu", .revenus(section: .apercu)),
            ("/soignant/mon-compte", .monCompte),
            ("/soignant/parametres", .monCompte),
            ("/soignant/score", .monCompte),
            ("/soignant/notifications?utm_source=push#haut", .notifications),                    // lot 3, T5
            ("/soignant/profil?tab=principal", .profil),          // lot 3, T9 : édition du profil livrée
            ("/soignant/reputation", .profil),                    // lot 3, T9 : alias du profil
        ]
        for (chemin, route) in cas {
            let d = try XCTUnwrap(lien("https://jolene.app" + chemin), chemin)
            XCTAssertEqual(d.route, route, chemin)
            XCTAssertTrue(DestinationLien.ecranNatifLivre(route), chemin)
            XCTAssertEqual(d.destination, route, chemin)
            XCTAssertTrue(d.destination.isNative, chemin)
        }
    }

    func testRenvoisWebEtEspaceEtablissementInchanges() throws {
        let litiges = try XCTUnwrap(lien("https://www.jolene.app/soignant/litiges#l%201"))
        XCTAssertEqual(litiges.route, .safari(url("https://jolene.app/soignant/litiges#l%201")))
        XCTAssertEqual(litiges.destination, litiges.route)
        let etab = try XCTUnwrap(lien("https://jolene.app/etablissement/missions/abc"))
        XCTAssertEqual(etab.destination, .etablissement(url("https://jolene.app/etablissement/missions/abc")))
        let horsAASA = try XCTUnwrap(lien("https://jolene.app/aide/pro-sante-connect?x=1"))
        XCTAssertEqual(horsAASA.destination, .safari(url("https://jolene.app/aide/pro-sante-connect?x=1")))
        XCTAssertFalse(DestinationLien.ecranNatifLivre(.safari(url("https://jolene.app/"))))
        XCTAssertFalse(DestinationLien.ecranNatifLivre(.etablissement(url("https://jolene.app/etablissement/x"))))
    }

    // MARK: Entrées refusées, liens internes

    func testMemesRefusQueLeRouteur() {
        for s in ["https://app.jolene.app/soignant/notifications", "https://evil.example/soignant/notifications",
                  "http://jolene.app/soignant/notifications", "https://jolene.app:444/soignant/notifications",
                  "https://jolene.app.evil.example/soignant/notifications"] {
            XCTAssertNil(lien(s), s)
            XCTAssertNil(LinkRouter.route(url: url(s)), s)
        }
        XCTAssertNil(DestinationLien(link: "https://evil.example/soignant/notifications"))
        XCTAssertNil(DestinationLien(link: "soignant/notifications"))
        XCTAssertNil(DestinationLien(link: ""))
    }

    func testLienInterneDuPush() throws {
        // `PAIEMENT_RECU` (correction 15) : section « Paiements à confirmer », renvoi web jusqu'à T13.
        let chemin = try XCTUnwrap(PushRouting.path(data: ["type_evenement": "PAIEMENT_RECU"], role: "SOIGNANT"))
        let paiement = try XCTUnwrap(DestinationLien(link: chemin))
        XCTAssertEqual(paiement.route, .revenus(section: .paiementsAConfirmer))
        XCTAssertEqual(paiement.destination, .safari(url("https://jolene.app/soignant/mes-gains?tab=paiements")))
        // `FACTURE_EMISE` soignant : onglet factures, renvoi web assumé jusqu'au lot 4.
        let facture = try XCTUnwrap(DestinationLien(link: try XCTUnwrap(PushRouting.path(data: ["type_evenement": "FACTURE_EMISE"],
                                                                                           role: "SOIGNANT"))))
        XCTAssertEqual(facture.route, .revenus(section: .factures))
        XCTAssertEqual(facture.destination, .safari(url("https://jolene.app/soignant/mes-gains?tab=factures")))
        // Lien explicite d'un autre hôte de confiance : URL canonique sur jolene.app.
        let notif = try XCTUnwrap(DestinationLien(link: "https://app.jolene.app/soignant/notifications"))
        XCTAssertEqual(notif.route, .notifications)
        XCTAssertEqual(notif.destination, .notifications, "T5 : centre de notifications natif")
        XCTAssertEqual(notif.canonique, url("https://jolene.app/soignant/notifications"))
        // Mission : destination native inchangée.
        let mission = try XCTUnwrap(DestinationLien(link: "/soignant/missions/m1"))
        XCTAssertEqual(mission.destination, .missionDetail(id: "m1"))
    }

    // MARK: Vecteur golden du push : destination attendue par famille de chemins

    /// Genre d'une route, sans ses valeurs associées (identifiants, URL).
    private func genre(_ route: JoleneRoute) -> String {
        switch route {
        case .missionDetail: return "missionDetail"
        case .missions: return "missions"
        case .explorer: return "explorer"
        case .notifications: return "notifications"
        case .profil: return "profil"
        case .stripeConnect: return "stripeConnect"
        case .revenus(let section): return "revenus(\(section.rawValue))"
        case .safari: return "safari"
        case .etablissement: return "etablissement"
        default: return "autre : \(route)"
        }
    }

    /// Famille d'un chemin du vecteur, lue sur le texte du chemin (indépendante du routeur).
    private func famille(_ chemin: String) -> String {
        let chemin = String(chemin.prefix { $0 != "#" })
        let path = String(chemin.prefix { $0 != "?" })
        let query = chemin.dropFirst(path.count)
        let segments = path.split(separator: "/").map(String.init)
        switch segments.first {
        case nil: return "/"
        case "etablissement": return "/etablissement/*"
        case "admin": return "/admin/*"
        case "contrat": return "/contrat/*"
        default: break
        }
        if segments.count == 3, segments[0] == "soignant", segments[1] == "missions" { return "/soignant/missions/{id}" }
        if path == "/soignant/mes-gains" { return path + query }
        return path
    }

    /// Chaque chemin non nul de `navigationPathForEvent` (vecteurs golden `push-routing`, lot 3 T2)
    /// appartient à une famille dont la route, la destination et le décompte sont figés ici. Une
    /// tranche d'écran qui passe sa ligne de `ecranNatifLivre` à `true` change la destination de sa
    /// famille (et les deux totaux) ; une re-génération du vecteur (T2 seul) change les décomptes.
    func testDestinationsDuRoutagePushParFamille() throws {
        let attendus: [String: (route: String, destination: String, nombre: Int)] = [
            "/soignant/missions/{id}": ("missionDetail", "missionDetail", 294),
            "/soignant/missions": ("missions", "missions", 130),
            "/soignant/recherche-missions": ("explorer", "explorer", 24),
            "/soignant/notifications": ("notifications", "notifications", 6),                // T5
            "/soignant/profil": ("profil", "profil", 7),                                     // T9 (livrée)
            "/soignant/stripe-connect": ("stripeConnect", "safari", 6),                      // T14a
            "/soignant/mes-gains?tab=paiements": ("revenus(paiements)", "safari", 32),       // T13
            "/soignant/mes-gains?tab=factures": ("revenus(factures)", "safari", 21),         // lot 4 (D4)
            "/soignant/litiges": ("safari", "safari", 46),
            "/soignant/mes-documents": ("safari", "safari", 30),
            "/etablissement/*": ("etablissement", "etablissement", 125),
            "/admin/*": ("safari", "safari", 47),
            "/contrat/*": ("safari", "safari", 97),
            "/": ("safari", "safari", 20),
            "/Soignant/Missions": ("safari", "safari", 5),                                   // casse : chemin inconnu
        ]
        let vecteurs = try Golden.charger("push-routing").filter { $0.fonction == "navigationPathForEvent" }
        var decomptes: [String: Int] = [:]
        var natifs = 0, renvois = 0
        for vecteur in vecteurs {
            guard let chemin = vecteur.expected.string else { continue }
            let d = try XCTUnwrap(DestinationLien(link: chemin), "\(vecteur.name) : \(chemin)")
            XCTAssertEqual(d.route, LinkRouter.resolve(link: chemin), vecteur.name)
            let nom = famille(chemin)
            guard let attendu = attendus[nom] else {
                XCTFail("\(vecteur.name) : famille inconnue « \(nom) » (\(d))")
                continue
            }
            decomptes[nom, default: 0] += 1
            XCTAssertEqual(genre(d.route), attendu.route, vecteur.name)
            XCTAssertEqual(genre(d.destination), attendu.destination, vecteur.name)
            if let externe = d.destination.externalURL {
                XCTAssertEqual(externe, d.canonique, vecteur.name)
                XCTAssertEqual(externe.host, "jolene.app", vecteur.name)
                renvois += 1
            } else {
                XCTAssertTrue(DestinationLien.ecranNatifLivre(d.destination), vecteur.name)
                natifs += 1
            }
        }
        XCTAssertEqual(decomptes, attendus.mapValues { $0.nombre }, "décomptes par famille")
        XCTAssertEqual(natifs, 461, "destinations natives (T5 : +6, centre de notifications ; T9 : +7, profil)")
        XCTAssertEqual(renvois, 429, "renvois web")
    }

    // MARK: Description masquée (PRINCIPES §7 : ni identifiant ni jeton dans les logs)

    /// Toutes les formes textuelles d'une valeur (description, reflet, interpolation).
    private func textes(_ valeur: Any) -> [String] {
        [String(describing: valeur), String(reflecting: valeur), "\(valeur)"]
    }

    /// Le chemin porte des jetons (`/etab/invitation/:token`, `src/App.tsx` l.433, consommé par
    /// `fn_accepter_invitation_membre(p_token)`) et des identifiants (`/contrat/:id` l.437,
    /// `/soignant/missions/:id`) ; la query et le fragment d'un lien de rappel portent `token_hash`,
    /// `code`, `access_token`, `refresh_token`. La description ne montre que le cas de route et un
    /// gabarit du chemin dont les segments dynamiques sont remplacés par « ‹masqué› ».
    func testDescriptionMasqueCheminQueryEtFragment() throws {
        let cas: [(lien: String, route: String, gabarit: String)] = [
            ("https://jolene.app/reset-password?token_hash=SECRET1&type=recovery",
             "resetPassword(AuthCallbackCredentials(token_hash recovery, valeur masquée))", "/reset-password?‹masqué›"),
            ("https://jolene.app/inscription/confirmer#access_token=SECRET2&refresh_token=SECRET3&type=signup",
             "confirmerInscription(AuthCallbackCredentials(implicit, valeurs masquées))", "/inscription/confirmer#‹masqué›"),
            ("https://jolene.app/auth/psc/callback?status=success&token_hash=SECRET4",
             "safari(/auth/psc/callback?‹masqué›)", "/auth/psc/callback?‹masqué›"),
            ("https://jolene.app/inscription/confirmer?code=SECRET5",
             "confirmerInscription(AuthCallbackCredentials(pkce, valeur masquée))", "/inscription/confirmer?‹masqué›"),
            ("https://jolene.app/etab/invitation/SECRET6",
             "etablissement(/etab/invitation/‹masqué›)", "/etab/invitation/‹masqué›"),
            ("https://jolene.app/contrat/SECRET7", "safari(/contrat/‹masqué›)", "/contrat/‹masqué›"),
            ("https://jolene.app/contrat/SECRET7/certificat#SECRET7", "safari(/contrat/‹masqué›/certificat#‹masqué›)",
             "/contrat/‹masqué›/certificat#‹masqué›"),
            ("https://jolene.app/soignant/missions/SECRET8", "missionDetail(id masqué)", "/soignant/missions/‹masqué›"),
            ("https://jolene.app/mission/SECRET8", "missionDetail(id masqué)", "/mission/‹masqué›"),
            ("https://jolene.app/soignant/missions/serie/SECRET8", "serieDetail(id masqué)", "/soignant/missions/serie/‹masqué›"),
            ("https://jolene.app/inscription/completer?ref=SECRET9", "inscription(completer, query masquée)",
             "/inscription/completer?‹masqué›"),
            ("https://jolene.app/soignant/SECRET10?tab=x", "safari(/soignant/‹masqué›?‹masqué›)", "/soignant/‹masqué›?‹masqué›"),
        ]
        for c in cas {
            let d = try XCTUnwrap(lien(c.lien), c.lien)
            for valeur in [d as Any, d.route, d.destination] {
                for texte in textes(valeur) {
                    XCTAssertFalse(texte.contains("SECRET"), "\(c.lien) → \(texte)")
                }
            }
            XCTAssertEqual(d.route.description, c.route, c.lien)
            XCTAssertEqual(d.route.debugDescription, c.route, c.lien)
            XCTAssertEqual(LienMasque.gabarit(d.canonique), c.gabarit, c.lien)
            XCTAssertEqual(d.description,
                           "DestinationLien(route: \(c.route), chemin: \(c.gabarit), destination: \(d.destination.isNative ? "natif" : "web"))",
                           c.lien)
            XCTAssertEqual(d.debugDescription, d.description, c.lien)
        }
    }

    /// Description de chaque cas de route : nom du cas et valeurs non sensibles seulement.
    func testDescriptionDeChaqueRoute() {
        let cas: [(JoleneRoute, String)] = [
            (.connexion, "connexion"),
            (.resetPassword(credentials: nil), "resetPassword(sans identifiants)"),
            (.resetPassword(credentials: .tokenHash(tokenHash: "SECRET", otpType: "recovery")),
             "resetPassword(AuthCallbackCredentials(token_hash recovery, valeur masquée))"),
            (.confirmerInscription(credentials: nil), "confirmerInscription(sans identifiants)"),
            (.inscription(EtapeInscription(page: .soignant, query: nil)), "inscription(soignant, sans query)"),
            (.inscription(EtapeInscription(page: .reprendre, query: "parrain=SECRET")), "inscription(reprendre, query masquée)"),
            (.accueil, "accueil"),
            (.explorer, "explorer"),
            (.missions, "missions"),
            (.missionDetail(id: "SECRET"), "missionDetail(id masqué)"),
            (.serieDetail(id: "SECRET"), "serieDetail(id masqué)"),
            (.revenus(section: .apercu), "revenus(apercu)"),
            (.revenus(section: .paiementsAConfirmer), "revenus(paiements)"),
            (.monCompte, "monCompte"),
            (.profil, "profil"),
            (.notifications, "notifications"),
            (.parametresNotifications, "parametresNotifications"),
            (.stripeConnect(retour: nil), "stripeConnect(sans retour)"),
            (.stripeConnect(retour: .succes), "stripeConnect(succes)"),
            (.stripeConnect(retour: .rafraichir), "stripeConnect(rafraichir)"),
            (.safari(url("https://jolene.app/admin/SECRET?SECRET#SECRET")), "safari(/admin/‹masqué›?‹masqué›#‹masqué›)"),
            (.safari(url("https://jolene.app")), "safari(/)"),
            (.etablissement(url("https://jolene.app/etablissement/missions/SECRET")),
             "etablissement(/etablissement/missions/‹masqué›)"),
        ]
        for (route, attendu) in cas {
            for texte in textes(route) {
                XCTAssertEqual(texte, attendu)
            }
        }
        let etape = EtapeInscription(page: .completer, query: "ref=SECRET")
        for texte in textes(etape) {
            XCTAssertEqual(texte, "EtapeInscription(completer, query masquée)")
        }
        for texte in textes(EtapeInscription(page: .soignant, query: nil)) {
            XCTAssertEqual(texte, "EtapeInscription(soignant, sans query)")
        }
    }

    /// Gabarit : un segment n'est montré que s'il appartient au vocabulaire fixe des routes ; tout
    /// chemin statique de `LinkRouter` (et des motifs AASA) est donc rendu tel quel.
    func testGabaritRendLesCheminsStatiquesTelsQuels() {
        let statiques = [
            "/connexion", "/reset-password", "/inscription/confirmer", "/inscription/soignant", "/inscription/reprendre",
            "/inscription/completer", "/inscription/etablissement", "/inscription/soignant/completion", "/inscription/succes",
            "/soignant/tableau-de-bord", "/soignant/recherche-missions", "/soignant/swipe-missions", "/soignant/missions",
            "/soignant/mes-matches", "/soignant/planning", "/soignant/calendrier-sync", "/soignant/historique-missions",
            "/soignant/mes-gains", "/soignant/mes-factures-honoraires", "/soignant/mes-avances", "/soignant/bulletins-paie",
            "/soignant/profil", "/soignant/reputation", "/soignant/mon-compte", "/soignant/parametres",
            "/soignant/parametres-complet", "/soignant/score", "/soignant/fiabilite", "/soignant/fiabilite-legacy",
            "/soignant/notifications", "/soignant/parametres/notifications", "/soignant/stripe-connect",
            "/soignant/litiges", "/soignant/mes-documents", "/soignant/presences", "/soignant/mes-favoris",
            "/auth/psc/callback", "/etab/invitation", "/admin/litiges", "/admin/reclamations", "/groupe",
            "/etablissement/contrats", "/etablissement/facturation", "/etablissement/litiges",
            "/etablissement/mes-reclamations", "/etablissement/missions", "/etablissement/tableau-de-bord",
            "/contrat", "/mission", "/",
        ]
        for chemin in statiques {
            XCTAssertEqual(LienMasque.gabarit(chemin: chemin), chemin)
        }
        XCTAssertEqual(LienMasque.gabarit(chemin: "/soignant/missions/abc"), "/soignant/missions/‹masqué›")
        XCTAssertEqual(LienMasque.gabarit(chemin: "/Soignant/Missions"), "/‹masqué›/‹masqué›", "casse : segment inconnu")
        XCTAssertEqual(LienMasque.gabarit(chemin: ""), "/")
        XCTAssertEqual(LienMasque.gabarit(url("https://jolene.app/soignant/notifications?")), "/soignant/notifications",
                       "query vide : rien à signaler")
    }

    // MARK: Table des écrans livrés (une ligne par tranche d'écran)

    /// `true` = destination dans l'app, écran provisoire compris : le coordinateur de liens (L1-T10, livré par
    /// L3-T3b) présente la route ; `false` = renvoi web canonique. Le reset et la confirmation d'inscription
    /// étaient à `true` « à l'arrivée de L1-T10 » : T3b n'apporte que le coordinateur, sans leurs écrans ; à `true`,
    /// leur lien n'aurait rien ouvert (`CibleNotification.aucune`). La confirmation repasse à `true` à l'intégration de
    /// T7, qui livre son écran et sa présentation hors de l'espace (`AiguillageLiens.Action.inscription`).
    func testTableDesEcransLivres() {
        let table: [(JoleneRoute, Bool, String)] = [
            (.connexion, true, "lot 0"),
            (.resetPassword(credentials: nil), false, "écran de réinitialisation natif non livré (reliquat L1-T10, T3b)"),
            (.confirmerInscription(credentials: nil), true, "T7 : ConfirmationInscriptionScreen, hors espace"),
            (.accueil, true, "lot 1"),
            (.explorer, true, "lot 1"),
            (.missions, true, "placeholder jusqu'à L1-T5"),
            (.missionDetail(id: "m"), true, "lot 1"),
            (.serieDetail(id: "s"), false, "renvoi web, décision 11 du lot 1 ; lot 4"),
            (.revenus(section: .apercu), true, "placeholder jusqu'à L3-T12"),
            (.monCompte, true, "hub ProfileScreen"),
            (.notifications, true, "T5"),
            (.parametresNotifications, true, "T6"),
            (.inscription(EtapeInscription(page: .soignant, query: nil)), true, "T7 : InscriptionRapideScreen, hors espace"),
            (.inscription(EtapeInscription(page: .reprendre, query: nil)), true, "T7 : OnboardingRootView, hors espace"),
            (.inscription(EtapeInscription(page: .completer, query: nil)), true, "T8 : CompletionProfilScreen, hors espace"),
            (.profil, true, "T9 : ProfilEditionScreen"),
            (.revenus(section: .paiementsAConfirmer), false, "T13"),
            (.stripeConnect(retour: nil), false, "T14a"),
            (.stripeConnect(retour: .succes), false, "T14a"),
            (.revenus(section: .factures), false, "lot 4"),
            (.revenus(section: .bulletins), false, "lot 4"),
            (.revenus(section: .avances), false, "lot 4"),
        ]
        for (route, livre, tranche) in table {
            XCTAssertEqual(DestinationLien.ecranNatifLivre(route), livre, "\(route) (\(tranche))")
        }
    }
}
