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
/// - `{error}` seul (aucun marqueur de refus structuré ci-dessous) : erreur levée par
///   `leverSiErreur` (« Non authentifié » → `.unauthorized`, sinon `.unknown` avec le message
///   serveur verbatim).
/// - Refus structuré (`estRefus`), traduit en issue métier par l'appelant
///   (`issueCandidatureRefusee`), quelle que soit la forme renvoyée (formes du dump
///   `supabase/schema/public.sql`, RPC par RPC) :
///   - `{success:false, ok:false, error, code?}` : `fn_confirmer_action_planning_v1` elle-même
///     (accès, action, mission indisponible, planning l.24199 et l.24247, conflit l.24260 dont
///     REPOS_11H, proposition introuvable) ; `{success:false, error_code, error}` :
///     `fn_annuler_candidature_soignant` (T7, `codeErreur`) ;
///   - `{choix_requis:true, error, options}` SANS `success` ni `ok` : `fn_resoudre_contrat_mission`
///     relayé en `v_resolution - 'ok'` par `fn_postuler_mission` (POSTULER) et
///     `fn_finaliser_attribution_mission` (ACCEPTER via `fn_accepter_mission`, PROPOSITION via
///     `fn_repondre_proposition`) ;
///   - `{error, documents_requis_pour, lien_documents}` SANS `success` ni `ok` : mêmes RPC
///     déléguées (documents requis non validés). `documents_requis_pour` accompagné de
///     `success:true` n'est PAS un refus (succès de `fn_postuler_mission` avec documents à
///     compléter) ;
///   - `{error, code, …}` SANS `success` ni `ok` : `fn_finaliser_attribution_mission`
///     (ACCEPTER, PROPOSITION), `PLANNING_HEBDOMADAIRE_INDISPONIBLE` l.36788-36793 et
///     `PLAFOND_48H_HEBDO` l.36811-36825 ;
///   - exception PostgREST (HTTP 400) dont le message contient `[CODE DU TRAVAIL]` : triggers
///     `dec_verifier_plafond_48h` (l.4477), `dec_verifier_repos_11h` (l.4615),
///     `dec_verifier_moyenne_44h_12_semaines` (l.4322) et `dec_verifier_repos_hebdo_35h`
///     (l.4707), levés par l'`UPDATE public.missions` de `fn_finaliser_attribution_mission`
///     (l.36840), donc sur ACCEPTER et PROPOSITION. `appeler` la restitue mot pour mot en
///     `{success:false, ok:false, code: CandidatureOutcome.codeRefusCodeDuTravail, error}`
///     (décision 2, HARD STOP n°4) au lieu du message générique de `SupabaseErrorMapping`.
/// - Aucun décodeur strict : chaque clé est optionnelle, sauf celles qui conditionnent une
///   action (`requiredString`, ex. `candidature_id`, `contrat_id`).
///
/// Les autres RPC du lot 1 (tableau de bord, favoris, présence, annulation, audit, suppression)
/// ne renvoient pas `{error, code}` sans drapeau dans le dump. Règle pour leurs gateways : tout
/// `estRefus` est un refus (issue `.refusee`, `.nonEnregistre`…), jamais un succès supposé.
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

    /// Clé `code` seule, vide ou absente → nil. Jamais de repli sur `error_code` (fiche T0 de
    /// `fn_confirmer_action_planning_v1` : ni ce corps ni `fn_conflit_planning_soignant` ne la posent).
    public var code: String? { texteNonVide("code") }

    /// Clé `error_code` (au lot 1, seule `fn_annuler_candidature_soignant` la pose, l.17557-17590 :
    /// T7) ; vide ou absente → nil.
    public var codeErreur: String? { texteNonVide("error_code") }

    private func texteNonVide(_ cle: String) -> String? {
        guard let texte = string(cle), !texte.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return texte
    }

    /// Régime dont les documents manquent (`SALARIE`, `LIBERAL`) ; vide ou absent → nil.
    public var documentsRequisPour: String? {
        guard let texte = string("documents_requis_pour"),
              !texte.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return texte
    }

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

    /// Refus structuré annoncé par le serveur : drapeau `success:false` / `ok:false`, choix de
    /// contrat demandé, documents requis manquants sans `success:true`, ou `code` + `error` sans
    /// drapeau vrai (les RPC déléguées au lot 1 ne posent aucun drapeau sur ces trois refus).
    public var estRefus: Bool {
        success == false || ok == false || choixRequis
            || (documentsRequisPour != nil && success != true)
            || (code != nil && erreur != nil && success != true && ok != true)
    }

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

    /// Refus de `fn_confirmer_action_planning_v1` et des RPC qu'elle délègue au lot 1
    /// (`fn_postuler_mission`, `fn_accepter_mission` → `fn_finaliser_attribution_mission`,
    /// `fn_repondre_proposition`), drapeau ou non, traduit en issue ; nil si la réponse n'est pas
    /// un refus structuré (`{error}` seul : `leverSiErreur`). Messages serveur verbatim
    /// (HARD STOP n°4).
    public func issueCandidatureRefusee(fallback: String) -> CandidatureOutcome? {
        guard estRefus else { return nil }
        if choixRequis { return .choixRequis(options) }
        let message = erreur ?? fallback
        if let code, Self.codesPlanningAReconfirmer.contains(code) {
            return .planningAReconfirmer(code: code, message: message)
        }
        return .refusee(code: code, message: message, documentsRequisPour: documentsRequisPour)
    }

    // MARK: - Refus du Code du travail (exception PostgREST)

    /// Préfixe des `RAISE EXCEPTION` des triggers du Code du travail.
    public static let marqueurCodeDuTravail = "[CODE DU TRAVAIL]"

    /// Vrai si le message d'exception contient le marqueur, à l'identique du web
    /// (`estBlocageCodeTravail`, `src/lib/erreurs.ts` l.586-588 : `includes`, sensible à la casse).
    public static func estRefusCodeDuTravail(_ message: String) -> Bool {
        message.contains(marqueurCodeDuTravail)
    }

    /// Refus structuré équivalent à l'exception : message mot pour mot (préfixe compris, DETAIL
    /// technique jamais repris), code client `CandidatureOutcome.codeRefusCodeDuTravail`.
    static func refusCodeDuTravail(_ message: String) -> RPCResponse {
        RPCResponse(.object([
            "success": .bool(false),
            "ok": .bool(false),
            "code": .string(CandidatureOutcome.codeRefusCodeDuTravail),
            "error": .string(message),
        ]))
    }

    // MARK: - Transport

    /// Appel RPC sans paramètre ; erreurs de transport traduites par `SupabaseErrorMapping`
    /// (PGRST202 et 300-303 → `.contract`, refus définitif sans renvoi), sauf l'exception
    /// `[CODE DU TRAVAIL]`, restituée en refus structuré (`refusCodeDuTravail`).
    static func appeler(_ client: SupabaseClient, _ fonction: String, fallback: String) async throws -> RPCResponse {
        try await executer(fallback: fallback) { try await client.rpc(fonction).execute().value }
    }

    /// Appel RPC à paramètres nommés (mêmes règles).
    static func appeler(_ client: SupabaseClient, _ fonction: String, params: JSONObject,
                        fallback: String) async throws -> RPCResponse {
        try await executer(fallback: fallback) { try await client.rpc(fonction, params: params).execute().value }
    }

    /// Seul point de traduction des erreurs d'appel : l'interception du Code du travail précède
    /// `SupabaseErrorMapping.map`, laissé inchangé (lot 0). Une seule requête, aucun renvoi.
    private static func executer(fallback: String, _ requete: () async throws -> AnyJSON) async throws -> RPCResponse {
        do {
            return RPCResponse(try await requete())
        } catch let postgrest as PostgrestError where estRefusCodeDuTravail(postgrest.message) {
            return refusCodeDuTravail(postgrest.message)
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: fallback)
        }
    }
}
