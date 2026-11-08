import Foundation
import Combine

/// Pré-prompt de notification (lot 3, T5 ; décision 1 du lot 3, `DECISIONS_LOT3.md`), port de
/// `src/components/DemandePermissionPush.tsx` (l.53-126) et de `src/lib/session-count.ts` :
/// - jamais au login ni à la 1re session : seulement à partir de la 2e (`PushPolicy.estSessionRecurrente`) ;
/// - jamais si la marque `push_permission_asked` du web est posée (`accepted`, `denied` ou `later`) : une fois
///   décidé, plus jamais proposé (le web lit la marque avant tout, l.55) ;
/// - autorisation déjà accordée (ou provisoire) → marque `accepted`, rien n'est affiché ; refusée → marque
///   `denied` (iOS ne réaffiche pas la feuille système, l.73-77) ; jamais demandée → affiché 5 s plus tard
///   (l.79) ;
/// - « Activer les notifications » → `PushPermissionPort.demander()` (le seul appel, au tap, D1), puis
///   enregistrement confirmé par `PushCoordinator` (web `demanderPermissionNativePush`, l.214-228 : une
///   autorisation sans enregistrement n'est pas un succès) ; « Plus tard » ou fermeture → marque `later`.
///
/// Persistance par appareil (blueprint §2.6) : compteur de lancements à froid `jolene.sessionCount` et marque
/// `jolene.pushPrePrompt` (UserDefaults dans l'app, mémoire vive en démo et sous `-JOLENE_SESSION_COUNT`).
public enum PrePromptPush {
    /// Clé du compteur de sessions (lancements à froid), valeur brute comme `jolene_session_count` du web.
    public static let cleCompteur = "jolene.sessionCount"
    /// Clé de la marque (`push_permission_asked` du web, `DemandePermissionPush.tsx` l.17).
    public static let cleMarque = "jolene.pushPrePrompt"
    /// Délai avant l'affichage (`window.setTimeout(…, 5000)`, l.79).
    public static let delaiAffichage: TimeInterval = 5

    /// Valeurs de la marque, celles du web (l.70, l.76, l.102, l.124).
    public enum Marque: String, CaseIterable, Sendable {
        case accepted, denied, later
    }

    /// Décision prise au chargement de l'espace prêt.
    public enum Decision: Equatable, Sendable {
        /// Rien à faire (marque déjà posée, 1re session).
        case rien
        /// Poser la marque sans rien afficher (autorisation déjà accordée ou refusée).
        case marquer(Marque)
        /// Afficher le pré-prompt après `delaiAffichage`.
        case proposer
    }

    /// Règle d'affichage (`useEffect`, l.53-93), autorisation lue seulement si la marque et le compteur le
    /// permettent (le web ne lit l'autorisation qu'ensuite).
    public static func decision(marque: String?, numeroSession: Double, autorisation: AutorisationPush) -> Decision {
        guard premiereEtapeOuverte(marque: marque, numeroSession: numeroSession) else { return .rien }
        switch autorisation {
        case .accordee, .provisoire: return .marquer(.accepted)
        case .refusee: return .marquer(.denied)
        case .nonDemandee: return .proposer
        }
    }

    /// Marque absente (toute valeur non vide compte, comme `localStorage.getItem`) et session récurrente.
    public static func premiereEtapeOuverte(marque: String?, numeroSession: Double) -> Bool {
        guard marque?.isEmpty ?? true else { return false }
        return PushPolicy.estSessionRecurrente(numero: numeroSession)
    }

    // MARK: - Textes (verbatim web, HARD STOP n°4 : aucun texte nouveau)

    // Titre, description, avantages, note et boutons : `PermissionCard.Content.pushSoignant` (JoleneDesign),
    // verbatim `DemandePermissionPush.tsx` l.20-28, l.149, l.158, l.164.

    // source: src/components/DemandePermissionPush.tsx:106
    public static let issueActivees = "Alertes push activées !"
    // source: src/components/DemandePermissionPush.tsx:107
    public static let issueNonActivees = "Notifications non activées. Vous pourrez les autoriser dans Réglages."
    // source: src/components/DemandePermissionPush.tsx:119
    public static let issueEchec = "Impossible d'activer les notifications."

    // MARK: - Argument DEBUG

    /// `-JOLENE_SESSION_COUNT <n>` (blueprint §2.7), honoré par `AppContainer` en build DEBUG seulement : numéro
    /// de la session courante, sans incrément ni persistance (compteur et marque en mémoire vive) ; « 1 » garde
    /// les XCUITest d'un appareil réel sans pré-prompt, « 2 » le déclenche.
    public static let argumentNumeroSession = "-JOLENE_SESSION_COUNT"

    public static func numeroSessionForce(arguments: [String]) -> Double? {
        guard let position = arguments.firstIndex(of: argumentNumeroSession), arguments.indices.contains(position + 1) else {
            return nil
        }
        let brut = arguments[position + 1]
        guard !brut.isEmpty, brut.allSatisfy({ ("0"..."9").contains($0) }) else { return nil }
        return PushPolicy.lireCompteur(brut)
    }
}

// MARK: - Stockage par appareil

/// Valeurs textuelles par appareil (UserDefaults dans l'app ; mémoire vive en démo et en test). Jamais de
/// donnée personnelle : compteur de lancements et marque du pré-prompt.
public protocol StockageAppareilPort: Sendable {
    func lire(_ cle: String) -> String?
    func ecrire(_ cle: String, _ valeur: String?)
}

/// Stockage en mémoire vive : rien ne survit au processus (démo, `-JOLENE_SESSION_COUNT`, tests).
public final class MemoireStockageAppareil: StockageAppareilPort, @unchecked Sendable {
    private let lock = NSLock()
    private var valeurs: [String: String]

    public init(_ valeurs: [String: String] = [:]) {
        self.valeurs = valeurs
    }

    public func lire(_ cle: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return valeurs[cle]
    }

    public func ecrire(_ cle: String, _ valeur: String?) {
        lock.lock(); defer { lock.unlock() }
        valeurs[cle] = valeur
    }
}

/// Contexte du pré-prompt pour ce lancement : stockage de l'appareil et numéro de la session courante.
public struct ContextePrePromptPush: Sendable {
    public let stockage: StockageAppareilPort
    public let numeroSession: Double

    public init(stockage: StockageAppareilPort, numeroSession: Double) {
        self.stockage = stockage
        self.numeroSession = numeroSession
    }

    /// Lancement à froid (`incrementerSession`, `session-count.ts` l.40-61) : le compteur de l'appareil avance
    /// d'une unité, une seule fois par processus (l'appelant, `AppContainer`, n'existe qu'une fois).
    public static func lancement(stockage: StockageAppareilPort) -> ContextePrePromptPush {
        var compteur = CompteurSessions(compteurBrut: stockage.lire(PrePromptPush.cleCompteur))
        let numero = compteur.incrementer()
        stockage.ecrire(PrePromptPush.cleCompteur, compteur.compteurBrut)
        return ContextePrePromptPush(stockage: stockage, numeroSession: numero)
    }
}

// MARK: - Modèle

/// Modèle du pré-prompt (surcouche de `MainTabView`, un modèle par espace prêt). `evaluer()` est lancé à
/// l'apparition de l'espace (tâche annulée à sa disparition : aucun affichage pour une identité partie) ;
/// l'issue d'« Activer » est un des trois messages verbatim du web.
@MainActor
public final class PrePromptPushModel: ObservableObject {
    public enum Issue: Equatable, Sendable {
        case activees, nonActivees, echec

        public var message: String {
            switch self {
            case .activees: return PrePromptPush.issueActivees
            case .nonActivees: return PrePromptPush.issueNonActivees
            case .echec: return PrePromptPush.issueEchec
            }
        }

        public var succes: Bool { self == .activees }
    }

    /// Pré-prompt affiché.
    @Published public private(set) var visible = false
    /// Demande système en cours (après « Activer »).
    @Published public private(set) var demandeEnCours = false
    /// Issue de la dernière activation, affichée brièvement (toast du web).
    @Published public private(set) var issue: Issue?

    private let contexte: ContextePrePromptPush?
    private let permission: PushPermissionPort?
    private let push: PushCoordinator?
    private let snapshot: SessionSnapshot
    private let delai: TimeInterval

    /// Sans contexte ni port d'autorisation (environnement refusé), aucun pré-prompt.
    public init(contexte: ContextePrePromptPush?, permission: PushPermissionPort?, push: PushCoordinator?,
                snapshot: SessionSnapshot, delai: TimeInterval = PrePromptPush.delaiAffichage) {
        self.contexte = contexte
        self.permission = permission
        self.push = push
        self.snapshot = snapshot
        self.delai = delai
    }

    /// Lit marque, compteur puis autorisation ; pose la marque ou affiche le pré-prompt après le délai.
    public func evaluer() async {
        guard let contexte, let permission, !visible else { return }
        let stockage = contexte.stockage
        guard PrePromptPush.premiereEtapeOuverte(marque: stockage.lire(PrePromptPush.cleMarque),
                                                 numeroSession: contexte.numeroSession) else { return }
        let autorisation = await permission.etat()
        guard !Task.isCancelled else { return }
        switch PrePromptPush.decision(marque: stockage.lire(PrePromptPush.cleMarque),
                                      numeroSession: contexte.numeroSession, autorisation: autorisation) {
        case .rien:
            return
        case .marquer(let marque):
            stockage.ecrire(PrePromptPush.cleMarque, marque.rawValue)
        case .proposer:
            if delai > 0 {
                do { try await Task.sleep(nanoseconds: UInt64(delai * 1_000_000_000)) } catch { return }
            }
            // La marque a pu être posée entre-temps (Préférences de T6) : relue avant d'afficher.
            guard !Task.isCancelled, stockage.lire(PrePromptPush.cleMarque)?.isEmpty ?? true else { return }
            visible = true
        }
    }

    /// « Activer les notifications » (`handleActiver`, l.95-121) : le pré-prompt se ferme d'abord, puis la
    /// feuille système est demandée ; accordée → enregistrement de cet appareil relu (`enregistrementConfirme`).
    public func activer() async {
        guard visible, !demandeEnCours, let contexte, let permission else { return }
        visible = false
        demandeEnCours = true
        defer { demandeEnCours = false }
        do {
            let accordee = try await permission.demander()
            if accordee {
                guard let push else { throw JoleneError(.unknown, PrePromptPush.issueEchec) }
                await push.surActive(snapshot)
                guard await push.enregistrementConfirme(epoch: snapshot.epoch) else {
                    // Autorisation sans enregistrement : erreur, marque non posée (web l.221-226, l.118-120).
                    throw JoleneError(.unknown, PrePromptPush.issueEchec)
                }
                contexte.stockage.ecrire(PrePromptPush.cleMarque, PrePromptPush.Marque.accepted.rawValue)
                issue = .activees
            } else {
                contexte.stockage.ecrire(PrePromptPush.cleMarque, PrePromptPush.Marque.denied.rawValue)
                issue = .nonActivees
            }
        } catch {
            issue = .echec
        }
    }

    /// « Plus tard » ou fermeture (`handlePlusTard`, l.123-126 ; `onOpenChange(false)`, l.131).
    public func plusTard() {
        guard visible else { return }
        contexte?.stockage.ecrire(PrePromptPush.cleMarque, PrePromptPush.Marque.later.rawValue)
        visible = false
    }

    /// Fin de l'affichage de l'issue (durée du toast, ou geste de l'utilisateur).
    public func effacerIssue() {
        issue = nil
    }
}
