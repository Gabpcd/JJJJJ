import Foundation
import JoleneCore
import Supabase
import XCTest
@testable import JoleneSupabase

/// Session établissement sur Supabase (lot 5 T1, §2.2, D2) : `fn_mes_permissions_etab` appelée avec le
/// corps exact `{"p_etablissement_id":null}`, décodée fail-closed ; `fn_mon_etablissement_complet`
/// réduite à son sous-ensemble, aucune colonne Stripe ou bancaire décodée.
final class SupabaseEtabSessionGatewayTests: XCTestCase {
    private let registry = StubRegistry.shared
    private let permissionsPath = "/rest/v1/rpc/fn_mes_permissions_etab"
    private let profilPath = "/rest/v1/rpc/fn_mon_etablissement_complet"
    private let etablissementId = "6f1c2a3b-4d5e-4f60-8a7b-9c0d1e2f3a4b"

    override func setUp() {
        super.setUp()
        registry.reset()
    }

    private func gateway() -> SupabaseEtabSessionGateway { SupabaseEtabSessionGateway(client: TestClient.make()) }

    private func echec(_ appel: () async throws -> Void, file: StaticString = #filePath, line: UInt = #line) async -> JoleneError? {
        do {
            try await appel()
            XCTFail("attendu : erreur levée", file: file, line: line)
            return nil
        } catch let error as JoleneError {
            return error
        } catch {
            XCTFail("type d'erreur inattendu : \(error)", file: file, line: line)
            return nil
        }
    }

    // MARK: - fn_mes_permissions_etab

    func testCorpsExactPerimetreServeur() async throws {
        registry.add("POST", permissionsPath, respond: .json(200, """
        {"success":true,"role":"RH","etablissement_id":"\(etablissementId)",
         "permissions":{"gerer_equipe":false,"supprimer_compte":false,"profil_etab":false,"paiement":false,
                        "lecture_paiement":false,"missions":true,"candidatures":true,"contrats":true,"pointage":true,
                        "rh":true,"lecture":true}}
        """))
        let lu = try await gateway().permissions(etablissementId: nil)
        XCTAssertEqual(lu.role, .rh)
        XCTAssertEqual(lu.etablissementId, etablissementId)
        XCTAssertEqual(lu.permissions.accordees, [.missions, .candidatures, .contrats, .pointage, .rh, .lecture])
        let requete = try XCTUnwrap(registry.requests(to: permissionsPath).first)
        XCTAssertEqual(requete.method, "POST")
        XCTAssertEqual(String(data: try XCTUnwrap(requete.body), encoding: .utf8), #"{"p_etablissement_id":null}"#,
                       "D2 : le périmètre est mon_etablissement_id(), jamais le candidat client")
        XCTAssertEqual(requete.header("X-Client-Info"), "jolene-ios/2.0.0")
        XCTAssertEqual(registry.requests.count, 1, "une seule requête, aucun renvoi")
        XCTAssertTrue(registry.unmatched.isEmpty)
    }

    func testIdentifiantExpliciteCanoniqueEtRefusAvantReseau() async throws {
        registry.add("POST", permissionsPath, respond: .json(200, #"{"success":true,"role":null,"etablissement_id":null,"permissions":{}}"#))
        _ = try await gateway().permissions(etablissementId: etablissementId.uppercased())
        let corps = try XCTUnwrap(registry.requests(to: permissionsPath).first?.bodyJSON as? [String: Any])
        XCTAssertEqual(corps["p_etablissement_id"] as? String, etablissementId, "uuid canonique en minuscules")
        registry.reset()
        for invalide in ["", "demo-etab-1", "00000000-0000-0000-0000-000000000000"] {
            let erreur = await echec { _ = try await self.gateway().permissions(etablissementId: invalide) }
            XCTAssertEqual(erreur, JoleneError(.contract, SupabaseErrorMapping.contractMessage), invalide)
        }
        XCTAssertTrue(registry.requests.isEmpty, "identifiant invalide refusé avant tout appel réseau")
    }

    func testFormesSansRoleEtCompteInactif() async throws {
        registry.add("POST", permissionsPath, respond: .json(200, #"{"success":false,"role":null,"permissions":{}}"#))
        let inactif = try await gateway().permissions(etablissementId: nil)
        XCTAssertEqual(inactif, PermissionsEtabResult(success: false, role: nil, etablissementId: nil, permissions: .aucune))
        registry.reset()
        registry.add("POST", permissionsPath, respond: .json(200, #"{"success":true,"role":null,"etablissement_id":null,"permissions":{}}"#))
        let revoque = try await gateway().permissions(etablissementId: nil)
        XCTAssertEqual(revoque, PermissionsEtabResult(success: true, role: nil, etablissementId: nil, permissions: .aucune))
        registry.reset()
        registry.add("POST", permissionsPath, respond: .json(200, """
        {"success":true,"role":"ADMIN_PLATEFORME","etablissement_id":"\(etablissementId)","permissions":{"lecture":true}}
        """))
        let admin = try await gateway().permissions(etablissementId: nil)
        XCTAssertEqual(admin.role, .inconnu("ADMIN_PLATEFORME"), "rôle inconnu conservé : l'espace ne l'ouvre pas (T2)")
    }

    func testFormesInattenduesSontDesRefusDeContrat() async {
        for corps in ["null", "[]", #""texte""#, #"{"role":"RH"}"#, #"{"success":"true","role":"RH"}"#] {
            registry.reset()
            registry.add("POST", permissionsPath, respond: .json(200, corps))
            let erreur = await echec { _ = try await self.gateway().permissions(etablissementId: nil) }
            XCTAssertEqual(erreur, JoleneError(.contract, SupabaseErrorMapping.contractMessage), corps)
        }
        registry.reset()
        registry.add("POST", permissionsPath, respond: .json(200, #"{"error":"Erreur inattendue"}"#))
        let verbatim = await echec { _ = try await self.gateway().permissions(etablissementId: nil) }
        XCTAssertEqual(verbatim, JoleneError(.unknown, "Erreur inattendue"))
    }

    func testTransportReseauSessionEtContrat() async {
        registry.add("POST", permissionsPath, respond: .networkFailure())
        let reseau = await echec { _ = try await self.gateway().permissions(etablissementId: nil) }
        XCTAssertEqual(reseau?.kind, .network)
        registry.reset()
        registry.add("POST", permissionsPath, respond: .json(401, #"{"code":"PGRST301","message":"JWT expired","details":null,"hint":null}"#))
        let session = await echec { _ = try await self.gateway().permissions(etablissementId: nil) }
        XCTAssertEqual(session?.kind, .unauthorized)
        registry.reset()
        registry.add("POST", permissionsPath, respond: .json(404, #"{"code":"PGRST202","message":"Could not find the function","details":null,"hint":null}"#))
        let contrat = await echec { _ = try await self.gateway().permissions(etablissementId: nil) }
        XCTAssertEqual(contrat, JoleneError(.contract, SupabaseErrorMapping.contractMessage))
        XCTAssertEqual(registry.requests(to: permissionsPath).count, 1, "refus définitif : aucun renvoi")
    }

    // MARK: - fn_mon_etablissement_complet

    func testProfilSousEnsembleSansColonneSensible() async throws {
        registry.add("POST", profilPath, respond: .json(200, """
        {"id":"\(etablissementId)","nom":"Clinique des Tests","siret":"00000000000000","type":"CLINIQUE",
         "stripe_customer_id":"cus_fictif","stripe_account_id":"acct_fictif","iban_last4":"0000","rib_s3_key":"rib/fictif.pdf",
         "taux_commission_negocie":12,"logo_url":null,"est_secteur_public":false,"peut_publier_missions":true,
         "statut_verification":"VERIFIE","contrat_service_signe":true,"bloque_auto_le":null,
         "bloque_auto_raisons":{"montant_du":1200},"note_moyenne":4.5}
        """))
        let profil = try await gateway().profil()
        XCTAssertEqual(profil, EtablissementProfil(id: etablissementId, nom: "Clinique des Tests", logoUrl: nil, type: "CLINIQUE",
                                                   peutPublierMissions: true, statutVerification: "VERIFIE", bloqueAutoLe: nil,
                                                   contratServiceSigne: true, estSecteurPublic: false))
        // Le modèle n'expose aucune des colonnes servies au-delà du sous-ensemble.
        let encode = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(profil)) as? [String: Any])
        for cle in ["siret", "stripe_customer_id", "stripe_account_id", "iban_last4", "rib_s3_key", "taux_commission_negocie",
                    "bloque_auto_raisons", "note_moyenne"] {
            XCTAssertNil(encode[cle], "\(cle) exposée par le modèle")
        }
        XCTAssertFalse("\(profil)".contains("cus_fictif"))
        XCTAssertFalse("\(profil)".contains("0000\""))
        let requete = try XCTUnwrap(registry.requests(to: profilPath).first)
        XCTAssertTrue((requete.bodyJSON as? [String: Any])?.isEmpty ?? true, "fonction sans paramètre")
        XCTAssertTrue(registry.unmatched.isEmpty)
    }

    func testProfilIntrouvableVerbatimEtFormesInattendues() async {
        // l.44603 / l.44647 : `{error:'Etablissement introuvable'}` en HTTP 200.
        registry.add("POST", profilPath, respond: .json(200, #"{"error":"Etablissement introuvable"}"#))
        let introuvable = await echec { _ = try await self.gateway().profil() }
        XCTAssertEqual(introuvable, JoleneError(.unknown, "Etablissement introuvable"))
        for corps in ["null", "[]", #"{"nom":"Sans identifiant"}"#, #"{"success":false,"id":"e"}"#] {
            registry.reset()
            registry.add("POST", profilPath, respond: .json(200, corps))
            let erreur = await echec { _ = try await self.gateway().profil() }
            XCTAssertEqual(erreur, JoleneError(.contract, SupabaseErrorMapping.contractMessage), corps)
        }
    }

    func testProfil42501ResteSessionExpiree() async {
        // Liste blanche vide (aucune exception dans le corps) : comportement du lot 0.
        registry.add("POST", profilPath, respond: .json(403, #"{"code":"42501","message":"permission denied for function","details":null,"hint":null}"#))
        let erreur = await echec { _ = try await self.gateway().profil() }
        XCTAssertEqual(erreur, JoleneError(.unauthorized, SupabaseErrorMapping.unauthorizedMessage))
    }
}
