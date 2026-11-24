import SwiftUI
import JoleneCore
import JoleneDesign

/// Liste des contrats du soignant (lot 2, T9a ; `ListeContrats.tsx`) : vue de `ContratsListeModel` (JoleneCore,
/// T8). Filtres « Tous / En attente / Signés / Annulés » appliqués localement comme le web (l.93), ouverts sur « Tous »
/// (aucun lien ne porte `?statut=` : écart consigné par L2-T10, `ContratsDestination`), cartes du rendu mobile du web
/// (`ContratPresentation.carte`), états vides du soignant et erreur de chargement verbatim (`LibellesWeb.Contrats`).
/// Chaque carte ouvre `ContratScreen`.
///
/// Deux présentations : écran poussé (« Mes contrats » du Profil : titre de navigation) ou onglet Contrats de
/// « Mes documents » (T7 : titre dans le contenu, comme le `h2` du web, l.101 ; aucun titre de navigation imposé à
/// l'écran hôte). Identifiants : `contrats-liste`, `contrats-filtre-<statut>`, `contrat-carte-<id>`, `contrats-vide`,
/// `contrats-erreur`, `contrats-reessayer`, `contrats-chargement`, `contrats-session-expiree`.
///
/// Espace établissement (lot 5, T10 ; D18 : même vue, aucun doublon) : liste de l'établissement confirmé
/// (`ContratsListeModel(controller:etablissement:)`), filtre initial `?statut=` du lien, titre et états vides de la
/// branche établissement du web (`EtabContratsPresentation`), « Signer le contrat » tant que l'établissement n'a pas
/// signé. Chaque carte pousse la destination `.contrat(id:)` du registre (permission et drapeau relus avant l'écran).
/// Identifiants propres : `etab-contrats-screen` (racine), `etab-contrat-{id}` (carte), `etab-contrat-statut-{id}`.
struct ContratsListeView: View {
    enum Presentation { case ecran, onglet }

    @StateObject private var model: ContratsListeModel
    @ObservedObject private var session: SessionStore
    private let epoch: Int
    private let presentation: Presentation

    init(session: SessionStore, snapshot: SessionSnapshot, presentation: Presentation = .ecran) {
        self.session = session
        self.epoch = snapshot.epoch
        self.presentation = presentation
        _model = StateObject(wrappedValue: ContratsListeModel(controller: session.controller, snapshot: snapshot))
    }

    /// Contrats de l'établissement (lot 5, T10), écran poussé sur l'onglet Missions.
    init(session: SessionStore, etablissement snapshot: EtablissementSessionSnapshot, statut: String?) {
        self.session = session
        self.epoch = snapshot.epoch
        self.presentation = .ecran
        _model = StateObject(wrappedValue: ContratsListeModel(
            controller: session.controller, etablissement: snapshot, filtreInitial: FiltreContrat.initial(statut: statut),
            relirePerimetre: { [weak session] in await session?.refreshEtablissementScope() }))
    }

    private var estEtablissement: Bool { model.partie == .etablissement }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JoleneSpacing.lg) {
                if presentation == .onglet {
                    Text(LibellesWeb.Contrats.titre)
                        .font(JoleneFont.title)
                        .foregroundStyle(JoleneColor.midnight)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.horizontal, JoleneSpacing.lg)
                }
                FilterChipRow(identifier: "contrats-filtres") {
                    ForEach(FiltreContrat.allCases, id: \.self) { filtre in
                        FilterChip(LibellesWeb.Contrats.libelleFiltre(filtre), isSelected: model.filtre == filtre,
                                   identifier: "contrats-filtre-\(filtre.rawValue)") { model.choisir(filtre) }
                    }
                }
                contenu
                    .padding(.horizontal, JoleneSpacing.lg)
            }
            .padding(.vertical, JoleneSpacing.lg)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .background(JoleneColor.lavender.ignoresSafeArea())
        .accessibilityIdentifier(estEtablissement ? "etab-contrats-screen" : "contrats-liste")
        .modifier(TitreListe(presentation: presentation,
                             titre: estEtablissement ? EtabContratsPresentation.titre : LibellesWeb.Contrats.titre))
        .task { await model.charger() }
        .refreshable { await model.charger() }
    }

    @ViewBuilder private var contenu: some View {
        switch model.etat {
        case .chargement:
            VStack(spacing: JoleneSpacing.md) {
                ForEach(0..<3, id: \.self) { _ in SkeletonCard() }
            }
            .accessibilityIdentifier("contrats-chargement")
        case let .echec(message) where model.sessionExpired:
            EmptyState(systemImage: "person.crop.circle.badge.exclamationmark", title: "Session à vérifier", message: message,
                       identifier: "contrats-session-expiree", actionTitle: "Vérifier ma session",
                       actionIdentifier: "contrats-session-verifier") {
                Task {
                    await session.start()
                    let courant = estEtablissement ? session.state.snapshotEtablissement?.epoch : session.state.snapshot?.epoch
                    guard courant == epoch else { return }
                    await model.charger()
                }
            }
        case .echec:
            EmptyState(systemImage: "wifi.exclamationmark", title: LibellesWeb.Contrats.indisponiblesTitre,
                       message: LibellesWeb.Contrats.chargementNAbouti, identifier: "contrats-erreur",
                       actionTitle: LibellesWeb.Contrats.reessayer, actionIdentifier: "contrats-reessayer") {
                Task { await model.charger() }
            }
        case .charge:
            let cartes = model.affiches.map { ContratPresentation.carte($0, partie: model.partie) }
            if cartes.isEmpty {
                let vide = estEtablissement ? EtabContratsPresentation.etatVide(model.filtre)
                    : (titre: LibellesWeb.Contrats.titreVide(model.filtre), message: LibellesWeb.Contrats.descriptionVide(model.filtre))
                EmptyState(systemImage: "doc.text", title: vide.titre, message: vide.message, identifier: "contrats-vide")
            } else if estEtablissement {
                LazyVStack(spacing: JoleneSpacing.md) {
                    ForEach(cartes) { carte in
                        NavigationLink(value: EtabDestination.contrat(id: carte.id)) {
                            CarteContratView(carte: carte, identifiantStatut: "etab-contrat-statut-\(carte.id)")
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("etab-contrat-\(carte.id)")
                    }
                }
            } else {
                LazyVStack(spacing: JoleneSpacing.md) {
                    ForEach(cartes) { carte in
                        NavigationLink {
                            ContratScreen(session: session, snapshot: snapshot, contratId: carte.id)
                        } label: {
                            CarteContratView(carte: carte)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("contrat-carte-\(carte.id)")
                    }
                }
            }
        }
    }
}

/// Titre de navigation de l'écran poussé seulement (l'onglet de « Mes documents » garde le titre de son hôte).
private struct TitreListe: ViewModifier {
    let presentation: ContratsListeView.Presentation
    let titre: String

    @ViewBuilder func body(content: Content) -> some View {
        switch presentation {
        case .ecran: content.navigationTitle(titre)
        case .onglet: content
        }
    }
}

/// Carte d'un contrat (`renduCarte`, `ListeContrats.tsx` l.205-226) : numéro et pastille, mission, type et date de
/// création, appel « Signer le contrat » ou « Voir le contrat » (ouvre la page du contrat ; aucune signature ici).
private struct CarteContratView: View {
    let carte: ContratPresentation.Carte
    /// Identifiant de la pastille de statut (espace établissement seulement, T10).
    var identifiantStatut: String?

    var body: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: JoleneSpacing.sm) {
                Image(systemName: "doc.text")
                    .foregroundStyle(JoleneColor.rose700)
                    .accessibilityHidden(true)
                Text(carte.numero)
                    .font(JoleneFont.headline)
                    .foregroundStyle(JoleneColor.midnight)
                    .lineLimit(1)
                Spacer(minLength: JoleneSpacing.sm)
                if let identifiantStatut {
                    JoleneBadge(carte.badge, tone: ton).accessibilityIdentifier(identifiantStatut)
                } else {
                    JoleneBadge(carte.badge, tone: ton)
                }
            }
            Text(carte.mission)
                .font(JoleneFont.callout)
                .foregroundStyle(JoleneColor.bubblegum)
                .lineLimit(1)
            Text(carte.typeEtDate)
                .font(JoleneFont.caption)
                .foregroundStyle(JoleneColor.bubblegum)
            HStack(spacing: JoleneSpacing.xs) {
                Text(carte.action)
                    .font(JoleneFont.button)
                    .foregroundStyle(carte.aSigner ? JoleneColor.rose700 : JoleneColor.midnight)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(JoleneFont.caption.weight(.semibold))
                    .foregroundStyle(JoleneColor.bubblegum)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
        }
        .padding(JoleneSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(JoleneColor.cloud)
        .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
        .contentShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
    }

    private var ton: JoleneBadge.Tone {
        switch carte.statut {
        case .signe: return .success
        case .annule: return .error
        case .enAttente: return .warning
        }
    }
}
