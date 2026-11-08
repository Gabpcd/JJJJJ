import Foundation

/// `PushRegistrationPort` du monde démo (blueprint §2.7) : acteur en mémoire, aucun réseau. Mêmes
/// refus que les fonctions serveur (`fn_upsert_token_push` l.64641-64648 : token de 16 à 4096
/// caractères ; `fn_desactiver_mon_token_push` l.30186-30191) et même périmètre : seul le profil fictif
/// (`DemoWorld.context`) enregistre un token ; la démo n'est jamais un repli pour un compte réel.
public actor DemoPushGateway: PushRegistrationPort {
    /// Appels reçus, dans l'ordre (`enregistrer`, `desactiver`), pour les tests.
    public private(set) var journal: [String] = []
    private var actifs: [String] = []

    public init() {}

    /// Tokens actifs, dans l'ordre d'enregistrement.
    public var tokensActifs: [String] { actifs }

    public func enregistrer(token: String, context: MissionReadContext) async throws {
        journal.append("enregistrer")
        guard context.userId == DemoWorld.context.userId else {
            throw JoleneError(.demoOnly, DemoWorld.messageDemoSeulement)
        }
        let valeur = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard PushCoordinator.tokenValide(valeur) else {
            // 22023 « Token push invalide » : refus de contrat, comme la gateway Supabase.
            throw JoleneError(.contract, "Token push invalide")
        }
        if !actifs.contains(valeur) { actifs.append(valeur) }
    }

    public func desactiver(token: String) async throws -> IssueDesactivationPush {
        journal.append("desactiver")
        let valeur = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard PushCoordinator.tokenValide(valeur) else { return .nonDesactive }
        let avant = actifs.count
        actifs.removeAll { $0 == valeur }
        return .desactive(tokensDesactives: avant - actifs.count)
    }
}
