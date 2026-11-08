import XCTest
@testable import JoleneCore

/// Lot 1 T10, reliquat lot 3 T3b (`DECISIONS_LOT3.md`, « T3 livrée en deux temps » et section T3b) : intention d'un
/// lien entrant (`DeepLinkIntent`) et aiguillage unique des liens et des taps push (`AiguillageLiens`).
///
/// Ce que ces tests prouvent (niveau 1) :
/// - classement de chaque genre de route : espace natif (cible de l'espace), renvoi web canonique (écran non livré,
///   section de Revenus, Safari, établissement), lien de réinitialisation `?code=` refusé (option B, décision 7 du
///   lot 1), lien consommé hors de l'espace (liste nommée et fermée) ;
/// - un lien de l'espace reçu avant `.ready` est mémorisé, puis rejoué une seule fois par le premier espace prêt ;
///   reçu dans un espace ouvert, il est présenté aussitôt, pour l'epoch de cet espace ;
/// - un renvoi web est présenté aussitôt, avec ou sans session, et n'est jamais mémorisé ;
/// - les taps push passent par le même aiguillage (`BoiteTapsPush` → `DestinationLien` → action), avec le rôle du
///   snapshot ; entre un lien et un tap en attente, le plus récent l'emporte, l'autre sert de repli ;
/// - un renvoi web issu de l'app n'est jamais rejoué comme lien universel (`LOT1_PLAN.md` §3 T10) ;
/// - argument DEBUG `-JOLENE_OPEN_URL`, texte du refus (décision 7 du lot 1), descriptions masquées (PRINCIPES §7).
@MainActor
final class DeepLinkIntentTests: XCTestCase {
    private func url(_ s: String) -> URL { URL(string: s)! }

    private func snapshot(epoch: Int, role: String = "SOIGNANT") -> SessionSnapshot {
        let user = AuthenticatedUser(id: "u-lien", email: "u-lien@example.invalid",
                                     emailConfirmedAt: Date(timeIntervalSince1970: 1_700_000_000), appMetadataRole: role)
        let profil = SoignantProfile(id: user.id, profession: "IDE")
        return SessionSnapshot(user: user, role: RoleResult(role: role), profile: profil,
                               context: MissionReadContext(userId: user.id, email: user.email, profile: profil), epoch: epoch)
    }

    private func intention(_ s: String) throws -> DeepLinkIntent {
        try XCTUnwrap(DeepLinkIntent(url: url(s)), s)
    }

    // MARK: - Classement

    /// Route native dont l'écran est livré : présentée dans l'espace, cible de `CibleNotification`.
    func testRoutesNativesLivreesVontDansLEspace() throws {
        let cas: [(String, CibleNotification)] = [
            ("https://jolene.app/soignant/tableau-de-bord", .accueil),
            ("https://jolene.app/soignant/recherche-missions", .explorer),
            ("https://jolene.app/soignant/swipe-missions", .explorer),
            ("https://jolene.app/soignant/missions?tab=passees", .missions),
            ("https://jolene.app/soignant/missions/m%201", .mission(id: "m 1")),
            ("https://jolene.app/mission/m1", .mission(id: "m1")),
            ("https://jolene.app/soignant/mes-gains", .revenus(section: .apercu)),
            ("https://jolene.app/soignant/mes-gains?tab=inconnu", .revenus(section: .apercu)),
            ("https://jolene.app/soignant/mon-compte", .monCompte),
            ("https://jolene.app/soignant/parametres", .monCompte),
            ("https://jolene.app/soignant/profil", .profil),
            ("https://jolene.app/soignant/reputation", .profil),
            ("https://www.jolene.app/soignant/notifications?utm_source=mail#haut", .centre),
            ("https://jolene.app/soignant/parametres/notifications", .preferences),
            // Onglet « Confidentialité » du profil web (export RGPD, suppression de compte) : le hub natif porte les deux
            // depuis L3-T11 (intégration du lot 3 ; revue B8 de T3b, m3, garde de `LinksRouterTests`).
            ("https://jolene.app/soignant/profil?tab=confidentialite#suppression-compte", .monCompte),
        ]
        for (lien, cible) in cas {
            let obtenue = try intention(lien)
            guard case .espace(let destination) = obtenue else {
                XCTFail("\(lien) : destination de l'espace attendue (\(obtenue))")
                continue
            }
            XCTAssertEqual(CibleNotification(destination), cible, lien)
            XCTAssertTrue(destination.destination.isNative, lien)
        }
    }

    /// Écran non livré, section de Revenus en renvoi web, chemin servi par Safari, espace établissement : URL canonique
    /// du lien reçu (query et fragment conservés), jamais un écran vide.
    func testRoutesSansEcranOuExternesSontDesRenvoisWebCanoniques() throws {
        let safari = [
            "https://jolene.app/soignant/mes-gains?tab=factures",                     // lot 4 (D4)
            "https://jolene.app/soignant/mes-gains?tab=bulletins&annee=2026",          // lot 4 (D4)
            "https://jolene.app/soignant/mes-gains?tab=avances",                      // lot 4 (D4)
            "https://jolene.app/soignant/mes-gains?tab=paiements",                    // T13
            "https://jolene.app/soignant/mes-factures-honoraires",                    // alias, lot 4
            "https://jolene.app/soignant/stripe-connect?success=true",                // T14a
            "https://jolene.app/soignant/stripe-connect?refresh=true",                // T14a
            "https://jolene.app/soignant/missions/serie/s1",                          // lot 4 (décision 11 du lot 1)
            "https://jolene.app/soignant/litiges#l1",
            // T7 (confirmation, `soignant`, `reprendre`) : présentées hors de l'espace depuis l'intégration du lot 3
            // (`testLiensDInscriptionEtDeConfirmationPresentesHorsDeLEspace`) ; la complétion attend T8.
            "https://jolene.app/inscription/completer?ref=ABCD-12",                   // T8
            "https://jolene.app/reset-password?token_hash=h&type=recovery",           // reset natif non livré
            "https://jolene.app/reset-password#access_token=a&refresh_token=r&type=recovery",
            "https://jolene.app/reset-password",                                      // sans identifiants
            "https://jolene.app/inscription/etablissement",
            "https://jolene.app/auth/psc/callback?status=success",                    // PSC non construit (D8)
            "https://jolene.app/contrat/c1",
            "https://jolene.app/admin/litiges",
            "https://jolene.app/groupe/tableau",
            "https://jolene.app/aide/pro-sante-connect?x=1",                          // hors AASA
        ]
        for lien in safari {
            let obtenue = try intention(lien)
            guard case .renvoiWeb(let destination) = obtenue else {
                XCTFail("\(lien) : renvoi web attendu (\(obtenue))")
                continue
            }
            let canonique = lien.replacingOccurrences(of: "https://www.", with: "https://")
            XCTAssertEqual(destination.destination, .safari(url(canonique)), lien)
            XCTAssertEqual(destination.destination.externalURL, destination.canonique, lien)
        }
        for lien in ["https://jolene.app/etablissement/missions/abc", "https://www.jolene.app/etab/invitation/t1"] {
            guard case .renvoiWeb(let destination) = try intention(lien) else {
                XCTFail("\(lien) : espace établissement en renvoi web")
                continue
            }
            XCTAssertEqual(destination.destination, .etablissement(url(lien.replacingOccurrences(of: "www.", with: ""))), lien)
        }
    }

    /// Option B (décision 7 du lot 1) : un lien de réinitialisation au format PKCE (`?code=`) est refusé dans l'app,
    /// jamais échangé ni servi par Safari (le verifier n'existe que dans le navigateur qui a demandé le lien) ;
    /// `token_hash` et implicit restent acceptés (renvoi web tant que l'écran natif n'est pas livré).
    func testReinitialisationPkceRefuseeOptionB() throws {
        for lien in ["https://jolene.app/reset-password?code=c", "https://www.jolene.app/reset-password?code=c&type=recovery",
                     "https://jolene.app/reset-password?code=c#x"] {
            XCTAssertEqual(try intention(lien), .reinitialisationRefusee, lien)
        }
        // Lien interne (tap, centre) : la barre oblique finale est ignorée par le routeur, le refus vaut aussi. (Un
        // lien universel `/reset-password/` n'est pas couvert par l'AASA : l'app ne le reçoit pas, Safari le sert.)
        XCTAssertEqual(DeepLinkIntent(try XCTUnwrap(DestinationLien(link: "/reset-password/?code=c"))), .reinitialisationRefusee)
        XCTAssertNotEqual(try intention("https://jolene.app/reset-password?token_hash=h&type=recovery"), .reinitialisationRefusee)
        XCTAssertNotEqual(try intention("https://jolene.app/reset-password#access_token=a&refresh_token=r&type=recovery"),
                          .reinitialisationRefusee)
        // La confirmation d'inscription accepte `code` (D10 du lot 3, T7) : l'option B ne vaut que pour le reset.
        XCTAssertNotEqual(try intention("https://jolene.app/inscription/confirmer?code=c"), .reinitialisationRefusee)
        // Le refus suit la route, pas la ligne `ecranNatifLivre` : un écran de reset livré plus tard n'y changera rien.
        XCTAssertEqual(DeepLinkIntent(try XCTUnwrap(DestinationLien(link: "/reset-password?code=c"))), .reinitialisationRefusee)
    }

    /// Texte du refus : décision 7 du lot 1 (`LOT1_PLAN.md` l.403), non juridique, repris mot pour mot.
    func testTexteDuRefusDeReinitialisationEpingle() {
        XCTAssertEqual(DeepLinkIntent.Textes.reinitialisationRefusee,
                       "Ce lien ne permet pas de réinitialiser le mot de passe depuis l'application.")
        XCTAssertEqual(DeepLinkIntent.Textes.fermer, "Fermer", "libellé déjà employé par `FiltresSheet` (lot 1)")
    }

    /// Liens consommés hors de l'espace : liste **nommée et fermée** (`CLAUDE.md`, « un gap connu reste verrouillé »).
    /// Une route native livrée qui n'a pas de cible dans l'espace tombe ici : la connexion (rien à ouvrir) ; depuis
    /// l'intégration de T7, la confirmation d'inscription et les pages `soignant` / `reprendre`, présentées hors de
    /// l'espace (action `.inscription`, déposée par le coordinateur dans `BoiteLiensInscription`, lue par `RootView`) ;
    /// demain le reset natif. Toute autre route qui y tomberait (une tranche passe sa ligne de `ecranNatifLivre` à `true`
    /// sans présentation hors espace) fait échouer ce test : il faut alors sa présentation dans `AiguillageLiens` (et
    /// l'app), puis sa ligne ici, justifiée dans `DECISIONS_LOT3.md`.
    func testToutLienHorsEspaceAppartientALaListeNommee() throws {
        let golden = try Golden.charger("push-routing").filter { $0.fonction == "navigationPathForEvent" }
            .compactMap { $0.expected.string }
        var horsEspace: Set<String> = []
        for chemin in Self.liensParGenre + golden {
            let lien = try XCTUnwrap(DestinationLien(link: chemin), chemin)
            guard case .horsEspace(let destination) = DeepLinkIntent(lien) else { continue }
            let aiguillage = AiguillageLiens(taps: BoiteTapsPush())
            switch destination.destination {
            case .connexion:
                horsEspace.insert("connexion")
                XCTAssertNil(aiguillage.recevoir(DeepLinkIntent(lien)), "\(chemin) : écran de connexion, rien à ouvrir")
            case .confirmerInscription:
                horsEspace.insert("confirmation")
                XCTAssertEqual(aiguillage.recevoir(DeepLinkIntent(lien)), .inscription(destination), chemin)
            case .inscription(let etape) where etape.page == .soignant || etape.page == .reprendre:
                horsEspace.insert("inscription")
                XCTAssertEqual(aiguillage.recevoir(DeepLinkIntent(lien)), .inscription(destination), chemin)
            default:
                XCTFail("\(chemin) : lien hors espace sans présentation nommée (\(destination))")
            }
            XCTAssertFalse(aiguillage.aUnLienEnAttente, "\(chemin) : jamais mémorisé pour un espace à venir")
        }
        XCTAssertEqual(horsEspace, ["connexion", "confirmation", "inscription"],
                       "liste nommée : connexion (sans action), confirmation et inscription (T7, présentées hors espace)")
        let aiguillage = AiguillageLiens(taps: BoiteTapsPush())
        XCTAssertNil(aiguillage.recevoir(url: url("https://jolene.app/connexion")), "écran de connexion : rien à ouvrir")
        XCTAssertFalse(aiguillage.aUnLienEnAttente, "jamais mémorisé")
        _ = aiguillage.ouvrirEspace(snapshot(epoch: 1))
        XCTAssertNil(aiguillage.recevoir(url: url("https://jolene.app/connexion")), "espace prêt : on y reste")
    }

    /// Intégration du lot 3 (T7 × T3b) : la confirmation d'inscription (`token_hash`, implicit, `code` — D10) et les
    /// pages `soignant` / `reprendre` sont livrées par T7 et consommées **hors de l'espace** (écran de connexion,
    /// confirmation présentée au-dessus de tout état, aiguillage d'onboarding) : l'aiguillage rend `.inscription` avec la
    /// destination reçue (query conservée : profession pré-remplie, `?ref=` pour le lot 4), avec ou sans espace ouvert,
    /// sans jamais la mémoriser ni la rejouer ; la vue de session décide (une identité ouverte n'a pas d'inscription à
    /// faire, la confirmation est présentée quel que soit l'état). La complétion (`completer`, T8) reste un renvoi web.
    func testLiensDInscriptionEtDeConfirmationPresentesHorsDeLEspace() throws {
        let aiguillage = AiguillageLiens(taps: BoiteTapsPush())
        let confirmation = try XCTUnwrap(DestinationLien(url: url("https://jolene.app/inscription/confirmer?token_hash=h&type=signup")))
        XCTAssertEqual(confirmation.destination, .confirmerInscription(credentials: .tokenHash(tokenHash: "h", otpType: "signup")))
        XCTAssertEqual(aiguillage.recevoir(url: url("https://jolene.app/inscription/confirmer?token_hash=h&type=signup")),
                       .inscription(confirmation), "sans session : présentée aussitôt")
        XCTAssertEqual(aiguillage.recevoir(url: url("https://jolene.app/inscription/confirmer?code=c")),
                       .inscription(try XCTUnwrap(DestinationLien(url: url("https://jolene.app/inscription/confirmer?code=c")))),
                       "D10 : `code` accepté pour la confirmation (l'option B ne vaut que pour le reset)")
        let rapide = try XCTUnwrap(DestinationLien(url: url("https://www.jolene.app/inscription/soignant?profession=IDE&ville=Lyon")))
        XCTAssertEqual(rapide.destination, .inscription(EtapeInscription(page: .soignant, query: "profession=IDE&ville=Lyon")),
                       "query conservée (profession pré-remplie)")
        XCTAssertEqual(aiguillage.recevoir(url: url("https://www.jolene.app/inscription/soignant?profession=IDE&ville=Lyon")),
                       .inscription(rapide))
        XCTAssertFalse(aiguillage.aUnLienEnAttente, "jamais mémorisé")
        XCTAssertNil(aiguillage.ouvrirEspace(snapshot(epoch: 1)), "rien n'est rejoué à l'ouverture de l'espace")
        let reprise = try XCTUnwrap(DestinationLien(url: url("https://jolene.app/inscription/reprendre")))
        XCTAssertEqual(aiguillage.recevoir(url: url("https://jolene.app/inscription/reprendre")), .inscription(reprise),
                       "espace ouvert : même action, la vue de session l'écarte")
        XCTAssertEqual(aiguillage.recevoir(url: url("https://jolene.app/inscription/confirmer?token_hash=h&type=signup")),
                       .inscription(confirmation), "espace ouvert : la confirmation est présentée au-dessus de tout état")
        let completer = url("https://jolene.app/inscription/completer?ref=ABCD-12")
        XCTAssertEqual(aiguillage.recevoir(url: completer), .renvoiWeb(.safari(completer)), "T8 non livrée : renvoi web")
        // Un tap ou un lien mémorisé ne mène jamais à l'inscription (aucun vecteur push n'y pointe) : sans action.
        XCTAssertNil(aiguillage.ouvrirEspace(snapshot(epoch: 2)))
    }

    /// Toute destination de l'espace (table des routes et famille push golden) donne, espace ouvert, une navigation
    /// vers une cible présentable ou un renvoi web canonique ; jamais une action vide.
    func testToutLienDeLEspaceDonneUneAction() throws {
        let golden = try Golden.charger("push-routing").filter { $0.fonction == "navigationPathForEvent" }
            .compactMap { $0.expected.string }
        let aiguillage = AiguillageLiens(taps: BoiteTapsPush())
        _ = aiguillage.ouvrirEspace(snapshot(epoch: 7))
        var navigations = 0, renvois = 0
        for chemin in Self.liensParGenre + golden {
            let lien = try XCTUnwrap(DestinationLien(link: chemin), chemin)
            let intention = DeepLinkIntent(lien)
            switch aiguillage.recevoir(intention) {
            case .naviguer(let cible, let route, let epoch)?:
                XCTAssertEqual(epoch, 7, chemin)
                XCTAssertEqual(route, lien.destination, chemin)
                XCTAssertTrue(cible.estPresentable(renvoiWebDisponible: true), chemin)
                XCTAssertNotNil(cible.onglet, chemin)
                navigations += 1
            case .renvoiWeb(let route)?:
                XCTAssertEqual(route.externalURL, lien.canonique, chemin)
                aiguillage.renvoiWebFerme()
                renvois += 1
            case .refusReinitialisation?:
                XCTAssertEqual(intention, .reinitialisationRefusee, chemin)
            case .inscription(let destination)?:
                XCTAssertEqual(intention, .horsEspace(destination), "\(chemin) : présenté hors de l'espace (T7)")
            case nil:
                guard case .horsEspace = intention else {
                    XCTFail("\(chemin) : aucune action pour \(intention)")
                    continue
                }
            }
        }
        XCTAssertGreaterThan(navigations, 0)
        XCTAssertGreaterThan(renvois, 0)
    }

    /// Sections de Revenus lues dans `?tab=` (comparaison exacte, `MesGains.tsx` l.899-900) : l'aperçu ouvre l'onglet
    /// natif ; factures, bulletins et avances restent des renvois web (D4), « Paiements à confirmer » jusqu'à T13.
    func testSectionsDeRevenusDepuisTab() throws {
        let cas: [(String, SectionRevenus, Bool)] = [
            ("tab=apercu", .apercu, true), ("", .apercu, true), ("tab=APERCU", .apercu, true), ("tab=inconnu", .apercu, true),
            ("tab=factures", .factures, false), ("tab=bulletins", .bulletins, false), ("tab=avances", .avances, false),
            ("tab=paiements", .paiementsAConfirmer, false),
        ]
        for (query, section, natif) in cas {
            let lien = "https://jolene.app/soignant/mes-gains" + (query.isEmpty ? "" : "?" + query)
            let destination = try XCTUnwrap(DestinationLien(url: url(lien)), lien)
            XCTAssertEqual(destination.route, .revenus(section: section), lien)
            switch try intention(lien) {
            case .espace(let d):
                XCTAssertTrue(natif, lien)
                XCTAssertEqual(CibleNotification(d), .revenus(section: .apercu), lien)
            case .renvoiWeb(let d):
                XCTAssertFalse(natif, lien)
                XCTAssertEqual(d.destination, .safari(url(lien)), lien)
            default:
                XCTFail(lien)
            }
        }
    }

    func testLienNonJoleneIgnore() {
        for s in ["https://evil.example/soignant/notifications", "http://jolene.app/soignant/notifications",
                  "https://jolene.app:444/soignant/notifications", "https://app.jolene.app/soignant/notifications",
                  "jolene://soignant/notifications"] {
            XCTAssertNil(DeepLinkIntent(url: url(s)), s)
            let aiguillage = AiguillageLiens(taps: BoiteTapsPush())
            XCTAssertNil(aiguillage.recevoir(url: url(s)), s)
            XCTAssertFalse(aiguillage.aUnLienEnAttente, s)
            XCTAssertNil(aiguillage.ouvrirEspace(snapshot(epoch: 1)), s)
        }
    }

    // MARK: - Aiguillage : lien reçu avant `.ready`, rejeu

    func testLienDeLEspaceAvantReadyMemoriseEtRejoueUneSeuleFois() {
        let aiguillage = AiguillageLiens(taps: BoiteTapsPush())
        XCTAssertNil(aiguillage.recevoir(url: url("https://jolene.app/soignant/notifications")),
                     "aucun espace ouvert (connexion, restauration) : rien n'est présenté")
        XCTAssertTrue(aiguillage.aUnLienEnAttente)
        XCTAssertEqual(aiguillage.ouvrirEspace(snapshot(epoch: 3)),
                       .naviguer(.centre, route: .notifications, epoch: 3), "rejoué par le premier espace prêt")
        XCTAssertFalse(aiguillage.aUnLienEnAttente)
        aiguillage.fermerEspace(epoch: 3)
        XCTAssertNil(aiguillage.ouvrirEspace(snapshot(epoch: 4)), "rejoué une seule fois")
    }

    func testLienDeLEspaceDansUnEspaceOuvertPresenteAussitotPourSonEpoch() {
        let aiguillage = AiguillageLiens(taps: BoiteTapsPush())
        XCTAssertNil(aiguillage.ouvrirEspace(snapshot(epoch: 2)))
        XCTAssertEqual(aiguillage.recevoir(url: url("https://jolene.app/soignant/missions/m-9")),
                       .naviguer(.mission(id: "m-9"), route: .missionDetail(id: "m-9"), epoch: 2))
        XCTAssertFalse(aiguillage.aUnLienEnAttente, "présenté, jamais gardé")
        XCTAssertEqual(aiguillage.recevoir(url: url("https://jolene.app/soignant/profil")),
                       .naviguer(.profil, route: .profil, epoch: 2))
    }

    func testLeDernierLienRecuAvantReadyGagne() {
        let aiguillage = AiguillageLiens(taps: BoiteTapsPush())
        _ = aiguillage.recevoir(url: url("https://jolene.app/soignant/notifications"))
        _ = aiguillage.recevoir(url: url("https://jolene.app/soignant/parametres/notifications"))
        XCTAssertEqual(aiguillage.ouvrirEspace(snapshot(epoch: 1)),
                       .naviguer(.preferences, route: .parametresNotifications, epoch: 1))
    }

    func testFermetureDeLEspacePuisLienMemoriseEtAncienEspaceSansEffet() {
        let aiguillage = AiguillageLiens(taps: BoiteTapsPush())
        _ = aiguillage.ouvrirEspace(snapshot(epoch: 1))
        aiguillage.fermerEspace(epoch: 1) // déconnexion : retour à l'écran de connexion
        XCTAssertNil(aiguillage.recevoir(url: url("https://jolene.app/soignant/mon-compte")))
        XCTAssertTrue(aiguillage.aUnLienEnAttente, "reçu sans espace : attend le prochain espace prêt")
        XCTAssertEqual(aiguillage.ouvrirEspace(snapshot(epoch: 2)), .naviguer(.monCompte, route: .monCompte, epoch: 2))
        // Le nouvel espace apparaît avant la disparition de l'ancien (`.id(snapshot.epoch)`) : l'ancien ne ferme rien.
        _ = aiguillage.ouvrirEspace(snapshot(epoch: 3))
        aiguillage.fermerEspace(epoch: 2)
        XCTAssertEqual(aiguillage.recevoir(url: url("https://jolene.app/soignant/tableau-de-bord")),
                       .naviguer(.accueil, route: .accueil, epoch: 3), "l'espace 3 reste ouvert")
    }

    // MARK: - Renvoi web, refus

    /// Un renvoi web n'a pas besoin de l'espace (inscription, établissement, compte bloqué) : présenté aussitôt, même
    /// sans session, et jamais mémorisé pour un espace à venir.
    func testRenvoiWebPresenteAussitotSansSessionEtJamaisMemorise() {
        let aiguillage = AiguillageLiens(taps: BoiteTapsPush())
        let stripe = url("https://jolene.app/soignant/stripe-connect?success=true")
        XCTAssertEqual(aiguillage.recevoir(url: stripe), .renvoiWeb(.safari(stripe)))
        XCTAssertFalse(aiguillage.aUnLienEnAttente)
        aiguillage.renvoiWebPresente(.safari(stripe))
        aiguillage.renvoiWebFerme()
        XCTAssertNil(aiguillage.ouvrirEspace(snapshot(epoch: 1)), "déjà présenté : rien à rejouer")
        let etab = url("https://jolene.app/etablissement/missions/abc")
        XCTAssertEqual(aiguillage.recevoir(url: etab), .renvoiWeb(.etablissement(etab)), "espace ouvert : même règle")
    }

    func testReinitialisationPkceRefuseeAvecOuSansEspace() {
        let aiguillage = AiguillageLiens(taps: BoiteTapsPush())
        XCTAssertEqual(aiguillage.recevoir(url: url("https://jolene.app/reset-password?code=c")), .refusReinitialisation)
        XCTAssertFalse(aiguillage.aUnLienEnAttente, "jamais mémorisé, jamais échangé")
        XCTAssertNil(aiguillage.ouvrirEspace(snapshot(epoch: 1)))
        XCTAssertEqual(aiguillage.recevoir(url: url("https://jolene.app/reset-password?code=c")), .refusReinitialisation)
        let tokenHash = url("https://jolene.app/reset-password?token_hash=h&type=recovery")
        XCTAssertEqual(aiguillage.recevoir(url: tokenHash), .renvoiWeb(.safari(tokenHash)),
                       "`token_hash` : la page web de réinitialisation (écran natif non livré)")
    }

    /// `LOT1_PLAN.md` §3 T10 : « un `.safari` issu de l'app n'est jamais rejoué comme lien universel ». Tant que le
    /// renvoi est affiché, le même lien reçu par l'app (retour du système, double remise `onOpenURL` /
    /// `onContinueUserActivity`) est ignoré ; une fois la feuille fermée, le lien est de nouveau présenté.
    func testRenvoiWebIssuDeLAppJamaisRejoueCommeLienUniversel() {
        let aiguillage = AiguillageLiens(taps: BoiteTapsPush())
        _ = aiguillage.ouvrirEspace(snapshot(epoch: 1))
        let litiges = url("https://jolene.app/soignant/litiges")
        aiguillage.renvoiWebPresente(.safari(litiges)) // présenté par l'app (centre, Accueil, profil)
        XCTAssertNil(aiguillage.recevoir(url: litiges), "même URL revenue par lien universel : ignorée")
        XCTAssertNil(aiguillage.recevoir(url: url("https://www.jolene.app/soignant/litiges")), "même URL canonique")
        let autre = url("https://jolene.app/contrat/c1")
        XCTAssertEqual(aiguillage.recevoir(url: autre), .renvoiWeb(.safari(autre)), "autre lien : présenté")
        aiguillage.renvoiWebPresente(.safari(autre))
        aiguillage.renvoiWebFerme()
        XCTAssertEqual(aiguillage.recevoir(url: litiges), .renvoiWeb(.safari(litiges)), "feuille fermée : présenté de nouveau")
    }

    // MARK: - Taps push : même aiguillage

    func testTapAvantReadyRejoueParLAiguillageAvecLeRole() {
        let taps = BoiteTapsPush()
        let aiguillage = AiguillageLiens(taps: taps)
        taps.recevoir(PushTapIntent(donnees: ["type_evenement": "RAPPEL_MISSION", "mission_id": "m-1"]))
        XCTAssertNil(aiguillage.tapRecu(), "aucun espace ouvert : le tap reste dans la boîte")
        XCTAssertTrue(taps.aUnTapEnAttente)
        XCTAssertEqual(aiguillage.ouvrirEspace(snapshot(epoch: 5)),
                       .naviguer(.mission(id: "m-1"), route: .missionDetail(id: "m-1"), epoch: 5))
        XCTAssertFalse(taps.aUnTapEnAttente)
    }

    func testTapDansUnEspaceOuvertAvecLeRoleDuSnapshot() {
        let taps = BoiteTapsPush()
        let aiguillage = AiguillageLiens(taps: taps)
        _ = aiguillage.ouvrirEspace(snapshot(epoch: 1, role: "ADMIN_ETABLISSEMENT"))
        taps.recevoir(PushTapIntent(donnees: ["type_evenement": "FACTURE_EMISE", "facture_id": "f1"]))
        XCTAssertEqual(aiguillage.tapRecu(),
                       .renvoiWeb(.etablissement(url("https://jolene.app/etablissement/facturation/f1"))))
        taps.recevoir(PushTapIntent(donnees: ["type_evenement": "LITIGE_OUVERT"]))
        XCTAssertEqual(aiguillage.tapRecu(), .renvoiWeb(.etablissement(url("https://jolene.app/etablissement/litiges"))))
        XCTAssertNil(aiguillage.tapRecu(), "boîte vide")
    }

    func testTapDUnAutreEpochEcarte() {
        let taps = BoiteTapsPush()
        let aiguillage = AiguillageLiens(taps: taps)
        _ = aiguillage.ouvrirEspace(snapshot(epoch: 1))
        taps.recevoir(PushTapIntent(donnees: ["type_evenement": "MISSION_A_POURVOIR"]))
        aiguillage.fermerEspace(epoch: 1) // déconnexion avant que l'espace 1 n'ait relu la boîte
        XCTAssertNil(aiguillage.ouvrirEspace(snapshot(epoch: 2)), "règle de `BoiteTapsPush` conservée")
    }

    func testLeTapPlusRecentQueLeLienGagneEtLeLienSertDeRepliSinon() {
        let taps = BoiteTapsPush()
        var aiguillage = AiguillageLiens(taps: taps)
        _ = aiguillage.recevoir(url: url("https://jolene.app/soignant/notifications"))
        taps.recevoir(PushTapIntent(donnees: ["type_evenement": "MISSION_A_POURVOIR"]))
        XCTAssertEqual(aiguillage.ouvrirEspace(snapshot(epoch: 1)), .naviguer(.explorer, route: .explorer, epoch: 1),
                       "tap reçu après le lien : il l'emporte")
        XCTAssertFalse(aiguillage.aUnLienEnAttente, "l'autre intention est consommée, jamais rejouée plus tard")

        let taps2 = BoiteTapsPush()
        aiguillage = AiguillageLiens(taps: taps2)
        taps2.recevoir(PushTapIntent(donnees: ["type_evenement": "MISSION_A_POURVOIR"]))
        _ = aiguillage.recevoir(url: url("https://jolene.app/soignant/notifications"))
        XCTAssertEqual(aiguillage.ouvrirEspace(snapshot(epoch: 1)), .naviguer(.centre, route: .notifications, epoch: 1),
                       "lien reçu après le tap : il l'emporte")
        XCTAssertFalse(taps2.aUnTapEnAttente)

        // Le plus récent ne mène nulle part (type inconnu sans lien) : repli sur l'autre intention.
        let taps3 = BoiteTapsPush()
        aiguillage = AiguillageLiens(taps: taps3)
        _ = aiguillage.recevoir(url: url("https://jolene.app/soignant/profil"))
        taps3.recevoir(PushTapIntent(donnees: ["type_evenement": "TYPE_INCONNU"]))
        XCTAssertEqual(aiguillage.ouvrirEspace(snapshot(epoch: 1)), .naviguer(.profil, route: .profil, epoch: 1))
    }

    /// Revue B8 de T3b, m8 : le plus récent (le tap) est écarté par la règle d'epoch de `BoiteTapsPush` (reçu pendant
    /// l'espace d'un autre epoch, que la boîte tient encore pour ouvert) ; le lien mémorisé sert de repli, et les deux
    /// sont consommés.
    func testTapPlusRecentEcarteParLEpochRepliSurLeLienMemorise() {
        let taps = BoiteTapsPush()
        let aiguillage = AiguillageLiens(taps: taps)
        _ = aiguillage.recevoir(url: url("https://jolene.app/soignant/parametres/notifications"))
        XCTAssertTrue(aiguillage.aUnLienEnAttente)
        // La boîte tient encore l'espace de l'epoch 1 pour ouvert : le tap reçu ensuite lui est lié.
        XCTAssertNil(taps.prendre(pour: snapshot(epoch: 1)))
        taps.recevoir(PushTapIntent(donnees: ["type_evenement": "MISSION_A_POURVOIR"]))
        XCTAssertTrue(taps.aUnTapEnAttente)
        XCTAssertEqual(aiguillage.ouvrirEspace(snapshot(epoch: 2)),
                       .naviguer(.preferences, route: .parametresNotifications, epoch: 2),
                       "tap plus récent, mais d'un autre epoch : écarté, le lien mémorisé est rejoué")
        XCTAssertFalse(taps.aUnTapEnAttente, "le tap écarté est consommé")
        XCTAssertFalse(aiguillage.aUnLienEnAttente, "le lien est consommé")
        aiguillage.fermerEspace(epoch: 2)
        XCTAssertNil(aiguillage.ouvrirEspace(snapshot(epoch: 3)), "rien n'est rejoué deux fois")
    }

    // MARK: - Argument DEBUG, descriptions

    func testArgumentDOuvertureSimulee() {
        XCTAssertEqual(DeepLinkIntent.argumentOuverture, "-JOLENE_OPEN_URL")
        XCTAssertEqual(DeepLinkIntent.ouvertureSimulee(arguments: ["Jolene", "-JOLENE_MODE", "demo", "-JOLENE_OPEN_URL",
                                                                   "https://jolene.app/soignant/notifications"]),
                       url("https://jolene.app/soignant/notifications"))
        XCTAssertEqual(DeepLinkIntent.ouvertureSimulee(arguments: ["-JOLENE_OPEN_URL",
                                                                   "https://jolene.app/inscription/confirmer?token_hash=h&type=signup"]),
                       url("https://jolene.app/inscription/confirmer?token_hash=h&type=signup"), "query conservée")
        XCTAssertNil(DeepLinkIntent.ouvertureSimulee(arguments: ["-JOLENE_OPEN_URL"]), "valeur absente")
        XCTAssertNil(DeepLinkIntent.ouvertureSimulee(arguments: ["-JOLENE_OPEN_URL", ""]), "valeur vide")
        XCTAssertNil(DeepLinkIntent.ouvertureSimulee(arguments: ["-JOLENE_MODE", "demo"]))
    }

    /// Revue B8 de T3b, m1 : `-JOLENE_OPEN_URL_SUIVANT <url>` (DEBUG, démo) — lien universel remis par le double démo
    /// du renvoi web (bouton `renvoi-web-lien-suivant`), pour prouver un lien reçu pendant qu'un renvoi est affiché.
    /// Distinct de `-JOLENE_OPEN_URL`, jamais confondu avec lui.
    func testArgumentDuLienSuivantSimule() {
        XCTAssertEqual(DeepLinkIntent.argumentLienSuivant, "-JOLENE_OPEN_URL_SUIVANT")
        let arguments = ["-JOLENE_OPEN_URL", "https://jolene.app/soignant/stripe-connect",
                         "-JOLENE_OPEN_URL_SUIVANT", "https://jolene.app/reset-password?code=demo"]
        XCTAssertEqual(DeepLinkIntent.lienSuivantSimule(arguments: arguments), url("https://jolene.app/reset-password?code=demo"))
        XCTAssertEqual(DeepLinkIntent.ouvertureSimulee(arguments: arguments), url("https://jolene.app/soignant/stripe-connect"))
        XCTAssertNil(DeepLinkIntent.lienSuivantSimule(arguments: ["-JOLENE_OPEN_URL", "https://jolene.app/soignant/stripe-connect"]))
        XCTAssertNil(DeepLinkIntent.lienSuivantSimule(arguments: ["-JOLENE_OPEN_URL_SUIVANT"]))
        XCTAssertNil(DeepLinkIntent.lienSuivantSimule(arguments: ["-JOLENE_OPEN_URL_SUIVANT", ""]))
    }

    private func textes(_ valeur: Any) -> [String] {
        [String(describing: valeur), String(reflecting: valeur), "\(valeur)"]
    }

    /// PRINCIPES §7 : une intention ne se décrit que par sa forme masquée (cas de route, gabarit du chemin) ; ni
    /// identifiant, ni jeton de rappel, ni query dans un journal ou un fil d'Ariane, `dump` compris.
    func testDescriptionMasquee() throws {
        let cas = [
            "https://jolene.app/reset-password?code=SECRET1",
            "https://jolene.app/reset-password?token_hash=SECRET2&type=recovery",
            "https://jolene.app/soignant/missions/SECRET3",
            "https://jolene.app/contrat/SECRET4",
            "https://jolene.app/inscription/completer?ref=SECRET5",
            "https://jolene.app/connexion?email=SECRET6",
        ]
        for lien in cas {
            let valeur = try intention(lien)
            var sortie = ""
            dump(valeur, to: &sortie)
            for texte in textes(valeur) + [sortie] {
                XCTAssertFalse(texte.contains("SECRET"), "\(lien) → \(texte)")
            }
            XCTAssertTrue(valeur.description.hasPrefix("DeepLinkIntent."), valeur.description)
        }
        XCTAssertEqual(DeepLinkIntent.reinitialisationRefusee.description, "DeepLinkIntent.reinitialisationRefusee")
        XCTAssertEqual(try intention("https://jolene.app/soignant/notifications").description,
                       "DeepLinkIntent.espace(DestinationLien(route: notifications, chemin: /soignant/notifications, destination: natif))")
        let confirmation = try XCTUnwrap(DestinationLien(url: url("https://jolene.app/inscription/confirmer?token_hash=SECRET9&type=signup")))
        let rapide = try XCTUnwrap(DestinationLien(url: url("https://jolene.app/inscription/soignant?ref=SECRET10")))
        for action in [AiguillageLiens.Action.naviguer(.mission(id: "SECRET7"), route: .missionDetail(id: "SECRET7"), epoch: 1),
                       .renvoiWeb(.safari(url("https://jolene.app/contrat/SECRET8"))),
                       .inscription(confirmation), .inscription(rapide)] {
            var sortie = ""
            dump(action, to: &sortie)
            for texte in textes(action) + [sortie] {
                XCTAssertFalse(texte.contains("SECRET"), texte)
            }
        }
    }

    // MARK: - Données

    /// Un lien par genre de route (même table que `CentreNotificationsTests.liensParGenre`), plus les formats de
    /// rappel du reset.
    private static let liensParGenre = [
        "/connexion", "/reset-password?token_hash=h&type=recovery", "/reset-password?code=c",
        "/reset-password#access_token=a&refresh_token=r&type=recovery", "/reset-password",
        "/inscription/confirmer?token_hash=h&type=signup", "/inscription/confirmer?code=c",
        "/inscription/soignant?profession=IDE", "/inscription/reprendre", "/inscription/completer?ref=ABCD-12",
        "/soignant/tableau-de-bord", "/soignant/recherche-missions", "/soignant/missions?tab=passees",
        "/soignant/missions/m-1", "/soignant/missions/serie/s-1",
        "/soignant/mes-gains", "/soignant/mes-gains?tab=factures", "/soignant/mes-gains?tab=bulletins",
        "/soignant/mes-gains?tab=avances", "/soignant/mes-gains?tab=paiements",
        "/soignant/mon-compte", "/soignant/profil", "/soignant/notifications", "/soignant/parametres/notifications",
        "/soignant/stripe-connect", "/soignant/stripe-connect?success=true", "/soignant/stripe-connect?refresh=true",
        "/soignant/litiges", "/etablissement/missions/abc",
    ]
}
