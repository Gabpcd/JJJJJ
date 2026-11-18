import SwiftUI
import JoleneCore

/// « Ne plus travailler ensemble » (`BoutonExclusion` puis `fn_exclure_utilisateur`, `DetailMissionSoignant.tsx`
/// l.1174) — **stub de L4-T1c**, remplacé par T11 sans retoucher `MissionDetailScreen` ni `MissionActionsSection`. Ne
/// rend rien tant que la tranche n'a pas livré.
struct MissionExclusionButton: View {
    let mission: Mission
    @Environment(\.contexteSecondaire) private var contexte

    var body: some View {
        EmptyView()
    }
}
