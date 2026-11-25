import XCTest
@testable import JoleneCore

/// Compte minimal et renvois web de l'espace établissement (lot 5, T12 ; `docs/mobile-swift/LOT5_PLAN.md` §3 T12,
/// §2.7, D16, D17) : table unique `clé → chemin` des pages servies par jolene.app.
///
/// Ce que ces tests prouvent (niveau 1) :
/// - chaque clé mène à un chemin déclaré dans `src/App.tsx` (route ou redirection `Navigate`) ;
/// - un chemin `/etablissement/*` est couvert par l'AASA de l'app (jamais `openURL` : il reviendrait dans l'app par
///   lien universel), une page légale ne l'est pas : toutes passent par le présentateur `.safari` du coordinateur ;
/// - un renvoi est un lien constant : ni jeton, ni identifiant de session, ni donnée personnelle dans l'URL ;
/// - une entrée réservée à une permission est masquée quand le serveur ne l'accorde pas (booléens de
///   `fn_mes_permissions_etab`, fixture générée depuis le `CASE` SQL) ; aucune correspondance rôle → permission ici ;
/// - les libellés sont ceux du menu web (`MonCompteEtablissement.tsx`) ; les deux qui n'y figurent pas sont nommés.
final class RenvoisWebEtabTests: XCTestCase {
    private typealias Cle = RenvoisWebEtab.Cle

    private let prive = EtablissementProfil(id: "etab-1", nom: "Clinique", estSecteurPublic: false)
    private let secteurPublic = EtablissementProfil(id: "etab-1", nom: "Hôpital", estSecteurPublic: true)
    private let toutesPermissions = PermissionsEtab(accordees: Set(PermissionEtab.allCases))

    private func cles(_ profil: EtablissementProfil, _ permissions: PermissionsEtab) -> [String] {
        RenvoisWebEtab.visibles(profil: profil, permissions: permissions).map(\.cle.rawValue)
    }

    // MARK: - Table

    func testTableCleCheminLibelleDansLOrdreDuMenu() {
        let attendue: [(String, String, String)] = [
            ("soignants", "/etablissement/soignants", "Annuaire des soignants"),
            ("mes-favoris", "/etablissement/mes-favoris", "Soignants favoris"),
            ("pool-urgence", "/etablissement/pool-urgence", "Pool urgence"),
            ("evaluations-a-faire", "/etablissement/evaluations-a-faire", "Évaluer vos soignants"),
            ("equipe", "/etablissement/equipe", "Gérer mon équipe"),
            ("rh", "/etablissement/rh", "Pilotage RH & statistiques"),
            ("export-paie", "/etablissement/export-paie", "Export paie"),
            ("score", "/etablissement/score", "Score qualité"),
            ("parrainage", "/etablissement/parrainage", "Parrainage"),
            ("premium", "/etablissement/premium", "Offre Premium"),
            ("parametres", "/etablissement/parametres?tab=profil", "Mon établissement"),
            ("facturation", "/etablissement/facturation", "Mes factures"),
            ("sepa", "/etablissement/facturation", "Prélèvement SEPA"),
            ("chorus-config", "/etablissement/chorus-config", "Configuration Chorus Pro"),
            ("litiges", "/etablissement/litiges", "Litiges & contestations"),
            ("notifications", "/etablissement/notifications", "Notifications"),
            ("api", "/etablissement/api", "API REST Jolene"),
            ("aide", "/aide", "Centre d'aide"),
            ("confidentialite", "/confidentialite", "Confidentialité"),
            ("cgu", "/cgu", "CGU"),
            ("cgv", "/cgv", "CGV"),
            ("mentions-legales", "/mentions-legales", "Mentions légales"),
            ("supprimer", "/etablissement/parametres?tab=securite#suppression-compte", "Supprimer mon compte"),
        ]
        XCTAssertEqual(RenvoisWebEtab.table.map(\.cle.rawValue), attendue.map(\.0))
        XCTAssertEqual(RenvoisWebEtab.table.map(\.chemin), attendue.map(\.1))
        XCTAssertEqual(RenvoisWebEtab.table.map(\.libelle), attendue.map(\.2))
    }

    func testUneEntreeParCleIdentifiantEtUrlCanonique() {
        XCTAssertEqual(RenvoisWebEtab.table.map(\.cle), Cle.allCases, "une entrée par clé, dans l'ordre des clés")
        XCTAssertEqual(Set(RenvoisWebEtab.table.map(\.identifiant)).count, RenvoisWebEtab.table.count)
        for entree in RenvoisWebEtab.table {
            XCTAssertEqual(entree.identifiant, "etab-compte-web-\(entree.cle.rawValue)")
            XCTAssertEqual(entree.id, entree.cle.rawValue)
            XCTAssertEqual(entree.url.absoluteString, "https://jolene.app\(entree.chemin)")
            XCTAssertEqual(RenvoisWebEtab.entree(entree.cle), entree)
            XCTAssertFalse(entree.libelle.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        // Critère de sortie du plan : facturation, SEPA, Chorus, RH, export paie, équipe, API.
        for cle in [Cle.facturation, .sepa, .chorusConfig, .rh, .exportPaie, .equipe, .api] {
            XCTAssertTrue(RenvoisWebEtab.table.contains { $0.cle == cle }, cle.rawValue)
        }
    }

    /// Chemins `path="…"` des `<Route>` de `src/App.tsx` (routes et redirections `Navigate`).
    private func routesDuWeb() throws -> Set<String> {
        let source = try SourceWebLot5.lire("src/App.tsx")
        let motif = try NSRegularExpression(pattern: #"<Route path="([^"]+)""#)
        let ns = source as NSString
        let chemins = motif.matches(in: source, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range(at: 1)) }
        XCTAssertGreaterThan(chemins.count, 100, "routes de App.tsx illisibles")
        return Set(chemins)
    }

    func testChaqueCheminEstUneRouteDeclareeDansAppTsx() throws {
        let routes = try routesDuWeb()
        for entree in RenvoisWebEtab.table {
            XCTAssertTrue(routes.contains(entree.cheminSeul), "\(entree.cle.rawValue) : \(entree.cheminSeul) absent de src/App.tsx")
        }
        XCTAssertEqual(RenvoisWebEtab.entree(.supprimer).cheminSeul, "/etablissement/parametres")
        XCTAssertEqual(RenvoisWebEtab.entree(.parametres).cheminSeul, "/etablissement/parametres")
    }

    func testCheminsEtablissementCouvertsParLAASAPagesLegalesNon() {
        let legales: Set<Cle> = [.aide, .confidentialite, .cgu, .cgv, .mentionsLegales]
        for entree in RenvoisWebEtab.table {
            let couvert = AASAPatterns.firstMatch(path: entree.cheminSeul) != nil
            if legales.contains(entree.cle) {
                XCTAssertFalse(couvert, "\(entree.cheminSeul) : page légale hors AASA")
                XCTAssertEqual(entree.route, .safari(entree.url), entree.cle.rawValue)
            } else {
                XCTAssertTrue(entree.cheminSeul.hasPrefix("/etablissement/"), entree.cheminSeul)
                XCTAssertEqual(AASAPatterns.firstMatch(path: entree.cheminSeul)?.pattern, "/etablissement/*", entree.cheminSeul)
                XCTAssertEqual(entree.route, .etablissement(entree.url), entree.cle.rawValue)
            }
            // Jamais une route native : le présentateur `.safari` ne présente qu'une route externe.
            XCTAssertFalse(entree.route.isNative)
            XCTAssertEqual(entree.route.externalURL, entree.url)
        }
    }

    /// La table des liens de l'espace (T2b) rend un renvoi web de la même URL : aucune entrée ne double un écran natif.
    /// Une page devenue native quitte cette table (ce test rougit).
    func testChaqueEntreeEstUnRenvoiWebPourLaTableDesLiens() throws {
        for entree in RenvoisWebEtab.table {
            let resultat = try XCTUnwrap(LinkRouter.etablissementDestination(link: entree.chemin), entree.chemin)
            XCTAssertEqual(resultat.route, .safari(entree.url), entree.cle.rawValue)
            XCTAssertEqual(resultat.route.presentation(canonique: resultat.canonique), .renvoiWeb(entree.url), entree.cle.rawValue)
        }
    }

    func testUnRenvoiEstUnLienConstantSansJetonNiDonneePersonnelle() throws {
        let queriesPermises: Set<String> = ["tab=profil", "tab=securite"]
        for entree in RenvoisWebEtab.table {
            let composants = try XCTUnwrap(URLComponents(url: entree.url, resolvingAgainstBaseURL: false))
            XCTAssertEqual(composants.scheme, "https")
            XCTAssertEqual(composants.host, "jolene.app")
            XCTAssertNil(composants.port)
            XCTAssertNil(composants.user)
            XCTAssertNil(composants.password)
            if let query = composants.percentEncodedQuery { XCTAssertTrue(queriesPermises.contains(query), "\(entree.cle.rawValue) : ?\(query)") }
            if let fragment = composants.percentEncodedFragment { XCTAssertEqual(fragment, "suppression-compte", entree.cle.rawValue) }
            // Segments littéraux : aucun identifiant (uuid, email), aucun encodage pourcent.
            XCTAssertNil(composants.path.range(of: "[^a-z/-]", options: .regularExpression), "\(entree.cle.rawValue) : \(composants.path)")
        }
        // Même table quels que soient l'utilisateur et l'établissement : seuls la présence des entrées en dépend.
        let autre = EtablissementProfil(id: "8f9a1c52-0000-4000-8000-000000000001", nom: "Autre", estSecteurPublic: false)
        XCTAssertEqual(RenvoisWebEtab.visibles(profil: autre, permissions: toutesPermissions).map(\.url),
                       RenvoisWebEtab.visibles(profil: prive, permissions: toutesPermissions).map(\.url))
    }

    // MARK: - Permissions servies (§2.7, fail-closed)

    func testEntreesVisiblesParRoleServi() throws {
        let fichier = try DemoFixtures.loadPermissionsEtab()
        func visibles(_ role: RoleEtab) throws -> Set<String> {
            Set(cles(prive, try XCTUnwrap(fichier.roles[role.brut])))
        }
        let sansCondition: Set<String> = ["soignants", "mes-favoris", "pool-urgence", "rh", "export-paie", "score", "parrainage",
                                          "premium", "parametres", "notifications", "api", "aide", "confidentialite", "cgu",
                                          "cgv", "mentions-legales", "supprimer"]
        let finances: Set<String> = ["facturation", "sepa"]
        let missions: Set<String> = ["evaluations-a-faire", "litiges"]
        XCTAssertEqual(try visibles(.proprietaire), sansCondition.union(finances).union(missions).union(["equipe"]))
        XCTAssertEqual(try visibles(.adminGroupe), sansCondition.union(finances).union(missions),
                       "ADMIN_GROUPE : pas d'équipe sans gerer_equipe")
        XCTAssertEqual(try visibles(.rh), sansCondition.union(missions), "RH : ni équipe, ni finances")
        XCTAssertEqual(try visibles(.pointageOnly), sansCondition, "POINTAGE_ONLY : aucune entrée réservée")
        XCTAssertEqual(try visibles(.lectureSeule), sansCondition.union(finances), "LECTURE_SEULE : lecture_paiement seulement")
        XCTAssertEqual(Set(cles(prive, .aucune)), sansCondition, "aucune permission : entrées sans condition seulement")
    }

    func testChaquePermissionOuvreSesSeulesEntrees() {
        func ajoutees(_ permission: PermissionEtab) -> Set<String> {
            Set(cles(prive, PermissionsEtab(accordees: [permission]))).subtracting(cles(prive, .aucune))
        }
        XCTAssertEqual(ajoutees(.gererEquipe), ["equipe"], "§2.7 : lien web Équipe sous gerer_equipe")
        XCTAssertEqual(ajoutees(.lecturePaiement), ["facturation", "sepa"])
        XCTAssertEqual(ajoutees(.paiement), ["facturation", "sepa"], "lecture_paiement ∨ paiement, comme le web (canReadFinance)")
        XCTAssertEqual(ajoutees(.missions), ["evaluations-a-faire", "litiges"], "même choix que l'Accueil (T4)")
        for permission in [PermissionEtab.supprimerCompte, .profilEtab, .candidatures, .contrats, .pointage, .rh, .lecture] {
            XCTAssertEqual(ajoutees(permission), [], permission.rawValue)
        }
    }

    func testSuppressionDuCompteLienDirectVisibleDeToutMembre() {
        let supprimer = RenvoisWebEtab.entree(.supprimer)
        XCTAssertEqual(supprimer.url.absoluteString, "https://jolene.app/etablissement/parametres?tab=securite#suppression-compte", "D17")
        XCTAssertEqual(supprimer.condition, .toutMembre, "aucune permission exigée : la page web et l'edge décident")
        XCTAssertTrue(cles(prive, .aucune).contains("supprimer"))
        XCTAssertTrue(cles(prive, PermissionsEtab(accordees: [.lecture])).contains("supprimer"),
                      "visible sans supprimer_compte (parité du web, Apple 5.1.1(v))")
    }

    func testChorusSeulementPourUnSecteurPublicServiEtSousFinances() {
        XCTAssertFalse(cles(prive, toutesPermissions).contains("chorus-config"))
        XCTAssertTrue(cles(secteurPublic, toutesPermissions).contains("chorus-config"))
        XCTAssertTrue(cles(secteurPublic, PermissionsEtab(accordees: [.lecturePaiement])).contains("chorus-config"))
        XCTAssertFalse(cles(secteurPublic, PermissionsEtab(accordees: [.missions, .gererEquipe])).contains("chorus-config"),
                       "secteur public sans lecture des finances : masqué")
        let inconnu = EtablissementProfil(id: "etab-1", nom: "Clinique", estSecteurPublic: nil)
        XCTAssertFalse(cles(inconnu, toutesPermissions).contains("chorus-config"), "valeur non servie : masqué (fail-closed)")
    }

    func testSectionsDansLOrdreDuMenuWebJamaisVides() throws {
        let sections = RenvoisWebEtab.sections(profil: secteurPublic, permissions: toutesPermissions)
        XCTAssertEqual(sections.map(\.section), [.activite, .equipePilotage, .gestion, .aideLegal])
        XCTAssertEqual(sections.map(\.section.titre), ["Activité", "Équipe & pilotage", nil, "Aide & légal"])
        XCTAssertEqual(sections.map { $0.entrees.map(\.cle.rawValue) }, [
            ["soignants", "mes-favoris", "pool-urgence", "evaluations-a-faire"],
            ["equipe", "rh", "export-paie", "score", "parrainage", "premium"],
            ["parametres", "facturation", "sepa", "chorus-config", "litiges", "notifications", "api"],
            ["aide", "confidentialite", "cgu", "cgv", "mentions-legales", "supprimer"],
        ])
        XCTAssertEqual(sections.flatMap(\.entrees), RenvoisWebEtab.table, "ordre de la table conservé")
        XCTAssertEqual(Set(sections.map(\.id)).count, sections.count)
        // Aucune section ne disparaît : chacune garde au moins une entrée sans condition.
        XCTAssertEqual(RenvoisWebEtab.sections(profil: prive, permissions: .aucune).map(\.section),
                       [.activite, .equipePilotage, .gestion, .aideLegal])
    }

    // MARK: - Sources des libellés

    /// Libellé et route d'une ligne du menu web (`{ icone: …, label: '…', route: '…' }`), apostrophe échappée comme
    /// dans la source.
    private func ligneDuMenu(_ entree: RenvoisWebEtab.Entree) -> String {
        "label: '\(entree.libelle.replacingOccurrences(of: "'", with: "\\'"))', route: '\(entree.chemin)'"
    }

    func testLibellesEtRoutesReprisDuMenuWeb() throws {
        let duMenu: [Cle] = [.soignants, .mesFavoris, .poolUrgence, .equipe, .rh, .exportPaie, .score, .parrainage, .premium,
                             .parametres, .facturation, .litiges, .aide, .confidentialite, .cgu, .cgv, .mentionsLegales,
                             .supprimer]
        try SourceWebLot5.verifier("src/pages/MonCompteEtablissement.tsx",
                                   contient: duMenu.map { ligneDuMenu(RenvoisWebEtab.entree($0)) })
        // Titres de section, « Notifications » (même libellé, page du centre de notifications) et déconnexion.
        try SourceWebLot5.verifier("src/pages/MonCompteEtablissement.tsx", contient: [
            "titre: 'Activité'", "titre: 'Équipe & pilotage'", "titre: 'Aide & légal'",
            "label: '\(RenvoisWebEtab.entree(.notifications).libelle)'",
            "label: '\(EtabComptePresentation.seDeconnecter)'",
            "titre={etab?.nom || '\(EtabComptePresentation.nomParDefaut)'}",
        ])
        XCTAssertEqual(RenvoisWebEtab.Section.allCases.compactMap(\.titre), ["Activité", "Équipe & pilotage", "Aide & légal"])
        // Pages hors du menu : titre de la page web.
        try SourceWebLot5.verifier("src/pages/ChorusConfig.tsx",
                                   contient: ["usePageTitle('\(RenvoisWebEtab.entree(.chorusConfig).libelle)')"])
        try SourceWebLot5.verifier("src/pages/APIEtablissement.tsx", contient: [RenvoisWebEtab.entree(.api).libelle])
    }

    /// Deux libellés ne viennent pas d'une ligne du menu web : ils sont nommés ici pour ne jamais passer inaperçus.
    func testLibellesHorsDuMenuWebNommes() {
        XCTAssertEqual(RenvoisWebEtab.libellesNatifs, [.evaluationsAFaire, .sepa])
        // Libellé neutre déjà retenu pour l'Accueil (intégration de la vague C, `DECISIONS_LOT5.md`).
        XCTAssertEqual(RenvoisWebEtab.entree(.evaluationsAFaire).libelle, PrioriteActions.Textes.evaluationsTitre)
        // Libellé de navigation : le plan demande un renvoi « SEPA » que le menu web ne nomme pas.
        XCTAssertEqual(RenvoisWebEtab.entree(.sepa).libelle, "Prélèvement SEPA")
        XCTAssertEqual(RenvoisWebEtab.entree(.sepa).chemin, RenvoisWebEtab.entree(.facturation).chemin)
    }

    func testTableUniqueCoherenteAvecLesRenvoisDesAutresTranches() {
        XCTAssertEqual(PrioriteActions.Chemins.facturation, RenvoisWebEtab.entree(.facturation).chemin)
        XCTAssertEqual(PrioriteActions.Chemins.litiges, RenvoisWebEtab.entree(.litiges).chemin)
        XCTAssertEqual(PrioriteActions.Chemins.evaluations, RenvoisWebEtab.entree(.evaluationsAFaire).chemin)
        XCTAssertEqual(CandidaturesEtabPresentation.urlFacturation, RenvoisWebEtab.entree(.facturation).url)
    }

    // MARK: - Matrice de parité

    /// Routes « renvoi web assumé » que la matrice attribue à T12 sans entrée dans le Compte : pages absentes du menu
    /// web, atteintes depuis leur page parente, et page d'activation ouverte par l'Accueil (T4).
    private let horsDuMenu: [String: String] = [
        "/etablissement/mes-reclamations": "atteinte depuis les litiges",
        "/etablissement/reclamations": "redirection vers /etablissement/litiges?tab=reclamations",
        "/etablissement/activer": "action « vérification » de l'Accueil (T4)",
        "/etablissement/parametres/notifications": "atteinte depuis les paramètres",
        "/etablissement/parametres/recherches-sauvegardees": "atteinte depuis les paramètres",
    ]

    func testRoutesDeLaMatriceAttribueesAT12() throws {
        let doc = try SourceWebLot5.lire("docs/mobile-swift/PARITE_ETABLISSEMENT.md")
        let routes = try routesDuWeb()
        let chemins = Set(RenvoisWebEtab.table.map(\.cheminSeul))
        var attribuees: [String] = []
        for ligne in doc.split(separator: "\n").map(String.init) where ligne.hasPrefix("| `/") {
            let colonnes = ligne.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            guard colonnes.count > 5, colonnes[4].hasPrefix("renvoi web assumé"),
                  colonnes[5].split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }).contains("T12"),
                  let fin = colonnes[1].dropFirst().firstIndex(of: "`") else { continue }
            let chemin = String(colonnes[1].dropFirst()[..<fin])
            attribuees.append(chemin)
            XCTAssertTrue(routes.contains(chemin), "\(chemin) absent de src/App.tsx")
            XCTAssertEqual(try XCTUnwrap(LinkRouter.etablissementDestination(link: chemin)).route,
                           .safari(try XCTUnwrap(URL(string: "https://jolene.app\(chemin)"))), chemin)
            XCTAssertTrue(chemins.contains(chemin) != (horsDuMenu[chemin] != nil),
                          "\(chemin) : une entrée de la table, ou une absence motivée, jamais les deux ni aucune")
        }
        XCTAssertEqual(attribuees.count, 21, "routes en renvoi web attribuées à T12 par la matrice")
        XCTAssertEqual(Set(horsDuMenu.keys).subtracting(attribuees), [], "absence motivée d'une route que la matrice ne confie pas à T12")
    }
}

/// Identité affichée par le Compte et déconnexion (lot 5, T12) : le rôle est celui que sert
/// `fn_mes_permissions_etab`, jamais déduit du JWT ni du rôle d'application ; la déconnexion est une frontière
/// d'identité (epoch + 1).
final class EtabCompteTests: XCTestCase {
    private let motDePasse = "demonstration"

    private func ouvrir(_ configuration: DemoEtablissementWorld.Configuration = .init()) async throws
        -> (SessionController, EtablissementSessionSnapshot) {
        let controller = SessionController(gateways: DemoWorld.gateways(espace: .etablissement(configuration)), espaceEtablissement: .ouvert)
        _ = await controller.start()
        let state = await controller.signIn(email: DemoEspace.emailEtablissement, password: motDePasse)
        return (controller, try XCTUnwrap(state.snapshotEtablissement, "espace établissement attendu, obtenu \(state)"))
    }

    func testRoleAfficheTelQueServiJamaisRecalcule() async throws {
        for role in RoleEtab.connus {
            let (_, snapshot) = try await ouvrir(.init(role: role))
            XCTAssertEqual(snapshot.role.role, "ADMIN_ETABLISSEMENT", "rôle d'application identique pour tous les membres")
            XCTAssertEqual(EtabComptePresentation.role(snapshot), role.libelle, role.brut)
        }
        // Compte legacy : `app_metadata.role = ETABLISSEMENT`, rôle d'équipe servi PROPRIETAIRE.
        let (_, legacy) = try await ouvrir(.init(role: .lectureSeule, legacy: true))
        XCTAssertEqual(legacy.user.appMetadataRole, "ETABLISSEMENT")
        XCTAssertEqual(EtabComptePresentation.role(legacy), "Propriétaire")
        // Valeur hors des cinq rôles : affichée telle quelle, sans traduction.
        var inconnu = legacy
        inconnu.context.roleEtab = .inconnu("ADMIN_PLATEFORME")
        XCTAssertEqual(EtabComptePresentation.role(inconnu), "ADMIN_PLATEFORME")
    }

    func testNomServiEtRepliDuWeb() async throws {
        let (_, snapshot) = try await ouvrir()
        XCTAssertEqual(EtabComptePresentation.nom(snapshot.etablissement), try DemoFixtures.loadEtablissementDemo().etablissement.nom)
        XCTAssertEqual(EtabComptePresentation.nom(EtablissementProfil(id: "etab-1", nom: "")), "Mon établissement")
        XCTAssertEqual(EtabComptePresentation.nom(EtablissementProfil(id: "etab-1", nom: "   ")), "Mon établissement")
        XCTAssertEqual(EtabComptePresentation.email(snapshot.user), DemoEspace.emailEtablissement)
        var sansEmail = snapshot.user
        sansEmail.email = nil
        XCTAssertEqual(EtabComptePresentation.email(sansEmail), "—")
    }

    func testVariantePubliqueDuMondeDemoPourLeRenvoiChorus() async throws {
        let (_, prive) = try await ouvrir()
        XCTAssertEqual(prive.etablissement.estSecteurPublic, false)
        XCTAssertFalse(RenvoisWebEtab.visibles(profil: prive.etablissement, permissions: prive.context.permissions)
            .contains { $0.cle == .chorusConfig })
        let (_, secteurPublic) = try await ouvrir(.init(secteurPublic: true))
        XCTAssertEqual(secteurPublic.etablissement.estSecteurPublic, true)
        XCTAssertEqual(secteurPublic.etablissement.id, prive.etablissement.id, "même établissement fictif")
        XCTAssertTrue(RenvoisWebEtab.visibles(profil: secteurPublic.etablissement, permissions: secteurPublic.context.permissions)
            .contains { $0.cle == .chorusConfig })
        XCTAssertEqual(DemoEspaceLancement.espace(arguments: ["-JOLENE_DEMO_ESPACE", "etablissement", "-JOLENE_DEMO_SECTEUR_PUBLIC", "1"]),
                       .etablissement(.init(secteurPublic: true)))
        XCTAssertEqual(DemoEspaceLancement.espace(arguments: ["-JOLENE_DEMO_ESPACE", "etablissement", "-JOLENE_DEMO_SECTEUR_PUBLIC", "0"]),
                       .etablissement(.init()))
        XCTAssertEqual(DemoEspaceLancement.espace(arguments: ["-JOLENE_DEMO_SECTEUR_PUBLIC", "1"]), .soignant,
                       "sans -JOLENE_DEMO_ESPACE etablissement, la variante est ignorée")
    }

    func testDeconnexionAvanceLEpochDeUnEtFermeLEspace() async throws {
        let (controller, snapshot) = try await ouvrir()
        let avant = await controller.epoch
        XCTAssertEqual(avant, snapshot.epoch)
        let apres = await controller.signOut()
        XCTAssertEqual(apres, .signedOut(message: nil))
        XCTAssertNil(apres.snapshotEtablissement)
        let epoch = await controller.epoch
        XCTAssertEqual(epoch, snapshot.epoch + 1, "déconnexion : une frontière d'identité")
        let perimes = await controller.gateways(for: snapshot.epoch)
        XCTAssertNil(perimes, "plus aucun port servi à l'epoch de l'espace fermé")
    }

    @MainActor
    func testDeconnexionParLeStorePublieLaFinDeLEspace() async throws {
        let store = SessionStore(controller: SessionController(gateways: DemoWorld.gateways(espace: .etablissement(.init())),
                                                                espaceEtablissement: .ouvert))
        await store.start()
        await store.signIn(email: DemoEspace.emailEtablissement, password: motDePasse)
        let snapshot = try XCTUnwrap(store.state.snapshotEtablissement)
        await store.signOut()
        XCTAssertEqual(store.state, .signedOut(message: nil))
        XCTAssertFalse(store.deconnexionEnCours)
        let epoch = await store.controller.epoch
        XCTAssertEqual(epoch, snapshot.epoch + 1)
    }
}
