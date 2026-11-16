import XCTest
@testable import JoleneCore

/// Lot 2, T10 — liens du lot 2 (`docs/mobile-swift/LOT2_PLAN.md` §3 T10) : table des chemins de `src/App.tsx`
/// (l.323-327, l.388, l.405-407, l.440-441), identifiants encodés, onglets inconnus ramenés au défaut du web
/// (`MesDocuments.tsx` l.18-24, `PresencesSoignant.tsx` l.276-279), alias `Navigate`, pages web conservées (DPAE,
/// Conformité), destinations et cibles de l'espace, liens de push (`navigationPathForEvent`, `src/lib/pushNative.ts`
/// l.264-268 et l.305-307, port `PushRouting`) résolus par le même aiguillage que les liens universels, routes forcées web
/// des renvois qui doivent survivre au routage natif, descriptions masquées (PRINCIPES §7).
@MainActor
final class LinksRouterLot2Tests: XCTestCase {
    private func url(_ s: String) -> URL { URL(string: s)! }

    private func route(_ s: String) -> JoleneRoute? {
        LinkRouter.route(url: url(s))
    }

    private func snapshot(epoch: Int, role: String = "SOIGNANT") -> SessionSnapshot {
        let user = AuthenticatedUser(id: "u-lot2", email: "u-lot2@example.invalid",
                                     emailConfirmedAt: Date(timeIntervalSince1970: 1_700_000_000), appMetadataRole: role)
        let profil = SoignantProfile(id: user.id, profession: "IDE")
        return SessionSnapshot(user: user, role: RoleResult(role: role), profile: profil,
                               context: MissionReadContext(userId: user.id, email: user.email, profile: profil), epoch: epoch)
    }

    // MARK: - Table des routes

    /// Chaque ligne est une route déclarée (ou un `Navigate`) de `src/App.tsx` ; mêmes routes par lien universel
    /// (`jolene.app`, `www`), par lien interne relatif et par l'hôte web de confiance `app.jolene.app`.
    func testTableDesRoutesDuLot2() {
        let table: [(String, JoleneRoute)] = [
            // Présences (l.326) : `?tab=` et `?filtre=` bruts (`searchParams.get`).
            ("/soignant/presences", .presences(onglet: nil, filtre: nil)),
            ("/soignant/presences?tab=historique", .presences(onglet: "historique", filtre: nil)),
            ("/soignant/presences?tab=historique&filtre=a_valider", .presences(onglet: "historique", filtre: "a_valider")),
            ("/soignant/presences?tab=aujourdhui", .presences(onglet: "aujourdhui", filtre: nil)),
            ("/soignant/presences?tab=encours", .presences(onglet: "encours", filtre: nil)),
            ("/soignant/presences?tab=avenir", .presences(onglet: "avenir", filtre: nil)),
            // Détail des présences d'une mission (l.327).
            ("/soignant/presences/mission/m-1", .presencesMission(id: "m-1")),
            // Mes documents (l.323) et ses onglets.
            ("/soignant/mes-documents", .documents(onglet: nil)),
            ("/soignant/mes-documents?tab=justificatifs", .documents(onglet: "justificatifs")),
            ("/soignant/mes-documents?tab=contrats", .documents(onglet: "contrats")),
            ("/soignant/mes-documents?tab=dpae", .documents(onglet: "dpae")),
            // Alias `Navigate` (l.388, l.407) : l'onglet est fixé par la redirection.
            ("/soignant/documents", .documents(onglet: "justificatifs")),
            ("/soignant/contrats", .documents(onglet: "contrats")),
            // Contrat (l.440) et certificat (l.441).
            ("/contrat/c-1", .contrat(id: "c-1")),
            ("/contrat/c-1/certificat", .contratCertificat(id: "c-1")),
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

    /// Le web encode les identifiants avec `encodeURIComponent` (`PushRouting.segment`) : le segment est décodé.
    func testIdentifiantsEncodesSontDecodes() {
        XCTAssertEqual(route("https://jolene.app/contrat/c%201"), .contrat(id: "c 1"))
        XCTAssertEqual(route("https://jolene.app/contrat/c%2F1/certificat"), .contratCertificat(id: "c/1"),
                       "barre oblique encodée : un seul segment, décodé")
        XCTAssertEqual(route("https://jolene.app/soignant/presences/mission/m%C3%A9-1"), .presencesMission(id: "mé-1"))
        XCTAssertEqual(LinkRouter.resolve(link: "/contrat/\("c?1".addingPercentEncoding(withAllowedCharacters: .alphanumerics)!)"),
                       .contrat(id: "c?1"))
        XCTAssertEqual(route("https://jolene.app/contrat/certificat"), .contrat(id: "certificat"),
                       "`/contrat/:id` du web accepte tout segment, « certificat » compris")
    }

    /// `?tab=` lu comme `searchParams.get('tab')` : décodage pourcent et « + », première occurrence, comparaison exacte par
    /// l'écran. Une valeur inconnue est transmise telle quelle puis ramenée au défaut : `justificatifs` pour Mes documents
    /// (`TABS.includes(tab) ? tab : 'justificatifs'`, l.24), onglet dérivé pour les Présences (écart assumé de T4a : le
    /// web afficherait un onglet vide).
    func testOngletsInconnusRetombentSurLeDefautDuWeb() throws {
        XCTAssertEqual(route("https://jolene.app/soignant/mes-documents?tab=xyz"), .documents(onglet: "xyz"))
        XCTAssertEqual(route("https://jolene.app/soignant/mes-documents?tab=Contrats"), .documents(onglet: "Contrats"))
        XCTAssertEqual(route("https://jolene.app/soignant/mes-documents?tab=contr%61ts&tab=dpae"), .documents(onglet: "contrats"))
        XCTAssertEqual(route("https://jolene.app/soignant/mes-documents?tab="), .documents(onglet: ""))
        XCTAssertEqual(route("https://jolene.app/soignant/mes-documents#tab=dpae"), .documents(onglet: nil), "fragment ignoré")
        for (parametre, onglet) in [(nil, OngletDocuments.justificatifs), ("xyz", .justificatifs), ("Contrats", .justificatifs),
                                    ("", .justificatifs), ("contrats", .contrats), ("dpae", .dpae), ("justificatifs", .justificatifs)] {
            XCTAssertEqual(OngletDocuments(parametre: parametre), onglet, String(describing: parametre))
        }

        XCTAssertEqual(route("https://jolene.app/soignant/presences?tab=Historique&filtre=A_VALIDER"),
                       .presences(onglet: "Historique", filtre: "A_VALIDER"))
        XCTAssertEqual(route("https://jolene.app/soignant/presences?filtre=a_valider"), .presences(onglet: nil, filtre: "a_valider"))
        XCTAssertEqual(PointageRules.ongletInitial(parametre: "Historique", missionsAujourdhui: 1, missionsEnCours: 0), .aujourdhui,
                       "onglet inconnu : onglet dérivé")
        XCTAssertEqual(PointageRules.ongletInitial(parametre: "historique", missionsAujourdhui: 1, missionsEnCours: 0), .historique)
        XCTAssertFalse(PointageRules.filtreAValider("A_VALIDER"), "comparaison exacte (`=== 'a_valider'`)")
        XCTAssertTrue(PointageRules.filtreAValider("a_valider"))
    }

    /// Les alias `Navigate` ont une cible fixe : la query du lien n'est pas reprise (le web perd `?statut=` sur
    /// `/soignant/contrats`), le fragment non plus.
    func testAliasNavigateFixentLOngletSansReprendreLaQuery() {
        XCTAssertEqual(route("https://jolene.app/soignant/documents?tab=contrats"), .documents(onglet: "justificatifs"))
        XCTAssertEqual(route("https://jolene.app/soignant/contrats?statut=ANNULE#x"), .documents(onglet: "contrats"))
        XCTAssertEqual(route("https://jolene.app/soignant/contrats/"), .documents(onglet: "contrats"))
    }

    /// DPAE (alias web de `?tab=dpae`, onglet en renvoi web, décision 16) et Conformité (lot 4) : pages web, URL canonique
    /// du lien reçu (query et fragment conservés).
    func testDpaeEtConformiteRestentDesRenvoisWeb() throws {
        for chemin in ["/soignant/dpae", "/soignant/dpae?origine=push#haut", "/soignant/conformite", "/soignant/conformite?tab=x"] {
            let canonique = url("https://jolene.app" + chemin)
            XCTAssertEqual(route("https://www.jolene.app" + chemin), .safari(canonique), chemin)
            let lien = try XCTUnwrap(DestinationLien(link: chemin), chemin)
            XCTAssertEqual(lien.destination, .safari(canonique), chemin)
            XCTAssertEqual(DeepLinkIntent(lien), .renvoiWeb(lien), chemin)
        }
        XCTAssertEqual(route("https://jolene.app/soignant/dpae/"), .safari(url("https://jolene.app/soignant/dpae/")),
                       "barre oblique finale ignorée pour le routage, URL du lien conservée")
    }

    /// Profondeurs et casses inconnues : jamais une route native, la page web canonique.
    func testProfondeursEtCassesInconnuesRestentSafari() {
        for chemin in ["/contrat", "/contrat/c-1/x", "/contrat/c-1/certificat/x", "/contrat//certificat", "/Contrat/c-1",
                       "/contrat/c-1/Certificat", "/soignant/presences/mission", "/soignant/presences/x",
                       "/soignant/presences/mission/m-1/x", "/soignant/presences/missions/m-1", "/soignant/Presences",
                       "/soignant/mes-documents/x", "/soignant/Mes-Documents", "/soignant/documents/x", "/contrats/c-1"] {
            XCTAssertEqual(route("https://jolene.app" + chemin), .safari(url("https://jolene.app" + chemin)), chemin)
        }
        XCTAssertEqual(route("https://jolene.app/contrat/"), .safari(url("https://jolene.app/contrat/")),
                       "barre finale retirée : `/contrat` sans identifiant")
    }

    func testBarreFinaleFragmentEtQueryEtrangereTolerees() {
        XCTAssertEqual(route("https://jolene.app/soignant/presences/?utm_source=email#haut"), .presences(onglet: nil, filtre: nil))
        XCTAssertEqual(route("https://jolene.app/soignant/presences/mission/m-1/#x"), .presencesMission(id: "m-1"))
        XCTAssertEqual(route("https://jolene.app/contrat/c-1/?origine=mail"), .contrat(id: "c-1"))
        XCTAssertEqual(route("https://jolene.app/contrat/c-1/certificat#signatures"), .contratCertificat(id: "c-1"))
        XCTAssertEqual(route("https://jolene.app/soignant/mes-documents/?tab=dpae"), .documents(onglet: "dpae"))
    }

    /// Hôtes, schéma et port : mêmes refus que le reste du routeur.
    func testMemesRefusQueLeRouteur() {
        for s in ["https://app.jolene.app/contrat/c-1", "https://evil.example/contrat/c-1", "http://jolene.app/contrat/c-1",
                  "https://jolene.app:444/soignant/presences", "https://jolene.app.evil.example/soignant/mes-documents"] {
            XCTAssertNil(route(s), s)
        }
        XCTAssertNil(LinkRouter.resolve(link: "contrat/c-1"))
        XCTAssertNil(LinkRouter.resolve(link: "https://evil.example/soignant/presences"))
    }

    // MARK: - Destination et cible de l'espace

    /// Écrans livrés (T4a, T5a, T7, T9a) : la route est sa propre destination, présentée dans l'espace sur l'onglet Profil
    /// (« Mon espace »), jamais un renvoi web.
    func testDestinationsNativesEtCiblesDeMonEspace() throws {
        let cas: [(String, CibleNotification)] = [
            ("/soignant/presences", .presences(onglet: nil, filtre: nil)),
            ("/soignant/presences?tab=historique&filtre=a_valider", .presences(onglet: "historique", filtre: "a_valider")),
            ("/soignant/presences/mission/m-1", .detailPresences(missionId: "m-1")),
            ("/soignant/mes-documents", .documents(onglet: .justificatifs)),
            ("/soignant/mes-documents?tab=xyz", .documents(onglet: .justificatifs)),
            ("/soignant/mes-documents?tab=contrats", .documents(onglet: .contrats)),
            ("/soignant/mes-documents?tab=dpae", .documents(onglet: .dpae)),
            ("/soignant/documents", .documents(onglet: .justificatifs)),
            ("/soignant/contrats?statut=ANNULE", .documents(onglet: .contrats)),
            ("/contrat/c-1", .contrat(id: "c-1")),
            ("/contrat/c-1/certificat", .certificat(contratId: "c-1")),
        ]
        for (chemin, cible) in cas {
            let lien = try XCTUnwrap(DestinationLien(url: url("https://jolene.app" + chemin)), chemin)
            XCTAssertTrue(DestinationLien.ecranNatifLivre(lien.route), chemin)
            XCTAssertEqual(lien.destination, lien.route, chemin)
            guard case .espace(let destination) = DeepLinkIntent(lien) else {
                XCTFail("\(chemin) : destination de l'espace attendue")
                continue
            }
            XCTAssertEqual(CibleNotification(destination), cible, chemin)
            XCTAssertEqual(cible.onglet, .profil, "\(chemin) : « Mon espace » vit sur l'onglet Profil")
            XCTAssertTrue(cible.estPresentable(renvoiWebDisponible: false), chemin)
            XCTAssertTrue(cible.estPresentable(renvoiWebDisponible: true, depuisCentre: true), "\(chemin) : depuis le centre")
            XCTAssertNil(AccueilPresentation.renvoiWeb(chemin), "\(chemin) : plus de renvoi web résolu par le routeur")
        }
    }

    // MARK: - Aiguillage (coordinateur des liens) et taps push

    /// Un lien de l'espace reçu avant `.ready` est mémorisé, puis rejoué une fois par le premier espace prêt, vers l'écran
    /// natif ; reçu dans un espace ouvert, il est présenté aussitôt pour l'epoch de cet espace.
    func testLienDuLot2MemoriseAvantReadyPuisRejoueVersLEcranNatif() {
        let aiguillage = AiguillageLiens(taps: BoiteTapsPush())
        XCTAssertNil(aiguillage.recevoir(url: url("https://jolene.app/contrat/demo-contrat-001")), "aucun espace : mémorisé")
        XCTAssertTrue(aiguillage.aUnLienEnAttente)
        XCTAssertEqual(aiguillage.ouvrirEspace(snapshot(epoch: 3)),
                       .naviguer(.contrat(id: "demo-contrat-001"), route: .contrat(id: "demo-contrat-001"), epoch: 3))
        XCTAssertFalse(aiguillage.aUnLienEnAttente)
        XCTAssertEqual(aiguillage.recevoir(url: url("https://www.jolene.app/soignant/presences?tab=historique")),
                       .naviguer(.presences(onglet: "historique", filtre: nil), route: .presences(onglet: "historique", filtre: nil),
                                 epoch: 3))
        XCTAssertEqual(aiguillage.recevoir(url: url("https://jolene.app/contrat/c-1/certificat")),
                       .naviguer(.certificat(contratId: "c-1"), route: .contratCertificat(id: "c-1"), epoch: 3))
        XCTAssertEqual(aiguillage.recevoir(url: url("https://jolene.app/soignant/mes-documents?tab=dpae")),
                       .naviguer(.documents(onglet: .dpae), route: .documents(onglet: "dpae"), epoch: 3))
        XCTAssertNil(aiguillage.ouvrirEspace(snapshot(epoch: 4)), "rien n'est rejoué deux fois")
    }

    /// `/soignant/dpae` : renvoi web présenté aussitôt, avec ou sans session, jamais mémorisé.
    func testDpaeRenvoiWebAussitotSansSession() {
        let aiguillage = AiguillageLiens(taps: BoiteTapsPush())
        let dpae = url("https://jolene.app/soignant/dpae")
        XCTAssertEqual(aiguillage.recevoir(url: dpae), .renvoiWeb(.safari(dpae)))
        XCTAssertFalse(aiguillage.aUnLienEnAttente)
        XCTAssertNil(aiguillage.ouvrirEspace(snapshot(epoch: 1)))
    }

    /// Liens de push (`navigationPathForEvent`, `pushNative.ts` l.264-268 et l.305-307) : contrats et DPAE mènent aux
    /// écrans natifs du lot 2 pour un soignant, à l'espace établissement pour un établissement.
    func testCheminsDePushDuLot2ResolusVersLesEcransNatifs() throws {
        let cas: [([String: String], String, JoleneRoute, CibleNotification)] = [
            (["type_evenement": "CONTRAT_A_SIGNER", "contrat_id": "c-1"], "/contrat/c-1", .contrat(id: "c-1"), .contrat(id: "c-1")),
            (["type_evenement": "CONTRAT_SIGNE", "contrat_id": "c 1"], "/contrat/c%201", .contrat(id: "c 1"), .contrat(id: "c 1")),
            (["type_evenement": "CONTRAT_REJETE"], "/soignant/mes-documents?tab=contrats", .documents(onglet: "contrats"),
             .documents(onglet: .contrats)),
            (["type_evenement": "DPAE_RAPPEL", "contrat_id": "c-2"], "/contrat/c-2", .contrat(id: "c-2"), .contrat(id: "c-2")),
            (["type_evenement": "DPAE_ANNULATION_RAPPEL"], "/soignant/mes-documents?tab=dpae", .documents(onglet: "dpae"),
             .documents(onglet: .dpae)),
            (["type_evenement": "DPAE_NON_REGULARISEE_POINTAGE"], "/soignant/mes-documents?tab=dpae", .documents(onglet: "dpae"),
             .documents(onglet: .dpae)),
            // Lien explicite d'une notification (`lien`) : gagne toujours (l.254-255).
            (["type_evenement": "SYSTEM", "lien": "/soignant/presences?tab=historique&filtre=a_valider"],
             "/soignant/presences?tab=historique&filtre=a_valider", .presences(onglet: "historique", filtre: "a_valider"),
             .presences(onglet: "historique", filtre: "a_valider")),
            (["type_evenement": "SYSTEM", "lien": "https://jolene.app/soignant/presences/mission/m-1"],
             "/soignant/presences/mission/m-1", .presencesMission(id: "m-1"), .detailPresences(missionId: "m-1")),
        ]
        for (donnees, chemin, route, cible) in cas {
            XCTAssertEqual(PushRouting.path(data: donnees, role: "SOIGNANT"), chemin, "\(donnees)")
            let destination = try XCTUnwrap(PushTapIntent(donnees: donnees).destination(role: "SOIGNANT"), "\(donnees)")
            XCTAssertEqual(destination.route, route, chemin)
            XCTAssertEqual(destination.destination, route, "\(chemin) : écran natif livré")
            XCTAssertEqual(CibleNotification(destination), cible, chemin)
        }
        // Établissement : espace établissement en renvoi web (le natif ne sert pas ce rôle).
        let etab = try XCTUnwrap(PushTapIntent(donnees: ["type_evenement": "CONTRAT_A_SIGNER"]).destination(role: "ADMIN_ETABLISSEMENT"))
        XCTAssertEqual(etab.destination, .etablissement(url("https://jolene.app/etablissement/contrats")))
    }

    /// Tap push reçu avant ou pendant l'espace : même aiguillage que les liens universels, rôle du snapshot.
    func testTapsPushDuLot2PassentParLAiguillage() {
        let taps = BoiteTapsPush()
        let aiguillage = AiguillageLiens(taps: taps)
        taps.recevoir(PushTapIntent(donnees: ["type_evenement": "CONTRAT_A_SIGNER", "contrat_id": "demo-contrat-001"]))
        XCTAssertNil(aiguillage.tapRecu(), "aucun espace ouvert : le tap attend dans la boîte")
        XCTAssertEqual(aiguillage.ouvrirEspace(snapshot(epoch: 7)),
                       .naviguer(.contrat(id: "demo-contrat-001"), route: .contrat(id: "demo-contrat-001"), epoch: 7))
        taps.recevoir(PushTapIntent(donnees: ["type_evenement": "DPAE_RAPPEL"]))
        XCTAssertEqual(aiguillage.tapRecu(), .naviguer(.documents(onglet: .dpae), route: .documents(onglet: "dpae"), epoch: 7))
        taps.recevoir(PushTapIntent(donnees: ["type_evenement": "CONTRAT_SIGNE"]))
        XCTAssertEqual(aiguillage.tapRecu(),
                       .naviguer(.documents(onglet: .contrats), route: .documents(onglet: "contrats"), epoch: 7))
    }

    // MARK: - Renvois web qui doivent survivre au routage natif (routes forcées web)

    /// Les renvois qui mènent **à la page web** (coupe-circuit à faux, suivi non vérifiable, signature d'un compte TEST,
    /// export PDF du certificat, récapitulatif financier) ne passent pas par `LinkRouter` : depuis T10, la résolution par le
    /// routeur rendrait nil (`AccueilPresentation.renvoiWeb`) et le bouton disparaîtrait sans bruit.
    func testRenvoisWebForcesSurviventAuRoutageNatif() throws {
        XCTAssertEqual(PresencesRenvois.presences, .safari(url("https://jolene.app/soignant/presences")))
        XCTAssertNil(AccueilPresentation.renvoiWeb("/soignant/presences"), "le chemin est natif depuis T10")
        XCTAssertEqual(DocumentsModel.routeRenvoiWeb, .safari(url("https://jolene.app/soignant/mes-documents?tab=justificatifs")))
        XCTAssertNil(AccueilPresentation.renvoiWeb(DocumentsModel.renvoiWeb), "le chemin est natif depuis T10")
        XCTAssertEqual(ContratPresentation.renvoiListe, .safari(url("https://jolene.app/soignant/mes-documents?tab=contrats")))
        XCTAssertEqual(ContratPresentation.renvoiContrat(contratId: "c-1"), .safari(url("https://jolene.app/contrat/c-1")))
        XCTAssertEqual(ContratPresentation.renvoiSignature(contratId: "c-1"), .safari(url("https://jolene.app/contrat/c-1")))
        XCTAssertEqual(ContratPresentation.renvoiCertificat(contratId: "c-1"),
                       .safari(url("https://jolene.app/contrat/c-1/certificat")))
        XCTAssertNil(AccueilPresentation.renvoiWeb("/contrat/c-1"), "le chemin est natif depuis T10")
        XCTAssertEqual(PresencesRenvois.recapitulatifFinancier(missionId: "m-1"),
                       .safari(url("https://jolene.app/soignant/presences/mission/m-1")))
        XCTAssertNil(AccueilPresentation.renvoiWeb("/soignant/presences/mission/m-1"), "le chemin est natif depuis T10")
        // Identifiant hors segment sûr : aucun renvoi construit (jamais un chemin détourné).
        for invalide in ["", "a/b", "a?x=1", "a#b", "..", "é"] {
            XCTAssertNil(ContratPresentation.renvoiContrat(contratId: invalide), invalide)
        }
        // DPAE : page web résolue par le routeur (route `.safari`), le bouton de l'onglet DPAE reste.
        XCTAssertEqual(AccueilPresentation.renvoiWeb("/soignant/dpae"), .safari(url("https://jolene.app/soignant/dpae")))
    }

    // MARK: - Revue B8 n°1 de L2-T10 (m1, m3, m4)

    /// m4 : quand un coupe-circuit renvoie au web, la page web s'ouvre sur l'onglet (et le filtre des présences) du lien,
    /// jamais sur l'onglet par défaut. Valeurs exactes du web seulement : rien d'autre du lien n'est recopié.
    func testCoupeCircuitsRenvoientAuWebSurLOngletDuLien() throws {
        let presences = "https://jolene.app/soignant/presences"
        XCTAssertEqual(PresencesRenvois.presences(onglet: "historique", aValider: true),
                       .safari(url(presences + "?tab=historique&filtre=a_valider")))
        for onglet in PointageRules.OngletPresences.allCases {
            XCTAssertEqual(PresencesRenvois.presences(onglet: onglet.rawValue, aValider: false),
                           .safari(url(presences + "?tab=" + onglet.rawValue)), onglet.rawValue)
        }
        XCTAssertEqual(PresencesRenvois.presences(onglet: nil, aValider: true), .safari(url(presences + "?filtre=a_valider")))
        XCTAssertEqual(PresencesRenvois.presences(onglet: nil, aValider: false), .safari(url(presences)))
        XCTAssertEqual(PresencesRenvois.presences, PresencesRenvois.presences(onglet: nil, aValider: false),
                       "suivi non vérifiable : page des présences sans onglet")
        // Onglet inconnu (le web afficherait un onglet vide) ou détourné : non transmis.
        for inconnu in ["", "SECRET", "Historique", "historique&filtre=x", "historique#f", "avenir/../x"] {
            XCTAssertEqual(PresencesRenvois.presences(onglet: inconnu, aValider: false), .safari(url(presences)), inconnu)
        }

        for onglet in OngletDocuments.allCases {
            XCTAssertEqual(DocumentsModel.routeRenvoiWeb(onglet: onglet),
                           .safari(url("https://jolene.app/soignant/mes-documents?tab=" + onglet.rawValue)), onglet.rawValue)
        }
        XCTAssertEqual(DocumentsModel.routeRenvoiWeb, DocumentsModel.routeRenvoiWeb(onglet: .justificatifs),
                       "journal illisible : onglet Justificatifs, comme avant")

        // Bout en bout, du lien au renvoi : mêmes conversions que `MonEspaceRoute` et les écrans.
        guard case let .presences(onglet, filtre)? = LinkRouter.resolve(link: "/soignant/presences?tab=historique&filtre=a_valider") else {
            return XCTFail("route des présences attendue")
        }
        XCTAssertEqual(PresencesRenvois.presences(onglet: onglet, aValider: PointageRules.filtreAValider(filtre)),
                       .safari(url(presences + "?tab=historique&filtre=a_valider")))
        for (lien, attendu) in [("/soignant/contrats", "contrats"), ("/soignant/mes-documents?tab=dpae", "dpae"),
                                ("/soignant/mes-documents?tab=inconnu", "justificatifs")] {
            guard case let .documents(brut)? = LinkRouter.resolve(link: lien) else { return XCTFail("\(lien) : route des documents attendue") }
            XCTAssertEqual(DocumentsModel.routeRenvoiWeb(onglet: OngletDocuments(parametre: brut)),
                           .safari(url("https://jolene.app/soignant/mes-documents?tab=" + attendu)), lien)
        }
    }

    /// m1 : chaque présentation d'une route par le présentateur de l'espace est une valeur nouvelle ; présenter deux fois la
    /// route déjà à la base de la pile change donc le chemin (SwiftUI reconstruit l'écran et retire ce qui est au-dessus).
    func testPresentationsSuccessivesDeLaMemeRouteChangentLeChemin() {
        enum Route: Hashable { case contrat(String), certificat(String) }
        var jetons = JetonsDePresentation()
        let premiere = jetons.presenter(Route.contrat("c-1"))
        let seconde = jetons.presenter(Route.contrat("c-1"))
        XCTAssertEqual(premiere.route, seconde.route, "même route")
        XCTAssertNotEqual(premiere, seconde, "même route présentée deux fois : deux valeurs")
        XCTAssertNotEqual([premiere], [seconde], "le chemin de la pile change")
        XCTAssertEqual(Set([premiere, seconde]).count, 2, "deux éléments de chemin distincts")
        XCTAssertGreaterThan(seconde.jeton, premiere.jeton)
        let autre = jetons.presenter(Route.certificat("c-1"))
        XCTAssertEqual(autre.route, .certificat("c-1"))
        XCTAssertEqual(jetons.dernier, 3, "un jeton par présentation")
        // Une présentation reste égale à elle-même (le chemin inchangé n'est pas reconstruit).
        XCTAssertEqual(premiere, PresentationJetonnee(route: Route.contrat("c-1"), jeton: premiere.jeton))
    }

    /// m3 : la porte des contrats attend la lecture du drapeau (ni écran natif ni renvoi avant), puis suit le drapeau ;
    /// drapeau absent (la passerelle rend son défaut sur erreur, décision 15) ou passerelle absente : fail-open.
    func testPorteDesContratsAttendLeDrapeauPuisResteFailOpen() async {
        XCTAssertEqual(PorteEcranNatif(drapeau: nil), .lecture, "avant la lecture : aucune lecture réseau de l'écran")
        XCTAssertEqual(PorteEcranNatif(drapeau: true), .natif)
        XCTAssertEqual(PorteEcranNatif(drapeau: false), .renvoiWeb)
        let cle = EcranNatif.contrats.cle
        XCTAssertEqual(cle, "ios_natif_contrats_actif")
        let faux = await PorteEcranNatif.lire(.contrats, flags: DemoFlagsGateway(surcharges: [cle: false]))
        XCTAssertEqual(faux, .renvoiWeb)
        let vrai = await PorteEcranNatif.lire(.contrats, flags: DemoFlagsGateway(surcharges: [cle: true]))
        XCTAssertEqual(vrai, .natif)
        let absent = await PorteEcranNatif.lire(.contrats, flags: DemoFlagsGateway())
        XCTAssertEqual(absent, .natif, "drapeau absent ou illisible : défaut fail-open")
        let sansPasserelle = await PorteEcranNatif.lire(.contrats, flags: nil)
        XCTAssertEqual(sansPasserelle, .natif, "aucune passerelle pour l'epoch : fail-open, comme avant")
        let autreEcran = await PorteEcranNatif.lire(.contrats, flags: DemoFlagsGateway(surcharges: [EcranNatif.documents.cle: false]))
        XCTAssertEqual(autreEcran, .natif, "seul le drapeau des contrats décide")
    }

    // MARK: - Descriptions masquées (PRINCIPES §7) et libellé DEBUG

    private func textes(_ valeur: Any) -> [String] {
        [String(describing: valeur), String(reflecting: valeur), "\(valeur)"]
    }

    func testDescriptionsMasquees() throws {
        let cas: [(JoleneRoute, String)] = [
            (.presences(onglet: nil, filtre: nil), "presences(sans onglet, sans filtre)"),
            (.presences(onglet: "historique", filtre: "a_valider"), "presences(historique, a_valider)"),
            (.presences(onglet: "SECRET", filtre: "SECRET"), "presences(onglet masqué, filtre masqué)"),
            (.presencesMission(id: "SECRET"), "presencesMission(id masqué)"),
            (.documents(onglet: nil), "documents(sans onglet)"),
            (.documents(onglet: "contrats"), "documents(contrats)"),
            (.documents(onglet: "SECRET"), "documents(onglet masqué)"),
            (.contrat(id: "SECRET"), "contrat(id masqué)"),
            (.contratCertificat(id: "SECRET"), "contratCertificat(id masqué)"),
        ]
        for (route, attendu) in cas {
            for texte in textes(route) { XCTAssertEqual(texte, attendu) }
        }
        let gabarits: [(String, String)] = [
            ("https://jolene.app/contrat/SECRET1", "/contrat/‹masqué›"),
            ("https://jolene.app/contrat/SECRET2/certificat#SECRET3", "/contrat/‹masqué›/certificat#‹masqué›"),
            ("https://jolene.app/soignant/presences/mission/SECRET4", "/soignant/presences/mission/‹masqué›"),
            ("https://jolene.app/soignant/presences?tab=SECRET5", "/soignant/presences?‹masqué›"),
            ("https://jolene.app/soignant/mes-documents?tab=SECRET6", "/soignant/mes-documents?‹masqué›"),
            ("https://jolene.app/soignant/documents", "/soignant/documents"),
            ("https://jolene.app/soignant/dpae", "/soignant/dpae"),
            ("https://jolene.app/soignant/conformite", "/soignant/conformite"),
        ]
        for (lien, gabarit) in gabarits {
            let destination = try XCTUnwrap(DestinationLien(url: url(lien)), lien)
            XCTAssertEqual(LienMasque.gabarit(destination.canonique), gabarit, lien)
            for valeur in [destination as Any, destination.route, DeepLinkIntent(destination)] {
                for texte in textes(valeur) { XCTAssertFalse(texte.contains("SECRET"), "\(lien) → \(texte)") }
            }
        }
        var sortie = ""
        dump(AiguillageLiens.Action.naviguer(.contrat(id: "SECRET7"), route: .contrat(id: "SECRET7"), epoch: 1), to: &sortie)
        XCTAssertFalse(sortie.contains("SECRET"), sortie)
    }

    /// `deeplink-route` (DEBUG, démo seulement) : cas de route et identifiant démo, lus par `DemoLiensLot2Tests`.
    func testLibelleDebugDesRoutesDuLot2() {
        XCTAssertEqual(PushTapIntent.libelleDebug(.contrat(id: "demo-contrat-001")), "contrat demo-contrat-001")
        XCTAssertEqual(PushTapIntent.libelleDebug(.contratCertificat(id: "demo-contrat-002")), "contratCertificat demo-contrat-002")
        XCTAssertEqual(PushTapIntent.libelleDebug(.presencesMission(id: "demo-presence-h2")), "presencesMission demo-presence-h2")
        XCTAssertEqual(PushTapIntent.libelleDebug(.presences(onglet: "historique", filtre: "a_valider")),
                       "presences(historique, a_valider)")
        XCTAssertEqual(PushTapIntent.libelleDebug(.documents(onglet: "contrats")), "documents(contrats)")
    }
}
