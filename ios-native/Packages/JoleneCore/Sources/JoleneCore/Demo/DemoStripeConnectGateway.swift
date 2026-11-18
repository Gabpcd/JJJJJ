import Foundation

/// `StripeConnectPort` du monde démo (lot 3, T14a, B9), sans réseau ni Stripe. Profil fictif `MIXTE` hors compte de test
/// (comme `demo-revenus.json`), statut `NON_DEMANDE` par défaut ; variantes DEBUG `-JOLENE_DEMO_STRIPE <variante>`
/// (`Scenario`, blueprint §2.7) : l'un des six statuts, `TEST` (compte de test) ou `SALARIE`.
///
/// Serveur simulé : `lienOnboarding` rend une URL hébergée fictive et marque l'onboarding parcouru ; la lecture suivante
/// **forcée** (`force=true`, retour du flux) rend `COMPLET`, une lecture non forcée rend toujours le statut d'avant (cache
/// serveur de 5 min de `stripe-connect-status`) : l'écran ne montre le compte connecté que s'il relit avec `force=true`.
/// Refuse tout contexte qui n'est pas celui du profil fictif (`.demoOnly`).
public actor DemoStripeConnectGateway: StripeConnectPort {
    public enum Scenario: String, Sendable, CaseIterable {
        case nonDemande = "NON_DEMANDE"
        case enCours = "EN_COURS"
        case complet = "COMPLET"
        case suspendu = "SUSPENDU"
        case rejete = "REJETE"
        case supprime = "SUPPRIME"
        case compteTest = "TEST"
        case salarie = "SALARIE"

        /// `-JOLENE_DEMO_STRIPE <variante>` ; absent ou inconnu → `NON_DEMANDE`.
        public init(arguments: [String]) {
            guard let index = arguments.firstIndex(of: DemoStripeConnectGateway.argument), index + 1 < arguments.count,
                  let scenario = Scenario(rawValue: arguments[index + 1]) else {
                self = .nonDemande
                return
            }
            self = scenario
        }
    }

    public static let argument = "-JOLENE_DEMO_STRIPE"
    /// URL hébergée fictive (jamais ouverte en démo : `DemoExternalFlow` rend aussitôt le retour).
    public static let lienDemo = URL(string: "https://connect.stripe.com/setup/e/demo")!
    /// Refus de l'edge pour un non-libéral (`stripe-connect-onboard/index.ts` l.123-124).
    static let refusNonLiberal = "Stripe Connect est réservé aux soignants en exercice libéral ou mixte"

    private let scenario: Scenario
    private var parcouru = false
    /// Lectures du statut reçues, avec leur `force` (tests).
    public private(set) var lectures: [Bool] = []
    public private(set) var liensDemandes = 0

    public init(scenario: Scenario = .nonDemande) {
        self.scenario = scenario
    }

    public func exercice(context: MissionReadContext) async throws -> ExerciceConnect {
        try DemoRevenusGateway.verifier(context)
        switch scenario {
        case .salarie: return ExerciceConnect(typeExercice: "SALARIE", estCompteTest: false)
        case .compteTest: return ExerciceConnect(typeExercice: "MIXTE", estCompteTest: true)
        default: return ExerciceConnect(typeExercice: "MIXTE", estCompteTest: false)
        }
    }

    public func statut(force: Bool, context: MissionReadContext) async throws -> StatutConnect {
        try DemoRevenusGateway.verifier(context)
        lectures.append(force)
        if parcouru, force { return Self.statut(.complet) }
        switch scenario {
        case .nonDemande, .compteTest, .salarie: return Self.statut(.nonDemande)
        case .enCours: return Self.statut(.enCours)
        case .complet: return Self.statut(.complet)
        case .suspendu: return Self.statut(.suspendu)
        case .rejete: return Self.statut(.rejete)
        case .supprime: return Self.statut(.supprime)
        }
    }

    public func lienOnboarding(context: MissionReadContext) async throws -> ResultatLienConnect {
        try DemoRevenusGateway.verifier(context)
        liensDemandes += 1
        switch scenario {
        case .compteTest: return .compteTest
        case .salarie: return .nonEligible(message: Self.refusNonLiberal)
        default:
            parcouru = true
            return .lien(Self.lienDemo)
        }
    }

    /// Corps que rendrait `stripe-connect-status`, lu par la même règle que le monde Supabase (`StatutConnect.lire`).
    static func statut(_ statut: StatutOnboardingConnect) -> StatutConnect {
        let complet = statut == .complet
        return StatutConnect.lire(statut: statut.rawValue, onboardingComplete: complet, chargesEnabled: complet,
                                  payoutsEnabled: complet, ibanLast4: complet ? "0189" : nil,
                                  disabledReason: statut == .rejete ? "rejected.other" : nil)!
    }
}

/// Flux hébergé du monde démo : aucune feuille ni réseau ; rend aussitôt le retour de `return_url`
/// (`https://jolene.app/soignant/stripe-connect?success=true`), que l'écran traite comme toute issue : relecture forcée.
public struct DemoExternalFlow: ExternalFlowPort {
    public init() {}

    public func ouvrir(url: URL, retour: RetourAttendu) async -> IssueFlux {
        var composants = URLComponents()
        composants.scheme = "https"
        composants.host = retour.hote
        composants.path = retour.chemin
        composants.queryItems = [URLQueryItem(name: "success", value: "true")]
        return composants.url.map(IssueFlux.retour) ?? .ferme
    }
}
