import Foundation
import Combine

/// Fil d'une conversation (lot 4, T7a ; `LOT4_PLAN.md` §2.5 « Messagerie Realtime »), port du panneau de détail de
/// `src/pages/PageMessagerie.tsx` (l.336-431), de `src/components/messagerie/InputMessage.tsx` et de
/// `src/hooks/useConversationRealtime.ts`. L'écran (T7b) ne lit que ce modèle ; le modèle ne lit que les ports.
///
/// Règles :
/// - `suivre()` : flux du fil (messages, état du canal, saisie, présence) **déclarés d'abord**, puis lecture des 500
///   derniers messages, puis `fn_marquer_messages_lus` ; le suivi dure jusqu'à la fermeture du flux des messages
///   (arrière-plan, changement d'identité) ou l'annulation de l'appelant ; l'écran le relance à chaque
///   `CycleRealtime.generation` ;
/// - fusion par id, ordre `cree_le` : un INSERT Realtime d'un message déjà relu est ignoré ;
/// - message entrant fil ouvert → `marquerLus`, puis badge relu (`CycleRealtime.conversationLue`) ; `42501 Accès
///   refusé` → `accesRefuse`, liste relue, jamais une déconnexion ;
/// - à chaque « rejoint » du canal du fil : relecture depuis le dernier `cree_le` connu (messages manqués entre la
///   lecture et l'abonnement, ou pendant une coupure) ;
/// - battement de présence (`fn_update_presence`) : le premier part après l'abonnement réussi du canal du fil, puis
///   toutes les 30 s tant que le fil est suivi ; aucun en arrière-plan ;
/// - envoi par l'edge seulement, un à la fois (verrou posé avant toute suspension) ; `message_id` → relecture de la
///   ligne par id → affichage (jamais un écho Realtime supposé) ; refus → texte conservé par l'écran ; délai dépassé,
///   coupure ou réponse non confirmée → `envoiNonConfirme` et relecture du fil, **aucun renvoi automatique** ;
/// - indicateur de saisie : `fn_typing_start` au plus toutes les 2 s, `fn_typing_stop` après 3 s d'inactivité, à
///   l'envoi et à la fermeture ; un échec l'abandonne sans message ; celui de l'interlocuteur expire après 6 s ;
/// - lectures et mutations bornées à `SessionController.resolutionTimeout` ; réponse d'un epoch périmé ignorée, flux
///   quittés ; une annulation n'est jamais une erreur.
@MainActor
public final class FilModel: ObservableObject {
    public enum Etat: Equatable, Sendable {
        case chargement
        case pret
        /// Première lecture en échec : message de l'erreur.
        case echec(String)
    }

    /// Refus d'un envoi : `code` machine de l'edge (jamais affiché, traduit par l'écran), `message` serveur ou repli.
    public struct RefusEnvoi: Equatable, Sendable {
        public var code: String?
        public var message: String
        public init(code: String?, message: String) { self.code = code; self.message = message }
    }

    /// Délais du fil, ceux du web par défaut (`HEARTBEAT_INTERVAL_MS`, `TYPING_REFRESH_MS`, `TYPING_IDLE_MS`,
    /// `TYPING_STALE_MS`).
    public struct Delais: Equatable, Sendable {
        public var battement: TimeInterval
        public var rafraichissementSaisie: TimeInterval
        public var inactiviteSaisie: TimeInterval
        public var peremptionSaisie: TimeInterval

        public init(battement: TimeInterval = 30, rafraichissementSaisie: TimeInterval = 2, inactiviteSaisie: TimeInterval = 3,
                    peremptionSaisie: TimeInterval = EtatSaisie.peremption) {
            self.battement = battement; self.rafraichissementSaisie = rafraichissementSaisie
            self.inactiviteSaisie = inactiviteSaisie; self.peremptionSaisie = peremptionSaisie
        }
    }

    @Published public private(set) var etat: Etat = .chargement
    /// Messages du fil, `cree_le` croissant.
    @Published public private(set) var messages: [MessageChat] = []
    @Published public private(set) var envoiEnCours = false
    /// Dernier envoi sans confirmation du serveur : le fil a été relu, rien n'a été renvoyé.
    @Published public private(set) var envoiNonConfirme = false
    /// Type détecté par l'anti-fuite du dernier envoi (feuille éducative de l'écran).
    @Published public private(set) var antiFuite: DetectedType?
    @Published public private(set) var refusEnvoi: RefusEnvoi?
    @Published public private(set) var saisieInterlocuteur = false
    @Published public private(set) var presence: EtatPresence?
    /// Dernier état du canal du fil.
    @Published public private(set) var canal: EtatCanal?
    /// `42501 Accès refusé` de `fn_marquer_messages_lus` : la conversation n'est plus accessible.
    @Published public private(set) var accesRefuse = false
    /// Conversation en lecture seule (`archived_at`, ou `CONVERSATION_ARCHIVEE` de l'edge) : composeur désactivé.
    @Published public private(set) var archivee: Bool
    @Published public private(set) var sessionExpiree = false
    /// Dernière erreur d'une relecture ou d'un envoi refusé avant d'atteindre l'edge, verbatim.
    @Published public private(set) var message: String?

    public let conversationId: String
    /// Interlocuteur (`autre_id`) : saisie et présence suivies pour lui seul ; `nil` : aucune présence suivie.
    public let autreId: String?

    private let controller: SessionController
    private let contexte: ContexteMessagerie
    private let cycle: CycleRealtime?
    private let delais: Delais
    private var filLu = false
    private var rejointAvantLecture = false
    private var suivisActifs = 0
    private var battement: Task<Void, Never>?
    private var peremption: Task<Void, Never>?
    private var inactivite: Task<Void, Never>?
    private var saisieEnCours = false
    private var dernierSignalSaisie: TimeInterval = 0

    public convenience init(controller: SessionController, snapshot: SessionSnapshot, conversationId: String, autreId: String?,
                            archivee: Bool = false, cycle: CycleRealtime? = nil, delais: Delais = Delais()) {
        self.init(controller: controller, contexte: ContexteMessagerie(snapshot), conversationId: conversationId, autreId: autreId,
                  archivee: archivee, cycle: cycle, delais: delais)
    }

    /// Lot 5 (T11) : le même fil en contexte établissement ; `moi` reste l'utilisateur courant.
    public init(controller: SessionController, contexte: ContexteMessagerie, conversationId: String, autreId: String?,
                archivee: Bool = false, cycle: CycleRealtime? = nil, delais: Delais = Delais()) {
        self.controller = controller
        self.contexte = contexte
        self.conversationId = conversationId
        self.autreId = autreId
        self.archivee = archivee
        self.cycle = cycle
        self.delais = delais
    }

    /// Identifiant de l'utilisateur de la session (auteur de ses propres messages), soignant ou membre d'établissement.
    public var moi: String { contexte.moi }

    /// Espace de la session (règles d'affichage du rôle).
    public var estEtablissement: Bool { contexte.estEtablissement }

    // MARK: - Suivi

    public func suivre() async {
        guard let gateways = await controller.gateways(for: contexte.epoch) else { return }
        let realtime = gateways.realtime
        suivisActifs += 1
        cycle?.ouvrirFil(conversationId)
        defer { arreterSuivi() }
        // Flux déclarés avant toute lecture ; la gateway les déclare au canal avant de s'y abonner (exigence du SDK).
        let entrants = realtime.messagesEntrants(conversationId: conversationId)
        let etats = realtime.etat(conversationId: conversationId)
        let saisies = realtime.saisies(conversationId: conversationId)
        let presences = autreId.map { realtime.presence(userId: $0) }
        await withTaskGroup(of: Bool.self) { groupe in
            groupe.addTask { await self.ecouter(entrants); return true }
            groupe.addTask { await self.suivreCanal(etats); return false }
            groupe.addTask { await self.suivreSaisies(saisies); return false }
            if let presences { groupe.addTask { await self.suivrePresence(presences); return false } }
            groupe.addTask { await self.lireFil(depuis: nil, marquer: .toujours); return false }
            while let fluxFerme = await groupe.next() {
                if fluxFerme { groupe.cancelAll() }
            }
        }
    }

    /// « Réessayer » après une lecture en échec : fil relu en entier puis marqué lu.
    public func relire() async {
        await lireFil(depuis: nil, marquer: .toujours)
    }

    private func arreterSuivi() {
        suivisActifs -= 1
        guard suivisActifs == 0 else { return } // un suivi relancé a déjà pris le relais
        battement?.cancel()
        battement = nil
        peremption?.cancel()
        peremption = nil
        inactivite?.cancel()
        inactivite = nil
        saisieInterlocuteur = false
        cycle?.fermerFil(conversationId)
        if saisieEnCours {
            saisieEnCours = false
            Task { await self.signalerSaisie(debut: false) }
        }
    }

    private enum Marquage { case toujours, siNouveauxEntrants, jamais }

    /// Lit le fil (500 derniers, ou depuis `depuis`) et le fusionne par id avec les messages déjà reçus.
    @discardableResult
    private func lireFil(depuis: String?, marquer: Marquage) async -> Bool {
        guard let gateways = await controller.gateways(for: contexte.epoch) else { return false }
        let port = gateways.messagerie
        let contexte = self.contexte
        let id = conversationId
        do {
            let lus = try await bounded(timeout: controller.resolutionTimeout) { () async throws -> [MessageChat] in
                if let depuis { return try await port.messages(conversationId: id, depuis: depuis, contexte: contexte) }
                return try await port.messages(conversationId: id, contexte: contexte)
            }
            guard await courant() else { return false }
            let connus = Set(messages.map(\.id))
            let nouveauxEntrants = lus.contains { !connus.contains($0.id) && FilMessages.estEntrant($0, moi: moi) }
            messages = FilMessages.fusionner(messages, lus, conversationId: id)
            etat = .pret
            message = nil
            filLu = true
            if marquer == .toujours || (marquer == .siNouveauxEntrants && nouveauxEntrants) {
                await marquerLus(signaler: marquer == .toujours)
            }
            if rejointAvantLecture {
                // Le canal a été abonné pendant la lecture : ce qui est arrivé entre les deux est relu.
                rejointAvantLecture = false
                await relireDepuisDernier()
            }
            return true
        } catch {
            guard await courant(), let texte = texte(error) else { return false }
            if etat == .pret { message = texte } else { etat = .echec(texte) }
            return false
        }
    }

    private func relireDepuisDernier() async {
        guard filLu else {
            rejointAvantLecture = true
            return
        }
        await lireFil(depuis: FilMessages.dernierCreeLe(messages), marquer: .siNouveauxEntrants)
    }

    private func marquerLus(signaler: Bool) async {
        guard let gateways = await controller.gateways(for: contexte.epoch) else { return }
        let port = gateways.messagerie
        let contexte = self.contexte
        let id = conversationId
        do {
            let issue = try await bounded(timeout: controller.resolutionTimeout) { try await port.marquerLus(conversationId: id, contexte: contexte) }
            guard await courant() else { return }
            switch issue {
            case .lus:
                await cycle?.conversationLue(id)
            case .accesRefuse:
                accesRefuse = true
                cycle?.listeARelire()
            }
        } catch {
            guard await courant(), let texte = texte(error), signaler else { return }
            message = texte
        }
    }

    // MARK: - Flux Realtime

    private func ecouter(_ entrants: AsyncStream<MessageChat>) async {
        for await recu in entrants {
            guard await courant() else { return }
            // Un message d'un autre fil, ou d'un id déjà relu, est ignoré (ni doublon, ni second marquage).
            guard recu.conversationId == conversationId, !messages.contains(where: { $0.id == recu.id }) else { continue }
            messages = FilMessages.fusionner(messages, [recu], conversationId: conversationId)
            if filLu, FilMessages.estEntrant(recu, moi: moi) { await marquerLus(signaler: false) }
        }
    }

    private func suivreCanal(_ etats: AsyncStream<EtatCanal>) async {
        var dejaRejoint = false
        for await nouvel in etats {
            guard await courant() else { return }
            canal = nouvel
            guard nouvel == .rejoint else { continue }
            if !dejaRejoint {
                dejaRejoint = true
                demarrerBattement()
            }
            await relireDepuisDernier()
        }
    }

    private func suivreSaisies(_ saisies: AsyncStream<EtatSaisie>) async {
        for await saisie in saisies {
            guard await courant() else { return }
            let auteur = saisie.userId.lowercased()
            if let autreId { guard auteur == autreId.lowercased() else { continue } } else if auteur == moi.lowercased() { continue }
            peremption?.cancel()
            peremption = nil
            saisieInterlocuteur = saisie.enTrain
            guard saisie.enTrain else { continue }
            let delai = delais.peremptionSaisie
            peremption = Task { [weak self] in
                try? await Task.sleep(nanoseconds: delaiEnNanosecondes(delai))
                guard !Task.isCancelled else { return }
                self?.saisieInterlocuteur = false
            }
        }
    }

    private func suivrePresence(_ presences: AsyncStream<EtatPresence>) async {
        for await nouvelle in presences {
            guard await courant() else { return }
            presence = nouvelle
        }
    }

    /// Battement de présence : lancé au premier « rejoint » du canal du fil, arrêté avec le suivi.
    private func demarrerBattement() {
        battement?.cancel()
        let intervalle = delais.battement
        battement = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, await self.battre() else { return }
                try? await Task.sleep(nanoseconds: delaiEnNanosecondes(intervalle))
            }
        }
    }

    /// Faux quand l'identité a changé : le battement s'arrête.
    private func battre() async -> Bool {
        guard let gateways = await controller.gateways(for: contexte.epoch) else { return false }
        let port = gateways.messagerie
        let contexte = self.contexte
        _ = try? await bounded(timeout: controller.resolutionTimeout) { try await port.presence(contexte: contexte) }
        return true
    }

    // MARK: - Envoi

    /// Envoie `texte` (espaces de bord retirés, comme le web). Vrai seulement si le serveur a confirmé l'insertion :
    /// l'écran vide alors le composeur ; sinon le texte saisi est conservé.
    public func envoyer(_ texte: String) async -> Bool {
        let contenu = texte.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !archivee, !envoiEnCours, !contenu.isEmpty else { return false }
        envoiEnCours = true
        defer { envoiEnCours = false }
        refusEnvoi = nil
        antiFuite = nil
        envoiNonConfirme = false
        guard let gateways = await controller.gateways(for: contexte.epoch) else { return false }
        let port = gateways.messagerie
        let contexte = self.contexte
        let id = conversationId
        do {
            let issue = try await bounded(timeout: controller.resolutionTimeout) {
                try await port.envoyer(conversationId: id, contenu: contenu, contexte: contexte)
            }
            guard await courant() else { return false }
            switch issue {
            case let .envoye(messageId):
                await finSaisie()
                await afficherEnvoye(messageId)
                cycle?.listeARelire()
                return true
            case let .antiFuite(type):
                if let type {
                    antiFuite = type
                } else {
                    refusEnvoi = RefusEnvoi(code: CodeEnvoi.antiFuite, message: MessagerieRepli.message)
                }
            case let .refuse(code, texte):
                refusEnvoi = RefusEnvoi(code: code, message: texte)
                if code == CodeEnvoi.conversationArchivee {
                    archivee = true
                    cycle?.listeARelire()
                }
            case .nonConfirme:
                await relireSansRenvoi()
            }
            return false
        } catch {
            guard await courant() else { return false }
            if error is CancellationError { return false }
            if let jolene = error as? JoleneError {
                switch jolene.kind {
                case .cancelled:
                    return false
                case .unauthorized:
                    sessionExpiree = true
                    message = jolene.message
                    return false
                case .contract, .environment, .demoOnly, .invalidCredentials:
                    message = jolene.message // refus avant l'edge : rien n'a été envoyé
                    return false
                case .network, .unknown:
                    break
                }
            }
            // Délai dépassé ou coupure : le serveur a peut-être inséré le message.
            await relireSansRenvoi()
            return false
        }
    }

    public func fermerAntiFuite() { antiFuite = nil }

    public func effacerRefus() { refusEnvoi = nil }

    private func relireSansRenvoi() async {
        envoiNonConfirme = true
        await lireFil(depuis: nil, marquer: .siNouveauxEntrants)
    }

    /// Ligne confirmée relue par id puis fusionnée ; à défaut, le fil entier est relu.
    private func afficherEnvoye(_ messageId: String) async {
        guard let gateways = await controller.gateways(for: contexte.epoch) else { return }
        let port = gateways.messagerie
        let contexte = self.contexte
        let id = conversationId
        let relu = try? await bounded(timeout: controller.resolutionTimeout) {
            try await port.message(id: messageId, conversationId: id, contexte: contexte)
        }
        guard await courant() else { return }
        if let ligne = relu {
            messages = FilMessages.fusionner(messages, [ligne], conversationId: id)
        } else {
            await lireFil(depuis: nil, marquer: .jamais)
        }
    }

    // MARK: - Indicateur de saisie

    /// Saisie en cours (texte modifié, champ focalisé) : signal au plus toutes les `rafraichissementSaisie` secondes,
    /// arrêt automatique après `inactiviteSaisie` secondes sans frappe.
    public func frappe() {
        guard !archivee, !accesRefuse else { return }
        let maintenant = ProcessInfo.processInfo.systemUptime
        if !saisieEnCours || maintenant - dernierSignalSaisie >= delais.rafraichissementSaisie {
            saisieEnCours = true
            dernierSignalSaisie = maintenant
            Task { await self.signalerSaisie(debut: true) }
        }
        inactivite?.cancel()
        let delai = delais.inactiviteSaisie
        inactivite = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delaiEnNanosecondes(delai))
            guard !Task.isCancelled else { return }
            await self?.arreterSaisie()
        }
    }

    /// Fin de saisie (champ quitté ou vidé, message envoyé).
    public func finSaisie() async {
        inactivite?.cancel()
        inactivite = nil
        await arreterSaisie()
    }

    private func arreterSaisie() async {
        guard saisieEnCours else { return }
        saisieEnCours = false
        dernierSignalSaisie = 0
        await signalerSaisie(debut: false)
    }

    /// Indicateur éphémère : un échec (dont `42501 NON_AUTORISE`) l'abandonne sans message.
    private func signalerSaisie(debut: Bool) async {
        guard let gateways = await controller.gateways(for: contexte.epoch) else { return }
        let port = gateways.messagerie
        let contexte = self.contexte
        let id = conversationId
        _ = try? await bounded(timeout: controller.resolutionTimeout) {
            try await port.saisie(debut: debut, conversationId: id, contexte: contexte)
        }
    }

    // MARK: - Interne

    private func courant() async -> Bool { await controller.epoch == contexte.epoch }

    /// Message d'une erreur (`nil` : annulation, rien à montrer) ; session expirée signalée.
    private func texte(_ error: Error) -> String? {
        if let jolene = error as? JoleneError {
            if jolene.kind == .cancelled { return nil }
            if jolene.kind == .unauthorized { sessionExpiree = true }
            return jolene.message
        }
        if error is CancellationError { return nil }
        return MessagerieRepli.message
    }
}
