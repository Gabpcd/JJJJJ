import SwiftUI
import JoleneCore
import JoleneDesign

/// Étoile « sauvegarder cette mission » (lot 1, T4b), port de `BoutonSauvegarderMission.tsx` : même
/// `FavorisModel` pour la carte Explorer et le détail, l'état affiché est celui de la dernière relecture.
/// Désactivée pendant l'appel (second appui ignoré) ; cible tactile de 44 pt ; style `.borderless` pour
/// rester distincte du lien de la carte dans une `List`. Identifiant : `favori-toggle-<missionId>`, valeur
/// vocalisée « Sauvegardée » / « Non sauvegardée », ou « État inconnu » (désactivée) tant que la liste n'est pas relue
/// (revue B8 de T4b, m3 : jamais « Non sauvegardée » par défaut ; l'échec est annoncé par `AvisLectureEtoiles`).
/// `contexte` : surface de l'étoile, où son erreur éventuelle est affichée (m4).
struct BoutonFavoriMission: View {
    @ObservedObject var favoris: FavorisModel
    let missionId: String
    let contexte: ContexteFavoris

    var body: some View {
        let etat = favoris.etoile(missionId)
        Button {
            Task { await favoris.basculer(missionId: missionId, depuis: contexte) }
        } label: {
            Image(systemName: etat == .sauvegardee ? "star.fill" : "star")
                .font(JoleneFont.headline)
                .foregroundStyle(etat == .sauvegardee ? JoleneColor.butter800 : JoleneColor.bubblegum)
                .opacity(etat == .inconnue ? 0.4 : 1)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(etat == .inconnue || favoris.enCours(missionId: missionId))
        .accessibilityLabel(FavorisPresentation.libelleEtoile(etat))
        .accessibilityValue(FavorisPresentation.valeurEtoile(etat))
        .accessibilityIdentifier("favori-toggle-\(missionId)")
    }
}

/// Échec de la première lecture des étoiles (revue B8 de T4b, m3) : message de la lecture et « Réessayer », ou
/// « Vérifier ma session » si la session est à vérifier (M1 : `verifierSession`, jamais une impasse). Rien sinon.
struct AvisLectureEtoiles: View {
    @ObservedObject var favoris: FavorisModel
    @ObservedObject var session: SessionStore
    let contexte: ContexteFavoris
    let identifier: String

    var body: some View {
        if let message = favoris.echecLectureEtoiles {
            VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
                InlineNotice(message, tone: .error, identifier: identifier, announcesOnAppear: true,
                             announcementID: favoris.tentatives)
                if favoris.sessionExpired {
                    JoleneButton("Vérifier ma session", style: .secondary) {
                        Task { await favoris.verifierSession(session) }
                    }
                    .accessibilityIdentifier("\(identifier)-session")
                } else {
                    JoleneButton("Réessayer", style: .secondary) {
                        Task { await favoris.chargerMissions(depuis: contexte) }
                    }
                    .accessibilityIdentifier("\(identifier)-reessayer")
                }
            }
        }
    }
}

/// Erreur d'une action sur les favoris (étoile, retrait) ou d'une relecture, affichée là où l'action a
/// eu lieu et annoncée à VoiceOver ; « Fermer » l'efface. Rien tant qu'aucune erreur de ce contexte n'est
/// signalée (m4 : l'erreur de l'étoile du détail ne réapparaît pas sur la liste). `verifierSession` (Explorer, détail) :
/// une session à vérifier propose aussi « Vérifier ma session », qui revalide puis relit (revue B8 delta de #1149, m2) ;
/// `nil` sur « Mes favoris », dont l'écran porte déjà ce bouton.
struct AvisFavoris: View {
    @ObservedObject var favoris: FavorisModel
    let contexte: ContexteFavoris
    let identifier: String
    var verifierSession: (@MainActor () async -> Void)? = nil

    var body: some View {
        if let message = favoris.erreur(pour: contexte) {
            HStack(alignment: .top, spacing: JoleneSpacing.sm) {
                VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
                    InlineNotice(message, tone: .error, identifier: identifier, announcesOnAppear: true,
                                 announcementID: favoris.tentatives)
                    if favoris.sessionExpired, let verifierSession {
                        JoleneButton("Vérifier ma session", style: .secondary) { Task { await verifierSession() } }
                            .accessibilityIdentifier("\(identifier)-session")
                    }
                }
                Button {
                    favoris.effacerErreur()
                } label: {
                    Image(systemName: "xmark")
                        .font(JoleneFont.callout.weight(.semibold))
                        .foregroundStyle(JoleneColor.midnight)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Fermer le message")
                .accessibilityIdentifier("\(identifier)-fermer")
            }
        }
    }
}

/// Bandeau d'Explorer filtré sur un établissement (« Voir les missions ouvertes » de « Mes favoris ») :
/// le filtre est visible et retirable, jamais conservé à l'insu de l'utilisateur.
struct FiltreEtablissementBandeau: View {
    let libelle: String
    let retirer: () -> Void

    var body: some View {
        HStack(spacing: JoleneSpacing.sm) {
            Image(systemName: "building.2")
                .foregroundStyle(JoleneColor.mauve700)
                .accessibilityHidden(true)
            Text(libelle)
                .font(JoleneFont.callout.weight(.semibold))
                .foregroundStyle(JoleneColor.midnight)
                .lineLimit(2)
                .accessibilityIdentifier("explorer-filtre-etablissement-libelle")
            Spacer(minLength: 0)
            Button(action: retirer) {
                Text("Retirer")
                    .font(JoleneFont.callout.weight(.semibold))
                    .foregroundStyle(JoleneColor.rose800)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Retirer le filtre établissement")
            .accessibilityIdentifier("explorer-filtre-etablissement-retirer")
        }
        .padding(.horizontal, JoleneSpacing.md)
        .background(JoleneColor.mauve100)
        .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.field))
        .padding(.horizontal, JoleneSpacing.lg)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("explorer-filtre-etablissement")
    }
}
