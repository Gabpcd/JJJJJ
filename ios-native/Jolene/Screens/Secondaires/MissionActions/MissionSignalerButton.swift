import SwiftUI
import JoleneCore
import JoleneDesign

/// « Signaler » l'établissement de la mission (L4-T7b, `SignalerUtilisateur` variante lien, cible `ETABLISSEMENT`,
/// `mission.etablissement_id` et `mission.id`, `DetailMissionSoignant.tsx` l.1175 et l.1182) : feuille
/// `SignalementSheet` (textes verbatim), confirmation verbatim après acceptation du serveur. Remplace le stub de T1c sans
/// retoucher `MissionDetailScreen` ; le repli « Autres actions » d'une mission ouverte est porté par
/// `ActionsEtablissementMission`.
///
/// Identifiants : `mission-signaler`, `mission-signaler-confirmation`.
struct MissionSignalerButton: View {
    let mission: Mission
    @Environment(\.contexteSecondaire) private var contexte
    @State private var ouvert = false
    @State private var transmis = false

    var body: some View {
        if let contexte, EcranSecondaire.messagerie(conversationId: nil).estLivre, !mission.record.etablissementId.isEmpty {
            VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
                Button {
                    transmis = false
                    ouvert = true
                } label: {
                    Label(MessagerieTextes.Signalement.signaler, systemImage: "flag")
                        .font(JoleneFont.caption)
                        .foregroundStyle(JoleneColor.bubblegum)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("mission-signaler")
                if transmis {
                    InlineNotice(MessagerieTextes.Signalement.succes, tone: .success, identifier: "mission-signaler-confirmation")
                }
            }
            .sheet(isPresented: $ouvert) {
                SignalementSheet(cible: .init(cibleId: mission.record.etablissementId, type: .etablissement, missionId: mission.record.id),
                                 contexte: contexte) { ok in
                    ouvert = false
                    transmis = ok
                }
            }
        }
    }
}
