import Foundation
import JoleneCore
import Supabase
import XCTest
@testable import JoleneSupabase

/// Paiements déclarés sur Supabase (lot 3, T13, B9 ; fiches `fn_confirmer_paiement_soignant` et
/// `fn_contester_paiement_soignant` de `docs/mobile-swift/CONTRATS_RPC_SOIGNANT.md`, contestation d'après B3, #1118) :
/// - liste `DECLARE` du soignant avec **exactement** les colonnes de `BandeauPaiementDeclare.tsx` l.97 (test-garde contre
///   la source web), noms par `fn_etablissements_safe` seul (repli « Établissement »), missions (l.122), présences
///   (l.132) et créneaux (l.137) ;
/// - confirmer → relecture `CONFIRME` ; `{error:'Paiement déjà confirmé'}` verbatim sans relecture ;
/// - contester : motif envoyé tel que saisi ; `{success, litige_id}` sans relecture `CONTESTE` → erreur, jamais un
///   succès ; `{success:true}` sans `litige_id` non vide → erreur de contrat, même avec une relecture `CONTESTE` (revue
///   B8 n°1, m1) ; `LITIGE_DEJA_OUVERT` verbatim ; 23505 non restituée → message générique, jamais un succès ;
/// - un seul POST par mutation, jamais renvoyé.
final class SupabasePaiementsGatewayTests: XCTestCase {
    private let registry = StubRegistry.shared
    private let paiementsChemin = "/rest/v1/paiements_soignant"
    private let missionsChemin = "/rest/v1/missions"
    private let presencesChemin = "/rest/v1/presences"
    private let creneauxChemin = "/rest/v1/mission_creneaux"
    private let etablissementsChemin = "/rest/v1/rpc/fn_etablissements_safe"
    private let confirmerChemin = "/rest/v1/rpc/fn_confirmer_paiement_soignant"
    private let contesterChemin = "/rest/v1/rpc/fn_contester_paiement_soignant"

    override func setUp() {
        super.setUp()
        registry.reset()
    }

    private func gateway() -> SupabasePaiementsGateway {
        SupabasePaiementsGateway(client: TestClient.make())
    }

    private func source(_ chemin: String) throws -> [String] {
        var racine = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { racine.deleteLastPathComponent() }
        return try String(contentsOf: racine.appendingPathComponent(chemin), encoding: .utf8).components(separatedBy: "\n")
    }

    private static let listeJSON = """
    [{"id":"p-1","montant_net":162.4,"mission_id":"m-1","etablissement_id":"etab-1","reference_virement":null,
      "methode":"VIREMENT","date_paiement":"2026-11-01"},
     {"id":"p-2","montant_net":"256","mission_id":"m-2","etablissement_id":"etab-x","reference_virement":"VIR-2",
      "methode":"CHEQUE","date_paiement":null}]
    """
    private static let missionsJSON = """
    [{"id":"m-1","intitule":"Nuit","debut_le":"2026-11-01T07:00:00+00:00","fin_le":"2026-11-01T15:00:00+00:00",
      "duree_heures":8,"taux_horaire_base":26,"taux_rist_plafonne":null,"rist_plafond_applique":false,"total_brut":208,
      "net_a_payer":224.6}]
    """
    private static let presencesJSON = """
    [{"mission_id":"m-1","pointage_arrivee_le":"2026-11-01T07:05:00+00:00","pointage_depart_le":"2026-11-01T15:00:00+00:00",
      "methode_pointage_arrivee":"GPS","heures_ajustees_litige":null}]
    """

    private static func ligne(statut: String, confirme: Bool = false, conteste: Bool = false) -> String {
        #"{"id":"p-1","montant_net":162.4,"mission_id":"m-1","etablissement_id":"etab-1","reference_virement":null,"methode":"VIREMENT","date_paiement":"2026-11-01","statut":"\#(statut)","confirme_par_soignant":\#(confirme),"conteste":\#(conteste)}"#
    }

    /// Relecture : `?id=eq.p-1` (prédicat) ; la liste filtre `statut=eq.DECLARE`.
    private func stubRelecture(_ corps: String) {
        registry.add("GET", paiementsChemin, where: { $0.query("id") == "eq.p-1" }, respond: .json(200, corps))
    }

    // MARK: - Liste

    func testListeColonnesDuWebFiltresEtDetail() async throws {
        registry.add("GET", paiementsChemin, respond: .json(200, Self.listeJSON))
        registry.add("POST", etablissementsChemin, respond: .json(200, TestClient.etablissementJSON))
        registry.add("GET", missionsChemin, respond: .json(200, Self.missionsJSON))
        registry.add("GET", presencesChemin, respond: .json(200, Self.presencesJSON))
        registry.add("GET", creneauxChemin, respond: .json(200, "[\(TestClient.slotJSON(id: "c-1", missionId: "m-1", debut: "2026-11-01T07:00:00+00:00", fin: "2026-11-01T15:00:00+00:00"))]"))

        let lignes = try await gateway().aConfirmer(context: TestClient.context)

        let liste = try XCTUnwrap(registry.requests(to: paiementsChemin).first)
        XCTAssertEqual(liste.method, "GET")
        XCTAssertEqual(liste.query("select"), SupabasePaiementsGateway.paiementsSelect.filter { !$0.isWhitespace })
        XCTAssertEqual(liste.query("soignant_id"), "eq.\(TestClient.userId)")
        XCTAssertEqual(liste.query("statut"), "eq.DECLARE")
        let etab = try XCTUnwrap(registry.requests(to: etablissementsChemin).first)
        XCTAssertEqual((etab.bodyJSON as? [String: Any])?["p_ids"] as? [String], ["etab-1", "etab-x"])
        let missions = try XCTUnwrap(registry.requests(to: missionsChemin).first)
        XCTAssertEqual(missions.query("select"), SupabasePaiementsGateway.missionsSelect.filter { !$0.isWhitespace })
        XCTAssertEqual(missions.query("id"), "in.(m-1,m-2)")
        let presences = try XCTUnwrap(registry.requests(to: presencesChemin).first)
        XCTAssertEqual(presences.query("select"), SupabasePaiementsGateway.presencesSelect.filter { !$0.isWhitespace })
        XCTAssertEqual(presences.query("mission_id"), "in.(m-1,m-2)")
        XCTAssertEqual(presences.query("order"), "pointage_arrivee_le.asc.nullslast")
        let creneaux = try XCTUnwrap(registry.requests(to: creneauxChemin).first)
        XCTAssertEqual(creneaux.query("select"), SupabasePaiementsGateway.creneauxSelect.filter { !$0.isWhitespace })
        XCTAssertEqual(creneaux.query("order"), "debut.asc.nullslast")
        XCTAssertTrue(registry.unmatched.isEmpty)

        XCTAssertEqual(lignes.map(\.id), ["p-1", "p-2"])
        XCTAssertEqual(lignes.map(\.montantNet), [162.4, 256])
        XCTAssertEqual(lignes[0].etablissementNom, "Clinique des Tests")
        XCTAssertNil(lignes[1].etablissementNom, "nom absent de fn_etablissements_safe : jamais deviné")
        XCTAssertEqual(lignes[0].mission?.intitule, "Nuit")
        XCTAssertEqual(lignes[0].presences.count, 1)
        XCTAssertEqual(lignes[0].creneaux.map(\.id), ["c-1"])
        XCTAssertTrue(lignes[1].creneaux.isEmpty)
    }

    /// Test-garde : colonnes du web mot pour mot (une colonne ajoutée d'un côté seulement ferait diverger les surfaces).
    func testColonnesIdentiquesALaSourceWeb() throws {
        let web = try source("src/components/BandeauPaiementDeclare.tsx")
        XCTAssertTrue(web[96].contains(".select('\(SupabasePaiementsGateway.paiementsSelect)')"), "l.97")
        XCTAssertTrue(web[98].contains(".eq('statut', 'DECLARE')"), "l.99")
        XCTAssertTrue(web[121].contains(".select('\(SupabasePaiementsGateway.missionsSelect)')"), "l.122")
        XCTAssertTrue(web[131].contains(".select('\(SupabasePaiementsGateway.presencesSelect)')"), "l.132")
        XCTAssertTrue(web[136].contains(".select('\(SupabasePaiementsGateway.creneauxSelect)')"), "l.137")
        XCTAssertTrue(web[181].contains("supabase.rpc('\(SupabasePaiementsGateway.confirmerRPC)'"), "l.182")
        XCTAssertTrue(web[187].contains("supabase.rpc('\(SupabasePaiementsGateway.contesterRPC)'"), "l.188")
        // Relecture : colonnes de l.97 plus l'état, toutes lues aussi par `MesGains.tsx` l.102 (droits de colonne).
        let gains = try source("src/pages/MesGains.tsx")[101]
        for colonne in ["statut", "confirme_par_soignant", "conteste"] { XCTAssertTrue(gains.contains(colonne), colonne) }
    }

    func testListeVideSansAutreRequeteEtEchecsDesLectures() async throws {
        registry.add("GET", paiementsChemin, respond: .json(200, "[]"))
        let vide = try await gateway().aConfirmer(context: TestClient.context)
        XCTAssertTrue(vide.isEmpty)
        XCTAssertEqual(registry.requests.count, 1, "aucune mission lue sans paiement (l.102-105)")

        // Noms en échec : repli « Établissement » (le web avale l'erreur) ; missions en échec : section en erreur.
        registry.reset()
        registry.add("GET", paiementsChemin, respond: .json(200, Self.listeJSON))
        registry.add("POST", etablissementsChemin, respond: .json(500, #"{"message":"boom"}"#))
        registry.add("GET", missionsChemin, respond: .json(500, #"{"code":"XX000","message":"boom"}"#))
        do {
            _ = try await gateway().aConfirmer(context: TestClient.context)
            XCTFail("missions en échec : la section doit être en erreur")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur.message, "Impossible de charger les paiements à confirmer.")
        }
    }

    // MARK: - Confirmer

    func testConfirmerRelitCONFIRME() async throws {
        registry.add("POST", confirmerChemin,
                     respond: .json(200, #"{"success":true,"confirme_le":"2026-11-16T10:00:00+00:00","facture_honoraires_id":null}"#))
        stubRelecture(Self.ligne(statut: "CONFIRME", confirme: true))
        let issue = try await gateway().confirmer(id: "p-1", context: TestClient.context)
        guard case let .confirme(relue) = issue else { return XCTFail("confirmation attendue, obtenu \(issue)") }
        XCTAssertEqual(relue.statut, "CONFIRME")
        let appel = try XCTUnwrap(registry.requests(to: confirmerChemin).first)
        XCTAssertEqual(appel.bodyJSON as? [String: String], ["p_paiement_id": "p-1"])
        XCTAssertEqual(registry.requests(to: confirmerChemin).count, 1)
        let relecture = try XCTUnwrap(registry.requests(to: paiementsChemin).first)
        XCTAssertEqual(relecture.query("select"), SupabasePaiementsGateway.relectureSelect.filter { !$0.isWhitespace })
        XCTAssertEqual(relecture.query("soignant_id"), "eq.\(TestClient.userId)")
    }

    func testRefusPaiementDejaConfirmeVerbatimSansRelecture() async throws {
        registry.add("POST", confirmerChemin, respond: .json(200, #"{"error":"Paiement déjà confirmé"}"#))
        let issue = try await gateway().confirmer(id: "p-1", context: TestClient.context)
        XCTAssertEqual(issue, .refuse(message: "Paiement déjà confirmé"))
        XCTAssertTrue(registry.requests(to: paiementsChemin).isEmpty, "un refus n'est pas relu ici (le modèle relit la liste)")
    }

    func testConfirmationAnnonceeSansRelectureProbanteEstUneErreur() async throws {
        registry.add("POST", confirmerChemin, respond: .json(200, #"{"success":true}"#))
        stubRelecture(Self.ligne(statut: "DECLARE"))
        do {
            let issue = try await gateway().confirmer(id: "p-1", context: TestClient.context)
            XCTFail("relecture DECLARE : jamais un succès, obtenu \(issue)")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur, JoleneError(.unknown, "Erreur lors du traitement"))
        }
    }

    func testNonAuthentifieSessionExpireeEtCorpsInattenduContrat() async throws {
        registry.add("POST", confirmerChemin, respond: .json(200, #"{"error":"Non authentifié"}"#))
        do {
            _ = try await gateway().confirmer(id: "p-1", context: TestClient.context)
            XCTFail("session expirée attendue")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur.kind, .unauthorized)
        }
        registry.reset()
        registry.add("POST", confirmerChemin, respond: .json(200, #"{"ok":true}"#))
        do {
            _ = try await gateway().confirmer(id: "p-1", context: TestClient.context)
            XCTFail("corps sans success ni error : contrat")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur.kind, .contract)
        }
    }

    // MARK: - Contester

    func testContesterEnvoieLeMotifTelQueSaisiEtRelitCONTESTE() async throws {
        registry.add("POST", contesterChemin, respond: .json(200, #"{"success":true,"litige_id":"l-1"}"#))
        stubRelecture(Self.ligne(statut: "CONTESTE", conteste: true))
        let issue = try await gateway().contester(id: "p-1", motif: " Montant erroné ", context: TestClient.context)
        guard case let .conteste(relue, litige) = issue else { return XCTFail("contestation attendue, obtenu \(issue)") }
        XCTAssertEqual(relue.statut, "CONTESTE")
        XCTAssertEqual(litige, "l-1")
        let appel = try XCTUnwrap(registry.requests(to: contesterChemin).first)
        XCTAssertEqual(appel.bodyJSON as? [String: String], ["p_paiement_id": "p-1", "p_motif": " Montant erroné "])
        XCTAssertEqual(registry.requests(to: contesterChemin).count, 1)
    }

    /// `{success, litige_id}` sans relecture `CONTESTE` → erreur, jamais un succès (relecture `DECLARE` ou ligne absente).
    func testSuccesSansRelectureCONTESTEEstUneErreur() async throws {
        for relue in [Self.ligne(statut: "DECLARE"), "null"] {
            registry.reset()
            registry.add("POST", contesterChemin, respond: .json(200, #"{"success":true,"litige_id":"l-1"}"#))
            registry.add("GET", paiementsChemin, respond: .json(200, relue == "null" ? "[]" : "[\(relue)]"))
            do {
                let issue = try await gateway().contester(id: "p-1", motif: "Montant erroné", context: TestClient.context)
                XCTFail("jamais un succès sans relecture CONTESTE, obtenu \(issue)")
            } catch let erreur as JoleneError {
                XCTAssertEqual(erreur.message, "Erreur lors du traitement", relue)
            }
            XCTAssertEqual(registry.requests(to: contesterChemin).count, 1, "jamais renvoyée")
        }
    }

    /// Revue B8 n°1 de T13, m1 : la preuve d'une contestation est `{success:true, litige_id}` de B3 (l.25837) **et** la
    /// relecture `CONTESTE` ; une ligne `CONTESTE` seule ne prouve pas le litige (statut aussi écrit par un UPDATE direct
    /// sous `pol_paie_soig_update` ou par `fn_ouvrir_litige_rate_limited`). Un succès sans identifiant de litige non
    /// vide est un décalage de contrat, jamais un succès, même si la relecture rend `CONTESTE` ; la ligne n'est pas
    /// relue ici (le modèle relit la liste après toute issue) et la mutation n'est jamais renvoyée.
    func testSuccesSansLitigeIdEstUneErreurDeContratMemeAvecRelectureCONTESTE() async throws {
        for corps in [#"{"success":true}"#, #"{"success":true,"litige_id":null}"#, #"{"success":true,"litige_id":""}"#,
                      #"{"success":true,"litige_id":"   "}"#, #"{"success":true,"litige_id":42}"#] {
            registry.reset()
            registry.add("POST", contesterChemin, respond: .json(200, corps))
            stubRelecture(Self.ligne(statut: "CONTESTE", conteste: true))
            do {
                let issue = try await gateway().contester(id: "p-1", motif: "Montant erroné", context: TestClient.context)
                XCTFail("\(corps) : jamais un succès sans litige_id, obtenu \(issue)")
            } catch let erreur as JoleneError {
                XCTAssertEqual(erreur, JoleneError(.contract, SupabaseErrorMapping.contractMessage), corps)
            }
            XCTAssertEqual(registry.requests(to: contesterChemin).count, 1, "\(corps) : jamais renvoyée")
            XCTAssertTrue(registry.requests(to: paiementsChemin).isEmpty, "\(corps) : contrat rompu, aucune relecture ici")
        }
    }

    func testRefusDeB3VerbatimLitigeDejaOuvertEtMotif() async throws {
        let refus: [(String, String)] = [
            (#"{"error":"Un litige de ce type est déjà ouvert pour cette mission.","error_code":"LITIGE_DEJA_OUVERT"}"#,
             "Un litige de ce type est déjà ouvert pour cette mission."),
            (#"{"error":"Motif requis","error_code":"MOTIF_INVALIDE"}"#, "Motif requis"),
            (#"{"error":"Paiement déjà contesté","error_code":"DEJA_CONTESTE"}"#, "Paiement déjà contesté"),
            (#"{"error":"Non authentifié ou compte inactif","error_code":"NON_AUTHENTIFIE"}"#, "Non authentifié ou compte inactif"),
        ]
        for (corps, message) in refus {
            registry.reset()
            registry.add("POST", contesterChemin, respond: .json(200, corps))
            let issue = try await gateway().contester(id: "p-1", motif: "Montant erroné", context: TestClient.context)
            XCTAssertEqual(issue, .refuse(message: message))
            XCTAssertTrue(registry.requests(to: paiementsChemin).isEmpty)
        }
    }

    /// 23505 d'une autre contrainte d'unicité (B3 la relève par `RAISE`) : message générique, jamais le détail technique
    /// ni un succès.
    func testUnicite23505MessageGeneriqueJamaisUnSucces() async throws {
        registry.add("POST", contesterChemin, respond: .json(409, #"""
        {"code":"23505","details":"Key (mission_id, type_litige)=(m-1, AUTRE) already exists.","hint":null,"message":"duplicate key value violates unique constraint \"uq_autre\""}
        """#))
        do {
            let issue = try await gateway().contester(id: "p-1", motif: "Montant erroné", context: TestClient.context)
            XCTFail("23505 : jamais un succès, obtenu \(issue)")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur, JoleneError(.unknown, "Erreur lors du traitement"))
            XCTAssertFalse(erreur.message.contains("duplicate"), "aucun détail technique")
        }
        XCTAssertEqual(registry.requests(to: contesterChemin).count, 1, "jamais renvoyée")
        XCTAssertTrue(registry.requests(to: paiementsChemin).isEmpty)
    }

    func testSupabaseGatewaysCableLesPaiementsDeclares() {
        let gateways = SupabaseGateways.make(client: TestClient.make())
        XCTAssertTrue(gateways.paiements is SupabasePaiementsGateway)
    }
}
