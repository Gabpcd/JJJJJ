import Foundation

/// Admission d'une signature OTP de recette (port du résultat de
/// `readSignatureSmsStagingAdmission`, `src/lib/signatureSmsStagingAdmission.ts`).
/// Instants au milliseconde près, comme `Date.parse`.
public struct AdmissionSignatureRecette: Equatable, Sendable {
    /// `expiresAt` : fin de la capacité de recette (une heure au plus).
    public var expireLe: Date
    /// `canSend` : un SMS peut encore être demandé (`remaining > 0`).
    public var peutEnvoyer: Bool
    /// `canValidate` : un code envoyé peut être saisi.
    public var peutValider: Bool
    /// `otpExpiresAt` : fin de validité du code, bornée par la capacité ; `nil` sans validation.
    public var otpExpireLe: Date?

    public init(expireLe: Date, peutEnvoyer: Bool, peutValider: Bool, otpExpireLe: Date?) {
        self.expireLe = expireLe; self.peutEnvoyer = peutEnvoyer; self.peutValider = peutValider; self.otpExpireLe = otpExpireLe
    }
}

/// Admission OTP de recette, en lecture seule et liée à l'appelant : la RPC n'existe que sur
/// STAGING (supplément `scripts/ci/sms-signature-staging.sql` l.120-142, absente en production) ;
/// toute réponse inattendue échoue fermé (`nil`, jamais une erreur de contrat). L'appel lui-même
/// appartient au gateway (lot 2, T8) : la règle reçoit une fonction qui l'exécute.
public enum AdmissionRecette {
    /// `STAGING_URL` du web, dérivée de l'allowlist d'environnement (jamais un second littéral).
    public static var urlStaging: String {
        "https://\(JoleneEnvironment.allowedProjectRefs[.staging] ?? "").supabase.co"
    }

    static let dureeMaxCapaciteMs: Int64 = 60 * 60_000
    static let dureeMaxOtpMs: Int64 = 10 * 60_000

    /// Garde d'entrée : URL STAGING exacte et identifiant de contrat au format UUID (sans
    /// accolades ni espaces, casse indifférente). Sinon aucun appel n'est fait.
    public static func doitInterroger(url: String, contratId: String) -> Bool {
        guard JoleneEnvironment.allowedProjectRefs[.staging] != nil, url == urlStaging else { return false }
        return estUUID(contratId)
    }

    /// Origine `https://<hôte>` d'une URL de projet (lot 2, T8 ; revue fraîche de T2, constat 2) : barre finale,
    /// chemin (`/storage/v1`) et casse de l'hôte ignorés ; `nil` hors `https`, avec port, identifiants, requête ou
    /// fragment. La comparaison exacte à `urlStaging` reste celle du web.
    public static func origine(_ url: URL) -> String? {
        guard let composants = URLComponents(url: url, resolvingAgainstBaseURL: false),
              composants.scheme?.lowercased() == "https", let hote = composants.host, !hote.isEmpty,
              composants.port == nil, composants.user == nil, composants.password == nil,
              composants.query == nil, composants.fragment == nil else { return nil }
        return "https://" + hote.lowercased()
    }

    /// Garde d'entrée depuis l'URL du projet du client (gateway Supabase) : son origine doit être `urlStaging`.
    public static func doitInterroger(projet: URL, contratId: String) -> Bool {
        guard let origine = origine(projet) else { return false }
        return doitInterroger(url: origine, contratId: contratId)
    }

    /// `lire(url:…)` depuis l'URL du projet du client, ramenée à son origine.
    public static func lire(projet: URL, contratId: String, maintenant: Date,
                            interroger: (String) async throws -> ValeurJSON) async -> AdmissionSignatureRecette? {
        guard let origine = origine(projet) else { return nil }
        return await lire(url: origine, contratId: contratId, maintenant: maintenant, interroger: interroger)
    }

    /// Lit l'admission : garde d'entrée, un seul appel, puis interprétation stricte. Une erreur de
    /// l'appel (réponse `{ error }`, transport) vaut refus, comme le `catch` du web.
    public static func lire(url: String, contratId: String, maintenant: Date,
                            interroger: (String) async throws -> ValeurJSON) async -> AdmissionSignatureRecette? {
        guard doitInterroger(url: url, contratId: contratId) else { return nil }
        guard let donnees = try? await interroger(contratId) else { return nil }
        return interpreter(donnees, maintenant: maintenant)
    }

    /// Contrôles du web, dans le même ordre de sens : objet `admitted: true`, `remaining` entier de
    /// 0 à 2, `can_send` vrai si et seulement s'il reste un envoi, au moins une action possible,
    /// capacité future d'une heure au plus, code futur de dix minutes au plus quand la validation
    /// est ouverte, aucun `otp_expires_at` sinon.
    public static func interpreter(_ donnees: ValeurJSON, maintenant: Date) -> AdmissionSignatureRecette? {
        guard case .objet(let reponse) = donnees,
              reponse["admitted"] == .booleen(true),
              case .chaine(let expiresAt)? = reponse["expires_at"],
              case .nombre(let restant)? = reponse["remaining"],
              restant.isFinite, restant.rounded(.towardZero) == restant, restant >= 0, restant <= 2,
              case .booleen(let peutEnvoyer)? = reponse["can_send"],
              case .booleen(let peutValider)? = reponse["can_validate"],
              peutEnvoyer == (restant > 0), peutEnvoyer || peutValider else { return nil }

        let maintenantMs = DateHeureParis.millisecondes(maintenant)
        guard let expireMs = millisecondes(expiresAt),
              expireMs > maintenantMs, expireMs <= maintenantMs + dureeMaxCapaciteMs else { return nil }

        var otpExpireMs: Int64?
        if peutValider {
            guard case .chaine(let otpExpiresAt)? = reponse["otp_expires_at"],
                  let expiration = millisecondes(otpExpiresAt),
                  expiration > maintenantMs, expiration <= maintenantMs + dureeMaxOtpMs else { return nil }
            otpExpireMs = min(expiration, expireMs)
        } else if let otp = reponse["otp_expires_at"], otp != .null {
            return nil
        }

        return AdmissionSignatureRecette(
            expireLe: DateHeureParis.date(millisecondes: expireMs),
            peutEnvoyer: peutEnvoyer,
            peutValider: peutValider,
            otpExpireLe: otpExpireMs.map { DateHeureParis.date(millisecondes: $0) }
        )
    }

    /// `Date.parse` restreint à l'ISO 8601 de `to_jsonb(timestamptz)` (échec fermé au-delà).
    private static func millisecondes(_ iso: String) -> Int64? {
        guard let date = try? DateHeureParis.instantJolene(iso) else { return nil }
        return DateHeureParis.millisecondes(date)
    }

    /// `/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i`.
    static func estUUID(_ valeur: String) -> Bool {
        let scalaires = Array(valeur.unicodeScalars)
        guard scalaires.count == 36 else { return false }
        for (index, scalaire) in scalaires.enumerated() {
            if [8, 13, 18, 23].contains(index) {
                guard scalaire == "-" else { return false }
            } else {
                switch scalaire {
                case "0"..."9", "a"..."f", "A"..."F": continue
                default: return false
                }
            }
        }
        return true
    }
}
