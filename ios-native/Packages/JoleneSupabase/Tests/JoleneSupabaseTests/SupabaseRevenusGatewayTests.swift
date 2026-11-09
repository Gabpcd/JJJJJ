import Foundation
import JoleneCore
import Supabase
import XCTest
@testable import JoleneSupabase

/// Revenus en lecture (lot 3, T12, B9 ; fiches `fn_mes_revenus_connect` et `fn_mes_paiements_escrow` de
/// `docs/mobile-swift/CONTRATS_RPC_SOIGNANT.md` ; définitions live relues en lecture seule le 09/11/2026, identiques au
/// dump ; GRANT `authenticated` et droits de colonne vérifiés) :
/// - missions TERMINEE du soignant avec **exactement** les colonnes de `MesGains.tsx` l.95 (aucune colonne Rist, D5 —
///   test-garde contre la source web), `debut_le` décroissant, pages de 50 ; dernière déclaration lue avec les colonnes
///   et l'ordre de l.102-107 ; noms d'établissement par `fn_etablissements_safe` seul (repli : nom absent) ;
/// - totaux : `soignants(type_exercice, est_compte_test)` d'abord (colonnes de `PageStripeConnect.tsx` l.95) ; RPC
///   appelée seulement pour `LIBERAL` ou `MIXTE` hors compte de test (cartes du web : l.178, l.300, l.302, l.367 ; la
///   condition de l.106 n'est que celle du chargement) ; cartes seulement si `stripe_connect_actif` est vrai
///   (`statut === 'COMPLET'`, l.367) ; trois nombres finis exigés, sinon section en erreur ;
/// - paiements rapides : tableau de la RPC, ordre serveur ; autre corps → contrat.
/// Aucune écriture : seulement des GET et des RPC de lecture.
final class SupabaseRevenusGatewayTests: XCTestCase {
    private let registry = StubRegistry.shared
    private let missionsChemin = "/rest/v1/missions"
    private let paiementsChemin = "/rest/v1/paiements_soignant"
    private let soignantsChemin = "/rest/v1/soignants"
    private let etablissementsChemin = "/rest/v1/rpc/fn_etablissements_safe"
    private let totauxChemin = "/rest/v1/rpc/fn_mes_revenus_connect"
    private let escrowChemin = "/rest/v1/rpc/fn_mes_paiements_escrow"

    override func setUp() {
        super.setUp()
        registry.reset()
    }

    private func gateway() -> SupabaseRevenusGateway {
        SupabaseRevenusGateway(client: TestClient.make())
    }

    private func source(_ chemin: String) throws -> [String] {
        var racine = URL(fileURLWithPath: #filePath)
        // …/ios-native/Packages/JoleneSupabase/Tests/JoleneSupabaseTests/<fichier> → racine du dépôt.
        for _ in 0..<6 { racine.deleteLastPathComponent() }
        return try String(contentsOf: racine.appendingPathComponent(chemin), encoding: .utf8).components(separatedBy: "\n")
    }

    private static let missionJSON = """
    {"id":"m-1","intitule":"Nuit","debut_le":"2026-11-01T07:00:00+00:00","fin_le":"2026-11-01T15:00:00+00:00",
     "duree_heures":8,"nb_creneaux":1,"taux_horaire_base":26,"net_a_payer":224.6,"net_estime":162.4,"total_brut":208,
     "statut":"TERMINEE","etablissement_id":"etab-1","service":"Urgences","type_contrat_applique":"SALARIE",
     "type_contrat_recherche":"SALARIE","presences":[{"valide_par_etablissement":true,"valide_auto_72h_le":null,"valide_le":null}]}
    """

    private static let paiementsJSON = """
    [{"id":"p-2","mission_id":"m-1","facture_honoraire_id":null,"statut":"CONFIRME","montant_net":162.4,"confirme_par_soignant":true,
      "conteste":false,"montant_du_reference":null,"source_montant_du":null,"methode":"VIREMENT","reference_virement":null,
      "date_paiement":"2026-11-05","modifie_le":"2026-11-06T09:00:00+00:00","cree_le":"2026-11-05T09:00:00+00:00"},
     {"id":"p-1","mission_id":"m-1","facture_honoraire_id":null,"statut":"DECLARE","montant_net":162.4,"confirme_par_soignant":false,
      "conteste":false,"montant_du_reference":null,"source_montant_du":null,"methode":"VIREMENT","reference_virement":null,
      "date_paiement":"2026-11-05","modifie_le":"2026-11-05T09:00:00+00:00","cree_le":"2026-11-05T09:00:00+00:00"}]
    """

    private func stubPage(missions: String = "[\(missionJSON)]", paiements: StubResponse = .json(200, paiementsJSON),
                          etablissements: StubResponse = .json(200, TestClient.etablissementJSON)) {
        registry.add("GET", missionsChemin, respond: .json(200, missions))
        registry.add("GET", paiementsChemin, respond: paiements)
        registry.add("POST", etablissementsChemin, respond: etablissements)
    }

    // MARK: - Missions terminées

    func testColonnesDeMesGainsSansColonneRistEtFiltresDuWeb() async throws {
        stubPage()
        let page = try await gateway().missionsTerminees(context: TestClient.context, page: 0)

        let requete = try XCTUnwrap(registry.requests(to: missionsChemin).first)
        XCTAssertEqual(requete.method, "GET")
        let attendu = SupabaseRevenusGateway.missionsSelect.filter { !$0.isWhitespace }
        XCTAssertEqual(requete.query("select"), attendu)
        for interdite in ["rist_plafond_applique", "taux_rist_plafonne", "soignant_assigne_id", "profession_requise", "etablissements("] {
            XCTAssertFalse(requete.query("select")?.contains(interdite) ?? true, "colonne \(interdite) jamais lue (décision 5, correction 19)")
        }
        XCTAssertEqual(requete.query("soignant_assigne_id"), "eq.\(TestClient.userId)")
        XCTAssertEqual(requete.query("statut"), "eq.TERMINEE")
        // `.order('debut_le', { ascending: false })` sans suffixe : NULLS FIRST par défaut de Postgres sur un DESC.
        XCTAssertEqual(requete.query("order"), "debut_le.desc.nullsfirst")
        XCTAssertEqual(requete.query("offset"), "0")
        XCTAssertEqual(requete.query("limit"), "50")

        XCTAssertEqual(page.missions.map(\.id), ["m-1"])
        XCTAssertFalse(page.aSuivre)
        XCTAssertEqual(page.missions.first?.etablissementNom, "Clinique des Tests", "nom par fn_etablissements_safe seul")
        XCTAssertEqual(page.missions.first?.dernierPaiement?.id, "p-2", "dernière déclaration (modifie_le), pas l'ordre reçu")
        XCTAssertEqual(page.missions.first?.netEstime, 162.4)
        XCTAssertTrue(registry.unmatched.isEmpty)
    }

    /// Test-garde (D5, correction 19) : la chaîne de colonnes est celle du web, mot pour mot ; une colonne ajoutée d'un
    /// côté seulement ferait diverger les montants des deux surfaces.
    func testSelectIdentiqueALaSourceWeb() throws {
        let lignes = try source("src/pages/MesGains.tsx")
        XCTAssertTrue(lignes[94].contains(".select('\(SupabaseRevenusGateway.missionsSelect)')"), "MesGains.tsx l.95")
        XCTAssertTrue(lignes[101].contains(".select('\(SupabaseRevenusGateway.paiementsSelect)')"), "MesGains.tsx l.102")
        XCTAssertTrue(lignes[71].contains("PAGE_SIZE = \(RevenusAssemblage.taillePage)"), "MesGains.tsx l.72")
        // Revue B8 de T12, M1 : l'exercice est lu comme `PageStripeConnect.tsx` l.95 (sous-ensemble : ni nom ni prénom,
        // `statut_liberal` inutile à l'affichage, l.178), jamais comme les onglets de `MesGains.tsx` l.855.
        let stripe = try source("src/pages/PageStripeConnect.tsx")
        let web = "prenom, nom, type_exercice, statut_liberal, est_compte_test"
        XCTAssertTrue(stripe[94].contains(".select('\(web)')"), "PageStripeConnect.tsx l.95")
        let colonnesWeb = Set(web.components(separatedBy: ", "))
        let colonnes = SupabaseRevenusGateway.exerciceSelect.components(separatedBy: ", ")
        XCTAssertEqual(colonnes, ["type_exercice", "est_compte_test"])
        XCTAssertTrue(Set(colonnes).isSubset(of: colonnesWeb))
    }

    func testDerniereDeclarationColonnesEtOrdreDuWeb() async throws {
        stubPage()
        _ = try await gateway().missionsTerminees(context: TestClient.context, page: 0)
        let requete = try XCTUnwrap(registry.requests(to: paiementsChemin).first)
        XCTAssertEqual(requete.query("select"), SupabaseRevenusGateway.paiementsSelect.filter { !$0.isWhitespace })
        XCTAssertEqual(requete.query("soignant_id"), "eq.\(TestClient.userId)")
        XCTAssertEqual(requete.query("order"),
                       "modifie_le.desc.nullslast,cree_le.desc.nullslast,date_paiement.desc.nullslast,id.desc.nullsfirst")
        let etab = try XCTUnwrap(registry.requests(to: etablissementsChemin).first)
        XCTAssertEqual((etab.bodyJSON as? [String: Any])?["p_ids"] as? [String], ["etab-1"])
    }

    func testPageSuivanteEtPageNegative() async throws {
        let cinquante = (0..<50).map { #"{"id":"m-\#($0)","etablissement_id":"etab-1","type_contrat_applique":"LIBERAL"}"# }
        stubPage(missions: "[\(cinquante.joined(separator: ","))]")
        let page = try await gateway().missionsTerminees(context: TestClient.context, page: 2)
        let requete = try XCTUnwrap(registry.requests(to: missionsChemin).first)
        XCTAssertEqual(requete.query("offset"), "100")
        XCTAssertEqual(requete.query("limit"), "50")
        XCTAssertEqual(page.page, 2)
        XCTAssertTrue(page.aSuivre, "page pleine : une suite est possible (`pageMissions.length === PAGE_SIZE`)")
        XCTAssertEqual(registry.requests(to: etablissementsChemin).count, 1, "identifiants dédoublonnés en un seul appel")

        registry.reset()
        do {
            _ = try await gateway().missionsTerminees(context: TestClient.context, page: -1)
            XCTFail("page négative acceptée")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur.kind, .contract)
        }
        XCTAssertTrue(registry.requests.isEmpty, "aucune requête pour une page invalide")
    }

    /// `enrichirEtablissements` du web : la RPC en échec laisse les noms absents (« — »), sans faire échouer l'écran.
    func testEtablissementsEnEchecNomsAbsentsSansErreur() async throws {
        stubPage(etablissements: .json(500, #"{"message":"boom"}"#))
        let page = try await gateway().missionsTerminees(context: TestClient.context, page: 0)
        XCTAssertEqual(page.missions.map(\.id), ["m-1"])
        XCTAssertNil(page.missions.first?.etablissementNom)
    }

    /// Promise.all du web : missions et paiements sont requis ; l'échec de l'un fait échouer la lecture.
    func testPaiementsEnEchecFontEchouerLaLecture() async {
        stubPage(paiements: .networkFailure())
        do {
            _ = try await gateway().missionsTerminees(context: TestClient.context, page: 0)
            XCTFail("lecture partielle annoncée comme complète")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur.kind, .network)
        } catch {
            XCTFail("erreur non traduite : \(error)")
        }
    }

    func testMissionsRefuseesSessionExpiree() async {
        stubPage(missions: "[]")
        registry.reset()
        registry.add("GET", missionsChemin, respond: .json(401, #"{"code":"PGRST301","message":"JWT expired"}"#))
        registry.add("GET", paiementsChemin, respond: .json(200, "[]"))
        do {
            _ = try await gateway().missionsTerminees(context: TestClient.context, page: 0)
            XCTFail("401 non traduit")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur.kind, .unauthorized)
        } catch {
            XCTFail("erreur non traduite : \(error)")
        }
    }

    func testContexteIncoherentRefuseSansRequete() async {
        let autre = MissionReadContext(userId: "", email: nil, profile: TestClient.profile)
        do {
            _ = try await gateway().missionsTerminees(context: autre, page: 0)
            XCTFail("contexte incohérent accepté")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur.kind, .unauthorized)
        } catch {
            XCTFail("erreur non traduite : \(error)")
        }
        XCTAssertTrue(registry.requests.isEmpty)
    }

    // MARK: - Totaux

    private func stubExercice(_ corps: String, status: Int = 200) {
        registry.add("GET", soignantsChemin, respond: .json(status, corps))
    }

    func testTotauxLusPourUnExerciceLiberalAvecUnCompteConnectComplet() async throws {
        stubExercice(#"{"type_exercice":"MIXTE","est_compte_test":false}"#)
        registry.add("POST", totauxChemin, respond: .json(200, #"{"mois_en_cours":195,"total":1425.6,"en_attente":780,"stripe_connect_actif":true}"#))
        let totaux = try await gateway().totaux(context: TestClient.context)
        XCTAssertEqual(totaux, TotauxRevenus(moisEnCours: 195, total: 1425.6, enAttente: 780, stripeConnectActif: true))
        let lecture = try XCTUnwrap(registry.requests(to: soignantsChemin).first)
        XCTAssertEqual(lecture.query("select"), "type_exercice,est_compte_test")
        XCTAssertEqual(lecture.query("id"), "eq.\(TestClient.userId)")
        let rpc = try XCTUnwrap(registry.requests(to: totauxChemin).first)
        XCTAssertEqual(rpc.method, "POST")
        if let corps = rpc.bodyJSON as? [String: Any] {
            XCTAssertTrue(corps.isEmpty, "`p_mois_debut` omis : mois courant côté serveur, comme le web")
        }
    }

    /// Revue B8 de T12, M1 : les cartes du web exigent `isLiberal` (`PageStripeConnect.tsx` l.178, appliqué l.300 ;
    /// `statut_liberal` ignoré) hors compte de test (l.302, l.367) → salarié (même `statut_liberal = ACTIF`) ou compte
    /// de test : section absente, sans appel de la RPC.
    func testTotauxMasquesSansExerciceLiberalOuPourUnCompteDeTestSansAppelRPC() async throws {
        for exercice in [#"{"type_exercice":"SALARIE","est_compte_test":false}"#,
                         #"{"type_exercice":"SALARIE","statut_liberal":"ACTIF","est_compte_test":false}"#,
                         #"{"type_exercice":"LIBERAL","est_compte_test":true}"#,
                         #"{"type_exercice":"MIXTE","est_compte_test":true}"#,
                         #"{"type_exercice":null,"est_compte_test":false}"#] {
            registry.reset()
            stubExercice(exercice)
            registry.add("POST", totauxChemin, respond: .json(200, #"{"mois_en_cours":1,"total":2,"en_attente":3,"stripe_connect_actif":true}"#))
            let totaux = try await gateway().totaux(context: TestClient.context)
            XCTAssertNil(totaux, exercice)
            XCTAssertTrue(registry.requests(to: totauxChemin).isEmpty, "aucune lecture des totaux : \(exercice)")
        }
    }

    /// M1 : `statut === 'COMPLET'` (l.367) — le drapeau `stripe_connect_actif` de la même réponse
    /// (`fn_soignant_stripe_connect_actif`) : faux ou inconnu → section absente, jamais des totaux affichés.
    func testTotauxMasquesSansCompteConnectComplet() async throws {
        for rpc in [#"{"mois_en_cours":195,"total":1425.6,"en_attente":780,"stripe_connect_actif":false}"#,
                    #"{"mois_en_cours":195,"total":1425.6,"en_attente":780}"#,
                    #"{"mois_en_cours":"x","stripe_connect_actif":false}"#] {
            registry.reset()
            stubExercice(#"{"type_exercice":"LIBERAL","est_compte_test":false}"#)
            registry.add("POST", totauxChemin, respond: .json(200, rpc))
            let totaux = try await gateway().totaux(context: TestClient.context)
            XCTAssertNil(totaux, rpc)
            XCTAssertEqual(registry.requests(to: totauxChemin).count, 1)
        }
    }

    func testTotauxIncompletsOuProfilIntrouvableSontIndisponibles() async {
        for (exercice, statut, rpc) in [
            (#"{"type_exercice":"LIBERAL","est_compte_test":false}"#, 200, #"{"mois_en_cours":1,"total":"2","en_attente":3,"stripe_connect_actif":true}"#),
            (#"{"type_exercice":"LIBERAL","est_compte_test":false}"#, 200, #"{"error":"Non authentifié"}"#),
            (#"{"code":"PGRST116","details":"The result contains 0 rows","hint":null,"message":"no rows"}"#, 406, "{}"),
        ] {
            registry.reset()
            stubExercice(exercice, status: statut)
            registry.add("POST", totauxChemin, respond: .json(200, rpc))
            do {
                _ = try await gateway().totaux(context: TestClient.context)
                XCTFail("totaux indisponibles annoncés comme lus : \(rpc)")
            } catch let erreur as JoleneError {
                XCTAssertEqual(erreur.kind, .unknown, rpc)
                XCTAssertEqual(erreur.message, RevenusTextes.totauxIndisponibles, rpc)
            } catch {
                XCTFail("erreur non traduite : \(error)")
            }
        }
    }

    // MARK: - Paiements rapides

    func testPaiementsRapidesOrdreServeur() async throws {
        registry.add("POST", escrowChemin, respond: .json(200, """
        [{"mission_id":"m-2","mission_intitule":"Nuit","etablissement_nom":"Clinique","honoraires_cents":15000,"etat":"RETARDE",
          "date_affichee":"2026-11-04T08:00:00+00:00","mission_date":"2026-10-28T07:00:00+00:00","a_litige":false},
         {"mission_id":"m-1","mission_intitule":"Jour","etablissement_nom":"Clinique","honoraires_cents":24000,"etat":"RESERVE",
          "date_affichee":null,"mission_date":"2026-11-09T07:00:00+00:00","a_litige":false}]
        """))
        let lignes = try await gateway().paiementsRapides(context: TestClient.context)
        XCTAssertEqual(lignes.map(\.missionId), ["m-2", "m-1"])
        XCTAssertEqual(lignes.map(\.honorairesCents), [15000, 24000], "honoraires_cents figés à la confirmation (règle #11)")
        XCTAssertEqual(registry.requests(to: escrowChemin).count, 1)
    }

    func testPaiementsRapidesCorpsNonTableauOuSessionExpiree() async {
        for (statut, corps, attendu) in [(200, #"{"error":"x"}"#, JoleneError.Kind.contract),
                                         (401, #"{"code":"PGRST301","message":"JWT expired"}"#, .unauthorized),
                                         (404, #"{"code":"PGRST202","message":"Could not find the function"}"#, .contract)] {
            registry.reset()
            registry.add("POST", escrowChemin, respond: .json(statut, corps))
            do {
                _ = try await gateway().paiementsRapides(context: TestClient.context)
                XCTFail("corps \(corps) accepté")
            } catch let erreur as JoleneError {
                XCTAssertEqual(erreur.kind, attendu, corps)
            } catch {
                XCTFail("erreur non traduite : \(error)")
            }
        }
    }

    func testMondeSupabaseCableLesRevenus() {
        let gateways = SupabaseGateways.make(client: TestClient.make())
        XCTAssertTrue(gateways.revenus is SupabaseRevenusGateway, "lot 3, T12 câble les revenus")
        XCTAssertEqual(SupabaseRevenusGateway.totauxRPC, "fn_mes_revenus_connect")
        XCTAssertEqual(SupabaseRevenusGateway.escrowRPC, "fn_mes_paiements_escrow")
    }
}
