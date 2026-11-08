import Foundation

/// Drapeaux démo : aucune lecture serveur. Une surcharge explicite (argument de lancement
/// DEBUG `-JOLENE_FLAG_<cle> false`, analysé par l'app en T9) prime ; sinon le défaut demandé,
/// fail-open pour les écrans natifs (décision 15).
public struct DemoFlagsGateway: FlagsPort {
    public let surcharges: [String: Bool]

    public init(surcharges: [String: Bool] = [:]) {
        self.surcharges = surcharges
    }

    public func ecranActif(cle: String, defaut: Bool) async -> Bool {
        surcharges[cle] ?? defaut
    }
}
