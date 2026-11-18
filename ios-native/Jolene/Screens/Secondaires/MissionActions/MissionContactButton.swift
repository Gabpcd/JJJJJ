import SwiftUI
import JoleneCore

/// « Écrire à l'établissement » (`fn_user_id_pour_etablissement` puis `fn_obtenir_conversation`, statuts ASSIGNEE,
/// EN_COURS, TERMINEE, ABSENCE, LITIGE de `DetailMissionSoignant.tsx` l.1550) — **stub de L4-T1c**, remplacé par T7b
/// sans retoucher `MissionDetailScreen` ni `MissionActionsSection`. Ne rend rien tant que la tranche n'a pas livré.
struct MissionContactButton: View {
    let mission: Mission
    @Environment(\.contexteSecondaire) private var contexte

    var body: some View {
        EmptyView()
    }
}
