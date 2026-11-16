import Foundation

/// Notation du monde démo (blueprint lot 2 §2.8, tranche T5a) : aucun réseau, profil fictif seulement (`.demoOnly` pour
/// tout autre utilisateur). Comme `fn_creer_notation_mission` (`ON CONFLICT (mission_id, sens) DO NOTHING`) : une
/// première note est enregistrée, une seconde pour la même mission rend `.dejaNotee`. Notes en mémoire seulement, jamais
/// relues ni affichées (écriture seule). Fin prévue lue dans `demo-presences.json` (missions du pointage et de
/// l'historique).
public actor DemoNotationGateway: NotationPort {
    /// Notes reçues (mission → critères envoyés), preuve des tests ; jamais affichées.
    public private(set) var notes: [String: CriteresNotation] = [:]

    public init() {}

    public func noter(missionId: String, note: Int, criteres: CriteresNotation?,
                      context: MissionReadContext) async throws -> IssueNotation {
        try verifier(context)
        let envoyes = criteres ?? CriteresNotation.repliques(note: note)
        guard envoyes.valeurs.allSatisfy({ (1...5).contains($0) }) else {
            return .refusee(message: Self.messageCriteresInvalides)
        }
        guard notes[missionId] == nil else { return .dejaNotee }
        notes[missionId] = envoyes
        return .enregistree
    }

    public func finPrevue(missionId: String, context: MissionReadContext) async throws -> String? {
        try verifier(context)
        let fixture = try DemoPointageGateway.Fixture.charger()
        return (fixture.missions + fixture.missionsHistorique).first { $0.id == missionId }?.finLe
    }

    /// Message serveur verbatim (`fn_creer_notation_mission`, `public.sql` l.27331).
    public static let messageCriteresInvalides = "Critères doivent être entre 1 et 5"

    private func verifier(_ context: MissionReadContext) throws {
        guard context.userId == DemoWorld.context.userId else { throw JoleneError(.demoOnly, DemoWorld.messageDemoSeulement) }
    }
}
