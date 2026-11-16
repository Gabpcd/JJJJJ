import SwiftUI
import JoleneCore

/// Destinations natives des contrats (lot 2, T9a), pour les points d'entrée des autres tranches, une ligne chacune
/// (consigne T9a de `DECISIONS_LOT2.md`) : « Mes contrats » du Profil (T4a, `EspaceSoignantSection`), onglet Contrats
/// de « Mes documents » (T7, `presentation: .onglet`), « Voir le contrat » du bloc de pointage (T4a,
/// `BlocPointageView`), liens `/soignant/contrats?statut=` (`FiltreContrat.initial(statut:)`), `/contrat/:id` et
/// `/contrat/:id/certificat` (T10).
enum ContratsDestination {
    @MainActor
    static func liste(session: SessionStore, snapshot: SessionSnapshot, filtreInitial: FiltreContrat = .tous,
                      presentation: ContratsListeView.Presentation = .ecran) -> ContratsListeView {
        ContratsListeView(session: session, snapshot: snapshot, filtreInitial: filtreInitial, presentation: presentation)
    }

    @MainActor
    static func contrat(session: SessionStore, snapshot: SessionSnapshot, contratId: String) -> ContratScreen {
        ContratScreen(session: session, snapshot: snapshot, contratId: contratId)
    }

    @MainActor
    static func certificat(session: SessionStore, snapshot: SessionSnapshot, contratId: String) -> CertificatRoute {
        CertificatRoute(session: session, snapshot: snapshot, contratId: contratId)
    }
}
