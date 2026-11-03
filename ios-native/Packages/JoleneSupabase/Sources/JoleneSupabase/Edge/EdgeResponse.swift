import Foundation
import JoleneCore
import Supabase

/// Lecture tolérante des réponses d'edge functions (blueprint `docs/mobile-swift/LOT3_PLAN.md`
/// §2.4, tranche T1), commune à `register-soignant` (T8), `stripe-connect-status` et
/// `stripe-connect-onboard` (T14a) et à `delete-account` (lot 1, T8, comportement inchangé).
///
/// Formes réelles (fiches « Edge … » de `docs/mobile-swift/CONTRATS_RPC_SOIGNANT.md`) :
/// - `{ok:false, code, message, error, details?}` : `_shared/errors.ts` l.34-46 (`error` = miroir
///   de `message`) ;
/// - `{error:'texte'}` : `_shared/admin-auth.ts` et la plupart des refus ;
/// - `{error:'CODE'}` et `{error:'CODE', message:'texte'}` : Stripe Connect (code machine dans
///   `error`, `mapStripeError` y met aussi le code Stripe brut, souvent en minuscules) ;
/// - `{error, error_code}` : `delete-account`.
///
/// Règles : supabase-swift lève `FunctionsError.httpError(code:data:)` sur tout statut hors 2xx —
/// `invoquer` en lit le corps AVANT tout mapping et le rend comme une réponse ; 401 → session
/// expirée quel que soit le corps (passerelle comprise, revue B8 de T0, constat 5) ; refus
/// structuré sinon, texte serveur verbatim, `fallback` si le corps n'est pas lisible ; un 2xx dont
/// le corps n'est pas un objet JSON (portail captif, proxy, corps vide, `null`, tableau, scalaire)
/// est un refus au `fallback`, jamais un succès fabriqué (PRINCIPES §3, revue B8 de T1) ; un code
/// machine n'est jamais affiché. Une seule requête, aucun renvoi. Chaque gateway exige ensuite les
/// clés qui conditionnent son succès (ex. `success === true` pour `delete-account`).
public struct EdgeResponse: Equatable, Sendable {
    /// Statut HTTP de la réponse (2xx, ou celui de `FunctionsError.httpError`).
    public let statut: Int
    public let raw: AnyJSON

    public init(statut: Int, raw: AnyJSON) {
        self.statut = statut
        self.raw = raw
    }

    /// Corps lu sans exigence (`lire`) ; l'interprétation (`estRefus`) écarte tout corps non objet.
    public init(statut: Int, corps: Data) {
        self.init(statut: statut, raw: Self.lire(corps))
    }

    /// Corps vide ou qui n'est pas du JSON (page HTML de passerelle ou de portail captif) → `null` ;
    /// tout JSON valide est rendu tel quel, objet ou non (`[…]`, `42`, `"x"`, `true`, `null`). Seul
    /// un objet peut échapper au refus (`estRefus`).
    public static func lire(_ corps: Data) -> AnyJSON {
        (try? JSONDecoder().decode(AnyJSON.self, from: corps)) ?? .null
    }

    private var corps: RPCResponse { RPCResponse(raw) }

    // MARK: - Accès tolérant (mêmes règles que `RPCResponse`)

    public var objet: JSONObject { corps.objet }
    public func valeur(_ cle: String) -> AnyJSON? { corps.valeur(cle) }
    public func string(_ cle: String) -> String? { corps.string(cle) }
    public func bool(_ cle: String) -> Bool? { corps.bool(cle) }
    public func int(_ cle: String) -> Int? { corps.int(cle) }
    public func double(_ cle: String) -> Double? { corps.double(cle) }

    public var ok: Bool? { corps.ok }
    public var success: Bool? { corps.success }
    /// Clé `error`, verbatim ; vide ou absente → nil.
    public var erreur: String? { corps.erreur }
    /// Clé `error_code` (`delete-account`) ; vide ou absente → nil.
    public var codeErreur: String? { corps.codeErreur }
    /// Clé `message`, verbatim ; vide ou absente → nil.
    public var message: String? {
        guard let texte = string("message"), !texte.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return texte
    }
    public var details: JSONObject? { valeur("details")?.objectValue }

    // MARK: - Interprétation

    /// Code machine du refus : `code`, sinon `error_code`, sinon `error` quand il porte le code (à
    /// côté d'un `message` distinct, ou seul en SCREAMING_SNAKE_CASE).
    public var code: String? {
        if let code = corps.code { return code }
        if let codeErreur { return codeErreur }
        guard let erreur else { return nil }
        if let message, message != erreur { return erreur }
        return Self.estCodeMachine(erreur) ? erreur : nil
    }

    /// Texte affichable verbatim : `message`, sinon `error` s'il n'est pas un code machine.
    public var texte: String? {
        if let message { return message }
        guard let erreur, erreur != code else { return nil }
        return erreur
    }

    /// Refus : statut hors 2xx, corps qui n'est pas un objet JSON (page HTML d'un portail captif ou
    /// d'un proxy, corps vide, `null`, tableau, scalaire : jamais un succès fabriqué, PRINCIPES §3),
    /// drapeau `ok:false` / `success:false`, ou `error` sans drapeau vrai (parité web `data?.error`).
    /// Un objet 2xx sans drapeau ni `error` n'est pas un refus (`stripe-connect-status` ne pose
    /// aucun drapeau).
    public var estRefus: Bool {
        !(200..<300).contains(statut) || raw.objectValue == nil || ok == false || success == false
            || (erreur != nil && ok != true && success != true)
    }

    /// Absence de refus : 2xx ET objet JSON, sans drapeau faux ni `error`. Plus faible que
    /// `RPCResponse.estSucces`, qui exige un drapeau vrai : `stripe-connect-status` n'en pose pas,
    /// si bien que chaque gateway exige ensuite les clés qui conditionnent SON succès.
    public var estSucces: Bool { !estRefus }
    public var estNonAutorise: Bool { statut == 401 }

    /// nil = 2xx à corps objet sans refus (la gateway vérifie ensuite ses clés) ; 401 →
    /// `JoleneError(.unauthorized)` (jamais un refus affiché) ; sinon refus structuré, texte serveur
    /// verbatim ou `fallback` (corps illisible ou non objet compris, `code` nil).
    public func refus(fallback: String) throws -> RefusEdge? {
        if estNonAutorise { throw JoleneError(.unauthorized, SupabaseErrorMapping.unauthorizedMessage) }
        guard estRefus else { return nil }
        return RefusEdge(statut: statut, code: code, message: texte ?? fallback)
    }

    /// Code machine : majuscules, chiffres et au moins un `_` (`TEST_ACCOUNT_PAYMENT_DISABLED`,
    /// `ORIGINE_NON_AUTORISEE`) — jamais un texte destiné à l'utilisateur.
    public static func estCodeMachine(_ texte: String) -> Bool {
        texte.range(of: #"^[A-Z][A-Z0-9]*(_[A-Z0-9]+)+$"#, options: .regularExpression) != nil
    }

    // MARK: - Transport

    /// Appel d'edge function : réponse 2xx et `FunctionsError.httpError` rendues telles quelles
    /// (corps lu avant tout mapping) ; relais Supabase en échec (`x-relay-error`) → erreur inconnue
    /// (`fallback`), jamais un succès ; erreur de transport → `SupabaseErrorMapping`. `options` est
    /// transmis sans modification (méthode, `query`, en-têtes comme `Origin`, corps).
    static func invoquer(_ client: SupabaseClient, _ fonction: String, options: FunctionInvokeOptions,
                         fallback: String) async throws -> EdgeResponse {
        do {
            return try await client.functions.invoke(fonction, options: options) { corps, reponse in
                EdgeResponse(statut: reponse.statusCode, corps: corps)
            }
        } catch FunctionsError.httpError(let code, let corps) {
            return EdgeResponse(statut: code, corps: corps)
        } catch FunctionsError.relayError {
            throw JoleneError(.unknown, fallback)
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: fallback)
        }
    }
}

/// Refus d'une edge function : statut HTTP, code machine éventuel (jamais affiché), texte verbatim.
public struct RefusEdge: Equatable, Sendable {
    public var statut: Int
    public var code: String?
    public var message: String

    public init(statut: Int, code: String?, message: String) {
        self.statut = statut; self.code = code; self.message = message
    }
}
