import Foundation

/// Contestation d'une présence du monde démo (blueprint lot 2 §2.8, tranche T5b) : aucun réseau, profil fictif seulement
/// (`.demoOnly` pour tout autre utilisateur). Litiges en mémoire, aucun au lancement ; la fenêtre est ouverte pour toute
/// mission sauf celles de `fenetresFermees` (le monde démo ne porte aucune constante de délai : il simule le seul verdict
/// de `fn_fenetre_contestation_ouverte`). Comme `fn_ouvrir_litige_rate_limited(uuid, type_litige, text)` : motif de 10 à
/// 2 000 caractères après `trim`, un seul litige actif de ce type par mission, refus de la fenêtre fermée, litige créé
/// `OUVERT` puis relu par `presence_id`. Messages serveur verbatim (`MessagesContestationServeur`). Aucune notification.
public actor DemoContestationGateway: ContestationPort {
    private var litiges: [LitigePresence] = []
    private let fenetresFermees: Set<String>

    public init(fenetresFermees: Set<String> = []) {
        self.fenetresFermees = fenetresFermees
    }

    public func litige(presenceId: String, context: MissionReadContext) async throws -> LitigePresence? {
        try verifier(context)
        return litiges.last { $0.presenceId == presenceId }
    }

    public func fenetreOuverte(missionId: String, context: MissionReadContext) async throws -> Bool {
        try verifier(context)
        return !fenetresFermees.contains(missionId)
    }

    public func contester(missionId: String, presenceId: String, motif: String,
                          context: MissionReadContext) async throws -> IssueContestation {
        try verifier(context)
        let longueur = motif.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.count
        guard (ContestationModel.longueurMinMotif...2_000).contains(longueur) else {
            return .refusee(message: MessagesContestationServeur.motifLongueur)
        }
        guard !litiges.contains(where: { $0.missionId == missionId && $0.statut == "OUVERT" }) else {
            return .refusee(message: MessagesContestationServeur.dejaOuvert)
        }
        guard !fenetresFermees.contains(missionId) else {
            return .refusee(message: MessagesContestationServeur.fenetreFermee)
        }
        let cree = LitigePresence(id: "demo-litige-\(litiges.count + 1)", statut: "OUVERT", presenceId: presenceId,
                                  missionId: missionId, typeLitige: ContestationModel.typeLitige,
                                  creeLe: ISO8601DateFormatter().string(from: DemoWorld.fixedNow))
        litiges.append(cree)
        guard let relu = litiges.last(where: { $0.presenceId == presenceId }) else {
            throw JoleneError(.contract, DemoWorld.messageDemoSeulement)
        }
        return .ouverte(relu)
    }

    private func verifier(_ context: MissionReadContext) throws {
        guard context.userId == DemoWorld.context.userId else { throw JoleneError(.demoOnly, DemoWorld.messageDemoSeulement) }
    }
}
