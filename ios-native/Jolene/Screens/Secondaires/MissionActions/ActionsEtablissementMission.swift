import SwiftUI
import JoleneCore
import JoleneDesign

/// Actions du lot 4 sur le détail d'une mission (L4-T1c, correction 20 et D25 de `LOT4_PLAN.md`), dans l'ordre du web
/// (revue B8 de #1159, m2) et posées une fois dans `MissionDetailScreen` :
/// - au bas du bloc de l'établissement, cette section : « Ne plus travailler ensemble » (`BoutonExclusion`, T11) puis
///   « Signaler » (`SignalerUtilisateur`, T7b), pour toute mission qui a un établissement, repliés sous « Autres
///   actions » pour une mission ouverte non assignée (`DetailMissionSoignant.tsx` l.1160-1183) ;
/// - après « Annuler ma participation », le fil de discussion (`MissionContactButton`, T7b, l.1550-1558).
/// Chaque bouton est un stub dans son propre fichier, remplacé par sa tranche (statuts, textes verbatim, cible
/// `mission.etablissement_id`) ; tant qu'aucune n'a livré, rien n'est rendu et le détail reste celui d'avant le lot 4.
/// Le repli « Autres actions » (T7b) est commun aux deux boutons : il n'apparaît que si l'un d'eux est livré.
/// Contexte des écrans secondaires : `contexteSecondaire`.
///
/// Identifiants : `mission-autres-actions`.
struct ActionsEtablissementMission: View {
    let mission: Mission
    @Environment(\.contexteSecondaire) private var contexte
    @State private var replisOuverts = false

    var body: some View {
        if replie {
            VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
                Button {
                    replisOuverts.toggle()
                } label: {
                    Label(MessagerieTextes.autresActions, systemImage: "ellipsis")
                        .font(JoleneFont.caption)
                        .foregroundStyle(JoleneColor.bubblegum)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("mission-autres-actions")
                if replisOuverts { boutons }
            }
        } else {
            boutons
        }
    }

    @ViewBuilder private var boutons: some View {
        MissionExclusionButton(mission: mission)
        MissionSignalerButton(mission: mission)
    }

    /// Mission ouverte, pas encore assignée à ce soignant (`estOuverte && !estAssigne`, l.1162), et au moins une des deux
    /// actions livrée (aujourd'hui : le signalement, T7b).
    private var replie: Bool {
        guard let contexte, EcranSecondaire.messagerie(conversationId: nil).estLivre, mission.record.statut == "OUVERTE" else {
            return false
        }
        let assigne = mission.record.soignantAssigneId?.caseInsensitiveCompare(contexte.snapshot.user.id) == .orderedSame
        return !assigne
    }
}
