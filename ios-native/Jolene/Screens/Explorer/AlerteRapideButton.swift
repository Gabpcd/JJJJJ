import SwiftUI
import JoleneCore
import JoleneDesign

extension View {
    /// « Créer une alerte » en un toucher depuis Explorer (L4-T1c, `LOT4_PLAN.md` §1.1 « Filtres sauvegardés »), posé une
    /// fois sur `MissionsListScreen`.
    func alerteRapide(model: MissionsListModel) -> some View {
        modifier(AlerteRapideExplorer(model: model))
    }
}

/// Alerte rapide et « Aller à la recherche » dans Explorer (L4-T4), sans retoucher `MissionsListScreen.swift` :
/// - bouton de la barre « Me prévenir des prochaines missions » (`explorer-alerte-rapide`, cloche), affiché seulement
///   si le coupe-circuit `ios_natif_recherches_actif` est lu vrai, absent ou illisible (fail-open, D18) ; il ouvre la
///   confirmation du web (`RechercheMissions.tsx` l.639-670, vouvoyée) puis `AlerteRapideModel.activer` sur les critères
///   courants d'Explorer (une alerte existante n'est jamais réécrite, une recherche identique sans alerte est activée à
///   sa fréquence, sinon création). Avec un filtre établissement actif, la confirmation dit qu'il n'est pas repris (le
///   validateur serveur refuse la clé). Écart consigné (`LOT4_PLAN.md`, écart n°14) : le web n'offre l'action que dans
///   l'état vide, la fin du paquet de swipe et `?alerte=1` ; l'emplacement de T1c est la barre d'Explorer, toujours
///   visible, le seul que la tranche peut poser sans modifier l'écran partagé ;
/// - recherche déposée par « Aller à la recherche » (`BoiteRechercheExplorer`) : critères appliqués
///   (`FiltresSauvegardesEncodage.explorer`), puis « Filtres « nom » appliqués » (toast du web, ici avis refermable).
/// Identifiants : `explorer-alerte-rapide` ; feuille `alerte-rapide` (`-confirm`, `-cancel`, `alerte-rapide-erreur`) ;
/// avis `alerte-confirmee`, `explorer-recherche-appliquee`, fermeture `explorer-avis-fermer`.
struct AlerteRapideExplorer: ViewModifier {
    @ObservedObject var model: MissionsListModel
    @Environment(\.contexteSecondaire) private var contexte

    func body(content: Content) -> some View {
        if let contexte {
            content.modifier(AlerteRapideActive(missions: model, contexte: contexte))
        } else {
            content
        }
    }
}

private struct AlerteRapideActive: ViewModifier {
    private enum Avis: Equatable {
        case alerte(String)
        case recherche(String)
    }

    @ObservedObject var missions: MissionsListModel
    let contexte: ContexteSecondaire
    @ObservedObject private var boite: BoiteRechercheExplorer
    @StateObject private var alerte: AlerteRapideModel
    @State private var porte = PorteEcranNatif(drapeau: nil)
    @State private var confirmationOuverte = false
    @State private var avis: Avis?

    init(missions: MissionsListModel, contexte: ContexteSecondaire) {
        self.missions = missions
        self.contexte = contexte
        _boite = ObservedObject(wrappedValue: contexte.container.rechercheExplorer)
        _alerte = StateObject(wrappedValue: AlerteRapideModel(controller: contexte.session.controller, snapshot: contexte.snapshot))
    }

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) { bandeau }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if porte == .natif { bouton }
                }
            }
            .confirmationSheet(isPresented: $confirmationOuverte, configuration, isLoading: alerte.enCours, onConfirm: activer) {
                if case let .echec(message)? = alerte.issue {
                    InlineNotice(message, tone: .error, identifier: "alerte-rapide-erreur", announcementID: alerte.jeton)
                }
            }
            .task { porte = await lirePorte() }
            .onAppear { appliquerDemande() }
            .onReceive(boite.$demande) { _ in appliquerDemande() }
    }

    private var bouton: some View {
        Button {
            alerte.effacerIssue()
            confirmationOuverte = true
        } label: {
            Image(systemName: "bell.badge")
                .foregroundStyle(JoleneColor.rose700)
        }
        .accessibilityLabel(FiltresTextes.alerteRapideAction)
        .accessibilityIdentifier("explorer-alerte-rapide")
    }

    @ViewBuilder private var bandeau: some View {
        if let avis {
            HStack(alignment: .top, spacing: JoleneSpacing.sm) {
                switch avis {
                case let .alerte(message):
                    InlineNotice(message, tone: .success, identifier: "alerte-confirmee", announcesOnAppear: true,
                                 announcementID: alerte.jeton)
                case let .recherche(message):
                    InlineNotice(message, tone: .success, identifier: "explorer-recherche-appliquee", announcesOnAppear: true)
                }
                Button {
                    self.avis = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(JoleneFont.caption.weight(.semibold))
                        .foregroundStyle(JoleneColor.midnight)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Fermer")
                .accessibilityIdentifier("explorer-avis-fermer")
            }
            .padding(.horizontal, JoleneSpacing.lg)
            .padding(.vertical, JoleneSpacing.xs)
            .background(JoleneColor.lavender)
        }
    }

    private var configuration: ConfirmationSheet.Configuration {
        ConfirmationSheet.Configuration(
            title: FiltresTextes.alerteRapideTitre,
            message: FiltresTextes.alerteRapideDescription(
                profession: FiltresPresentation.professionAlerte(filtres: missions.filtres, profile: missions.profile),
                rayonKm: missions.filtres.rayonKm,
                // Filtre établissement (`?etablissement=`) : refusé par le validateur serveur, jamais repris ; dit ici.
                filtreEtablissement: missions.filtres.etablissementId != nil),
            confirmTitle: FiltresTextes.alerteRapideActiver,
            cancelTitle: FiltresTextes.alerteRapideAnnuler,
            identifier: "alerte-rapide")
    }

    private func activer() {
        let filtres = missions.filtres
        let profil = missions.profile
        Task {
            guard await alerte.activer(filtres: filtres, profile: profil), case let .confirmee(message)? = alerte.issue else { return }
            confirmationOuverte = false
            avis = .alerte(message)
        }
    }

    /// Recherche déposée par « Aller à la recherche » : appliquée une fois, pour l'utilisateur de cet espace seulement.
    private func appliquerDemande() {
        guard let demande = boite.retirer(userId: contexte.snapshot.user.id) else { return }
        let nouveaux = FiltresSauvegardesEncodage.explorer(depuis: demande.filtres, precedent: missions.filtres)
        avis = .recherche(FiltresTextes.filtresAppliques(nom: demande.nomSource))
        Task { await missions.appliquer(nouveaux) }
    }

    private func lirePorte() async -> PorteEcranNatif {
        await PorteEcranNatif.lire(EcranSecondaire.recherches,
                                   flags: contexte.session.controller.gateways(for: contexte.snapshot.epoch)?.flags)
    }
}
