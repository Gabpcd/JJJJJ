import Foundation
import Combine

// Drapeaux d'écran de l'espace établissement (lot 5, T2a ; `docs/mobile-swift/LOT5_PLAN.md` §2.8, D14) :
// arrêt d'urgence par écran, sept lignes `parametres_systeme` `ios_natif_etab_<ecran>_actif` posées par
// la migration D-FLAGS (`supabase/migrations/20261102204450_drapeaux_ios_natif_lots_2_4_5.sql`, #1111,
// catégorie OPERATIONS, sans GRANT `anon`). Lus avec la session (`fn_param_bool` via `FlagsPort`), après
// `.readyEtablissement` et à chaque reprise, AVANT que l'espace ne s'affiche ; défaut fail-open
// (`FlagsPolicy.defautFailOpen`). Enum additive : `EcranNatif` du lot 1 reste inchangée.

/// Écrans natifs de l'espace établissement pilotés par un drapeau (D14 : `pointage` est le
/// coupe-circuit du polling 5 s sur une base à CPU partagé).
public enum EcranNatifEtablissement: String, CaseIterable, Sendable {
    case accueil, missions, publier, presences, pointage, messages, compte

    /// Clé `parametres_systeme.cle`.
    public var cle: String { "ios_natif_etab_\(rawValue)_actif" }

    /// Libellé de l'écran (onglets `EtablissementTabView`, D13).
    public var titre: String {
        switch self {
        case .accueil: return "Accueil"
        case .missions: return "Missions"
        case .publier: return "Publier une mission"
        case .presences: return "Présences"
        case .pointage: return "Pointage"
        case .messages: return "Messages"
        case .compte: return "Compte"
        }
    }

    /// Permission exigée pour ouvrir l'écran (§2.7, fail-closed ; le serveur reste l'autorité). Le
    /// compte n'en exige aucune : déconnexion et suppression du compte restent toujours atteignables.
    public var permissionRequise: PermissionEtab? {
        switch self {
        case .accueil, .missions, .presences, .messages: return .lecture
        case .publier: return .missions
        case .pointage: return .pointage
        case .compte: return nil
        }
    }

    /// Route web équivalente (`src/App.tsx` l.349-376), présentée hors lien universel quand l'écran est coupé.
    public var cheminWeb: String {
        switch self {
        case .accueil: return "/etablissement/tableau-de-bord"
        case .missions: return "/etablissement/missions"
        case .publier: return "/etablissement/missions/creer"
        case .presences, .pointage: return "/etablissement/presences"
        case .messages: return "/etablissement/messagerie"
        case .compte: return "/etablissement/mon-compte"
        }
    }

    /// URL canonique du renvoi (`https://jolene.app<chemin>`).
    public var urlWeb: URL {
        // Littéral constant et valide : la construction ne peut pas échouer.
        URL(string: "https://jolene.app\(cheminWeb)")!
    }
}

public extension FlagsPort {
    /// Drapeau d'un écran établissement, défaut fail-open (`FlagsPolicy.defautFailOpen`).
    func ecranEtablissementActif(_ ecran: EcranNatifEtablissement) async -> Bool {
        await ecranActif(cle: ecran.cle, defaut: FlagsPolicy.defautFailOpen)
    }
}

/// État des sept drapeaux pour l'interface, propre à un epoch : une valeur lue pour une autre identité ne
/// s'applique jamais (fail-open). `SessionStore` charge les valeurs avant de publier `.readyEtablissement`.
@MainActor
public final class EcransEtablissementModel: ObservableObject {
    @Published public private(set) var actifs: [EcranNatifEtablissement: Bool] = [:]
    /// Epoch de la dernière lecture appliquée, nil avant toute lecture.
    @Published public private(set) var epochCharge: Int?
    private var generation = 0

    public init() {}

    public func estActif(_ ecran: EcranNatifEtablissement, epoch: Int) -> Bool {
        guard epochCharge == epoch else { return FlagsPolicy.defautFailOpen }
        return actifs[ecran] ?? FlagsPolicy.defautFailOpen
    }

    /// Lit les sept drapeaux pour l'epoch de `snapshot` (en parallèle, chacun borné à `delai`, par
    /// défaut `resolutionTimeout` : délai dépassé → actif). Aucun appel pour un epoch périmé ; une réponse
    /// arrivée après un changement d'identité, ou supplantée par une lecture plus récente, est ignorée.
    public func charger(snapshot: EtablissementSessionSnapshot, controller: SessionController, delai: TimeInterval? = nil) async {
        guard let gateways = await controller.gateways(for: snapshot.epoch) else { return }
        generation += 1
        let lecture = generation
        let flags = gateways.flags
        let borne = delai ?? controller.resolutionTimeout
        let valeurs = await withTaskGroup(of: (EcranNatifEtablissement, Bool).self,
                                          returning: [EcranNatifEtablissement: Bool].self) { groupe in
            for ecran in EcranNatifEtablissement.allCases {
                groupe.addTask {
                    let actif = (try? await bounded(timeout: borne) { await flags.ecranEtablissementActif(ecran) }) ?? FlagsPolicy.defautFailOpen
                    return (ecran, actif)
                }
            }
            var lues: [EcranNatifEtablissement: Bool] = [:]
            for await (ecran, actif) in groupe { lues[ecran] = actif }
            return lues
        }
        guard lecture == generation, await controller.epoch == snapshot.epoch else { return }
        actifs = valeurs
        epochCharge = snapshot.epoch
    }
}
