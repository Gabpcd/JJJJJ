import XCTest
@testable import JoleneCore

final class LinksRouterTests: XCTestCase {
    private func route(_ s: String) -> JoleneRoute? {
        LinkRouter.route(url: URL(string: s)!)
    }

    // MARK: Hôtes

    func testAccepteJoleneAppEtWwwSeulement() {
        XCTAssertEqual(route("https://jolene.app/connexion"), .connexion)
        XCTAssertEqual(route("https://www.jolene.app/connexion"), .connexion)
        XCTAssertEqual(route("https://JOLENE.APP/connexion"), .connexion)
        XCTAssertNil(route("https://app.jolene.app/connexion"), "hôte hors entitlements applinks")
        XCTAssertNil(route("https://evil.example/connexion"))
        XCTAssertNil(route("https://jolene.app.evil.example/connexion"))
        XCTAssertNil(route("http://jolene.app/connexion"))
        XCTAssertNil(route("https://jolene.app:444/connexion"))
        XCTAssertNil(route("https://evil.example/reset-password#access_token=x&refresh_token=y&type=recovery"))
    }

    // MARK: Un chemin par motif AASA, avec sa destination

    func testDestinationParMotifAASA() {
        XCTAssertEqual(route("https://jolene.app/soignant/tableau-de-bord"), .accueil)                      // /soignant/*
        XCTAssertEqual(route("https://jolene.app/etablissement/tableau-de-bord"),
                       .etablissement(URL(string: "https://jolene.app/etablissement/tableau-de-bord")!))     // /etablissement/*
        XCTAssertEqual(route("https://jolene.app/groupe/tableau-de-bord"),
                       .safari(URL(string: "https://jolene.app/groupe/tableau-de-bord")!))                  // /groupe/*
        XCTAssertEqual(route("https://www.jolene.app/admin/litiges#litige-id"),
                       .safari(URL(string: "https://jolene.app/admin/litiges#litige-id")!))                  // /admin/*
        XCTAssertEqual(route("https://jolene.app/connexion"), .connexion)                                   // /connexion
        XCTAssertEqual(route("https://jolene.app/inscription/confirmer?code=abc"),
                       .confirmerInscription(credentials: .pkce(code: "abc")))                              // /inscription/*
        XCTAssertEqual(route("https://jolene.app/reset-password?code=abc#type=recovery"),
                       .resetPassword(credentials: .pkce(code: "abc")))                                     // /reset-password
        XCTAssertEqual(route("https://jolene.app/auth/psc/callback?status=success&token_hash=x"),
                       .safari(URL(string: "https://jolene.app/auth/psc/callback?status=success&token_hash=x")!)) // PSC lot 3
        XCTAssertEqual(route("https://jolene.app/etab/invitation/token?source=email"),
                       .etablissement(URL(string: "https://jolene.app/etab/invitation/token?source=email")!)) // /etab/invitation/*
        XCTAssertEqual(route("https://jolene.app/mission/mission-id"), .missionDetail(id: "mission-id"))    // /mission/*
        XCTAssertEqual(route("https://jolene.app/contrat/contrat-id"),
                       .safari(URL(string: "https://jolene.app/contrat/contrat-id")!))                      // /contrat/* lot 2
        XCTAssertEqual(route("https://jolene.app/soignant/missions"), .missions)                            // /soignant/missions
        XCTAssertEqual(route("https://jolene.app/soignant/missions/mission-id"), .missionDetail(id: "mission-id")) // /soignant/missions/*
        XCTAssertEqual(route("https://jolene.app/etablissement/missions"),
                       .etablissement(URL(string: "https://jolene.app/etablissement/missions")!))           // /etablissement/missions
        XCTAssertEqual(route("https://jolene.app/etablissement/missions/abc/modifier"),
                       .etablissement(URL(string: "https://jolene.app/etablissement/missions/abc/modifier")!)) // /etablissement/missions/*
    }

    func testAdminEtGroupeVersSafariQuelleQueSoitLaProfondeur() {
        for path in ["/admin/", "/admin/reclamations?tab=score", "/groupe/x/y/z"] {
            let r = route("https://jolene.app" + path)
            XCTAssertEqual(r?.isNative, false, path)
            XCTAssertEqual(r?.externalURL?.host, "jolene.app", path)
            if case .safari = r {} else { XCTFail("attendu .safari pour \(path), reçu \(String(describing: r))") }
        }
    }

    func testCheminHorsAASAVersSafariSansCrash() {
        XCTAssertEqual(route("https://jolene.app/aide/pro-sante-connect"),
                       .safari(URL(string: "https://jolene.app/aide/pro-sante-connect")!))
        XCTAssertEqual(route("https://jolene.app/"), .safari(URL(string: "https://jolene.app/")!))
        XCTAssertEqual(route("https://jolene.app/soignant"), .safari(URL(string: "https://jolene.app/soignant")!))
    }

    // MARK: Reset : query et fragment conservés, trois formats

    func testResetConserveQueryEtFragmentDansLesTroisFormats() {
        XCTAssertEqual(route("https://jolene.app/reset-password?code=pkce"), .resetPassword(credentials: .pkce(code: "pkce")))
        XCTAssertEqual(route("https://jolene.app/reset-password?token_hash=hash&type=recovery"),
                       .resetPassword(credentials: .tokenHash(tokenHash: "hash", otpType: "recovery")))
        XCTAssertEqual(route("https://jolene.app/reset-password#access_token=access&refresh_token=refresh&type=recovery"),
                       .resetPassword(credentials: .implicit(accessToken: "access", refreshToken: "refresh")))
        XCTAssertEqual(route("https://jolene.app/reset-password"), .resetPassword(credentials: nil))
        XCTAssertEqual(route("https://jolene.app/reset-password#access_token=a&refresh_token=r"),
                       .resetPassword(credentials: nil), "session sans marqueur recovery refusée")
    }

    func testConfirmerInscriptionTroisFormats() {
        XCTAssertEqual(route("https://jolene.app/inscription/confirmer?token_hash=h&type=signup"),
                       .confirmerInscription(credentials: .tokenHash(tokenHash: "h", otpType: "signup")))
        XCTAssertEqual(route("https://jolene.app/inscription/confirmer#access_token=a&refresh_token=r&type=email"),
                       .confirmerInscription(credentials: .implicit(accessToken: "a", refreshToken: "r")))
        XCTAssertEqual(route("https://jolene.app/inscription/confirmer?code=c&type=recovery"),
                       .confirmerInscription(credentials: nil))
        XCTAssertEqual(route("https://jolene.app/inscription/soignant"),
                       .inscription(EtapeInscription(page: .soignant, query: nil)), "inscription lot 3 (T3)")
    }

    // MARK: Parcours soignant

    func testOngletsEtAlias() {
        XCTAssertEqual(route("https://jolene.app/soignant/recherche-missions?rayon=20"), .explorer)
        XCTAssertEqual(route("https://jolene.app/soignant/swipe-missions"), .explorer)
        XCTAssertEqual(route("https://jolene.app/soignant/missions/"), .missions, "barre oblique finale ignorée")
        XCTAssertEqual(route("https://jolene.app/soignant/missions?tab=passees"), .missions)
        XCTAssertEqual(route("https://jolene.app/soignant/planning"), .missions)
        XCTAssertEqual(route("https://jolene.app/soignant/historique-missions"), .missions)
        XCTAssertEqual(route("https://jolene.app/soignant/mes-gains?tab=factures"), .revenus(section: .factures))
        XCTAssertEqual(route("https://jolene.app/soignant/bulletins-paie"), .revenus(section: .bulletins))
        XCTAssertEqual(route("https://jolene.app/soignant/profil"), .profil)
        XCTAssertEqual(route("https://jolene.app/soignant/mon-compte"), .monCompte, "hub séparé de l'édition (lot 3, T3)")
        XCTAssertEqual(route("https://jolene.app/soignant/score"), .monCompte, "page score au lot 4 : hub en attendant")
    }

    func testDetailsMissionEtSerie() {
        XCTAssertEqual(route("https://jolene.app/soignant/missions/serie/serie-id"), .serieDetail(id: "serie-id"))
        XCTAssertEqual(route("https://jolene.app/soignant/missions/serie/serie-id/"), .serieDetail(id: "serie-id"))
        XCTAssertEqual(route("https://jolene.app/soignant/missions/abc%20d"), .missionDetail(id: "abc d"), "segment décodé")
        XCTAssertEqual(route("https://jolene.app/mission/abc?utm=x"), .missionDetail(id: "abc"))
        XCTAssertEqual(route("https://jolene.app/soignant/missions/serie"), .missionDetail(id: "serie"),
                       "sans identifiant de série, le web rend /soignant/missions/:id")
        XCTAssertEqual(route("https://jolene.app/soignant/missions/a/b"),
                       .safari(URL(string: "https://jolene.app/soignant/missions/a/b")!), "profondeur inconnue")
        XCTAssertEqual(route("https://jolene.app/soignant/presences/mission/abc"),
                       .safari(URL(string: "https://jolene.app/soignant/presences/mission/abc")!), "pointage lot 2")
    }

    func testTraversalNeContournePasLeRoutage() {
        XCTAssertEqual(route("https://jolene.app/soignant/../admin/litiges"),
                       .safari(URL(string: "https://jolene.app/admin/litiges")!))
    }

    // MARK: Liens internes (push, in-app)

    func testResolveLienInterneRelatifOuAbsolu() {
        XCTAssertEqual(LinkRouter.resolve(link: "/soignant/missions/mission-id"), .missionDetail(id: "mission-id"))
        XCTAssertEqual(LinkRouter.resolve(link: "https://app.jolene.app/soignant/mes-gains?tab=paiements"),
                       .revenus(section: .paiementsAConfirmer))
        XCTAssertEqual(LinkRouter.resolve(link: "/soignant/litiges#litige-id"),
                       .safari(URL(string: "https://jolene.app/soignant/litiges#litige-id")!))
        XCTAssertEqual(LinkRouter.resolve(link: "/"), .safari(URL(string: "https://jolene.app/")!))
        XCTAssertNil(LinkRouter.resolve(link: "https://evil.example/soignant/missions"))
        XCTAssertNil(LinkRouter.resolve(link: "soignant/missions"))
        XCTAssertNil(LinkRouter.resolve(link: ""))
    }

    func testProprietesDeRoute() {
        XCTAssertTrue(JoleneRoute.accueil.isNative)
        XCTAssertNil(JoleneRoute.accueil.externalURL)
        let url = URL(string: "https://jolene.app/etablissement/missions")!
        XCTAssertFalse(JoleneRoute.etablissement(url).isNative)
        XCTAssertEqual(JoleneRoute.etablissement(url).externalURL, url)
    }

    // MARK: Lot 3, T3 — routes soignant restantes (`src/App.tsx` l.283-292, l.313-341, l.393-418)

    /// Table complète des chemins soignant et d'inscription qui ont une destination dans l'app au
    /// lot 3 : chaque ligne est une route déclarée (ou un `Navigate`) de `src/App.tsx`.
    func testTableCompleteDesRoutesSoignantLot3() {
        let table: [(String, JoleneRoute)] = [
            // Centre et préférences de notifications (l.335, l.341).
            ("/soignant/notifications", .notifications),
            ("/soignant/parametres/notifications", .parametresNotifications),
            // Stripe Connect (l.339) : retour de `return_url` / `refresh_url` (`stripe-connect-onboard` l.202-203).
            ("/soignant/stripe-connect", .stripeConnect(retour: nil)),
            ("/soignant/stripe-connect?success=true", .stripeConnect(retour: .succes)),
            ("/soignant/stripe-connect?refresh=true", .stripeConnect(retour: .rafraichir)),
            // Inscription (l.286, l.290, l.291).
            ("/inscription/soignant", .inscription(EtapeInscription(page: .soignant, query: nil))),
            ("/inscription/reprendre", .inscription(EtapeInscription(page: .reprendre, query: nil))),
            ("/inscription/completer", .inscription(EtapeInscription(page: .completer, query: nil))),
            // Revenus (l.325) et ses alias `Navigate` (l.395-397).
            ("/soignant/mes-gains", .revenus(section: .apercu)),
            ("/soignant/mes-gains?tab=apercu", .revenus(section: .apercu)),
            ("/soignant/mes-gains?tab=factures", .revenus(section: .factures)),
            ("/soignant/mes-gains?tab=bulletins", .revenus(section: .bulletins)),
            ("/soignant/mes-gains?tab=avances", .revenus(section: .avances)),
            ("/soignant/mes-gains?tab=paiements", .revenus(section: .paiementsAConfirmer)),
            ("/soignant/mes-factures-honoraires", .revenus(section: .factures)),
            ("/soignant/mes-avances", .revenus(section: .avances)),
            ("/soignant/bulletins-paie", .revenus(section: .bulletins)),
            // Édition du profil (l.313) et son alias `reputation` (l.393).
            ("/soignant/profil", .profil),
            ("/soignant/reputation", .profil),
            // Hub du compte (l.314) et ses alias (l.417-418) ; score et fiabilité (l.327, l.399-400) restent
            // sur le hub tant que la page score est au lot 4.
            ("/soignant/mon-compte", .monCompte),
            ("/soignant/parametres", .monCompte),
            ("/soignant/parametres-complet", .monCompte),
            ("/soignant/score", .monCompte),
            ("/soignant/fiabilite", .monCompte),
            ("/soignant/fiabilite-legacy", .monCompte),
        ]
        for (chemin, attendu) in table {
            XCTAssertEqual(route("https://jolene.app" + chemin), attendu, "Universal Link \(chemin)")
            XCTAssertEqual(route("https://www.jolene.app" + chemin), attendu, "www \(chemin)")
            XCTAssertEqual(LinkRouter.resolve(link: chemin), attendu, "lien interne \(chemin)")
            XCTAssertEqual(LinkRouter.resolve(link: "https://app.jolene.app" + chemin), attendu, "hôte web de confiance \(chemin)")
            XCTAssertTrue(attendu.isNative, "\(chemin) : destination de l'app")
            XCTAssertNil(attendu.externalURL, chemin)
        }
    }

    func testRoutesLot3ToleresBarreFinaleFragmentEtQueryEtrangere() {
        XCTAssertEqual(route("https://jolene.app/soignant/notifications/"), .notifications)
        XCTAssertEqual(route("https://jolene.app/soignant/notifications?utm_source=email#haut"), .notifications)
        XCTAssertEqual(route("https://jolene.app/soignant/parametres/notifications/"), .parametresNotifications)
        XCTAssertEqual(route("https://jolene.app/soignant/mon-compte/"), .monCompte)
        XCTAssertEqual(route("https://jolene.app/soignant/parametres/"), .monCompte)
        XCTAssertEqual(route("https://jolene.app/soignant/profil?tab=principal"), .profil)
    }

    /// L3-T3b (point de fusion de la revue L3-T9, m2, tranché) : l'onglet « Confidentialité » du profil web
    /// (`ProfilSoignant.tsx` l.42-44 et l.505-507, `SectionConfidentialite` : export RGPD et suppression de compte ;
    /// entrée « Supprimer mon compte » du hub web vers `?tab=confidentialite#suppression-compte`,
    /// `MonCompteSoignant.tsx` l.135) mène au hub natif, qui porte la suppression (L1-T8) et l'export (L3-T11) ; les
    /// autres onglets, `?tab=` absent ou inconnu compris, mènent à l'édition. Comparaison exacte, comme le web.
    func testOngletConfidentialiteDuProfilMeneAuHub() {
        XCTAssertEqual(route("https://jolene.app/soignant/profil?tab=confidentialite"), .monCompte)
        XCTAssertEqual(route("https://jolene.app/soignant/profil?tab=confidentialite#suppression-compte"), .monCompte)
        XCTAssertEqual(route("https://jolene.app/soignant/profil/?x=1&tab=confidentialite"), .monCompte)
        XCTAssertEqual(LinkRouter.resolve(link: "/soignant/profil?tab=confidentialite"), .monCompte)
        for query in ["", "?tab=principal", "?tab=preferences", "?tab=Confidentialite", "?tab=inconnu", "?onglet=confidentialite"] {
            XCTAssertEqual(route("https://jolene.app/soignant/profil" + query), .profil, query)
        }
        XCTAssertEqual(route("https://jolene.app/soignant/reputation?tab=confidentialite"), .profil, "alias : redirection web vers le profil sans query")
    }

    func testCheminsSoignantSansEcranLot3RestentSafariAvecQueryEtFragment() {
        for chemin in ["/soignant/notifications/abc", "/soignant/parametres/recherches-sauvegardees",
                       "/soignant/litiges?tab=reclamations#l%201", "/soignant/mes-documents?tab=contrats",
                       "/soignant/stripe-connect/retour", "/soignant/mes-gains/factures", "/soignant/Notifications"] {
            XCTAssertEqual(route("https://www.jolene.app" + chemin), .safari(URL(string: "https://jolene.app" + chemin)!), chemin)
        }
    }

    /// `?success=` lu comme `searchParams.get('success') === 'true'` (`PageStripeConnect.tsx` l.28) :
    /// valeur exacte, première occurrence, décodage `x-www-form-urlencoded`. `?refresh=` vient de la
    /// `refresh_url` de `stripe-connect-onboard/index.ts` l.202 ; le web ne le lit jamais :
    /// `RetourConnect.rafraichir` est un ajout natif, lu avec la même règle.
    func testRetourStripeConnectStrict() {
        let cas: [(String, RetourConnect?)] = [
            ("", nil),
            ("?success=true", .succes),
            ("?refresh=true", .rafraichir),
            ("?success=true&refresh=true", .succes),
            ("?refresh=true&success=true", .succes),
            ("?success=false&refresh=true", .rafraichir),
            ("?success=1", nil),
            ("?success=TRUE", nil),
            ("?success=", nil),
            ("?success", nil),
            ("?success=tru%65", .succes),
            ("?success=true&success=false", .succes),
            ("?success=false&success=true", nil),
            ("?refresh=yes", nil),
            ("#success=true", nil),
        ]
        for (suffixe, attendu) in cas {
            XCTAssertEqual(route("https://jolene.app/soignant/stripe-connect" + suffixe), .stripeConnect(retour: attendu),
                           "stripe-connect\(suffixe)")
        }
    }

    /// La query de l'inscription est conservée telle quelle (encodage compris) : `profession`/`ville`
    /// (`InscriptionRapide.tsx` l.35-42) et `ref`/`parrain` (`InscriptionSoignant.tsx` l.109-117, lot 4).
    func testInscriptionConserveLaQuery() throws {
        let rapide = try XCTUnwrap(route("https://jolene.app/inscription/soignant?profession=IDE&ville=Saint+%C3%89tienne"))
        guard case .inscription(let etape) = rapide else { return XCTFail("attendu .inscription, reçu \(rapide)") }
        XCTAssertEqual(etape.page, .soignant)
        XCTAssertEqual(etape.query, "profession=IDE&ville=Saint+%C3%89tienne")
        XCTAssertEqual(etape.parametre("profession"), "IDE")
        XCTAssertEqual(etape.parametre("ville"), "Saint Étienne")
        XCTAssertNil(etape.parametre("ref"))

        let parrainage = try XCTUnwrap(route("https://www.jolene.app/inscription/completer?ref=ABCD-12&ref=ZZZZ#ancre"))
        XCTAssertEqual(parrainage, .inscription(EtapeInscription(page: .completer, query: "ref=ABCD-12&ref=ZZZZ")),
                       "fragment écarté, query intacte")
        if case .inscription(let etape) = parrainage {
            XCTAssertEqual(etape.parametre("ref"), "ABCD-12", "première occurrence, comme URLSearchParams.get")
        }
        XCTAssertEqual(LinkRouter.resolve(link: "/inscription/reprendre?parrain=XY12"),
                       .inscription(EtapeInscription(page: .reprendre, query: "parrain=XY12")))
        XCTAssertEqual(route("https://jolene.app/inscription/reprendre/"),
                       .inscription(EtapeInscription(page: .reprendre, query: nil)))
        XCTAssertNil(EtapeInscription(page: .soignant, query: nil).parametre("ville"))
    }

    /// Hors périmètre du lot 3 : PSC (D8), établissement, page de succès, profondeur inconnue.
    func testInscriptionHorsPerimetreResteSafari() {
        for chemin in ["/inscription/etablissement?source=landing", "/inscription/soignant/completion?code=x",
                       "/inscription/succes", "/inscription/soignant/x", "/inscription/Soignant",
                       "/auth/psc/callback?status=success&token_hash=x"] {
            XCTAssertEqual(route("https://jolene.app" + chemin), .safari(URL(string: "https://jolene.app" + chemin)!), chemin)
        }
    }

    /// `?tab=` lu comme `MesGains.tsx` l.899-900 (`TABS_FINANCES.includes(tab) ? tab : 'apercu'`), plus
    /// `paiements` (push `PAIEMENT_RECU`, correction 15) → section « Paiements à confirmer ».
    func testSectionRevenusDepuisTab() {
        let cas: [(String, SectionRevenus)] = [
            ("", .apercu),
            ("?tab=", .apercu),
            ("?tab=xyz", .apercu),
            ("?tab=Factures", .apercu),
            ("?tab=%20factures", .apercu),
            ("?tab=fac%74ures", .factures),
            ("?tab=factures&tab=avances", .factures),
            ("?onglet=factures", .apercu),
            ("?mois=2026-11&tab=bulletins", .bulletins),
            ("?tab=paiements#ligne", .paiementsAConfirmer),
            ("#tab=factures", .apercu),
        ]
        for (suffixe, attendu) in cas {
            XCTAssertEqual(route("https://jolene.app/soignant/mes-gains" + suffixe), .revenus(section: attendu), "mes-gains\(suffixe)")
        }
        XCTAssertEqual(SectionRevenus.allCases.map(\.rawValue), ["apercu", "factures", "bulletins", "avances", "paiements"])
        XCTAssertEqual(route("https://jolene.app/soignant/mes-avances?tab=apercu"), .revenus(section: .avances),
                       "alias : la redirection web (`Navigate`) fixe l'onglet")
    }
}
