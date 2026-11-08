import Foundation

/// Purge locale de la session, sans révocation globale (lot 1, T8 : après la suppression du compte,
/// l'edge `delete-account` a déjà révoqué toutes les sessions et supprimé l'utilisateur Auth ; le web
/// appelle alors `supabase.auth.signOut({ scope: 'local' })`, `SectionConfidentialite.tsx` l.96).
///
/// Port distinct d'`AuthPort` : la signature de `Ports.swift` est figée (PRINCIPES §2), la capacité
/// s'ajoute donc par un second protocole qu'une gateway adopte. Ne lève jamais : l'implémentation
/// retire la session locale (Keychain) avant tout appel réseau et tolère l'échec de ce dernier.
public protocol LocalSignOutPort: Sendable {
    func signOutLocally() async
}

public extension AuthPort {
    /// Purge locale tolérante (blueprint lot 1 §3 T8) : la gateway qui adopte `LocalSignOutPort`
    /// (Supabase : `signOut(scope: .local)`) est appelée ; sinon `signOut()` (ports démo et doubles de
    /// test), dont l'échec est avalé. Jamais d'erreur remontée : la session locale est déjà retirée.
    func signOutLocally() async {
        if let local = self as? any LocalSignOutPort {
            await local.signOutLocally()
            return
        }
        try? await signOut()
    }
}
