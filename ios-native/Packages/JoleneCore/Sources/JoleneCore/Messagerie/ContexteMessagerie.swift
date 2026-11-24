import Foundation

/// Espace d'appel de la messagerie (lot 5, T11 ; `LOT5_PLAN.md` §3 T11, D18) : les modèles du lot 4
/// (`ConversationsModel`, `FilModel`, `BlocageModel`, `SignalementModel`) servent le soignant **et** l'établissement,
/// sans second écran ni copie de leurs règles. Seuls changent le contexte passé au port (`context:` ou `etab:`) et les
/// règles d'affichage propres au rôle (`PageMessagerie.tsx`, rôle `ADMIN_ETABLISSEMENT`).
///
/// `moi` est l'utilisateur de la session (le JWT) dans les deux espaces, jamais l'identifiant de l'établissement : le
/// serveur pose `auteur_id = auth.uid()` et compare lui-même à l'établissement (`fn_messages_non_lus`,
/// `fn_stats_dashboard_etablissement`).
public struct ContexteMessagerie: Equatable, Sendable {
    public enum Espace: Equatable, Sendable {
        case soignant(MissionReadContext)
        case etablissement(EtablissementReadContext)
    }

    public let espace: Espace
    public let epoch: Int
    /// Utilisateur courant (auteur de ses propres messages).
    public let moi: String

    public init(_ snapshot: SessionSnapshot) {
        espace = .soignant(snapshot.context); epoch = snapshot.epoch; moi = snapshot.user.id
    }

    public init(_ snapshot: EtablissementSessionSnapshot) {
        espace = .etablissement(snapshot.context); epoch = snapshot.epoch; moi = snapshot.user.id
    }

    public var estEtablissement: Bool {
        if case .etablissement = espace { return true }
        return false
    }
}

/// Aiguillage du port selon l'espace (aucune règle : chaque branche appelle la méthode du port de son contexte).
extension MessageriePort {
    func conversations(avant: CurseurConversations?, contexte: ContexteMessagerie) async throws -> PageConversations {
        switch contexte.espace {
        case let .soignant(c): return try await conversations(avant: avant, context: c)
        case let .etablissement(e): return try await conversations(avant: avant, etab: e)
        }
    }

    func interlocuteurs(ids: [String], contexte: ContexteMessagerie) async throws -> [Interlocuteur] {
        switch contexte.espace {
        case let .soignant(c): return try await interlocuteurs(ids: ids, context: c)
        case let .etablissement(e): return try await interlocuteurs(ids: ids, etab: e)
        }
    }

    func messages(conversationId: String, contexte: ContexteMessagerie) async throws -> [MessageChat] {
        switch contexte.espace {
        case let .soignant(c): return try await messages(conversationId: conversationId, context: c)
        case let .etablissement(e): return try await messages(conversationId: conversationId, etab: e)
        }
    }

    func messages(conversationId: String, depuis: String, contexte: ContexteMessagerie) async throws -> [MessageChat] {
        switch contexte.espace {
        case let .soignant(c): return try await messages(conversationId: conversationId, depuis: depuis, context: c)
        case let .etablissement(e): return try await messages(conversationId: conversationId, depuis: depuis, etab: e)
        }
    }

    func envoyer(conversationId: String, contenu: String, contexte: ContexteMessagerie) async throws -> EnvoiOutcome {
        switch contexte.espace {
        case let .soignant(c): return try await envoyer(conversationId: conversationId, contenu: contenu, context: c)
        case let .etablissement(e): return try await envoyer(conversationId: conversationId, contenu: contenu, etab: e)
        }
    }

    func message(id: String, conversationId: String, contexte: ContexteMessagerie) async throws -> MessageChat? {
        switch contexte.espace {
        case let .soignant(c): return try await message(id: id, conversationId: conversationId, context: c)
        case let .etablissement(e): return try await message(id: id, conversationId: conversationId, etab: e)
        }
    }

    func marquerLus(conversationId: String, contexte: ContexteMessagerie) async throws -> IssueLecture {
        switch contexte.espace {
        case let .soignant(c): return try await marquerLus(conversationId: conversationId, context: c)
        case let .etablissement(e): return try await marquerLus(conversationId: conversationId, etab: e)
        }
    }

    func saisie(debut: Bool, conversationId: String, contexte: ContexteMessagerie) async throws {
        switch contexte.espace {
        case let .soignant(c): try await saisie(debut: debut, conversationId: conversationId, context: c)
        case let .etablissement(e): try await saisie(debut: debut, conversationId: conversationId, etab: e)
        }
    }

    func presence(contexte: ContexteMessagerie) async throws {
        switch contexte.espace {
        case let .soignant(c): try await presence(context: c)
        case let .etablissement(e): try await presence(etab: e)
        }
    }

    func bloque(cibleId: String, contexte: ContexteMessagerie) async throws -> Bool {
        switch contexte.espace {
        case let .soignant(c): return try await bloque(cibleId: cibleId, context: c)
        case let .etablissement(e): return try await bloque(cibleId: cibleId, etab: e)
        }
    }

    func basculerBlocage(cibleId: String, bloquer: Bool, contexte: ContexteMessagerie) async throws -> Bool {
        switch contexte.espace {
        case let .soignant(c): return try await basculerBlocage(cibleId: cibleId, bloquer: bloquer, context: c)
        case let .etablissement(e): return try await basculerBlocage(cibleId: cibleId, bloquer: bloquer, etab: e)
        }
    }

    func signaler(cibleId: String, type: TypeCibleSignalement, categorie: String, motif: String, missionId: String?,
                  contexte: ContexteMessagerie) async throws -> IssueSignalement {
        switch contexte.espace {
        case let .soignant(c):
            return try await signaler(cibleId: cibleId, type: type, categorie: categorie, motif: motif, missionId: missionId, context: c)
        case let .etablissement(e):
            return try await signaler(cibleId: cibleId, type: type, categorie: categorie, motif: motif, missionId: missionId, etab: e)
        }
    }

    func nonLus(contexte: ContexteMessagerie) async throws -> Int {
        switch contexte.espace {
        case let .soignant(c): return try await nonLus(context: c)
        case let .etablissement(e): return try await nonLus(etab: e)
        }
    }
}
