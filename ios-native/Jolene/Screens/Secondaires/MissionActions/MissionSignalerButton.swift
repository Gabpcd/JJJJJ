import SwiftUI
import JoleneCore

/// « Signaler » l'établissement de la mission (`SignalerUtilisateur`, cible `ETABLISSEMENT`,
/// `DetailMissionSoignant.tsx` l.1175) — **stub de L4-T1c**, remplacé par T7b sans retoucher `MissionDetailScreen` ni
/// `ActionsEtablissementMission`. Ne rend rien tant que la tranche n'a pas livré.
struct MissionSignalerButton: View {
    let mission: Mission
    @Environment(\.contexteSecondaire) private var contexte

    var body: some View {
        EmptyView()
    }
}
