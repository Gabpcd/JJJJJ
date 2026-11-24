import Foundation

/// Clôture rétroactive d'un segment ouvert par l'établissement (lot 5, T8 ; `LOT5_PLAN.md` correction 17, D28), règles
/// pures de `cloturerRetroactif` (`src/components/pointage/AffichageCodeRotatifEtab.tsx` l.177-202) :
/// - la saisie est une heure **de Paris** (`instantDepuisSaisieParis`, l.181), quel que soit le fuseau de l'appareil ;
///   une heure que le fuseau refuse rend le message du web (l.196) ;
/// - l'heure proposée est bornée à [début du segment ouvert, maintenant]. **Gap verrouillé (D28)** :
///   `fn_declarer_fin_retroactive` ne refuse pas une heure future (seul `p_heure_fin <= début` est contrôlé, 23514) ;
///   tant que le serveur ne le fait pas (proposition B5b), l'app refuse une heure postérieure à maintenant avant tout
///   envoi. Une heure antérieure au début du segment reste jugée par le serveur, dont le refus est affiché tel quel.
public enum ClotureSegment {
    // source: src/components/pointage/AffichageCodeRotatifEtab.tsx:185 (`p_raison`)
    public static let raison = "Clôture par l'établissement (oubli de scan / sans téléphone)"
    // source: src/components/pointage/AffichageCodeRotatifEtab.tsx:196
    public static let messageHeureInexistante = "Cette heure n’existe pas à Paris en raison du passage à l’heure d’été. Choisissez une autre heure."
    /// Texte natif (non juridique) du verrou D28 (`docs/mobile-swift/DECISIONS_LOT5.md`).
    public static let messageHeureFuture = "L'heure de fin ne peut pas être postérieure à l'heure actuelle."

    /// Intervalle proposé par le sélecteur d'heure.
    public struct Bornes: Equatable, Sendable {
        public var debut: Date
        public var fin: Date

        public init(debut: Date, fin: Date) { self.debut = debut; self.fin = fin }
    }

    public enum Analyse: Equatable, Sendable {
        case heure(Date)
        case refus(String)
    }

    /// [début du segment EFFECTIF ouvert le plus récent, maintenant] — le segment que le serveur ferme
    /// (`ORDER BY debut DESC LIMIT 1`). `nil` sans segment ouvert lisible, ou s'il commence après maintenant.
    public static func bornes(creneaux: [MissionSlot], maintenant: Date) -> Bornes? {
        let debuts = creneaux
            .filter { $0.typeCreneau == "EFFECTIF" && !$0.estPause && ($0.fin ?? "").isEmpty }
            .compactMap { try? DateHeureParis.instantJolene($0.debut) }
        guard let debut = debuts.max(), debut < maintenant else { return nil }
        return Bornes(debut: debut, fin: maintenant)
    }

    /// Heure de fin à envoyer pour une saisie `YYYY-MM-DDTHH:mm` en heure de Paris, ou le refus à afficher.
    public static func analyser(saisie: String, maintenant: Date) -> Analyse {
        guard let heure = try? DateHeureParis.instantDepuisSaisie(saisie) else { return .refus(messageHeureInexistante) }
        guard heure <= maintenant else { return .refus(messageHeureFuture) }
        return .heure(heure)
    }
}
