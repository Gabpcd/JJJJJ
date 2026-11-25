import SwiftUI
import JoleneCore

/// Racine de l'onglet Présences de l'espace établissement, posée par T2a, remplie par T8 (B9) : présences à valider,
/// en cours, validées et en alerte (`PresencesEtabScreen`) ; les présences d'une mission sont la destination
/// `.presencesMission` du registre (`EtabDestinations.swift`). Identifiant : `etab-presences-screen` (T8, remplace
/// `placeholder-etab-presences`).
struct EtabPresencesRoot: View {
    @ObservedObject var session: SessionStore
    let snapshot: EtablissementSessionSnapshot
    /// Lot 5, T8 : onglet `?tab=` porté par un lien vers la page (T2b).
    var demande = DemandeOngletPresences()

    var body: some View {
        PresencesEtabScreen(session: session, snapshot: snapshot, demande: demande)
    }
}
