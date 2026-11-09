import Foundation
import JoleneCore
import Supabase
import XCTest
@testable import JoleneSupabase

/// Avatar sur Supabase (lot 3, T10 ; blueprint §3 T10, D14) : dépôt `jolene-documents/<uid>/avatar-<ms>.jpg` en
/// `image/jpeg` sans écrasement, URL signée de 5 ans, refus 4xx du stockage = refus certain, 5xx et réseau = issue
/// inconnue ; enchaînement réel `EnvoiAvatar` → un 403 du stockage n'envoie AUCUN `p_avatar_url`.
final class SupabaseAvatarStorageTests: XCTestCase {
    private let registry = StubRegistry.shared
    private let chemin = "\(TestClient.userId)/avatar-1793577600000.jpg"
    private var depot: String { "/storage/v1/object/jolene-documents/\(chemin)" }
    private var signature: String { "/storage/v1/object/sign/jolene-documents/\(chemin)" }
    private let ecriture = "/rest/v1/rpc/fn_modifier_mon_profil"
    private let lecture = "/rest/v1/rpc/fn_mon_profil_soignant_complet"
    private let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10])

    override func setUp() {
        super.setUp()
        registry.reset()
    }

    private func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func stockage() -> SupabaseAvatarStorage {
        SupabaseAvatarStorage(client: TestClient.make(), session: session())
    }

    private var urlSignee: String {
        "\(TestClient.url.absoluteString)/storage/v1/object/sign/jolene-documents/\(chemin)?token=jeton-de-test"
    }

    func testDepotCheminContentTypeEtSansEcrasement() async throws {
        registry.add("POST", depot, respond: .json(200, #"{"Key":"jolene-documents/\#(chemin)","Id":"obj-1"}"#))
        try await stockage().deposer(chemin: chemin, jpeg: jpeg, context: TestClient.context)
        let requete = try XCTUnwrap(registry.requests(to: depot).first)
        XCTAssertEqual(requete.method, "POST")
        XCTAssertEqual(requete.header("x-upsert"), "false", "`upsert: false` : un objet n'est jamais remplacé")
        let corps = try XCTUnwrap(requete.body)
        XCTAssertTrue(String(decoding: corps, as: UTF8.self).contains("Content-Type: image/jpeg"), "partie du fichier en image/jpeg")
        XCTAssertNotNil(corps.range(of: jpeg), "octets JPEG envoyés tels quels")
        XCTAssertEqual(registry.requests.count, 1)
        XCTAssertTrue(registry.unmatched.isEmpty)
    }

    func testRefus4xxDuStockageEstUnRefusCertain() async throws {
        for (statut, corps) in [(403, #"{"statusCode":"403","error":"Unauthorized","message":"new row violates row-level security policy"}"#),
                                (409, #"{"statusCode":"409","error":"Duplicate","message":"The resource already exists"}"#),
                                (400, "pas du JSON")] {
            registry.reset()
            registry.add("POST", depot, respond: .json(statut, corps))
            do {
                try await stockage().deposer(chemin: chemin, jpeg: jpeg, context: TestClient.context)
                XCTFail("\(statut) accepté")
            } catch let refus as RefusStockageAvatar {
                XCTAssertEqual(refus.statut, statut)
            }
        }
    }

    func testErreur5xxOuReseauIssueInconnue() async throws {
        registry.add("POST", depot, respond: .json(500, #"{"statusCode":"500","error":"Internal","message":"boom"}"#))
        do {
            try await stockage().deposer(chemin: chemin, jpeg: jpeg, context: TestClient.context)
            XCTFail("500 accepté")
        } catch {
            XCTAssertFalse(error is RefusStockageAvatar, "un 5xx n'est pas un refus certain")
            XCTAssertTrue(error is JoleneError)
            XCTAssertFalse((error as? JoleneError)?.message.contains("boom") ?? true, "aucun message serveur affiché")
        }
        registry.reset()
        registry.add("POST", depot, respond: .networkFailure())
        do {
            try await stockage().deposer(chemin: chemin, jpeg: jpeg, context: TestClient.context)
            XCTFail("coupure acceptée")
        } catch {
            XCTAssertEqual((error as? JoleneError)?.kind, .network)
        }
    }

    func testURLSigneeCinqAns() async throws {
        registry.add("POST", signature, respond: .json(200, #"{"signedURL":"/object/sign/jolene-documents/\#(chemin)?token=jeton-de-test"}"#))
        let url = try await stockage().urlSignee(chemin: chemin, dureeSecondes: AvatarProfil.dureeURLSigneeSecondes,
                                                 context: TestClient.context)
        XCTAssertEqual(url.absoluteString, urlSignee)
        let corps = try XCTUnwrap(registry.requests(to: signature).first?.bodyJSON as? NSDictionary)
        XCTAssertEqual(corps["expiresIn"] as? Int, 157_680_000)
        XCTAssertTrue(AvatarProfil.urlDesigne(url.absoluteString, chemin: chemin))
    }

    func testLectureDeLImageParLURLSignee() async throws {
        let chemin = "/storage/v1/object/sign/jolene-documents/\(self.chemin)"
        registry.add("GET", chemin, respond: StubResponse(status: 200, headers: ["Content-Type": "image/jpeg"], body: jpeg, failure: nil))
        let image = await stockage().image(url: URL(string: urlSignee)!)
        XCTAssertEqual(image, jpeg)
        let requete = try XCTUnwrap(registry.requests(to: chemin).first)
        XCTAssertNil(requete.header("Authorization"), "lecture par le jeton de l'URL, aucun en-tête ajouté")
        registry.reset()
        registry.add("GET", chemin, respond: .json(404, "{}"))
        let absente = await stockage().image(url: URL(string: urlSignee)!)
        XCTAssertNil(absente)
        let nonHttps = await stockage().image(url: URL(string: "http://exemple.invalid/a.jpg")!)
        XCTAssertNil(nonHttps)
    }

    /// Revue B8 de T10, m11 : l'URL signée (jeton de 5 ans) et les octets de l'image ne sont conservés dans AUCUN cache
    /// HTTP ni magasin de cookies partagé : session par défaut éphémère, sans cache ni cookie ni identifiants, requête
    /// qui ignore tout cache local (même avec une session injectée).
    func testLectureDeLImageSansCacheNiCookie() async throws {
        let configuration = SupabaseAvatarStorage.sessionParDefaut.configuration
        XCTAssertNil(configuration.urlCache, "aucun cache HTTP (ni disque ni mémoire)")
        XCTAssertEqual(configuration.requestCachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertNil(configuration.httpCookieStorage, "aucun magasin de cookies")
        XCTAssertEqual(configuration.httpCookieAcceptPolicy, .never)
        XCTAssertFalse(configuration.httpShouldSetCookies)
        XCTAssertNil(configuration.urlCredentialStorage, "aucun identifiant mémorisé")
        XCTAssertTrue(SupabaseAvatarStorage.sessionParDefaut === SupabaseAvatarStorage.sessionParDefaut,
                      "une seule session pour l'app, jamais une session par appel")

        let chemin = "/storage/v1/object/sign/jolene-documents/\(self.chemin)"
        registry.add("GET", chemin, respond: StubResponse(status: 200, headers: ["Content-Type": "image/jpeg"], body: jpeg, failure: nil))
        _ = await stockage().image(url: URL(string: urlSignee)!)
        let requete = try XCTUnwrap(registry.requests(to: chemin).first)
        XCTAssertEqual(requete.cachePolicy, .reloadIgnoringLocalCacheData, "requête sans cache local")
    }

    // MARK: - Enchaînement réel (`EnvoiAvatar` + Supabase)

    private func envoi(recus: RecusAvatarEnMemoire) -> EnvoiAvatar {
        let client = TestClient.make()
        return EnvoiAvatar(stockage: SupabaseAvatarStorage(client: client, session: session()),
                           profil: SupabaseProfilGateway(client: client), recus: recus,
                           horloge: FixedClock(Date(timeIntervalSince1970: 1_793_577_600)), registre: RegistreEnvoisAvatar(),
                           identifiant: { "essai-1" })
    }

    private func ligne(avatar: String?) -> String {
        let valeur = avatar.map { #""\#($0)""# } ?? "null"
        return """
        {"id":"\(TestClient.userId)","prenom":"Léa","nom":"Martin","email":"\(TestClient.email)","telephone":null,
         "date_naissance":"1990-05-14","profession":"IDE","numero_rpps":null,"rpps_verifie":false,"type_contrat":"CDD",
         "type_exercice":"SALARIE","adresse_lat":45.75,"adresse_lng":4.85,"rayon_deplacement_km":40,"bio":null,
         "annees_experience":7,"types_contrat_acceptes":"CDD","avatar_url":\(valeur),"taux_horaire_minimum":null,
         "ville_recherche":null}
        """
    }

    func testRefus403DuStockageAucunPAvatarUrlEnvoye() async throws {
        registry.add("POST", depot, respond: .json(403, #"{"statusCode":"403","error":"Unauthorized","message":"rls"}"#))
        let recus = RecusAvatarEnMemoire()
        do {
            _ = try await envoi(recus: recus).televerser(jpeg: jpeg, context: TestClient.context)
            XCTFail("refus attendu")
        } catch let refus as RefusAvatar {
            XCTAssertEqual(refus.message, "Une erreur est survenue lors de l'upload. Veuillez réessayer.")
        }
        XCTAssertTrue(registry.requests(to: ecriture).isEmpty, "aucun `p_avatar_url` envoyé après un 403 du stockage")
        XCTAssertTrue(registry.requests(to: signature).isEmpty, "aucune URL signée")
        XCTAssertEqual(registry.requests(to: depot).count, 1, "aucun renvoi")
        let reste = try await recus.lire(userId: TestClient.userId)
        XCTAssertNil(reste)
    }

    func testSuccesUnSeulParametreEtRelecture() async throws {
        registry.add("POST", depot, respond: .json(200, #"{"Key":"jolene-documents/\#(chemin)","Id":"obj-1"}"#))
        registry.add("POST", signature, respond: .json(200, #"{"signedURL":"/object/sign/jolene-documents/\#(chemin)?token=jeton-de-test"}"#))
        registry.add("POST", ecriture, respond: .json(200, #"{"success":true}"#))
        registry.add("POST", lecture, respond: .json(200, ligne(avatar: urlSignee)))
        let recus = RecusAvatarEnMemoire()
        let url = try await envoi(recus: recus).televerser(jpeg: jpeg, context: TestClient.context)
        XCTAssertEqual(url.absoluteString, urlSignee)
        let corps = try XCTUnwrap(registry.requests(to: ecriture).first?.bodyJSON as? NSDictionary)
        XCTAssertEqual(corps.allKeys as? [String], ["p_avatar_url"], "seul `p_avatar_url` part")
        XCTAssertEqual(corps["p_avatar_url"] as? String, urlSignee)
        XCTAssertEqual(registry.requests(to: lecture).count, 1, "aucun reçu : aucune relecture préalable ; relecture après `{success:true}`")
        let reste = try await recus.lire(userId: TestClient.userId)
        XCTAssertNil(reste)
    }

    func testArretEntreDepotEtRPCRelectureAuRetourSansSecondEnvoi() async throws {
        let recus = RecusAvatarEnMemoire()
        try await recus.ecrire(RecuAvatar(userId: TestClient.userId, attemptId: "essai-0", chemin: chemin, phase: .stored))
        registry.add("POST", lecture, respond: .json(200, ligne(avatar: nil)))
        let issue = try await envoi(recus: recus).reconcilier(context: TestClient.context)
        XCTAssertEqual(issue, .nonConfirmee)
        XCTAssertEqual(registry.requests(to: lecture).count, 1, "relecture de `avatar_url`")
        XCTAssertTrue(registry.requests(to: depot).isEmpty, "aucun second dépôt")
        XCTAssertTrue(registry.requests(to: ecriture).isEmpty, "aucun `p_avatar_url` rejoué")
    }
}
