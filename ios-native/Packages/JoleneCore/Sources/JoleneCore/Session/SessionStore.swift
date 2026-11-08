import Foundation
import Combine

/// Façade `ObservableObject` du contrôleur de session pour SwiftUI. Chaque
/// opération délègue à l'acteur puis publie l'état renvoyé sur le main actor.
///
/// Lot 3, T4 (blueprint `LOT3_PLAN.md` §2.5, correction 11, D2-D3) — crochets du coordinateur push,
/// optionnel (nil : comportement du lot 1 inchangé), tous posés sur la **publication** de `state`
/// (`didSet`), quel que soit le chemin (lancement, connexion, revalidation, événement du SDK) :
/// - `.ready` d'un **nouvel** epoch → `push.surReady` (tâche non attendue, `pushEnCours`, lancée après la
///   fin de session précédente) ; une revalidation du même epoch ne relance rien (le retour au premier plan
///   relève de `surActive`, appelé par l'app) ;
/// - `signOut` → `push.avantDeconnexion` (désactivation du token, JWT encore valide, bornée à 2,5 s,
///   puis désinscription locale) AVANT `controller.signOut()`, qui avance l'epoch avant le réseau ; un
///   second appel pendant la déconnexion est ignoré (`deconnexionEnCours`) ;
/// - `.signedOut` qui porte une absence de session **confirmée par le contrôleur** (revue B8 : restauration
///   sans session, `.signedOut` du SDK avec une identité active ; `SessionController.Publication`), hors
///   déconnexion voulue :
///   - après une identité (`.ready` ou `.blocked`) → `push.surDeconnexionSubie` (désinscription locale seule,
///     sans RPC : JWT absent), lancée APRÈS la publication (`finDeSessionPush`) : l'écran de connexion
///     n'attend pas la désinscription ;
///   - sans identité (lancement à froid, « Réessayer » qui ne trouve plus de session) →
///     `push.surSessionAbsente` (oubli d'un token laissé par une session précédente) ;
/// - tout autre `.signedOut` (restauration, rôle ou profil en échec transitoire : le SDK peut encore détenir
///   la session ; connexion refusée ; au merge de L1-T9, verrou biométrique) → rien : token conservé,
///   identité suivie inchangée. La cause n'est jamais déduite du texte du message ni de `canRetryRestore` ;
/// - suppression de compte (`signOutLocally`) → `push.surDeconnexionSubie` avant la purge, sans RPC.
///
/// D3 (audit `DECONNEXION` de L1-T9 lancé EN PARALLÈLE de la désactivation, `async let`) : L1-T9 n'est
/// pas sur cette base ; écart et résolution du merge consignés dans `DECISIONS_LOT3.md` (D3) et
/// `REVUES_LOT3.md` (section L3-T4) — jamais les deux appels en série.
///
/// Lot 3, T3b (revue fraîche B8, M1) — port du navigateur intégré `FinIdentiteWebPort`, optionnel (nil :
/// comportement inchangé), indépendant du push : `identiteTerminee()` une fois par fin d'identité
/// (`signOut` après la révocation, `signOutLocally` après la purge, absence de session confirmée après une
/// identité), avant chaque `signIn`, jamais sur une fin transitoire ni au lancement à froid sans session.
@MainActor
public final class SessionStore: ObservableObject {
    @Published public private(set) var state: SessionState {
        didSet { suivreIdentite(depuis: oldValue) }
    }
    /// Vrai quand la dernière restauration a échoué de façon transitoire : l'écran de
    /// connexion propose « Réessayer » (`start()`), sans redemander le mot de passe.
    @Published public private(set) var canRetryRestore = false
    /// Lot 3, T4 : vrai pendant `signOut()` (désactivation du token jusqu'à 2,5 s, puis révocation) ; un
    /// second appel est ignoré et l'écran bloqué montre l'attente sur « Se déconnecter ».
    @Published public private(set) var deconnexionEnCours = false
    public let controller: SessionController
    /// Lot 3, T4 : coordinateur push (nil sans push, doubles de test du lot 1).
    public let push: PushCoordinator?
    /// Lot 3, T3b (revue B8, M1) : navigateur intégré à vider à chaque fin d'identité (nil sans renvoi web).
    public let finIdentiteWeb: FinIdentiteWebPort?
    /// Lot 3, T4 : enregistrement push lancé par le dernier `.ready` d'un nouvel epoch (preuves des tests).
    private(set) var pushEnCours: Task<Void, Never>?
    /// Lot 3, T4 : désinscription locale lancée par la dernière fin de session subie (preuves des tests).
    private(set) var finDeSessionPush: Task<Void, Never>?
    /// Événements d'auth traités par `observeAuthEvents` (preuves des tests ; jamais lu par l'app).
    private(set) var evenementsAuthTraites = 0
    private var authEventsTask: Task<Void, Never>?
    /// Lot 3, T4 : fins de session voulues en cours (`signOut`, `signOutLocally`) ; le coordinateur y est
    /// déjà prévenu, une publication de `.signedOut` n'est pas une fin subie.
    private var finsDeSessionVoulues = 0
    /// Lot 3, T4 : une identité (`.ready` ou `.blocked`) a été publiée depuis la dernière fin de session.
    private var identitePubliee = false
    /// Lot 3, T4 : epoch du dernier `.ready` publié depuis la dernière fin de session.
    private var dernierEpochPret: Int?
    /// Lot 3, T4 : absences de session confirmées par le contrôleur déjà vues (`SessionController.Publication`) ;
    /// une même absence publiée deux fois (retour de `start()` et boucle d'événements) n'est traitée qu'une fois.
    private var absencesVues = 0
    /// Lot 3, T4 : vrai seulement pendant la publication (`appliquer`) d'un état qui porte une absence de session
    /// confirmée encore jamais vue ; lu par `suivreIdentite`. Toute autre affectation de `state` le trouve faux.
    private var publicationConfirmeAbsence = false

    public init(controller: SessionController, push: PushCoordinator? = nil, finIdentiteWeb: FinIdentiteWebPort? = nil) {
        self.controller = controller
        self.push = push
        self.finIdentiteWeb = finIdentiteWeb
        self.state = .idle
    }

    /// Démarre ou revalide la session. Une session déjà prête n'est pas démontée pendant
    /// la vérification (pas de `.loading` intermédiaire : reprise après 30 minutes).
    public func start() async {
        if !state.isReady { state = .loading }
        appliquer(await controller.startPublication())
        canRetryRestore = await controller.canRetryRestore
    }

    public func signIn(email: String, password: String) async {
        // Lot 3, T3b (revue B8, M1) : l'identité qui s'ouvre ne trouve jamais les données web d'une autre (identité
        // close hors de l'app, session web ouverte sans identité native, identité remplacée après une fin transitoire).
        finIdentiteWeb?.identiteTerminee()
        state = .loading
        canRetryRestore = false
        state = await controller.signIn(email: email, password: password)
    }

    public func signOut() async {
        guard !deconnexionEnCours else { return }
        deconnexionEnCours = true
        finsDeSessionVoulues += 1
        defer {
            finsDeSessionVoulues -= 1
            deconnexionEnCours = false
        }
        canRetryRestore = false
        // Lot 3, T4 : le token de cet appareil est désactivé tant que le JWT est valide (correction 11).
        // D3 : au merge de L1-T9, l'audit DECONNEXION part en parallèle (`async let`), jamais en série
        // (`REVUES_LOT3.md`, section L3-T4).
        await desactiverPushAvantDeconnexion()
        state = await controller.signOut()
        // Lot 3, T3b (revue B8, M1) : l'identité est close ; le renvoi web ne la sert plus.
        finIdentiteWeb?.identiteTerminee()
    }

    /// Lot 3, T4 : fin de session locale après la suppression du compte (lot 1, T8, `LocalSignOut`) —
    /// désinscription push locale (aucune RPC : l'edge `delete-account` a révoqué le JWT), puis
    /// `controller.signOutLocally()` et relecture de l'état (comportement du lot 1 inchangé).
    public func signOutLocally() async {
        finsDeSessionVoulues += 1
        defer { finsDeSessionVoulues -= 1 }
        canRetryRestore = false
        if let push {
            let epoch = await epochDeLIdentiteOuverte()
            await push.surDeconnexionSubie(epoch: epoch)
        }
        _ = await controller.signOutLocally()
        await refresh()
        finIdentiteWeb?.identiteTerminee() // lot 3, T3b (revue B8, M1)
    }

    /// Relit l'état courant de l'acteur sans déclencher d'opération.
    public func refresh() async {
        appliquer(await controller.publication)
        canRetryRestore = await controller.canRetryRestore
    }

    /// Relie le flux `AuthPort.authEvents()` au contrôleur : une session effacée par le SDK
    /// (révocation, déconnexion globale, refresh refusé) bascule l'écran sans action de
    /// l'utilisateur. Idempotent ; le flux vide des ports démo se termine aussitôt.
    public func observeAuthEvents() {
        guard authEventsTask == nil else { return }
        let controller = self.controller
        authEventsTask = Task { [weak self] in
            for await event in controller.authEvents() {
                let publication = await controller.handleAuthEventPublication(event)
                guard let self else { return }
                self.appliquer(publication)
                self.canRetryRestore = await controller.canRetryRestore
                self.evenementsAuthTraites += 1
            }
        }
    }

    /// Vrai tant que l'observation des événements d'auth est active.
    public var isObservingAuthEvents: Bool { authEventsTask != nil }

    // MARK: - Lot 3, T4 (push)

    /// Publie l'état rendu par le contrôleur avec la cause qu'il porte : `publicationConfirmeAbsence` n'est vrai
    /// que pendant l'affectation de `state` (donc pendant `suivreIdentite`), et seulement pour une absence de
    /// session confirmée encore jamais vue.
    private func appliquer(_ publication: SessionController.Publication) {
        publicationConfirmeAbsence = publication.absencesConfirmees > absencesVues
        absencesVues = max(absencesVues, publication.absencesConfirmees)
        defer { publicationConfirmeAbsence = false }
        state = publication.state
    }

    /// Suit chaque publication de `state` (voir l'en-tête) : ouverture d'un espace, fin de session subie
    /// confirmée, lancement sans session confirmé. L'identité est suivie avec ou sans coordinateur push (le port du
    /// navigateur intégré en dépend aussi, T3b) ; les appels au push n'ont lieu qu'avec lui, comme avant.
    private func suivreIdentite(depuis ancien: SessionState) {
        switch state {
        case let .ready(snapshot):
            identitePubliee = true
            dernierEpochPret = snapshot.epoch
            guard let push, snapshot.epoch != ancien.snapshot?.epoch else { return }
            // Après la fin de session précédente : sa désinscription ne suit jamais le nouvel enregistrement.
            let finPrecedente = finDeSessionPush
            pushEnCours = Task {
                await finPrecedente?.value
                await push.surReady(snapshot)
            }
        case .blocked:
            identitePubliee = true
        case .signedOut:
            if finsDeSessionVoulues > 0 {
                // `signOut` / `signOutLocally` : le coordinateur est déjà prévenu, l'identité est partie.
                oublierIdentiteSuivie()
                return
            }
            // Échec transitoire, connexion refusée, (L1-T9) verrou biométrique : le SDK peut encore détenir la
            // session ; rien n'est désinscrit ni oublié, l'identité suivie reste celle d'avant.
            guard publicationConfirmeAbsence else { return }
            let identitePerdue = identitePubliee
            let epochPerdu = dernierEpochPret
            oublierIdentiteSuivie()
            if identitePerdue {
                // Lot 3, T3b (revue B8, M1) : fin d'identité subie, le renvoi web ne la sert plus.
                finIdentiteWeb?.identiteTerminee()
                // Session effacée par le SDK ou absente à la restauration : JWT absent, désinscription seule.
                if let push { finDeSessionPush = Task { await push.surDeconnexionSubie(epoch: epochPerdu) } }
            } else if let push {
                // Aucune session ni identité ouverte : un token laissé par une session précédente est oublié.
                // (T3b : aucun appel au navigateur intégré — rien d'ouvert dans ce processus, et un renvoi présenté
                // par le lien de lancement, écart n°1, ne doit pas être fermé ; `signIn` vide le magasin avant la
                // connexion suivante.)
                finDeSessionPush = Task { await push.surSessionAbsente() }
            }
        case .idle, .loading:
            break
        }
    }

    private func oublierIdentiteSuivie() {
        identitePubliee = false
        dernierEpochPret = nil
    }

    /// Epoch de l'identité ouverte (espace prêt ou bloqué : JWT présent), nil sans identité.
    private func epochDeLIdentiteOuverte() async -> Int? {
        switch state {
        case let .ready(snapshot): return snapshot.epoch
        case .blocked: return await controller.epoch
        case .idle, .loading, .signedOut: return nil
        }
    }

    private func desactiverPushAvantDeconnexion() async {
        guard let push else { return }
        let epoch = await epochDeLIdentiteOuverte()
        await push.avantDeconnexion(epoch: epoch)
    }
}
