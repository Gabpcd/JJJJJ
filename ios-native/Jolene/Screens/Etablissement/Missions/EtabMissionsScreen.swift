import SwiftUI
import JoleneCore
import JoleneDesign

/// Liste des missions de l'établissement (lot 5, T5) : vue de `EtabMissionsModel` (JoleneCore), port de
/// `ListeMissions.tsx` sans montant (D15). Pastilles de filtre avec compteurs (« Toutes » par défaut), cartes
/// (`EtabMissionsPresentation.Carte`), « Charger plus » (pages cumulatives de 50), états de chargement, d'erreur et
/// vides du web. Chaque carte pousse la destination `.detailMission` du registre (T2a). Les règles d'état sont
/// testées dans `EtabMissionsModelTests`, les textes dans `EtabMissionsPresentationTests` ; la vue n'ajoute
/// aucune logique.
///
/// Identifiants : `etab-missions-screen`, `etab-missions-scroll`, `etab-missions-filtres`, `etab-missions-filtre-{toutes|<STATUT>}`
/// (libellé « Ouvertes (3) »), `etab-missions-count`, `etab-mission-card-{id}`, `etab-missions-load-more`
/// (+ `-error`), `etab-missions-loading`, `etab-missions-error` (+ `etab-missions-retry`), `etab-missions-empty`,
/// `etab-missions-refresh-error`.
struct EtabMissionsScreen: View {
    @StateObject private var model: EtabMissionsModel
    /// Demande de filtre portée par un lien (`?statut=`, T2b) ; chaque nouveau jeton sélectionne le filtre.
    private let demande: DemandeFiltreMissions

    init(session: SessionStore, snapshot: EtablissementSessionSnapshot, demande: DemandeFiltreMissions) {
        self.demande = demande
        _model = StateObject(wrappedValue: EtabMissionsModel(controller: session.controller, snapshot: snapshot,
                                                             filtre: EtabMissionsFiltre(parametre: demande.statut)))
    }

    var body: some View {
        VStack(spacing: 0) {
            filtres
            ScrollView {
                VStack(alignment: .leading, spacing: JoleneSpacing.md) {
                    contenu
                }
                .padding(JoleneSpacing.lg)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .refreshable { await model.charger() }
            .accessibilityIdentifier("etab-missions-scroll")
        }
        .background(JoleneColor.lavender.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("etab-missions-screen")
        .navigationTitle("Mes missions")
        .navigationBarTitleDisplayMode(.inline)
        // Chaque apparition relit le filtre affiché (liste conservée pendant la relecture), comme le web qui relit
        // à chaque montage (`staleTime` de 60 s non porté : la relecture est plus stricte).
        .task { await model.charger() }
        .onChange(of: demande.jeton) { _ in
            Task { await model.selectionner(EtabMissionsFiltre(parametre: demande.statut)) }
        }
    }

    // MARK: - Filtres

    private var filtres: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: JoleneSpacing.sm) {
                ForEach(EtabMissionsFiltre.allCases) { filtre in
                    FilterChip(EtabMissionsPresentation.libelle(filtre, compteurs: model.compteurs),
                               isSelected: model.filtre == filtre, identifier: filtre.identifiant) {
                        Task { await model.selectionner(filtre) }
                    }
                }
            }
            .padding(.horizontal, JoleneSpacing.lg)
            .padding(.vertical, JoleneSpacing.sm)
        }
        .background(JoleneColor.cloud)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("etab-missions-filtres")
    }

    // MARK: - États

    @ViewBuilder private var contenu: some View {
        switch model.contenu {
        case .chargement:
            VStack(alignment: .leading, spacing: JoleneSpacing.md) {
                Text("Chargement des missions…")
                    .font(JoleneFont.callout)
                    .foregroundStyle(JoleneColor.bubblegum)
                SkeletonCard()
                SkeletonCard()
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("etab-missions-loading")
        case let .echec(message):
            EmptyState(systemImage: "wifi.exclamationmark", title: EtabMissionsPresentation.titreErreurListe, message: message,
                       identifier: "etab-missions-error", actionTitle: "Réessayer",
                       actionIdentifier: "etab-missions-retry") { Task { await model.charger() } }
        case let .chargee(missions) where missions.isEmpty:
            erreurRafraichissement
            let vide = EtabMissionsPresentation.etatVide(model.filtre, compteurs: model.compteurs)
            EmptyState(systemImage: "briefcase", title: vide.titre, message: vide.message, identifier: "etab-missions-empty")
        case let .chargee(missions):
            erreurRafraichissement
            Text(EtabMissionsPresentation.nombreTrouvees(missions.count))
                .font(JoleneFont.callout)
                .foregroundStyle(JoleneColor.bubblegum)
                .accessibilityIdentifier("etab-missions-count")
            ForEach(missions) { mission in
                carte(model.carte(mission))
            }
            if model.aSuivre {
                JoleneButton(EtabMissionsPresentation.chargerPlus, style: .secondary, isLoading: model.chargementSuite) {
                    Task { await model.chargerPlus() }
                }
                .disabled(!model.peutChargerPlus)
                .accessibilityIdentifier("etab-missions-load-more")
            }
            if let erreur = model.erreurSuite {
                InlineNotice(erreur, tone: .error, identifier: "etab-missions-load-more-error", announcesOnAppear: true)
            }
        }
    }

    @ViewBuilder private var erreurRafraichissement: some View {
        if let erreur = model.erreurRafraichissement {
            InlineNotice(erreur, tone: .error, identifier: "etab-missions-refresh-error", announcesOnAppear: true)
        }
    }

    // MARK: - Carte

    private func carte(_ carte: EtabMissionsPresentation.Carte) -> some View {
        NavigationLink(value: EtabDestination.detailMission(id: carte.id)) {
            HStack(alignment: .center, spacing: JoleneSpacing.md) {
                VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: JoleneSpacing.xs) { pastilles(carte.badges) }
                        VStack(alignment: .leading, spacing: JoleneSpacing.xs) { pastilles(carte.badges) }
                    }
                    Text(carte.titre)
                        .font(JoleneFont.headline)
                        .foregroundStyle(JoleneColor.midnight)
                        .multilineTextAlignment(.leading)
                    if !carte.sousTitre.isEmpty {
                        Text(carte.sousTitre)
                            .font(JoleneFont.callout)
                            .foregroundStyle(JoleneColor.bubblegum)
                    }
                    Text(carte.periode)
                        .font(JoleneFont.caption)
                        .foregroundStyle(JoleneColor.midnight)
                    Text(carte.planning)
                        .font(JoleneFont.caption)
                        .foregroundStyle(carte.planningAConfirmer ? JoleneColor.butter800 : JoleneColor.midnight)
                    if let soignant = carte.soignant {
                        Text(soignant)
                            .font(JoleneFont.caption.italic())
                            .foregroundStyle(JoleneColor.bubblegum)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(JoleneFont.caption)
                    .foregroundStyle(JoleneColor.bubblegum)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .padding(JoleneSpacing.md)
            .background(JoleneColor.cloud)
            .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(carte.texteAccessible)
        .accessibilityHint("Ouvre le détail de la mission")
        .accessibilityIdentifier("etab-mission-card-\(carte.id)")
    }

    @ViewBuilder private func pastilles(_ badges: [EtabMissionsPresentation.Badge]) -> some View {
        ForEach(Array(badges.enumerated()), id: \.offset) { _, badge in
            JoleneBadge(badge.texte, tone: MesMissionLigneVue.ton(badge.ton))
        }
    }
}

/// Filtre de statut demandé par un lien vers la liste (`/etablissement/missions?statut=…`, `CibleEtablissement`) :
/// `jeton` avance à chaque demande, même répétée, pour que l'écran déjà monté la rejoue.
struct DemandeFiltreMissions: Equatable {
    var statut: String?
    var jeton = 0
}
