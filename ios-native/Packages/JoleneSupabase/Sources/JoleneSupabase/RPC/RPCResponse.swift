import Foundation
import JoleneCore
import Supabase

/// Lecture tolérante des réponses jsonb renvoyées en HTTP 200 (blueprint lot 1 §2.4).
///
/// Plusieurs RPC du lot 1 (`fn_dashboard_soignant_complet`, `fn_mes_favoris_etablissements`,
/// `fn_confirmer_presence_mission`, `fn_postuler_mission`, `fn_audit_connexion`…) signalent un
/// refus dans le corps et non par le statut HTTP. Une gateway qui ne testerait que l'erreur
/// PostgREST afficherait un faux succès : chaque gateway passe par ce helper unique.
///
/// - `{error}` sans `success:false` / `ok:false` : erreur levée par `leverSiErreur`
///   (« Non authentifié » → `.unauthorized`, sinon `.unknown` avec le message serveur verbatim).
/// - `{success:false | ok:false, error?, error_code? | code?, documents_requis_pour?,
///   choix_requis?, options?}` : refus structuré, traduit en issue métier par l'appelant
///   (`issueCandidatureRefusee`).
/// - Aucun décodeur strict : chaque clé est optionnelle, sauf celles qui conditionnent une
///   action (`requiredString`, ex. `candidature_id`, `contrat_id`).
public struct RPCResponse: Equatable, Sendable {
    /// Codes de `fn_confirmer_action_planning_v1` qui imposent de relire puis reconfirmer le planning.
    public static let codesPlanningAReconfirmer: Set<String> = ["PLANNING_A_RECONFIRMER", "PLANNING_MODIFIE_RECONFIRMER"]

    public let raw: AnyJSON

    public init(_ raw: AnyJSON) {
        self.raw = raw
    }

    /// Corps objet, ou vide si le serveur a renvoyé un scalaire, un tableau ou `null`.
    public var objet: JSONObject { raw.objectValue ?? [:] }

    // MARK: - Accès tolérant

    public func valeur(_ cle: String) -> AnyJSON? {
        guard let valeur = objet[cle], !valeur.isNil else { return nil }
        return valeur
    }

    public func string(_ cle: String) -> String? { valeur(cle)?.stringValue }

    public func bool(_ cle: String) -> Bool? { valeur(cle)?.boolValue }

    public func int(_ cle: String) -> Int? {
        guard let valeur = valeur(cle) else { return nil }
        if let entier = valeur.intValue { return entier }
        if let reel = valeur.doubleValue, reel.rounded() == reel, abs(reel) < 9_007_199_254_740_992 { return Int(reel) }
        return nil
    }

    public func double(_ cle: String) -> Double? {
        guard let valeur = valeur(cle) else { return nil }
        return valeur.doubleValue ?? valeur.intValue.map(Double.init)
    }

    /// Éléments textuels d'un tableau ; les autres éléments sont ignorés.
    public func strings(_ cle: String) -> [String]? {
        valeur(cle)?.arrayValue?.compactMap(\.stringValue)
    }

    /// Clé qui conditionne une action (identifiant renvoyé) : absente ou vide → refus de contrat.
    public func requiredString(_ cle: String) throws -> String {
        guard let texte = string(cle)?.trimmingCharacters(in: .whitespacesAndNewlines), !texte.isEmpty else {
            throw JoleneError(.contract, SupabaseErrorMapping.contractMessage)
        }
        return texte
    }

    // MARK: - Champs usuels

    public var success: Bool? { bool("success") }
    public var ok: Bool? { bool("ok") }

    /// Message `error` du serveur, verbatim ; vide ou absent → nil.
    public var erreur: String? {
        guard let texte = string("error"), !texte.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return texte
    }

    /// `error_code`, sinon `code`.
    public var code: String? { string("error_code") ?? string("code") }

    public var documentsRequisPour: String? { string("documents_requis_pour") }

    public var choixRequis: Bool { bool("choix_requis") == true }

    /// Options `{value, label}` lisibles ; une option sans valeur ou sans libellé est écartée.
    public var options: [ChoixContratOption] {
        (valeur("options")?.arrayValue ?? []).compactMap { element in
            guard let option = element.objectValue,
                  let value = option["value"]?.stringValue, !value.isEmpty,
                  let label = option["label"]?.stringValue else { return nil }
            return ChoixContratOption(value: value, label: label)
        }
    }

    /// Refus structuré annoncé par le serveur.
    public var estRefus: Bool { success == false || ok == false || choixRequis }

    /// Succès annoncé explicitement (`success:true` ou `ok:true`), sans message d'erreur.
    public var estSucces: Bool { !estRefus && erreur == nil && (success == true || ok == true) }

    // MARK: - Interprétation

    /// Vrai pour « Non authentifié » (casse, accents, espaces et point final ignorés).
    public static func estNonAuthentifie(_ message: String) -> Bool {
        var texte = message.trimmingCharacters(in: .whitespacesAndNewlines)
        while texte.hasSuffix(".") { texte.removeLast() }
        return texte.compare("Non authentifié", options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }

    /// Lève l'erreur portée par la réponse :
    /// - « Non authentifié », refus structuré ou non → `.unauthorized` (session expirée) ;
    /// - `error` textuel sans refus structuré → `.unknown`, message serveur verbatim ;
    /// - `error` non textuel sans refus structuré → `.unknown` avec `fallback`.
    /// Un refus structuré ne lève rien : l'appelant le traduit en issue métier.
    public func leverSiErreur(fallback: String) throws {
        if let erreur, Self.estNonAuthentifie(erreur) {
            throw JoleneError(.unauthorized, SupabaseErrorMapping.unauthorizedMessage)
        }
        guard !estRefus else { return }
        if let erreur { throw JoleneError(.unknown, erreur) }
        if let brute = valeur("error"), brute.stringValue == nil { throw JoleneError(.unknown, fallback) }
    }

    /// Refus de `fn_confirmer_action_planning_v1` (et des RPC qu'elle délègue) traduit en issue ;
    /// nil si la réponse n'est pas un refus. Messages serveur verbatim (HARD STOP n°4).
    public func issueCandidatureRefusee(fallback: String) -> CandidatureOutcome? {
        guard estRefus else { return nil }
        if choixRequis { return .choixRequis(options) }
        let message = erreur ?? fallback
        if let code, Self.codesPlanningAReconfirmer.contains(code) {
            return .planningAReconfirmer(code: code, message: message)
        }
        return .refusee(code: code, message: message, documentsRequisPour: documentsRequisPour)
    }

    // MARK: - Transport

    /// Appel RPC sans paramètre ; erreurs de transport traduites par `SupabaseErrorMapping`
    /// (PGRST202 et 300-303 → `.contract`, refus définitif sans renvoi).
    static func appeler(_ client: SupabaseClient, _ fonction: String, fallback: String) async throws -> RPCResponse {
        do {
            let valeur: AnyJSON = try await client.rpc(fonction).execute().value
            return RPCResponse(valeur)
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: fallback)
        }
    }

    /// Appel RPC à paramètres nommés.
    static func appeler(_ client: SupabaseClient, _ fonction: String, params: JSONObject,
                        fallback: String) async throws -> RPCResponse {
        do {
            let valeur: AnyJSON = try await client.rpc(fonction, params: params).execute().value
            return RPCResponse(valeur)
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: fallback)
        }
    }
}
