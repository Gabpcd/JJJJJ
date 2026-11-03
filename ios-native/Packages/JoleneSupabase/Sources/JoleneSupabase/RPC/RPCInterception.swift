import Foundation
import JoleneCore

/// Exceptions PostgREST traduites **avant** `SupabaseErrorMapping` (lot 5 §2.5, D12 ; correction 5).
///
/// `SupabaseErrorMapping` range `42501` en « session expirée ». Or l'espace établissement reçoit des
/// 42501 de **droit** (`Mission indisponible ou accès refusé`, trigger RBAC `Permission etablissement %
/// requise`…) qui ne doivent jamais déconnecter, et des refus métier P0001/P0002/23503/23514 dont le
/// texte serveur doit s'afficher mot pour mot. Chaque interception est une **liste blanche exacte**
/// (`ListesBlanchesEtablissement`, comparée au champ `exceptions` de `ios-native/rpc-contracts.json`,
/// extrait du dump) : un message hors liste garde le comportement du lot 0, une modification serveur
/// rougit le contrat avant que l'interception ne se trompe.
///
/// Résultat d'une interception : un refus structuré `RPCResponse` (`success:false`, `ok:false`, `code`
/// client, `error` = message à afficher, `sqlstate`), traduit en issue par la gateway, ou une erreur
/// levée (`.unauthorized` pour 28000). Le DETAIL et le HINT techniques ne sont jamais repris.
public enum RPCInterception: Equatable, Sendable {
    /// Lot 1 : message contenant `[CODE DU TRAVAIL]`, quel que soit le SQLSTATE → refus structuré
    /// verbatim (`RPCResponse.refusCodeDuTravail`). Interception par défaut de tout appel.
    case codeDuTravail
    /// SQLSTATE 42501 dont le message correspond à un modèle → `codeAccesRefuse`, message serveur ou,
    /// si `messageAffiche` est posé, ce message natif neutre (trigger RBAC).
    case accesRefuse(messagesExacts: [String], messageAffiche: String? = nil)
    /// SQLSTATE exact dont le message correspond à un modèle → `codeRefusMetier`, message verbatim.
    case refusMetier(sqlstate: String, messagesExacts: [String])
    /// SQLSTATE (28000) → `.unauthorized`, message de session du lot 0.
    case nonAuthentifie(sqlstate: String)

    /// Code client d'un refus de droit intercepté (distinct de tout code jsonb serveur).
    public static let codeAccesRefuse = "ACCES_REFUSE"
    /// Code client d'un refus métier intercepté.
    public static let codeRefusMetier = "REFUS_METIER"
    public static let sqlstateAccesRefuse = "42501"
    public static let sqlstateNonAuthentifie = "28000"
    /// Message natif neutre substitué au refus du trigger RBAC (§2.5), suivi d'une relecture des
    /// permissions par l'écran.
    public static let messageRoleInsuffisant = "Votre rôle dans cet établissement ne permet pas cette action."

    /// Interceptions du lot 1, inchangées : comportement par défaut de `RPCResponse.appeler`.
    public static let parDefaut: [RPCInterception] = [.codeDuTravail]

    /// Issue d'une interception.
    enum Resultat: Equatable {
        case reponse(RPCResponse)
        case erreur(JoleneError)
    }

    /// Correspondance d'un message serveur à un modèle de la liste blanche : égalité exacte, sauf que
    /// chaque `%` du modèle (argument formaté par `RAISE`) correspond à un texte **non vide**.
    /// Sensible à la casse, aucun espace ignoré.
    public static func correspond(modele: String, message: String) -> Bool {
        let morceaux = modele.components(separatedBy: "%")
        guard morceaux.count > 1 else { return modele == message }
        return apparier(morceaux[...], message[...])
    }

    /// `texte` commence par le premier littéral, puis chaque joker consomme au moins un caractère avant
    /// le littéral suivant (avec retour arrière : un littéral peut aussi figurer dans la valeur d'un
    /// argument), et le dernier littéral termine exactement le texte.
    private static func apparier(_ morceaux: ArraySlice<String>, _ texte: Substring) -> Bool {
        guard let litteral = morceaux.first else { return texte.isEmpty }
        guard texte.hasPrefix(litteral) else { return false }
        let reste = texte.dropFirst(litteral.count)
        let suite = morceaux.dropFirst()
        guard !suite.isEmpty else { return reste.isEmpty }
        guard !reste.isEmpty else { return false }
        var finJoker = reste.index(after: reste.startIndex)
        while true {
            if apparier(suite, reste[finJoker...]) { return true }
            guard finJoker < reste.endIndex else { return false }
            finJoker = reste.index(after: finJoker)
        }
    }

    static func correspondAUnModele(_ modeles: [String], message: String) -> Bool {
        modeles.contains { correspond(modele: $0, message: message) }
    }

    /// Applique cette interception à une exception PostgREST ; nil si elle ne la vise pas.
    func appliquer(code: String?, message: String) -> Resultat? {
        switch self {
        case .codeDuTravail:
            guard RPCResponse.estRefusCodeDuTravail(message) else { return nil }
            return .reponse(RPCResponse.refusCodeDuTravail(message))
        case let .accesRefuse(modeles, messageAffiche):
            guard code == Self.sqlstateAccesRefuse, Self.correspondAUnModele(modeles, message: message) else { return nil }
            return .reponse(Self.refus(code: Self.codeAccesRefuse, sqlstate: Self.sqlstateAccesRefuse, message: messageAffiche ?? message))
        case let .refusMetier(sqlstate, modeles):
            guard code == sqlstate, Self.correspondAUnModele(modeles, message: message) else { return nil }
            return .reponse(Self.refus(code: Self.codeRefusMetier, sqlstate: sqlstate, message: message))
        case let .nonAuthentifie(sqlstate):
            guard code == sqlstate else { return nil }
            return .erreur(JoleneError(.unauthorized, SupabaseErrorMapping.unauthorizedMessage))
        }
    }

    /// Première interception de la liste qui vise l'exception, dans l'ordre donné.
    static func appliquer(_ interceptions: [RPCInterception], code: String?, message: String) -> Resultat? {
        for interception in interceptions {
            if let resultat = interception.appliquer(code: code, message: message) { return resultat }
        }
        return nil
    }

    static func refus(code: String, sqlstate: String, message: String) -> RPCResponse {
        RPCResponse(.object([
            "success": .bool(false),
            "ok": .bool(false),
            "code": .string(code),
            "sqlstate": .string(sqlstate),
            "error": .string(message),
        ]))
    }
}

public extension RPCResponse {
    /// Refus de droit intercepté (`RPCInterception.accesRefuse`).
    var estAccesRefuse: Bool { estRefus && code == RPCInterception.codeAccesRefuse }
    /// Refus métier intercepté (`RPCInterception.refusMetier`), texte serveur verbatim.
    var estRefusMetier: Bool { estRefus && code == RPCInterception.codeRefusMetier }
    /// SQLSTATE d'un refus intercepté.
    var sqlstate: String? { string("sqlstate") }
}
