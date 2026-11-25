import Foundation

/// Capture mémorisée par appareil et marqueur « appliqué » par compte (L4-T6), port de `src/hooks/useAppliquerParrainage.ts`
/// et de `src/lib/attribution.ts` :
/// - la capture `{code, captureLe}` est unique sur l'appareil (le web : `sessionStorage` et l'attribution
///   `localStorage`) : un même code reçu de nouveau garde sa date (la fenêtre n'est jamais prolongée) ; un autre code
///   remplace la capture (le web : `InscriptionSoignant.tsx` l.113-115 réécrit le code de la page d'inscription, lu en
///   premier, l.36-37) ;
/// - le marqueur `jolene.parrainage_appliqué:<userId>` vaut le code traité (l.60-61, l.83) : jamais rejoué pour ce
///   compte ; marquer retire la capture seulement si elle porte ce code (« ne pas retirer un autre code reçu pendant
///   l'appel », l.84-87) ;
/// - un code relu du stockage repasse par la forme du web avant tout envoi ; une capture illisible ou expirée est
///   ignorée (et la capture expirée effacée).
public struct ParrainageStockage: Sendable {
    public static let cleCapture = "jolene.parrainage.capture"
    public static func cleMarqueur(_ userId: String) -> String { "jolene.parrainage_appliqué:\(userId)" }

    private let stockage: StockageAppareilPort

    public init(_ stockage: StockageAppareilPort) {
        self.stockage = stockage
    }

    public func capture() -> ParrainageCapture.Capture? {
        guard let texte = stockage.lire(Self.cleCapture), let data = texte.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ParrainageCapture.Capture.self, from: data)
    }

    /// Mémorise un code déjà normalisé par `ParrainageCapture`.
    public func capturer(_ code: String, le date: Date) {
        if capture()?.code == code { return }
        ecrire(ParrainageCapture.Capture(code: code, captureLe: date))
    }

    /// Code à appliquer pour `userId` à `maintenant`, ou `nil` (aucune capture, hors fenêtre, hors forme, déjà traité).
    public func codeAAppliquer(userId: String, maintenant: Date) -> String? {
        guard let capture = capture() else { return nil }
        guard ParrainageCapture.estApplicable(capture, maintenant: maintenant) else {
            if capture.captureLe <= maintenant { stockage.ecrire(Self.cleCapture, nil) }
            return nil
        }
        guard let code = ParrainageCapture.normaliser(capture.code), code == capture.code else { return nil }
        guard stockage.lire(Self.cleMarqueur(userId)) != code else { return nil }
        return code
    }

    public func marquer(userId: String, code: String) {
        stockage.ecrire(Self.cleMarqueur(userId), code)
        if capture()?.code == code { stockage.ecrire(Self.cleCapture, nil) }
    }

    private func ecrire(_ capture: ParrainageCapture.Capture) {
        guard let data = try? JSONEncoder().encode(capture) else { return }
        stockage.ecrire(Self.cleCapture, String(data: data, encoding: .utf8))
    }
}

/// Avis affiché après une application (toasts du web, `useAppliquerParrainage.ts` l.74 et l.89). Le message serveur de
/// succès de `fn_appliquer_parrainage` (promesse de prime contradictoire, HARD STOP n°4) n'est jamais affiché ; les
/// refus définitifs sont silencieux, comme le web.
public enum AvisParrainage: Equatable, Sendable {
    case enregistre
    case nonEnregistre

    public var texte: String {
        switch self {
        case .enregistre: return "Code de parrainage enregistré."                                            // l.89
        case .nonEnregistre: return "Le parrainage n’a pas pu être enregistré. Nous réessaierons à votre prochaine connexion." // l.74
        }
    }
}

/// Durée d'affichage de l'avis du parrainage : 8 s (`AvisParrainageVue`, toast du web), surchargeable en démonstration
/// et en build DEBUG seulement, sur le modèle de `ReglagesSwipe.dureeAnnulation`. Run 45446351274 (iPad paysage) : le
/// premier relevé de l'avis par XCUITest a eu lieu 14,7 s après le toucher de « Se connecter » (deux lectures de la barre
/// d'onglets de 3 à 6 s chacune), l'avis était déjà retiré.
public enum DureeAvisParrainage {
    public static let standard: TimeInterval = 8
    public static let variable = "JOLENE_DEMO_PARRAINAGE_AVIS"
    /// Borne haute de la surcharge (secondes).
    public static let maximale: TimeInterval = 600

    /// Durée pour ce lancement : la surcharge n'est lue qu'en démonstration **et** en build DEBUG, pour une valeur entière
    /// de secondes entre 1 et `maximale` ; toute autre valeur garde les 8 s.
    public static func duree(demo: Bool, debug: Bool, environnement: [String: String]) -> TimeInterval {
        guard demo, debug, let brut = environnement[variable], let secondes = Int(brut),
              secondes >= 1, TimeInterval(secondes) <= maximale else { return standard }
        return TimeInterval(secondes)
    }
}

/// Application d'un code capturé au premier `.ready` qui suit (D14), une seule fois par compte et code.
public enum ParrainageApplication {
    /// Refus définitifs de `fn_appliquer_parrainage` (`REFUS_DEFINITIFS`, `useAppliquerParrainage.ts` l.20-25) : le
    /// marqueur est posé, le code n'est jamais rejoué.
    public static let refusDefinitifs: Set<String> = [
        "Code de parrainage invalide",
        "Vous ne pouvez pas vous parrainer vous-même",
        "Le parrain a atteint la limite de 20 filleuls validés",
        "Vous avez déjà appliqué un code de parrainage",
    ]

    /// Applique la capture encore applicable pour `userId` par `appel` (port `parrainage`, borné par l'appelant).
    /// Succès ou refus définitif : marqueur posé. Refus non définitif ou erreur : code conservé, avis `nonEnregistre`.
    /// Annulation : rien (ni avis, ni marqueur). Sans capture applicable : aucun appel.
    public static func appliquer(stockage: ParrainageStockage, userId: String, maintenant: Date,
                                 appel: @Sendable (String) async throws -> ApplicationParrainage) async -> AvisParrainage? {
        guard let code = stockage.codeAAppliquer(userId: userId, maintenant: maintenant) else { return nil }
        let issue: ApplicationParrainage
        do {
            issue = try await appel(code)
        } catch {
            if error is CancellationError || (error as? JoleneError)?.kind == .cancelled || Task.isCancelled { return nil }
            return .nonEnregistre
        }
        switch issue {
        case .appliquee:
            stockage.marquer(userId: userId, code: code)
            return .enregistre
        case .refusDefinitif:
            stockage.marquer(userId: userId, code: code)
            return nil
        case .aReessayer:
            return .nonEnregistre
        }
    }
}
