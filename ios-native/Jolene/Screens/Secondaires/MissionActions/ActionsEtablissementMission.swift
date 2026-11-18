import SwiftUI
import JoleneCore

/// Actions du lot 4 sur le détail d'une mission (L4-T1c, correction 20 et D25 de `LOT4_PLAN.md`), dans l'ordre du web
/// (revue B8 de #1159, m2) et posées une fois dans `MissionDetailScreen` :
/// - au bas du bloc de l'établissement, cette section : « Ne plus travailler ensemble » (`BoutonExclusion`, T11) puis
///   « Signaler » (`SignalerUtilisateur`, T7b), pour toute mission qui a un établissement, repliés sous « Autres
///   actions » pour une mission ouverte non assignée (`DetailMissionSoignant.tsx` l.1160-1183) ;
/// - après « Annuler ma participation », le fil de discussion (`MissionContactButton`, T7b, l.1550-1558).
/// Chaque bouton est un stub dans son propre fichier, remplacé par sa tranche (statuts, repli, textes verbatim, cible
/// `mission.etablissement_id`) ; tant qu'aucune n'a livré, rien n'est rendu et le détail reste celui d'avant le lot 4.
/// Contexte des écrans secondaires : `contexteSecondaire`.
struct ActionsEtablissementMission: View {
    let mission: Mission

    var body: some View {
        MissionExclusionButton(mission: mission)
        MissionSignalerButton(mission: mission)
    }
}
