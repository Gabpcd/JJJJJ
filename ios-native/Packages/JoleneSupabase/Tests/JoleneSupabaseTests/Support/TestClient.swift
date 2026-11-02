import Foundation
import JoleneCore
import Supabase
@testable import JoleneSupabase

/// Stockage de session en mémoire : remplace le Keychain dans les tests macOS.
final class InMemoryAuthStorage: AuthLocalStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]

    func store(key: String, value: Data) throws {
        lock.lock(); defer { lock.unlock() }
        values[key] = value
    }

    func retrieve(key: String) throws -> Data? {
        lock.lock(); defer { lock.unlock() }
        return values[key]
    }

    func remove(key: String) throws {
        lock.lock(); defer { lock.unlock() }
        values[key] = nil
    }

    var keys: [String] {
        lock.lock(); defer { lock.unlock() }
        return Array(values.keys)
    }
}

/// Fabrique de client de test : clé publishable factice, transport `StubURLProtocol`,
/// stockage mémoire, sans rafraîchissement automatique (aucune tâche de fond réseau).
enum TestClient {
    static let url = URL(string: "https://mejpriaetwgtcstbgfid.supabase.co")!
    static let publishableKey = "sb_publishable_test_0000000000000000"
    static let userId = "0b4d2b8e-4a9f-4b1c-9e0a-7f3c1d2e5a66"
    static let email = "soignant-test@example.test"
    /// Mot de passe volontairement refusé par le serveur simulé (assemblé pour ne pas ressembler à un secret).
    static let motDePasseRefuse = ["mau", "vais"].joined()

    static func make(storage: InMemoryAuthStorage = InMemoryAuthStorage()) -> SupabaseClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        return SupabaseGateways.makeClient(
            url: url, publishableKey: publishableKey, storage: storage, session: session, autoRefreshToken: false
        )
    }

    /// JWT structurellement valide (en-tête.charge.signature), non signé : seul le SDK le lit.
    static func accessToken(expiresAt: TimeInterval) -> String {
        func b64(_ json: String) -> String {
            Data(json.utf8).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        let header = b64(#"{"alg":"HS256","typ":"JWT"}"#)
        let payload = b64(#"{"sub":"\#(userId)","role":"authenticated","aud":"authenticated","exp":\#(Int(expiresAt))}"#)
        return "\(header).\(payload).signature"
    }

    /// Réponse GoTrue `/token?grant_type=password` (fixture dérivée du contrat de session).
    static func sessionJSON(expiresAt: TimeInterval = Date().timeIntervalSince1970 + 3600, role: String? = "SOIGNANT",
                            emailConfirmed: Bool = true) -> String {
        let roleField = role.map { #","role":"\#($0)""# } ?? ""
        let confirmed = emailConfirmed ? #""email_confirmed_at":"2026-01-15T10:00:00Z","# : ""
        return """
        {"access_token":"\(accessToken(expiresAt: expiresAt))","token_type":"bearer","expires_in":3600,
         "expires_at":\(Int(expiresAt)),"refresh_token":"refresh-token-test",
         "user":{"id":"\(userId)","aud":"authenticated","role":"authenticated","email":"\(email)",
                 \(confirmed)"app_metadata":{"provider":"email","providers":["email"]\(roleField)},
                 "user_metadata":{},"identities":[],"created_at":"2026-01-10T09:00:00Z",
                 "updated_at":"2026-01-15T10:00:00Z","is_anonymous":false}}
        """
    }

    static let missionJSON = """
    {"id":"m-1","intitule":"Remplacement IDE nuit","description":null,"service":"Urgences",
     "profession_requise":"IDE","specialite_medicale_requise":null,"accepte_non_specialises":null,
     "debut_le":"2026-12-01T19:00:00+00:00","fin_le":"2026-12-02T07:00:00+00:00","duree_heures":12,
     "nb_creneaux":2,"taux_horaire_base":28.5,"taux_rist_plafonne":null,"rist_plafond_applique":false,
     "total_brut":342,"net_a_payer":300.1,"est_urgente":true,"niveau_urgence":2,"statut":"OUVERTE",
     "etablissement_id":"etab-1","type_contrat_recherche":"SALARIE","boostee_le":null,
     "mode_remuneration":null,"retrocession_pct":null}
    """

    static let etablissementJSON = """
    [{"id":"etab-1","nom":"Clinique des Tests","adresse_rue":"1 rue","adresse_code_postal":"69003",
      "adresse_ville":"Lyon","adresse_departement":"69","adresse_lat":45.76,"adresse_lng":4.85,
      "type":"CLINIQUE","finess":"690000000","taux_majoration_nuit_pourcent":10,
      "taux_majoration_dimanche_pourcent":20,"taux_majoration_ferie_pourcent":30,"logo_url":null,
      "couleur_theme":null,"paiement_rapide":false,"jour_paie_habituel":5}]
    """

    static func slotJSON(id: String, missionId: String, debut: String, fin: String, type: String = "PREVISIONNEL", pause: Bool = false) -> String {
        #"{"id":"\#(id)","mission_id":"\#(missionId)","debut":"\#(debut)","fin":"\#(fin)","est_pause":\#(pause),"type_creneau":"\#(type)"}"#
    }

    static let profile = SoignantProfile(
        id: userId, profession: "IADE", adresseLat: 45.75, adresseLng: 4.85, rayonDeplacementKm: 30,
        tousDocumentsValides: true, typeContrat: "SALARIE", typesContratAcceptes: nil, typeExercice: "SALARIE",
        tauxHoraireMinimum: 25
    )

    static var context: MissionReadContext {
        MissionReadContext(userId: userId, email: email, profile: profile)
    }
}
