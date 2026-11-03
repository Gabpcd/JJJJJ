import Foundation

/// Port de `src/lib/session-count.ts` : compteur cumulatif de sessions qui réserve les prompts non
/// urgents (pré-prompt de notification, `DemandePermissionPush.tsx`) à partir de la 2e session.
/// Décision 1 du lot 3 : jamais de prompt au login, pré-prompt à partir du 2e lancement à froid.
public enum PushPolicy {
    /// `estSessionRecurrente` : vrai à partir de la 2e session.
    public static let seuilSessionRecurrente: Double = 2

    /// `lireCompteur` : `parseInt(brut, 10)` ; 0 si la valeur est absente, vide, illisible ou négative.
    /// Le résultat suit `Number` (au-delà de 2^53, la valeur est celle du `Double` le plus proche).
    public static func lireCompteur(_ brut: String?) -> Double {
        guard let brut, !brut.isEmpty else { return 0 }
        let numero = PrimitivesJS.parseInt10(brut)
        return numero.isFinite && numero >= 0 ? numero : 0
    }

    public static func estSessionRecurrente(numero: Double) -> Bool {
        numero >= seuilSessionRecurrente
    }
}

/// Compteur de sessions d'un appareil, port d'`incrementerSession` : `compteurBrut` est la valeur
/// persistée (`jolene_session_count` côté web, UserDefaults côté natif), `dejaCompteeCetteSession`
/// le drapeau de session (`jolene_session_counted`) ; une instance ne compte qu'une fois (drapeau
/// de module du web). Côté natif, une session est un lancement à froid : le drapeau de session
/// part toujours de `false`. Domaine : compteurs dont le successeur reste sous 1e21.
public struct CompteurSessions: Equatable, Sendable {
    public private(set) var compteurBrut: String?
    public private(set) var dejaCompteeCetteSession: Bool
    private var compteCeChargement = false

    public init(compteurBrut: String?, dejaCompteeCetteSession: Bool = false) {
        self.compteurBrut = compteurBrut
        self.dejaCompteeCetteSession = dejaCompteeCetteSession
    }

    /// `getNumeroSession` : numéro de la session courante, sans incrémenter.
    public var numero: Double { PushPolicy.lireCompteur(compteurBrut) }

    public var estRecurrente: Bool { PushPolicy.estSessionRecurrente(numero: numero) }

    /// Incrémente au plus une fois par instance et par session ; renvoie le numéro courant.
    public mutating func incrementer() -> Double {
        guard !compteCeChargement, !dejaCompteeCetteSession else {
            compteCeChargement = true
            return numero
        }
        let suivant = numero + 1
        compteurBrut = PrimitivesJS.texteEntier(suivant)
        dejaCompteeCetteSession = true
        compteCeChargement = true
        return suivant
    }
}
