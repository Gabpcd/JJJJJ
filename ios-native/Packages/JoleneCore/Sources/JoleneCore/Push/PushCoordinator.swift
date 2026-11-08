import Foundation
import os

/// Coordinateur push du lot 3, tranche T4 (blueprint `docs/mobile-swift/LOT3_PLAN.md` §2.5 ; D1-D3 ;
/// corrections 11 et 16). Port de `initNativePush` / `enregistrerToken` (`src/lib/pushNative.ts` l.25-38,
/// l.73-207) et de `desactiverPushAppareilCourant` (`src/lib/pushDeviceToken.ts` l.68-124).
///
/// Enregistrement (`surReady` à l'ouverture d'un espace, `surActive` au retour au premier plan) :
/// - seulement si l'appareil l'autorise déjà (`accordee`, `provisoire`) : le coordinateur ne demande
///   **jamais** l'autorisation (D1 ; le pré-prompt de T5 et les préférences de T6 le font au tap) ;
/// - token APNs (`PushRegistrarPort`, borné à `delaiToken`) → hexadécimal minuscule → contrôle d'identité
///   (`controller.gateways(for: epoch)`, web l.25-29) → `fn_upsert_token_push(p_token, 'IOS')` → mémoire ;
/// - idempotent pour un même epoch et un même token ; une rotation est réenregistrée ; un échec reste
///   réessayable au prochain événement, sans renvoi automatique ; best-effort : jamais de déconnexion.
///
/// Déconnexion volontaire (`avantDeconnexion`, appelée par `SessionStore.signOut` AVANT
/// `controller.signOut()`, le JWT étant requis) : `fn_desactiver_mon_token_push(token mémorisé)` bornée à
/// `delaiDesactivation` (2,5 s, D3), puis `unregisterForRemoteNotifications()` et oubli du token, que la RPC
/// ait abouti ou non. Sans token mémorisé ou sans identité, aucune RPC (jamais « tous les tokens du
/// compte », web l.61-67). Déconnexion subie (session effacée par le SDK ou absente à la revalidation)
/// et suppression de compte (`surDeconnexionSubie(epoch:)`) : désinscription locale et oubli seulement.
/// Lancement sans session (`surSessionAbsente`) : un token laissé par une session précédente est oublié
/// après la désinscription locale ; sans token, rien.
///
/// Concurrence : un enregistrement en vol pour le même epoch est rejoint, jamais doublé ; toute
/// déconnexion l'abandonne (génération) et ferme les epochs de l'identité qui part (aucun
/// réenregistrement, même si un retour au premier plan survient pendant la désactivation).
///
/// Journal DEBUG (§2.4 ; T17 distingue non autorisé, APNs muet, 22023 et réseau) : étape et catégorie
/// d'erreur seulement (`motif(_:)`), jamais le token, l'identifiant ni le message. Rien en Release.
public actor PushCoordinator {
    /// Délai de la désactivation et de la désinscription locale (`pushDeviceToken.ts` l.90-92, l.113 : 2 500 ms).
    public static let delaiDesactivation: TimeInterval = 2.5
    /// Délai d'obtention du token APNs (`pushNative.ts` l.178-191 : 15 000 ms).
    public static let delaiToken: TimeInterval = 15
    /// `p_plateforme` envoyé à `fn_upsert_token_push` (web `pushNative.ts` l.31).
    public static let plateforme = "IOS"
    /// Bornes de longueur du token de `fn_upsert_token_push` (l.64644-64645) et `fn_desactiver_mon_token_push`.
    public static let longueursToken: ClosedRange<Int> = 16...4096

    private struct Enregistrement {
        let numero: Int
        let epoch: Int
        let generation: Int
        let tache: Task<Void, Never>
    }

    private let controller: SessionController
    private let permission: PushPermissionPort
    private let registrar: PushRegistrarPort
    private let memoire: PushTokenStorePort
    private let delaiDesactivationEffectif: TimeInterval
    private let delaiTokenEffectif: TimeInterval

    /// Avance à chaque déconnexion : un enregistrement d'une génération passée n'aboutit plus.
    private var generation = 0
    /// Aucun enregistrement pour un epoch inférieur (identités fermées par une déconnexion).
    private var epochMinimal = 0
    /// Dernier token enregistré avec succès, et pour quel epoch.
    private var confirme: (epoch: Int, token: String)?
    private var enCours: Enregistrement?
    private var numeroSuivant = 0
    /// Appels qui ont rejoint un enregistrement en vol (preuve des tests ; jamais lu par l'app).
    private(set) var enregistrementsRejoints = 0

    public init(controller: SessionController, permission: PushPermissionPort, registrar: PushRegistrarPort,
                memoire: PushTokenStorePort, delaiDesactivation: TimeInterval = PushCoordinator.delaiDesactivation,
                delaiToken: TimeInterval = PushCoordinator.delaiToken) {
        self.controller = controller
        self.permission = permission
        self.registrar = registrar
        self.memoire = memoire
        self.delaiDesactivationEffectif = delaiDesactivation
        self.delaiTokenEffectif = delaiToken
    }

    // MARK: - Format

    /// Hexadécimal minuscule sans séparateur (token APNs brut, 32 octets → 64 caractères).
    public static func hex(_ data: Data) -> String {
        let chiffres = Array("0123456789abcdef")
        var texte = ""
        texte.reserveCapacity(data.count * 2)
        for octet in data {
            texte.append(chiffres[Int(octet >> 4)])
            texte.append(chiffres[Int(octet & 0x0f)])
        }
        return texte
    }

    /// Longueur acceptée par la fonction serveur (après `trim`) ; hors bornes, l'appel serait un 22023.
    public static func tokenValide(_ token: String) -> Bool {
        longueursToken.contains(token.trimmingCharacters(in: .whitespacesAndNewlines).count)
    }

    // MARK: - Enregistrement

    /// Ouverture d'un espace (`.ready` d'un nouvel epoch) : lancement à froid, connexion, restauration.
    public func surReady(_ snapshot: SessionSnapshot) async {
        await enregistrer(snapshot)
    }

    /// Retour au premier plan : autorisation relue (elle peut changer dans Réglages), rotation détectée,
    /// enregistrement échoué retenté (web `AuthContext.tsx` l.151-160) ; sans effet si rien n'a changé.
    public func surActive(_ snapshot: SessionSnapshot) async {
        await enregistrer(snapshot)
    }

    /// Vrai si un token a été enregistré avec succès pour cet epoch (web `enregistrementPushConfirme`).
    public func enregistrementConfirme(epoch: Int) -> Bool {
        confirme?.epoch == epoch
    }

    private func enregistrer(_ snapshot: SessionSnapshot) async {
        guard snapshot.epoch >= epochMinimal else { return }
        if let enCours, enCours.epoch == snapshot.epoch, enCours.generation == generation {
            enregistrementsRejoints += 1
            await enCours.tache.value
            return
        }
        numeroSuivant += 1
        let numero = numeroSuivant
        let courante = generation
        let tache = Task { await self.executer(snapshot, generation: courante) }
        enCours = Enregistrement(numero: numero, epoch: snapshot.epoch, generation: courante, tache: tache)
        await tache.value
        if enCours?.numero == numero { enCours = nil }
    }

    private func executer(_ snapshot: SessionSnapshot, generation courante: Int) async {
        let autorisation = await permission.etat()
        guard actif(courante) else { return }
        guard autorisation.permetEnregistrement else {
            // Autorisation retirée dans Réglages : plus rien n'est confirmé (web l.85-86).
            confirme = nil
            Self.journaliser("Enregistrement sans objet : autorisation \(autorisation.rawValue)")
            return
        }
        let registrar = self.registrar
        let brut: Data
        do {
            brut = try await bounded(timeout: delaiTokenEffectif) { try await registrar.enregistrer() }
        } catch {
            Self.journaliser("Token APNs indisponible : \(Self.motif(error))")
            return
        }
        guard actif(courante) else { return }
        let token = Self.hex(brut)
        guard Self.tokenValide(token) else {
            Self.journaliser("Token APNs hors des bornes du serveur (\(token.count) caractères)")
            return
        }
        if let confirme, confirme.epoch == snapshot.epoch, confirme.token == token { return }
        // Identité vérifiée avant l'appel : un epoch périmé n'écrit rien (web l.25-29).
        guard let gateways = await controller.gateways(for: snapshot.epoch), actif(courante) else { return }
        let port = gateways.push
        let context = snapshot.context
        do {
            try await bounded(timeout: controller.resolutionTimeout) {
                try await port.enregistrer(token: token, context: context)
            }
        } catch {
            // Best-effort : rien n'est confirmé, le prochain `.ready` ou premier plan réessaie.
            if confirme?.epoch == snapshot.epoch { confirme = nil }
            Self.journaliser("Enregistrement du token en échec : \(Self.motif(error))")
            return
        }
        guard actif(courante) else { return }
        let epochCourant = await controller.epoch
        // Réentrance : une déconnexion a pu s'exécuter entièrement pendant cette lecture (génération avancée,
        // token oublié) ; la génération est relue après la suspension, sans suspension avant l'écriture.
        guard actif(courante), epochCourant == snapshot.epoch else { return }
        confirme = (snapshot.epoch, token)
        memoire.memoriser(TokenPushMemorise(token: token, userId: snapshot.user.id))
    }

    private func actif(_ courante: Int) -> Bool {
        courante == generation && !Task.isCancelled
    }

    // MARK: - Déconnexion

    /// Déconnexion volontaire : `epoch` est celui de l'identité qui part (espace prêt ou bloqué), `nil`
    /// sans identité (aucun JWT : pas de RPC). À appeler AVANT `controller.signOut()`.
    public func avantDeconnexion(epoch: Int?) async {
        await fermer(epoch: epoch)
        if let epoch, let memorise = memoire.lire(), let gateways = await controller.gateways(for: epoch) {
            let port = gateways.push
            let token = memorise.token
            // Refus `{success:false}`, erreur ou délai dépassé : la désinscription locale a lieu quand même.
            do {
                let issue = try await bounded(timeout: delaiDesactivationEffectif) { try await port.desactiver(token: token) }
                if issue == .nonDesactive { Self.journaliser("Désactivation du token refusée par le serveur") }
            } catch {
                Self.journaliser("Désactivation du token en échec : \(Self.motif(error))")
            }
        }
        await desinscrireLocalement()
    }

    /// Fin de session sans JWT utilisable, aucune RPC : session effacée par le SDK ou absente à la
    /// revalidation — absence confirmée par le contrôleur, jamais un échec transitoire — (`epoch` : celui de
    /// l'identité perdue, connu de l'appelant), suppression du compte
    /// (`epoch` : celui de l'identité qui part, avant la purge). Ferme cet epoch et ceux que le coordinateur
    /// connaît, sans lire l'epoch courant du contrôleur : la fin subie est traitée après la publication de
    /// l'état et une identité suivante, déjà ouverte, ne doit jamais être fermée.
    public func surDeconnexionSubie(epoch perdu: Int?) async {
        abandonner(jusqua: [perdu, enCours?.epoch, confirme?.epoch].compactMap { $0 }.max())
        await desinscrireLocalement()
    }

    /// Absence de session **confirmée** par le contrôleur sans identité ouverte (le SDK n'a rien restauré, ou a
    /// effacé une session jamais ouverte comme espace) : un token mémorisé vient d'une session close hors de
    /// l'app (application tuée pendant la déconnexion, refresh refusé) ; aucun JWT, donc aucune RPC :
    /// désinscription locale puis oubli. Sans token mémorisé, rien (aucun appel système inutile). Jamais
    /// appelé sur un échec transitoire (restauration hors ligne, profil illisible) : le SDK détient encore la
    /// session et l'appareil doit continuer de recevoir les push (`SessionStore`, revue B8).
    public func surSessionAbsente() async {
        guard memoire.lire() != nil else { return }
        Self.journaliser("Token mémorisé sans session : désinscription locale")
        await desinscrireLocalement()
    }

    /// Abandonne l'enregistrement en vol et ferme les epochs ouverts jusqu'ici : d'abord ceux que le
    /// coordinateur connaît (sans suspension), puis l'epoch courant du contrôleur (déconnexion voulue :
    /// l'identité qui part est encore l'identité courante) ; un enregistrement lancé pendant cette lecture
    /// est abandonné à son tour.
    private func fermer(epoch connu: Int?) async {
        abandonner(jusqua: [connu, enCours?.epoch, confirme?.epoch].compactMap { $0 }.max())
        let courant = await controller.epoch
        abandonner(jusqua: courant)
    }

    private func abandonner(jusqua epoch: Int?) {
        generation += 1
        enCours?.tache.cancel()
        enCours = nil
        confirme = nil
        if let epoch { epochMinimal = max(epochMinimal, epoch + 1) }
    }

    /// `unregisterForRemoteNotifications()` (borné comme le web l.113), puis oubli du token.
    private func desinscrireLocalement() async {
        let registrar = self.registrar
        do {
            try await bounded(timeout: delaiDesactivationEffectif) { await registrar.desinscrire() }
        } catch {
            Self.journaliser("Désinscription APNs : \(Self.motif(error))")
        }
        memoire.oublier()
    }

    // MARK: - Journal DEBUG

    /// Catégorie d'une erreur pour le journal : genre de `JoleneError` (« délai dépassé » pour la borne de
    /// `bounded`), annulation, sinon domaine et code (`didFailToRegisterForRemoteNotificationsWithError`).
    /// Jamais le message : il pourrait citer un token ou un texte serveur.
    static func motif(_ erreur: Error) -> String {
        if erreur is CancellationError { return "annulé" }
        if let jolene = erreur as? JoleneError {
            let delai = jolene.kind == .network && jolene.message == SessionController.timeoutMessage
            return delai ? "network (délai dépassé)" : "\(jolene.kind)"
        }
        let ns = erreur as NSError
        return "\(ns.domain) \(ns.code)"
    }

    /// Journal DEBUG (`app.jolene`, catégorie `push`) ; le texte ne contient ni token ni identifiant.
    private static func journaliser(_ texte: String) {
        #if DEBUG
        Logger(subsystem: "app.jolene", category: "push").debug("\(texte, privacy: .public)")
        #endif
    }
}
