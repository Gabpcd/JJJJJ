import Foundation

/// SQLSTATE métier déclarés par RPC pour le lot 2 (blueprint `docs/mobile-swift/LOT2_PLAN.md` §2.4,
/// correction 10), passés à `RPCResponse.appeler(…, exceptionsMetier:)` (extension partagée avec le lot 3,
/// `RPCResponse+ExceptionsMetier.swift`). Une interception par RPC, déclarée, jamais globale : toute
/// autre exception garde le comportement du lot 1 (`SupabaseErrorMapping`).
public enum ExceptionsMetierLot2 {
    /// `fn_scanner_code_pointage` (`public.sql` l.55649-55778 : P0002, 42501, 23514) et les triggers de
    /// `presences` levés à la première OUVERTURE (`fn_exiger_conformite_demarrage_mission` l.35867-35926 :
    /// 22023, 42501, 23514, 23503 ; `dec_fenetre_pointage` l.1961 : P0001). Chacune prouve un rollback :
    /// refus verbatim, jamais un résultat incertain. « permission denied for … » reste une erreur de contrat.
    public static let scannerCodePointage: Set<String> = ["P0001", "P0002", "22023", "23503", "23514", "42501"]

    /// `fn_verifier_coherence_documents` (l.65833, l.65839 : « Accès refusé », compte inactif) : lecture
    /// best-effort, aucune bannière, jamais « Votre session a expiré ».
    public static let verifierCoherenceDocuments: Set<String> = ["42501"]
}
