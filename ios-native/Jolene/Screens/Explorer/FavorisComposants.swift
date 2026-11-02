import SwiftUI
import JoleneCore
import JoleneDesign

/// Étoile « sauvegarder cette mission » (lot 1, T4b), port de `BoutonSauvegarderMission.tsx` : même
/// `FavorisModel` pour la carte Explorer et le détail, l'état affiché est celui de la dernière relecture.
/// Désactivée pendant l'appel (second appui ignoré) ; cible tactile de 44 pt ; style `.borderless` pour
/// rester distincte du lien de la carte dans une `List`. Identifiant : `favori-toggle-<missionId>`, valeur
/// vocalisée « Sauvegardée » / « Non sauvegardée ».
struct BoutonFavoriMission: View {
    @ObservedObject var favoris: FavorisModel
    let missionId: String

    var body: some View {
        let sauvegardee = favoris.estSauvegardee(missionId)
        Button {
            Task { await favoris.basculer(missionId: missionId) }
        } label: {
            Image(systemName: sauvegardee ? "star.fill" : "star")
                .font(JoleneFont.headline)
                .foregroundStyle(sauvegardee ? JoleneColor.butter800 : JoleneColor.bubblegum)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(favoris.enCours(missionId: missionId))
        .accessibilityLabel(FavorisPresentation.libelleEtoile(sauvegardee: sauvegardee))
        .accessibilityValue(FavorisPresentation.valeurEtoile(sauvegardee: sauvegardee))
        .accessibilityIdentifier("favori-toggle-\(missionId)")
    }
}

/// Erreur d'une action sur les favoris (étoile, retrait) ou d'une relecture, affichée là où l'action a
/// eu lieu et annoncée à VoiceOver ; « Fermer » l'efface. Rien tant qu'aucune erreur n'est signalée.
struct AvisFavoris: View {
    @ObservedObject var favoris: FavorisModel
    let identifier: String

    var body: some View {
        if let message = favoris.erreurAction {
            HStack(alignment: .top, spacing: JoleneSpacing.sm) {
                InlineNotice(message, tone: .error, identifier: identifier, announcesOnAppear: true,
                             announcementID: favoris.tentatives)
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
