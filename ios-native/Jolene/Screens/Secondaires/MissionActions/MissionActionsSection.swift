import SwiftUI
import JoleneCore

/// Actions du lot 4 sur le détail d'une mission (L4-T1c, correction 20 et D25 de `LOT4_PLAN.md`), insérées une fois
/// dans `MissionDetailScreen` après les actions du lot 1 : « Écrire à l'établissement » (fil de la mission,
/// `DetailMissionSoignant.tsx` l.1550-1558, T7b), « Signaler » et « Ne plus travailler ensemble »
/// (`DetailMissionSoignant.tsx` l.1174-1182, T7b et T11). Chaque bouton est un stub dans son propre fichier, remplacé
/// par sa tranche (statuts, textes verbatim, cible `mission.etablissement_id`) ; tant qu'aucune n'a livré, la section
/// ne rend rien et le détail reste celui d'avant le lot 4. Contexte des écrans secondaires : `contexteSecondaire`.
struct MissionActionsSection: View {
    let mission: Mission

    var body: some View {
        MissionContactButton(mission: mission)
        MissionSignalerButton(mission: mission)
        MissionExclusionButton(mission: mission)
    }
}
