import Foundation

/// Lot 4 (blueprint `docs/mobile-swift/LOT4_PLAN.md` §2.2, décision D1) : seul point d'assignation des treize ports du
/// lot 4 du monde démo, appelé une fois par `DemoWorld.gateways(drapeaux:)` après l'init du lot 1 (aucun troisième init).
/// Une fabrique par domaine, chacune dans son fichier (`Demo/Lot4/Demo<Domaine>Gateway.swift`) : les onze tranches
/// parallèles ne modifient jamais ce fichier, seulement le leur.
enum DemoLot4 {
    static func cabler(_ gateways: inout Gateways) {
        gateways.swipe = swipe()
        gateways.filtres = filtres()
        gateways.disponibilites = disponibilites()
        gateways.parrainage = parrainage()
        gateways.litiges = litiges()
        gateways.reclamations = reclamations()
        gateways.messagerie = messagerie()
        gateways.realtime = realtime()
        gateways.bulletins = bulletins()
        gateways.evaluationsRecues = evaluationsRecues()
        gateways.poolUrgence = poolUrgence()
        gateways.score = score()
        gateways.exclusions = exclusions()
    }
}
