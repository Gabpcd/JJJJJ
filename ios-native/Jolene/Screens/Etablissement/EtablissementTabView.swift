import SwiftUI
import JoleneCore
import JoleneDesign

/// Coquille de l'espace établissement (lot 5, T2a ; D13) : Accueil · Missions · Présences · Messages ·
/// Compte. « Publier » n'est pas un onglet (un onglet qui disparaît selon le rôle déplacerait la barre) :
/// c'est un bouton de la barre de Missions, masqué sans la permission `missions`. Chaque onglet possède
/// sa `NavigationStack`, le registre de destinations (`EtabDestinations.swift`) et son pilotage
/// permission → drapeau (`Composition/EtabFeatureFlags.swift`) ; son contenu vit dans un `…Root.swift`
/// que seule la tranche du domaine remplit.
///
/// Monté par `RootView` avec `.id(snapshot.epoch)` : une nouvelle identité ou un nouveau périmètre
/// reconstruit tout l'espace ; une relecture des permissions à epoch constant le re-filtre sans le démonter.
///
/// Liens (T2b) : à l'apparition, le coordinateur (`DeepLinkCoordinator.espaceEtablissementOuvert`) rejoue le lien reçu
/// avant l'espace ; chaque demande de cet epoch (`demandeEtablissement`) sélectionne l'onglet, remet sa pile à la racine
/// et y empile l'écran livré éventuel (`CibleEtablissement`), une seule fois.
///
/// Accessibilité : `.accessibilityIdentifier("tab-etab-*")` est porté par le CONTENU de l'onglet ; UIKit
/// expose le bouton d'onglet avec le nom de l'image de son `Label` (`house`, `list.clipboard`,
/// `checkmark.seal`, `bubble.left.and.bubble.right`, `person.crop.circle`). Ne pas renommer ces symboles
/// sans mettre à jour `tabSymbols` dans `UITestSupport.swift`.
struct EtablissementTabView: View {
    typealias Tab = CibleEtablissement.Onglet

    let container: AppContainer
    @ObservedObject var session: SessionStore
    let snapshot: EtablissementSessionSnapshot
    /// Lot 5, T2b : coordinateur des liens (demandes de navigation de cet espace).
    @ObservedObject private var liens: DeepLinkCoordinator
    @State private var selection: Tab = .accueil
    /// Piles des onglets (T2b) : un lien remet la pile de son onglet à la racine avant d'empiler son écran.
    @State private var chemins: [Tab: [EtabDestination]] = [:]
    /// Lot 5, T5 : filtre `?statut=` d'un lien vers la liste des missions, rejoué par `EtabMissionsScreen`.
    @State private var demandeMissions = DemandeFiltreMissions()
    /// Lot 5, T8 : onglet `?tab=` d'un lien vers la page Présences, rejoué par `PresencesEtabScreen`.
    @State private var demandePresences = DemandeOngletPresences()

    init(container: AppContainer, session: SessionStore, snapshot: EtablissementSessionSnapshot) {
        self.container = container
        self.session = session
        self.snapshot = snapshot
        self.liens = container.liens
    }

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack(path: chemin(.accueil)) {
                EtabAccueilRoot(session: session, snapshot: snapshot) { ouvrir($0) } // T4 : actions de l'Accueil
                    .destinationsEtablissement(snapshot: snapshot, session: session)
            }
            .ecranEtablissement(.accueil, snapshot: snapshot, session: session)
            .tabItem { Label("Accueil", systemImage: "house") }
            .tag(Tab.accueil)
            .accessibilityIdentifier("tab-etab-accueil")

            NavigationStack(path: chemin(.missions)) {
                EtabMissionsRoot(session: session, snapshot: snapshot, demande: demandeMissions)
                    .destinationsEtablissement(snapshot: snapshot, session: session)
            }
            .ecranEtablissement(.missions, snapshot: snapshot, session: session)
            .tabItem { Label("Missions", systemImage: "list.clipboard") }
            .tag(Tab.missions)
            .accessibilityIdentifier("tab-etab-missions")

            NavigationStack(path: chemin(.presences)) {
                EtabPresencesRoot(session: session, snapshot: snapshot, demande: demandePresences)
                    .destinationsEtablissement(snapshot: snapshot, session: session)
            }
            .ecranEtablissement(.presences, snapshot: snapshot, session: session)
            .tabItem { Label("Présences", systemImage: "checkmark.seal") }
            .tag(Tab.presences)
            .accessibilityIdentifier("tab-etab-presences")

            NavigationStack(path: chemin(.messages)) {
                EtabMessagesRoot(session: session, snapshot: snapshot)
                    .destinationsEtablissement(snapshot: snapshot, session: session)
            }
            .ecranEtablissement(.messages, snapshot: snapshot, session: session)
            .badgeMessagesEtablissement(container.cycleMessagerie) // T11 : `fn_messages_non_lus()` relu
            .tabItem { Label("Messages", systemImage: "bubble.left.and.bubble.right") }
            .tag(Tab.messages)
            .accessibilityIdentifier("tab-etab-messages")

            NavigationStack(path: chemin(.compte)) {
                EtabCompteRoot(container: container, session: session, snapshot: snapshot)
                    .destinationsEtablissement(snapshot: snapshot, session: session)
            }
            .ecranEtablissement(.compte, snapshot: snapshot, session: session) { Task { await session.signOut() } }
            .tabItem { Label("Compte", systemImage: "person.crop.circle") }
            .tag(Tab.compte)
            .accessibilityIdentifier("tab-etab-compte")
        }
        .tint(JoleneColor.rose700)
        .modifier(DernierEchecDebug(actif: !container.isDemo))
        // Lot 5, T11 : cycle Realtime et horloge de la messagerie pour les racines et destinations de l'espace.
        .environment(\.messagerieEtablissement,
                     MessagerieEtablissementEnvironnement(cycle: container.cycleMessagerie, clock: container.clock))
        // Lot 5, T2b : lien reçu avant l'espace rejoué une fois, puis chaque demande de cet epoch.
        .onAppear {
            liens.espaceEtablissementOuvert(snapshot)
            executerDemande()
        }
        .onChange(of: liens.demandeEtablissement) { _ in executerDemande() }
        // Revue B8 sécurité (vague D, m6) : copies de contrats écrites par l'espace établissement effacées à sa sortie.
        .onDisappear {
            liens.espaceFerme(epoch: snapshot.epoch)
            FichiersTemporairesSensibles.purger()
        }
    }

    private func chemin(_ onglet: Tab) -> Binding<[EtabDestination]> {
        Binding(get: { chemins[onglet] ?? [] }, set: { chemins[onglet] = $0 })
    }

    /// Exécute la demande de navigation du coordinateur pour cet espace (epoch), une seule fois.
    private func executerDemande() {
        guard let demande = liens.demandeEtablissement, demande.epoch == snapshot.epoch else { return }
        liens.demandeEtablissementTraitee(demande)
        ouvrir(demande.cible)
    }

    /// Sélectionne l'onglet de `cible`, remet sa pile à la racine et y empile l'écran livré éventuel (liens, T2b ;
    /// actions de l'Accueil, T4). La liste des missions sans écran empilé rejoue le filtre `?statut=` de la cible
    /// (T5) : l'action « candidatures » de l'Accueil (`/etablissement/missions?statut=OUVERTE`) ouvre Missions sur
    /// « Ouvertes », comme un lien (intégration vague C, revues B8 de #1160 et #1162, m1).
    private func ouvrir(_ cible: CibleEtablissement) {
        selection = cible.onglet
        chemins[cible.onglet] = cible.destination.map { [$0] } ?? []
        if cible.onglet == .missions, cible.destination == nil {
            demandeMissions = DemandeFiltreMissions(statut: cible.statut, jeton: demandeMissions.jeton + 1)
        }
        // T8 : `/etablissement/presences?tab=alertes` ouvre Présences sur l'onglet demandé (toute autre valeur : « À valider »).
        if cible.onglet == .presences, cible.destination == nil {
            demandePresences = DemandeOngletPresences(onglet: cible.ongletPresences, jeton: demandePresences.jeton + 1)
        }
    }
}

/// DEBUG seulement, hors démo : dernier échec serveur (`DiagnosticDernierEchec`, sans secret) posé comme valeur
/// d'accessibilité de `debug-dernier-echec`, relu chaque seconde, pour que le XCUITest STAGING nomme la cause d'une
/// attente échouée (quatrième parcours STAGING du lot 5). En Release, la vue est rendue telle quelle.
private struct DernierEchecDebug: ViewModifier {
    let actif: Bool

    func body(content: Content) -> some View {
        #if DEBUG
        content.overlay(alignment: .topLeading) {
            if actif {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Color.clear
                        .frame(width: 1, height: 1)
                        .accessibilityElement()
                        .accessibilityIdentifier("debug-dernier-echec")
                        .accessibilityValue(DiagnosticDernierEchec.partage.valeur ?? "aucun")
                }
                .allowsHitTesting(false)
            }
        }
        #else
        content
        #endif
    }
}
