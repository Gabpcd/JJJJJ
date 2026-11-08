import XCTest
@testable import JoleneCore

/// Lot 3, T3 : destination effective d'un lien (`DeepLinkIntent`). Une route dont l'écran natif
/// n'est pas encore livré est renvoyée vers Safari avec son URL canonique (query et fragment
/// conservés) ; chaque tranche d'écran change une ligne de `DeepLinkIntent.ecranNatifLivre` et
/// ajuste ici la ligne correspondante.
final class DeepLinkIntentTests: XCTestCase {
    private func intent(_ s: String) -> DeepLinkIntent? {
        DeepLinkIntent(url: URL(string: s)!)
    }

    private func url(_ s: String) -> URL { URL(string: s)! }

    // MARK: Écrans du lot 3 pas encore livrés

    func testRoutesLot3SansEcranRenvoyeesVersSafariCanonique() throws {
        let cas: [(lien: String, route: JoleneRoute, canonique: String)] = [
            ("https://www.jolene.app/soignant/notifications?utm_source=push#haut", .notifications,
             "https://jolene.app/soignant/notifications?utm_source=push#haut"),                                     // T5
            ("https://jolene.app/soignant/parametres/notifications", .parametresNotifications,
             "https://jolene.app/soignant/parametres/notifications"),                                               // T6
            ("https://jolene.app/soignant/stripe-connect?success=true", .stripeConnect(retour: .succes),
             "https://jolene.app/soignant/stripe-connect?success=true"),                                            // T14a
            ("https://jolene.app/soignant/stripe-connect?refresh=true", .stripeConnect(retour: .rafraichir),
             "https://jolene.app/soignant/stripe-connect?refresh=true"),                                            // T14a
            ("https://jolene.app/inscription/soignant?profession=IDE&ville=Lyon",
             .inscription(EtapeInscription(page: .soignant, query: "profession=IDE&ville=Lyon")),
             "https://jolene.app/inscription/soignant?profession=IDE&ville=Lyon"),                                  // T7
            ("https://jolene.app/inscription/reprendre", .inscription(EtapeInscription(page: .reprendre, query: nil)),
             "https://jolene.app/inscription/reprendre"),                                                           // T7
            ("https://jolene.app/inscription/completer?ref=ABCD-12#x",
             .inscription(EtapeInscription(page: .completer, query: "ref=ABCD-12")),
             "https://jolene.app/inscription/completer?ref=ABCD-12#x"),                                             // T8
            ("https://jolene.app/soignant/profil?tab=principal", .profil,
             "https://jolene.app/soignant/profil?tab=principal"),                                                   // T9
            ("https://jolene.app/soignant/reputation", .profil, "https://jolene.app/soignant/reputation"),          // T9
            ("https://jolene.app/soignant/mes-gains?tab=paiements", .revenus(section: .paiementsAConfirmer),
             "https://jolene.app/soignant/mes-gains?tab=paiements"),                                                // T13
        ]
        for c in cas {
            let i = try XCTUnwrap(intent(c.lien), c.lien)
            XCTAssertEqual(i.route, c.route, c.lien)
            XCTAssertTrue(i.route.isNative, "\(c.lien) : la route reste native dans la table")
            XCTAssertFalse(DeepLinkIntent.ecranNatifLivre(i.route), c.lien)
            XCTAssertEqual(i.destination, .safari(url(c.canonique)), c.lien)
            XCTAssertEqual(i.canonique, url(c.canonique), c.lien)
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
            let i = try XCTUnwrap(intent("https://jolene.app" + chemin), chemin)
            XCTAssertEqual(i.route, .revenus(section: section), chemin)
            XCTAssertEqual(i.destination, .safari(url("https://jolene.app" + chemin)), chemin)
        }
    }

    // MARK: Destinations natives existantes inchangées

    func testRoutesDesLots0Et1InchangeesEtNatives() throws {
        let cas: [(String, JoleneRoute)] = [
            ("/connexion", .connexion),
            ("/reset-password?token_hash=h&type=recovery", .resetPassword(credentials: .tokenHash(tokenHash: "h", otpType: "recovery"))),
            ("/inscription/confirmer?token_hash=h&type=signup",
             .confirmerInscription(credentials: .tokenHash(tokenHash: "h", otpType: "signup"))),
            ("/soignant/tableau-de-bord", .accueil),
            ("/soignant/recherche-missions", .explorer),
            ("/soignant/missions?tab=passees", .missions),
            ("/soignant/missions/m%201", .missionDetail(id: "m 1")),
            ("/soignant/missions/serie/s1", .serieDetail(id: "s1")),
            ("/mission/m1", .missionDetail(id: "m1")),
            ("/soignant/mes-gains", .revenus(section: .apercu)),
            ("/soignant/mes-gains?tab=inconnu", .revenus(section: .apercu)),
            ("/soignant/mon-compte", .monCompte),
            ("/soignant/parametres", .monCompte),
            ("/soignant/score", .monCompte),
        ]
        for (chemin, route) in cas {
            let i = try XCTUnwrap(intent("https://jolene.app" + chemin), chemin)
            XCTAssertEqual(i.route, route, chemin)
            XCTAssertTrue(DeepLinkIntent.ecranNatifLivre(route), chemin)
            XCTAssertEqual(i.destination, route, chemin)
            XCTAssertTrue(i.destination.isNative, chemin)
        }
    }

    func testRenvoisWebEtEspaceEtablissementInchanges() throws {
        let litiges = try XCTUnwrap(intent("https://www.jolene.app/soignant/litiges#l%201"))
        XCTAssertEqual(litiges.route, .safari(url("https://jolene.app/soignant/litiges#l%201")))
        XCTAssertEqual(litiges.destination, litiges.route)
        let etab = try XCTUnwrap(intent("https://jolene.app/etablissement/missions/abc"))
        XCTAssertEqual(etab.destination, .etablissement(url("https://jolene.app/etablissement/missions/abc")))
        let horsAASA = try XCTUnwrap(intent("https://jolene.app/aide/pro-sante-connect?x=1"))
        XCTAssertEqual(horsAASA.destination, .safari(url("https://jolene.app/aide/pro-sante-connect?x=1")))
        XCTAssertFalse(DeepLinkIntent.ecranNatifLivre(.safari(url("https://jolene.app/"))))
        XCTAssertFalse(DeepLinkIntent.ecranNatifLivre(.etablissement(url("https://jolene.app/etablissement/x"))))
    }

    // MARK: Entrées refusées, liens internes

    func testMemesRefusQueLeRouteur() {
        for s in ["https://app.jolene.app/soignant/notifications", "https://evil.example/soignant/notifications",
                  "http://jolene.app/soignant/notifications", "https://jolene.app:444/soignant/notifications",
                  "https://jolene.app.evil.example/soignant/notifications"] {
            XCTAssertNil(intent(s), s)
            XCTAssertNil(LinkRouter.route(url: url(s)), s)
        }
        XCTAssertNil(DeepLinkIntent(link: "https://evil.example/soignant/notifications"))
        XCTAssertNil(DeepLinkIntent(link: "soignant/notifications"))
        XCTAssertNil(DeepLinkIntent(link: ""))
    }

    func testLienInterneDuPush() throws {
        // `PAIEMENT_RECU` (correction 15) : section « Paiements à confirmer », renvoi web jusqu'à T13.
        let chemin = try XCTUnwrap(PushRouting.path(data: ["type_evenement": "PAIEMENT_RECU"], role: "SOIGNANT"))
        let paiement = try XCTUnwrap(DeepLinkIntent(link: chemin))
        XCTAssertEqual(paiement.route, .revenus(section: .paiementsAConfirmer))
        XCTAssertEqual(paiement.destination, .safari(url("https://jolene.app/soignant/mes-gains?tab=paiements")))
        // `FACTURE_EMISE` soignant : onglet factures, renvoi web assumé jusqu'au lot 4.
        let facture = try XCTUnwrap(DeepLinkIntent(link: try XCTUnwrap(PushRouting.path(data: ["type_evenement": "FACTURE_EMISE"],
                                                                                          role: "SOIGNANT"))))
        XCTAssertEqual(facture.route, .revenus(section: .factures))
        XCTAssertEqual(facture.destination, .safari(url("https://jolene.app/soignant/mes-gains?tab=factures")))
        // Lien explicite d'un autre hôte de confiance : URL canonique sur jolene.app.
        let notif = try XCTUnwrap(DeepLinkIntent(link: "https://app.jolene.app/soignant/notifications"))
        XCTAssertEqual(notif.route, .notifications)
        XCTAssertEqual(notif.destination, .safari(url("https://jolene.app/soignant/notifications")))
        // Mission : destination native inchangée.
        let mission = try XCTUnwrap(DeepLinkIntent(link: "/soignant/missions/m1"))
        XCTAssertEqual(mission.destination, .missionDetail(id: "m1"))
    }

    /// Tout chemin produit par le routage push (vecteurs golden de `navigationPathForEvent`) a une
    /// destination : écran natif, ou renvoi web sur l'origine canonique.
    func testToutCheminDuRoutagePushADesDestination() throws {
        let vecteurs = try Golden.charger("push-routing").filter { $0.fonction == "navigationPathForEvent" }
        var resolus = 0
        for vecteur in vecteurs {
            guard let chemin = vecteur.expected.string else { continue }
            let i = try XCTUnwrap(DeepLinkIntent(link: chemin), "\(vecteur.name) : \(chemin)")
            XCTAssertEqual(i.route, LinkRouter.resolve(link: chemin), vecteur.name)
            if let externe = i.destination.externalURL {
                XCTAssertEqual(externe.host, "jolene.app", vecteur.name)
                XCTAssertEqual(externe, i.canonique, vecteur.name)
            } else {
                XCTAssertTrue(DeepLinkIntent.ecranNatifLivre(i.destination), vecteur.name)
            }
            resolus += 1
        }
        XCTAssertGreaterThan(resolus, 800, "chemins non nuls du vecteur push-routing")
    }

    // MARK: Table des écrans livrés (une ligne par tranche d'écran)

    func testTableDesEcransLivres() {
        let table: [(JoleneRoute, Bool, String)] = [
            (.connexion, true, "lot 0"),
            (.resetPassword(credentials: nil), true, "lot 1 T10"),
            (.confirmerInscription(credentials: nil), true, "lot 1 T10"),
            (.accueil, true, "lot 1"),
            (.explorer, true, "lot 1"),
            (.missions, true, "lot 1"),
            (.missionDetail(id: "m"), true, "lot 1"),
            (.serieDetail(id: "s"), true, "lot 1"),
            (.revenus(section: .apercu), true, "onglet Revenus"),
            (.monCompte, true, "hub ProfileScreen"),
            (.notifications, false, "T5"),
            (.parametresNotifications, false, "T6"),
            (.inscription(EtapeInscription(page: .soignant, query: nil)), false, "T7"),
            (.inscription(EtapeInscription(page: .reprendre, query: nil)), false, "T7"),
            (.inscription(EtapeInscription(page: .completer, query: nil)), false, "T8"),
            (.profil, false, "T9"),
            (.revenus(section: .paiementsAConfirmer), false, "T13"),
            (.stripeConnect(retour: nil), false, "T14a"),
            (.stripeConnect(retour: .succes), false, "T14a"),
            (.revenus(section: .factures), false, "lot 4"),
            (.revenus(section: .bulletins), false, "lot 4"),
            (.revenus(section: .avances), false, "lot 4"),
        ]
        for (route, livre, tranche) in table {
            XCTAssertEqual(DeepLinkIntent.ecranNatifLivre(route), livre, "\(route) (\(tranche))")
        }
    }
}
