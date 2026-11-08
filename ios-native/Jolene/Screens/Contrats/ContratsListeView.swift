import SwiftUI
import JoleneCore
import JoleneDesign

/// Liste des contrats du soignant (lot 2, T9a ; `ListeContrats.tsx`) : vue de `ContratsListeModel` (JoleneCore,
/// T8). Filtres « Tous / En attente / Signés / Annulés » appliqués localement comme le web (l.93), filtre initial
/// depuis `?statut=` (`filtreInitial`, route de T10), cartes du rendu mobile du web (`ContratPresentation.carte`),
/// états vides du soignant et erreur de chargement verbatim (`LibellesWeb.Contrats`). Chaque carte ouvre
/// `ContratScreen`.
///
/// Deux présentations : écran poussé (« Mes contrats » du Profil : titre de navigation) ou onglet Contrats de
/// « Mes documents » (T7 : titre dans le contenu, comme le `h2` du web, l.101 ; aucun titre de navigation imposé à
/// l'écran hôte). Identifiants : `contrats-liste`, `contrats-filtre-<statut>`, `contrat-carte-<id>`, `contrats-vide`,
/// `contrats-erreur`, `contrats-reessayer`, `contrats-chargement`, `contrats-session-expiree`.
struct ContratsListeView: View {
    enum Presentation { case ecran, onglet }

    @StateObject private var model: ContratsListeModel
    @ObservedObject private var session: SessionStore
    private let snapshot: SessionSnapshot
    private let presentation: Presentation

    init(session: SessionStore, snapshot: SessionSnapshot, filtreInitial: FiltreContrat = .tous,
         presentation: Presentation = .ecran) {
        self.session = session
        self.snapshot = snapshot
        self.presentation = presentation
        _model = StateObject(wrappedValue: ContratsListeModel(controller: session.controller, snapshot: snapshot,
                                                              filtreInitial: filtreInitial))
    }

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
        .accessibilityIdentifier("contrats-liste")
        .modifier(TitreListe(presentation: presentation))
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
                    guard session.state.snapshot?.epoch == snapshot.epoch else { return }
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
            let cartes = model.affiches.map(ContratPresentation.carte)
            if cartes.isEmpty {
                EmptyState(systemImage: "doc.text", title: LibellesWeb.Contrats.titreVide(model.filtre),
                           message: LibellesWeb.Contrats.descriptionVide(model.filtre), identifier: "contrats-vide")
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

    @ViewBuilder func body(content: Content) -> some View {
        switch presentation {
        case .ecran: content.navigationTitle(LibellesWeb.Contrats.titre)
        case .onglet: content
        }
    }
}

/// Carte d'un contrat (`renduCarte`, `ListeContrats.tsx` l.205-226) : numéro et pastille, mission, type et date de
/// création, appel « Signer le contrat » ou « Voir le contrat » (ouvre la page du contrat ; aucune signature ici).
private struct CarteContratView: View {
    let carte: ContratPresentation.Carte

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
                JoleneBadge(carte.badge, tone: ton)
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
