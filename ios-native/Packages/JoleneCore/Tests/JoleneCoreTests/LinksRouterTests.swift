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
                       .safari(URL(string: "https://jolene.app/inscription/soignant")!), "inscription lot 3")
    }

    // MARK: Parcours soignant

    func testOngletsEtAlias() {
        XCTAssertEqual(route("https://jolene.app/soignant/recherche-missions?rayon=20"), .explorer)
        XCTAssertEqual(route("https://jolene.app/soignant/swipe-missions"), .explorer)
        XCTAssertEqual(route("https://jolene.app/soignant/missions/"), .missions, "barre oblique finale ignorée")
        XCTAssertEqual(route("https://jolene.app/soignant/missions?tab=passees"), .missions)
        XCTAssertEqual(route("https://jolene.app/soignant/planning"), .missions)
        XCTAssertEqual(route("https://jolene.app/soignant/historique-missions"), .missions)
        XCTAssertEqual(route("https://jolene.app/soignant/mes-gains?tab=factures"), .revenus)
        XCTAssertEqual(route("https://jolene.app/soignant/bulletins-paie"), .revenus)
        XCTAssertEqual(route("https://jolene.app/soignant/profil"), .profil)
        XCTAssertEqual(route("https://jolene.app/soignant/mon-compte"), .profil)
        XCTAssertEqual(route("https://jolene.app/soignant/score"), .profil)
        // Lot 1, T4b : « Mes favoris » est natif (onglet Explorer).
        XCTAssertEqual(route("https://jolene.app/soignant/mes-favoris"), .favoris)
        XCTAssertEqual(route("https://www.jolene.app/soignant/mes-favoris/"), .favoris)
        XCTAssertEqual(LinkRouter.resolve(link: "/soignant/mes-favoris?onglet=etablissements"), .favoris)
        XCTAssertTrue(JoleneRoute.favoris.isNative)
        XCTAssertNil(JoleneRoute.favoris.externalURL)
        XCTAssertEqual(route("https://jolene.app/etablissement/mes-favoris"),
                       .etablissement(URL(string: "https://jolene.app/etablissement/mes-favoris")!), "favoris établissement : lot 5")
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
        XCTAssertEqual(LinkRouter.resolve(link: "https://app.jolene.app/soignant/mes-gains?tab=paiements"), .revenus)
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
}
