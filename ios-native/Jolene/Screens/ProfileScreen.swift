import SwiftUI
import JoleneCore
import JoleneDesign

/// Onglet Profil = hub « Mon compte » (`MonCompteSoignant.tsx`, route `/soignant/mon-compte`, `.monCompte`) ;
/// seule surface du hub (correction 18 du blueprint du lot 3 : aucun `MonCompteScreen` parallèle). Sections :
/// - lot 0 : « Compte » (identité minimale), « Se déconnecter », « Application » (version, diagnostic démo) — en
///   tête et inchangées : les XCUITest des lots 0 à 3 les lisent sans défilement (écart d'ordre assumé avec le web,
///   qui place « Se déconnecter » après « Aide & légal ») ;
/// - lot 2, T4a (décision 24 du lot 2) : « Mon espace » (`EspaceSoignantSection` : Mes présences, Mes documents,
///   Mes contrats, consentement GPS), juste après « Application », comme au lot 2 ;
/// - lot 3, T9 : « Mon profil » (`ProfilEntreeSection`, `profil-ouvrir`) ;
/// - lot 3, T14a et T14b : une seule section « Paiements & facturation » (`PaiementsFacturationSection`,
///   `MonCompteSoignant.tsx` l.64-77), juste après « Mon profil » comme le web ; lignes dans l'ordre du web :
///   « Compte de paiement (Stripe) » (`StripeConnectEntreeLigne`, `profile-stripe-connect`, montée seulement si la règle
///   web `estLiberal` est vraie à la lecture de l'exercice ; `StripeConnectRoute` enregistrée par `MainTabView`), puis
///   « Coordonnées bancaires » (`IbanEntreeLigne`, `iban-ouvrir`, `IbanRoute` enregistrée ici) ;
/// - « Réglages » : « Notifications » (T6, préférences, `profile-preferences-notifications`, hôte de la carte
///   d'autorisation de T4 : aucune seconde carte ici) et le thème Système / Clair / Sombre (T11, D16) ;
/// - T11 : « Connexion & sécurité » (« Changer mon mot de passe », `compte-mdp-ouvrir` ; issue d'une demande dont
///   l'écran a été dépilé, `compte-mdp-issue-hub`), « Mes données (RGPD) » (export JSON / CSV ; feuille de partage
///   présentée hub à l'écran seulement), « Aide & légal » (pages publiques en Safari, montée seulement avec le
///   présentateur `.safari` du coordinateur des liens, L3-T3b) ;
/// - lot 1, T8 : « Suppression de compte », dernière section.
/// Entrées natives en liens par valeur (`ProfilEditionRoute`, `PreferencesNotificationsRoute` enregistrées par
/// `MainTabView` ; `MotDePasseRoute` enregistrée ici, sur la liste et non dans ses lignes) ; celles de « Mon espace »
/// (lot 2) en liens à destination. Entrées web : `JoleneRoute` puis `DestinationLien.destination`. Points d'extension
/// (sans entrée tant que l'écran ou le présentateur manque) : biométrie (L1-T9), centre de notifications (ouvert depuis
/// l'Accueil, le hub web n'en a pas). Identifiant de la liste : `profile-list`.
struct ProfileScreen: View {
    let container: AppContainer
    @ObservedObject var session: SessionStore
    let snapshot: SessionSnapshot
    /// Bascule d'onglet des actions des états vides de la page Présences (lot 2, T4a).
    var ouvrirOnglet: (MainTabView.Tab) -> Void = { _ in }
    @State private var isSigningOut = false
    /// Export RGPD : modèle tenu par le hub (et non par sa section, ligne d'une liste paresseuse) pour que la
    /// feuille de partage survive au défilement.
    @StateObject private var export: ExportRGPDModel
    /// Mot de passe : modèle tenu par le hub (revue B8, m3) pour qu'un retour programmé de la pile en pleine
    /// demande ne perde pas l'issue (annoncée ici, `compte-mdp-issue-hub`).
    @StateObject private var motDePasse: MotDePasseModel
    @Environment(\.presentateurRenvoiWeb) private var presentateurRenvoiWeb
    /// Lot 3, T14a : entrée « Compte de paiement (Stripe) », montrée selon l'exercice lu (`StripeConnectEntreeLigne`).
    @State private var entreeStripe = false

    init(container: AppContainer, session: SessionStore, snapshot: SessionSnapshot,
         ouvrirOnglet: @escaping (MainTabView.Tab) -> Void = { _ in }) {
        self.container = container
        self.session = session
        self.snapshot = snapshot
        self.ouvrirOnglet = ouvrirOnglet
        _export = StateObject(wrappedValue: ExportRGPDModel(session: session, snapshot: snapshot))
        _motDePasse = StateObject(wrappedValue: MotDePasseModel(session: session, snapshot: snapshot))
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
            // Lot 2, T4a (décision 24) : Mes présences, Mes documents, Mes contrats. Placée après « Application »
            // pour ne pas déplacer la déconnexion ni la sentinelle réseau, lues sans défilement par les XCUITest
            // des lots 0 et 1 (cellules hors écran d'une `List` absentes de l'arbre d'accessibilité).
            // Une ligne par tranche (T4a présences, T7 documents, T9a contrats ; T4b consentement GPS).
            EspaceSoignantSection(session: session, snapshot: snapshot) // L2-T10 : liens par valeur (`MonEspaceRoute`)
            ProfilEntreeSection() // lot 3, T9 : « Mon profil » (`MonCompteSoignant.tsx` l.59)
            // Lot 3, T14a et T14b : une seule section « Paiements & facturation » (l.64-77), Stripe (l.67-68, libéral) puis
            // « Coordonnées bancaires » (l.73). Toujours présente ; la ligne Stripe, montée une fois l'exercice lu, décale
            // d'une ligne ce qui la suit.
            PaiementsFacturationSection(entreeStripe: entreeStripe)
            // Lot 4, T1c : renvois web assumés (T13) puis écrans secondaires livrés, dans l'ordre du hub web ; rien avant
            // leurs tranches.
            RenvoisWebHubSection(session: session, snapshot: snapshot)
            ActiviteSoignantSection()
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
                if let issue = motDePasse.issueAuHub {
                    InlineNotice(issue.texte, tone: issue.estSucces ? .success : .error, identifier: "compte-mdp-issue-hub",
                                 announcesOnAppear: true, announcementID: motDePasse.annonces)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: JoleneSpacing.sm, leading: 0, bottom: JoleneSpacing.sm, trailing: 0))
                }
            }
            ExportRGPDSection(model: export, exposerResidus: container.isDemo) // lot 3, T11
            if let presentateurRenvoiWeb {
                AideEtLegalSection(presentateur: presentateurRenvoiWeb) // lot 3, T11 (présentateur de L3-T3b)
            }
            // Lot 1, T8 (Apple 5.1.1) : dernière section.
            SuppressionCompteSection(session: session, snapshot: snapshot, finDeCompte: container.finDeCompte)
        }
        .accessibilityIdentifier("profile-list")
        .scrollContentBackground(.hidden)
        .background(JoleneColor.lavender.ignoresSafeArea())
        .navigationTitle("Profil")
        .navigationDestination(for: MotDePasseRoute.self) { _ in
            MotDePasseScreen(model: motDePasse)
        }
        .navigationDestination(for: IbanRoute.self) { _ in
            IbanScreen(session: session, snapshot: snapshot) // lot 3, T14b
        }
        // Lot 3, T14a : exercice relu à chaque apparition du hub (entrée Stripe selon la règle web `estLiberal`).
        .task { entreeStripe = await StripeConnectEntreeLigne.estVisible(session: session, snapshot: snapshot) }
        // Export RGPD (revue B8, M1 et m3) : la feuille n'est présentée que hub à l'écran, une seule fois, par
        // UIKit (`FeuillePartageExport`, fin unique `completionWithItemsHandler`) ; un export abouti pendant qu'un
        // autre onglet ou un écran empilé est affiché attend le retour du hub.
        .onAppear { export.hubAffiche(true) }
        .onDisappear { export.hubAffiche(false) }
        .onChange(of: export.fichierAPresenter) { fichier in
            guard let fichier else { return }
            FeuillePartageExport.presenter(fichier, model: export, exposerNom: container.isDemo)
        }
    }
}

/// Section « Paiements & facturation » du hub (`MonCompteSoignant.tsx` l.64-77), unique (intégration de T14a et T14b,
/// revue B8 de #1144) : « Compte de paiement (Stripe) » (l.67-68) seulement pour un exercice libéral lu
/// (`entreeStripe`), puis « Coordonnées bancaires » (l.73), toujours. « Mandat de facturation » (l.69-70) n'est pas
/// porté (renvoi web, lot 4 ; `DECISIONS_LOT3.md`, section T14a). Titre unique : `StripeConnectTextes.sectionHub`.
struct PaiementsFacturationSection: View {
    let entreeStripe: Bool

    var body: some View {
        Section(StripeConnectTextes.sectionHub) {
            if entreeStripe { StripeConnectEntreeLigne() } // lot 3, T14a
            IbanEntreeLigne() // lot 3, T14b
        }
    }
}

#if DEBUG
/// Preuve « aucune requête réseau en démo » : libellé `network-sentinel` (« 0 requête »).
/// DEBUG seulement, comme `NetworkSentinel`. Interne (lot 5, T2a) : partagé avec le compte établissement.
struct NetworkSentinelRow: View {
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
