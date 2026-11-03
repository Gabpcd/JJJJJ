import SwiftUI
import JoleneCore

/// Registre des destinations de l'espace établissement (lot 5, T2a, corrigé v2 ; `LOT5_PLAN.md` §4) :
/// chaque onglet pousse une `EtabDestination` (`JoleneCore/Etablissement/EtabDestination.swift`), rendue
/// ici par **une** ligne du `switch`. Chaque tranche remplace sa ligne (T5 le détail, T6 les candidatures,
/// T7 le pointage, T8 les présences de mission, T9 la publication, T10 le contrat, T11 la conversation) ;
/// aucune ne référence l'écran d'une autre. Avant le contenu : permission exigée (fail-closed, §2.7) puis
/// drapeau d'écran (D14).
struct EtabDestinationEcran: View {
    let destination: EtabDestination
    let snapshot: EtablissementSessionSnapshot
    @ObservedObject var session: SessionStore
    @ObservedObject var ecrans: EcransEtablissementModel

    var body: some View {
        if !destination.accessible(avec: snapshot.context.permissions) {
            EtabAccesRefuseScreen(session: session)
        } else if !ecrans.estActif(destination.drapeau, epoch: snapshot.epoch) {
            RenvoiWebEtabScreen(destination: destination)
        } else {
            contenu
        }
    }

    @ViewBuilder private var contenu: some View {
        switch destination {
        case .detailMission:
            provisoire("Mission", "Le détail de la mission arrive dans une prochaine version de l'application.") // T5
        case .candidatures:
            provisoire("Candidatures", "Les candidatures de la mission arrivent dans une prochaine version de l'application.") // T6
        case .pointage:
            provisoire("Pointage", "Le code de pointage arrive dans une prochaine version de l'application.") // T7
        case .presencesMission:
            provisoire("Présences", "Les présences de la mission arrivent dans une prochaine version de l'application.") // T8
        case .contrat:
            provisoire("Contrat", "Le contrat arrive dans une prochaine version de l'application.") // T10
        case .conversation:
            provisoire("Message", "La conversation arrive dans une prochaine version de l'application.") // T11
        case .publication:
            provisoire("Publier une mission", "La publication d'une mission arrive dans une prochaine version de l'application.") // T9
        }
    }

    private func provisoire(_ titre: String, _ description: String) -> PlaceholderScreen {
        PlaceholderScreen(titre: titre, identifier: "placeholder-etab-\(destination.identifiant)", description: description,
                          etat: "Disponible au lot 5")
    }
}

extension View {
    /// Rattache le registre de destinations à la `NavigationStack` d'un onglet établissement.
    func destinationsEtablissement(snapshot: EtablissementSessionSnapshot, session: SessionStore) -> some View {
        navigationDestination(for: EtabDestination.self) { destination in
            EtabDestinationEcran(destination: destination, snapshot: snapshot, session: session,
                                 ecrans: session.ecransEtablissement)
        }
    }
}
