import Foundation

/// Mode d'exécution de l'app. Seules ces trois valeurs sont acceptées (plan §4.1).
public enum JoleneMode: String, Sendable, CaseIterable {
    case demo, staging, production
}

/// Configuration réseau validée. Un écran bloquant est affiché si la validation échoue.
public struct JoleneEnvironment: Equatable, Sendable {
    public static let allowedProjectRefs: [JoleneMode: String] = [
        .staging: "mejpriaetwgtcstbgfid",
        .production: "flripxtsyegjshnhzjkz",
    ]

    public var mode: JoleneMode
    public var supabaseURL: URL?
    public var publishableKey: String?
    /// Valeur brute du mode lue par `load` lorsqu'elle n'est PAS l'un des trois modes
    /// acceptés (`dev`, `stagin`, valeur absente…). `validate()` la refuse : un mode
    /// inconnu n'ouvre jamais la production en silence. `nil` quand le mode est reconnu.
    public var unknownModeRaw: String? = nil

    public init(mode: JoleneMode, supabaseURL: URL?, publishableKey: String?) {
        self.mode = mode; self.supabaseURL = supabaseURL; self.publishableKey = publishableKey
    }

    /// Garde d'environnement : refuse un mode inconnu, exige une clé `sb_publishable_`,
    /// refuse toute clé secrète ou JWT legacy, et n'accepte qu'un ref de projet de l'allowlist.
    public func validate() throws {
        if let unknownModeRaw {
            throw JoleneError(.environment, Self.unknownModeMessage(unknownModeRaw))
        }
        if mode == .demo {
            // Le mode démo n'a pas de réseau : aucune URL ni clé ne doit être présente.
            if supabaseURL != nil || (publishableKey?.isEmpty == false) {
                throw JoleneError(.environment, "Le mode démonstration ne doit recevoir ni URL ni clé Supabase.")
            }
            return
        }
        guard let key = publishableKey, !key.isEmpty else {
            throw JoleneError(.environment, "Clé Supabase absente pour l'environnement \(mode.rawValue).")
        }
        if key.hasPrefix("sb_secret_") || key.lowercased().contains("service_role") {
            throw JoleneError(.environment, "Une clé secrète ne doit jamais être embarquée dans l'application.")
        }
        guard key.hasPrefix("sb_publishable_") else {
            throw JoleneError(.environment, "Seule une clé publishable (sb_publishable_) est acceptée.")
        }
        guard let url = supabaseURL, url.scheme == "https", let host = url.host else {
            throw JoleneError(.environment, "URL Supabase absente ou non sécurisée.")
        }
        let expectedRef = Self.allowedProjectRefs[mode]
        guard host == "\(expectedRef ?? "").supabase.co" else {
            throw JoleneError(.environment, "Le projet Supabase \(host) n'est pas autorisé pour \(mode.rawValue).")
        }
    }

    /// Message de refus d'un mode inconnu. La valeur brute est citée : ce n'est jamais un secret.
    public static func unknownModeMessage(_ raw: String) -> String {
        let cite = raw.isEmpty ? "absent" : "« \(raw) »"
        return "Mode d'exécution \(cite) refusé : seuls demo, staging et production sont acceptés."
    }

    /// Lecture depuis les arguments de lancement (`-JOLENE_MODE demo`), la variable
    /// d'environnement `JOLENE_MODE`, puis l'Info.plist (`JoleneEnvironment`, `JoleneSupabaseURL`,
    /// `JoleneSupabasePublishableKey`), dans cet ordre de priorité pour le mode.
    ///
    /// `allowOverrides` : lorsque `false` (build Release), les arguments et la variable
    /// d'environnement sont ignorés et seul l'Info.plist fait foi ; l'app ne l'active qu'en DEBUG.
    /// Un mode inconnu ou absent n'est jamais remplacé par `production` en silence : la valeur
    /// brute est conservée dans `unknownModeRaw` et `validate()` la refuse (écran bloquant).
    public static func load(arguments: [String], environment: [String: String], info: [String: Any],
                            allowOverrides: Bool = true) -> JoleneEnvironment {
        var modeRaw: String? = nil
        if allowOverrides {
            if let index = arguments.firstIndex(of: "-JOLENE_MODE"), index + 1 < arguments.count {
                modeRaw = arguments[index + 1]
            }
            modeRaw = modeRaw ?? environment["JOLENE_MODE"]
        }
        modeRaw = modeRaw ?? (info["JoleneEnvironment"] as? String)
        let raw = (modeRaw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let mode = JoleneMode(rawValue: raw.lowercased()) else {
            var refused = JoleneEnvironment(mode: .production, supabaseURL: nil, publishableKey: nil)
            refused.unknownModeRaw = raw
            return refused
        }
        if mode == .demo { return JoleneEnvironment(mode: .demo, supabaseURL: nil, publishableKey: nil) }
        let urlString = (info["JoleneSupabaseURL"] as? String) ?? ""
        let key = (info["JoleneSupabasePublishableKey"] as? String) ?? ""
        return JoleneEnvironment(mode: mode, supabaseURL: URL(string: urlString), publishableKey: key)
    }
}
