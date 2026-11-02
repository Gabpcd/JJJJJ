import Foundation
import Combine

// Drapeaux d'écran natif (lot 1, T9, décision 15) : arrêt d'urgence par onglet du socle, lignes
// `parametres_systeme` `ios_natif_<ecran>_actif` créées par la PR backend B0 (#1109, migration
// `20261102150000_drapeaux_ios_natif.sql`, catégorie OPERATIONS, sans GRANT `anon`). Lus avec la
// session (`fn_param_bool`), après `.ready` et à chaque reprise, AVANT que l'espace ne s'affiche ;
// défaut fail-open `true` (inverse assumé de `useParamBool.ts`, fail-closed côté web). Un onglet
// coupé affiche l'écran de renvoi web (`RenvoiWebScreen`), jamais l'écran natif.

public extension EcranNatif {
    /// Libellé de l'onglet (`MainTabView`, `src/components/BarreNavigation.tsx` l.33-37).
    var titre: String {
        switch self {
        case .accueil: return "Accueil"
        case .explorer: return "Explorer"
        case .missions: return "Mes missions"
        case .revenus: return "Revenus"
        case .profil: return "Profil"
        }
    }

    /// Route web équivalente (`src/App.tsx`), que `LinkRouter` ramène à ce même onglet.
    var cheminWeb: String {
        switch self {
        case .accueil: return "/soignant/tableau-de-bord"
        case .explorer: return "/soignant/recherche-missions"
        case .missions: return "/soignant/missions"
        case .revenus: return "/soignant/mes-gains"
        case .profil: return "/soignant/profil"
        }
    }

    /// URL canonique du renvoi (`https://jolene.app<chemin>`), présentée hors lien universel.
    var urlWeb: URL {
        // Littéral constant et valide : la construction ne peut pas échouer.
        URL(string: "https://jolene.app\(cheminWeb)")!
    }

    /// Onglet d'une route native (point d'entrée du coordinateur de liens, T10) ; nil pour un détail,
    /// la connexion ou un renvoi web.
    init?(route: JoleneRoute) {
        switch route {
        case .accueil: self = .accueil
        case .explorer: self = .explorer
        case .missions: self = .missions
        case .revenus: self = .revenus
        case .profil: self = .profil
        default: return nil
        }
    }
}

/// État des cinq drapeaux pour l'interface. Tout est actif tant qu'aucune lecture n'a abouti
/// (fail-open) ; `SessionStore` charge les valeurs avant de publier `.ready`.
@MainActor
public final class EcransNatifsModel: ObservableObject {
    @Published public private(set) var actifs: [EcranNatif: Bool] = [:]
    private var generation = 0

    public init() {}

    public func estActif(_ ecran: EcranNatif) -> Bool {
        actifs[ecran] ?? FlagsPolicy.defautFailOpen
    }

    /// Lit les cinq drapeaux pour l'epoch de `snapshot` (en parallèle, chacun borné à
    /// `resolutionTimeout` : délai dépassé → `true`). Aucun appel pour un epoch périmé ; une réponse
    /// arrivée après un changement d'identité, ou supplantée par une lecture plus récente, est ignorée.
    public func charger(snapshot: SessionSnapshot, controller: SessionController) async {
        guard let gateways = await controller.gateways(for: snapshot.epoch) else { return }
        generation += 1
        let lecture = generation
        let flags = gateways.flags
        let delai = controller.resolutionTimeout
        let valeurs = await withTaskGroup(of: (EcranNatif, Bool).self, returning: [EcranNatif: Bool].self) { groupe in
            for ecran in EcranNatif.allCases {
                groupe.addTask {
                    let actif = (try? await bounded(timeout: delai) { await flags.ecranActif(ecran) }) ?? FlagsPolicy.defautFailOpen
                    return (ecran, actif)
                }
            }
            var lues: [EcranNatif: Bool] = [:]
            for await (ecran, actif) in groupe { lues[ecran] = actif }
            return lues
        }
        guard lecture == generation, await controller.epoch == snapshot.epoch else { return }
        actifs = valeurs
    }
}

/// Surcharges de lancement `-JOLENE_FLAG_<cle> true|false` (DEBUG, monde démo seulement : lues par
/// `AppContainer` puis `DemoFlagsGateway`). Une valeur illisible ou absente est ignorée : jamais un
/// écran coupé par erreur de saisie.
public enum DrapeauxLancement {
    public static let prefixe = "-JOLENE_FLAG_"

    public static func surcharges(arguments: [String]) -> [String: Bool] {
        var surcharges: [String: Bool] = [:]
        for (index, argument) in arguments.enumerated() where argument.hasPrefix(prefixe) {
            let cle = String(argument.dropFirst(prefixe.count))
            guard !cle.isEmpty, index + 1 < arguments.count else { continue }
            switch arguments[index + 1].lowercased() {
            case "false", "0", "no": surcharges[cle] = false
            case "true", "1", "yes": surcharges[cle] = true
            default: continue
            }
        }
        return surcharges
    }
}
