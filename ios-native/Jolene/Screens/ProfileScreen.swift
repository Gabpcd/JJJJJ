import SwiftUI
import JoleneCore
import JoleneDesign

/// Onglet Profil = hub « Mon compte » (`MonCompteSoignant.tsx`, route `/soignant/mon-compte`, `.monCompte`) ;
/// seule surface du hub (correction 18 du blueprint du lot 3 : aucun `MonCompteScreen` parallèle). Sections :
/// - lot 0 : « Compte » (identité minimale), « Se déconnecter », « Application » (version, diagnostic démo) — en
///   tête et inchangées : les XCUITest des lots 0 à 3 les lisent sans défilement (écart d'ordre assumé avec le web,
///   qui place « Se déconnecter » après « Aide & légal ») ;
/// - lot 3, T9 : « Mon profil » (`ProfilEntreeSection`, `profil-ouvrir`) ;
/// - « Réglages » : « Notifications » (T6, préférences, `profile-preferences-notifications`, hôte de la carte
///   d'autorisation de T4 : aucune seconde carte ici) et le thème Système / Clair / Sombre (T11, D16) ;
/// - T11 : « Connexion & sécurité » (« Changer mon mot de passe », `compte-mdp-ouvrir`), « Mes données (RGPD) »
///   (export JSON / CSV), « Aide & légal » (pages publiques en Safari, montée seulement avec le présentateur `.safari`
///   de L1-T10) ;
/// - lot 1, T8 : « Suppression de compte », dernière section.
/// Entrées natives en liens par valeur (`ProfilEditionRoute`, `PreferencesNotificationsRoute` enregistrées par
/// `MainTabView` ; `MotDePasseRoute` enregistrée ici, sur la liste et non dans ses lignes). Entrées web : `JoleneRoute`
/// puis `DestinationLien.destination`. Points d'extension (sans entrée tant que l'écran ou le présentateur manque) :
/// paiements et Stripe (T14a), coordonnées bancaires (T14b), biométrie (L1-T9), centre de notifications (ouvert
/// depuis l'Accueil, le hub web n'en a pas). Identifiant de la liste : `profile-list`.
struct ProfileScreen: View {
    let container: AppContainer
    @ObservedObject var session: SessionStore
    let snapshot: SessionSnapshot
    @State private var isSigningOut = false
    /// Export RGPD : modèle tenu par le hub (et non par sa section, ligne d'une liste paresseuse) pour que la
    /// feuille de partage survive au défilement.
    @StateObject private var export: ExportRGPDModel
    @Environment(\.presentateurRenvoiWeb) private var presentateurRenvoiWeb

    init(container: AppContainer, session: SessionStore, snapshot: SessionSnapshot) {
        self.container = container
        self.session = session
        self.snapshot = snapshot
        _export = StateObject(wrappedValue: ExportRGPDModel(session: session, snapshot: snapshot))
    }

    var body: some View {
        List {
            Section("Compte") {
                LabeledContent("Email", value: snapshot.user.email ?? "—")
                    .accessibilityIdentifier("profile-email")
                LabeledContent("Rôle", value: snapshot.role.role)
                    .accessibilityIdentifier("profile-role")
                LabeledContent("Profession", value: snapshot.profile.profession)
                    .accessibilityIdentifier("profile-profession")
            }
            Section {
                JoleneButton("Se déconnecter", style: .secondary, isLoading: isSigningOut) {
                    isSigningOut = true
                    Task { await session.signOut() }
                }
                .accessibilityIdentifier("logout-button")
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            Section("Application") {
                LabeledContent("Version", value: "\(JoleneCore.version) · \(container.environment.mode.rawValue)")
                    .accessibilityIdentifier("profile-version")
                #if DEBUG
                if let monitor = container.networkSentinel {
                    NetworkSentinelRow(monitor: monitor)
                }
                #endif
            }
            ProfilEntreeSection() // lot 3, T9 : « Mon profil » (`MonCompteSoignant.tsx` l.59)
            Section(HubCompte.titreReglages) {
                // Lot 3, T6 : « Notifications » (l.115) vers les préférences ; lien par valeur, `MainTabView` enregistre
                // la destination et pousse le même écran par programme (ligne du centre, tap push).
                NavigationLink(value: PreferencesNotificationsRoute()) {
                    Label(PreferencesTextes.entreeHub, systemImage: "bell")
                }
                .accessibilityIdentifier(PreferencesTextes.identifiantEntreeHub)
                ThemeRow(theme: container.theme, exposerSchemaEffectif: container.isDemo) // lot 3, T11 (D16)
            }
            Section(MotDePasse.Textes.sectionHub) {
                NavigationLink(value: MotDePasseRoute()) {
                    Label(MotDePasse.Textes.titre, systemImage: "key")
                        .font(JoleneFont.body)
                        .foregroundStyle(JoleneColor.midnight)
                        .frame(minHeight: 44, alignment: .leading)
                }
                .accessibilityIdentifier("compte-mdp-ouvrir")
            }
            ExportRGPDSection(model: export) // lot 3, T11
            if let presentateurRenvoiWeb {
                AideEtLegalSection(presentateur: presentateurRenvoiWeb) // lot 3, T11 : après L1-T10
            }
            // Lot 1, T8 (Apple 5.1.1) : dernière section.
            SuppressionCompteSection(session: session, snapshot: snapshot, finDeCompte: container.finDeCompte)
        }
        .accessibilityIdentifier("profile-list")
        .scrollContentBackground(.hidden)
        .background(JoleneColor.lavender.ignoresSafeArea())
        .navigationTitle("Profil")
        .navigationDestination(for: MotDePasseRoute.self) { _ in
            MotDePasseScreen(session: session, snapshot: snapshot)
        }
        .sheet(item: Binding(get: { export.partage }, set: { if $0 == nil { export.partageTermine(complete: false) } })) { fichier in
            PartageExportSheet(fichier: fichier, exposerNom: container.isDemo) { complete in
                export.partageTermine(complete: complete)
            }
        }
    }
}

/// Feuille de partage de l'export, avec, en DEBUG et en démo seulement, le nom du fichier partagé
/// (`compte-export-pret`, preuve XCUITest posée DANS la feuille : le contenu qu'elle recouvre n'est plus exposé).
private struct PartageExportSheet: View {
    let fichier: FichierAPartager
    let exposerNom: Bool
    let termine: @MainActor @Sendable (Bool) -> Void

    var body: some View {
        PartageFichierView(url: fichier.url, termine: termine)
            .ignoresSafeArea()
            #if DEBUG
            .overlay(alignment: .topLeading) {
                if exposerNom {
                    Text(fichier.nom)
                        .font(.system(size: 1))
                        .foregroundStyle(.clear)
                        .frame(width: 1, height: 1)
                        .allowsHitTesting(false)
                        .accessibilityIdentifier("compte-export-pret")
                }
            }
            #endif
    }
}

#if DEBUG
/// Preuve « aucune requête réseau en démo » : libellé `network-sentinel` (« 0 requête »).
/// DEBUG seulement, comme `NetworkSentinel`.
private struct NetworkSentinelRow: View {
    @ObservedObject var monitor: NetworkSentinel.Monitor

    var body: some View {
        // HStack et non LabeledContent : l'identifiant doit désigner la seule valeur « 0 requête ».
        HStack {
            Text("Requêtes réseau (démo)")
            Spacer()
            Text(monitor.label)
                .foregroundStyle(JoleneColor.bubblegum)
                .accessibilityIdentifier("network-sentinel")
        }
    }
}
#endif
