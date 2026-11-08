import Foundation
import Combine

/// Tap sur une notification push (lot 3, T5 ; blueprint `docs/mobile-swift/LOT3_PLAN.md` §2.5, §3 T5), port
/// du gestionnaire `pushNotificationActionPerformed` de `src/lib/pushNative.ts` (l.160-175) :
/// - seules les clés et valeurs **textuelles** du payload sont lues (`userInfo` d'APNs : `aps` et toute valeur
///   non textuelle ignorés, comme `valeurTexte` côté web ; fiche « Payload `send-push` » de
///   `CONTRATS_RPC_SOIGNANT.md`) ;
/// - chemin web : `PushRouting.path(data:role:)` (port golden de `navigationPathForEvent`, lien explicite
///   d'abord, racine « / » écartée quand un type permet le repli métier, lien externe refusé), le rôle étant
///   lu dans l'instantané de session (le web appelle `fn_get_my_role`, l.40-57) ;
/// - destination : `DestinationLien(link:)` (routes de T3a), jamais la route brute : un écran pas encore livré
///   part vers son renvoi web (`DestinationLien.destination`).
///
/// Journalisation (PRINCIPES §7) : les valeurs du payload portent des identifiants (`mission_id`,
/// `contrat_id`…) et le lien peut porter un jeton ; `description` et le reflet n'exposent que le type
/// d'événement et la liste triée des clés.
public struct PushTapIntent: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible,
                             CustomReflectable {
    /// Clés et valeurs textuelles du payload, telles que reçues.
    public let donnees: [String: String]

    public init(donnees: [String: String]) {
        self.donnees = donnees
    }

    /// `userInfo` d'une notification : seules les paires textuelles sont gardées (`valeurTexte` du web
    /// n'accepte que des chaînes ; `aps` est un dictionnaire, donc ignoré).
    public init(userInfo: [AnyHashable: Any]) {
        var donnees: [String: String] = [:]
        for (cle, valeur) in userInfo {
            guard let cle = cle as? String, let texte = valeur as? String else { continue }
            donnees[cle] = texte
        }
        self.init(donnees: donnees)
    }

    /// Destination du tap pour le rôle de la session (valeur brute de `RoleResult.role`) ; nil si le payload
    /// ne mène nulle part (type inconnu sans lien, lien externe sans type).
    public func destination(role: String?) -> DestinationLien? {
        PushRouting.path(data: donnees, role: role).flatMap(DestinationLien.init(link:))
    }

    // MARK: - Simulation DEBUG

    /// `-JOLENE_SIMULER_PUSH <TYPE>[:<valeur>][:<lien>]` (blueprint §2.7), honoré par `AppContainer` en build
    /// DEBUG et en démo seulement : traité comme un tap à froid. `<valeur>` remplit `mission_id`, ou la clé
    /// nommée sous la forme `cle=valeur` (`CONTRAT_A_SIGNER:contrat_id=c1`) ; `<lien>` est tout le reste (il
    /// peut contenir « : »). Un segment vide est ignoré.
    public static let argumentSimulation = "-JOLENE_SIMULER_PUSH"

    public static func simule(arguments: [String]) -> PushTapIntent? {
        guard let position = arguments.firstIndex(of: argumentSimulation), arguments.indices.contains(position + 1) else {
            return nil
        }
        let parties = arguments[position + 1].split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
            .map(String.init)
        guard let type = parties.first, !type.isEmpty else { return nil }
        var donnees = ["type_evenement": type]
        if parties.count > 1, !parties[1].isEmpty {
            let valeur = parties[1]
            if let egal = valeur.firstIndex(of: "="), egal != valeur.startIndex {
                donnees[String(valeur[..<egal])] = String(valeur[valeur.index(after: egal)...])
            } else {
                donnees["mission_id"] = valeur
            }
        }
        if parties.count > 2, !parties[2].isEmpty {
            donnees["lien"] = parties[2]
        }
        return PushTapIntent(donnees: donnees)
    }

    /// Libellé DEBUG de la route effectivement présentée (`push-tap-cible`, XCUITest de T5) : cas de route et,
    /// pour un renvoi web ou un détail, l'URL canonique ou l'identifiant. Données de démonstration seulement :
    /// jamais journalisé (PRINCIPES §7), exposé par `MainTabView` en build DEBUG **et** en mode démo uniquement
    /// (revue L3-T5, m8 : jamais dans l'arbre d'accessibilité d'un build DEBUG STAGING, identifiants réels).
    public static func libelleDebug(_ route: JoleneRoute) -> String {
        switch route {
        case .safari(let url): return "safari \(url.absoluteString)"
        case .etablissement(let url): return "etablissement \(url.absoluteString)"
        case .missionDetail(let id): return "missionDetail \(id)"
        default: return String(describing: route)
        }
    }

    // MARK: - Description masquée

    public var description: String {
        let type = donnees["type_evenement"].map { "« \($0) »" } ?? "absent"
        return "PushTapIntent(type: \(type), clés: \(donnees.keys.sorted().joined(separator: ", ")))"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror { Mirror(self, children: ["description": description]) }
}

/// Boîte des taps push (lot 3, T5) : point d'extension unique entre le délégué `UNUserNotificationCenter` de
/// l'app et l'espace prêt (`MainTabView`). Elle mémorise le **dernier** tap reçu (le web navigue vers le dernier
/// tap) et le rejoue une fois l'espace ouvert, le rôle étant alors connu (mieux que le web, `pushNative.ts`
/// l.40-57, qui appelle `fn_get_my_role` au tap) :
/// - tap reçu sans espace ouvert (lancement à froid, écran de connexion) : rejoué par le premier espace prêt ;
/// - tap reçu pendant l'espace d'un epoch : lié à cet epoch ; un espace d'un autre epoch (autre identité,
///   reconnexion) l'écarte sans le présenter.
///
/// Écart consigné (revue L3-T5, m12 ; `DECISIONS_LOT3.md`) : un tap reçu sur l'écran de connexion **après** une
/// déconnexion (volontaire ou subie) n'a pas d'espace ouvert ; il est rejoué pour l'identité qui se connecte
/// ensuite, comme le web (redirection après connexion vers le chemin du tap). Aucune donnée n'est exposée : la
/// destination est relue sous la RLS de la nouvelle identité.
///
/// Consommée par l'aiguillage des liens (lot 3 T3b, reliquat L1-T10 : `AiguillageLiens`, `DeepLinkIntent.swift`,
/// exécuté par `DeepLinkCoordinator`) : même règle d'epoch, même destination `DestinationLien` que les liens
/// universels ; entre un lien et un tap en attente, le plus récent l'emporte.
///
/// Premier plan (`willPresent`) : `premiersPlans` avance, le centre de notifications visible se relit.
@MainActor
public final class BoiteTapsPush: ObservableObject {
    /// Avance à chaque tap reçu : l'espace prêt relit la boîte (`prendre(pour:)`).
    @Published public private(set) var tapsRecus = 0
    /// Avance à chaque notification présentée au premier plan.
    @Published public private(set) var premiersPlans = 0

    private struct Attente {
        let tap: PushTapIntent
        /// Epoch de l'espace ouvert à la réception ; nil : reçu sans espace (rejoué par le premier espace prêt).
        let epoch: Int?
    }

    private var attente: Attente?
    private var epochOuvert: Int?

    public init() {}

    /// Vrai si un tap attend d'être présenté (preuve des tests).
    public var aUnTapEnAttente: Bool { attente != nil }

    /// Tap reçu (délégué de notifications, ou simulation DEBUG au lancement) ; remplace un tap non présenté.
    public func recevoir(_ tap: PushTapIntent) {
        attente = Attente(tap: tap, epoch: epochOuvert)
        tapsRecus += 1
    }

    /// Appelé par l'espace prêt (apparition, puis à chaque tap reçu) : ouvre l'espace pour son epoch et rend la
    /// destination du tap en attente, résolue avec le rôle de la session, une seule fois. Un tap lié à un autre
    /// epoch est écarté (nil).
    public func prendre(pour snapshot: SessionSnapshot) -> DestinationLien? {
        epochOuvert = snapshot.epoch
        guard let attente else { return nil }
        self.attente = nil
        if let epoch = attente.epoch, epoch != snapshot.epoch { return nil }
        return attente.tap.destination(role: snapshot.role.role)
    }

    /// Fermeture de l'espace de cet epoch (disparition) ; sans effet si un autre espace s'est déjà ouvert.
    public func fermerEspace(epoch: Int) {
        if epochOuvert == epoch { epochOuvert = nil }
    }

    /// Notification présentée au premier plan (`willPresent`).
    public func signalerPremierPlan() {
        premiersPlans += 1
    }
}
