import SwiftUI
import JoleneCore
import JoleneDesign

/// « Mes favoris » (lot 1, T4b), port de `MesFavorisSoignant.tsx` (`/soignant/mes-favoris`), poussé dans
/// l'onglet Explorer. Vue de `FavorisModel` (JoleneCore), partagé avec les étoiles d'Explorer et du
/// détail ; les règles (relecture qui confirme, délai, second appui, session, epoch) sont testées dans
/// `FavorisModelTests`, la vue n'ajoute aucune logique.
///
/// - Missions sauvegardées : missions OUVERTE à venir (filtre du web), ouverture du détail (même pile,
///   étoile du détail synchronisée), « Retirer ».
/// - Établissements suivis : valeurs serveur (`nb_missions_ouvertes`, date du favori), « Voir les missions
///   ouvertes » → Explorer filtré sur l'établissement, « Retirer » après confirmation. Aucun ajout
///   d'établissement en natif (décision 8). « Redemander à travailler ici » (`fn_demander_a_retravailler`)
///   n'est pas porté au lot 1 (écart consigné dans `PARITE_SOIGNANT.md`).
///
/// Identifiants : `favoris-screen` ; `favoris-missions` (+ `-title`), `favori-mission-<missionId>`,
/// `favori-mission-retirer-<missionId>`, `favoris-missions-vide|-chargement|-erreur|-reessayer` ;
/// `favoris-etablissements` (+ `-title`), `favori-etab-<id>`, `favori-etab-badge-<id>`,
/// `favori-etab-depuis-<id>`, `favori-etab-missions-<id>`, `favori-etab-retirer-<id>`,
/// `favoris-etablissements-vide|-chargement|-erreur|-reessayer` ; `favori-etab-retrait` (feuille,
/// + `-title`, `-message`, `-confirm`, `-cancel`, `-erreur`) ; `favoris-action-erreur`,
/// `favoris-session-check`.
struct MesFavorisScreen: View {
    @ObservedObject var favoris: FavorisModel
    @ObservedObject var session: SessionStore
    /// « Voir les missions ouvertes » : Explorer filtré sur l'établissement, puis retour à la liste.
    let voirMissions: (EtablissementFavori) -> Void
    @State private var aRetirer: EtablissementFavori?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JoleneSpacing.xl) {
                if aRetirer == nil {
                    AvisFavoris(favoris: favoris, identifier: "favoris-action-erreur")
                }
                if favoris.sessionExpired {
                    JoleneButton("Vérifier ma session", style: .secondary) { Task { await session.start() } }
                        .accessibilityIdentifier("favoris-session-check")
                }
                sectionMissions
                sectionEtablissements
            }
            .padding(JoleneSpacing.lg)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .refreshable { await favoris.charger() }
        .background(JoleneColor.lavender.ignoresSafeArea())
        .navigationTitle(FavorisPresentation.titreEcran)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("favoris-screen")
        // À chaque apparition, comme le web au montage : les deux listes relues.
        .task { await favoris.charger() }
        .confirmationSheet(isPresented: retraitPresente, configurationRetrait, isLoading: retraitEnCours,
                           onConfirm: confirmerRetrait) {
            AvisFavoris(favoris: favoris, identifier: "favori-etab-retrait-erreur")
        }
    }

    // MARK: - Missions sauvegardées

    private var sectionMissions: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
            SectionHeader(FavorisPresentation.titreMissions(favoris.missionsAffichees.count), identifier: "favoris-missions")
            switch favoris.missions {
            case .chargement:
                SkeletonCard(identifier: "favoris-missions-chargement")
            case let .echec(message):
                echecSection(message, identifiant: "favoris-missions") { await favoris.chargerMissions() }
            case .prete:
                if favoris.missionsAffichees.isEmpty {
                    texteVide(FavorisPresentation.missionsVides, identifiant: "favoris-missions-vide")
                } else {
                    ForEach(favoris.missionsAffichees) { ligne in
                        if let mission = ligne.mission { carteMission(mission) }
                    }
                }
            }
        }
    }

    private func carteMission(_ mission: MissionSauvegardee.Apercu) -> some View {
        HStack(spacing: JoleneSpacing.sm) {
            NavigationLink(value: MissionRoute(id: mission.id)) {
                HStack(spacing: JoleneSpacing.sm) {
                    VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
                        Text(FavorisPresentation.titreMission(mission))
                            .font(JoleneFont.headline)
                            .foregroundStyle(JoleneColor.midnight)
                            .multilineTextAlignment(.leading)
                        Text(FavorisPresentation.detailMission(mission))
                            .font(JoleneFont.caption)
                            .foregroundStyle(JoleneColor.bubblegum)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(JoleneFont.caption.weight(.semibold))
                        .foregroundStyle(JoleneColor.rose700)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(FavorisPresentation.titreMission(mission)), \(FavorisPresentation.detailMission(mission))")
            .accessibilityHint("Ouvre le détail de la mission")
            .accessibilityIdentifier("favori-mission-\(mission.id)")
            boutonTexte(FavorisPresentation.retirer, identifiant: "favori-mission-retirer-\(mission.id)",
                        libelle: "Retirer \(FavorisPresentation.titreMission(mission)) de mes missions sauvegardées",
                        desactive: favoris.enCours(missionId: mission.id)) {
                Task { await favoris.retirerMission(mission.id) }
            }
        }
        .padding(JoleneSpacing.md)
        .background(JoleneColor.cloud)
        .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
    }

    // MARK: - Établissements suivis

    private var sectionEtablissements: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
            SectionHeader(FavorisPresentation.titreEtablissements, identifier: "favoris-etablissements")
            Text(FavorisPresentation.explicationEtablissements)
                .font(JoleneFont.caption)
                .foregroundStyle(JoleneColor.bubblegum)
                .fixedSize(horizontal: false, vertical: true)
            switch favoris.etablissements {
            case .chargement:
                SkeletonCard(identifier: "favoris-etablissements-chargement")
            case let .echec(message):
                echecSection(message, identifiant: "favoris-etablissements") { await favoris.chargerEtablissements() }
            case let .prete(etablissements) where etablissements.isEmpty:
                texteVide(FavorisPresentation.etablissementsVides, identifiant: "favoris-etablissements-vide")
            case let .prete(etablissements):
                ForEach(etablissements) { carteEtablissement($0) }
            }
        }
    }

    private func carteEtablissement(_ etablissement: EtablissementFavori) -> some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
            HStack(alignment: .top, spacing: JoleneSpacing.sm) {
                VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
                    Text(FavorisPresentation.nom(etablissement))
                        .font(JoleneFont.headline)
                        .foregroundStyle(JoleneColor.midnight)
                        .accessibilityAddTraits(.isHeader)
                    Text(FavorisPresentation.lieu(etablissement))
                        .font(JoleneFont.caption)
                        .foregroundStyle(JoleneColor.bubblegum)
                }
                Spacer(minLength: 0)
                if let badge = FavorisPresentation.badgeMissions(etablissement.nbMissionsOuvertes) {
                    JoleneBadge(badge, tone: .info)
                        .accessibilityIdentifier("favori-etab-badge-\(etablissement.id)")
                }
            }
            if let depuis = FavorisPresentation.favoriDepuis(etablissement.creeLe) {
                Text(depuis)
                    .font(JoleneFont.caption)
                    .foregroundStyle(JoleneColor.bubblegum)
                    .accessibilityIdentifier("favori-etab-depuis-\(etablissement.id)")
            }
            HStack(spacing: JoleneSpacing.sm) {
                if FavorisPresentation.afficheVoirMissions(etablissement.nbMissionsOuvertes) {
                    JoleneButton(FavorisPresentation.voirMissions, style: .secondary) { voirMissions(etablissement) }
                        .accessibilityIdentifier("favori-etab-missions-\(etablissement.id)")
                }
                Spacer(minLength: 0)
                boutonTexte(FavorisPresentation.retirer, identifiant: "favori-etab-retirer-\(etablissement.id)",
                            libelle: "Retirer \(FavorisPresentation.nom(etablissement)) de mes favoris",
                            desactive: favoris.retraitEnCours(etablissementId: etablissement.id)) {
                    favoris.effacerErreur()
                    aRetirer = etablissement
                }
            }
        }
        .padding(JoleneSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(JoleneColor.cloud)
        .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("favori-etab-\(etablissement.id)")
    }

    // MARK: - Retrait d'un établissement

    private var retraitPresente: Binding<Bool> {
        Binding(get: { aRetirer != nil }, set: { if !$0 { aRetirer = nil } })
    }

    private var retraitEnCours: Bool {
        aRetirer.map { favoris.retraitEnCours(etablissementId: $0.id) } ?? false
    }

    private var configurationRetrait: ConfirmationSheet.Configuration {
        ConfirmationSheet.Configuration(
            title: FavorisPresentation.titreRetraitEtablissement,
            message: FavorisPresentation.messageRetraitEtablissement(nom: aRetirer?.nom),
            confirmTitle: FavorisPresentation.retirer,
            variant: .danger,
            identifier: "favori-etab-retrait")
    }

    private func confirmerRetrait() {
        guard let cible = aRetirer else { return }
        Task {
            // La feuille ne se referme qu'après une relecture qui confirme le retrait.
            if await favoris.retirerEtablissement(cible.id) { aRetirer = nil }
        }
    }

    // MARK: - Éléments communs

    private func echecSection(_ message: String, identifiant: String, reessayer: @escaping () async -> Void) -> some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
            InlineNotice(message, tone: .error, identifier: "\(identifiant)-erreur")
            if !favoris.sessionExpired {
                JoleneButton("Réessayer", style: .secondary) { Task { await reessayer() } }
                    .accessibilityIdentifier("\(identifiant)-reessayer")
            }
        }
    }

    private func texteVide(_ texte: String, identifiant: String) -> some View {
        Text(texte)
            .font(JoleneFont.callout)
            .foregroundStyle(JoleneColor.bubblegum)
            .fixedSize(horizontal: false, vertical: true)
            .padding(JoleneSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(JoleneColor.cloud)
            .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
            .accessibilityIdentifier(identifiant)
    }

    private func boutonTexte(_ titre: String, identifiant: String, libelle: String, desactive: Bool,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(titre)
                .font(JoleneFont.callout.weight(.semibold))
                .foregroundStyle(JoleneColor.rose800)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(desactive)
        .accessibilityLabel(libelle)
        .accessibilityIdentifier(identifiant)
    }
}
