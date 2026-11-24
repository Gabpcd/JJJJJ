import SwiftUI
import JoleneCore

/// Contrats de l'espace établissement (lot 5, T10 ; `LOT5_PLAN.md` §3 T10, D13, D18). Aucun écran nouveau : la liste et
/// la page du contrat sont celles du lot 2 (`ContratsListeView`, `ContratScreen`), construites sous le contexte confirmé
/// de l'établissement. Points d'entrée : bouton « Contrats » de la barre de l'onglet Missions et lien « Contrats » du
/// détail d'une mission assignée (masqués sans la permission `contrats`, §2.7 : absents pour POINTAGE_ONLY et
/// LECTURE_SEULE), liens `/etablissement/contrats?statut=` et `/contrat/{id}`. Destinations du registre, permission et
/// drapeau relus avant l'écran (`EtabDestinations.swift`).
struct ContratsEtabScreen: View {
    let statut: String?
    @ObservedObject var session: SessionStore
    let snapshot: EtablissementSessionSnapshot

    var body: some View {
        ContratsListeView(session: session, etablissement: snapshot, statut: statut)
    }
}

/// Page d'un contrat vu par l'établissement : `ContratScreen` du lot 2 (identifiant racine `contrat-detail`).
struct ContratEtabScreen: View {
    let contratId: String
    @ObservedObject var session: SessionStore
    let snapshot: EtablissementSessionSnapshot

    var body: some View {
        ContratScreen(session: session, etablissement: snapshot, contratId: contratId)
    }
}
