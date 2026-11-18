import Foundation
import Combine

/// « Aller à la recherche » (L4-T4) : recherche à appliquer à Explorer, déposée par l'écran des recherches (empilé sur
/// le Profil) et retirée par Explorer (`AlerteRapideExplorer`), qui applique ses critères
/// (`FiltresSauvegardesEncodage.explorer`) et annonce « Filtres « nom » appliqués ». Équivalent natif du
/// `sessionStorage['jolene.filtres_a_appliquer']` du web (`PageRecherchesSauvegardees.tsx` l.110-122, lu et effacé au
/// montage d'Explorer, `RechercheMissions.tsx` l.137-158).
///
/// Une instance par lancement (`AppContainer`) ; la demande porte l'identifiant de l'utilisateur qui l'a déposée et
/// n'est remise qu'à lui (aucun critère d'une session ne s'applique à une autre). Une seule demande à la fois : la
/// dernière déposée remplace la précédente, comme la clé du web.
@MainActor
public final class BoiteRechercheExplorer: ObservableObject {
    public struct Demande: Identifiable, Equatable, Sendable {
        /// Distingue deux dépôts successifs de la même recherche.
        public let id: Int
        public let userId: String
        public let nomSource: String
        public let filtres: ValeurJSON
    }

    @Published public private(set) var demande: Demande?
    private var compteur = 0

    public init() {}

    public func deposer(_ recherche: FiltreSauvegarde, userId: String) {
        compteur += 1
        demande = Demande(id: compteur, userId: userId, nomSource: recherche.nom, filtres: recherche.filtres)
    }

    /// Demande en attente pour `userId`, retirée de la boîte ; celle d'une autre identité est effacée sans être remise.
    public func retirer(userId: String) -> Demande? {
        guard let courante = demande else { return nil }
        demande = nil
        return courante.userId == userId ? courante : nil
    }
}
