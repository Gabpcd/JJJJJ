import Foundation
import JoleneCore
import Supabase

/// Dépôt des justificatifs d'annulation sur Supabase Storage (lot 1, T7), comme `ModaleAnnulationCandidature.tsx`
/// l.82-87 : bucket privé `justificatifs`, chemin du reçu `RecuJustificatif`
/// (`<uid>/annulations-candidature/<candidatureId>/<ms>_<nom>`, politique `justificatifs_insert_auth` :
/// `fn_peut_deposer_justificatif`, premier segment = `auth.uid()`), `contentType` du fichier vérifié, `upsert: false`.
///
/// Classement des échecs : celui des justificatifs du lot 2 (`SupabaseDocumentsGateway.classerEchecUpload`) — hôte
/// injoignable → `.nonEnvoye` ; 401 ou `InvalidJWT` → session expirée ; 409 (objet déjà présent : seul cet essai écrit
/// sous ce chemin) et toute réponse perdue → `.incertain`, réconcilié par `existe` (HEAD, lecture permise au déposant
/// par `fn_peut_lire_justificatif`) ; autre 4xx (politique 403, MIME, taille) → `.refuse(statut:)`, rien n'est déposé.
/// Aucun message du serveur n'est affiché ni journalisé.
public struct SupabaseJustificatifStorage: JustificatifStoragePort {
    public static let bucket = "justificatifs"

    private let client: SupabaseClient

    public init(client: SupabaseClient) {
        self.client = client
    }

    public func deposer(chemin: String, octets: Data, mime: MimeDocument, context: MissionReadContext) async throws -> IssueDepotJustificatif {
        try MissionQuery.validate(context: context)
        try Self.verifierChemin(chemin, context: context)
        guard (1...RecuJustificatif.tailleMaxOctets).contains(octets.count) else { return .refuse(statut: 413) }
        do {
            try await client.storage.from(Self.bucket)
                .upload(chemin, data: octets, options: FileOptions(contentType: mime.rawValue, upsert: false))
        } catch {
            switch SupabaseDocumentsGateway.classerEchecUpload(error) {
            case .nonEnvoye: return .nonEnvoye
            case .incertain: return .incertain
            case .refuse: return .refuse(statut: SupabaseDocumentsGateway.statutHTTP(error) ?? 400)
            case .sessionExpiree: throw SupabaseDocumentsGateway.sessionExpireeErreur
            }
        }
        return .depose
    }

    public func existe(chemin: String, context: MissionReadContext) async throws -> Bool {
        try MissionQuery.validate(context: context)
        try Self.verifierChemin(chemin, context: context)
        do {
            return try await client.storage.from(Self.bucket).exists(path: chemin)
        } catch {
            if SupabaseDocumentsGateway.sessionExpiree(error) { throw SupabaseDocumentsGateway.sessionExpireeErreur }
            throw SupabaseErrorMapping.map(error, fallback: LibellesAnnulation.depotIncertain)
        }
    }

    /// Chemin d'un justificatif de l'utilisateur de la session (premier segment), sans `..` ni `\` : refus de contrat
    /// avant tout appel réseau.
    static func verifierChemin(_ chemin: String, context: MissionReadContext) throws {
        let segments = chemin.split(separator: "/", omittingEmptySubsequences: false)
        guard segments.count == 4, String(segments[0]) == context.userId, segments[1] == RecuJustificatif.segment,
              segments.allSatisfy({ !$0.isEmpty }), !chemin.contains(".."), !chemin.contains("\\") else {
            throw JoleneError(.contract, "Chemin de justificatif invalide.")
        }
    }
}
